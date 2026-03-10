# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HPC pipeline framework for the TJP group on Juno HPC, deployed to the shared group location `/groups/tprice/pipelines`. Uses Apptainer containers + SLURM scheduling + config-driven YAML execution. Has six pipelines: AddOne (inline demo), BulkRNASeq (submoduled container + external Nextflow pipeline), Psoma (submoduled combined container+pipeline repo), and three 10x Genomics native pipelines (Cell Ranger, Space Ranger, Xenium Ranger). Designed to scale horizontally by adding new pipeline directories or container submodules.

## Build and Run Commands

### Build container (local, requires sudo)
```bash
sudo apptainer build containers/addone_latest.sif containers/apptainer.def
```

### Test locally
```bash
apptainer exec containers/addone_latest.sif python pipelines/addone/addone.py --input test_data/numbers.txt --output /tmp/addone_output.txt
```

### Submit on HPC
```bash
cd /groups/tprice/pipelines
mkdir -p logs
sbatch slurm_templates/addone_slurm_template.sh configs/example_config.yaml
```

### Monitor on HPC
```bash
squeue -u $USER
cat logs/addone_*.out
cat logs/addone_*.err
```

## Architecture

Four-layer stack where each layer has a single responsibility:

1. **SLURM** (`slurm_templates/`) — resource allocation and job scheduling
2. **Apptainer** (`containers/`) — reproducible execution environment (.def defines it, .sif is the built binary)
3. **Pipeline** (`pipelines/<name>/`) — domain logic (Python scripts)
4. **Config** (`configs/`) — YAML files parameterizing input/output paths (legacy); `templates/` for user-facing config templates

Supporting layers:

- **`bin/`** — user-facing CLI tools (`tjp-setup`, `tjp-launch`, `tjp-test`, `tjp-test-validate`) with `hyperion-*` and `biocruiser-*` symlink aliases, plus shared libraries (`bin/lib/` including `branding.sh` for Hyperion Compute themed output)
- **`templates/`** — per-pipeline config templates with `__USER__`/`__SCRATCH__`/`__WORK__` placeholders, plus the Nextflow config template (`pipeline.config.tmpl`)

Execution flow: `sbatch template.sh config.yaml` → SLURM allocates node → Apptainer runs container → pipeline executes → writes to scratch → archives inputs/outputs to work run directory.

Pipelines can be **inline** (code in `pipelines/<name>/`, e.g., addone), **submoduled** (container repo in `containers/<name>/` with external pipeline code, e.g., bulkrnaseq), or **native** (no container, tool manages its own execution, e.g., cellranger).

## User Workflow (Recommended)

New users should use the automated tooling instead of manual setup:

```bash
# One-time setup (creates workspace with template configs)
/groups/tprice/pipelines/bin/tjp-setup

# Edit config with your paths
vi /work/$USER/pipelines/addone/config.yaml

# Launch (creates timestamped run, snapshots config, submits job)
tjp-launch addone
```

Each launch creates a timestamped run directory under `/work/$USER/pipelines/<pipeline>/runs/` containing a config snapshot, reproducibility manifest (`manifest.json`), and SLURM logs. After a successful pipeline run, inputs (FASTQs) and outputs are automatically archived from scratch to `inputs/` and `outputs/` subdirectories in the run directory via rsync with checksum verification. See `ONBOARDING.md` for full details.

### Smoke Testing

Verify a pipeline works end-to-end with 2 pre-configured test samples on the dev partition:

```bash
tjp-test psoma              # copies test FASTQs to scratch, generates config, submits to dev
squeue -u $USER             # monitor
tjp-test-validate psoma     # check outputs after completion
```

Supports `psoma`, `bulkrnaseq`, and `cellranger`. Test FASTQs live at `$REPO_ROOT/test_data/rnaseq/fastq/` (RNA-seq, gitignored, generated on HPC) and `$REPO_ROOT/test_data/10x/` (10x pipelines). Use `--clean` to wipe previous test data.

## HPC Path Conventions (Juno-Specific)

The repo lives at a shared group location. Each user's data stays on their own work/scratch directories:

| What | Path |
|------|------|
| Shared pipelines repo | `/groups/tprice/pipelines` |
| User work directory | `/work/$USER` |
| User scratch directory | `/scratch/juno/$USER` |

Juno uses symlinked home directories. Apptainer bind mounts require **real paths** — always resolve with `readlink -f` before passing to Apptainer.

The SLURM templates auto-detect user paths via `$USER` (`PROJECT_ROOT=/groups/tprice/pipelines`, `SCRATCH_ROOT=/scratch/juno/$USER`, `WORK_ROOT=/work/$USER`).

## BulkRNASeq Pipeline

### Submodule

Container repo `mwilde49/bulkseq` is a git submodule at `containers/bulkrnaseq/`, pinned to `v1.0.0`. The actual pipeline code lives in `utdal/Bulk-RNA-Seq-Nextflow-Pipeline`, cloned separately on the HPC to `$PROJECT_ROOT/Bulk-RNA-Seq-Nextflow-Pipeline`.

### Build container (local, requires sudo)
```bash
cd containers/bulkrnaseq && sudo ./build.sh
```

### Test container
```bash
cd containers/bulkrnaseq && ./test_container.sh
```

### Critical runtime flags
- `--cleanenv` — prevents host env vars from leaking into the container
- `--env PYTHONNOUSERSITE=1` — prevents host Python packages from shadowing container packages

