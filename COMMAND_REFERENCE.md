# Hyperion Compute — Command Reference

**Version:** 6.0.0 | **Cluster:** Juno HPC, UT Dallas | **Updated:** 2026-04-05

Comprehensive reference for every command available in the Hyperion Compute / TJP pipeline framework. Organized from general cluster commands inward to per-pipeline specifics. Use `Ctrl+F` / `grep` to jump to any command, flag, or config key.

---

## Table of Contents

1. [Juno HPC — General](#1-juno-hpc--general)
2. [SLURM — Job Scheduling](#2-slurm--job-scheduling)
3. [Apptainer — Containers](#3-apptainer--containers)
4. [Git & Submodules](#4-git--submodules)
5. [HPC Framework — Setup & Launch](#5-hpc-framework--setup--launch)
   - [tjp-setup](#51-tjp-setup)
   - [tjp-launch](#52-tjp-launch)
   - [tjp-batch](#53-tjp-batch)
   - [tjp-test](#54-tjp-test)
   - [tjp-test-validate](#55-tjp-test-validate)
   - [labdata](#56-labdata)
6. [Pipeline Reference](#6-pipeline-reference)
   - [AddOne](#61-addone)
   - [BulkRNASeq](#62-bulkrnaseq)
   - [Psoma](#63-psoma)
   - [Virome](#64-virome)
   - [SQANTI3](#65-sqanti3)
   - [wf-transcriptomes](#66-wf-transcriptomes)
   - [Cell Ranger](#67-cell-ranger)
   - [Space Ranger](#68-space-ranger)
   - [Xenium Ranger](#69-xenium-ranger)
7. [Config Key Reference](#7-config-key-reference)
8. [Path & Environment Reference](#8-path--environment-reference)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Juno HPC — General

### Connecting

```bash
ssh YOUR_NETID@juno.hpcre.utdallas.edu
```

> **Note:** Juno uses symlinked home directories. Always resolve real paths with `readlink -f ~/work` before passing to Apptainer bind mounts.

### Modules

```bash
module avail                    # list available modules
module load apptainer           # load Apptainer (required before running containers)
module load nextflow            # load Nextflow (if not on PATH)
module list                     # show currently loaded modules
module purge                    # unload all modules
```

> Pipelines call `module load apptainer` inside SLURM templates. You do **not** need to load it manually if using `tjp-launch`.

### File Transfer

```bash
# Upload FASTQs to scratch (use scratch — it's fast; never write outputs to groups/)
scp -r /local/fastq/ YOUR_NETID@juno.hpcre.utdallas.edu:/scratch/juno/YOUR_NETID/project/fastq/
rsync -avP /local/fastq/ YOUR_NETID@juno.hpcre.utdallas.edu:/scratch/juno/YOUR_NETID/project/fastq/

# Upload a config file to work
scp config.yaml YOUR_NETID@juno.hpcre.utdallas.edu:/work/YOUR_NETID/pipelines/bulkrnaseq/config.yaml

# Download results from work
scp -r YOUR_NETID@juno.hpcre.utdallas.edu:/work/YOUR_NETID/pipelines/psoma/runs/2026-03-04_14-30-00/outputs/ ./local_results/
rsync -avP YOUR_NETID@juno.hpcre.utdallas.edu:/work/YOUR_NETID/pipelines/psoma/runs/ ./archive/
```

### Storage Tiers

| Mount | Path | Speed | Persistence | Use for |
|-------|------|-------|-------------|---------|
| home | `/home/$USER` | Slow | Permanent | `.bashrc`, login config |
| work | `/work/$USER` | Medium | Permanent | Configs, run logs, archived outputs |
| scratch | `/scratch/juno/$USER` | **Fast** | **Purged periodically** | FASTQ input, pipeline outputs, intermediates |
| groups | `/groups/tprice/pipelines` | Slow | Permanent | Shared code, containers, references |

> **Warning:** Scratch is purged periodically. Outputs are automatically archived to `/work/$USER/pipelines/<pipeline>/runs/<timestamp>/outputs/` by `tjp-launch`.

### Interactive Compute Nodes

```bash
# Get an interactive compute node (always required for memory-intensive prep work)
srun --account=tprice --partition=normal --cpus-per-task=2 --mem=4G --time=4:00:00 --pty bash

# For STAR index generation (needs more resources)
srun --time=02:00:00 --mem=40G --cpus-per-task=20 --pty bash
```

> **Critical:** Never run pipeline code on login nodes. Long jobs on login nodes may be killed and may affect other users.

### Cluster Partitions

| Partition | Nodes | Cores | RAM | Time limit | Use for |
|-----------|-------|-------|-----|------------|---------|
| **normal** (default) | 75 | 64 | 384 GB | 2 days | All production pipelines |
| **dev** | 8 | 64 | 384 GB | 2 hours | Smoke tests (`--dev` flag) |
| **a30** | 2 | 128 | 1 TB | 2 days | GPU workloads |
| **h100** | 3 | 64 | 512 GB | 2 days | Heavy AI/ML |
| **vdi** | 2 | 128 | 384 GB | 8 hours | Interactive/desktop |

### PATH Setup

```bash
# If tjp-* commands are not found, add to PATH manually
export PATH="/groups/tprice/pipelines/bin:$PATH"

# Or run setup once to add permanently to ~/.bashrc
/groups/tprice/pipelines/bin/tjp-setup
```

> `tjp-setup` appends the PATH line to `~/.bashrc` automatically on first run.

---

## 2. SLURM — Job Scheduling

### Submitting Jobs

```bash
# Direct SLURM submission (low-level; prefer tjp-launch)
sbatch slurm_templates/bulkrnaseq_slurm_template.sh <config.yaml>
sbatch slurm_templates/psoma_slurm_template.sh      <config.yaml>
sbatch slurm_templates/virome_slurm_template.sh     <config.yaml>
sbatch slurm_templates/cellranger_slurm_template.sh <config.yaml>

# Override partition at submission time
sbatch --partition=dev --time=02:00:00 slurm_templates/psoma_slurm_template.sh <config.yaml>

# Override memory/CPUs at submission time
sbatch --mem=256G --cpus-per-task=40 slurm_templates/bulkrnaseq_slurm_template.sh <config.yaml>
```

### Monitoring Jobs

```bash
squeue -u $USER                     # show your running/pending jobs
squeue -u $USER --format="%i %j %T %M %l %R"  # more verbose: jobid, name, state, runtime, timelimit, reason
squeue --partition=dev -u $USER     # show jobs on dev partition only

# Watch job queue live (refreshes every 5 seconds)
watch -n 5 squeue -u $USER
```

### Log Files

```bash
# Framework-managed logs (via tjp-launch) — in run directory
tail -f /work/$USER/pipelines/<pipeline>/runs/<timestamp>/slurm_<JOBID>.out
cat  /work/$USER/pipelines/<pipeline>/runs/<timestamp>/slurm_<JOBID>.err

# Direct-sbatch logs (legacy) — in /groups/tprice/pipelines/logs/
tail -f /groups/tprice/pipelines/logs/bulkrnaseq_<JOBID>.out
cat  /groups/tprice/pipelines/logs/bulkrnaseq_<JOBID>.err
```

### Cancelling Jobs

```bash
scancel <JOBID>                     # cancel a specific job
scancel -u $USER                    # cancel ALL your jobs
scancel -u $USER --name=psoma       # cancel all jobs named "psoma"
```

### Job History & Efficiency

```bash
sacct -u $USER --format=JobID,JobName,State,Elapsed,CPUTime,MaxRSS,Start,End
sacct -j <JOBID> --format=JobID,State,MaxRSS,CPUTime,Elapsed

# Cluster node availability
sinfo
sinfo -p normal                     # normal partition only
sinfo -p dev                        # dev partition only
```

### SLURM Directives Used by This Framework

Each pipeline template sets these `#SBATCH` directives:

| Pipeline | `--time` | `--cpus-per-task` | `--mem` | `--exclusive` |
|----------|----------|-------------------|---------|---------------|
| addone | 00:05:00 | 1 | 1G | — |
| bulkrnaseq | 12:00:00 | 40 | 128G | — |
| psoma | 12:00:00 | 40 | 128G | — |
| virome | 12:00:00 | 16 | 128G | — |
| sqanti3 (orchestrator) | 00:30:00 | 1 | 4G | — |
| wf-transcriptomes | 48:00:00 | 2 | 8G | — |
| cellranger | 24:00:00 | 16 | 128G | ✓ |
| spaceranger | 24:00:00 | 16 | 128G | ✓ |
| xeniumranger | 12:00:00 | 16 | 128G | ✓ |

> `--exclusive` on 10x pipelines means the job gets an entire node; 10x tools expect full node access and handle their own threading via `--localcores`.

> **Sizing guidance:** BulkRNASeq/Psoma 10–20 human samples: 12h/128G/40 CPUs. For 50+ samples, increase to `--time=24:00:00`.

---

## 3. Apptainer — Containers

### Basic Execution

```bash
# Execute a command inside a container
apptainer exec containers/addone_latest.sif python3 pipelines/addone/addone.py \
    --input test_data/numbers.txt --output /tmp/out.txt

# Shell into a container interactively
apptainer shell containers/bulkrnaseq/bulkrnaseq_v1.0.0.sif

# With cleanenv (prevents host env leaking in — required for RNA-seq pipelines)
apptainer exec --cleanenv containers/bulkrnaseq/bulkrnaseq_v1.0.0.sif <command>
```

### Bind Mounts (required for pipelines)

```bash
# Standard three-way bind used by all pipeline SLURM templates
apptainer exec \
    --cleanenv \
    --env PYTHONNOUSERSITE=1 \
    --bind /groups/tprice/pipelines:/groups/tprice/pipelines \
    --bind /scratch/juno/$USER:/scratch/juno/$USER \
    --bind /work/$USER:/work/$USER \
    containers/psoma/psomagen_v1.0.0.sif \
    <command>
```

> Bind mounts require **real paths** — Juno's symlinked home dirs will break. Always resolve with `readlink -f`.

### Building Containers

```bash
# Build from .def file (local, requires sudo)
sudo apptainer build containers/addone_latest.sif containers/apptainer.def
sudo apptainer build containers/bulkrnaseq/bulkrnaseq_v1.0.0.sif containers/bulkrnaseq/bulkrnaseq.def

# Build with fakeroot (on HPC, no sudo)
apptainer build --fakeroot containers/psoma/psomagen_v1.0.0.sif containers/psoma/container/psomagen.def
apptainer build --fakeroot --force containers/virome/python.sif containers/virome/containers/python.def

# Pull from Docker Hub (used for SQANTI3)
apptainer pull containers/sqanti3/sqanti3_v5.5.4.sif docker://anaconesalab/sqanti3:v5.5.4
```

### Transferring .sif Files

```bash
# .sif files are not in git — build locally then scp to HPC
scp containers/bulkrnaseq/bulkrnaseq_v1.0.0.sif \
    YOUR_NETID@juno.hpcre.utdallas.edu:/groups/tprice/pipelines/containers/bulkrnaseq/

scp containers/psoma/psomagen_v1.0.0.sif \
    YOUR_NETID@juno.hpcre.utdallas.edu:/groups/tprice/pipelines/containers/psoma/

# Virome: sync per-process .sif directory
rsync -avP containers/virome/containers/*.sif \
    YOUR_NETID@juno.hpcre.utdallas.edu:/groups/tprice/pipelines/containers/virome/containers/
```

### Environment Variables Used in Containers

| Variable | Value | Purpose |
|----------|-------|---------|
| `PYTHONNOUSERSITE=1` | `1` | Prevents host Python packages shadowing container packages |
| `HOME=/tmp` | `/tmp` | Lets Nextflow write `~/.nextflow` inside the container (psoma) |
| `_JAVA_OPTIONS=-Xmx16g` | `-Xmx16g` | Limits Trimmomatic JVM heap (psoma with 20+ threads) |

---

## 4. Git & Submodules

### Cloning the Framework

```bash
# Full clone with all submodules
git clone --recurse-submodules https://github.com/mwilde49/hpc.git /groups/tprice/pipelines

# After a regular clone, initialize submodules
git submodule update --init --recursive
```

### Updating the Deployed Repo

```bash
cd /groups/tprice/pipelines

# Pull latest commits and update all submodules to pinned commits
git pull
git submodule update --init --recursive

# Check submodule states (+ = ahead of pin, - = not initialized)
git submodule status
```

### Working with Submodules

```bash
# Update a single submodule to its latest commit
cd containers/virome
git fetch && git checkout main && git pull

# Return to parent repo and commit the pointer update
cd /groups/tprice/pipelines
git add containers/virome
git commit -m "Update virome submodule to v1.5.0"

# Pin a submodule to a specific tag
cd containers/psoma
git checkout v2.0.0
cd ..
git add containers/psoma
git commit -m "Pin psoma to v2.0.0"
```

### File Permissions (Juno-specific)

```bash
# New scripts need execute permissions set via git (Juno doesn't preserve +x otherwise)
git update-index --chmod=+x bin/my-new-script
git commit -m "Add execute permission to my-new-script"
```

---

## 5. HPC Framework — Setup & Launch

### CLI Aliases

All `tjp-*` commands have two additional alias forms:

```bash
tjp-setup       == hyperion-setup       == biocruiser-setup
tjp-launch      == hyperion-launch      == biocruiser-launch
tjp-batch       == hyperion-batch       == biocruiser-batch
tjp-test        == hyperion-test        == biocruiser-test
```

---

### 5.1 tjp-setup

One-time workspace initialization. Run once per user per cluster. No arguments.

```bash
/groups/tprice/pipelines/bin/tjp-setup
```

**What it does:**

1. Checks for Apptainer, containers, 10x tool installs, UTDal repo
2. Creates `$WORK_ROOT/pipelines/<pipeline>/` and `runs/` subdirs for all 9 pipelines
3. Copies template configs from `templates/` to `$USER_PIPELINES/<pipeline>/config.yaml` with `__USER__`/`__SCRATCH__`/`__WORK__` substituted
4. Copies template samplesheets to `$USER_PIPELINES/<pipeline>/samplesheet.csv`
5. Adds `/groups/tprice/pipelines/bin` to `~/.bashrc` PATH if not already there

**Edge cases:**
- Existing configs are **not** overwritten — re-running is safe
- If Apptainer is not loaded, prints a warning but continues
- If a container `.sif` is missing, prints a warning with the build/transfer command
- Skips native pipeline container checks (cellranger/spaceranger/xeniumranger)

---

### 5.2 tjp-launch

Launches a single pipeline run. Creates a timestamped run directory, snapshots the config, generates a Nextflow config if needed, submits to SLURM, and registers a PLR-xxxx metadata record.

```bash
tjp-launch <pipeline>
tjp-launch <pipeline> --config <path/to/config.yaml>
tjp-launch <pipeline> --dev
tjp-launch <pipeline> --config /path/to/config.yaml --dev
tjp-launch --help
```

**Arguments:**

| Argument | Default | Description |
|----------|---------|-------------|
| `<pipeline>` | required | One of the 9 known pipelines |
| `--config <path>` | `$USER_PIPELINES/<pipeline>/config.yaml` | Path to YAML config file |
| `--dev` | off | Submit to `dev` partition (`--time=02:00:00`) |
| `--help` / `-h` | — | Show help |

**Known pipelines:** `addone bulkrnaseq psoma virome cellranger spaceranger xeniumranger sqanti3 wf-transcriptomes`

**Run directory created:** `/work/$USER/pipelines/<pipeline>/runs/<YYYY-MM-DD_HH-MM-SS>/`

Contents of each run directory:

```
runs/<timestamp>/
├── config.yaml          ← snapshot of the config at launch time
├── manifest.json        ← reproducibility manifest (container hash, git commit, etc.)
├── titan_metadata.json  ← PLR-xxxx Titan metadata record
├── pipeline.config      ← generated Nextflow config (bulkrnaseq/psoma only)
├── slurm_<JOBID>.out    ← redirected from SLURM --output
└── slurm_<JOBID>.err    ← redirected from SLURM --error
```

**Re-running from a previous config snapshot:**

```bash
tjp-launch psoma --config /work/$USER/pipelines/psoma/runs/2026-03-04_14-30-00/config.yaml
```

**Edge cases:**
- If pipeline name is not recognized, prints list of known pipelines and exits
- If config file does not exist, exits with error
- For native pipelines (cellranger/spaceranger/xeniumranger), `--dev` overrides `--time` but not `--exclusive`
- `--dev` sets `--partition=dev --time=02:00:00`; all other SBATCH flags come from the template

---

### 5.3 tjp-batch

Launches multiple runs from a CSV samplesheet. Supports dry-run preview.

```bash
tjp-batch <pipeline> <samplesheet.csv> [options]
```

**Arguments:**

| Argument | Default | Description |
|----------|---------|-------------|
| `<pipeline>` | required | One of the 9 known pipelines |
| `<samplesheet.csv>` | required | Path to samplesheet CSV file |
| `--config <path>` | `$USER_PIPELINES/<pipeline>/config.yaml` | Base config YAML merged with samplesheet row values |
| `--dry-run` | off | Print what would be submitted; do not submit |
| `--dev` | off | Submit all jobs to dev partition |
| `--help` / `-h` | — | Show help |

**Batch modes:**

| Mode | Pipelines | Behavior |
|------|-----------|----------|
| **Per-row** | cellranger, spaceranger, xeniumranger, sqanti3, wf-transcriptomes | One SLURM job per CSV row |
| **Per-sheet** | bulkrnaseq, psoma, virome | One SLURM job for all rows; Nextflow handles per-sample parallelism |

**Samplesheet column schemas:**

```
bulkrnaseq:        sample, fastq_1, fastq_2  [, project_id, sample_id, library_id, run_id]
psoma:             sample, fastq_1, fastq_2  [, project_id, sample_id, library_id, run_id]
virome:            sample, fastq_r1, fastq_r2  [, project_id, sample_id, library_id, run_id]
cellranger:        sample, fastqs, transcriptome  [, sample_name, create_bam, project_id, ...]
spaceranger:       sample, fastqs, transcriptome, image, slide, area  [, unknown_slide, ...]
xeniumranger:      sample, xenium_bundle, command  [, segmentation_file, project_id, ...]
sqanti3:           sample, isoforms, ref_gtf, ref_fasta  [, coverage, fl_count, project_id, ...]
wf-transcriptomes: sample, fastq_dir, sample_sheet, ref_genome, ref_annotation  [, direct_rna, wf_version, ...]
```

> Titan metadata columns (`project_id`, `sample_id`, `library_id`, `run_id`) are optional in all samplesheets. They are written to PLR-xxxx records but **not** passed to the pipeline itself.

**Batch run directory:** `/work/$USER/pipelines/<pipeline>/batch_runs/<BATCH_TS>/`

**Per-row mode:** each row gets a subdirectory `<sample>/` under the batch run dir.

**Dry-run example:**

```bash
tjp-batch cellranger /work/$USER/pipelines/cellranger/samplesheet.csv --dry-run
tjp-batch bulkrnaseq samplesheet.csv --config /work/$USER/pipelines/bulkrnaseq/config.yaml --dry-run
```

**Edge cases:**
- Samplesheet header row is required; comment lines (`#`) and blank lines are skipped
- For per-sheet mode, the whole samplesheet CSV is passed as the `samplesheet` or `--input` parameter to the pipeline
- For bulkrnaseq/psoma, `fastq_dir` is inferred from `dirname(fastq_1)` of the first row
- Titan fields in samplesheet rows override any `titan_*` fields in the base config
- Missing optional columns (e.g., `coverage` in sqanti3) produce empty values, not errors

---

### 5.4 tjp-test

Runs a smoke test for a pipeline using pre-staged test data on the `dev` partition.

```bash
tjp-test <pipeline>
tjp-test <pipeline> --clean
tjp-test --help
```

**Arguments:**

| Argument | Default | Description |
|----------|---------|-------------|
| `<pipeline>` | required | Pipeline to test |
| `--clean` | off | Wipe previous test data in scratch before copying |
| `--help` / `-h` | — | Show help |

**Supported pipelines:** `psoma bulkrnaseq virome cellranger spaceranger sqanti3 wf-transcriptomes`

> xeniumranger not yet supported — needs a Xenium output bundle test dataset.

**Smoke test workflow:**

```bash
tjp-test psoma              # 1. submit
squeue -u $USER             # 2. monitor
tjp-test-validate psoma     # 3. validate outputs
```

**Test data locations:**

| Pipeline | Source |
|----------|--------|
| psoma / bulkrnaseq | `$REPO_ROOT/test_data/rnaseq/fastq/` (2 subsampled samples; gitignored, must be staged) |
| cellranger | `$REPO_ROOT/test_data/10x/cellranger/` (staged on HPC) |
| spaceranger | `$SPACERANGER_DIR/external/spaceranger_tiny_inputs/` (bundled with Space Ranger install) |
| sqanti3 | `$REPO_ROOT/containers/sqanti3/SQANTI3/data/` (must be staged) |
| wf-transcriptomes | `$REPO_ROOT/containers/sqanti3/test_data/wf_transcriptomes/` (must be staged) |

**What it does:** generates a test config at `$SCRATCH_ROOT/pipelines/<pipeline>/test_data/config.yaml`, then calls `tjp-launch <pipeline> --config <test_config> --dev`.

**Edge cases:**
- `--clean` wipes `$SCRATCH_ROOT/pipelines/<pipeline>/test_data/` before copying; use when a previous test left stale outputs
- BulkRNASeq renames test FASTQs from `_1.fastq.gz`/`_2.fastq.gz` → `_R1_001.fastq.gz`/`_R2_001.fastq.gz` during copy
- SpaceRanger test uses `unknown_slide: visium-1` (not real slide serial + area)

---

### 5.5 tjp-test-validate

Checks that a completed smoke test produced the expected output files.

```bash
tjp-test-validate <pipeline>
tjp-test-validate <pipeline> --run <timestamp>
tjp-test-validate --help
```

**Arguments:**

| Argument | Default | Description |
|----------|---------|-------------|
| `<pipeline>` | required | Pipeline to validate |
| `--run <timestamp>` | most recent test run | Validate a specific run by timestamp |
| `--help` / `-h` | — | Show help |

**Supported pipelines:** `psoma bulkrnaseq virome cellranger spaceranger`

**Expected outputs per pipeline:**

*psoma:*
```
dirs:  2_trim_output, 3_hisat2_mapping_output, 4_filter_output,
       5_stringtie_counts_output, 6_raw_counts_output
files: 3_hisat2_mapping_output/*.sorted.bam
       4_filter_output/*.filt.bam
       5_stringtie_counts_output/genes.tpm.txt
       6_raw_counts_output/raw_htseq_counts.csv
```

*bulkrnaseq:*
```
dirs:  2_star_mapping_output, 3_filter_output,
       4_stringtie_counts_output, 5_raw_counts_output
files: 2_star_mapping_output/*Aligned.sortedByCoord.out.bam
       3_filter_output/*.filt.bam
       4_stringtie_counts_output/genes.tpm.txt
       5_raw_counts_output/raw_htseq_counts.csv
```

*virome:*
```
dirs:  results, multiqc, multiqc/multiqc_data
files: results/viral_abundance_matrix.tsv
       results/viral_abundance_matrix.csv
       multiqc/multiqc_report.html
```

*cellranger:*
```
dirs:  <sample_id>/outs, <sample_id>/outs/filtered_feature_bc_matrix,
       <sample_id>/outs/raw_feature_bc_matrix
files: <sample_id>/outs/web_summary.html
       <sample_id>/outs/metrics_summary.csv
       <sample_id>/outs/filtered_feature_bc_matrix/barcodes.tsv.gz
       <sample_id>/outs/filtered_feature_bc_matrix/features.tsv.gz
       <sample_id>/outs/filtered_feature_bc_matrix/matrix.mtx.gz
```

*spaceranger:*
```
dirs:  <sample_id>/outs, <sample_id>/outs/spatial,
       <sample_id>/outs/filtered_feature_bc_matrix
files: <sample_id>/outs/web_summary.html
       <sample_id>/outs/metrics_summary.csv
       <sample_id>/outs/spatial/tissue_positions.csv
       <sample_id>/outs/spatial/scalefactors_json.json
       <sample_id>/outs/filtered_feature_bc_matrix.h5
```

---

### 5.6 labdata

Local Titan metadata store CLI. Every `tjp-launch` and `tjp-batch` run auto-registers a PLR-xxxx record; use `labdata` to query and inspect them.

**Metadata store location:** `/work/$USER/pipelines/metadata/pipeline_runs/`

#### `labdata new-id`

Generate a new Titan-format ID without creating a record.

```bash
labdata new-id <TYPE>

# TYPE options:
labdata new-id PLR    # pipeline run  → PLR-a4f2
labdata new-id PRJ    # project       → PRJ-xxxx
labdata new-id SMP    # sample        → SMP-xxxx
labdata new-id LIB    # library       → LIB-xxxx
labdata new-id RUN    # sequencing run → RUN-xxxx
labdata new-id REF    # reference     → REF-xxxx
labdata new-id ANN    # annotation    → ANN-xxxx
```

#### `labdata register-run`

Manually register a run record (normally called automatically by `tjp-launch`).

```bash
labdata register-run \
    --pipeline <name>            \  # required
    --version  <version>         \  # required (e.g. "v1.0.0")
    --output-path <path>         \  # required
    --status <status>            \  # required: pending|running|completed|failed|cancelled
    [--project  <PRJ-xxxx>]      \
    [--sample   <SMP-xxxx>]      \
    [--library  <LIB-xxxx>]      \
    [--run-id   <RUN-xxxx>]      \
    [--slurm-job-id <id>]        \
    [--container <image>]        \  # e.g. "native:/groups/tprice/opt/cellranger-10.0.0"
    [--params <json_string>]     \  # JSON object, default: {}
    [--run-dir <path>]           \  # also writes titan_metadata.json to this dir
    [--started-at <iso8601>]
# Prints the generated PLR-xxxx on stdout
```

#### `labdata find`

```bash
labdata find runs                              # all runs, table format
labdata find runs --pipeline psoma             # filter by pipeline name
labdata find runs --pipeline bulkrnaseq        # RNA-seq runs only
labdata find runs --status completed           # completed runs only
labdata find runs --status failed              # find failed runs
labdata find runs --format json                # output as JSON array
labdata find runs --format paths               # output as one output_path per line
labdata find runs --pipeline cellranger --format table
```

**Table columns:** `PLR-xxxx | pipeline | version | status | registered_at | output_path`

**Status values:** `pending | running | completed | failed | cancelled`

#### `labdata show`

```bash
labdata show PLR-a4f2    # pretty-print full JSON record
labdata show PLR-xxxx    # replace xxxx with your ID
```

#### `labdata status`

```bash
labdata status    # print summary counts: total runs, by pipeline, by status
```

---

## 6. Pipeline Reference

### Pipeline Execution Models

| Pipeline | Model | Container | Batch mode |
|----------|-------|-----------|------------|
| addone | Inline | Single `.sif` | — |
| bulkrnaseq | Submoduled container | Single `.sif` | Per-sheet |
| psoma | Submoduled combined | Single `.sif` | Per-sheet |
| virome | Multi-container Nextflow | Per-process `.sif` dir | Per-sheet |
| sqanti3 | 4-stage SLURM DAG | Single `.sif` | Per-row |
| wf-transcriptomes | Nextflow SLURM executor | Host Nextflow | Per-row |
| cellranger | Native (no container) | Tool install | Per-row |
| spaceranger | Native (no container) | Tool install | Per-row |
| xeniumranger | Native (no container) | Tool install | Per-row |

---

### 6.1 AddOne

Demo/template pipeline. Adds 1 to each number in a text file.

```bash
# Setup
vi /work/$USER/pipelines/addone/config.yaml

# Launch
tjp-launch addone
tjp-launch addone --config /path/to/config.yaml
tjp-launch addone --dev
```

**Config keys:**

```yaml
input:  /path/to/numbers.txt     # required: input file with one number per line
output: /scratch/juno/$USER/addone/output.txt   # required: output path
```

**Direct container execution (testing):**

```bash
apptainer exec containers/addone_latest.sif \
    python3 pipelines/addone/addone.py \
    --input test_data/numbers.txt \
    --output /tmp/addone_output.txt
```

---

### 6.2 BulkRNASeq

Bulk RNA-seq pipeline using STAR aligner + HTSeq counts. Runs inside the `bulkrnaseq_v1.0.0.sif` container, which wraps the UTDal Bulk-RNA-Seq-Nextflow-Pipeline.

```bash
# Setup
vi /work/$USER/pipelines/bulkrnaseq/config.yaml
vi /work/$USER/pipelines/bulkrnaseq/samples.txt

# Single run
tjp-launch bulkrnaseq
tjp-launch bulkrnaseq --config /path/to/config.yaml

# Batch run (per-sheet — one job for all samples)
vi /work/$USER/pipelines/bulkrnaseq/samplesheet.csv
tjp-batch bulkrnaseq /work/$USER/pipelines/bulkrnaseq/samplesheet.csv
tjp-batch bulkrnaseq samplesheet.csv --config /work/$USER/pipelines/bulkrnaseq/config.yaml --dry-run

# Smoke test
tjp-test bulkrnaseq
tjp-test bulkrnaseq --clean
tjp-test-validate bulkrnaseq
```

**Config keys:**

```yaml
project_name: My-Project-Name
species: Human                    # Human | Mouse | Rattus
paired_end: true                  # true | false

fastq_dir: /scratch/juno/$USER/fastq/
samples_file: /work/$USER/pipelines/bulkrnaseq/samples.txt

star_index: /groups/tprice/pipelines/references/star_index
reference_gtf: /groups/tprice/pipelines/references/gencode.v48.primary_assembly.annotation.gtf
exclude_bed_file_path: /groups/tprice/pipelines/references/filter.bed
blacklist_bed_file_path: /groups/tprice/pipelines/references/blacklist.bed

read1_suffix: _R1_001             # suffix identifying R1 FASTQs
read2_suffix: _R2_001

clip5_num: 11                     # 5' clip bases
clip3_num: 5                      # 3' clip bases
strand_st: --rf                   # StringTie strand: --rf | --fr | (empty)
strand_hts: reverse               # HTSeq strand: reverse | yes | no
paired_hts: pos                   # HTSeq paired: pos | (empty)
fastqc_cores: 40

run_fastqc: true
run_rna_pipeline: true

# Titan integration (optional)
titan_project_id:                 # PRJ-xxxx
titan_sample_id:                  # SMP-xxxx
titan_library_id:                 # LIB-xxxx
titan_run_id:                     # RUN-xxxx
```

**samples.txt format:** one sample name per line, matching FASTQ filename stems:

```
Sample_19
Sample_20
Sample_21
```

**Generating samples.txt from FASTQs:**

```bash
ls /scratch/juno/$USER/fastq/*_R1_001.fastq.gz \
  | xargs -n1 basename \
  | sed 's/_R1_001.fastq.gz//' \
  > /work/$USER/pipelines/bulkrnaseq/samples.txt
```

**Batch samplesheet format:**

```csv
sample,fastq_1,fastq_2
Patient01,/scratch/juno/$USER/fastq/Patient01_R1_001.fastq.gz,/scratch/juno/$USER/fastq/Patient01_R2_001.fastq.gz
Patient02,/scratch/juno/$USER/fastq/Patient02_R1_001.fastq.gz,/scratch/juno/$USER/fastq/Patient02_R2_001.fastq.gz
```

**Output directories:**

```
2_star_mapping_output/      ← STAR BAM files (*Aligned.sortedByCoord.out.bam)
3_filter_output/            ← filtered BAMs (*.filt.bam)
4_stringtie_counts_output/  ← TPM matrix (genes.tpm.txt)
5_raw_counts_output/        ← HTSeq counts (raw_htseq_counts.csv)
```

**STAR index generation (run on an interactive node):**

```bash
srun --time=02:00:00 --mem=40G --cpus-per-task=20 --pty bash
apptainer exec \
    --cleanenv --env PYTHONNOUSERSITE=1 \
    --bind /groups/tprice/pipelines:/groups/tprice/pipelines \
    --bind /scratch/juno/$USER:/scratch/juno/$USER \
    /groups/tprice/pipelines/containers/bulkrnaseq/bulkrnaseq_v1.0.0.sif \
    STAR --runMode genomeGenerate \
        --genomeDir /scratch/juno/$USER/star_index \
        --genomeFastaFiles /path/to/genome.fa \
        --sjdbGTFfile /path/to/annotation.gtf \
        --runThreadN 20
```

**Edge cases:**
- Nextflow working directory at `$SCRATCH_ROOT/nextflow_work` — delete if a previous run left corrupted state: `rm -rf /scratch/juno/$USER/nextflow_work`
- Container uses `--cleanenv` + `--env PYTHONNOUSERSITE=1` — critical for preventing host Python packages from shadowing container packages
- UTDal pipeline code lives at `/groups/tprice/pipelines/Bulk-RNA-Seq-Nextflow-Pipeline/` (separate clone, not a submodule); must exist for the pipeline to run

---

### 6.3 Psoma

Bulk RNA-seq pipeline using HISAT2 aligner + Trimmomatic adapter trimming + HTSeq counts.

```bash
# Setup
vi /work/$USER/pipelines/psoma/config.yaml
vi /work/$USER/pipelines/psoma/samples.txt

# Single run
tjp-launch psoma
tjp-launch psoma --config /path/to/config.yaml

# Batch run (per-sheet)
vi /work/$USER/pipelines/psoma/samplesheet.csv
tjp-batch psoma /work/$USER/pipelines/psoma/samplesheet.csv

# Smoke test
tjp-test psoma
tjp-test psoma --clean
tjp-test-validate psoma
```

**Config keys:**

```yaml
project_name: My-Project-Name
species: Human                    # Human | Mouse | Rattus
paired_end: true

fastq_dir: /scratch/juno/$USER/fastq/
samples_file: /work/$USER/pipelines/psoma/samples.txt

hisat2_index: /groups/tprice/pipelines/references/hisat2_index/gencode48
# IMPORTANT: hisat2_index is a PREFIX PATH, not a directory
# e.g. /path/to/gencode48 → hisat2 looks for gencode48.1.ht2, gencode48.2.ht2 ...

reference_gtf: /groups/tprice/pipelines/references/gencode.v48.primary_assembly.annotation.gtf
exclude_bed_file_path: /groups/tprice/pipelines/references/filter.bed
blacklist_bed_file_path: /groups/tprice/pipelines/references/blacklist.bed

read1_suffix: _1                  # Psoma default (vs _R1_001 for bulkrnaseq)
read2_suffix: _2

# Trimmomatic settings
headcrop: 10
leading: 3
trailing: 3
slidingwindow: "4:15"
minlen: 36
illuminaclip_params: "2:30:10:5:true"   # Nextera adapters

strand_st: --rf
strand_hts: reverse
paired_hts: pos
fastqc_cores: 40

run_fastqc: true
run_rna_pipeline: true

# Titan integration (optional)
titan_project_id:
titan_sample_id:
titan_library_id:
titan_run_id:
```

**FASTQ naming convention:** Psoma expects `<sample>_1.fastq.gz` / `<sample>_2.fastq.gz` (not `_R1_001`).

**Batch samplesheet format:**

```csv
sample,fastq_1,fastq_2
Patient01,/scratch/juno/$USER/fastq/Patient01_1.fastq.gz,/scratch/juno/$USER/fastq/Patient01_2.fastq.gz
```

**Output directories:**

```
2_trim_output/                  ← Trimmomatic trimmed FASTQs
3_hisat2_mapping_output/        ← HISAT2 BAMs (*.sorted.bam)
4_filter_output/                ← filtered BAMs (*.filt.bam)
5_stringtie_counts_output/      ← TPM matrix (genes.tpm.txt)
6_raw_counts_output/            ← HTSeq counts (raw_htseq_counts.csv)
```

**Edge cases:**
- `hisat2_index` is a **prefix path**, not a directory — the index files have the prefix as their stem
- `_JAVA_OPTIONS=-Xmx16g` is set in the container invocation to prevent Trimmomatic OOM at 40 threads
- `HOME=/tmp` is set so Nextflow can write `~/.nextflow` inside the container
- `illuminaclip_params` format: `<seed_mismatches>:<palindrome_clip>:<simple_clip>:<min_adapter_len>:<keep_both_reads>`

---

### 6.4 Virome

Viral profiling pipeline — STAR host removal → Kraken2 classification → Bracken abundance → MultiQC. Native Nextflow on host with per-process Apptainer containers.

```bash
# Setup
vi /work/$USER/pipelines/virome/config.yaml

# Single run (samplesheet path goes in config)
tjp-launch virome
tjp-launch virome --config /path/to/config.yaml

# Batch run (per-sheet — one job for all samples)
vi /work/$USER/pipelines/virome/samplesheet.csv
tjp-batch virome /work/$USER/pipelines/virome/samplesheet.csv

# Smoke test
tjp-test virome
tjp-test-validate virome
```

**Config keys:**

```yaml
project_name: My-Virome-Project
samplesheet: /work/$USER/pipelines/virome/samplesheet.csv
outdir: /scratch/juno/$USER/virome/results

star_index: /groups/tprice/pipelines/references/star_index
kraken2_db: /groups/tprice/pipelines/references/kraken2_viral_db
adapters: /groups/tprice/pipelines/containers/virome/assets/NexteraPE-PE.fa
container_dir: /groups/tprice/pipelines/containers/virome/containers/

trim_headcrop: 0
trim_leading: 3
trim_trailing: 3
trim_slidingwindow: "4:15"
trim_minlen: 36
kraken2_confidence: 0.1
min_reads_per_taxon: 5

# Optional: intermediate file publishing
save_kraken2_output: false        # publishes {id}.kraken2.output to outdir/kraken2_output/
save_unmapped_reads: false        # publishes STAR-unmapped FASTQs; WARNING: ~2 GB/sample

# Titan integration (optional)
titan_project_id:
titan_sample_id:
titan_library_id:
titan_run_id:
```

**Samplesheet format:**

```csv
sample,fastq_r1,fastq_r2
sample01,/scratch/juno/$USER/fastq/sample01_R1.fastq.gz,/scratch/juno/$USER/fastq/sample01_R2.fastq.gz
```

**Output files:**

```
results/viral_abundance_matrix.tsv    ← per-sample viral abundance
results/viral_abundance_matrix.csv
multiqc/multiqc_report.html           ← QC summary
multiqc/multiqc_data/
```

**Container SIF files required** (in `containers/virome/containers/`):

```bash
# Rebuild if main.nf or container defs changed
apptainer build --fakeroot --force containers/virome/containers/python.sif containers/virome/containers/python.def
apptainer build --fakeroot --force containers/virome/containers/star.sif   containers/virome/containers/star.def
apptainer build --fakeroot --force containers/virome/containers/blast.sif  containers/virome/containers/blast.def
# ... (6 per-process containers total)

# Transfer to HPC
rsync -avP containers/virome/containers/*.sif \
    YOUR_NETID@juno.hpcre.utdallas.edu:/groups/tprice/pipelines/containers/virome/containers/
```

**Direct Nextflow invocation (bypassing framework):**

```bash
nextflow run /groups/tprice/pipelines/containers/virome/main.nf \
    -profile slurm \
    --input samplesheet.csv \
    --outdir /scratch/juno/$USER/virome/results \
    -params-file /path/to/config.yaml
```

**Edge cases:**
- Nextflow runs on the host (not inside a container) and dispatches per-process jobs
- `container_dir` must point to a directory containing pre-built `.sif` files
- `save_unmapped_reads: true` can add ~2 GB per sample to the output directory
- Titan columns in the samplesheet (`project_id` etc.) are silently ignored by Nextflow's samplesheet parser — they are read by `tjp-batch` only

---

### 6.5 SQANTI3

4-stage SLURM DAG for long-read transcript quality control. Stages: 1a (QC long-read), 1b (QC reference, runs parallel to 1a), 2 (Filter), 3 (Rescue).

```bash
# Setup
vi /work/$USER/pipelines/sqanti3/config.yaml

# Single run
tjp-launch sqanti3
tjp-launch sqanti3 --config /path/to/config.yaml

# Batch run (per-row — one DAG per CSV row)
vi /work/$USER/pipelines/sqanti3/samplesheet.csv
tjp-batch sqanti3 /work/$USER/pipelines/sqanti3/samplesheet.csv
tjp-batch sqanti3 samplesheet.csv --config base_config.yaml --dry-run

# Smoke test
tjp-test sqanti3
```

**Container setup (one-time, must run on HPC):**

```bash
apptainer pull /groups/tprice/pipelines/containers/sqanti3/sqanti3_v5.5.4.sif \
    docker://anaconesalab/sqanti3:v5.5.4
```

**Config keys:**

```yaml
# Required inputs
sample: my_sample
isoforms: /path/to/collapsed.gtf             # from wf-transcriptomes, FLAIR, StringTie2, etc.
ref_gtf: /groups/tprice/pipelines/references/gencode.v48.primary_assembly.annotation.gtf
ref_fasta: /groups/tprice/pipelines/references/GRCh38.primary_assembly.genome.fa
outdir: /scratch/juno/$USER/sqanti3/results

# Optional inputs
coverage: /path/to/STAR_SJ.out.tab           # short-read junction support
fl_count: /path/to/abundance.tsv             # transcript abundance

# Optional CAGE/polyA (leave blank to skip)
CAGE_peak: /path/to/refTSS.bed
polyA_motif_list: /path/to/polyA_motif.txt
polyA_peak: ""

# Filtering parameters
filter_mode: rules                           # rules | sqanti_rules | expression
rescue_mode: automatic                       # automatic | skip
filter_mono_exonic: false
force_id_ignore: true
skip_report: true                            # skip HTML report generation (faster)
skip_orf: false

# Resource overrides (0 = auto-scale from GTF size)
cpus: 0
chunks: 0

# Titan integration (optional)
titan_project_id:
titan_sample_id:
titan_library_id:
titan_run_id:
```

**Batch samplesheet format:**

```csv
sample,isoforms,ref_gtf,ref_fasta,coverage,fl_count,project_id,sample_id,library_id,run_id
sample_01,/path/to/sample_01_collapsed.gtf,/groups/tprice/pipelines/references/gencode.v48.primary_assembly.annotation.gtf,/groups/tprice/pipelines/references/GRCh38.primary_assembly.genome.fa,,,,,, 
```

**Stage resource scaling:** CPU/memory allocations for stages 1a/1b/2/3 are dynamically computed from the GTF transcript count by the orchestrator script. Set `cpus: 0` to use automatic scaling.

**Edge cases:**
- Outputs write directly to `outdir:` — no scratch staging (unlike bulkrnaseq/psoma)
- SQANTI3 stage scripts are in `containers/sqanti3/slurm_templates/` (not the main `slurm_templates/`)
- The orchestrator uses `--dependency=afterok:<id>` to chain SLURM stages
- `filter_mode: rules` uses a default JSON filter file baked into the container at `/opt2/sqanti3/5.5.4/SQANTI3-5.5.4/src/utilities/filter/filter_default.json`

---

### 6.6 wf-transcriptomes

Oxford Nanopore long-read transcriptomics using the EPI2ME Labs `wf-transcriptomes` Nextflow workflow. The head job runs Nextflow on the SLURM node; Nextflow submits per-process SLURM jobs itself.

```bash
# Setup
vi /work/$USER/pipelines/wf-transcriptomes/config.yaml
vi /work/$USER/pipelines/wf-transcriptomes/samplesheet.csv   # barcode samplesheet

# Single run
tjp-launch wf-transcriptomes
tjp-launch wf-transcriptomes --config /path/to/config.yaml

# Batch run (per-row — one Nextflow head job per CSV row)
vi /work/$USER/pipelines/wf-transcriptomes/samplesheet.csv
tjp-batch wf-transcriptomes /work/$USER/pipelines/wf-transcriptomes/samplesheet.csv
tjp-batch wf-transcriptomes samplesheet.csv --config base_config.yaml --dry-run

# Smoke test
tjp-test wf-transcriptomes
```

**Config keys:**

```yaml
# Required
sample: my_experiment
fastq_dir: /scratch/juno/$USER/ont/experiment_01/fastq_pass
sample_sheet: /scratch/juno/$USER/ont/experiment_01/barcodes.csv
ref_genome: /groups/tprice/pipelines/references/GRCh38.primary_assembly.genome.fa
ref_annotation: /groups/tprice/pipelines/references/gencode.v47.primary_assembly.annotation.gtf
outdir: /scratch/juno/$USER/wf-transcriptomes/results

# Pipeline version
wf_version: v1.7.2               # pinned version of epi2me-labs/wf-transcriptomes

# Read type
direct_rna: false                # true for direct RNA; false for cDNA/PCR

# Alignment
minimap2_index_opts: "-k 15"

# Quality filtering
min_read_length: 100
min_qscore: 9

# Differential expression (optional, requires metadata)
de_analysis: false

# Titan integration (optional)
titan_project_id:
titan_sample_id:
titan_library_id:
titan_run_id:
```

**EPI2ME barcode samplesheet format** (required in `sample_sheet:`):

```csv
barcode,alias
barcode09,sample1
barcode10,sample2
barcode11,sample3
```

Optional third column: `type` (experimental group for DE analysis).

**Batch samplesheet format** (one experiment per row):

```csv
sample,fastq_dir,sample_sheet,ref_genome,ref_annotation,direct_rna,wf_version,project_id,sample_id,library_id,run_id
experiment_01,/scratch/juno/$USER/ont/exp01/fastq_pass,/scratch/juno/$USER/ont/exp01/barcodes.csv,/groups/tprice/pipelines/references/GRCh38.primary_assembly.genome.fa,/groups/tprice/pipelines/references/gencode.v47.primary_assembly.annotation.gtf,false,v1.7.2,,,,
```

**Nextflow config:** `containers/sqanti3/configs/wf_transcriptomes/juno.config` (part of longreads submodule)

**Edge cases:**
- Outputs write directly to `outdir:` — no scratch staging
- Head job is lightweight (2 CPU, 8 GB, 48h) — all heavy compute runs in Nextflow-managed sub-jobs
- `wf_version` pins the exact release of `epi2me-labs/wf-transcriptomes` pulled at runtime; default is `v1.7.2`
- `direct_rna: true` changes minimap2 preset and disables PCR dedup
- `de_analysis: true` requires a metadata column in the barcode samplesheet

---

### 6.7 Cell Ranger

10x Genomics single-cell RNA-seq. Native tool (no Apptainer). Runs with `--exclusive` (full node).

```bash
# Setup
vi /work/$USER/pipelines/cellranger/config.yaml

# Single run
tjp-launch cellranger
tjp-launch cellranger --config /path/to/config.yaml

# Batch run (per-row — one job per sample)
vi /work/$USER/pipelines/cellranger/samplesheet.csv
tjp-batch cellranger /work/$USER/pipelines/cellranger/samplesheet.csv
tjp-batch cellranger samplesheet.csv --dry-run

# Smoke test
tjp-test cellranger
tjp-test-validate cellranger
```

**Tool path:** `/groups/tprice/opt/cellranger-10.0.0` (symlink: `/groups/tprice/software/cellranger`)

**Config keys:**

```yaml
sample_id: my_sample              # used as output directory name
sample_name: my_sample            # matches FASTQ filename prefix
fastq_dir: /scratch/juno/$USER/fastq/
transcriptome: /groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A
localcores: 16
localmem: 120                     # GB

create_bam: true                  # REQUIRED for Cell Ranger 10.0.0+
chemistry: auto                   # auto | SC3Pv3 | SC3Pv2 | etc.
expect_cells: 5000
include_introns: true
tool_path: ""                     # override default install path (optional)

# Titan integration (optional)
titan_project_id:
titan_sample_id:
titan_library_id:
titan_run_id:
```

**Batch samplesheet format:**

```csv
sample,fastqs,transcriptome,sample_name,create_bam,project_id,sample_id,library_id,run_id
sample01,/scratch/juno/$USER/fastq/,/groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A,sample01,true,,,,
```

**Output directories:**

```
<sample_id>/outs/
├── web_summary.html
├── metrics_summary.csv
├── filtered_feature_bc_matrix/
│   ├── barcodes.tsv.gz
│   ├── features.tsv.gz
│   └── matrix.mtx.gz
├── raw_feature_bc_matrix/
└── possorted_genome_bam.bam      ← only if create_bam: true
```

**Edge cases:**
- `create_bam: true` is **required** for Cell Ranger 10.0.0+ (removed default BAM output)
- `sample_name` must match the FASTQ filename prefix exactly (Cell Ranger reads from `<sample_name>_S*_L*_R*.fastq.gz`)
- Chemistry `SC3Pv3LT` (3' v3 LT) was dropped in CR 10.0.0 — do not use
- `--exclusive` in the SLURM template gives the job a full 64-core node; `localcores: 16` limits Cell Ranger's internal thread count to prevent I/O contention
- Override the tool install with `tool_path: /groups/tprice/opt/cellranger-11.0.0` to test a new version

---

### 6.8 Space Ranger

10x Genomics spatial transcriptomics. Native tool (no Apptainer). Runs with `--exclusive`.

```bash
# Setup
vi /work/$USER/pipelines/spaceranger/config.yaml

# Single run
tjp-launch spaceranger
tjp-launch spaceranger --config /path/to/config.yaml

# Batch run (per-row)
vi /work/$USER/pipelines/spaceranger/samplesheet.csv
tjp-batch spaceranger /work/$USER/pipelines/spaceranger/samplesheet.csv

# Smoke test (uses bundled tiny inputs)
tjp-test spaceranger
tjp-test-validate spaceranger
```

**Tool path:** `/groups/tprice/opt/spaceranger-4.0.1` (symlink: `/groups/tprice/software/spaceranger`)

**Config keys:**

```yaml
sample_id: my_section
sample_name: my_section
fastq_dir: /scratch/juno/$USER/fastq/
transcriptome: /groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A
image: /scratch/juno/$USER/images/section.jpg    # brightfield or fluorescence image

# Slide identification — use ONE of these two approaches:
# Option A: known slide serial + area
slide: V10J14-049
area: A1                          # A1 | B1 | C1 | D1

# Option B: unknown/generic slide (smoke test, or if serial not available)
unknown_slide: visium-1           # visium-1 | visium-2 | visium-2-large | visium-hd
# If unknown_slide is set, slide and area are ignored

localcores: 16
localmem: 120
create_bam: true                  # REQUIRED for Space Ranger 3.0+
tool_path: ""

# Titan integration (optional)
titan_project_id:
titan_sample_id:
titan_library_id:
titan_run_id:
```

**Batch samplesheet format:**

```csv
sample,fastqs,transcriptome,image,slide,area,project_id,sample_id,library_id,run_id
section01,/scratch/juno/$USER/fastq/,/groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A,/scratch/juno/$USER/images/section01.jpg,V10J14-049,A1,,,,
```

**Output directories:**

```
<sample_id>/outs/
├── web_summary.html
├── metrics_summary.csv
├── filtered_feature_bc_matrix.h5
├── filtered_feature_bc_matrix/
├── raw_feature_bc_matrix/
└── spatial/
    ├── tissue_positions.csv
    ├── scalefactors_json.json
    ├── tissue_hires_image.png
    └── tissue_lowres_image.png
```

**Edge cases:**
- `create_bam: true` is **required** for Space Ranger 3.0+
- `unknown_slide` takes precedence over `slide` + `area` — useful for pilot runs or when slide info is unavailable
- Image must be the full-resolution brightfield or fluorescence image (`.jpg`, `.png`, `.tiff`)
- Smoke test uses `unknown_slide: visium-1` with images bundled at `$SPACERANGER_DIR/external/spaceranger_tiny_inputs/`

---

### 6.9 Xenium Ranger

10x Genomics Xenium in-situ spatial analysis. Native tool. Runs with `--exclusive`.

```bash
# Setup
vi /work/$USER/pipelines/xeniumranger/config.yaml

# Single run
tjp-launch xeniumranger
tjp-launch xeniumranger --config /path/to/config.yaml

# Batch run (per-row)
vi /work/$USER/pipelines/xeniumranger/samplesheet.csv
tjp-batch xeniumranger /work/$USER/pipelines/xeniumranger/samplesheet.csv
```

**Tool path:** `/groups/tprice/opt/xeniumranger-xenium4.0` (symlink: `/groups/tprice/software/xeniumranger`)

**Config keys:**

```yaml
sample_id: my_xenium_run
command: resegment                # resegment | import-segmentation

xenium_bundle: /scratch/juno/$USER/xenium/20240101_output/   # Xenium instrument output dir
localcores: 16
localmem: 120

# Conditional: required only when command = import-segmentation
segmentation_file: /path/to/segmentation.csv

tool_path: ""                     # override default install path (optional)

# Titan integration (optional)
titan_project_id:
titan_sample_id:
titan_library_id:
titan_run_id:
```

**Batch samplesheet format:**

```csv
sample,xenium_bundle,command,segmentation_file,project_id,sample_id,library_id,run_id
run01,/scratch/juno/$USER/xenium/run01_output,resegment,,,,,
run02,/scratch/juno/$USER/xenium/run02_output,import-segmentation,/scratch/juno/$USER/xenium/run02_seg.csv,,,,
```

**Edge cases:**
- `segmentation_file` is only required when `command: import-segmentation`; leave blank for `resegment`
- Xenium Ranger expects the full Xenium instrument output bundle directory, not individual files
- Smoke testing not yet supported (needs a Xenium output bundle test dataset)

---

## 7. Config Key Reference

### Shared Reference Paths (Juno)

All paths below are on HPC at `/groups/tprice/pipelines/references/`:

| Key | Path | Used by |
|-----|------|---------|
| `star_index` | `references/star_index` | bulkrnaseq, virome |
| `hisat2_index` | `references/hisat2_index/gencode48` | psoma |
| `reference_gtf` | `references/gencode.v48.primary_assembly.annotation.gtf` | bulkrnaseq, psoma |
| `ref_annotation` | `references/gencode.v47.primary_assembly.annotation.gtf` | wf-transcriptomes |
| `ref_gtf` | `references/gencode.v48.primary_assembly.annotation.gtf` | sqanti3 |
| `ref_fasta` | `references/GRCh38.primary_assembly.genome.fa` | sqanti3 |
| `ref_genome` | `references/GRCh38.primary_assembly.genome.fa` | wf-transcriptomes |
| `exclude_bed_file_path` | `references/filter.bed` | bulkrnaseq, psoma |
| `blacklist_bed_file_path` | `references/blacklist.bed` | bulkrnaseq, psoma |
| `kraken2_db` | `references/kraken2_viral_db` | virome |
| `transcriptome` | `references/refdata-gex-GRCh38-2024-A` | cellranger, spaceranger |

### Titan Integration Keys

Use `titan_` prefix in YAML configs to avoid naming collisions with native tool fields:

```yaml
titan_project_id:    # PRJ-xxxx — links run to a Titan project
titan_sample_id:     # SMP-xxxx — links run to a biological sample
titan_library_id:    # LIB-xxxx — links run to a sequencing library
titan_run_id:        # RUN-xxxx — links run to a sequencing run
```

> These are **framework-level only** — do not add them to Nextflow `pipeline.config` or pass them to tool command lines.

In batch **samplesheets**, the same fields appear without the `titan_` prefix (unambiguous in CSV context):

```csv
project_id,sample_id,library_id,run_id
```

---

## 8. Path & Environment Reference

### Key Paths

```bash
# Shared framework
/groups/tprice/pipelines/           # REPO_ROOT — shared code, containers, references
/groups/tprice/pipelines/bin/       # CLI tools (added to PATH by tjp-setup)
/groups/tprice/opt/                 # 10x tool installs (cellranger, spaceranger, xeniumranger)
/groups/tprice/software/            # symlinks to versioned tool dirs

# Per-user
/work/$USER/                        # WORK_ROOT — permanent, medium speed
/work/$USER/pipelines/              # USER_PIPELINES — workspace root
/work/$USER/pipelines/<pl>/runs/    # timestamped run directories (config snapshots, logs)
/work/$USER/pipelines/metadata/     # labdata PLR-xxxx JSON records

/scratch/juno/$USER/                # SCRATCH_ROOT — fast, temporary (purged periodically)
/scratch/juno/$USER/pipelines/<pl>/ # scratch I/O for pipeline runs

# Reference data (shared, read-only)
/groups/tprice/pipelines/references/star_index/
/groups/tprice/pipelines/references/hisat2_index/
/groups/tprice/pipelines/references/gencode.v48.primary_assembly.annotation.gtf
/groups/tprice/pipelines/references/GRCh38.primary_assembly.genome.fa
/groups/tprice/pipelines/references/kraken2_viral_db/
/groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A/   # 10x reference
```

### Environment Variables Set by Framework

```bash
REPO_ROOT="/groups/tprice/pipelines"
WORK_ROOT="/work/$USER"
SCRATCH_ROOT="/scratch/juno/$USER"
USER_PIPELINES="$WORK_ROOT/pipelines"
```

### 10x Tool Versions & Paths

| Tool | Version | Install path | Symlink |
|------|---------|-------------|---------|
| Cell Ranger | 10.0.0 | `/groups/tprice/opt/cellranger-10.0.0` | `/groups/tprice/software/cellranger` |
| Space Ranger | 4.0.1 | `/groups/tprice/opt/spaceranger-4.0.1` | `/groups/tprice/software/spaceranger` |
| Xenium Ranger | xenium4.0 | `/groups/tprice/opt/xeniumranger-xenium4.0` | `/groups/tprice/software/xeniumranger` |

**To upgrade a 10x tool:**

```bash
# 1. Extract new tarball
tar -xzf cellranger-11.0.0.tar.gz -C /groups/tprice/opt/

# 2. Update symlink
ln -sfn /groups/tprice/opt/cellranger-11.0.0 /groups/tprice/software/cellranger

# 3. Update PIPELINE_TOOL_PATHS in bin/lib/common.sh
# 4. Test with: tjp-test cellranger
```

---

## 9. Troubleshooting

### Commands not found

```bash
# Confirm PATH is set
echo $PATH | grep -o 'groups/tprice/pipelines/bin'

# Fix for current session
export PATH="/groups/tprice/pipelines/bin:$PATH"

# Fix permanently (if tjp-setup was not run)
echo 'export PATH="/groups/tprice/pipelines/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Apptainer not found

```bash
module load apptainer
# Or check available versions:
module avail apptainer
```

### Job fails immediately — config not found

```bash
cat /work/$USER/pipelines/<pipeline>/runs/<timestamp>/slurm_<JOBID>.err
# Look for: "ERROR: Config file not found"
# Fix: verify path in config.yaml, re-run tjp-launch
```

### BulkRNASeq — corrupted Nextflow work directory

```bash
rm -rf /scratch/juno/$USER/nextflow_work
tjp-launch bulkrnaseq
```

### SQANTI3 — container not found

```bash
apptainer pull /groups/tprice/pipelines/containers/sqanti3/sqanti3_v5.5.4.sif \
    docker://anaconesalab/sqanti3:v5.5.4
```

### Submodule not initialized

```bash
cd /groups/tprice/pipelines
git submodule update --init --recursive
# Check status:
git submodule status
```

### Path resolution failure in Apptainer

```bash
# Juno's symlinked home dir can break bind mounts
readlink -f ~/work           # get real path
readlink -f /work/$USER      # should return same real path
# Use the resolved real path in bind mount arguments
```

### Psoma — Java OOM with Trimmomatic

The template already sets `_JAVA_OPTIONS=-Xmx16g`. If OOM persists, reduce `--cpus-per-task` in the SLURM template (Trimmomatic uses one JVM per thread).

### 10x tools — unexpected node sharing

If another user's job lands on your exclusive node, contact HPC support — the `--exclusive` flag should prevent this. Verify with:

```bash
squeue -j <JOBID> -o "%i %j %T %N %R"   # check node assignment and reason
```

### Checking what a PLR-xxxx run produced

```bash
labdata show PLR-xxxx         # shows output_path
ls $(labdata find runs --format paths | grep PLR-xxxx)
```

---

*To keep this document current: update it whenever a new pipeline is added, a config key changes, a tool is upgraded, or a flag is added to any `tjp-*` command. The authoritative sources for each section are the `bin/` scripts themselves and `CLAUDE.md`.*
