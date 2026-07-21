# Glossary — Hyperion Compute / TJP HPC Framework

Definitions for terms that appear throughout the documentation. If a term isn't here, check `COMMAND_REFERENCE.md` §8 (Path & Environment Reference) or the `metadata/SCHEMA.md`.

---

## A

**Apptainer**
A container runtime for HPC environments, previously called Singularity. Packages an entire software environment (OS, libraries, tools) into a single `.sif` file. Unlike Docker, Apptainer runs without root privileges, making it safe for shared HPC clusters. Used by all container-based pipelines in this framework.

**Archive (stage-out)**
After a successful pipeline run, results are copied from scratch to the durable work directory using `rsync --checksum`. The work copy is the canonical result; scratch is the working copy. See also: *scratch*, *work directory*.

---

## B

**BCL (Base Call)**
The raw output format from Illumina sequencers. BCL files store per-cycle base calls and quality scores. Before running Cell Ranger count or other alignment pipelines, BCL files must be demultiplexed into per-sample FASTQ files using `cellranger mkfastq`.

**Batch run**
A `tjp-batch` invocation that submits multiple pipeline jobs from a CSV samplesheet. Two modes exist: *per-row* (one SLURM job per CSV row, for 10x and long-read pipelines) and *per-sheet* (one SLURM job for all rows, for Nextflow pipelines like BulkRNASeq, Psoma, and Virome). See `ONBOARDING.md §3.5`.

**Bind mount**
An Apptainer mechanism that makes a host directory visible inside a container at a specified path. For example, `--bind /scratch/juno/$USER:/scratch` makes your scratch directory accessible as `/scratch` inside the container. Required because containers are isolated from the host filesystem by default.

---

## C

**Cell2Location**
The deconvolution method used by the DeconvATAC pipeline to estimate cell-type abundance at each spatial location from a paired single-cell reference. Runs on CPU or GPU (`use_gpu: true` in config, only meaningful with `dconvatac-gpu`). See *DeconvATAC*.

**CellPlex**
A 10x Genomics sample multiplexing technology using Cell Multiplexing Oligos (CMOs). Multiple samples are pooled into one GEM well and later demultiplexed computationally. Processed using `cellranger multi` with `feature_types: Multiplexing Capture`.

**CITE-seq**
Cellular Indexing of Transcriptomes and Epitopes by Sequencing. Simultaneously measures gene expression and surface protein abundance by adding antibody-derived tags (ADTs) to a single-cell library. Requires `feature_types: Antibody Capture` in `cellranger multi`.

**Config YAML**
A plain YAML file that parameterizes a pipeline run — input paths, output paths, reference files, resource limits, and optional metadata fields. Lives at `/work/$USER/pipelines/<pipeline>/config.yaml`. Snapshotted into the run directory at launch time.

---

## D

**DAG (Directed Acyclic Graph)**
A workflow where stages have defined dependencies and no cycles. In this framework, SQANTI3 uses a 4-stage SLURM DAG: stages 1a and 1b run in parallel, then stage 2 depends on both, then stage 3 depends on stage 2. The orchestrator script wires this with `--dependency afterok:<job_id>`.

**DeconvATAC**
Spatial ATAC deconvolution pipeline using Cell2Location, submoduled at `containers/dconvatac/`. Two registered pipelines: `dconvatac` (CPU) and `dconvatac-gpu` (A30 GPU). Python (not Nextflow) — both the container definition and pipeline script live in the submodule. See *Cell2Location*.

**Dev partition**
A SLURM partition on Juno limited to 2 hours of wall time. Used for smoke testing and quick validation. Submit to it with `tjp-launch <pipeline> --dev` or `tjp-batch <pipeline> samplesheet.csv --dev`.

---

## E

**EPI2ME**
Oxford Nanopore Technologies' bioinformatics analysis platform. The `wf-transcriptomes` pipeline uses the EPI2ME `wf-transcriptomes` Nextflow workflow, which Nextflow pulls automatically at runtime via `epi2me-labs/wf-transcriptomes`.

**Exclusive node**
A SLURM job flag (`--exclusive`) that gives a job sole access to a compute node. Required for 10x native pipelines, which use the node's full memory and I/O capacity. Prevents resource contention with other jobs.

---

## F

**FASTQ**
The standard sequencing read file format. Contains read sequences and per-base quality scores. Named for the FASTA format with Quality scores added.

**Feature-barcode matrix**
The primary output of Cell Ranger (count and multi). A sparse matrix with cells as columns and genomic features (genes, antibodies, CRISPR guides) as rows, quantifying how many UMIs of each feature were detected in each cell.

