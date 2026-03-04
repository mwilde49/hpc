# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HPC pipeline framework for the TJP group on Juno HPC, deployed to the shared group location `/groups/tprice/pipelines`. Uses Apptainer containers + SLURM scheduling + config-driven YAML execution. Has two pipelines: AddOne (inline demo) and BulkRNASeq (submoduled container + external Nextflow pipeline). Designed to scale horizontally by adding new pipeline directories or container submodules.

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
4. **Config** (`configs/`) — YAML files parameterizing input/output paths

Execution flow: `sbatch template.sh config.yaml` → SLURM allocates node → Apptainer runs container → pipeline executes → writes to scratch.

Pipelines can be **inline** (code in `pipelines/<name>/`, e.g., addone) or **submoduled** (container repo in `containers/<name>/` with external pipeline code, e.g., bulkrnaseq).

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

## Key Constraints

- `.sif` container files are excluded from git (large binaries) — must be transferred separately to HPC
- Pipelines must support `--config <yaml>` for config-driven execution
- SLURM templates must bind `PROJECT_ROOT`, `SCRATCH_ROOT`, and `WORK_ROOT` into the container
- Outputs go to scratch space, never to the project directory
