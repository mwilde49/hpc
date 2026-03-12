# BioCruiser / Hyperion Compute — Developer Onboarding Guide

This document is a comprehensive technical reference for developers joining the TJP HPC pipeline framework. It covers every layer of the system, traces execution flows step-by-step for all six pipelines, and explains the design decisions behind each component.

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
5. [Pipeline Comparison Matrix](#5-pipeline-comparison-matrix)
6. [Testing Infrastructure](#6-testing-infrastructure)
7. [Adding a New Pipeline](#7-adding-a-new-pipeline)
8. [HPC Environment](#8-hpc-environment)
9. [Key Files Reference](#9-key-files-reference)

---

## 1. System Overview

This framework runs bioinformatics pipelines on the Juno HPC cluster for the TJP research group. It is deployed to `/groups/tprice/pipelines` and provides six pipelines:

| Pipeline | Type | Purpose |
|----------|------|---------|
| **AddOne** | Inline container | Demo/template pipeline (adds 1 to numbers) |
| **BulkRNASeq** | Submoduled container | Bulk RNA-seq analysis (STAR aligner) |
| **Psoma** | Submoduled container | Psomagen RNA-seq analysis (HISAT2 + Trimmomatic) |
| **Cell Ranger** | Native 10x | Single-cell RNA-seq (10x Genomics) |
| **Space Ranger** | Native 10x | Spatial transcriptomics (10x Visium) |
| **Xenium Ranger** | Native 10x | In situ transcriptomics (10x Xenium) |

Users interact through five CLI tools:

```
tjp-setup          →  One-time workspace initialization
tjp-test           →  Smoke test with bundled test data
tjp-test-validate  →  Verify smoke test outputs
tjp-launch         →  Submit a pipeline run
tjp-validate       →  Validate config without submitting
```

All tools also have `hyperion-*` and `biocruiser-*` symlink aliases.

---

## 2. Architecture: The Four-Layer Stack

The framework has four layers, each with a single responsibility. Think of it as an assembly line:

### Layer 1: Config (the order form)

**Location:** `templates/<pipeline>/config.yaml`

YAML files where users specify their inputs, outputs, and parameters. Templates contain `__USER__`, `__SCRATCH__`, and `__WORK__` placeholders that `tjp-setup` replaces with real paths. Users edit these once, then launch.

Each pipeline has different required keys. For example, Cell Ranger needs `sample_id`, `fastq_dir`, `transcriptome`, `localcores`, `localmem`, and `create_bam`. Psoma needs `hisat2_index`, `reference_gtf`, and Trimmomatic parameters.

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

### Layer 3: Execution Environment (the sealed toolbox)

**Location:** `containers/` (container definitions and submodules)

Two models:

- **Container pipelines** (AddOne, BulkRNASeq, Psoma): All dependencies are packaged into an Apptainer `.sif` file. The SLURM template runs `apptainer exec` with `--cleanenv` (no host environment leakage) and `--env PYTHONNOUSERSITE=1` (no host Python package shadowing). Host directories are bind-mounted into the container.

- **Native pipelines** (Cell Ranger, Space Ranger, Xenium Ranger): 10x Genomics tools are installed from tarballs at `/groups/tprice/opt/` and manage their own execution. The SLURM template calls a wrapper script that invokes the tool directly. No container needed.

### Layer 4: Pipeline (the worker)

The actual scientific code. For container pipelines, this is Python/Nextflow scripts inside the container. For native pipelines, this is the 10x Genomics binary itself. This layer reads the config, processes data, and writes results.

### How They Connect

```
User runs tjp-launch <pipeline>
    │
    ▼
CLI Layer (bin/tjp-launch)
    │  validates config, creates run directory,
    │  generates manifest, calls sbatch
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
- `KNOWN_PIPELINES` — master list of all pipelines (line 43)

**Key functions:**
- `yaml_get <file> <key>` — reads a value from flat YAML (grep-based, not a full parser)
- `yaml_has <file> <key>` — checks if a key exists
- `is_native_pipeline <name>` — returns 0 if pipeline skips containers
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
    "output_paths": "/scratch/juno/jsmith/pipelines/psoma/runs/2026-03-11_14-30-45"
}
```

Key details:
- `container_checksum` is an MD5 of the first 10MB of the `.sif` file (for speed)
- For native pipelines, `container_file` is `native:<tool_path>` and `container_checksum` is the tool version string
- `slurm_job_id` starts as `"pending"` and is updated after `sbatch` returns

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
4. Adds `$REPO_ROOT/bin` to the user's `.bashrc`

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
    verify .sif file exists
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

#### Step 9: Submit (lines 350-366)
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

#### Step 10: Post-Submit (lines 369-400)
```
JOB_ID = parse from sbatch output
update_manifest_job_id "$RUN_DIR" "$JOB_ID"
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

### Data Flow

| Pipeline | Input Type | Primary Command | Special Input |
|----------|-----------|----------------|---------------|
| AddOne | Text file | `python addone.py` | None |
| BulkRNASeq | FASTQs | `nextflow run` | STAR index |
| Psoma | FASTQs | `nextflow run` | HISAT2 index + Nextera adapters |
| Cell Ranger | FASTQs | `cellranger count` | Transcriptome reference |
| Space Ranger | FASTQs + Image | `spaceranger count` | Slide/area + microscope image |
| Xenium Ranger | Xenium bundle | `xeniumranger resegment` or `import-segmentation` | Segmentation file (import only) |

### Container Flags

| Flag | Purpose | Used By |
|------|---------|---------|
| `--cleanenv` | Block host env vars from entering container | BulkRNASeq, Psoma |
| `--env PYTHONNOUSERSITE=1` | Block host Python packages | BulkRNASeq, Psoma |
| `--env HOME=/tmp` | Writable home for Nextflow | Psoma |
| `--env _JAVA_OPTIONS=-Xmx16g` | Java heap limit | Psoma |
| `--bind` | Mount host paths into container | All container pipelines |
| `--exclusive` | Full node access | All native pipelines |

---

## 6. Testing Infrastructure

### Smoke Testing (`tjp-test`)

Verifies a pipeline works end-to-end with pre-bundled test data on the dev partition.

**Currently supported:** `psoma`, `bulkrnaseq`, `cellranger`, `spaceranger`

**Not yet supported:** `xeniumranger` (infrastructure exists, not wired up), `addone`

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

### Run Directory Structure

Each `tjp-launch` creates a timestamped run directory:

```
/work/$USER/pipelines/<pipeline>/runs/<timestamp>/
├── config.yaml              ← snapshot of config at launch time
├── pipeline.config          ← generated Nextflow config (container pipelines only)
├── manifest.json            ← reproducibility record
├── slurm_<jobid>.out        ← SLURM stdout
├── slurm_<jobid>.err        ← SLURM stderr
├── inputs/                  ← archived input files (post-run rsync)
└── outputs/                 ← archived results (post-run rsync)
```

### Important: Symlinked Home Directories

Juno uses symlinked home directories. Apptainer bind mounts require **real paths** — always resolve with `readlink -f` before passing to Apptainer. The SLURM templates handle this by using absolute paths (`/groups/tprice/pipelines`, `/scratch/juno/$USER`, `/work/$USER`), not `$HOME`-relative paths.

This is also why Psoma's SLURM template sets `--env HOME=/tmp` — Nextflow tries to write to `~/.nextflow`, but `~` resolves to a symlink that Apptainer cannot follow.

---

## 9. Key Files Reference

### CLI Tools

| File | Purpose |
|------|---------|
| `bin/tjp-setup` | One-time workspace initialization |
| `bin/tjp-launch` | Main launch orchestrator |
| `bin/tjp-test` | Smoke test with bundled data |
| `bin/tjp-test-validate` | Verify smoke test outputs |
| `bin/tjp-validate` | Config-only validation |

### Shared Libraries

| File | Purpose |
|------|---------|
| `bin/lib/common.sh` | Pipeline registry, YAML helpers, logging, path functions |
| `bin/lib/validate.sh` | Per-pipeline config validators |
| `bin/lib/manifest.sh` | Reproducibility manifest generation |
| `bin/lib/branding.sh` | Hyperion Compute themed output |

### SLURM Templates

| File | Resources |
|------|-----------|
| `slurm_templates/addone_slurm_template.sh` | 5min, 1 CPU, 1GB |
| `slurm_templates/bulkrnaseq_slurm_template.sh` | 12h, 40 CPU, 128GB |
| `slurm_templates/psoma_slurm_template.sh` | 12h, 40 CPU, 128GB |
| `slurm_templates/cellranger_slurm_template.sh` | 24h, 16 CPU, 128GB, exclusive |
| `slurm_templates/spaceranger_slurm_template.sh` | 24h, 16 CPU, 128GB, exclusive |
| `slurm_templates/xeniumranger_slurm_template.sh` | 12h, 16 CPU, 128GB, exclusive |

### Config Templates

| File | Key Required Fields |
|------|-------------------|
| `templates/addone/config.yaml` | `input`, `output` |
| `templates/bulkrnaseq/config.yaml` | `project_name`, `fastq_dir`, `star_index`, `reference_gtf` |
| `templates/psoma/config.yaml` | `project_name`, `fastq_dir`, `hisat2_index`, `reference_gtf` |
| `templates/cellranger/config.yaml` | `sample_id`, `fastq_dir`, `transcriptome`, `create_bam` |
| `templates/spaceranger/config.yaml` | `sample_id`, `fastq_dir`, `transcriptome`, `image`, `slide`/`area` |
| `templates/xeniumranger/config.yaml` | `sample_id`, `command`, `xenium_bundle` |

### Submodules

| Path | Repo | Version | Contains |
|------|------|---------|----------|
| `containers/bulkrnaseq/` | `mwilde49/bulkseq` | v1.0.0 | Container def + build scripts |
| `containers/psoma/` | `mwilde49/psoma` | v1.0.0 | Container def + pipeline code + adapters |
| `containers/10x/` | `mwilde49/10x` | v1.1.0 | Wrapper scripts, validators, tests |

### Pipeline Code

| File | Language | Purpose |
|------|----------|---------|
| `pipelines/addone/addone.py` | Python | Demo pipeline (add 1 to numbers) |
| `containers/psoma/psomagen_bulk_rna_seq_pipeline.nf` | Nextflow | Psoma RNA-seq pipeline |
| `Bulk-RNA-Seq-Nextflow-Pipeline/bulk_rna_seq_nextflow_pipeline.nf` | Nextflow | UTDal bulk RNA-seq (external clone) |
| `containers/10x/bin/cellranger-run.sh` | Bash | Cell Ranger wrapper |
| `containers/10x/bin/spaceranger-run.sh` | Bash | Space Ranger wrapper |
| `containers/10x/bin/xeniumranger-run.sh` | Bash | Xenium Ranger wrapper |

### References (Shared Data)

| Path | Purpose |
|------|---------|
| `/groups/tprice/pipelines/references/gencode.v48.primary_assembly.annotation.gtf` | Gene annotation |
| `/groups/tprice/pipelines/references/filter.bed` | Genomic region filter |
| `/groups/tprice/pipelines/references/blacklist.bed` | Blacklisted regions |
| `/groups/tprice/pipelines/references/hisat2_index/` | HISAT2 genome index |
| `/groups/tprice/pipelines/references/star_index/` | STAR genome index |