**Flex (Fixed RNA Profiling)**
A 10x Genomics single-cell protocol using fixed, crosslinked cells rather than fresh tissue. Enables cell preservation before sequencing. Processed with `cellranger multi` using `feature_types: Fixed RNA Profiling`.

---

## G

**GEX (Gene Expression)**
Standard single-cell RNA-seq library measuring mRNA abundance. The primary library type for `cellranger count`. In `cellranger multi`, specified as `feature_types: Gene Expression`.

**GTF (General Transfer Format / Gene Transfer Format)**
A text file format describing genomic features (genes, transcripts, exons) and their coordinates. Used as reference annotations by STAR, HISAT2, StringTie, SQANTI3, and others.

**Groups directory**
`/groups/tprice/pipelines` — the shared HPC location where the framework code, containers, and reference files are deployed. All users share this; no user-specific data goes here.

---

## H

**Hyperion Compute**
The internal branding name for this framework. Synonymous with "TJP HPC Pipeline Framework" and "BioCruiser." All three refer to the same system. The `hyperion-*` and `biocruiser-*` CLI aliases are identical to `tjp-*`.

---

## I

**invocation.log**
A file written into every run directory recording the exact, fully-quoted, resolved command line for the pipeline invocation (or, for SQANTI3, all four DAG-stage `sbatch` calls), captured by `run_logged` in `bin/lib/repro.sh` immediately before running it.

---

## J

**Juno**
The HPC cluster at UT Dallas used by the TJP group. Runs SLURM for job scheduling. Access via `ssh YOUR_NETID@juno.hpcre.utdallas.edu`. The framework is deployed to `/groups/tprice/pipelines` on Juno.

**juno_environment.json**
A reproducibility file written into every run directory by `bin/lib/repro.sh`: SLURM job ID, node, partition, allocated CPUs/mem/GPU, requested time limit, start/end time, duration, exit code, and best-effort `sacct` accounting. Captured at job start (`capture_juno_env`) and finalized via an `EXIT` trap (`finalize_juno_env`). See also: *manifest.json*.

---

## L

**labdata**
The CLI tool for querying local pipeline run metadata (`PLR-xxxx` records). Provides `find`, `show`, `status`, and `new-id` subcommands. Will eventually sync records to the Titan PostgreSQL database.

**LIB-xxxx**
A Titan sequencing library identifier. Optional metadata field in config YAMLs (`titan_library_id: LIB-xxxx`).

**localcores / localmem**
Config keys that limit how many CPU cores and how much memory (in GB) a 10x Genomics tool uses internally. Should be set slightly below the SLURM allocation (`--cpus-per-task` and `--mem`) to leave headroom for the OS and wrapper overhead.

---

## M

**manifest.json**
A reproducibility record created in every run directory at launch time. Records the git commit, container file and checksum, SLURM job ID, pipeline name, and Titan run ID. See `ONBOARDING.md §7`.

**Multi CSV**
The input format for `cellranger multi`. Describes library types and FASTQ paths in a structured CSV format. In this framework, the wrapper script (`cellranger-multi-run.sh`) generates this CSV from your YAML config automatically — you never write it by hand.

---

## N

**Native pipeline**
A pipeline that uses a tool installed directly on the HPC rather than inside an Apptainer container. Cell Ranger, Space Ranger, and Xenium Ranger are native pipelines. Identified by `is_native_pipeline()` in `bin/lib/common.sh`.

**Nextflow**
A workflow manager that orchestrates complex multi-step pipelines with automatic parallelism, error retry, and environment isolation. Used by BulkRNASeq and Psoma (inside containers), and by Virome and wf-transcriptomes (running natively on the compute node).

---

## P

**Per-row (batch mode)**
Batch mode where `tjp-batch` submits one SLURM job per CSV row. Used by 10x (cellranger, spaceranger, etc.) and long-read pipelines (sqanti3, wf-transcriptomes). Contrast with *per-sheet*.

**Per-sheet (batch mode)**
Batch mode where `tjp-batch` submits a single SLURM job for all CSV rows, and the pipeline (Nextflow) handles per-sample parallelism internally. Used by BulkRNASeq, Psoma, and Virome.

**pipeline_source.tar.gz**
A frozen `git archive HEAD` of the pipeline's submodule source (or `pipelines/addone/` for the inline demo), written into every run directory by `snapshot_pipeline_source` in `bin/lib/manifest.sh` at manifest-generation time — so a later submodule bump doesn't retroactively change what an old run "was."

**Pipeline run record**
See *PLR-xxxx*.

**PLR-xxxx**
A locally generated pipeline run ID assigned to every `tjp-launch` and `tjp-batch` invocation. Format: `PLR-` followed by a 4-character hex string. Stored as a JSON file in `/work/$USER/pipelines/metadata/pipeline_runs/PLR-xxxx.json`. Will sync to the Titan PostgreSQL database when Titan comes online.

