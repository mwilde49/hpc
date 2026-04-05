# Juno HPC System Map & Pipeline Architecture

Technical reference for the TJP pipeline system on Juno HPC at UT Dallas.

---

## Table of Contents

1. [Cluster Overview](#1-cluster-overview)
2. [Storage & Directory Structure](#2-storage--directory-structure)
3. [Symlinks & Bind Mounts](#3-symlinks--bind-mounts)
4. [How Jobs Run](#4-how-jobs-run)
5. [Resource Allocation](#5-resource-allocation)
6. [Partition Selection](#6-partition-selection)
7. [Optimization Opportunities](#7-optimization-opportunities)
8. [Metadata and Titan Integration](#8-metadata-and-titan-integration)

---

## 1. Cluster Overview

### Compute Partitions

| Partition | Nodes | Cores/node | RAM/node | GPUs | Time limit | Use case |
|-----------|-------|------------|----------|------|------------|----------|
| **normal*** (default) | 75 | 64 (2×32 sockets) | 384 GB | none | 2 days | General compute; our pipelines |
| **dev** | 8 | 64 | 384 GB | none | 2 hours | Quick testing/debugging |
| **a30** | 2 | 128 (2×64) | 1 TB | 2× NVIDIA A30 | 2 days | GPU workloads |
| **a30-2.12gb** | 1 | 128 | 1 TB | 4× A30 MIG (12GB) | 2 days | Medium GPU jobs |
| **a30-4.6gb** | 1 | 256 | 1 TB | 8× A30 MIG (6GB) | 2 days | Many small GPU jobs |
| **h100** | 3 | 64 | 512 GB | 1–4× H100 80GB | 2 days | Heavy AI/ML |
| **vdi** | 2 | 128 | 384 GB | none | 8 hours | Interactive/desktop |

### Queue (QOS) Limits

| QOS | Max nodes per job |
|-----|-------------------|
| juno | 8 |
| hpcre | 2 |
| large | 16 |

---

## 2. Storage & Directory Structure

### Storage tiers

| Mount | Path | Quota (example) | Speed | Persistence | Purpose |
|-------|------|-----------------|-------|-------------|---------|
| **home** | `/home/$USER` | 50 GB / 300k files | Slow | Permanent | Login profile, `.bashrc` |
| **work** | `/work/$USER` | 1 TB / 3M files | Medium | Permanent | Configs, logs, run metadata |
| **scratch** | `/scratch/juno/$USER` | Large (check with admin) | Fast | **Temporary** (purged periodically) | FASTQ input, pipeline outputs, intermediates |
| **groups** | `/groups/tprice/pipelines` | Shared group quota | Slow | Permanent | Code, containers, references |
| **titan** (future) | `/store/<project>` | Project-scoped | Fast NFS | Permanent | Titan genomics data lake (~6 months) |

### Shared repo layout (`/groups/tprice/pipelines/`)

```
/groups/tprice/pipelines/
├── bin/
│   ├── tjp-setup, tjp-launch, tjp-batch
│   ├── tjp-test, tjp-test-validate, tjp-validate
│   ├── labdata
│   ├── hyperion-*, biocruiser-* (symlinks)
│   └── lib/
│       ├── common.sh        ← pipeline registry, YAML helpers, logging
│       ├── validate.sh      ← per-pipeline config validators
│       ├── manifest.sh      ← reproducibility manifest generation
│       ├── metadata.sh      ← Titan metadata / PLR-xxxx generation
│       ├── samplesheet.sh   ← CSV samplesheet parsing and validation
│       └── branding.sh      ← Hyperion Compute themed output
├── containers/
│   ├── apptainer.def        ← AddOne container definition
│   ├── addone_latest.sif
│   ├── bulkrnaseq/          ← submodule: mwilde49/bulkseq @ v1.0.0
│   │   └── bulkrnaseq_v1.0.0.sif
│   ├── psoma/               ← submodule: mwilde49/psoma @ v2.0.0
│   │   ├── psomagen_bulk_rna_seq_pipeline.nf
│   │   ├── *.sh, *.py       ← pipeline scripts
│   │   └── NexteraPE-PE.fa
│   ├── virome/              ← submodule: mwilde49/virome-pipeline @ v1.4.0
│   │   ├── main.nf
│   │   └── containers/      ← 6 per-process .sif files
│   ├── sqanti3/             ← submodule: mwilde49/longreads (SQANTI3 + wf-transcriptomes)
│   │   ├── sqanti3_v5.5.4.sif
│   │   ├── slurm_templates/ ← stage scripts for 4-stage DAG
│   │   └── configs/         ← wf_transcriptomes/juno.config etc.
│   └── 10x/                 ← submodule: mwilde49/10x @ v1.1.0
│       ├── bin/             ← cellranger-run.sh, spaceranger-run.sh, xeniumranger-run.sh
│       └── lib/             ← 10x_common.sh, validate_*.sh
├── Bulk-RNA-Seq-Nextflow-Pipeline/  ← cloned UTDal repo (not a submodule)
├── pipelines/addone/        ← inline demo pipeline
├── slurm_templates/         ← 9 SLURM templates (one per pipeline)
├── templates/               ← per-pipeline config.yaml + samplesheet.csv templates (9 pipelines)
├── docs/                    ← architecture.md, generate_diagrams.py, img/
├── metadata/                ← SCHEMA.md (local Titan metadata format docs)
├── references/              ← shared reference files (gitignored)
│   ├── star_index/
│   ├── hisat2_index/
│   ├── gencode.v48.primary_assembly.annotation.gtf
│   ├── GRCh38.primary_assembly.genome.fa
│   ├── filter.bed
│   └── blacklist.bed
├── opt/ → /groups/tprice/opt/  ← 10x tool tarballs
│   ├── cellranger-10.0.0/
│   ├── spaceranger-4.0.1/
│   └── xeniumranger-xenium4.0/
├── test_data/               ← smoke test data
└── configs/                 ← legacy example configs
```

### Per-user workspace (`/work/$USER/pipelines/`)

Created by `tjp-setup`:

```
/work/$USER/pipelines/
├── bulkrnaseq/
│   ├── config.yaml, samples.txt, samplesheet.csv
│   └── runs/YYYY-MM-DD_HH-MM-SS/
│       ├── config.yaml (snapshot), pipeline.config, manifest.json
│       ├── titan_metadata.json
│       ├── slurm_JOBID.out, slurm_JOBID.err
│       ├── inputs/ (rsync'd FASTQs)
│       └── outputs/ (rsync'd results)
├── psoma/ (same structure)
├── virome/ (config.yaml, samplesheet.csv, runs/)
├── sqanti3/ (config.yaml, samplesheet.csv, runs/)
├── wf-transcriptomes/ (config.yaml, samplesheet.csv, runs/)
├── cellranger/ (config.yaml, samplesheet.csv, runs/)
├── spaceranger/ (same)
├── xeniumranger/ (same)
├── addone/ (config.yaml, runs/)
└── metadata/
    └── pipeline_runs/
        └── PLR-xxxx.json     ← local Titan metadata records
```

### Per-user scratch (`/scratch/juno/$USER/pipelines/`)

```
/scratch/juno/$USER/pipelines/
├── bulkrnaseq/runs/<timestamp>/
│   ├── 2_star_mapping_output/
│   ├── 3_filter_output/
│   ├── 4_stringtie_counts_output/
│   └── 5_raw_counts_output/
├── psoma/runs/<timestamp>/
│   ├── 2_trim_output/
│   ├── 3_hisat2_mapping_output/
│   ├── 4_filter_output/
│   ├── 5_stringtie_counts_output/
│   └── 6_raw_counts_output/
├── virome/runs/<timestamp>/    (Nextflow writes directly here)
├── sqanti3/runs/<timestamp>/   (SQANTI3 outputs)
├── wf-transcriptomes/runs/<timestamp>/
├── cellranger/runs/<timestamp>/   (cell_ranger outputs)
├── spaceranger/runs/<timestamp>/
└── xeniumranger/runs/<timestamp>/
```

---

## 3. Symlinks & Bind Mounts

### Why symlinks matter

Juno uses **symlinked home directories** — `/home/$USER` may not be the real path. Apptainer containers resolve paths at the kernel level and need **real paths** to bind-mount directories. Always resolve with:

```bash
readlink -f /home/$USER
```

### Apptainer bind mounts

Containers cannot see the host filesystem by default. Our SLURM templates explicitly mount the three directories the pipeline needs:

```bash
apptainer exec \
    --bind $PROJECT_ROOT:$PROJECT_ROOT \    # shared repo (code, containers, refs)
    --bind $SCRATCH_ROOT:$SCRATCH_ROOT \    # user scratch (FASTQ input, outputs)
    --bind $WORK_ROOT:$WORK_ROOT \          # user work (configs, logs)
    $CONTAINER \
    nextflow run ...
```

Any path not under these three mounts is **invisible** inside the container. Native pipelines (10x tools) do not use Apptainer and have no bind mount restrictions.

### BulkRNASeq symlink strategy

The UTDal pipeline code cannot be modified (third-party repo). To redirect its outputs to scratch, `tjp-launch` symlinks all UTDal repo files into the scratch output directory:

```bash
# tjp-launch creates:
/scratch/juno/$USER/pipelines/bulkrnaseq/runs/<timestamp>/
    ├── bulk_rna_seq_nextflow_pipeline.nf → /groups/tprice/pipelines/Bulk-RNA-Seq-Nextflow-Pipeline/...
    ├── *.sh → (symlinked)
    ├── *.py → (symlinked)
    └── (pipeline writes outputs here alongside the symlinks)
```

The Nextflow config sets `config_directory` to this scratch path, so UTDal code finds scripts via symlinks and writes outputs to scratch.

### Psoma output_directory strategy

The psoma pipeline was modified to accept a separate `output_directory` parameter. Scripts and reference files are located via `config_directory` (pointing to the shared repo), while all outputs write to `output_directory` (pointing to scratch).

---

## 4. How Jobs Run

### Execution flow

```
1. User edits config.yaml (+ optional samplesheet.csv for batch-capable pipelines)
       │
2. User runs:  tjp-launch <pipeline>
            or tjp-batch <pipeline> samplesheet.csv
       │
3.     ├── Validates config YAML (per-pipeline validator in bin/lib/validate.sh)
       ├── Creates timestamped run dir:  /work/$USER/pipelines/<pipeline>/runs/<ts>/
       ├── Creates scratch output dir:   /scratch/juno/$USER/pipelines/<pipeline>/runs/<ts>/
       ├── Snapshots config.yaml into run dir
       ├── Generates Nextflow config from template (container-based pipelines)
       ├── Writes manifest.json (git commit, container checksum, paths)
       ├── Registers PLR-xxxx metadata record at /work/$USER/pipelines/metadata/pipeline_runs/
       └── Submits:  sbatch slurm_template.sh <args>
               │
4.             └── SLURM queues the job → assigns to a compute node
                       │
5.                     └── Compute node executes SLURM template:
                               │
                               ├── [Container pipelines]
                               │   ├── module load apptainer
                               │   ├── Pre-flight checks (container, pipeline, config exist)
                               │   └── apptainer exec --cleanenv ... $CONTAINER \
                               │           nextflow run pipeline.nf -c pipeline.config
                               │
                               └── [Native pipelines: cellranger, spaceranger, xeniumranger]
                                   ├── Pre-flight checks (tool path, config exist)
                                   └── containers/10x/bin/<tool>-run.sh config.yaml
                                           │
                                           └── <tool> --localcores N --localmem M ...
                                                   │
6.                                                 └── Pipeline writes outputs to scratch
                                                           │
7.                                                         └── Stage-out: rsync scratch → work
                                                               ├── inputs/ (FASTQs archived)
                                                               └── outputs/ (results archived)
```

### Batch launching (v6.0.0+)

`tjp-batch` accepts a CSV samplesheet and submits one SLURM job per sample row. Each row generates its own timestamped run directory and PLR-xxxx metadata record. The samplesheet format is pipeline-specific; templates live in `templates/<pipeline>/samplesheet.csv`.

### Parallelism levels

| Level | Description | State |
|-------|-------------|-------|
| **Within a tool** | HISAT2, STAR, samtools use `-p 20` threads | Done — 20 threads per tool |
| **Between steps** | Nextflow runs independent steps concurrently | Done — StringTie + featureCounts overlap |
| **Between samples** | Each sample processed independently | Available via tjp-batch (SLURM array) |
| **Between nodes** | Spread work across multiple compute nodes | Available via Nextflow SLURM executor (wf-transcriptomes) |

### Key flags (container pipelines)

| Flag | Purpose |
|------|---------|
| `--cleanenv` | Prevents host environment from leaking into container |
| `--env PYTHONNOUSERSITE=1` | Prevents host Python packages from shadowing container packages |
| `--env HOME=/tmp` | (Psoma) Lets Nextflow write to `~/.nextflow` inside container |
| `--env _JAVA_OPTIONS=-Xmx16g` | Sets Java heap for Trimmomatic |

---

## 5. Resource Allocation

### SLURM resource requests by pipeline

| Pipeline | Time | CPUs | RAM | Exclusive | Notes |
|----------|------|------|-----|-----------|-------|
| AddOne | 5 min | 1 | 1 GB | No | Demo only |
| BulkRNASeq | 12 h | 20 | 64 GB | No | Nextflow inside container |
| Psoma | 12 h | 20 | 64 GB | No | Nextflow inside container |
| Virome | 12 h | 16 | 128 GB | No | Nextflow on host |
| SQANTI3 | varies | varies | varies | No | 4-stage DAG, dynamic scaling by GTF transcript count |
| wf-transcriptomes | 24 h | 8 | 32 GB | No | Head job only; Nextflow submits per-process sub-jobs |
| Cell Ranger | 24 h | 16 | 128 GB | Yes | `--exclusive`; tool manages threading internally |
| Space Ranger | 24 h | 16 | 128 GB | Yes | `--exclusive`; tool manages threading internally |
| Xenium Ranger | 12 h | 16 | 128 GB | Yes | `--exclusive`; tool manages threading internally |

### Benchmark: Psoma 10-sample run (job 151456)

| Metric | Value |
|--------|-------|
| Wall time | 3 hours 24 minutes |
| Peak RAM | ~64 GB (maxed against request) |
| CPUs used | 20 |
| Exit status | COMPLETED |

### Efficiency vs node capacity (Psoma/BulkRNASeq)

```
               Requested    Node has     Utilization
CPUs:          20           64           31%
RAM:           64 GB        384 GB       17%
```

We're underutilizing the node's total capacity, but RAM peaked at our limit. Consider bumping RAM to 128 GB for runs with more than 10 samples.

---

## 6. Partition Selection

**We do not currently specify a partition for most pipelines.** SLURM templates contain no `#SBATCH --partition=` directive, so jobs go to `normal*` (the default partition, marked with `*` in `sinfo` output). The exception is the dev partition used by `tjp-test`.

This is appropriate for our workload — RNA-seq alignment is CPU-bound, not GPU-bound, and normal nodes have more than enough cores and RAM.

To explicitly set a partition, add to the SLURM template:

```bash
#SBATCH --partition=normal    # explicit (same as current default behavior)
#SBATCH --partition=dev       # for quick 2-hour test runs
```

GPU partitions (`a30`, `h100`) would require `--gres=gpu:1` and GPU-accelerated tools — not applicable to any of our current pipelines.

---

## 7. Optimization Opportunities

### Priority 1: Increase RAM request (low effort, high safety)

Our 10-sample psoma run peaked at exactly 64 GB. More samples or larger genomes could OOM.

```bash
# Change in slurm_templates/psoma_slurm_template.sh and bulkrnaseq_slurm_template.sh:
#SBATCH --mem=64G    →    #SBATCH --mem=128G
```

No downside — the node has 384 GB, and SLURM won't allocate more than the node has.

### Priority 2: Increase CPU request (low effort, moderate speedup)

HISAT2, STAR, samtools, and sambamba all scale with threads. We use 20 of 64 available cores.

```bash
#SBATCH --cpus-per-task=20    →    #SBATCH --cpus-per-task=40
```

Would need to update `fastqc_cores` in configs to match (this controls thread count passed to tools).

### Priority 3: Per-sample parallelism via tjp-batch (medium effort, large speedup)

**Current (single-sample):** One SLURM job processes one config/sample set.

**Available (v6.0.0+):** `tjp-batch` submits one SLURM job per samplesheet row, running N samples in parallel across N nodes. Each job gets its own run directory and metadata record.

For pipelines with Nextflow loops over multiple samples, consider converting the shell loops into proper Nextflow `process` blocks so Nextflow can parallelize within a single job (especially for psoma).

### Priority 4: Dev partition for testing (no effort)

For quick config validation or small test runs, use the `dev` partition (2-hour limit, usually empty):

```bash
#SBATCH --partition=dev
#SBATCH --time=02:00:00
```

`tjp-test` already uses the dev partition. You can also pass `--dev` conceptually by editing the template before submitting.

### Priority 5: Multi-node Nextflow (high effort, large-scale only)

`wf-transcriptomes` already uses this pattern — the head job runs Nextflow, which submits per-process SLURM jobs via `containers/sqanti3/configs/wf_transcriptomes/juno.config`. This scales to hundreds of samples across the full 75-node cluster. Other pipelines could adopt this pattern with effort.

### Not recommended currently

- **GPU partitions** — Our tools (HISAT2, STAR, samtools, 10x tools) are CPU-only. GPU-accelerated alternatives exist (NVIDIA Parabricks) but would require container rebuilds and pipeline rewrites.
- **Multi-node MPI** — RNA-seq alignment is embarrassingly parallel per-sample, not a single distributed computation. Job arrays or Nextflow SLURM executor are the right pattern.

---

## 8. Metadata and Titan Integration

### PLR-xxxx Records

Every pipeline launch (via `tjp-launch` or `tjp-batch`) automatically generates a **Pipeline Run Record** (PLR) — a JSON file stored locally at:

```
/work/$USER/pipelines/metadata/pipeline_runs/PLR-xxxx.json
```

Each PLR captures the key reproducibility and provenance fields for the run: pipeline name, version, git commit, container checksum, input paths, config snapshot path, SLURM job ID, timestamps, and run status. The schema is documented in `metadata/SCHEMA.md` in the shared repo.

### labdata CLI

The `labdata` tool (in `bin/`) provides a command-line interface for querying and managing local PLR records:

```bash
labdata list                        # list all local PLR records
labdata show PLR-0042               # print full JSON for one record
labdata search --pipeline psoma     # filter by pipeline
labdata search --status COMPLETED   # filter by run status
```

### Titan DB Integration (coming ~2026-Q4)

Titan is a genomics data lake planned for on-prem deployment (~6 months from 2026-04-05). Once live, PLR records will be synced from local JSON files to the Titan database automatically, enabling:

- Cross-user query of all pipeline runs in the group
- Input/output file tracking and lineage
- Integration with the Titan web UI for run monitoring
- Storage of pipeline outputs on `/store/<project>` (permanent NFS, see storage tiers table)

Until Titan is available, PLR records remain local to each user's work directory. No action is required from users — the local records will be importable once the Titan API is ready.
