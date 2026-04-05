# Hyperion Compute — TJP HPC Pipeline Framework

HPC pipeline framework for the TJP group on Juno HPC (UT Dallas). Uses Apptainer containers, SLURM scheduling, and config-driven YAML execution. Deployed to the shared group location at `/groups/tprice/pipelines`.

**Version:** v6.0.0 &nbsp;|&nbsp; **Platform:** Juno HPC &nbsp;|&nbsp; **Branding:** Hyperion Compute

---

## Pipelines

Nine pipelines are currently supported across three architecture patterns:

| Pipeline | Type | Description |
|----------|------|-------------|
| **AddOne** | Inline (demo) | Adds 1 to every number in a file. Teaching example for the framework. |
| **BulkRNASeq** | Submoduled (mwilde49/bulkseq @ v1.0.0) | Bulk RNA-seq via STAR aligner, wrapped in an Apptainer container. |
| **Psoma** | Submoduled (mwilde49/psoma @ v2.0.0) | Psomagen bulk RNA-seq via HISAT2 + Trimmomatic, Apptainer container. |
| **Virome** | Submoduled (mwilde49/virome-pipeline @ v1.4.0) | Viral profiling — host depletion, Kraken2, MetaPhlAn3. |
| **SQANTI3** | Submoduled (mwilde49/longreads) | Long-read isoform QC — 4-stage SLURM DAG with dynamic resource scaling. |
| **wf-transcriptomes** | Submoduled (mwilde49/longreads) | ONT full-length transcript analysis via EPI2ME Nextflow pipeline. |
| **Cell Ranger** | Native 10x (v10.0.0) | Single-cell RNA-seq (10x Genomics). |
| **Space Ranger** | Native 10x (v4.0.1) | Spatial gene expression — Visium (10x Genomics). |
| **Xenium Ranger** | Native 10x (v4.0) | In situ transcriptomics — Xenium (10x Genomics). |

**Architecture patterns:**
- **Inline** — pipeline code lives directly in this repo (`pipelines/<name>/`)
- **Submoduled** — container and/or pipeline code live in a separate git submodule (`containers/<name>/`)
- **Native** — no container; tool installed from tarball, manages its own execution

---

## Directory Structure

```
hpc/
├── bin/
│   ├── tjp-setup, tjp-launch, tjp-batch, tjp-test, tjp-test-validate, tjp-validate, labdata
│   ├── hyperion-*, biocruiser-* (symlinks)
│   └── lib/                  # common.sh, validate.sh, manifest.sh, metadata.sh, samplesheet.sh, branding.sh
├── containers/
│   ├── apptainer.def         # AddOne container definition
│   ├── addone_latest.sif
│   ├── bulkrnaseq/           # submodule: mwilde49/bulkseq @ v1.0.0
│   ├── psoma/                # submodule: mwilde49/psoma @ v2.0.0
│   ├── virome/               # submodule: mwilde49/virome-pipeline @ v1.4.0
│   ├── sqanti3/              # submodule: mwilde49/longreads (SQANTI3 + wf-transcriptomes)
│   └── 10x/                  # submodule: mwilde49/10x @ v1.1.0 (Cell Ranger / Space Ranger / Xenium Ranger wrappers)
├── pipelines/
│   └── addone/               # AddOne pipeline code
├── slurm_templates/          # 9 SLURM job scripts (one per pipeline)
├── templates/                # per-pipeline config templates + samplesheets (9 pipelines)
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
| `tjp-validate <pipeline>` | Validate config without submitting a job |
| `tjp-test <pipeline>` | Submit a smoke test (2 samples, dev partition) |
| `tjp-test-validate <pipeline>` | Check smoke test outputs after completion |
| `labdata` | Metadata management — find runs, show PLR-xxxx records, check status |

Smoke testing is supported for `psoma`, `bulkrnaseq`, `cellranger`, and `spaceranger`.

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
| [USER_GUIDE.md](USER_GUIDE.md) | End-user guide for all pipelines |
| [ONBOARDING.md](ONBOARDING.md) | Quick-start for new group members |
| [DEVELOPER_ONBOARDING.md](DEVELOPER_ONBOARDING.md) | Technical reference for developers |
| [PIPELINE_DESIGN_REVIEW.md](PIPELINE_DESIGN_REVIEW.md) | Architecture decisions and design rationale |
| [BULKRNASEQ_HPC_GUIDE.md](BULKRNASEQ_HPC_GUIDE.md) | BulkRNASeq setup and detailed usage guide |
| [HPC_SYSTEM_MAP.md](HPC_SYSTEM_MAP.md) | Cluster specs, filesystem layout, optimization |
| [TJP_HPC_COMPLETE_GUIDE.md](TJP_HPC_COMPLETE_GUIDE.md) | Complete operational guide — architecture, deployment, troubleshooting |
| [CLAUDE.md](CLAUDE.md) | AI assistant instructions and project reference |
| [docs/architecture.md](docs/architecture.md) | Architecture diagrams (Mermaid + pre-rendered SVGs) |