### Submit on HPC
```bash
cd /groups/tprice/pipelines
mkdir -p logs
sbatch slurm_templates/bulkrnaseq_slurm_template.sh
```

See `BULKRNASEQ_HPC_GUIDE.md` for full setup and usage details.

## Psoma Pipeline

### Submodule

Container repo `mwilde49/psoma` is a git submodule at `containers/psoma/`, pinned to `v1.0.0`. Unlike bulkrnaseq, psoma is a combined repo — both the pipeline scripts and container definition live in the submodule (no separate clone needed).

### Key differences from BulkRNASeq
- Uses **HISAT2** aligner instead of STAR
- Adds **Trimmomatic** adapter/quality trimming (Nextera adapters)
- `config_directory` points to `$PROJECT_ROOT/containers/psoma` (the submodule itself)
- Psomagen naming convention: `sample_1.fastq.gz` / `sample_2.fastq.gz`
- HISAT2 index is a **prefix path** (e.g., `/path/to/gencode48`, not a directory)
- SLURM template uses `--env HOME=/tmp` so Nextflow can write to `~/.nextflow`

### Build container (local, requires sudo)
```bash
cd containers/psoma/container && sudo ./build.sh
```

### Submit on HPC
```bash
cd /groups/tprice/pipelines
mkdir -p logs
sbatch slurm_templates/psoma_slurm_template.sh
```

### References
- Shared Gencode v48 GTF, filter.bed, blacklist.bed from `/groups/tprice/pipelines/references/`
- HISAT2 index at `/groups/tprice/pipelines/references/hisat2_index/`
- NexteraPE-PE.fa adapter file lives in the psoma submodule (auto-referenced)

## 10x Genomics Pipelines (Cell Ranger, Space Ranger, Xenium Ranger)

### Native Architecture

Unlike BulkRNASeq/Psoma, 10x pipelines are **native** — no Apptainer container, no Nextflow. The tools are installed from tarballs at `/groups/tprice/software/<tool>/` and manage their own threading via `--localcores`/`--localmem`. The SLURM template calls a wrapper script from the `containers/10x/` submodule which invokes the tool directly.

### Submodule

The `mwilde49/10x` repo is a git submodule at `containers/10x/`. It contains:
- `bin/*-run.sh` — wrapper scripts for each tool
- `lib/10x_common.sh` — shared YAML parsing and tool discovery
- `lib/validate_*.sh` — per-tool validation
- `test/test_*.sh` — binary smoke tests

### Key differences from container pipelines
- **No `.sif` file** — tools installed natively from 10x Genomics tarballs
- **No Nextflow** — SLURM template calls wrapper script directly
- **Config passes through** — YAML config goes directly to SLURM (no Nextflow config generation)
- **`--exclusive` SLURM flag** — 10x tools expect full node access
- `is_native_pipeline()` gates all native-specific logic in shared code
- Manifest uses `native:<tool_path>` for `container_file` and tool version for `container_checksum`

### Tool paths
| Tool | Install path | SLURM resources |
|------|-------------|-----------------|
| Cell Ranger | `/groups/tprice/software/cellranger` | 24h, 16 CPU, 128GB, exclusive |
| Space Ranger | `/groups/tprice/software/spaceranger` | 24h, 16 CPU, 128GB, exclusive |
| Xenium Ranger | `/groups/tprice/software/xeniumranger` | 12h, 16 CPU, 128GB, exclusive |

### Config-level tool_path override
Users can set `tool_path` in their config YAML to override the default install location (useful for testing new tool versions).

## Adding a New Pipeline

### Inline pipelines (e.g., addone)

For simple pipelines where code lives directly in this repo:

1. Create `pipelines/<name>/` with pipeline script and README
2. Create or extend container definition in `containers/` if new dependencies needed, then rebuild .sif
3. Add `slurm_templates/<name>_slurm_template.sh` (copy addone template, adjust resources)
4. Add `configs/<name>_example_config.yaml`
5. .sif files are NOT in git — transfer via `scp` to HPC

### Submoduled pipelines (e.g., bulkrnaseq)

For pipelines with their own container repo:

1. Add the container repo as a submodule: `git submodule add <url> containers/<name>/`
2. Pin to a release tag: `cd containers/<name> && git checkout v1.0.0`
3. Add `slurm_templates/<name>_slurm_template.sh` with pre-flight checks
4. If pipeline code lives in a third-party repo, document the clone step in a guide
5. Create a top-level `<NAME>_HPC_GUIDE.md` documenting setup and usage
6. .sif files are NOT in git — build in submodule dir, transfer via `scp` to HPC

### Native pipelines (e.g., cellranger)

For tools that don't need a container:

1. Add the wrapper repo as a submodule: `git submodule add <url> containers/<name>/`
2. Install the tool from tarball to `/groups/tprice/software/<name>/`
3. Add `PIPELINE_TOOL_PATHS[<name>]` and `NATIVE_PIPELINES+=(<name>)` in `bin/lib/common.sh`
4. Add `slurm_templates/<name>_slurm_template.sh` calling the wrapper script
5. Add config template in `templates/<name>/config.yaml`
6. Add validator in `bin/lib/validate.sh`

## Key Constraints

- `.sif` container files are excluded from git (large binaries) — must be transferred separately to HPC
- Pipelines must support `--config <yaml>` for config-driven execution
- Container-based SLURM templates must bind `PROJECT_ROOT`, `SCRATCH_ROOT`, and `WORK_ROOT` into the container
- Native pipeline SLURM templates use `--exclusive` and call wrapper scripts directly
- Outputs go to scratch space, never to the project directory
