# TJP Next Generation Bulk RNA-Seq Pipelines, High Performance Computing Edition — User Guide

This guide covers how to configure and run the two bulk RNA-seq pipelines available on the TJP HPC system (Juno). You do **not** need admin access, any special training, or to build anything — containers and references are already installed. All you need is this guide. Feel free to reach out to me (Michael) with any questions.

|    **Component**       |    **BulkRNASeq (UTDal)**          |    **Psoma (Psomagen)**         |
|------------------------|------------------------------------|---------------------------------|
| Aligner                | STAR                               | HISAT2                          |
| Trimming               | Clip-based (5'/3' hard trim)       | Trimmomatic (adapter + quality) |
| Typical data source    | Standard Illumina sequencing cores | Psomagen sequencing service     |
| Read suffix convention | `_R1_001` / `_R2_001`              | `_1` / `_2`                     |

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [One-Time Setup](#2-one-time-setup)
3. [Uploading Your Data](#3-uploading-your-data)
4. [BulkRNASeq Pipeline (UTDal/STAR)](#4-bulkrnaseq-pipeline-utdalstar)
5. [Psoma Pipeline (HISAT2/Trimmomatic)](#5-psoma-pipeline-hisat2trimmomatic)
6. [Launching a Pipeline](#6-launching-a-pipeline)
7. [Monitoring Your Job](#7-monitoring-your-job)
8. [Finding Your Results](#8-finding-your-results)
9. [Re-running and Reproducibility](#9-re-running-and-reproducibility)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Prerequisites

- An active Juno HPC account
- SSH access to `juno.hpcre.utdallas.edu`
- FASTQ files from your RNA-seq experiment

Log in:

```bash
ssh YOUR_NETID@juno.hpcre.utdallas.edu
```

---

## 2. One-Time Setup

Run the setup command to create your personal workspace:

```bash
/groups/tprice/pipelines/bin/tjp-setup
```

This creates:

```
/work/$USER/pipelines/
├── addone/          ← demo pipeline (ignore)
│   └── config.yaml
├── bulkrnaseq/      ← UTDal/STAR pipeline
│   ├── config.yaml
│   └── samples.txt
└── psoma/           ← Psomagen/HISAT2 pipeline
    ├── config.yaml
    └── samples.txt
```

Add the pipeline tools to your PATH (do this each session, or add to your `~/.bashrc`):

```bash
export PATH="/groups/tprice/pipelines/bin:$PATH"
```
```bash
echo 'export PATH="/groups/tprice/pipelines/bin:$PATH"' >> ~/.bashrc
```

I would recommend doing the second if you intend to use this more than once

---

## 3. Uploading Your Data

Transfer your FASTQ files to your scratch directory. From your **local machine**:

```bash
scp -r /path/to/fastq_files/ YOUR_NETID@juno.hpcre.utdallas.edu:/scratch/juno/YOUR_NETID/myproject/fastq/
```

Or use `rsync` for large transfers (in case it crashes):

```bash
rsync -avP /path/to/fastq_files/ YOUR_NETID@juno.hpcre.utdallas.edu:/scratch/juno/YOUR_NETID/myproject/fastq/
```




Verify on Juno:

```bash
ls /scratch/juno/$USER/myproject/fastq/
```

You should see paired files like:
- BulkRNASeq: `SampleA_R1_001.fastq.gz`, `SampleA_R2_001.fastq.gz`
- Psoma: `SampleA_1.fastq.gz`, `SampleA_2.fastq.gz`

NOTE: If not running paired, we'll need to reconfigure some settings; find a member of the compute team. Making this something you can do is on the to-do list :)

---

## 4. BulkRNASeq Pipeline (UTDal/STAR)

Use this pipeline for standard Illumina-sequenced bulk RNA-seq data from the UTD Core

### Step 1: Create your samples file

Edit the samples file — one sample name per line, **without** the read suffix or `.fastq.gz` extension:
(these editors are annoying, be careful when using them)


```bash
vi /work/$USER/pipelines/bulkrnaseq/samples.txt
```
or
```bash
nono /work/$USER/pipelines/bulkrnaseq/samples.txt
```
(I would suggest nano)

Example — if your files are:

```
Patient01_S1_R1_001.fastq.gz
Patient01_S1_R2_001.fastq.gz
Patient02_S2_R1_001.fastq.gz
Patient02_S2_R2_001.fastq.gz
```

Then your `samples.txt` should contain:

```
Patient01_S1
Patient02_S2
```

(Alternatively, you can create this file on your own work station and then ship it in with a scp command; this is easiest, will add later)

(add command here)



### Step 2: Edit your config

```bash
vi /work/$USER/pipelines/bulkrnaseq/config.yaml
```

The fields you **must** edit:

```yaml
project_name: My-Experiment                              # give it a name
fastq_dir: /scratch/juno/YOUR_NETID/myproject/fastq      # the path to where your FASTQs are
samples_file: /work/YOUR_NETID/pipelines/bulkrnaseq/samples.txt   # the path to the text file containing the list of samples being run 
```

Fields you **may** need to change:

|    Field           |   Default |      When to change                             |
|--------------------|-----------|-------------------------------------------------|
| `species`          | `Human`   | Set to `Mouse` or `Rattus` if applicable        |
| `paired_end`       | `true`    | Set to `false` for single-end data              |
| `read1_suffix`     | `_R1_001` | If your files use a different naming convention |
| `read2_suffix`     | `_R2_001` | Same as above                                   |
| `clip5_num`        | `11`      | Adjust 5' clipping length                       |
| `clip3_num`        | `5`       | Adjust 3' clipping length                       |
| `run_fastqc`       | `true`    | Set to `false` to skip QC reports               |
| `run_rna_pipeline` | `true`    | Set to `false` to run only FastQC               |

Fields you should **not** change (shared references are pre-installed):

```yaml
star_index: /groups/tprice/pipelines/references/star_index
reference_gtf: /groups/tprice/pipelines/references/gencode.v48.primary_assembly.annotation.gtf
exclude_bed_file_path: /groups/tprice/pipelines/references/filter.bed
blacklist_bed_file_path: /groups/tprice/pipelines/references/blacklist.bed
```

Alternatively, you can create these file on your own work station and then ship it in with a scp command

```bash
scp config.yaml NETID@juno.hpcre.utdallas.edu:/work/NETID/pipelines/bulkrnaseq/config.yaml
scp samples.txt NETID@juno.hpcre.utdallas.edu:/work/NETID/pipelines/bulkrnaseq/samples.txt
```

### Step 3: Launch

```bash
tjp-launch bulkrnaseq
```

---

## 5. Psoma Pipeline (HISAT2/Trimmomatic)

Use this pipeline for Psomagen-sequenced bulk RNA-seq data. It uses HISAT2 alignment with Trimmomatic adapter/quality trimming (Nextera adapters).

### Step 1: Create your samples file

```bash
vi /work/$USER/pipelines/psoma/samples.txt
```

Example — if your files are:

```
Sample_19_1.fastq.gz
Sample_19_2.fastq.gz
Sample_20_1.fastq.gz
Sample_20_2.fastq.gz
```

Then your `samples.txt` should contain:

```
Sample_19
Sample_20
```



### Step 2: Edit your config

```bash
vi /work/$USER/pipelines/psoma/config.yaml
```

The fields you **must** edit:

```yaml
project_name: My-Psomagen-Experiment                     # give it a name
fastq_dir: /scratch/juno/YOUR_NETID/myproject/fastq      # where your FASTQs are
samples_file: /work/YOUR_NETID/pipelines/psoma/samples.txt
```

Fields you **may** need to change:

|     Field          | Default |     When to change                              |
|--------------------|---------|-------------------------------------------------|
| `species`          | `Human` | Set to `Mouse` or `Rattus` if applicable        |
| `paired_end`       | `true`  | Set to `false` for single-end data              |
| `read1_suffix`     | `_1`    | If your files use a different naming convention |
| `read2_suffix`     | `_2`    | Same as above                                   |
| `headcrop`         | `10`    | Number of bases to hard-clip from read start    |
| `run_fastqc`       | `true`  | Set to `false` to skip QC reports               |
| `run_rna_pipeline` | `true`  | Set to `false` to run only FastQC               |

Trimmomatic defaults (rarely need changing):

|      Field            |     Default      |        Description                      |
|-----------------------|------------------|-----------------------------------------|
| `leading`             | `3`              | Cut bases from start below this quality |
| `trailing`            | `3`              | Cut bases from end below this quality   |
| `slidingwindow`       | `4:15`           | Window size:quality threshold           |
| `minlen`              | `36`             | Drop reads shorter than this            |
| `illuminaclip_params` | `2:30:10:5:true` | Adapter matching stringency             |

Fields you should **not** change (shared references are pre-installed):

```yaml
hisat2_index: /groups/tprice/pipelines/references/hisat2_index/gencode48
reference_gtf: /groups/tprice/pipelines/references/gencode.v48.primary_assembly.annotation.gtf
exclude_bed_file_path: /groups/tprice/pipelines/references/filter.bed
blacklist_bed_file_path: /groups/tprice/pipelines/references/blacklist.bed
```

Alternatively, you can create these files on your own computer and then ship it in with an scp command

```bash
scp config.yaml NETID@juno.hpcre.utdallas.edu:/work/NETID/pipelines/psoma/config.yaml
scp samples.txt NETID@juno.hpcre.utdallas.edu:/work/NETID/pipelines/psoma/samples.txt
```

### Step 3: Launch

```bash
tjp-launch psoma
```

---

## 6. Launching a Pipeline

Both pipelines are launched the same way:

```bash
tjp-launch bulkrnaseq    # UTDal/STAR pipeline
tjp-launch psoma          # Psomagen/HISAT2 pipeline
```

You'll see output like:

```
=== Launching psoma pipeline ===

[INFO]  Validating config: /work/jsmith/pipelines/psoma/config.yaml
[INFO]  Config validation passed.
[INFO]  Run directory: /work/jsmith/pipelines/psoma/runs/2026-03-04_14-30-00
[INFO]  Scratch output dir: /scratch/juno/jsmith/pipelines/psoma/runs/2026-03-04_14-30-00

=== Job submitted ===

  Pipeline:   psoma
  Job ID:     151456
  Run dir:    /work/jsmith/pipelines/psoma/runs/2026-03-04_14-30-00/
  Output dir: /scratch/juno/jsmith/pipelines/psoma/runs/2026-03-04_14-30-00/
  Monitor:    tail -f /work/jsmith/pipelines/psoma/runs/2026-03-04_14-30-00/slurm_151456.out
  Cancel:     scancel 151456
```

To use a custom config location:

```bash
tjp-launch psoma --config /path/to/my_custom_config.yaml
```

---

## 7. Monitoring Your Job
You will want to monitor the tail of 99% of jobs to ensure they have launched properly.

### Check job status

```bash
squeue -u $USER
```

### Watch live output

```bash
# stdout (pipeline progress)
tail -f /work/$USER/pipelines/<pipeline>/runs/<timestamp>/slurm_<JOBID>.out

# stderr (warnings/errors)
tail -f /work/$USER/pipelines/<pipeline>/runs/<timestamp>/slurm_<JOBID>.err
```

NOTE: The exact `tail -f` command is printed when you launch — just copy and paste it.

Press `Ctrl+C` to stop watching (this does **not** cancel the job).

### Cancel a job

```bash
scancel <JOBID>
```

---

## 8. Finding Your Results

Pipeline outputs are written to your **scratch** directory:

```
/scratch/juno/$USER/pipelines/<pipeline>/runs/<timestamp>/
```

### BulkRNASeq output directories

|        Directory                 |         Contents                   |
|----------------------------------|------------------------------------|
| `1_fastqc_and_multiqc_reports/`  | FastQC and MultiQC quality reports |
| `3_star_mapping_output/`         | STAR-aligned BAM files             |
| `3_1_map_metrics_output_qc/`     | Alignment statistics               |
| `4_filter_output/`               | Filtered/deduplicated BAMs         |
| `4_1_qualimap_filter_output_qc/` | Post-filter QC reports             |
| `5_stringtie_counts_output/`     | StringTie transcript counts        |
| `6_raw_counts_output/`           | HTSeq + featureCounts raw counts   |

### Psoma output directories

|       Directory                  |  Contents                          |
|----------------------------------|------------------------------------|
| `0_nextflow_logs/`               | Per-step Nextflow logs             |
| `1_fastqc_and_multiqc_reports/`  | FastQC and MultiQC quality reports |
| `2_trim_output/`                 | Trimmomatic-trimmed reads          |
| `3_hisat2_mapping_output/`       | HISAT2-aligned BAM files           |
| `3_1_map_metrics_output_qc/`     | Alignment statistics + MultiQC     |
| `4_filter_output/`               | Filtered/deduplicated BAMs         |
| `4_1_qualimap_filter_output_qc/` | Post-filter QC reports             |
| `5_stringtie_counts_output/`     | StringTie transcript counts (TPM)  |
| `6_raw_counts_output/`           | HTSeq + featureCounts raw counts   |
| `7_pipeline_stats_*.log`         | Software versions and run summary  |

### Key output files for downstream analysis

- **`6_raw_counts_output/raw_htseq_counts.csv`** — Raw gene counts (for DESeq2, edgeR)
- **`6_raw_counts_output/raw_feature_counts.csv`** — featureCounts gene counts
- **`5_stringtie_counts_output/genes_tpm.txt`** — TPM-normalized expression values

### Run metadata

Logs and reproducibility info are in your **work** directory:

```
/work/$USER/pipelines/<pipeline>/runs/<timestamp>/
├── config.yaml        ← frozen copy of your config
├── pipeline.config    ← generated Nextflow config
├── manifest.json      ← full reproducibility record
├── slurm_<JOBID>.out  ← job stdout
└── slurm_<JOBID>.err  ← job stderr
```

---

## 9. Re-running and Reproducibility

- Each launch creates a **new** timestamped run directory. Previous runs are never overwritten.
- The `manifest.json` file records the exact git commit, container checksum, config, and paths used — so any run can be reproduced.
- To re-run with the same config, just run `tjp-launch` again. To re-run an old config, point to its snapshot:

```bash
tjp-launch psoma --config /work/$USER/pipelines/psoma/runs/2026-03-04_14-30-00/config.yaml
```

---

## 10. Troubleshooting

|         Problem                     |                                 Solution                                                           |
|-------------------------------------|----------------------------------------------------------------------------------------------------|
| `tjp-launch: command not found`     | Run: `export PATH="/groups/tprice/pipelines/bin:$PATH"`                                            |
| `Config file not found`             | Run `tjp-setup` first to create your workspace                                                     |
| `Container not found`               | Contact the pipeline administrator — the `.sif` file needs to be transferred to HPC                |
| Job fails immediately               | Check the `.err` file: `cat /work/$USER/pipelines/<pipeline>/runs/<timestamp>/slurm_*.err`         |
| `No fastq.gz files found`           | Verify `fastq_dir` path in your config points to the right directory                               |
| Wrong sample names                  | Each line in `samples.txt` must match the FASTQ filename prefix exactly (before `_R1_001` or `_1`) |
| Job runs but produces empty outputs | Check that `run_rna_pipeline: true` is set in your config                                          |
| `module: command not found`         | You may be on a login node that doesn't support modules — try a different login node               |

### Getting help

You can contact me or another member of Price Lab's Compute Team for help with any of this. We're happy to troubleshoot or teach.


Michael Wilde
281-793-3180
maw210003@utdalls.edu
