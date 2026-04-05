# Hyperion Compute — Onboarding Guide

Quick start for running pipelines on Juno HPC.

> **Note:** The CLI tools are available as `tjp-*`, `hyperion-*`, or `biocruiser-*` — they're all identical. Use whichever you prefer.

---

## 1. One-Time Setup

```bash
/groups/tprice/pipelines/bin/tjp-setup
```

This creates your personal workspace at `/work/$USER/pipelines/` with template configs for each pipeline, and automatically adds the tools to your `~/.bashrc`. Log out and back in (or run `source ~/.bashrc`) to activate.

Your workspace will look like this:

```
/work/$USER/pipelines/
├── addone/          ← demo pipeline
├── bulkrnaseq/      ← UTDal/STAR
├── psoma/           ← Psomagen/HISAT2
├── virome/          ← viral profiling
├── sqanti3/         ← long-read isoform QC
├── wf-transcriptomes/ ← ONT full-length RNA
├── cellranger/      ← 10x single-cell
├── spaceranger/     ← 10x spatial
├── xeniumranger/    ← 10x in situ
└── metadata/        ← local run records (PLR-xxxx.json)
```

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

### Virome (viral profiling)

```bash
vi /work/$USER/pipelines/virome/config.yaml
```

Fields:

| Key | Description |
|-----|-------------|
| `fastq_dir` | Directory containing FASTQ input files |
| `outdir` | Output directory (on scratch) |
| `kraken2_db` | Path to Kraken2 database |
| `ref_genome` | Reference genome for host read removal |
| `titan_project_id` / `titan_sample_id` / `titan_library_id` / `titan_run_id` | Optional Titan metadata |

### SQANTI3 (long-read isoform QC)

```bash
vi /work/$USER/pipelines/sqanti3/config.yaml
```

Fields:

| Key | Description |
|-----|-------------|
| `isoforms` | Collapsed isoforms GTF (from wf-transcriptomes or FLAIR) |
| `ref_gtf` | Reference annotation GTF |
| `ref_fasta` | Reference genome FASTA |
| `outdir` | Output directory |
| `coverage` | Optional: STAR SJ.out.tab file for short-read splice junction support |
| `titan_project_id` / `titan_sample_id` / `titan_library_id` / `titan_run_id` | Optional Titan metadata |

### wf-transcriptomes (ONT full-length RNA)

```bash
vi /work/$USER/pipelines/wf-transcriptomes/config.yaml
```

Fields:

| Key | Description |
|-----|-------------|
| `fastq_dir` | ONT fastq_pass directory (with barcode subdirs) |
| `sample_sheet` | EPI2ME barcode samplesheet CSV (barcode,alias) |
| `ref_genome` | Reference genome FASTA |
| `ref_annotation` | Reference annotation GTF |
| `wf_version` | Pipeline version (default: `v1.7.2`) |
| `direct_rna` | `true` for direct RNA, `false` for cDNA/PCR |
| `titan_project_id` / `titan_sample_id` / `titan_library_id` / `titan_run_id` | Optional Titan metadata |

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
| `create_bam` | yes | Create BAM file (`true`/`false`) — required in Cell Ranger 10+ |
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
| `slide` | yes* | Visium slide serial number (e.g., `V19J25-123`) |
| `area` | yes* | Capture area (`A1`, `B1`, `C1`, or `D1`) |
| `unknown_slide` | yes* | Use instead of `slide`+`area` when slide serial is unknown (`visium-1`, `visium-2`, `visium-2-large`, or `visium-hd`) |
| `localcores` | yes | Number of CPU cores |
| `localmem` | yes | Memory in GB |
| `create_bam` | yes | Create BAM file (`true`/`false`) — required in Space Ranger 3+ |
| `tool_path` | no | Override default tool location |

*Provide either `slide`+`area` or `unknown_slide`, not both.

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
tjp-launch virome
tjp-launch sqanti3
tjp-launch wf-transcriptomes
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
[14:30:00] [INFO]  Pipeline run ID: PLR-a3b7

[HYPERION] Warp Drive Engaged — psoma job 151456 submitted
  Pipeline:   psoma
  Job ID:     151456
  Run dir:    /work/jsmith/pipelines/psoma/runs/2026-03-04_14-30-00/
  Monitor:    tail -f .../slurm_151456.out
  Cancel:     scancel 151456
```

## 3.5. Batch Launching (Multiple Samples from a Samplesheet)

To run the same pipeline on multiple samples, use `tjp-batch`:

1. Edit the samplesheet template:

   ```bash
   vi /work/$USER/pipelines/cellranger/samplesheet.csv
   ```

2. Launch all rows at once:

   ```bash
   tjp-batch cellranger /work/$USER/pipelines/cellranger/samplesheet.csv
   ```

3. Add a base config for shared settings:

   ```bash
   tjp-batch bulkrnaseq samplesheet.csv --config /work/$USER/pipelines/bulkrnaseq/config.yaml
   ```

Options:

| Flag | Description |
|------|-------------|
| `--dry-run` | Show what would be submitted without submitting |
| `--dev` | Use the dev partition (2-hour limit) for all jobs |

**Per-row pipelines** (one SLURM job per CSV row): `cellranger`, `spaceranger`, `xeniumranger`, `sqanti3`, `wf-transcriptomes`

**Per-sheet pipelines** (one SLURM job for all rows): `bulkrnaseq`, `psoma`, `virome`

## 4. Smoke Testing

Verify a pipeline works end-to-end with pre-configured test data (2 samples on the dev partition):

```bash
tjp-test psoma              # submit smoke test
squeue -u $USER             # monitor job
tjp-test-validate psoma     # validate outputs after completion
```

Works for `psoma`, `bulkrnaseq`, `cellranger`, and `spaceranger`. Use `--clean` to wipe previous test data:

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

## 6. Metadata and Run Tracking (labdata)

Every launch automatically generates a local metadata record with a unique pipeline run ID (PLR-xxxx):

```bash
labdata find runs                    # list all runs
labdata find runs --pipeline psoma   # filter by pipeline
labdata find runs --status completed # filter by status
labdata show PLR-xxxx                # show full run record
labdata status                       # show metadata store health
```

Run records are stored at `/work/$USER/pipelines/metadata/pipeline_runs/` and will sync to the Titan database when Titan comes online (~6 months).

## 7. Run Directory Structure

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
    "pipeline": "psoma",
    "git_commit": "fc20314",
    "container_file": "/groups/tprice/pipelines/containers/psoma/psoma_v1.0.0.sif",
    "container_checksum": "a1b2c3d4e5f6...",
    "slurm_job_id": "151456",
    "titan_pipeline_run_id": "PLR-a3b7"
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

**Q: How do I find my previous runs?**
A: Run `labdata find runs` for a searchable list, or browse the filesystem directly with `ls /work/$USER/pipelines/<pipeline>/runs/`.

**Q: What is a PLR-xxxx ID?**
A: It's a locally generated pipeline run ID assigned to every launch. It uniquely identifies the run in the metadata store and will sync to the Titan database when Titan comes online.

**Q: Can I use Titan IDs with my runs?**
A: Yes. Add `titan_project_id`, `titan_sample_id`, `titan_library_id`, and/or `titan_run_id` to your `config.yaml` and they will be included in the run record automatically.
