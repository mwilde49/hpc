# BioCruiser / Hyperion Compute — Developer Onboarding Guide

This document is a comprehensive technical reference for developers joining the TJP HPC pipeline framework. It covers every layer of the system, traces execution flows step-by-step for all nine pipelines, and explains the design decisions behind each component.

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Architecture: The Four-Layer Stack](#2-architecture-the-four-layer-stack)
3. [Shared Infrastructure](#3-shared-infrastructure)
4. [Pipeline Execution Flows](#4-pipeline-execution-flows)
   - [Common Launch Sequence](#41-common-launch-sequence-tjp-launch)
   - [AddOne (Inline Container)](#42-addone-inline-container-pipeline)
   - [BulkRNASeq (Submoduled Container + External Nextflow)](#43-bulkrnaseq-submoduled-container--external-nextflow)
   - [Psoma (Submoduled Combined Container+Pipeline)](#44-psoma-submoduled-combined-containerpipeline)
   - [Cell Ranger (Native 10x)](#45-cell-ranger-native-10x)
   - [Space Ranger (Native 10x)](#46-space-ranger-native-10x)
   - [Xenium Ranger (Native 10x)](#47-xenium-ranger-native-10x)
   - [Virome (Native Nextflow + Per-Process Containers)](#48-virome-native-nextflow--per-process-containers)
   - [SQANTI3 (4-Stage SLURM DAG)](#49-sqanti3-4-stage-slurm-dag)
   - [wf-transcriptomes (Nextflow SLURM Executor)](#410-wf-transcriptomes-nextflow-slurm-executor)
5. [Pipeline Comparison Matrix](#5-pipeline-comparison-matrix)
6. [Testing Infrastructure](#6-testing-infrastructure)
7. [Adding a New Pipeline](#7-adding-a-new-pipeline)
8. [HPC Environment](#8-hpc-environment)
9. [Key Files Reference](#9-key-files-reference)

---

## 1. System Overview

This framework runs bioinformatics pipelines on the Juno HPC cluster for the TJP research group. It is deployed to `/groups/tprice/pipelines` and provides nine pipelines:

| Pipeline | Type | Purpose |
|----------|------|---------|
| **AddOne** | Inline container | Demo/template pipeline (adds 1 to numbers) |
| **BulkRNASeq** | Submoduled container | Bulk RNA-seq analysis (STAR aligner) |
| **Psoma** | Submoduled container | Psomagen RNA-seq analysis (HISAT2 + Trimmomatic) |
| **Cell Ranger** | Native 10x | Single-cell RNA-seq (10x Genomics) |
| **Space Ranger** | Native 10x | Spatial transcriptomics (10x Visium) |
| **Xenium Ranger** | Native 10x | In situ transcriptomics (10x Xenium) |
| **Virome** | Submoduled (native Nextflow) | Viral profiling (Kraken2/MetaPhlAn3) |
| **SQANTI3** | Submoduled (SLURM DAG) | Long-read isoform QC (4-stage pipeline) |
| **wf-transcriptomes** | Submoduled (Nextflow SLURM executor) | ONT full-length transcript analysis |

Users interact through seven CLI tools:

```
tjp-setup          →  One-time workspace initialization
tjp-launch         →  Submit a single pipeline run
tjp-batch          →  Batch submission from CSV samplesheet
tjp-test           →  Smoke test with bundled test data
tjp-test-validate  →  Verify smoke test outputs
tjp-validate       →  Validate config without submitting
labdata            →  Metadata management (find/show PLR-xxxx records)
```

All tools also have `hyperion-*` and `biocruiser-*` symlink aliases.

---

## 2. Architecture: The Four-Layer Stack

The framework has four layers, each with a single responsibility. Think of it as an assembly line:

### Layer 1: Config (the order form)

**Location:** `templates/<pipeline>/config.yaml`

YAML files where users specify their inputs, outputs, and parameters. Templates contain `__USER__`, `__SCRATCH__`, and `__WORK__` placeholders that `tjp-setup` replaces with real paths. Users edit these once, then launch.

Each pipeline has different required keys. For example, Cell Ranger needs `sample_id`, `fastq_dir`, `transcriptome`, `localcores`, `localmem`, and `create_bam`. Psoma needs `hisat2_index`, `reference_gtf`, and Trimmomatic parameters. All pipelines that integrate with Titan include an optional block of `titan_*` fields for metadata registration.

### Layer 2: SLURM (the receptionist)

**Location:** `slurm_templates/<pipeline>_slurm_template.sh`

SLURM job scripts that request resources (CPUs, memory, walltime) from the cluster scheduler. When you submit a job, SLURM finds a free compute node that meets your requirements and runs your script there.

Key resource allocations:

| Pipeline | Time | CPUs | Memory | Exclusive |
|----------|------|------|--------|-----------|
| AddOne | 5 min | 1 | 1 GB | No |
| BulkRNASeq | 12h | 40 | 128 GB | No |
| Psoma | 12h | 40 | 128 GB | No |
| Cell Ranger | 24h | 16 | 128 GB | Yes |
| Space Ranger | 24h | 16 | 128 GB | Yes |
| Xenium Ranger | 12h | 16 | 128 GB | Yes |
| Virome | 12h | 20 | 64 GB | No |
| SQANTI3 | Orchestrator: 1h; stages: dynamic | Dynamic | Dynamic | No |
| wf-transcriptomes | 24h head job; sub-jobs dynamic | 2 (head) | 8 GB (head) | No |

### Layer 3: Execution Environment (the sealed toolbox)

**Location:** `containers/` (container definitions and submodules)

Three models:

- **Container pipelines** (AddOne, BulkRNASeq, Psoma, SQANTI3): All dependencies are packaged into an Apptainer `.sif` file. The SLURM template runs `apptainer exec` with `--cleanenv` (no host environment leakage) and `--env PYTHONNOUSERSITE=1` (no host Python package shadowing). Host directories are bind-mounted into the container.

- **Native pipelines** (Cell Ranger, Space Ranger, Xenium Ranger): 10x Genomics tools are installed from tarballs at `/groups/tprice/opt/` and manage their own execution. The SLURM template calls a wrapper script that invokes the tool directly. No container needed.

- **Nextflow-managed pipelines** (Virome, wf-transcriptomes): Nextflow runs natively on the compute node (no Apptainer wrapper for the head process). Nextflow itself manages per-process containers or submits sub-jobs to SLURM.

### Layer 4: Pipeline (the worker)

The actual scientific code. For container pipelines, this is Python/Nextflow scripts inside the container. For native pipelines, this is the 10x Genomics binary itself. For Nextflow-managed pipelines, this is a Nextflow workflow that coordinates tools across stages. This layer reads the config, processes data, and writes results.

### How They Connect

```
User runs tjp-launch <pipeline>
    │
    ▼
CLI Layer (bin/tjp-launch)
    │  validates config, creates run directory,
    │  generates manifest, registers Titan metadata,
    │  calls sbatch
    │
    ▼
SLURM Layer (slurm_templates/)
    │  allocates compute node, sets up environment,
    │  runs pre-flight checks
    │
    ▼
Execution Layer (containers/ or native tools)
    │  container: apptainer exec ... pipeline_script
    │  native:    bash wrapper.sh config.yaml output_dir
    │  nextflow:  nextflow run ... --params-file config.yaml
    │
    ▼
Pipeline Layer (pipelines/ or external code)
    │  reads config, processes data, writes results
    │
    ▼
Stage-Out
    rsync results from scratch → work directory
    verify archive integrity via checksum
```

---

## 3. Shared Infrastructure

### 3.1 Pipeline Registry (`bin/lib/common.sh`)

This is the central nervous system. Every script sources it. It defines:

**Pipeline registries** (associative arrays):
- `PIPELINE_CONTAINERS` — maps pipeline names to `.sif` file paths (lines 17-19)
- `PIPELINE_TEMPLATES` — maps pipeline names to SLURM template paths (lines 22-30)
- `PIPELINE_TOOL_PATHS` — maps native pipelines to tool install directories (lines 34-36)
- `NATIVE_PIPELINES` — array of pipelines that skip containers (line 40)
- `NEXTFLOW_MANAGED_PIPELINES` — array of pipelines where Nextflow manages sub-job containers
- `KNOWN_PIPELINES` — master list of all pipelines (line 43)

**Key functions:**
- `yaml_get <file> <key>` — reads a value from flat YAML (grep-based, not a full parser)
- `yaml_has <file> <key>` — checks if a key exists
- `is_native_pipeline <name>` — returns 0 if pipeline skips containers
- `is_nextflow_managed_pipeline <name>` — returns 0 if Nextflow manages sub-job execution
- `get_tool_path <name>` — returns native tool install path
- `get_container_path <name>` — returns full `.sif` path
- `get_slurm_template <name>` — returns SLURM template path
- `timestamp` — returns `YYYY-MM-DD_HH-MM-SS`
- `info`, `warn`, `error`, `die` — colored logging with timestamps

**To register a new pipeline**, add entries to these arrays. The rest of the framework discovers pipelines through these registries.

### 3.2 Config Validation (`bin/lib/validate.sh`)

Each pipeline has a `_validate_<name>()` function. The dispatcher `validate_config()` routes by pipeline name. Validators check:

1. **Required keys present** — e.g., `sample_id`, `fastq_dir`
2. **Paths exist** — input files/directories must be on disk (skips `__*` placeholders)
3. **Numeric fields valid** — `localcores`, `localmem` must be positive integers
4. **Pipeline-specific logic:**
   - Psoma: HISAT2 index is a prefix path — checks `${index}.1.ht2` exists
   - Space Ranger: XOR logic — either (`slide` + `area`) or `unknown_slide`, not both
   - Xenium Ranger: `command` must be `resegment` or `import-segmentation`; if `import-segmentation`, `segmentation_file` is required
   - SQANTI3: isoform GTF and reference GTF must both exist
   - wf-transcriptomes: `sample_sheet` CSV must exist, `wf_version` is checked for semver format

Errors are collected in an array and reported all at once, not one-at-a-time.

### 3.3 Reproducibility Manifest (`bin/lib/manifest.sh`)

Every launch creates a `manifest.json` in the run directory:

```json
{
    "timestamp": "2026-03-11T14:30:45-05:00",
    "user": "jsmith",
    "pipeline": "psoma",
    "git_commit": "2ffe5b2",
    "container_file": "/groups/tprice/pipelines/containers/psoma/psomagen_v1.0.0.sif",
    "container_checksum": "a1b2c3d4e5f6...",
    "config": "config.yaml",
    "slurm_job_id": "123456",
    "slurm_template": "slurm_templates/psoma_slurm_template.sh",
    "input_paths": "/scratch/juno/jsmith/fastq/",
    "output_paths": "/scratch/juno/jsmith/pipelines/psoma/runs/2026-03-11_14-30-45",
    "titan_pipeline_run_id": "PLR-a3b7"
}
```

Key details:
- `container_checksum` is an MD5 of the first 10MB of the `.sif` file (for speed)
- For native pipelines, `container_file` is `native:<tool_path>` and `container_checksum` is the tool version string
- `slurm_job_id` starts as `"pending"` and is updated after `sbatch` returns
- `titan_pipeline_run_id` is populated after metadata registration (if Titan fields are present in config); absent from manifest if no Titan block in config

### 3.4 Branding (`bin/lib/branding.sh`)

Provides Hyperion Compute themed output:
- `hyperion_banner [mode]` — prints ASCII banner with cluster node count
- `hyperion_milestone <msg>` — prints `[HYPERION]` prefixed status messages
- `hyperion_sign_off` — closing banner

### 3.5 Workspace Setup (`bin/tjp-setup`)

One-time script that:
1. Runs pre-flight checks (Apptainer available, containers exist, 10x tools installed)
2. Creates `/work/$USER/pipelines/<pipeline>/runs/` for all known pipelines
3. Copies config templates with placeholder substitution (`__USER__` → `$USER`, etc.)
4. Also copies samplesheet templates from `templates/<pipeline>/samplesheet.csv` (if present)
5. Adds `$REPO_ROOT/bin` to the user's `.bashrc`

### 3.6 Samplesheet Library (`bin/lib/samplesheet.sh`)

Provides CSV samplesheet validation and parsing for all nine pipelines. All batch-mode operations go through this library.

**Key public functions:**

- `validate_samplesheet <pipeline> <path>` — checks that all required columns for the given pipeline are present in the CSV header; exits non-zero with a descriptive error if any are missing
- `samplesheet_row_count <path>` — returns the number of data rows (excludes the header line and any lines beginning with `#`)
- `samplesheet_get_col <path> <column> <row_num>` — extract a single cell value by column name and 1-indexed row number
- `samplesheet_to_samples_file <path> <output>` — write all `sample_name` values (one per line) to a file; used by bulkrnaseq/psoma to generate the `samples_file` param
- `samplesheet_infer_fastq_dir <path>` — returns `$(dirname)` of the first `fastq_1` path; used by bulkrnaseq/psoma when the samplesheet encodes full paths
- `samplesheet_get_titan_ids <path> <row_num>` — prints Titan ID fields (`project_id`, `sample_id`, `library_id`, `run_id`) as `key=value` pairs for a given row; returns empty for any absent columns

**Required columns per pipeline** are defined in the `_SAMPLESHEET_REQUIRED_COLS` associative array at the top of `samplesheet.sh`. Each entry is a space-separated list of column names. Example:

```bash
_SAMPLESHEET_REQUIRED_COLS[cellranger]="sample_id sample_name fastq_dir transcriptome"
_SAMPLESHEET_REQUIRED_COLS[psoma]="sample_name fastq_1 fastq_2"
_SAMPLESHEET_REQUIRED_COLS[virome]="sample_id fastq_1 fastq_2"
```

Adding a new pipeline requires adding its entry here as well as registering it in `common.sh`.

### 3.7 Metadata Library (`bin/lib/metadata.sh`)

Provides local Titan metadata record generation. Records are stored as JSON files in the user's metadata store at `$WORK_ROOT/pipelines/metadata/`. When Titan connectivity is available in the future, these local records will be the source of truth for sync.

**Key public functions:**

- `register_pipeline_run [options]` — generates a `PLR-xxxx` ID (collision-checked against existing records), writes a JSON record to the metadata store, and prints the new ID on stdout. Options: `--pipeline <name>`, `--job-id <id>`, `--run-dir <path>`, `--config <path>`, `--project-id <PRJ-xxxx>`, `--sample-id <SMP-xxxx>`, `--library-id <LIB-xxxx>`, `--run-id <RUN-xxxx>`
- `update_pipeline_run_status <plr_id> <status>` — updates the `status` field in-place using `jq`; valid values are `submitted`, `running`, `completed`, `failed`
- `generate_titan_id <TYPE>` — generates a `TYPE-xxxx` ID (4 lowercase hex characters) that does not collide with any existing record of that type in the metadata store; used internally by `register_pipeline_run`
- `metadata_get_store` — returns the path to the metadata store directory, creating it if it does not exist

**PLR-xxxx JSON schema:**

```json
{
    "id": "PLR-xxxx",
    "pipeline": "psoma",
    "slurm_job_id": "151456",
    "run_directory": "/work/$USER/pipelines/psoma/runs/<ts>/",
    "config_snapshot": "/work/$USER/.../config.yaml",
    "status": "submitted",
    "titan_registered": false,
    "project_id": "PRJ-xxxx",
    "sample_id": "SMP-xxxx",
    "library_id": "LIB-xxxx",
    "run_id": "RUN-xxxx"
}
```

The `titan_registered` flag is `false` locally; it will be set to `true` when a future Titan sync confirms server-side registration. Fields `project_id` through `run_id` are omitted (rather than null) if the corresponding `titan_*` keys are absent from the config.

**`labdata` CLI (`bin/labdata`):**

User-facing tool for browsing the local metadata store:
- `labdata list` — list all PLR records (newest first)
- `labdata show <PLR-xxxx>` — pretty-print a single record
- `labdata status <PLR-xxxx> <status>` — manually update status

### 3.8 Batch Launcher (`bin/tjp-batch`)

Reads a CSV samplesheet and submits one or more pipeline runs without requiring the user to manually edit a config per sample. All samplesheet validation is delegated to `bin/lib/samplesheet.sh`.

**Usage:**
```
tjp-batch <pipeline> --samplesheet <path> [--config <base_config>] [--dev]
```

**Two batch modes:**

- **Per-row** (cellranger, spaceranger, xeniumranger, sqanti3, wf-transcriptomes): one `tjp-launch` call per CSV data row. Each row provides sample-specific values that override or extend the base config.

- **Per-sheet** (bulkrnaseq, psoma, virome): one `tjp-launch` call for the entire samplesheet. The samplesheet is treated as a unit (all samples processed together in one Nextflow run).

**Per-row flow:**
1. Validate samplesheet via `validate_samplesheet <pipeline> <path>`
2. For each data row:
   a. Read per-row values (`sample_id`, `fastq_dir`, Titan IDs, etc.)
   b. Generate a per-sample config by copying the base config and injecting row values
   c. Call `tjp-launch <pipeline> --config <per_sample_config> [--dev]`
3. Print a summary table of submitted job IDs and PLR IDs

**Per-sheet flow:**
1. Validate samplesheet via `validate_samplesheet <pipeline> <path>`
2. Build augmented config:
   - Virome: inject `samplesheet: <path>` into the base config
   - BulkRNASeq/Psoma: call `samplesheet_to_samples_file` to write a samples file and `samplesheet_infer_fastq_dir` to determine `fastq_dir`; inject both into the base config
3. Call `tjp-launch <pipeline> --config <augmented_config> [--dev]` once
4. Print submitted job ID

The `--dev` flag is forwarded to every `tjp-launch` call, routing all jobs to the dev partition.

---

## 4. Pipeline Execution Flows

### 4.1 Common Launch Sequence (`tjp-launch`)

Every pipeline goes through the same launch sequence before diverging at the pipeline-specific dispatch. Here it is step by step:

**File:** `bin/tjp-launch`

#### Step 1: Initialization (lines 1-19)
```
set -euo pipefail
source lib/common.sh     ← pipeline registry, YAML helpers, logging
source lib/validate.sh   ← per-pipeline validators
source lib/manifest.sh   ← manifest generation
source lib/metadata.sh   ← PLR-xxxx Titan metadata
```

#### Step 2: Argument Parsing (lines 200-231)
```
tjp-launch <pipeline> [--config <path>] [--dev]

PIPELINE = first positional arg (e.g., "psoma")
CONFIG_PATH = --config value, or default: /work/$USER/pipelines/$PIPELINE/config.yaml
DEV_MODE = true if --dev passed (uses dev partition, 2h limit)
```

#### Step 3: Validation (lines 233-254)
```
is_known_pipeline "$PIPELINE"   ← check against KNOWN_PIPELINES array
[ -f "$CONFIG_PATH" ]           ← config file must exist
validate_config "$PIPELINE" "$CONFIG_PATH"  ← run per-pipeline validator
```

#### Step 4: Path Resolution (lines 257-279)
```
SLURM_TEMPLATE = get_slurm_template "$PIPELINE"
  → slurm_templates/${PIPELINE}_slurm_template.sh

if is_native_pipeline "$PIPELINE":
    TOOL_PATH = get_tool_path "$PIPELINE"
    CONTAINER = "native:$TOOL_PATH"
    (check for config-level tool_path override)
else:
    CONTAINER = get_container_path "$PIPELINE"
    verify .sif file exists (skipped for nextflow-managed pipelines)
```

#### Step 5: Run Directory (lines 281-288)
```
TS = timestamp()  → "2026-03-11_14-30-45"
RUN_DIR = /work/$USER/pipelines/$PIPELINE/runs/$TS
mkdir -p "$RUN_DIR"
cp "$CONFIG_PATH" "$RUN_DIR/config.yaml"   ← snapshot for reproducibility
```

#### Step 6: Extract Input Path (lines 290-297)
```
case $PIPELINE in
    bulkrnaseq|psoma)  FASTQ_DIR = yaml_get config "fastq_dir" ;;
    cellranger|spaceranger) FASTQ_DIR = yaml_get config "fastq_dir" ;;
    xeniumranger) FASTQ_DIR = yaml_get config "xenium_bundle" ;;
    virome) FASTQ_DIR = "" (outdir used instead) ;;
    sqanti3|wf_transcriptomes) FASTQ_DIR = "" (output goes to outdir) ;;
    addone) FASTQ_DIR = "" ;;
esac
```

#### Step 7: Pipeline-Specific Dispatch (lines 299-344)
This is where pipelines diverge. See individual sections below.

#### Step 8: Manifest (line 347)
```
generate_manifest "$RUN_DIR" "$PIPELINE" "$RUN_DIR/config.yaml" "$CONTAINER" "$SLURM_TEMPLATE"
  → writes RUN_DIR/manifest.json with git commit, container checksum, paths
```

#### Step 9: Titan Metadata Registration
After sbatch returns the job ID:
- Reads `titan_project_id`, `titan_sample_id`, `titan_library_id`, `titan_run_id` from `config.yaml` (if present)
- Calls `register_pipeline_run()` from `metadata.sh` with the pipeline name, SLURM job ID, run directory path, config snapshot path, and any Titan IDs found
- Returns a `PLR-xxxx` ID
- Calls `update_manifest_titan_id()` to add `titan_pipeline_run_id` to `manifest.json`
- Logs: `Metadata record: PLR-a3b7  (labdata show PLR-a3b7)`
- If no `titan_*` keys are present in config, this step is skipped silently

#### Step 10: Submit (lines 350-366)
```
sbatch \
    --output="$RUN_DIR/slurm_%j.out" \
    --error="$RUN_DIR/slurm_%j.err" \
    [--partition=dev --time=02:00:00]   ← if --dev mode
    "$SLURM_TEMPLATE" \
    "$SBATCH_CONFIG_ARG" \              ← arg $1: config file
    "$RUN_DIR" \                        ← arg $2: work run directory
    "$SCRATCH_OUTPUT_DIR" \             ← arg $3: scratch output directory
    "$FASTQ_DIR"                        ← arg $4: input dir for archiving
```

#### Step 11: Post-Submit (lines 369-400)
```
JOB_ID = parse from sbatch output
update_manifest_job_id "$RUN_DIR" "$JOB_ID"
update_pipeline_run_status "$PLR_ID" "submitted"  ← if Titan metadata registered
print summary (job ID, run dir, monitoring commands)
```

---

### 4.2 AddOne (Inline Container Pipeline)

**Type:** Inline — pipeline code lives in `pipelines/addone/`, container built from `containers/apptainer.def`.

**Purpose:** Demo pipeline that reads a file of numbers and writes each number + 1. Serves as a template for new pipelines.

#### Dispatch (tjp-launch lines 304-307)
```
SBATCH_CONFIG_ARG = "$RUN_DIR/config.yaml"
```
No Nextflow config generation. Config YAML passed directly to SLURM template.

#### SLURM Execution (`slurm_templates/addone_slurm_template.sh`)

```
#SBATCH --job-name=addone_demo
#SBATCH --time=00:05:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
```

1. `module load apptainer`
2. Set paths: `PROJECT_ROOT`, `SCRATCH_ROOT`, `WORK_ROOT`
3. Receive `CONFIG=$1` from sbatch
4. Execute inside container:

```bash
apptainer exec \
    --bind $PROJECT_ROOT:$PROJECT_ROOT \
    --bind $SCRATCH_ROOT:$SCRATCH_ROOT \
    --bind $WORK_ROOT:$WORK_ROOT \
    $CONTAINER \
    python $PIPELINE --config $CONFIG
```

#### Pipeline Execution (`pipelines/addone/addone.py`)

1. Parse `--config` argument
2. Load YAML config with `yaml.safe_load()`
3. Extract `input` and `output` paths from config
4. Read input file → list of numbers
5. Add 1 to each: `[x + 1 for x in numbers]`
6. Create output directory if needed
7. Write results to output file

#### Container Definition (`containers/apptainer.def`)

```
Bootstrap: docker
From: python:3.11-slim

%post
    pip install pyyaml

%environment
    export LC_ALL=C
    export LANG=C
```

Minimal container — just Python 3.11 + PyYAML.

#### Config Template (`templates/addone/config.yaml`)

```yaml
input: /groups/tprice/pipelines/test_data/numbers.txt
output: __SCRATCH__/addone_output.txt
```

Only two keys. The simplest config in the framework.

#### Key Takeaway

AddOne demonstrates the minimal execution path: config → SLURM → Apptainer → Python script. No Nextflow, no submodules, no Nextflow config generation. Use this as a reference when adding new simple pipelines.

---

### 4.3 BulkRNASeq (Submoduled Container + External Nextflow)

**Type:** Submoduled — container repo at `containers/bulkrnaseq/` (pinned to v1.0.0), pipeline code in a separately cloned repo (`Bulk-RNA-Seq-Nextflow-Pipeline` from UTDal).

**Purpose:** Bulk RNA-seq analysis using STAR aligner, with FastQC, featureCounts, and StringTie.

#### Dispatch (tjp-launch lines 308-325)

This is the most complex dispatch:

```
1. Create scratch output dir:
   SCRATCH_OUTPUT_DIR = /scratch/juno/$USER/pipelines/bulkrnaseq/runs/$TS

2. Symlink UTDal pipeline files into scratch:
   for each file in $REPO_ROOT/Bulk-RNA-Seq-Nextflow-Pipeline:
       ln -sf "$f" "$SCRATCH_OUTPUT_DIR/"
   (Nextflow's config_directory points here to find scripts)

3. Generate Nextflow config:
   _generate_nextflow_config "$RUN_DIR/config.yaml" "$RUN_DIR/pipeline.config" "$SCRATCH_OUTPUT_DIR"
   (reads user YAML, substitutes into templates/bulkrnaseq/pipeline.config.tmpl)

4. SBATCH_CONFIG_ARG = "$RUN_DIR/pipeline.config"
```

#### Nextflow Config Generation (`_generate_nextflow_config`, lines 37-110)

Reads these keys from user YAML and substitutes `@@PLACEHOLDER@@` values in the template:

- `project_name`, `species`, `paired_end`
- `fastq_dir`, `samples_file`
- `star_index`, `reference_gtf`
- `read1_suffix` (default: `_R1_001`), `read2_suffix` (default: `_R2_001`)
- `clip5_num` (default: 11), `clip3_num` (default: 5)
- `strand_st` (default: `--rf`), `strand_hts` (default: `reverse`), `paired_hts` (default: `pos`)
- `exclude_bed_file_path`, `blacklist_bed_file_path`
- `fastqc_cores`, `run_fastqc`, `run_rna_pipeline`

Sets `config_directory` to the scratch output dir (where UTDal files were symlinked).

#### SLURM Execution (`slurm_templates/bulkrnaseq_slurm_template.sh`)

```
#SBATCH --time=12:00:00
#SBATCH --cpus-per-task=40
#SBATCH --mem=128G
```

1. `module load apptainer`
2. Pre-flight: verify container, UTDal repo, and pipeline config exist
3. Execute:

```bash
apptainer exec \
    --cleanenv \
    --env PYTHONNOUSERSITE=1 \
    --bind $PROJECT_ROOT:$PROJECT_ROOT \
    --bind $SCRATCH_ROOT:$SCRATCH_ROOT \
    --bind $WORK_ROOT:$WORK_ROOT \
    $CONTAINER \
    nextflow run $PIPELINE_REPO/bulk_rna_seq_nextflow_pipeline.nf \
        -c $PIPELINE_CONFIG \
        -w $SCRATCH_ROOT/nextflow_work
```

4. If successful, archive results:
   - `rsync -a --checksum "$SCRATCH_OUTPUT_DIR/" "$RUN_DIR/outputs/"`
   - `rsync -a --checksum "$FASTQ_DIR/" "$RUN_DIR/inputs/"`
   - Dry-run verification for integrity

#### Critical Flags

- `--cleanenv` — prevents host environment variables from leaking into the container (e.g., `$PATH`, `$PYTHONPATH`)
- `--env PYTHONNOUSERSITE=1` — prevents host `~/.local/lib/python*/` packages from shadowing container packages
- These flags exist because an early production bug caused the container's Python packages to be overridden by the host's, silently producing wrong results

#### Config Validation (`_validate_bulkrnaseq`, validate.sh lines 54-91)

Required: `project_name`, `species`, `paired_end`, `fastq_dir`, `samples_file`, `star_index`, `reference_gtf`, `run_fastqc`, `run_rna_pipeline`

Path checks: `fastq_dir`, `samples_file`, `star_index`, `reference_gtf` (and optional BED files)

Species: soft warning if not Human/Mouse/Rattus

---

### 4.4 Psoma (Submoduled Combined Container+Pipeline)

**Type:** Submoduled combined — both container definition and pipeline code live in `containers/psoma/` (pinned to v1.0.0). No separate clone needed.

**Purpose:** RNA-seq analysis for Psomagen data using HISAT2 aligner + Trimmomatic adapter trimming.

#### Key Differences from BulkRNASeq

| Aspect | BulkRNASeq | Psoma |
|--------|-----------|-------|
| Aligner | STAR | HISAT2 |
| Trimming | None | Trimmomatic (Nextera adapters) |
| Pipeline code | External UTDal repo (cloned separately) | Inside submodule (`containers/psoma/`) |
| Config directory | Scratch (symlinked UTDal files) | `$REPO_ROOT/containers/psoma` (submodule) |
| Read suffixes | `_R1_001` / `_R2_001` | `_1` / `_2` |
| Index format | STAR directory | HISAT2 prefix path |
| Extra env var | None | `--env HOME=/tmp` (Nextflow needs writable `~`) |

#### Dispatch (tjp-launch lines 326-336)

```
1. Create scratch output dir
2. Generate Nextflow config:
   _generate_psoma_config "$RUN_DIR/config.yaml" "$RUN_DIR/pipeline.config" "$SCRATCH_OUTPUT_DIR"
3. SBATCH_CONFIG_ARG = "$RUN_DIR/pipeline.config"
```

No symlink step needed — `config_directory` points directly to the submodule.

#### Nextflow Config Generation (`_generate_psoma_config`, lines 112-198)

Reads all BulkRNASeq keys plus Trimmomatic-specific parameters:
- `headcrop`, `leading`, `trailing`, `slidingwindow`, `minlen`, `illuminaclip_params`
- Auto-sets: `illumina_clip_file = $REPO_ROOT/containers/psoma/NexteraPE-PE.fa`
- Auto-sets: `output_directory = $SCRATCH_OUTPUT_DIR`

#### SLURM Execution (`slurm_templates/psoma_slurm_template.sh`)

Same structure as BulkRNASeq, with one addition:
- `--env HOME=/tmp` — Nextflow writes to `~/.nextflow` at startup; on Juno, home directories are symlinked, and Apptainer cannot resolve them. Setting `HOME=/tmp` gives Nextflow a writable location.

```bash
apptainer exec \
    --cleanenv \
    --env PYTHONNOUSERSITE=1 \
    --env HOME=/tmp \
    --env _JAVA_OPTIONS=-Xmx16g \
    --bind ... \
    $CONTAINER \
    nextflow run $PIPELINE_REPO/psomagen_bulk_rna_seq_pipeline.nf \
        -c $PIPELINE_CONFIG \
        -w $SCRATCH_ROOT/nextflow_work
```

#### Config Validation (`_validate_psoma`, validate.sh lines 94-140)

Same as BulkRNASeq except:
- Requires `hisat2_index` instead of `star_index`
- HISAT2 index validation: checks `${hisat2_index}.1.ht2` exists (index is a prefix, not a directory)

---

### 4.5 Cell Ranger (Native 10x)

**Type:** Native — no container, no Nextflow. 10x Genomics Cell Ranger binary installed at `/groups/tprice/opt/cellranger-10.0.0`.

**Purpose:** Single-cell RNA-seq gene expression analysis (alignment, barcode counting, clustering).

#### Dispatch (tjp-launch lines 337-343)

```
1. Create scratch output dir
2. SBATCH_CONFIG_ARG = "$RUN_DIR/config.yaml"   ← pass YAML directly, no Nextflow
```

Native pipelines are simpler — no config generation step.

#### SLURM Execution (`slurm_templates/cellranger_slurm_template.sh`)

```
#SBATCH --time=24:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --exclusive          ← 10x tools expect full node access
```

No `module load apptainer`. Instead:

1. Set `WRAPPER=$PROJECT_ROOT/containers/10x/bin/cellranger-run.sh`
2. Pre-flight: verify config and wrapper exist
3. Execute: `bash "$WRAPPER" "$CONFIG" "$SCRATCH_OUTPUT_DIR"`
4. Archive results on success (same rsync + verification pattern)

#### Wrapper Execution (`containers/10x/bin/cellranger-run.sh`)

The 10x submodule (`containers/10x/`, pinned to v1.1.0) provides wrapper scripts that standardize config parsing across all three 10x tools.

Step by step:

1. **Source shared library:** `source lib/10x_common.sh`
2. **Validate required keys:** `require_config_keys "$CONFIG" sample_id sample_name fastq_dir transcriptome localcores localmem`
3. **Read config values:** `yaml_get` for each key (sample_id, sample_name, fastq_dir, transcriptome, localcores, localmem, plus optional: create_bam, chemistry, expect_cells, force_cells, include_introns, no_bam, tool_path)
4. **Find binary:** `find_10x_binary "cellranger" "$tool_path"` — checks config override, then `$PATH`, then common HPC paths (`/groups/tprice/software/`, `/opt/`)
5. **Validate paths:** `require_paths_exist "$CONFIG" fastq_dir transcriptome`
6. **Change to scratch:** `cd "$SCRATCH_OUTPUT_DIR"` (Cell Ranger writes to `<cwd>/<id>/outs/`)
7. **Build command:**
```bash
cellranger count \
    --id="$sample_id" \
    --transcriptome="$transcriptome" \
    --fastqs="$fastq_dir" \
    --sample="$sample_name" \
    --localcores="$localcores" \
    --localmem="$localmem" \
    [--create-bam=$create_bam] \
    [--chemistry=$chemistry] \
    [--expect-cells=$expect_cells] \
    [--force-cells=$force_cells] \
    [--include-introns=$include_introns] \
    [--no-bam]
```
8. **Execute and exit** with Cell Ranger's exit code

#### 10x Common Library (`containers/10x/lib/10x_common.sh`)

Shared across all three 10x wrappers:

- `TENX_TOOLS=(cellranger spaceranger xeniumranger)` — tool list
- `find_10x_binary <tool> [tool_path]` — binary discovery with fallback chain
- `get_10x_version <binary>` — extract version string
- `require_config_keys <config> <keys...>` — check all keys present
- `require_paths_exist <config> <keys...>` — check all path values exist on disk
- `yaml_get`, `yaml_has` — YAML parsing (same grep-based approach as common.sh)

#### Config Validation (`_validate_cellranger`, validate.sh lines 143-188)

Required: `sample_id`, `sample_name`, `fastq_dir`, `transcriptome`, `localcores`, `localmem`, `create_bam`

Path checks: `fastq_dir`, `transcriptome`

Numeric checks: `localcores`, `localmem` must be positive integers

Optional: `tool_path` — if set, directory must exist and contain executable `cellranger` binary

---

### 4.6 Space Ranger (Native 10x)

**Type:** Native — same architecture as Cell Ranger.

**Purpose:** Spatial transcriptomics analysis for 10x Visium slides (gene expression + tissue imaging).

#### Key Differences from Cell Ranger

1. **Image input required:** Space Ranger needs a microscope image (`--image`)
2. **Slide identification:** Either `--slide` + `--area` (standard Visium) or `--unknown-slide` (unknown/non-standard slides)
3. **Additional optional images:** `cytaimage`, `darkimage`, `colorizedimage`, `loupe_alignment`, `reorient_images`

#### Wrapper Execution (`containers/10x/bin/spaceranger-run.sh`)

Same structure as Cell Ranger, with additions:

1. **Required keys include `image`** — path to microscope TIF
2. **Slide identification logic:**
```bash
if [ -n "$unknown_slide" ]; then
    CMD+=(--unknown-slide="$unknown_slide")
else
    CMD+=(--slide="$slide" --area="$area")
fi
```
3. **Command:** `spaceranger count` (same subcommand as Cell Ranger)

#### Config Validation (`_validate_spaceranger`, validate.sh lines 191-275)

Required: `sample_id`, `sample_name`, `fastq_dir`, `transcriptome`, `image`, `localcores`, `localmem`, `create_bam`

Slide logic (XOR):
- If `unknown_slide` is set: must be one of `visium-1`, `visium-2`, `visium-2-large`, `visium-hd`
- If `unknown_slide` is NOT set: both `slide` and `area` are required
  - `slide` format: starts with `V` (e.g., `V19L29-096`)
  - `area` must be: `A1`, `B1`, `C1`, or `D1`

Path checks: `fastq_dir`, `transcriptome`, `image`

---

### 4.7 Xenium Ranger (Native 10x)

**Type:** Native — same architecture as Cell Ranger / Space Ranger.

**Purpose:** Post-processing of Xenium in situ transcriptomics data (re-segmentation or external segmentation import).

#### Key Differences from Cell Ranger / Space Ranger

1. **No FASTQs:** Works on pre-computed Xenium output bundles
2. **Dual command:** Supports `resegment` or `import-segmentation` (Cell/Space Ranger only have `count`)
3. **Shorter runtime:** 12h vs 24h (post-processing, not alignment)
4. **No smoke test support** in `tjp-test` (infrastructure exists but not wired up)

#### Wrapper Execution (`containers/10x/bin/xeniumranger-run.sh`)

1. **Required keys:** `sample_id`, `command`, `xenium_bundle`, `localcores`, `localmem`
2. **Command dispatch:**

```bash
case "$command" in
    resegment)
        # Optional: expansion_distance, panel_file
        xeniumranger resegment \
            --id="$sample_id" \
            --xenium-bundle="$xenium_bundle" \
            --localcores="$localcores" \
            --localmem="$localmem" \
            [--expansion-distance=$expansion_distance] \
            [--panel-file=$panel_file]
        ;;
    import-segmentation)
        # Required: segmentation_file; Optional: viz_labels
        xeniumranger import-segmentation \
            --id="$sample_id" \
            --xenium-bundle="$xenium_bundle" \
            --segmentation="$segmentation_file" \
            --localcores="$localcores" \
            --localmem="$localmem" \
            [--viz-labels=$viz_labels]
        ;;
esac
```

#### Config Validation (`_validate_xeniumranger`, validate.sh lines 278-343)

Required: `sample_id`, `command`, `xenium_bundle`, `localcores`, `localmem`

Command validation: must be `resegment` or `import-segmentation`

Conditional: if `import-segmentation`, `segmentation_file` is required and must exist

Path checks: `xenium_bundle` must exist

#### SLURM Template

```
#SBATCH --time=12:00:00        ← shorter than cell/spaceranger
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --exclusive
```

Note: uses `INPUT_DIR` instead of `FASTQ_DIR` for archiving (Xenium input is a bundle, not FASTQs).

---

### 4.8 Virome (Native Nextflow + Per-Process Containers)

**Type:** Submoduled — `mwilde49/virome` at `containers/virome/` (pinned to v1.4.0). Nextflow runs natively on the compute node; each Nextflow process uses its own `.sif` container from `containers/virome/containers/`.

**Purpose:** Viral metagenomic profiling using Kraken2 for taxonomic classification and MetaPhlAn3 for abundance estimation.

#### Key Architectural Distinction

Virome is neither a container pipeline (no Apptainer wrapper for the head process) nor a fully native pipeline (individual processes still use containers). Nextflow is loaded as a module and runs directly on the compute node. The `--params-file` flag passes the user YAML directly to the Nextflow workflow — no intermediate config translation by `tjp-launch`.

This means:
- No `_generate_virome_config()` function in `tjp-launch`
- The YAML key names must match the Nextflow `params.*` names in the workflow exactly
- `is_nextflow_managed_pipeline("virome")` returns true, gating native-specific logic

#### Dispatch (tjp-launch)

```
1. Create scratch output dir (used as Nextflow work dir only)
2. SBATCH_CONFIG_ARG = "$RUN_DIR/config.yaml"   ← passthrough, no translation
```

No config generation. The user YAML is passed directly to Nextflow via `--params-file`.

#### SLURM Execution (`slurm_templates/virome_slurm_template.sh`)

```
#SBATCH --time=12:00:00
#SBATCH --cpus-per-task=20
#SBATCH --mem=64G
```

1. `module load nextflow apptainer`
2. Pre-flight: verify that `*.sif` container files exist in `$PROJECT_ROOT/containers/virome/containers/`; abort with a descriptive error if any are missing (common failure mode after a fresh git clone before SIF files have been staged)
3. Execute:

```bash
nextflow run $PROJECT_ROOT/containers/virome/main.nf \
    -profile juno \
    --params-file "$CONFIG" \
    -w "$SCRATCH_OUTPUT_DIR/work"
```

4. No separate stage-out step — output writes directly to `outdir:` from config (user is responsible for setting `outdir` to a persistent location, not scratch)

#### Config Validation (`_validate_virome`, validate.sh)

Required: `outdir`, `kraken2_db`, plus either `fastq_dir` (batch) or `samplesheet` (when using `tjp-batch`)

Path checks: `kraken2_db`, `outdir` parent directory must exist

#### Key Takeaway

Virome demonstrates the passthrough pattern: when a Nextflow workflow already has a well-defined `params` schema, there is no reason to add a translation layer. The user edits the YAML directly to match the Nextflow params namespace.

---

### 4.9 SQANTI3 (4-Stage SLURM DAG)

**Type:** Submoduled — `mwilde49/longreads` at `containers/sqanti3/` (pinned to current release). Uses a single `.sif` container (`containers/sqanti3/sqanti3_v5.5.4.sif`) for all four stages.

**Purpose:** Long-read isoform QC pipeline for PacBio/ONT data. Classifies isoforms against a reference annotation, filters low-confidence isoforms, and rescues those supported by additional evidence.

#### Architecture: Orchestrator + 4-Stage DAG

Unlike all other pipelines, the SLURM template for SQANTI3 is an **orchestrator**: it does not run the pipeline itself, but instead submits four dependent SLURM jobs that form a directed acyclic graph (DAG). The orchestrator job exits quickly after submitting the stage jobs.

```
sqanti3_slurm_template.sh  ←  orchestrator (exits after job submission)
    │
    ├─ SLURM job: stage_1a_qc_longreads.sh      (depends on: none)
    ├─ SLURM job: stage_1b_qc_reference.sh       (depends on: none)
    ├─ SLURM job: stage_2_filter.sh              (depends on: 1a + 1b complete)
    └─ SLURM job: stage_3_rescue.sh              (depends on: 2 complete)
```

Stage scripts live in `containers/sqanti3/slurm_templates/`. The orchestrator passes the config path and scratch output dir to each stage as positional arguments.

#### Dynamic Resource Scaling

The orchestrator reads `isoform_gtf` from the config, counts transcripts with `awk`, and passes scaled `--cpus` and `--mem` arguments to each `sbatch` call. This avoids wasting resources on small datasets while ensuring large datasets (>100k transcripts) get enough memory for the GTF parsing steps.

#### Dispatch (tjp-launch)

```
1. SBATCH_CONFIG_ARG = "$RUN_DIR/config.yaml"   ← passthrough to orchestrator
```

No config translation. The orchestrator reads the YAML directly.

#### SLURM Orchestrator (`slurm_templates/sqanti3_slurm_template.sh`)

```
#SBATCH --time=01:00:00        ← orchestrator itself is short-lived
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
```

1. Read config: `ISOFORM_GTF = yaml_get "$CONFIG" "isoform_gtf"`
2. Count transcripts: `N_TX=$(awk '/transcript_id/ {count++} END {print count}' "$ISOFORM_GTF")`
3. Scale resources: set `STAGE_CPUS` and `STAGE_MEM` based on `$N_TX` thresholds
4. Submit stage 1a and 1b in parallel (no dependency):
```bash
JOB_1A=$(sbatch --parsable \
    --cpus-per-task=$STAGE_CPUS --mem=${STAGE_MEM}G \
    containers/sqanti3/slurm_templates/stage_1a_qc_longreads.sh \
    "$CONFIG" "$SCRATCH_OUTPUT_DIR")

JOB_1B=$(sbatch --parsable \
    --cpus-per-task=$STAGE_CPUS --mem=${STAGE_MEM}G \
    containers/sqanti3/slurm_templates/stage_1b_qc_reference.sh \
    "$CONFIG" "$SCRATCH_OUTPUT_DIR")
```
5. Submit stage 2 with afterok dependency on both 1a and 1b:
```bash
JOB_2=$(sbatch --parsable \
    --dependency=afterok:${JOB_1A}:${JOB_1B} \
    containers/sqanti3/slurm_templates/stage_2_filter.sh \
    "$CONFIG" "$SCRATCH_OUTPUT_DIR")
```
6. Submit stage 3 with afterok dependency on stage 2:
```bash
JOB_3=$(sbatch --parsable \
    --dependency=afterok:${JOB_2} \
    containers/sqanti3/slurm_templates/stage_3_rescue.sh \
    "$CONFIG" "$SCRATCH_OUTPUT_DIR")
```
7. Log all four job IDs and exit

#### Stage Execution (each stage script)

Each stage script calls `apptainer exec` with the sqanti3 SIF:

```bash
apptainer exec \
    --bind $PROJECT_ROOT:$PROJECT_ROOT \
    --bind $SCRATCH_ROOT:$SCRATCH_ROOT \
    $SIF \
    python SQANTI3_qc.py [stage-specific args from config]
```

#### Container Pre-Pull Requirement

The SIF must be staged on HPC before first use — it is too large for git and is not built from a local `.def` file:

```bash
apptainer pull containers/sqanti3/sqanti3_v5.5.4.sif \
    docker://anaconesalab/sqanti3:v5.5.4
```

#### Config Validation (`_validate_sqanti3`, validate.sh)

Required: `isoform_gtf`, `isoform_fasta`, `reference_gtf`, `outdir`

Path checks: `isoform_gtf`, `isoform_fasta`, `reference_gtf` must exist; `outdir` parent must exist

---

### 4.10 wf-transcriptomes (Nextflow SLURM Executor)

**Type:** Submoduled — shares `mwilde49/longreads` at `containers/sqanti3/` with SQANTI3. The Nextflow workflow is `epi2me-labs/wf-transcriptomes`, fetched by Nextflow at runtime.

**Purpose:** End-to-end ONT full-length transcript analysis: basecalling QC, alignment, assembly, abundance, fusion detection, and differential expression.

#### Architecture: Head Job + Dynamic Sub-Jobs

This is the most complex execution model in the framework. A single SLURM head job runs Nextflow on a compute node. Nextflow is configured with `executor = 'slurm'`, so each Nextflow process submits its own SLURM job. The compute topology is dynamic: the head job coordinates dozens of sub-jobs that run on separate compute nodes.

```
SLURM head job (wf_transcriptomes_slurm_template.sh)
    │
    └─ Nextflow process manager (running on head compute node)
           │
           ├─ sbatch → SLURM sub-job: minimap2 alignment
           ├─ sbatch → SLURM sub-job: StringTie assembly
           ├─ sbatch → SLURM sub-job: salmon quantification
           ├─ sbatch → SLURM sub-job: JAFFAL fusion detection
           └─ ... (each process = one SLURM job)
```

**Critical constraint:** The head job must stay alive for the entire duration. If the head job is cancelled or times out before sub-jobs complete, Nextflow cannot collect results and the run fails. The head job's walltime (`24:00:00`) must exceed the total expected runtime including queueing delays for sub-jobs.

#### Nextflow SLURM Executor Config

The executor configuration lives at `containers/sqanti3/configs/wf_transcriptomes/juno.config`:

```groovy
executor {
    name = 'slurm'
    queueSize = 50
    submitRateLimit = '10 sec'
}

process {
    queue = 'normal'
    clusterOptions = '--account=tprice'
}
```

This file is passed to Nextflow via `-c` alongside the pipeline's built-in config.

#### Dispatch (tjp-launch)

```
1. SBATCH_CONFIG_ARG = "$RUN_DIR/config.yaml"   ← passthrough to head job
```

No config translation. The user YAML is passed directly to wf-transcriptomes via `--params-file`.

#### SLURM Head Job (`slurm_templates/wf_transcriptomes_slurm_template.sh`)

```
#SBATCH --time=24:00:00        ← must outlast all sub-jobs
#SBATCH --cpus-per-task=2      ← head job is coordinator, not worker
#SBATCH --mem=8G
```

1. `module load nextflow`
2. Read `wf_version` from config (default: `v1.7.2`)
3. Execute:

```bash
nextflow run epi2me-labs/wf-transcriptomes \
    -r "$wf_version" \
    -c "$PROJECT_ROOT/containers/sqanti3/configs/wf_transcriptomes/juno.config" \
    --params-file "$CONFIG" \
    -w "$SCRATCH_OUTPUT_DIR/work"
```

4. No separate stage-out — output goes directly to `outdir:` from config

#### EPI2ME Samplesheet

The `sample_sheet:` key in config points to an EPI2ME-format CSV that maps barcode directories to sample names. This is passed directly to wf-transcriptomes and is distinct from the framework's own samplesheet format. The `samplesheet_*` functions in `bin/lib/samplesheet.sh` are not used for this internal EPI2ME file.

#### Pipeline Version Pinning

The `wf_version` key in config controls which release of wf-transcriptomes Nextflow fetches. Default is `v1.7.2`. Nextflow caches the workflow locally under `$NXF_HOME`, so the first run on a given node will be slower while it fetches; subsequent runs use the cache.

#### Config Validation (`_validate_wf_transcriptomes`, validate.sh)

Required: `sample_sheet`, `outdir`, `ref_genome`, `ref_annotation`

Path checks: `sample_sheet`, `ref_genome`, `ref_annotation` must exist

Format check: `wf_version` (if set) must match `v[0-9]+\.[0-9]+\.[0-9]+`

---

## 5. Pipeline Comparison Matrix

### Execution Model

| Pipeline | Container | Pipeline Engine | Config Transform | Exclusive Node |
|----------|-----------|----------------|-----------------|----------------|
| AddOne | `.sif` (inline) | Python script | None (pass YAML) | No |
| BulkRNASeq | `.sif` (submodule) | Nextflow | YAML → `pipeline.config` | No |
| Psoma | `.sif` (submodule) | Nextflow | YAML → `pipeline.config` | No |
| Cell Ranger | Native binary | Self-managed | None (pass YAML) | Yes |
| Space Ranger | Native binary | Self-managed | None (pass YAML) | Yes |
| Xenium Ranger | Native binary | Self-managed | None (pass YAML) | Yes |
| Virome | Per-process `.sif` | Nextflow (native head) | None (params-file passthrough) | No |
| SQANTI3 | `.sif` (submodule) | SLURM DAG (orchestrator) | None (pass YAML) | No |
| wf-transcriptomes | Nextflow-managed | Nextflow (SLURM executor) | None (params-file passthrough) | No |

### Data Flow

| Pipeline | Input Type | Primary Command | Special Input |
|----------|-----------|----------------|---------------|
| AddOne | Text file | `python addone.py` | None |
| BulkRNASeq | FASTQs | `nextflow run` | STAR index |
| Psoma | FASTQs | `nextflow run` | HISAT2 index + Nextera adapters |
| Cell Ranger | FASTQs | `cellranger count` | Transcriptome reference |
| Space Ranger | FASTQs + Image | `spaceranger count` | Slide/area + microscope image |
| Xenium Ranger | Xenium bundle | `xeniumranger resegment` or `import-segmentation` | Segmentation file (import only) |
| Virome | FASTQs | `nextflow run` (Kraken2/MetaPhlAn3) | Kraken2 database |
| SQANTI3 | Isoform GTF + FASTA | `python SQANTI3_qc.py` (4 stages) | Reference GTF |
| wf-transcriptomes | ONT FASTQ dirs | `nextflow run` (wf-transcriptomes) | EPI2ME samplesheet, genome + annotation |

### Container Flags

| Flag | Purpose | Used By |
|------|---------|---------|
| `--cleanenv` | Block host env vars from entering container | BulkRNASeq, Psoma |
| `--env PYTHONNOUSERSITE=1` | Block host Python packages | BulkRNASeq, Psoma |
| `--env HOME=/tmp` | Writable home for Nextflow | Psoma |
| `--env _JAVA_OPTIONS=-Xmx16g` | Java heap limit | Psoma |
| `--bind` | Mount host paths into container | All container pipelines, SQANTI3 |
| `--exclusive` | Full node access | All native pipelines (10x) |

### Stage-Out Behavior

| Pipeline | Outputs Written To | Archived to Work Dir? |
|----------|-------------------|----------------------|
| AddOne | Scratch (via config) | No (addone is a demo) |
| BulkRNASeq | Scratch → `outputs/` | Yes (rsync + checksum) |
| Psoma | Scratch → `outputs/` | Yes (rsync + checksum) |
| Cell Ranger | Scratch → `outputs/` | Yes (rsync + checksum) |
| Space Ranger | Scratch → `outputs/` | Yes (rsync + checksum) |
| Xenium Ranger | Scratch → `outputs/` | Yes (rsync + checksum) |
| Virome | `outdir:` from config | No (user sets outdir directly) |
| SQANTI3 | `outdir:` from config | No (user sets outdir directly) |
| wf-transcriptomes | `outdir:` from config | No (user sets outdir directly) |

---

## 6. Testing Infrastructure

### Smoke Testing (`tjp-test`)

Verifies a pipeline works end-to-end with pre-bundled test data on the dev partition.

**Currently supported:** `psoma`, `bulkrnaseq`, `cellranger`, `spaceranger`

**Not yet supported:** `xeniumranger` (infrastructure exists, not wired up), `addone`, `virome`, `sqanti3`, `wf-transcriptomes` (test data must be staged on HPC first)

**How it works:**

1. Copies test FASTQs to scratch (with pipeline-specific naming conventions):
   - Psoma: `_1.fastq.gz` / `_2.fastq.gz` (as-is)
   - BulkRNASeq: renames `_1.fastq.gz` → `_R1_001.fastq.gz`
   - 10x: standard Illumina naming (as-is)
   - Space Ranger: copies bundled tiny inputs from SpaceRanger install directory

2. Generates a test config YAML with hardcoded parameters

3. Delegates to `tjp-launch --dev` (submits to dev partition with 2h limit)

**Test data locations:**
- RNA-seq: `$REPO_ROOT/test_data/rnaseq/fastq/` (gitignored, generated on HPC)
- 10x: `$REPO_ROOT/test_data/10x/<tool>/`
- Space Ranger: uses bundled tiny inputs from SpaceRanger install dir
- SQANTI3: `containers/sqanti3/SQANTI3/data/` (must be staged manually on HPC)
- wf-transcriptomes: `containers/sqanti3/test_data/wf_transcriptomes/` (must be staged manually on HPC)

### Output Validation (`tjp-test-validate`)

Checks expected output directories and files after a smoke test completes.

**Expected outputs per pipeline:**

| Pipeline | Expected Directories | Key Files |
|----------|---------------------|-----------|
| Psoma | `2_trim_output/`, `3_hisat2_mapping_output/`, `4_filter_output/`, `5_stringtie_counts_output/`, `6_raw_counts_output/` | BAM, counts |
| BulkRNASeq | `2_star_mapping_output/`, `3_filter_output/`, `4_stringtie_counts_output/`, `5_raw_counts_output/` | BAM, counts |
| Cell Ranger | `<sample_id>/outs/` | `filtered_feature_bc_matrix/`, `web_summary.html`, `metrics_summary.csv` |
| Space Ranger | `<sample_id>/outs/spatial/` | `tissue_positions.csv`, `scalefactors_json.json`, feature matrices |

Reports pass/fail with file counts and sizes. Exits 0 if all pass, 1 if any fail.

### Binary Smoke Tests (`containers/10x/test/`)

Independent of `tjp-test`. These test that 10x binaries are discoverable and functional:

- `test_cellranger.sh` — binary discovery → version → `count --help` → sitecheck
- `test_spaceranger.sh` — binary discovery → version → `count --help` → sitecheck
- `test_xeniumranger.sh` — binary discovery → version → `resegment --help` + `import-segmentation --help`

---

## 7. Adding a New Pipeline

### Inline Pipeline (like AddOne)

1. Create `pipelines/<name>/` with your script and a README
2. Add or extend a container definition in `containers/` if new dependencies are needed, rebuild `.sif`
3. Add `slurm_templates/<name>_slurm_template.sh` (copy addone template, adjust resources)
4. Add `templates/<name>/config.yaml` with `__USER__`/`__SCRATCH__`/`__WORK__` placeholders
5. Register in `bin/lib/common.sh`:
   - `PIPELINE_CONTAINERS[<name>]="containers/<sif_file>"`
   - `PIPELINE_TEMPLATES[<name>]="slurm_templates/<name>_slurm_template.sh"`
   - Add to `KNOWN_PIPELINES`
6. Add `_validate_<name>()` in `bin/lib/validate.sh` and wire it into the dispatcher
7. Add input/output path extraction in `manifest.sh`
8. Add dispatch case in `tjp-launch`
9. Transfer `.sif` to HPC via `scp` (not tracked in git)

### Submoduled Pipeline (like BulkRNASeq)

Same as above, plus:
1. `git submodule add <url> containers/<name>/` and pin to a release tag
2. If pipeline code is in a third-party repo, document the clone step
3. Add Nextflow config template in `templates/<name>/pipeline.config.tmpl` if using Nextflow
4. Add `_generate_<name>_config()` function in `tjp-launch` for config transformation

### Native Pipeline (like Cell Ranger)

1. Install the tool from tarball to `/groups/tprice/opt/<name>/`
2. Add wrapper to the 10x submodule: `containers/10x/bin/<name>-run.sh`
3. Add validator: `containers/10x/lib/validate_<name>.sh`
4. Register in `bin/lib/common.sh`:
   - `PIPELINE_TOOL_PATHS[<name>]="/groups/tprice/opt/<tool_dir>"`
   - Add to `NATIVE_PIPELINES` array
   - Add to `KNOWN_PIPELINES`
5. Add SLURM template with `--exclusive` flag
6. Add `is_native_pipeline()` gates in any shared code that assumes containers

### For All Pipeline Types

After completing the type-specific steps above, complete these framework-wide registrations:

**`bin/lib/common.sh`:**
- Add to `KNOWN_PIPELINES` array (required for all validation and dispatch)
- Add container/tool path to `PIPELINE_CONTAINERS` or `PIPELINE_TOOL_PATHS`
- If using Nextflow as the head-job executor, add to `NEXTFLOW_MANAGED_PIPELINES`

**`bin/lib/samplesheet.sh`:**
- Add required samplesheet columns to `_SAMPLESHEET_REQUIRED_COLS[<name>]`
- If `tjp-batch` needs special per-row or per-sheet logic, add a case to the batch dispatch

**`bin/lib/validate.sh`:**
- Add a `_validate_<name>()` function implementing all required-key and path checks
- Wire into the `validate_config()` dispatcher

**`bin/tjp-batch`:**
- Add the pipeline to either the per-row or per-sheet dispatch case
- Implement any per-row config injection or per-sheet config augmentation needed

**Templates:**
- Add config template at `templates/<name>/config.yaml` with the Titan block:
  ```yaml
  # Optional: Titan metadata fields (leave blank to skip registration)
  titan_project_id:
  titan_sample_id:
  titan_library_id:
  titan_run_id:
  ```
- Add samplesheet template at `templates/<name>/samplesheet.csv` with all required columns as a header row plus one example data row

---

## 8. HPC Environment

### Path Conventions

| What | Path |
|------|------|
| Shared pipelines repo | `/groups/tprice/pipelines` |
| Native tool installs | `/groups/tprice/opt/<tool>` |
| User work directory | `/work/$USER` |
| User scratch directory | `/scratch/juno/$USER` |
| User pipeline workspace | `/work/$USER/pipelines/<pipeline>/` |
| Run archives | `/work/$USER/pipelines/<pipeline>/runs/<timestamp>/` |
| Pipeline execution | `/scratch/juno/$USER/pipelines/<pipeline>/runs/<timestamp>/` |
| Metadata store | `/work/$USER/pipelines/metadata/` |

### Run Directory Structure

Each `tjp-launch` creates a timestamped run directory:

```
/work/$USER/pipelines/<pipeline>/runs/<timestamp>/
├── config.yaml              ← snapshot of config at launch time
├── pipeline.config          ← generated Nextflow config (container pipelines only)
├── manifest.json            ← reproducibility record (includes titan_pipeline_run_id if registered)
├── slurm_<jobid>.out        ← SLURM stdout
├── slurm_<jobid>.err        ← SLURM stderr
├── inputs/                  ← archived input files (post-run rsync, where applicable)
└── outputs/                 ← archived results (post-run rsync, where applicable)
```

Pipelines that write directly to `outdir:` (virome, sqanti3, wf-transcriptomes) do not populate `inputs/` or `outputs/` subdirectories.

### Important: Symlinked Home Directories

Juno uses symlinked home directories. Apptainer bind mounts require **real paths** — always resolve with `readlink -f` before passing to Apptainer. The SLURM templates handle this by using absolute paths (`/groups/tprice/pipelines`, `/scratch/juno/$USER`, `/work/$USER`), not `$HOME`-relative paths.

This is also why Psoma's SLURM template sets `--env HOME=/tmp` — Nextflow tries to write to `~/.nextflow`, but `~` resolves to a symlink that Apptainer cannot follow.

### Bash Gotcha: Arithmetic in `set -e` Scripts

`((var++))` returns exit code 1 when `var` equals 0, which causes immediate script termination under `set -e`. Use `var=$((var + 1))` instead. This applies to all counter increments in SLURM templates and CLI tools.

---

## 9. Key Files Reference

### CLI Tools

| File | Purpose |
|------|---------|
| `bin/tjp-setup` | One-time workspace initialization |
| `bin/tjp-launch` | Main launch orchestrator |
| `bin/tjp-batch` | Batch submission from CSV samplesheet |
| `bin/tjp-test` | Smoke test with bundled data |
| `bin/tjp-test-validate` | Verify smoke test outputs |
| `bin/tjp-validate` | Config-only validation |
| `bin/labdata` | Metadata management CLI (find/show PLR-xxxx records) |

### Shared Libraries

| File | Purpose |
|------|---------|
| `bin/lib/common.sh` | Pipeline registry, YAML helpers, logging, path functions |
| `bin/lib/validate.sh` | Per-pipeline config validators |
| `bin/lib/manifest.sh` | Reproducibility manifest generation |
| `bin/lib/branding.sh` | Hyperion Compute themed output |
| `bin/lib/samplesheet.sh` | CSV samplesheet validation and parsing |
| `bin/lib/metadata.sh` | PLR-xxxx generation and local JSON metadata store |

### SLURM Templates

| File | Resources |
|------|-----------|
| `slurm_templates/addone_slurm_template.sh` | 5min, 1 CPU, 1GB |
| `slurm_templates/bulkrnaseq_slurm_template.sh` | 12h, 40 CPU, 128GB |
| `slurm_templates/psoma_slurm_template.sh` | 12h, 40 CPU, 128GB |
| `slurm_templates/cellranger_slurm_template.sh` | 24h, 16 CPU, 128GB, exclusive |
| `slurm_templates/spaceranger_slurm_template.sh` | 24h, 16 CPU, 128GB, exclusive |
| `slurm_templates/xeniumranger_slurm_template.sh` | 12h, 16 CPU, 128GB, exclusive |
| `slurm_templates/virome_slurm_template.sh` | 12h, 20 CPU, 64GB |
| `slurm_templates/sqanti3_slurm_template.sh` | 1h orchestrator; stage resources dynamic |
| `slurm_templates/wf_transcriptomes_slurm_template.sh` | 24h head job, 2 CPU, 8GB |

### Config Templates

| File | Key Required Fields |
|------|-------------------|
| `templates/addone/config.yaml` | `input`, `output` |
| `templates/bulkrnaseq/config.yaml` | `project_name`, `fastq_dir`, `star_index`, `reference_gtf` |
| `templates/psoma/config.yaml` | `project_name`, `fastq_dir`, `hisat2_index`, `reference_gtf` |
| `templates/cellranger/config.yaml` | `sample_id`, `fastq_dir`, `transcriptome`, `create_bam` |
| `templates/spaceranger/config.yaml` | `sample_id`, `fastq_dir`, `transcriptome`, `image`, `slide`/`area` |
| `templates/xeniumranger/config.yaml` | `sample_id`, `command`, `xenium_bundle` |
| `templates/virome/config.yaml` | `outdir`, `kraken2_db`, `fastq_dir` |
| `templates/sqanti3/config.yaml` | `isoform_gtf`, `isoform_fasta`, `reference_gtf`, `outdir` |
| `templates/wf_transcriptomes/config.yaml` | `sample_sheet`, `outdir`, `ref_genome`, `ref_annotation` |

### Samplesheet Templates

| File | Required Columns |
|------|-----------------|
| `templates/bulkrnaseq/samplesheet.csv` | `sample_name`, `fastq_1`, `fastq_2` |
| `templates/psoma/samplesheet.csv` | `sample_name`, `fastq_1`, `fastq_2` |
| `templates/cellranger/samplesheet.csv` | `sample_id`, `sample_name`, `fastq_dir`, `transcriptome` |
| `templates/spaceranger/samplesheet.csv` | `sample_id`, `sample_name`, `fastq_dir`, `transcriptome`, `image` |
| `templates/xeniumranger/samplesheet.csv` | `sample_id`, `command`, `xenium_bundle` |
| `templates/virome/samplesheet.csv` | `sample_id`, `fastq_1`, `fastq_2` |
| `templates/sqanti3/samplesheet.csv` | `sample_id`, `isoform_gtf`, `isoform_fasta` |
| `templates/wf_transcriptomes/samplesheet.csv` | `sample_id`, `barcode_dir` (EPI2ME format) |

### Submodules

| Path | Repo | Version | Contains |
|------|------|---------|----------|
| `containers/bulkrnaseq/` | `mwilde49/bulkseq` | v1.0.0 | Container def + build scripts |
| `containers/psoma/` | `mwilde49/psoma` | v1.0.0 | Container def + pipeline code + adapters |
| `containers/10x/` | `mwilde49/10x` | v1.1.0 | Wrapper scripts, validators, tests |
| `containers/virome/` | `mwilde49/virome` | v1.4.0 | Nextflow workflow + per-process container defs |
| `containers/sqanti3/` | `mwilde49/longreads` | current | SQANTI3 + wf-transcriptomes configs + stage scripts |

### Pipeline Code

| File | Language | Purpose |
|------|----------|---------|
| `pipelines/addone/addone.py` | Python | Demo pipeline (add 1 to numbers) |
| `containers/psoma/psomagen_bulk_rna_seq_pipeline.nf` | Nextflow | Psoma RNA-seq pipeline |
| `Bulk-RNA-Seq-Nextflow-Pipeline/bulk_rna_seq_nextflow_pipeline.nf` | Nextflow | UTDal bulk RNA-seq (external clone) |
| `containers/10x/bin/cellranger-run.sh` | Bash | Cell Ranger wrapper |
| `containers/10x/bin/spaceranger-run.sh` | Bash | Space Ranger wrapper |
| `containers/10x/bin/xeniumranger-run.sh` | Bash | Xenium Ranger wrapper |
| `containers/virome/main.nf` | Nextflow | Virome viral profiling workflow |
| `containers/sqanti3/slurm_templates/` | Bash | SQANTI3 stage scripts (4 stages) |

### References (Shared Data)

| Path | Purpose |
|------|---------|
| `/groups/tprice/pipelines/references/gencode.v48.primary_assembly.annotation.gtf` | Gene annotation |
| `/groups/tprice/pipelines/references/filter.bed` | Genomic region filter |
| `/groups/tprice/pipelines/references/blacklist.bed` | Blacklisted regions |
| `/groups/tprice/pipelines/references/hisat2_index/` | HISAT2 genome index |
| `/groups/tprice/pipelines/references/star_index/` | STAR genome index |

### Metadata

| Path | Purpose |
|------|---------|
| `/work/$USER/pipelines/metadata/` | Local PLR-xxxx JSON records |
| `metadata/SCHEMA.md` | Titan metadata format reference |

---

## Appendix A: Execution Flow Diagrams

Detailed nesting and timeline for each pipeline, showing every layer from user command to tool execution.

### A.1 AddOne (Inline Container)

```
USER LOGIN NODE
│
├─ tjp-launch addone
│   ├─ 1. source lib/common.sh, validate.sh, manifest.sh, metadata.sh
│   ├─ 2. validate_config() → _validate_addone()
│   │      checks: input file exists, output key present
│   ├─ 3. create /work/$USER/pipelines/addone/runs/<timestamp>/
│   ├─ 4. cp config.yaml → run dir (snapshot)
│   ├─ 5. generate_manifest() → manifest.json
│   ├─ 6. sbatch addone_slurm_template.sh config.yaml
│   │      ════════════════════════════════════════════════
│   │      HANDOFF — control leaves login node, enters SLURM queue
│   │      ════════════════════════════════════════════════
│   └─ 7. extract job ID, update manifest, print summary

COMPUTE NODE (allocated by SLURM: 1 CPU, 1GB, 5min)
│
├─ addone_slurm_template.sh
│   ├─ 8. module load apptainer
│   ├─ 9. apptainer exec \
│   │       --bind $PROJECT_ROOT --bind $SCRATCH_ROOT --bind $WORK_ROOT \
│   │       $CONTAINER \
│   │       ════════════════════════════════════════════════
│   │       HANDOFF — enters sealed container
│   │       ════════════════════════════════════════════════
│   │
│   │   INSIDE CONTAINER (.sif — python:3.11-slim + pyyaml)
│   │   │
│   │   └─ 10. python addone.py --config config.yaml
│   │          ├─ load YAML config
│   │          ├─ read input file → list of numbers
│   │          ├─ add 1 to each number
│   │          └─ write output file
│   │
│   └─ container exits, SLURM template ends
│
DONE — job exits, SLURM releases node

Nesting depth: 3 layers
  tjp-launch → SLURM template → Apptainer → Python script
```

### A.2 BulkRNASeq (Submoduled Container + External Nextflow)

```
USER LOGIN NODE
│
├─ tjp-launch bulkrnaseq
│   ├─ 1. source lib/common.sh, validate.sh, manifest.sh, metadata.sh
│   ├─ 2. validate_config() → _validate_bulkrnaseq()
│   │      checks: fastq_dir exists, samples_file exists,
│   │      star_index exists, reference_gtf exists
│   ├─ 3. create /work/$USER/pipelines/bulkrnaseq/runs/<timestamp>/
│   ├─ 4. cp config.yaml → run dir (snapshot)
│   ├─ 5. create /scratch/juno/$USER/pipelines/bulkrnaseq/runs/<timestamp>/
│   ├─ 6. symlink UTDal repo files into scratch dir
│   │      ln -sf $REPO_ROOT/Bulk-RNA-Seq-Nextflow-Pipeline/* → scratch/
│   ├─ 7. _generate_nextflow_config()
│   │      reads user YAML → sed substitutes into pipeline.config.tmpl
│   │      → writes run dir/pipeline.config
│   │      (references wired in here: star_index, reference_gtf,
│   │       filter.bed, blacklist.bed)
│   ├─ 8. generate_manifest() → manifest.json
│   ├─ 9. sbatch bulkrnaseq_slurm_template.sh pipeline.config run_dir scratch_dir fastq_dir
│   │      ════════════════════════════════════════════════
│   │      HANDOFF — control leaves login node, enters SLURM queue
│   │      ════════════════════════════════════════════════
│   └─ 10. extract job ID, update manifest, register Titan metadata (if titan_* present)

COMPUTE NODE (allocated by SLURM: 40 CPU, 128GB, 12h)
│
├─ bulkrnaseq_slurm_template.sh
│   ├─ 11. module load apptainer
│   ├─ 12. pre-flight: container exists? UTDal repo exists? config exists?
│   ├─ 13. apptainer exec \
│   │       --cleanenv \
│   │       --env PYTHONNOUSERSITE=1 \
│   │       --bind $PROJECT_ROOT --bind $SCRATCH_ROOT --bind $WORK_ROOT \
│   │       $CONTAINER \
│   │       ════════════════════════════════════════════════
│   │       HANDOFF — enters sealed container
│   │       ════════════════════════════════════════════════
│   │
│   │   INSIDE CONTAINER (.sif)
│   │   │
│   │   ├─ 14. nextflow run bulk_rna_seq_nextflow_pipeline.nf \
│   │   │       -c pipeline.config \
│   │   │       -w /scratch/juno/$USER/nextflow_work
│   │   │
│   │   │   NEXTFLOW ORCHESTRATES THESE STAGES:
│   │   │   │
│   │   │   ├─ 15. FastQC (if run_fastqc=true)
│   │   │   │      reads: fastq_dir/*.fastq.gz
│   │   │   │      → QC reports
│   │   │   │
│   │   │   ├─ 16. STAR alignment
│   │   │   │      reads: fastq_dir/*.fastq.gz
│   │   │   │      uses:  star_index (reference genome index)
│   │   │   │      uses:  reference_gtf (gene annotation)
│   │   │   │      → sorted BAM files
│   │   │   │
│   │   │   ├─ 17. Filtering
│   │   │   │      reads: BAM files from step 16
│   │   │   │      uses:  filter.bed (genomic regions to exclude)
│   │   │   │      uses:  blacklist.bed (blacklisted regions)
│   │   │   │      → filtered BAM files
│   │   │   │
│   │   │   ├─ 18. StringTie quantification
│   │   │   │      reads: filtered BAMs from step 17
│   │   │   │      uses:  reference_gtf
│   │   │   │      → transcript-level counts
│   │   │   │
│   │   │   └─ 19. featureCounts (raw counts)
│   │   │          reads: filtered BAMs from step 17
│   │   │          uses:  reference_gtf
│   │   │          → gene-level count matrix
│   │   │
│   │   └─ Nextflow exits
│   │       ════════════════════════════════════════════════
│   │       HANDOFF — exits container, back to SLURM template
│   │       ════════════════════════════════════════════════
│   │
│   ├─ 20. check pipeline exit code (fail → skip archive, exit)
│   ├─ 21. rsync --checksum scratch outputs → run dir/outputs/
│   ├─ 22. rsync --checksum fastq_dir → run dir/inputs/
│   └─ 23. dry-run rsync verification → pass/fail
│
DONE — job exits, SLURM releases node

Nesting depth: 4 layers
  tjp-launch → SLURM template → Apptainer → Nextflow → tools (STAR, samtools, etc.)
```

### A.3 Psoma (Submoduled Combined Container+Pipeline)

```
USER LOGIN NODE
│
├─ tjp-launch psoma
│   ├─ 1. source lib/common.sh, validate.sh, manifest.sh, metadata.sh
│   ├─ 2. validate_config() → _validate_psoma()
│   │      checks: fastq_dir, samples_file, reference_gtf exist
│   │      checks: hisat2_index prefix valid (${index}.1.ht2 exists)
│   ├─ 3. create /work/$USER/pipelines/psoma/runs/<timestamp>/
│   ├─ 4. cp config.yaml → run dir (snapshot)
│   ├─ 5. create /scratch/juno/$USER/pipelines/psoma/runs/<timestamp>/
│   ├─ 6. _generate_psoma_config()
│   │      reads user YAML → sed substitutes into pipeline.config.tmpl
│   │      → writes run dir/pipeline.config
│   │      auto-sets: config_directory = $REPO_ROOT/containers/psoma
│   │      auto-sets: illumina_clip_file = .../NexteraPE-PE.fa
│   │      auto-sets: output_directory = scratch output dir
│   │      (references: hisat2_index, reference_gtf, filter.bed, blacklist.bed)
│   ├─ 7. generate_manifest() → manifest.json
│   ├─ 8. sbatch psoma_slurm_template.sh pipeline.config run_dir scratch_dir fastq_dir
│   │      ════════════════════════════════════════════════
│   │      HANDOFF — control leaves login node, enters SLURM queue
│   │      ════════════════════════════════════════════════
│   └─ 9. extract job ID, update manifest, register Titan metadata (if titan_* present)

COMPUTE NODE (allocated by SLURM: 40 CPU, 128GB, 12h)
│
├─ psoma_slurm_template.sh
│   ├─ 10. module load apptainer
│   ├─ 11. pre-flight: container exists? submodule exists? config exists?
│   ├─ 12. apptainer exec \
│   │       --cleanenv \
│   │       --env PYTHONNOUSERSITE=1 \
│   │       --env HOME=/tmp \
│   │       --env _JAVA_OPTIONS=-Xmx16g \
│   │       --bind $PROJECT_ROOT --bind $SCRATCH_ROOT --bind $WORK_ROOT \
│   │       $CONTAINER \
│   │       ════════════════════════════════════════════════
│   │       HANDOFF — enters sealed container
│   │       ════════════════════════════════════════════════
│   │
│   │   INSIDE CONTAINER (.sif)
│   │   │
│   │   ├─ 13. nextflow run psomagen_bulk_rna_seq_pipeline.nf \
│   │   │       -c pipeline.config \
│   │   │       -w /scratch/juno/$USER/nextflow_work
│   │   │
│   │   │   NEXTFLOW ORCHESTRATES THESE STAGES:
│   │   │   │
│   │   │   ├─ 14. FastQC (if run_fastqc=true)
│   │   │   │      reads: fastq_dir/*.fastq.gz
│   │   │   │      → QC reports
│   │   │   │
│   │   │   ├─ 15. Trimmomatic adapter/quality trimming
│   │   │   │      reads: fastq_dir/*.fastq.gz
│   │   │   │      uses:  NexteraPE-PE.fa (Nextera adapters, from submodule)
│   │   │   │      params: headcrop, leading, trailing, slidingwindow, minlen
│   │   │   │      → trimmed FASTQ files
│   │   │   │
│   │   │   ├─ 16. HISAT2 alignment
│   │   │   │      reads: trimmed FASTQs from step 15
│   │   │   │      uses:  hisat2_index (prefix path, e.g., /path/to/gencode48)
│   │   │   │      uses:  reference_gtf (gene annotation)
│   │   │   │      → sorted BAM files
│   │   │   │
│   │   │   ├─ 17. Filtering
│   │   │   │      reads: BAM files from step 16
│   │   │   │      uses:  filter.bed, blacklist.bed
│   │   │   │      → filtered BAM files
│   │   │   │
│   │   │   ├─ 18. StringTie quantification
│   │   │   │      reads: filtered BAMs from step 17
│   │   │   │      uses:  reference_gtf
│   │   │   │      → transcript-level counts
│   │   │   │
│   │   │   └─ 19. featureCounts (raw counts)
│   │   │          reads: filtered BAMs from step 17
│   │   │          uses:  reference_gtf
│   │   │          → gene-level count matrix
│   │   │
│   │   └─ Nextflow exits
│   │       ════════════════════════════════════════════════
│   │       HANDOFF — exits container, back to SLURM template
│   │       ════════════════════════════════════════════════
│   │
│   ├─ 20. check pipeline exit code
│   ├─ 21. rsync --checksum scratch outputs → run dir/outputs/
│   ├─ 22. rsync --checksum fastq_dir → run dir/inputs/
│   └─ 23. dry-run rsync verification → pass/fail
│
DONE — job exits, SLURM releases node

Nesting depth: 4 layers
  tjp-launch → SLURM template → Apptainer → Nextflow → tools (HISAT2, Trimmomatic, samtools, etc.)

Key differences from BulkRNASeq:
  - HISAT2 instead of STAR (prefix-path index, not directory)
  - Trimmomatic step added before alignment (step 15)
  - --env HOME=/tmp (Nextflow needs writable ~)
  - --env _JAVA_OPTIONS=-Xmx16g (Java heap limit)
  - config_directory points to submodule, not symlinked UTDal files
  - No symlink step (pipeline code is in the submodule itself)
  - Read suffixes: _1/_2 instead of _R1_001/_R2_001
```

### A.4 Cell Ranger (Native 10x)

```
USER LOGIN NODE
│
├─ tjp-launch cellranger
│   ├─ 1. source lib/common.sh, validate.sh, manifest.sh, metadata.sh
│   ├─ 2. validate_config() → _validate_cellranger()
│   │      checks: sample_id, sample_name, fastq_dir, transcriptome,
│   │      localcores, localmem, create_bam present
│   │      checks: fastq_dir, transcriptome paths exist
│   │      checks: localcores, localmem are positive integers
│   ├─ 3. is_native_pipeline("cellranger") → true
│   │      CONTAINER = "native:/groups/tprice/opt/cellranger-10.0.0"
│   ├─ 4. create /work/$USER/pipelines/cellranger/runs/<timestamp>/
│   ├─ 5. cp config.yaml → run dir (snapshot)
│   ├─ 6. create /scratch/juno/$USER/pipelines/cellranger/runs/<timestamp>/
│   ├─ 7. SBATCH_CONFIG_ARG = config.yaml (no Nextflow config generation)
│   ├─ 8. generate_manifest() → manifest.json
│   │      container_file: "native:/groups/tprice/opt/cellranger-10.0.0"
│   │      container_checksum: tool version string
│   ├─ 9. sbatch cellranger_slurm_template.sh config.yaml run_dir scratch_dir fastq_dir
│   │      ════════════════════════════════════════════════
│   │      HANDOFF — control leaves login node, enters SLURM queue
│   │      ════════════════════════════════════════════════
│   └─ 10. extract job ID, update manifest, register Titan metadata (if titan_* present)

COMPUTE NODE (allocated by SLURM: 16 CPU, 128GB, 24h, EXCLUSIVE)
│
├─ cellranger_slurm_template.sh
│   │
│   │  (no module load apptainer — native pipeline)
│   │
│   ├─ 11. pre-flight: config exists? wrapper script exists?
│   ├─ 12. bash containers/10x/bin/cellranger-run.sh config.yaml scratch_dir
│   │       ════════════════════════════════════════════════
│   │       HANDOFF — enters 10x wrapper script
│   │       ════════════════════════════════════════════════
│   │
│   │   WRAPPER SCRIPT (cellranger-run.sh)
│   │   │
│   │   ├─ 13. source lib/10x_common.sh
│   │   ├─ 14. require_config_keys: sample_id, sample_name, fastq_dir,
│   │   │      transcriptome, localcores, localmem
│   │   ├─ 15. yaml_get each config value (+ optional: create_bam,
│   │   │      chemistry, expect_cells, force_cells, include_introns, no_bam)
│   │   ├─ 16. find_10x_binary "cellranger" "$tool_path"
│   │   │      checks: config tool_path → $PATH → common HPC paths
│   │   │      → /groups/tprice/opt/cellranger-10.0.0/cellranger
│   │   ├─ 17. require_paths_exist: fastq_dir, transcriptome
│   │   ├─ 18. cd "$SCRATCH_OUTPUT_DIR"
│   │   │      (Cell Ranger writes to <cwd>/<id>/outs/)
│   │   ├─ 19. build command:
│   │   │      cellranger count \
│   │   │          --id=$sample_id \
│   │   │          --transcriptome=$transcriptome \
│   │   │          --fastqs=$fastq_dir \
│   │   │          --sample=$sample_name \
│   │   │          --localcores=$localcores \
│   │   │          --localmem=$localmem \
│   │   │          [--create-bam=$create_bam] \
│   │   │          [--chemistry=$chemistry] ...
│   │   ├─ 20. EXECUTE cellranger count
│   │   │      Cell Ranger manages its own threading internally
│   │   │      → $SCRATCH_OUTPUT_DIR/$sample_id/outs/
│   │   │         ├── filtered_feature_bc_matrix/
│   │   │         ├── raw_feature_bc_matrix/
│   │   │         ├── web_summary.html
│   │   │         ├── metrics_summary.csv
│   │   │         └── possorted_genome_bam.bam (if create_bam=true)
│   │   └─ 21. exit with cellranger's exit code
│   │       ════════════════════════════════════════════════
│   │       HANDOFF — back to SLURM template
│   │       ════════════════════════════════════════════════
│   │
│   ├─ 22. check pipeline exit code
│   ├─ 23. rsync --checksum scratch outputs → run dir/outputs/
│   ├─ 24. rsync --checksum fastq_dir → run dir/inputs/
│   └─ 25. dry-run rsync verification → pass/fail
│
DONE — job exits, SLURM releases node

Nesting depth: 3 layers
  tjp-launch → SLURM template → wrapper script → cellranger binary

Key differences from container pipelines:
  - No Apptainer, no container, no Nextflow
  - --exclusive SLURM flag (full node)
  - Config YAML passed directly (no pipeline.config generation)
  - Binary discovery via find_10x_binary() with fallback chain
  - Tool manages own threading via --localcores/--localmem
```

### A.5 Space Ranger (Native 10x)

```
USER LOGIN NODE
│
├─ tjp-launch spaceranger
│   ├─ 1. source lib/common.sh, validate.sh, manifest.sh, metadata.sh
│   ├─ 2. validate_config() → _validate_spaceranger()
│   │      checks: sample_id, sample_name, fastq_dir, transcriptome,
│   │      image, localcores, localmem, create_bam present
│   │      checks: slide identification — EITHER:
│   │        (slide + area) where area ∈ {A1, B1, C1, D1}
│   │        OR unknown_slide ∈ {visium-1, visium-2, visium-2-large, visium-hd}
│   │      checks: paths exist (fastq_dir, transcriptome, image)
│   ├─ 3-10. (same as Cell Ranger: native path, run dir, manifest, sbatch)
│   │      ════════════════════════════════════════════════
│   │      HANDOFF — enters SLURM queue
│   │      ════════════════════════════════════════════════

COMPUTE NODE (allocated by SLURM: 16 CPU, 128GB, 24h, EXCLUSIVE)
│
├─ spaceranger_slurm_template.sh
│   ├─ 11. pre-flight: config exists? wrapper exists?
│   ├─ 12. bash containers/10x/bin/spaceranger-run.sh config.yaml scratch_dir
│   │
│   │   WRAPPER SCRIPT (spaceranger-run.sh)
│   │   │
│   │   ├─ 13. source lib/10x_common.sh
│   │   ├─ 14. require_config_keys: sample_id, sample_name, fastq_dir,
│   │   │      transcriptome, image, localcores, localmem
│   │   ├─ 15. yaml_get each value (+ optional: slide, area, unknown_slide,
│   │   │      cytaimage, darkimage, colorizedimage, reorient_images,
│   │   │      loupe_alignment, create_bam, no_bam, tool_path)
│   │   ├─ 16. find_10x_binary "spaceranger"
│   │   ├─ 17. require_paths_exist: fastq_dir, transcriptome, image
│   │   ├─ 18. cd "$SCRATCH_OUTPUT_DIR"
│   │   ├─ 19. build command:
│   │   │      spaceranger count \
│   │   │          --id=$sample_id \
│   │   │          --transcriptome=$transcriptome \
│   │   │          --fastqs=$fastq_dir \
│   │   │          --sample=$sample_name \
│   │   │          --image=$image \
│   │   │          --localcores=$localcores \
│   │   │          --localmem=$localmem
│   │   │
│   │   ├─ 20. SLIDE IDENTIFICATION (conditional):
│   │   │      if unknown_slide set:
│   │   │          --unknown-slide=$unknown_slide
│   │   │      else:
│   │   │          --slide=$slide --area=$area
│   │   │
│   │   ├─ 21. append optional flags (cytaimage, darkimage, etc.)
│   │   ├─ 22. EXECUTE spaceranger count
│   │   │      → $SCRATCH_OUTPUT_DIR/$sample_id/outs/
│   │   │         ├── spatial/
│   │   │         │   ├── tissue_positions.csv
│   │   │         │   ├── scalefactors_json.json
│   │   │         │   └── tissue_hires_image.png
│   │   │         ├── filtered_feature_bc_matrix/
│   │   │         ├── raw_feature_bc_matrix/
│   │   │         └── web_summary.html
│   │   └─ 23. exit with spaceranger's exit code
│   │
│   ├─ 24-27. archive + verification (same as Cell Ranger)

DONE

Nesting depth: 3 layers
  tjp-launch → SLURM template → wrapper script → spaceranger binary

Key differences from Cell Ranger:
  - Requires image (microscope TIF) as input
  - Slide identification: --slide/--area OR --unknown-slide
  - Additional optional image inputs (cytaimage, darkimage, colorizedimage)
  - Outputs include spatial/ directory with tissue positions and scale factors
```

### A.6 Xenium Ranger (Native 10x)

```
USER LOGIN NODE
│
├─ tjp-launch xeniumranger
│   ├─ 1. source lib/common.sh, validate.sh, manifest.sh, metadata.sh
│   ├─ 2. validate_config() → _validate_xeniumranger()
│   │      checks: sample_id, command, xenium_bundle, localcores, localmem
│   │      checks: command ∈ {resegment, import-segmentation}
│   │      if import-segmentation: segmentation_file required + must exist
│   │      checks: xenium_bundle path exists
│   ├─ 3-10. (same native path, but FASTQ_DIR = xenium_bundle for archiving)
│   │      ════════════════════════════════════════════════
│   │      HANDOFF — enters SLURM queue
│   │      ════════════════════════════════════════════════

COMPUTE NODE (allocated by SLURM: 16 CPU, 128GB, 12h, EXCLUSIVE)
│
├─ xeniumranger_slurm_template.sh
│   ├─ 11. pre-flight: config exists? wrapper exists?
│   ├─ 12. bash containers/10x/bin/xeniumranger-run.sh config.yaml scratch_dir
│   │
│   │   WRAPPER SCRIPT (xeniumranger-run.sh)
│   │   │
│   │   ├─ 13. source lib/10x_common.sh
│   │   ├─ 14. require_config_keys: sample_id, command, xenium_bundle,
│   │   │      localcores, localmem
│   │   ├─ 15. yaml_get each value (+ optional: tool_path)
│   │   ├─ 16. find_10x_binary "xeniumranger"
│   │   ├─ 17. require_paths_exist: xenium_bundle
│   │   ├─ 18. cd "$SCRATCH_OUTPUT_DIR"
│   │   │
│   │   ├─ 19. COMMAND DISPATCH:
│   │   │
│   │   │   case "$command" in
│   │   │
│   │   │   ┌─ resegment ──────────────────────────────────────┐
│   │   │   │  optional: expansion_distance, panel_file        │
│   │   │   │                                                  │
│   │   │   │  xeniumranger resegment \                        │
│   │   │   │      --id=$sample_id \                           │
│   │   │   │      --xenium-bundle=$xenium_bundle \            │
│   │   │   │      --localcores=$localcores \                  │
│   │   │   │      --localmem=$localmem \                      │
│   │   │   │      [--expansion-distance=$expansion_distance] \│
│   │   │   │      [--panel-file=$panel_file]                  │
│   │   │   └──────────────────────────────────────────────────┘
│   │   │
│   │   │   ┌─ import-segmentation ────────────────────────────┐
│   │   │   │  required: segmentation_file                     │
│   │   │   │  optional: viz_labels                            │
│   │   │   │                                                  │
│   │   │   │  xeniumranger import-segmentation \              │
│   │   │   │      --id=$sample_id \                           │
│   │   │   │      --xenium-bundle=$xenium_bundle \            │
│   │   │   │      --segmentation=$segmentation_file \         │
│   │   │   │      --localcores=$localcores \                  │
│   │   │   │      --localmem=$localmem \                      │
│   │   │   │      [--viz-labels=$viz_labels]                  │
│   │   │   └──────────────────────────────────────────────────┘
│   │   │
│   │   └─ 20. exit with xeniumranger's exit code
│   │
│   ├─ 21-24. archive + verification (INPUT_DIR instead of FASTQ_DIR)

DONE

Nesting depth: 3 layers
  tjp-launch → SLURM template → wrapper script → xeniumranger binary

Key differences from Cell Ranger / Space Ranger:
  - No FASTQs — works on pre-computed Xenium output bundles
  - Dual command: resegment OR import-segmentation (not count)
  - Command-specific required fields (segmentation_file for import)
  - 12h walltime (post-processing, not alignment)
  - Archives INPUT_DIR (xenium_bundle) not FASTQ_DIR
  - No smoke test support in tjp-test (infrastructure ready but not wired)
```

### A.7 Virome (Native Nextflow + Per-Process Containers)

```
USER LOGIN NODE
│
├─ tjp-launch virome
│   ├─ 1. source lib/common.sh, validate.sh, manifest.sh, metadata.sh
│   ├─ 2. validate_config() → _validate_virome()
│   │      checks: outdir, kraken2_db present; fastq_dir or samplesheet present
│   │      checks: kraken2_db path exists
│   ├─ 3. is_nextflow_managed_pipeline("virome") → true
│   │      no container SIF path check
│   ├─ 4. create /work/$USER/pipelines/virome/runs/<timestamp>/
│   ├─ 5. cp config.yaml → run dir (snapshot)
│   ├─ 6. SBATCH_CONFIG_ARG = config.yaml (no translation)
│   ├─ 7. generate_manifest() → manifest.json
│   ├─ 8. sbatch virome_slurm_template.sh config.yaml run_dir scratch_dir
│   │      ════════════════════════════════════════════════
│   │      HANDOFF — control leaves login node, enters SLURM queue
│   │      ════════════════════════════════════════════════
│   └─ 9. extract job ID, update manifest, register Titan metadata (if titan_* present)

COMPUTE NODE (allocated by SLURM: 20 CPU, 64GB, 12h)
│
├─ virome_slurm_template.sh
│   ├─ 10. module load nextflow apptainer
│   ├─ 11. pre-flight: verify *.sif files exist in containers/virome/containers/
│   ├─ 12. nextflow run $PROJECT_ROOT/containers/virome/main.nf \
│   │       -profile juno \
│   │       --params-file "$CONFIG" \
│   │       -w "$SCRATCH_OUTPUT_DIR/work"
│   │       ════════════════════════════════════════════════
│   │       HANDOFF — Nextflow orchestrates per-process containers
│   │       ════════════════════════════════════════════════
│   │
│   │   NEXTFLOW MANAGES THESE PROCESSES (each in own .sif):
│   │   │
│   │   ├─ 13. FASTQC (containers/virome/containers/fastqc.sif)
│   │   │      reads: input FASTQs
│   │   │      → QC reports
│   │   │
│   │   ├─ 14. Kraken2 classification (containers/virome/containers/kraken2.sif)
│   │   │      reads: input FASTQs
│   │   │      uses:  kraken2_db
│   │   │      → taxonomic classification report
│   │   │
│   │   └─ 15. MetaPhlAn3 abundance (containers/virome/containers/metaphlan.sif)
│   │          reads: input FASTQs
│   │          → relative abundance table
│   │
│   └─ Nextflow exits (outputs already at outdir: from config)
│
DONE — job exits, SLURM releases node
  (no separate stage-out: output written directly to outdir:)

Nesting depth: 3 layers
  tjp-launch → SLURM template → Nextflow → per-process containers

Key differences from BulkRNASeq/Psoma:
  - No Apptainer wrapper for head process (Nextflow runs natively)
  - Each Nextflow process uses its own .sif (not one shared container)
  - No config translation — user YAML is passed directly as --params-file
  - Output goes directly to outdir: (no scratch staging or rsync)
  - Pre-flight checks for per-process SIF files (not a single container file)
```

### A.8 SQANTI3 (4-Stage SLURM DAG)

```
USER LOGIN NODE
│
├─ tjp-launch sqanti3
│   ├─ 1. source lib/common.sh, validate.sh, manifest.sh, metadata.sh
│   ├─ 2. validate_config() → _validate_sqanti3()
│   │      checks: isoform_gtf, isoform_fasta, reference_gtf, outdir present
│   │      checks: isoform_gtf, isoform_fasta, reference_gtf paths exist
│   ├─ 3. create /work/$USER/pipelines/sqanti3/runs/<timestamp>/
│   ├─ 4. cp config.yaml → run dir (snapshot)
│   ├─ 5. SBATCH_CONFIG_ARG = config.yaml (no translation)
│   ├─ 6. generate_manifest() → manifest.json
│   ├─ 7. sbatch sqanti3_slurm_template.sh config.yaml run_dir scratch_dir
│   │      ════════════════════════════════════════════════
│   │      HANDOFF — enters SLURM queue
│   │      ════════════════════════════════════════════════
│   └─ 8. extract orchestrator job ID, update manifest

COMPUTE NODE (orchestrator: 1 CPU, 4GB, 1h)
│
├─ sqanti3_slurm_template.sh  ← ORCHESTRATOR
│   ├─ 9.  count transcripts in isoform_gtf → N_TX
│   ├─ 10. compute STAGE_CPUS, STAGE_MEM from N_TX
│   ├─ 11. JOB_1A = sbatch --parsable ... stage_1a_qc_longreads.sh "$CONFIG" "$SCRATCH"
│   ├─ 12. JOB_1B = sbatch --parsable ... stage_1b_qc_reference.sh "$CONFIG" "$SCRATCH"
│   ├─ 13. JOB_2  = sbatch --parsable --dependency=afterok:${JOB_1A}:${JOB_1B} \
│   │               ... stage_2_filter.sh "$CONFIG" "$SCRATCH"
│   ├─ 14. JOB_3  = sbatch --parsable --dependency=afterok:${JOB_2} \
│   │               ... stage_3_rescue.sh "$CONFIG" "$SCRATCH"
│   └─ 15. log job IDs and exit
│          ════════════════════════════════════════════════
│          ORCHESTRATOR EXITS — 4 stage jobs now in queue
│          ════════════════════════════════════════════════

STAGE JOBS (run on separate compute nodes, dynamically allocated)
│
├─ stage_1a_qc_longreads.sh  (no dependencies)
│   └─ apptainer exec sqanti3_v5.5.4.sif python SQANTI3_qc.py [long-read args]
│      → isoform classification report
│
├─ stage_1b_qc_reference.sh  (no dependencies, runs in parallel with 1a)
│   └─ apptainer exec sqanti3_v5.5.4.sif python SQANTI3_qc.py [reference args]
│      → reference annotation QC
│
├─ stage_2_filter.sh  (depends: 1a + 1b)
│   └─ apptainer exec sqanti3_v5.5.4.sif python SQANTI3_filter.py [filter args]
│      → filtered isoforms
│
└─ stage_3_rescue.sh  (depends: 2)
    └─ apptainer exec sqanti3_v5.5.4.sif python SQANTI3_rescue.py [rescue args]
       → final rescued isoform set (written to outdir:)

DONE — all stage jobs exit, outputs in outdir: from config

Nesting depth: orchestrator + 3 (each stage: tjp-launch → SLURM → Apptainer → SQANTI3)

Key differences from all other pipelines:
  - SLURM template is an orchestrator, not an executor
  - Jobs run as a DAG with SLURM --dependency flags
  - Stages 1a and 1b run in parallel
  - Dynamic resource allocation based on transcript count
  - Output goes directly to outdir: (no scratch staging or rsync)
  - SIF must be pre-pulled (not built from local .def)
```

### A.9 wf-transcriptomes (Nextflow SLURM Executor)

```
USER LOGIN NODE
│
├─ tjp-launch wf_transcriptomes
│   ├─ 1. source lib/common.sh, validate.sh, manifest.sh, metadata.sh
│   ├─ 2. validate_config() → _validate_wf_transcriptomes()
│   │      checks: sample_sheet, outdir, ref_genome, ref_annotation present
│   │      checks: paths exist; wf_version format valid
│   ├─ 3. is_nextflow_managed_pipeline("wf_transcriptomes") → true
│   ├─ 4. create /work/$USER/pipelines/wf_transcriptomes/runs/<timestamp>/
│   ├─ 5. cp config.yaml → run dir (snapshot)
│   ├─ 6. SBATCH_CONFIG_ARG = config.yaml (no translation)
│   ├─ 7. generate_manifest() → manifest.json
│   ├─ 8. sbatch wf_transcriptomes_slurm_template.sh config.yaml run_dir scratch_dir
│   │      ════════════════════════════════════════════════
│   │      HANDOFF — enters SLURM queue
│   │      ════════════════════════════════════════════════
│   └─ 9. extract head job ID, update manifest

HEAD JOB COMPUTE NODE (2 CPU, 8GB, 24h)
│
├─ wf_transcriptomes_slurm_template.sh
│   ├─ 10. module load nextflow
│   ├─ 11. read wf_version from config (default: v1.7.2)
│   ├─ 12. nextflow run epi2me-labs/wf-transcriptomes \
│   │       -r "$wf_version" \
│   │       -c "$PROJECT_ROOT/containers/sqanti3/configs/wf_transcriptomes/juno.config" \
│   │       --params-file "$CONFIG" \
│   │       -w "$SCRATCH_OUTPUT_DIR/work"
│   │       ════════════════════════════════════════════════
│   │       HANDOFF — Nextflow submits sub-jobs to SLURM
│   │       HEAD JOB MUST STAY ALIVE UNTIL ALL SUB-JOBS COMPLETE
│   │       ════════════════════════════════════════════════
│   │
│   │   NEXTFLOW SLURM EXECUTOR (jobs on separate compute nodes):
│   │   │
│   │   ├─ sbatch → minimap2 alignment (one job per sample)
│   │   ├─ sbatch → StringTie assembly
│   │   ├─ sbatch → salmon quantification
│   │   ├─ sbatch → JAFFAL fusion detection
│   │   ├─ sbatch → differential expression (if groups configured)
│   │   └─ ... (process graph determined by wf-transcriptomes version)
│   │
│   └─ Nextflow collects results, exits
│      (outputs already at outdir: — no separate rsync)
│
DONE

Nesting depth: head job + dynamic sub-jobs
  tjp-launch → SLURM head job → Nextflow → SLURM sub-jobs → tools

Key differences from all other pipelines:
  - Most complex job topology: head job coordinates dozens of SLURM sub-jobs
  - Head job must outlast all sub-jobs (24h walltime)
  - Nextflow fetches workflow from GitHub at runtime (cached in $NXF_HOME)
  - sub-job containers managed by Nextflow, not by the framework
  - Output goes directly to outdir: (no scratch staging)
  - EPI2ME samplesheet format (distinct from framework CSV samplesheet)
  - Pipeline version pinned via wf_version key (default: v1.7.2)
```

### A.10 Nesting Depth Summary

```
Pipeline          Nesting                                                        Depth
────────────────  ─────────────────────────────────────────────────────────────  ─────
AddOne            tjp-launch → SLURM → Apptainer → Python                        3
BulkRNASeq        tjp-launch → SLURM → Apptainer → Nextflow → tools             4
Psoma             tjp-launch → SLURM → Apptainer → Nextflow → tools             4
Cell Ranger       tjp-launch → SLURM → wrapper → cellranger                      3
Space Ranger      tjp-launch → SLURM → wrapper → spaceranger                     3
Xenium Ranger     tjp-launch → SLURM → wrapper → xeniumranger                    3
Virome            tjp-launch → SLURM → Nextflow → per-process containers         3
SQANTI3           tjp-launch → SLURM orchestrator → 4 stage SLURM jobs → tool   3+
wf-transcriptomes tjp-launch → SLURM head job → Nextflow → SLURM sub-jobs       3+
```