**PRJ-xxxx**
A Titan project identifier. Optional metadata field in config YAMLs (`titan_project_id: PRJ-xxxx`).

---

## R

**repro.sh**
`bin/lib/repro.sh` — the shared library sourced by every SLURM template that captures Juno runtime environment (*juno_environment.json*) and logs the exact pipeline invocation (*invocation.log*). See `CLAUDE.md` §"Reproducibility & Provenance Logging".

**RUN-xxxx**
A Titan sequencing run identifier. Optional metadata field in config YAMLs (`titan_run_id: RUN-xxxx`).

**Run directory**
A timestamped directory created by `tjp-launch` for every pipeline submission. Path: `/work/$USER/pipelines/<pipeline>/runs/YYYY-MM-DD_HH-MM-SS/`. Contains the config snapshot, manifest, SLURM logs, and after completion, archived inputs and outputs.

---

## S

**Samplesheet**
A CSV file used with `tjp-batch` to describe multiple samples. Each row represents one sample (per-row mode) or one entry in a multi-sample run (per-sheet mode). Required columns differ per pipeline; defined in `_SAMPLESHEET_REQUIRED_COLS` in `bin/lib/samplesheet.sh`.

**Scratch directory**
`/scratch/juno/$USER/` — fast, temporary storage on Juno. Pipeline outputs are written here during execution. Wiped every 45 days. After a successful run, outputs are archived from scratch to the work directory. Never use scratch for durable storage.

**SIF (Singularity/Apptainer Image File)**
The binary container image built from a `.def` definition file. Portable and self-contained. Not stored in git (too large); built locally and transferred to HPC via `scp`. Apptainer runs `.sif` files with `apptainer exec`.

**SLURM**
Simple Linux Utility for Resource Management. The job scheduler on Juno. Users submit jobs with `sbatch`; SLURM allocates a compute node with the requested CPUs, memory, and walltime and runs the script.

**SMP-xxxx**
A Titan biological sample identifier. Optional metadata field in config YAMLs (`titan_sample_id: SMP-xxxx`).

**Submodule**
A git repository embedded inside another git repository at a fixed commit. The framework uses six submodules under `containers/` for pipeline container definitions and wrapper scripts. Update with `git submodule update --init --recursive`. See `CONTRIBUTING.md §5`.

---

## T

**Titan**
The TJP group's planned Laboratory Information Management System (LIMS) and data registry. Currently in development (estimated availability ~6 months from v6.0.0 release, April 2026). When online, `labdata` will sync local `PLR-xxxx` records to a PostgreSQL database and expose a web UI for browsing runs. All config YAMLs have optional `titan_*` fields in preparation.

**tjp-launch**
The primary CLI tool for submitting a single pipeline run. Creates a timestamped run directory, snapshots the config, validates it, generates the reproducibility manifest, submits the SLURM job, and registers a Titan metadata record.

**tjp-test-suite**
The primary testing tool: a three-layer test harness (offline validation, registry/wiring checks, full SLURM execution) run per-pipeline or for all registered pipelines. Supersedes the deprecated `tjp-test`/`tjp-test-validate`. Test modules live in `bin/lib/tests/test_<pipeline>.sh`.

**Tool path**
The directory where a native 10x tool is installed (e.g., `/groups/tprice/opt/cellranger-10.0.0`). Overridable per-run with `tool_path:` in the config YAML — useful for testing a new tool version without changing the default.

---

## V

**VDJ**
Variable, Diversity, and Joining gene segments — the recombination mechanism for T cell receptor (TCR) and B cell receptor (BCR) diversity. Sequencing VDJ regions ("immune profiling") captures clonotype information. Requires `cellranger multi` with `feature_types: VDJ-T` (T cell) or `VDJ-B` (B cell), plus a VDJ reference.

---

## W

**Work directory**
`/work/$USER/` — durable (but not infinite) storage on Juno. Run directories, archived inputs, and outputs live here. Pipeline outputs are rsync'd from scratch to work after successful completion for long-term retention.

**Wrapper script**
For native 10x pipelines, a bash script in `containers/10x/bin/` that reads the YAML config and constructs the appropriate `cellranger`/`spaceranger`/`xeniumranger` command. Abstracts away tool-specific CLI flags from the framework.

---

## Y

**yaml_get**
A `grep`/`awk`-based YAML key reader defined in `bin/lib/common.sh`. Not a full YAML parser — only handles flat key-value pairs (no nested keys, no lists). Pipelines with complex YAML (e.g., `cellranger-multi`'s `libraries:` block) handle their own parsing in the wrapper script.
