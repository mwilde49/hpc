# Hyperion Compute — TJP HPC Pipeline Framework

HPC pipeline framework for the TJP group on Juno HPC (UT Dallas). Uses Apptainer containers, SLURM scheduling, and config-driven YAML execution. Deployed to the shared group location at `/groups/tprice/pipelines`.

**Version:** v7.3.1 &nbsp;|&nbsp; **Platform:** Juno HPC &nbsp;|&nbsp; **Branding:** Hyperion Compute

---

## Pipelines

Thirteen pipelines are currently supported across three architecture patterns:

| Pipeline | Type | Description |
|----------|------|-------------|
| **AddOne** | Inline (demo) | Adds 1 to every number in a file. Teaching example for the framework. |
| **BulkRNASeq** | Submoduled (mwilde49/bulkseq @ v1.0.1) | Bulk RNA-seq via STAR aligner, wrapped in an Apptainer container. |
| **Psoma** | Submoduled (mwilde49/psoma @ v2.0.2) | Psomagen bulk RNA-seq via HISAT2 + Trimmomatic, Apptainer container. |
| **Virome** | Submoduled (mwilde49/virome-pipeline @ v1.5.0) | Viral profiling — host depletion, Kraken2, MetaPhlAn3. |
| **SQANTI3** | Submoduled (mwilde49/longreads @ v1.1.0, +6 commits untagged) | Long-read isoform QC — 4-stage SLURM DAG with dynamic resource scaling. |
| **wf-transcriptomes** | Submoduled (mwilde49/longreads @ v1.1.0, +6 commits untagged) | ONT full-length transcript analysis via EPI2ME Nextflow pipeline. |
| **Cell Ranger** | Native 10x (v10.0.0) | Single-cell gene expression (10x Genomics). |
| **Cell Ranger mkfastq** | Native 10x (v10.0.0) | BCL demultiplexing — converts instrument run folders to per-sample FASTQs. |
| **Cell Ranger Multi** | Native 10x (v10.0.0) | Multi-library runs — GEX + VDJ, CITE-seq, CellPlex, Flex, CRISPR. |
| **Space Ranger** | Native 10x (v4.0.1) | Spatial gene expression — Visium (10x Genomics). |
| **Xenium Ranger** | Native 10x (v4.0) | In situ transcriptomics — Xenium (10x Genomics). |
| **DeconvATAC** | Submoduled (mwilde49/dconvatac @ v1.0.0, +4 commits untagged) | Spatial ATAC deconvolution — Cell2Location (CPU). |
| **DeconvATAC GPU** | Submoduled (mwilde49/dconvatac @ v1.0.0, +4 commits untagged) | Spatial ATAC deconvolution — Cell2Location (A30 GPU). |

**Architecture patterns:**
- **Inline** — pipeline code lives directly in this repo (`pipelines/<name>/`)
- **Submoduled** — container and/or pipeline code live in a separate git submodule (`containers/<name>/`)
- **Native** — no container; tool installed from tarball, manages its own execution

---

## Directory Structure

```
hpc/
├── bin/
│   ├── tjp-setup, tjp-launch, tjp-batch, tjp-edit, tjp-validate, tjp-test-suite, labdata
│   ├── hyperion-*, biocruiser-* (symlinks)
│   └── lib/                  # common.sh, validate.sh, manifest.sh, metadata.sh, samplesheet.sh, branding.sh
├── containers/
│   ├── apptainer.def         # AddOne container definition
│   ├── addone_latest.sif
│   ├── bulkrnaseq/           # submodule: mwilde49/bulkseq @ v1.0.1
│   ├── psoma/                # submodule: mwilde49/psoma @ v2.0.2
│   ├── virome/               # submodule: mwilde49/virome-pipeline @ v1.5.0
│   ├── sqanti3/              # submodule: mwilde49/longreads @ v1.1.0, +6 commits untagged (SQANTI3 + wf-transcriptomes)
│   ├── dconvatac/            # submodule: mwilde49/dconvatac @ v1.0.0, +4 commits untagged (spatial ATAC deconvolution)
│   └── 10x/                  # submodule: mwilde49/10x @ v1.2.0, +1 commit untagged (Cell Ranger / Space Ranger / Xenium Ranger wrappers)
├── pipelines/
│   └── addone/               # AddOne pipeline code
├── slurm_templates/          # 13 SLURM job scripts (one per pipeline)
├── templates/                # per-pipeline config templates + samplesheets (13 pipelines)
├── docs/                     # architecture diagrams and design docs
│   ├── architecture.md       # Mermaid diagrams (6 diagrams)
│   └── img/                  # Pre-rendered SVGs
├── metadata/                 # SCHEMA.md (local Titan metadata format)
├── references/               # Shared HPC reference files (gitignored)
├── test_data/                # Smoke test data
└── configs/                  # Legacy example configs
```

