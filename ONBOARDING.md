# Hyperion Compute — Onboarding Guide

Quick start for running pipelines on Juno HPC.

> **Note:** The CLI tools are available as `tjp-*`, `hyperion-*`, or `biocruiser-*` — they're all identical. Use whichever you prefer.

---

## 1. One-Time Setup

```bash
/groups/tprice/pipelines/bin/tjp-setup
```

This creates your personal workspace at `/work/$USER/pipelines/` with template configs for each pipeline, and automatically adds the tools to your `~/.bashrc`. Log out and back in (or run `source ~/.bashrc`) to activate.

## 2. Configure a Pipeline

### AddOne (demo pipeline)

```bash
vi /work/$USER/pipelines/addone/config.yaml
```

Fields:

| Key | Description |
|-----|-------------|
| `input` | Path to input file (one number per line) |
| `output` | Path for output file (typically on scratch) |

### BulkRNASeq

```bash
vi /work/$USER/pipelines/bulkrnaseq/config.yaml
```

Fields:

| Key | Required | Description |
|-----|----------|-------------|
| `project_name` | yes | Name for your project |
| `species` | yes | `Human`, `Mouse`, or `Rattus` |
| `paired_end` | yes | `true` or `false` |
| `fastq_dir` | yes | Directory containing FASTQ files |
| `samples_file` | yes | File listing sample names (one per line) |
| `star_index` | yes | Path to STAR genome index |
| `reference_gtf` | yes | Path to reference GTF annotation |
| `read1_suffix` | no | Read 1 suffix (default: `_R1_001`) |
| `read2_suffix` | no | Read 2 suffix (default: `_R2_001`) |
| `run_fastqc` | yes | Run FastQC step (`true`/`false`) |
| `run_rna_pipeline` | yes | Run RNA pipeline step (`true`/`false`) |
| `exclude_bed_file_path` | no | BED file for region exclusion |
| `blacklist_bed_file_path` | no | BED file for blacklist regions |

Edit your samples file:

```bash
vi /work/$USER/pipelines/bulkrnaseq/samples.txt
```

List sample names without the read suffix or `.fastq.gz` extension. For example, if your files are `Patient01_S1_R1_001.fastq.gz`, list `Patient01_S1`.

### Psoma

```bash
vi /work/$USER/pipelines/psoma/config.yaml
```

Fields:

| Key | Required | Description |
|-----|----------|-------------|
| `project_name` | yes | Name for your project |
| `species` | yes | `Human`, `Mouse`, or `Rattus` |
| `paired_end` | yes | `true` or `false` |
| `fastq_dir` | yes | Directory containing FASTQ files |
| `samples_file` | yes | File listing sample names (one per line) |
| `hisat2_index` | yes | Path to HISAT2 index prefix |
| `reference_gtf` | yes | Path to reference GTF annotation |
| `read1_suffix` | no | Read 1 suffix (default: `_1`) |
| `read2_suffix` | no | Read 2 suffix (default: `_2`) |
| `run_fastqc` | yes | Run FastQC step (`true`/`false`) |
| `run_rna_pipeline` | yes | Run RNA pipeline step (`true`/`false`) |
| `exclude_bed_file_path` | no | BED file for region exclusion |
| `blacklist_bed_file_path` | no | BED file for blacklist regions |

Edit your samples file:

```bash
vi /work/$USER/pipelines/psoma/samples.txt
```

List sample names without the read suffix or `.fastq.gz` extension. For example, if your files are `Sample_19_1.fastq.gz`, list `Sample_19`.

### Cell Ranger (10x single-cell gene expression)

```bash
vi /work/$USER/pipelines/cellranger/config.yaml
```

Fields:

| Key | Required | Description |
|-----|----------|-------------|
| `sample_id` | yes | ID for the run (used as output directory name) |
| `sample_name` | yes | Sample name matching FASTQ filenames |
| `fastq_dir` | yes | Directory containing FASTQ files |
| `transcriptome` | yes | Path to Cell Ranger reference transcriptome |
| `localcores` | yes | Number of CPU cores (match SLURM allocation) |
| `localmem` | yes | Memory in GB (leave headroom below SLURM `--mem`) |
| `tool_path` | no | Override default tool location |
| `chemistry` | no | Chemistry type (`auto`, `SC3Pv3`, etc.) |
| `expect_cells` | no | Expected number of recovered cells |
| `include_introns` | no | Include intronic reads (default: true) |

### Space Ranger (10x spatial gene expression)

```bash
vi /work/$USER/pipelines/spaceranger/config.yaml
```

Fields:

| Key | Required | Description |
|-----|----------|-------------|
| `sample_id` | yes | ID for the run |
| `sample_name` | yes | Sample name matching FASTQ filenames |
| `fastq_dir` | yes | Directory containing FASTQ files |
| `transcriptome` | yes | Path to Space Ranger reference transcriptome |
| `image` | yes | Path to microscope image (TIFF) |
| `slide` | yes | Visium slide serial number |
| `area` | yes | Capture area (`A1`, `B1`, `C1`, or `D1`) |
| `localcores` | yes | Number of CPU cores |
| `localmem` | yes | Memory in GB |
| `tool_path` | no | Override default tool location |

### Xenium Ranger (10x in situ transcriptomics)

