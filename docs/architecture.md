---
title: "Hyperion Compute — Architecture Reference"
date: "2026-04-05"
version: "6.0.0"
---

# Hyperion Compute
## Distributed Bioinformatics Execution Framework

**Center for Advanced Pain Studies — UT Dallas**

---

## Introduction

Hyperion Compute is the TJP group's HPC pipeline framework, deployed on the Juno cluster at UT Dallas. It provides a standardized, reproducible execution environment for bioinformatics workflows ranging from bulk RNA-seq and single-cell 10x Genomics assays to long-read isoform characterization and metagenomics. The framework is designed to scale horizontally — new pipelines and users can be onboarded without modifying the core infrastructure.

The system is built on four interlocking layers: **SLURM** schedules compute resources, **Apptainer** (or native tool installs) provides a reproducible execution environment, **pipeline code** (Nextflow or shell-driven) implements domain logic, and **YAML configs** parameterize each run. A command-line interface (`tjp-*`, aliased as `hyperion-*` and `biocruiser-*`) wraps this stack for researchers, while a metadata layer (currently local JSON, converging on Titan PostgreSQL) records every run for reproducibility and auditability.

These diagrams are intended for both **technical HPC users** setting up or debugging pipelines and **management/administrative stakeholders** who need a high-level understanding of data flow, storage, and infrastructure dependencies.

---

## 1. System Architecture Overview

Hyperion Compute is composed of five logical layers, each with a distinct responsibility. Researchers interact exclusively with the **User Interface** layer — the CLI tools and config files — and never need to touch the underlying SLURM or container machinery directly. The **Execution Engine** handles resource allocation and environment isolation. The **Pipeline Layer** hosts all eight bioinformatics workflows, grouped by how their dependencies are packaged. The **Storage Layer** spans three tiers: the shared group repository (read-only for users), ephemeral per-user compute scratch, and persistent per-user work directories. The **Metadata Layer** currently records every pipeline run as a local JSON file (PLR-xxxx format); this will migrate to a centralized PostgreSQL database on the forthcoming Titan storage system.

```mermaid
graph TB
    %% ── User Interface Layer ──────────────────────────────────────────
    subgraph UI["User Interface — Mission Control"]
        direction LR
        cli_setup["tjp-setup\n(hyperion-setup)"]
        cli_launch["tjp-launch\n(hyperion-launch)"]
        cli_batch["tjp-batch\n(hyperion-batch)"]
        cli_test["tjp-test\n(hyperion-test)"]
        cli_labdata["labdata\n(Titan CLI)"]
    end

    %% ── Execution Engine ──────────────────────────────────────────────
    subgraph EE["Execution Engine — Warp Drive"]
        direction LR
        slurm["SLURM\nJob Scheduler"]
        apptainer["Apptainer\nContainer Runtime"]
        native["Native Tool\nInstall (no container)"]
    end

    %% ── Pipeline Layer ────────────────────────────────────────────────
    subgraph PL["Pipeline Layer — Data Relays"]
        direction TB
        subgraph inline_grp["Inline"]
            p_addone["addone\n(demo)"]
        end
        subgraph sub_grp["Submoduled"]
            p_bulk["bulkrnaseq\nSTAR / DESeq2"]
            p_psoma["psoma\nHISAT2 / Trimmomatic"]
            p_virome["virome\nKraken2 / MetaPhlAn3"]
            p_sqanti["sqanti3\nLong-read isoform QC"]
            p_wftx["wf-transcriptomes\nONT / EPI2ME"]
        end
        subgraph native_grp["Native"]
            p_cr["cellranger\n10x scRNA-seq"]
            p_sr["spaceranger\n10x Spatial"]
            p_xr["xeniumranger\n10x In Situ"]
        end
    end

    %% ── Storage Layer ─────────────────────────────────────────────────
    subgraph SL["Storage Layer"]
        direction LR
        store_repo["/groups/tprice/pipelines\nShared Group Repo"]
        store_work["/work/USER/pipelines/\nPersistent Work Dir"]
        store_scratch["/scratch/juno/USER/\nEphemeral Compute Scratch"]
        store_titan["/store/ (future)\nTitan NFS"]
    end

    %% ── Metadata Layer ────────────────────────────────────────────────
    subgraph ML["Metadata Layer — Titan Integration"]
        direction LR
        meta_json["Local JSON\nPLR-xxxx.json"]
        meta_db["Titan PostgreSQL\n(future)"]
    end

    %% ── Connections ───────────────────────────────────────────────────
    UI --> EE
    EE --> PL
    EE --> SL
    PL --> SL
    SL --> ML
    cli_labdata --> meta_json
    cli_labdata -.->|"future"| meta_db
    store_work -.->|"archive"| store_titan

    %% ── Styling ───────────────────────────────────────────────────────
    classDef userTool fill:#1565C0,color:#fff,stroke:#0D47A1,stroke-width:2px
    classDef compute fill:#E65100,color:#fff,stroke:#BF360C,stroke-width:2px
    classDef storage fill:#2E7D32,color:#fff,stroke:#1B5E20,stroke-width:2px
    classDef titan fill:#6A1B9A,color:#fff,stroke:#4A148C,stroke-width:2px
    classDef pipeline fill:#00695C,color:#fff,stroke:#004D40,stroke-width:2px

    class cli_setup,cli_launch,cli_batch,cli_test,cli_labdata userTool
    class slurm,apptainer,native compute
    class store_repo,store_work,store_scratch storage
    class store_titan,meta_json,meta_db titan
    class p_addone,p_bulk,p_psoma,p_virome,p_sqanti,p_wftx,p_cr,p_sr,p_xr pipeline
```