---

## Quick Start

### 1. Clone with submodules

```bash
git clone --recurse-submodules https://github.com/mwilde49/hpc.git
```

### 2. One-time workspace setup

Run this once on the HPC to create your personal workspace with template configs:

```bash
/groups/tprice/pipelines/bin/tjp-setup
```

This creates `/work/$USER/pipelines/` with a config template for each pipeline.

### 3. Single pipeline run

Edit the config template for your pipeline, then launch:

```bash
vi /work/$USER/pipelines/psoma/config.yaml
tjp-launch psoma
```

`tjp-launch` creates a timestamped run directory, snapshots the config, submits the SLURM job, and archives inputs/outputs from scratch when complete.

### 4. Batch run from samplesheet

For multi-sample runs, populate a CSV samplesheet and use `tjp-batch`:

```bash
vi /work/$USER/pipelines/cellranger/samplesheet.csv
tjp-batch cellranger samplesheet.csv
```

### 5. Monitor

```bash
squeue -u $USER               # check job queue
labdata find runs             # list all your run records
```

---

## CLI Tools

All tools live in `bin/` and are also available as `hyperion-*` and `biocruiser-*` aliases.

| Tool | Description |
|------|-------------|
| `tjp-setup` | One-time workspace creation — copies config templates to `/work/$USER/pipelines/` |
| `tjp-launch <pipeline>` | Launch a single run from a config YAML; creates timestamped run directory |
| `tjp-batch <pipeline> samplesheet.csv` | Batch launch — one SLURM job per row in the samplesheet |
| `tjp-edit <pipeline>` | Open the pipeline config for a given pipeline in `$EDITOR` (default: nano) |
| `tjp-validate <pipeline>` | Validate config without submitting a job |
| `tjp-test-suite` | Three-layer test harness for all pipelines (layers 1–3, offline to full SLURM) |
| `tjp-test <pipeline>` | (deprecated) Single-pipeline smoke test; superseded by `tjp-test-suite` |
| `tjp-test-validate <pipeline>` | (deprecated) Check smoke test outputs; superseded by `tjp-test-suite` |
| `labdata` | Metadata management — find runs, show PLR-xxxx records, check status |

`tjp-test-suite` is the primary testing path; `tjp-test` and `tjp-test-validate` are kept for backwards compatibility.

---

## Reproducibility (v7.0.0+)

Every run directory now records, beyond the config snapshot and `manifest.json`: which Juno node/partition it ran on and for how long (`juno_environment.json`), the exact resolved command that was executed (`invocation.log`), a frozen copy of the SLURM template and pipeline source as they existed at launch time (`slurm_template_used.sh`, `pipeline_source.tar.gz`), and — for the four Nextflow-based pipelines — Nextflow's own per-process trace/report/timeline (`nextflow_logs/`). See `CLAUDE.md` §"Reproducibility & Provenance Logging" and `USER_GUIDE.md` §17.

**Provenance README (v7.2.0, full rollout v7.3.0):** every pipeline's run directory also gets a full console transcript (`CONSOLE_LOG.txt`), software versions queried live from the container/tool (`software_versions.txt` — coverage depth varies by pipeline architecture, see `CLAUDE.md`), and a single polished `PROVENANCE_README.md` that pulls all of it — status, parameters, software versions, exact commands, and pointers to every other artifact — into one Hyperion-branded report. See `CLAUDE.md` §"Provenance README" and `USER_GUIDE.md` §17.

---

## HPC Path Conventions (Juno)