```bash
vi /work/$USER/pipelines/xeniumranger/config.yaml
```

Fields:

| Key | Required | Description |
|-----|----------|-------------|
| `sample_id` | yes | ID for the run |
| `command` | yes | `resegment` or `import-segmentation` |
| `xenium_bundle` | yes | Path to Xenium output bundle directory |
| `localcores` | yes | Number of CPU cores |
| `localmem` | yes | Memory in GB |
| `tool_path` | no | Override default tool location |
| `segmentation_file` | conditional | Required when command is `import-segmentation` |

## 3. Launch

```bash
tjp-launch addone
tjp-launch bulkrnaseq
tjp-launch psoma
tjp-launch cellranger
tjp-launch spaceranger
tjp-launch xeniumranger
```

Use a custom config path:

```bash
tjp-launch addone --config /path/to/my_config.yaml
```

Use the dev partition for quick testing (2-hour limit):

```bash
tjp-launch psoma --dev
```

Output:

```
============================================================
            H Y P E R I O N   C O M P U T E
------------------------------------------------------------
  Distributed Bioinformatics Execution Framework
  SLURM Orchestration • Pipeline Automation • HPC Scale
============================================================

  Mode: LAUNCH

Initializing Hyperion Pipeline Engine...
Cluster nodes detected: 86
SLURM scheduler online.

[14:30:00] [INFO]  Validating config: /work/jsmith/pipelines/psoma/config.yaml
[14:30:00] [INFO]  Config validation passed.
[14:30:00] [INFO]  Run directory: /work/jsmith/pipelines/psoma/runs/2026-03-04_14-30-00

[HYPERION] Warp Drive Engaged — psoma job 151456 submitted
  Pipeline:   psoma
  Job ID:     151456
  Run dir:    /work/jsmith/pipelines/psoma/runs/2026-03-04_14-30-00/
  Monitor:    tail -f .../slurm_151456.out
  Cancel:     scancel 151456
```

## 4. Smoke Testing

Verify a pipeline works end-to-end with pre-configured test data (2 samples on the dev partition):

```bash
tjp-test psoma              # submit smoke test
squeue -u $USER             # monitor job
tjp-test-validate psoma     # validate outputs after completion
```

Works for `psoma`, `bulkrnaseq`, and `cellranger`. Use `--clean` to wipe previous test data:

```bash
tjp-test bulkrnaseq --clean
```

## 5. Monitor

```bash
# Check job status
squeue -u $USER

# Watch logs in real time
tail -f /work/$USER/pipelines/<pipeline>/runs/<timestamp>/slurm_<jobid>.out

# After completion
cat /work/$USER/pipelines/<pipeline>/runs/<timestamp>/slurm_<jobid>.out
cat /work/$USER/pipelines/<pipeline>/runs/<timestamp>/slurm_<jobid>.err
```

## 6. Run Directory Structure

Each launch creates a timestamped run directory with everything needed to reproduce the run:

```
/work/$USER/pipelines/bulkrnaseq/
├── config.yaml                    ← you edit this
├── samples.txt                    ← your sample list
└── runs/
    └── 2026-03-04_14-30-00/
        ├── config.yaml            ← frozen YAML snapshot
        ├── pipeline.config        ← generated Nextflow config
        ├── manifest.json          ← reproducibility metadata
        ├── slurm_123456.out       ← SLURM stdout
        ├── slurm_123456.err       ← SLURM stderr
        ├── inputs/                ← archived copy of your FASTQs
        └── outputs/               ← archived pipeline outputs (all stages)
```

### manifest.json

Records everything about the run for reproducibility:

```json
{
    "timestamp": "2026-03-04T14:30:00-06:00",
    "user": "jsmith",
    "pipeline": "bulkrnaseq",
    "git_commit": "fc20314",
    "container_file": "/groups/tprice/pipelines/containers/bulkrnaseq/bulkrnaseq_v1.0.0.sif",
    "container_checksum": "a1b2c3d4e5f6...",
    "config": "config.yaml",
    "slurm_job_id": "123456",
    "slurm_template": "/groups/tprice/pipelines/slurm_templates/bulkrnaseq_slurm_template.sh"
}
```

---

## FAQ

**Q: I get "Config file not found" when running `tjp-launch`.**
A: Run `tjp-setup` first to create your workspace and template configs.

**Q: I get "Container not found".**
A: The `.sif` container file must be built and transferred to the HPC. See `BULKRNASEQ_HPC_GUIDE.md` or the main `README.md` for build instructions.

**Q: Can I re-run with the same config?**
A: Yes. Each launch creates a new timestamped run directory, so previous runs are preserved.

**Q: Where do pipeline outputs go?**
A: Pipeline outputs are written to scratch during execution: `/scratch/juno/$USER/pipelines/<pipeline>/runs/<timestamp>/`. After a successful run, inputs and outputs are automatically archived to your work run directory under `inputs/` and `outputs/`. Scratch is fast but wiped every 45 days — the work archive is durable.

**Q: How do I use the tools without modifying my PATH?**
A: Use the full path: `/groups/tprice/pipelines/bin/tjp-launch addone`

**Q: I already have a workspace. Will `tjp-setup` overwrite my configs?**
A: No. It skips existing configs and prints a warning.