---

## 2. Execution Flow (Single Pipeline Run)

This sequence diagram traces the full lifecycle of a single pipeline run from the moment a researcher invokes `tjp-launch` to the point where a permanent record is written to the metadata store. The flow illustrates how responsibility is handed off between the user-facing CLI, SLURM's job scheduler, the container or native tool runtime, the pipeline logic itself, and finally the stage-out and metadata subsystems. Each step is decoupled: if SLURM is busy, the job queues without blocking the researcher; if stage-out fails, the raw compute outputs on scratch remain intact for manual recovery.

```mermaid
sequenceDiagram
    participant User as User
    participant Launch as tjp-launch
    participant SLURM as SLURM Scheduler
    participant Runtime as Apptainer / Native Tool
    participant Pipeline as Pipeline Code
    participant StageOut as Stage-Out (rsync)
    participant Metadata as labdata / JSON

    User->>+Launch: tjp-launch psoma

    Note over Launch: Reads config.yaml +<br/>optional samplesheet.csv

    Launch->>Launch: Create timestamped run dir<br/>/work/USER/pipelines/psoma/runs/<timestamp>/
    Launch->>Launch: Snapshot config → manifest.json
    Launch->>+SLURM: sbatch psoma_slurm_template.sh config.yaml

    Note over SLURM: Allocates node on<br/>normal partition (20 CPU / 64 GB)

    SLURM->>+Runtime: Start Apptainer container<br/>(psoma_latest.sif)
    Runtime->>+Pipeline: nextflow run psoma.nf --config config.yaml

    Note over Pipeline: HISAT2 alignment<br/>Trimmomatic QC<br/>StringTie counts<br/>HTSeq raw counts

    Pipeline-->>-Runtime: Pipeline complete<br/>outputs in /scratch/juno/USER/...
    Runtime-->>-SLURM: Exit 0
    SLURM-->>-Launch: Job finished (SLURM callback)

    Launch->>+StageOut: rsync scratch → work/runs/<timestamp>/outputs/
    StageOut->>StageOut: Checksum verify (md5sum)
    StageOut->>StageOut: rsync inputs → work/runs/<timestamp>/inputs/
    StageOut-->>-Launch: Archive complete

    Launch->>+Metadata: labdata register-run
    Metadata->>Metadata: Write PLR-xxxx.json<br/>(titan_registered: false)
    Metadata-->>-Launch: PLR-0042 recorded

    Launch-->>-User: Mission Complete ✓<br/>Run ID: PLR-0042
```

---

## 3. Pipeline Taxonomy

Hyperion Compute hosts eight bioinformatics pipelines organized into three architectural families. **Inline** pipelines bundle their code directly in the shared repository and are suitable for simple tasks or framework testing. **Submoduled** pipelines reference external container repositories (git submodules), each encapsulating a container definition and pipeline scripts; this keeps the main repo lean while enabling independent versioning of each pipeline's dependencies. **Native** pipelines require no container at all — the 10x Genomics tools are installed from vendor tarballs and manage their own parallelism. All three families share the same CLI interface (`tjp-launch`, `tjp-batch`) and produce the same run-directory and manifest structure.