The repo is deployed to a shared group location. Each user's data stays on their own directories.

| What | Path |
|------|------|
| Shared pipelines repo | `/groups/tprice/pipelines` |
| User workspace | `/work/$USER/pipelines/` |
| User scratch | `/scratch/juno/$USER/` |
| Future Titan storage | `/store/<project>/` (coming ~6 months) |

SLURM templates auto-detect user paths via `$USER`. Apptainer bind mounts require real paths — Juno uses symlinked home directories, so always resolve with `readlink -f` before passing paths to Apptainer.

---

## Adding a New Pipeline

The `KNOWN_PIPELINES` array in `bin/lib/common.sh` is the central registry — add your pipeline name there first.

### Pattern 1: Inline (addone model)

For simple pipelines where code lives in this repo:

1. Create `pipelines/<name>/` with pipeline script and README
2. Add or extend a container definition in `containers/` and rebuild the `.sif`
3. Add `slurm_templates/<name>_slurm_template.sh` (copy addone template, adjust resources)
4. Add `templates/<name>/config.yaml` with `__USER__`/`__SCRATCH__`/`__WORK__` placeholders
5. Register in `KNOWN_PIPELINES` in `bin/lib/common.sh`
6. `.sif` files are not in git — transfer via `scp` to HPC

### Pattern 2: Submoduled (bulkrnaseq/psoma model)

For pipelines with their own container repo:

1. Add the container repo as a submodule: `git submodule add <url> containers/<name>/`
2. Pin to a release tag: `cd containers/<name> && git checkout v1.0.0`
3. Add `slurm_templates/<name>_slurm_template.sh` with pre-flight checks
4. Add `templates/<name>/config.yaml`
5. Register in `KNOWN_PIPELINES` in `bin/lib/common.sh`
6. Create a top-level `<NAME>_HPC_GUIDE.md` documenting setup and usage
7. `.sif` files are not in git — build in the submodule dir, transfer via `scp`

### Pattern 3: Native (cellranger model)

For tools that manage their own execution (no container needed):

1. Add the wrapper repo as a submodule: `git submodule add <url> containers/<name>/`
2. Install the tool from tarball to `/groups/tprice/opt/<name>-<version>/` and symlink from `/groups/tprice/software/<name>`
3. Add `PIPELINE_TOOL_PATHS[<name>]` and `NATIVE_PIPELINES+=(<name>)` in `bin/lib/common.sh`
4. Add `slurm_templates/<name>_slurm_template.sh` with `--exclusive` and calling the wrapper script
5. Add `templates/<name>/config.yaml`
6. Add a validator in `bin/lib/validate.sh`
7. Register in `KNOWN_PIPELINES` in `bin/lib/common.sh`

---

## Documentation

| Guide | Description |
|-------|-------------|
| [MASTER_DOCU.md](MASTER_DOCU.md) | **Documentation map** — index of every guide, what it covers, and what to read first |
| [COMMAND_REFERENCE.md](COMMAND_REFERENCE.md) | **Complete command reference** — every command, flag, config key, and edge case |
| [USER_GUIDE.md](USER_GUIDE.md) | End-user guide for all pipelines |
| [ONBOARDING.md](ONBOARDING.md) | Quick-start for new group members |
| [DEVELOPER_ONBOARDING.md](DEVELOPER_ONBOARDING.md) | Technical reference for developers |
| [PIPELINE_DESIGN_REVIEW.md](PIPELINE_DESIGN_REVIEW.md) | Architecture decisions and design rationale |
| [BULKRNASEQ_HPC_GUIDE.md](BULKRNASEQ_HPC_GUIDE.md) | BulkRNASeq setup and detailed usage guide |
| [HPC_SYSTEM_MAP.md](HPC_SYSTEM_MAP.md) | Cluster specs, filesystem layout, optimization |
| [TJP_HPC_COMPLETE_GUIDE.md](TJP_HPC_COMPLETE_GUIDE.md) | Complete operational guide — architecture, deployment, troubleshooting |
| [CLAUDE.md](CLAUDE.md) | AI assistant instructions and project reference |
| [docs/architecture.md](docs/architecture.md) | Architecture diagrams (Mermaid + pre-rendered SVGs) |
