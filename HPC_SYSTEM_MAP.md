# Juno HPC System Map & Pipeline Architecture

Technical reference for the TJP pipeline system on Juno HPC at UT Dallas.

---

## Table of Contents

1. [Cluster Overview](#1-cluster-overview)
2. [Storage & Directory Structure](#2-storage--directory-structure)
3. [Symlinks & Bind Mounts](#3-symlinks--bind-mounts)
4. [How Jobs Run Today](#4-how-jobs-run-today)
5. [Current Resource Allocation](#5-current-resource-allocation)
6. [Partition Selection](#6-partition-selection)
7. [Optimization Opportunities](#7-optimization-opportunities)

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

### Shared repo layout (`/groups/tprice/pipelines/`)

```
/groups/tprice/pipelines/
├── bin/                          ← CLI tools (tjp-setup, tjp-launch)
│   └── lib/                      ← shared bash libraries
├── containers/
│   ├── addone_latest.sif         ← demo container
│   ├── bulkrnaseq/               ← submodule: mwilde49/bulkseq
│   │   └── bulkrnaseq_v1.0.0.sif
│   └── psoma/                    ← submodule: mwilde49/psoma
│       ├── psomagen_v1.0.0.sif
│       ├── psomagen_bulk_rna_seq_pipeline.nf
│       ├── *.sh                  ← pipeline shell scripts
│       ├── *.py                  ← pipeline Python scripts
│       ├── ref_*_geneid_*.tsv    ← species reference files
│       ├── NexteraPE-PE.fa       ← Trimmomatic adapter file
│       └── pipeline.config       ← default Nextflow config
├── Bulk-RNA-Seq-Nextflow-Pipeline/  ← cloned UTDal repo
├── pipelines/addone/             ← inline demo pipeline
├── references/                   ← shared reference files
│   ├── star_index/               ← STAR genome index
│   ├── hisat2_index/             ← HISAT2 genome index
│   ├── gencode.v48.primary_assembly.annotation.gtf
│   ├── filter.bed
│   └── blacklist.bed
├── slurm_templates/              ← SLURM job scripts
├── templates/                    ← per-pipeline config templates
└── configs/                      ← legacy example configs
```

### Per-user workspace (`/work/$USER/pipelines/`)

Created by `tjp-setup`:

```
/work/$USER/pipelines/
├── bulkrnaseq/
│   ├── config.yaml           ← user edits this
│   ├── samples.txt           ← sample names
│   └── runs/
│       └── 2026-03-04_21-22-19/
│           ├── config.yaml       ← frozen snapshot
│           ├── pipeline.config   ← generated Nextflow config
│           ├── manifest.json     ← reproducibility metadata
│           ├── slurm_151456.out  ← stdout
│           └── slurm_151456.err  ← stderr
└── psoma/
    ├── config.yaml
    ├── samples.txt
    └── runs/
        └── 2026-03-04_21-22-19/
            └── (same structure)
```

### Per-user outputs (`/scratch/juno/$USER/`)

```
/scratch/juno/$USER/
├── fastq/                        ← uploaded FASTQ files (input)
├── nextflow_work/                ← Nextflow intermediate files
└── pipelines/
    ├── bulkrnaseq/runs/
    │   └── 2026-03-04_21-22-19/  ← pipeline output (numbered dirs)
    └── psoma/runs/
        └── 2026-03-04_21-22-19/
            ├── 0_nextflow_logs/
            ├── 1_fastqc_and_multiqc_reports/
            ├── 2_trim_output/
            ├── 3_hisat2_mapping_output/
            ├── 3_1_map_metrics_output_qc/
            ├── 4_filter_output/
            ├── 4_1_qualimap_filter_output_qc/
            ├── 5_stringtie_counts_output/
            ├── 6_raw_counts_output/
            └── 7_pipeline_stats_*.log
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

Any path not under these three mounts is **invisible** inside the container.

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

## 4. How Jobs Run Today

### Execution flow

```
1. User runs:  tjp-launch psoma
       │
2.     ├── Validates user config YAML
       ├── Creates timestamped run dir:  /work/$USER/pipelines/psoma/runs/<ts>/
       ├── Creates scratch output dir:   /scratch/juno/$USER/pipelines/psoma/runs/<ts>/
       ├── Generates Nextflow config from YAML template (sed substitution)
       ├── Writes manifest.json (git commit, container checksum, paths)
       └── Submits:  sbatch slurm_template.sh pipeline.config
               │
3.             └── SLURM queues the job → assigns to a compute node
                       │
4.                     └── Compute node executes SLURM script:
                               │
                               ├── module load apptainer
                               ├── Pre-flight checks (container exists, pipeline exists, config exists)
                               └── apptainer exec --cleanenv ... $CONTAINER \
                                       nextflow run pipeline.nf -c pipeline.config -w $SCRATCH/nextflow_work
                                           │
5.                                         └── Nextflow orchestrates pipeline steps:
                                               ├── FastQC/MultiQC (if enabled)
                                               ├── Trimmomatic trimming (psoma) / Clip trimming (UTDal)
                                               ├── HISAT2 mapping (psoma) / STAR mapping (UTDal)
                                               ├── Mapping metrics + MultiQC
                                               ├── Filter/deduplicate (sambamba + bedtools)
                                               ├── Qualimap QC
                                               ├── StringTie counts ──┐
                                               ├── featureCounts ─────┤ (these run in parallel)
                                               ├── HTSeq counts ──────┘
                                               └── Pipeline stats summary
```

### Parallelism levels

| Level | Description | Current state |
|-------|-------------|---------------|
| **Within a tool** | HISAT2, STAR, samtools use `-p 20` threads | Done — 20 threads per tool |
| **Between steps** | Nextflow runs independent steps concurrently | Done — StringTie + featureCounts overlap |
| **Between samples** | Each sample processed independently | **Not yet** — samples loop sequentially |
| **Between nodes** | Spread work across multiple compute nodes | **Not yet** — single node per job |

### Key flags

| Flag | Purpose |
|------|---------|
| `--cleanenv` | Prevents host environment from leaking into container |
| `--env PYTHONNOUSERSITE=1` | Prevents host Python packages from shadowing container packages |
| `--env HOME=/tmp` | (Psoma) Lets Nextflow write to `~/.nextflow` inside container |
| `--env _JAVA_OPTIONS=-Xmx16g` | Sets Java heap for Trimmomatic |

---

## 5. Current Resource Allocation

### What we request (SLURM templates)

| Setting | Psoma / BulkRNASeq | AddOne |
|---------|--------------------|--------|
| Partition | normal (implicit default) | normal (implicit default) |
| CPUs | 20 | 1 |
| RAM | 64 GB | 1 GB |
| Wall time | 12 hours | 5 minutes |
| Nodes | 1 (implicit) | 1 |

### Benchmark: Psoma 10-sample run (job 151456)

| Metric | Value |
|--------|-------|
| Wall time | 3 hours 24 minutes |
| Peak RAM | ~64 GB (maxed against request) |
| CPUs used | 20 |
| Exit status | COMPLETED |

### Efficiency vs node capacity

```
               Requested    Node has     Utilization
CPUs:          20           64           31%
RAM:           64 GB        384 GB       17%
```

We're underutilizing the node's total capacity, but RAM peaked at our limit.

---

## 6. Partition Selection

**We do not currently specify a partition.** Our SLURM templates contain no `#SBATCH --partition=` directive, so jobs go to `normal*` (the default partition, marked with `*` in `sinfo` output).

This is appropriate for our workload — RNA-seq alignment is CPU-bound, not GPU-bound, and normal nodes have more than enough cores and RAM.

To explicitly set a partition, you would add to the SLURM template:

```bash
#SBATCH --partition=normal    # explicit (same as current default behavior)
#SBATCH --partition=dev       # for quick 2-hour test runs
```

GPU partitions (`a30`, `h100`) would require `--gres=gpu:1` and GPU-accelerated tools — not applicable to our current pipelines.

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

### Priority 3: Per-sample parallelism (medium effort, large speedup)

**Current:** One SLURM job loops through N samples sequentially.

**Target:** Each sample runs as a separate Nextflow process (or SLURM job array task), running in parallel.

Two approaches:

**A. Nextflow-native (preferred for psoma):**
Convert the shell loops in Trimmomatic/HISAT2 into proper Nextflow `process` blocks that operate on individual samples. Nextflow automatically parallelizes processes with no dependencies.

**B. SLURM job arrays (works for both pipelines):**
```bash
#SBATCH --array=1-10
# Each array task reads one sample name from the samples file
SAMPLE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" samples.txt)
```
Each array task gets its own node allocation and runs one sample. 10 samples finish in the time of 1.

### Priority 4: Dev partition for testing (no effort)

For quick config validation or small test runs, use the `dev` partition (2-hour limit, usually empty):

```bash
#SBATCH --partition=dev
#SBATCH --time=02:00:00
```

Could add a `--dev` flag to `tjp-launch` to enable this.

### Priority 5: Multi-node Nextflow (high effort, large-scale only)

Nextflow supports `executor = 'slurm'` mode where each Nextflow process submits its own SLURM job. This would distribute samples across multiple nodes automatically. Complex to set up but scales to hundreds of samples across the full 75-node cluster.

### Not recommended currently

- **GPU partitions** — Our tools (HISAT2, STAR, samtools) are CPU-only. GPU-accelerated alternatives exist (NVIDIA Parabricks) but would require container rebuilds and pipeline rewrites.
- **Multi-node MPI** — RNA-seq alignment is embarrassingly parallel per-sample, not a single distributed computation. Job arrays or Nextflow SLURM executor are the right pattern.