```mermaid
graph LR
    %% Root
    HC(["Hyperion Compute\nPipelines"])

    %% Branches
    B_inline["Inline\n(code in main repo)"]
    B_sub["Submoduled\n(git submodule container)"]
    B_native["Native\n(vendor tarball install)"]

    HC --> B_inline
    HC --> B_sub
    HC --> B_native

    %% Inline leaf
    P_addone["addone\nPython script\n— demo / testing"]

    %% Submoduled leaves
    P_bulk["bulkrnaseq\nNextflow + STAR\nDESeq2 / HTSeq"]
    P_psoma["psoma\nNextflow + HISAT2\nTrimmomatic / StringTie"]
    P_virome["virome\nNextflow + Kraken2\nMetaPhlAn3"]
    P_sqanti["sqanti3\n4-stage SLURM DAG\nSQANTI3 v5.5.4"]
    P_wftx["wf-transcriptomes\nNextflow (EPI2ME)\nONT long-read"]

    %% Native leaves
    P_cr["cellranger\n10x binary\nscRNA-seq (v10.0.0)"]
    P_sr["spaceranger\n10x binary\nSpatial (v4.0.1)"]
    P_xr["xeniumranger\n10x binary\nIn Situ (v4.0)"]

    B_inline --> P_addone
    B_sub --> P_bulk
    B_sub --> P_psoma
    B_sub --> P_virome
    B_sub --> P_sqanti
    B_sub --> P_wftx
    B_native --> P_cr
    B_native --> P_sr
    B_native --> P_xr

    %% Styling
    classDef branch fill:#37474F,color:#fff,stroke:#263238,stroke-width:2px
    classDef inlinePipe fill:#1565C0,color:#fff,stroke:#0D47A1,stroke-width:1px
    classDef subPipe fill:#00695C,color:#fff,stroke:#004D40,stroke-width:1px
    classDef nativePipe fill:#E65100,color:#fff,stroke:#BF360C,stroke-width:1px
    classDef root fill:#6A1B9A,color:#fff,stroke:#4A148C,stroke-width:2px

    class HC root
    class B_inline,B_sub,B_native branch
    class P_addone inlinePipe
    class P_bulk,P_psoma,P_virome,P_sqanti,P_wftx subPipe
    class P_cr,P_sr,P_xr nativePipe
```

---

## 4. Filesystem Layout

Hyperion Compute uses a three-tier filesystem model on the Juno HPC cluster. The **shared group repository** (`/groups/tprice/pipelines`) is maintained by the TJP group and is read-only for most users; it contains the CLI tools, SLURM templates, container definitions, and config templates. Each user has a **persistent work directory** (`/work/$USER/pipelines/`) where run records, config snapshots, and archived outputs live permanently. **Ephemeral compute scratch** (`/scratch/juno/$USER/`) holds live pipeline outputs during a job and is not backed up — data is automatically archived to the work directory at job completion via rsync. A fourth tier, `/store/` on the future Titan NFS filesystem, will eventually replace per-user work directories as the permanent data home.

```mermaid
graph TB
    %% ── Shared Group Repo ─────────────────────────────────────────────
    subgraph GRP["/groups/tprice/pipelines — Shared Group Repo"]
        direction TB
        g_bin["bin/\ntjp-* / hyperion-* / biocruiser-*\nlib/ (common.sh, branding.sh, validate.sh)"]
        g_tmpl["templates/\nper-pipeline config templates\n__USER__ / __SCRATCH__ / __WORK__ placeholders"]
        g_slurm["slurm_templates/\n*_slurm_template.sh\none per pipeline"]
        g_cont["containers/\nbulkrnaseq/ psoma/ sqanti3/\n10x/ (submodules)\n*.sif built binaries"]
        g_refs["references/\ngencode48 GTF\nhisat2_index/\nblacklist.bed / filter.bed"]
        g_meta["metadata/\nschema/\n(local JSON store)"]
    end

    %% ── User Work Dir ─────────────────────────────────────────────────
    subgraph WORK["/work/USER/pipelines — Persistent Work"]
        direction TB
        w_pipe["&lt;pipeline&gt;/\nconfig.yaml (user-edited)"]
        w_runs["runs/\n&lt;YYYYMMDD_HHMMSS&gt;/\n  config_snapshot.yaml\n  manifest.json\n  inputs/ (archived FASTQs)\n  outputs/ (archived results)\n  logs/ (SLURM .out/.err)"]
        w_meta["metadata/\npipeline_runs/\n  PLR-xxxx.json"]
        w_pipe --> w_runs
    end

    %% ── Compute Scratch ───────────────────────────────────────────────
    subgraph SCR["/scratch/juno/USER — Ephemeral Compute Scratch"]
        direction TB
        s_runs["pipelines/&lt;pipeline&gt;/runs/&lt;timestamp&gt;/\n  (live pipeline outputs during job)"]
        s_warn["⚠ Not backed up\nRsync'd to /work after job completes"]
    end

    %% ── Future Titan ──────────────────────────────────────────────────
    subgraph TITAN["/store — Titan NFS (future ~6 months)"]
        direction TB
        t_proj["projects/\nPRJ-xxxx/"]
        t_arch["archive/\nlong-term output storage"]
        t_db["PostgreSQL DB\nPLR / SMP / LIB / RUN records"]
    end

    %% ── Flow ──────────────────────────────────────────────────────────
    GRP -->|"sbatch template"| SCR
    SCR -->|"stage-out rsync\n+ checksum verify"| WORK
    WORK -.->|"future archive"| TITAN

    %% ── Styling ───────────────────────────────────────────────────────
    classDef storage fill:#2E7D32,color:#fff,stroke:#1B5E20,stroke-width:2px
    classDef compute fill:#E65100,color:#fff,stroke:#BF360C,stroke-width:2px
    classDef titan fill:#6A1B9A,color:#fff,stroke:#4A148C,stroke-width:2px
    classDef node_default fill:#37474F,color:#fff,stroke:#263238,stroke-width:1px

    class g_bin,g_tmpl,g_slurm,g_cont,g_refs,g_meta storage
    class s_runs,s_warn compute
    class t_proj,t_arch,t_db titan
    class w_pipe,w_runs,w_meta node_default
```

---

## 5. Titan Integration Roadmap

Titan is the TJP group's forthcoming centralized research data management system, expected to come online approximately six months from the time of writing. Hyperion Compute is designed so that the researcher-facing interface (`labdata`, config YAML fields, run IDs) remains **identical** across both phases — only the backend storage changes. In Phase 1 (current), each pipeline run generates a local JSON file named with a PLR-xxxx identifier, and the `titan_registered` flag is set to `false`. In Phase 2, the same `labdata register-run` command will instead perform a network INSERT into a PostgreSQL database, set `titan_registered: true`, and link the run record to project, sample, library, and run IDs stored in the DB. No changes to SLURM templates, pipeline code, or user configs are required for this transition.

```mermaid
graph LR
    %% ── Shared Interface (stable across both phases) ──────────────────
    subgraph IFACE["Stable Interface (both phases)"]
        direction TB
        cfg["YAML Config Fields\ntitan_project_id\ntitan_sample_id\ntitan_library_id\ntitan_run_id"]
        csv["Samplesheet Columns\nproject_id / sample_id\nlibrary_id / run_id"]
        ids["ID Scheme\nPRJ-xxxx SMP-xxxx\nLIB-xxxx RUN-xxxx PLR-xxxx"]
        labdata_cli["labdata CLI\nregister-run\nlist-runs / get-run"]
    end

    %% ── Phase 1 ───────────────────────────────────────────────────────
    subgraph P1["Phase 1 — Current (v6.0.0)"]
        direction TB
        p1_store["/work/USER/pipelines/metadata/\npipeline_runs/PLR-xxxx.json"]
        p1_flag["titan_registered: false"]
        p1_note["Local filesystem only\nNo network dependency"]
    end

    %% ── Phase 2 ───────────────────────────────────────────────────────
    subgraph P2["Phase 2 — Titan Online (future)"]
        direction TB
        p2_store["PostgreSQL Database\nTitan server"]
        p2_nfs["/store/ NFS\nLong-term data archive"]
        p2_flag["titan_registered: true"]
        p2_note["DB INSERT on register\nFull audit trail"]
    end

    %% ── Flow ──────────────────────────────────────────────────────────
    IFACE -->|"writes to"| P1
    IFACE -.->|"will write to\n(same CLI call)"| P2
    P1 -.->|"migration path\n(one-time import)"| P2

    %% ── Styling ───────────────────────────────────────────────────────
    classDef userTool fill:#1565C0,color:#fff,stroke:#0D47A1,stroke-width:2px
    classDef current fill:#2E7D32,color:#fff,stroke:#1B5E20,stroke-width:2px
    classDef future fill:#6A1B9A,color:#fff,stroke:#4A148C,stroke-width:2px

    class cfg,csv,ids,labdata_cli userTool
    class p1_store,p1_flag,p1_note current
    class p2_store,p2_nfs,p2_flag,p2_note future
```

---

## 6. Batch Execution Flow

The `tjp-batch` command enables researchers to process entire cohorts from a single CSV samplesheet, rather than launching individual pipeline runs manually. The framework supports two distinct batching modes determined by the pipeline type. **Per-row** pipelines (cellranger, spaceranger, xeniumranger, sqanti3, wf-transcriptomes) spawn one independent SLURM job per CSV row, allowing each sample to run in parallel on separate compute nodes. **Per-sheet** pipelines (bulkrnaseq, psoma, virome) submit a single SLURM job that reads all rows internally; these pipelines are designed to handle multi-sample cohorts natively through Nextflow's process-level parallelism. Both modes produce the same per-run directory structure and PLR-xxxx metadata records, and both respect the same config YAML fields and Titan ID columns.

```mermaid
graph TD
    %% ── Input ─────────────────────────────────────────────────────────
    SS["samplesheet.csv\nproject_id / sample_id / library_id\nrun_id / fastq_dir / ..."]
    CMD["tjp-batch &lt;pipeline&gt; samplesheet.csv"]

    SS --> CMD

    %% ── Dispatch ──────────────────────────────────────────────────────
    CMD --> PARSE["Parse samplesheet\n+ validate columns"]
    PARSE --> DECIDE{"Batching mode?"}

    %% ── Per-Row branch ────────────────────────────────────────────────
    DECIDE -->|"per-row"| ROW_NOTE["One SLURM job\nper CSV row"]

    ROW_NOTE --> ROW_PIPES["Pipelines:\ncellranger\nspaceranger\nxeniumranger\nsqanti3\nwf-transcriptomes"]

    ROW_PIPES --> JOB1["SLURM Job — row 1\nSMP-0001"]
    ROW_PIPES --> JOB2["SLURM Job — row 2\nSMP-0002"]
    ROW_PIPES --> JOBN["SLURM Job — row N\nSMP-000N"]

    JOB1 --> OUT1["run dir + PLR-xxxx\noutputs archived"]
    JOB2 --> OUT2["run dir + PLR-xxxx\noutputs archived"]
    JOBN --> OUTN["run dir + PLR-xxxx\noutputs archived"]

    %% ── Per-Sheet branch ──────────────────────────────────────────────
    DECIDE -->|"per-sheet"| SHEET_NOTE["One SLURM job\nfor entire sheet"]

    SHEET_NOTE --> SHEET_PIPES["Pipelines:\nbulkrnaseq\npsoma\nvirome"]

    SHEET_PIPES --> JOB_ALL["Single SLURM Job\nall samples in CSV"]
    JOB_ALL --> NF_PARALLEL["Nextflow internal\nparallel processes\n(one channel per sample)"]
    NF_PARALLEL --> OUT_ALL["run dir + PLR-xxxx\ncombined outputs archived"]

    %% ── Styling ───────────────────────────────────────────────────────
    classDef userTool fill:#1565C0,color:#fff,stroke:#0D47A1,stroke-width:2px
    classDef compute fill:#E65100,color:#fff,stroke:#BF360C,stroke-width:2px
    classDef pipeline fill:#00695C,color:#fff,stroke:#004D40,stroke-width:2px
    classDef storage fill:#2E7D32,color:#fff,stroke:#1B5E20,stroke-width:2px
    classDef decision fill:#F57F17,color:#000,stroke:#E65100,stroke-width:2px

    class SS,CMD,PARSE userTool
    class DECIDE decision
    class ROW_NOTE,SHEET_NOTE,ROW_PIPES,SHEET_PIPES compute
    class JOB1,JOB2,JOBN,JOB_ALL,NF_PARALLEL pipeline
    class OUT1,OUT2,OUTN,OUT_ALL storage
```

---

## Rendering

These diagrams use [Mermaid](https://mermaid.js.org/) v10+ syntax and can be rendered in several ways:

**GitHub / GitLab**
Push this file to a GitHub or GitLab repository. Both platforms natively render Mermaid blocks in Markdown previews with no extensions required.

**VS Code**
Install the [Mermaid Preview](https://marketplace.visualstudio.com/items?itemName=bierner.markdown-mermaid) or [Markdown Preview Mermaid Support](https://marketplace.visualstudio.com/items?itemName=bierner.markdown-mermaid) extension. Open the file and use `Ctrl+Shift+V` (or `Cmd+Shift+V` on macOS) to preview.

**Mermaid CLI (`mmdc`)**
```bash
npm install -g @mermaid-js/mermaid-cli

# Render all diagrams to PNG
mmdc -i docs/architecture.md -o docs/architecture.png

# Render to SVG (vector, scalable for presentations)
mmdc -i docs/architecture.md -o docs/architecture.svg --outputFormat svg
```

**Mermaid Live Editor**
Paste any individual diagram block (the content between the triple backticks) into [https://mermaid.live](https://mermaid.live) for interactive editing and PNG/SVG export.

---

*Hyperion Compute — Center for Advanced Pain Studies, UT Dallas*
*Generated: 2026-04-05 | Framework version: 6.0.0*
