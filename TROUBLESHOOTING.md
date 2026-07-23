# Hyperion Compute — Troubleshooting Guide

**Version:** 7.3.0 | **Cluster:** Juno HPC, UT Dallas | **Updated:** 2026-07-23

---

## Quick Symptom Lookup

| Symptom | Section |
|---------|---------|
| `tjp-launch: command not found` | [1.1 Commands not found](#11-commands-not-found) |
| `Config file not found` | [1.2 Config not found or not yet created](#12-config-not-found-or-not-yet-created) |
| `Container not found` (SIF missing) | [1.3 Container SIF not found](#13-container-sif-not-found) |
| `No validator for pipeline` | [1.4 Unrecognized pipeline name](#14-unrecognized-pipeline-name) |
| Job fails immediately | [2.1 Job fails immediately after submission](#21-job-fails-immediately-after-submission) |
| Job stuck in `PD` (pending) | [2.2 Job stuck in pending state](#22-job-stuck-in-pending-state) |
| SQANTI3 orchestrator pending indefinitely | [2.3 SQANTI3 DAG stuck pending](#23-sqanti3-dag-stuck-pending) |
| SLURM dependency failure | [2.4 SLURM dependency chain broken](#24-slurm-dependency-chain-broken) |
| `mount source doesn't exist` | [3.1 Bind mount source does not exist](#31-bind-mount-source-does-not-exist) |
| `No such file or directory` inside container | [3.2 File not visible inside container](#32-file-not-visible-inside-container) |
| `Read-only file system` | [3.3 Output directory not writable inside container](#33-output-directory-not-writable-inside-container) |
| `gocryptfs not found` warning | [3.4 gocryptfs warning](#34-gocryptfs-warning) |
| Host Python packages shadowing container | [3.5 Host environment leaking into container](#35-host-environment-leaking-into-container) |
| `run_fastqc` / `run_rna_pipeline` not recognized | [4.1 Nextflow params missing prefix](#41-nextflow-params-missing-the-params-prefix) |
| `No fastq.gz files found` | [4.2 No FASTQ files found](#42-no-fastq-files-found) |
| Wrong sample names / samples not processed | [4.3 Sample names do not match FASTQ prefixes](#43-sample-names-do-not-match-fastq-prefixes) |
| Job produces empty outputs | [4.4 Pipeline runs but produces no outputs](#44-pipeline-runs-but-produces-no-outputs) |
| Nextflow corrupted work directory | [4.5 Corrupted Nextflow work directory](#45-corrupted-nextflow-work-directory) |
| UTDal pipeline repo not found | [4.6 UTDal pipeline repo not cloned](#46-utdal-pipeline-repo-not-cloned) |
| Java OOM with Trimmomatic | [4.7 Trimmomatic Java out of memory](#47-trimmomatic-java-out-of-memory) |
| STAR out of memory | [4.8 STAR alignment out of memory](#48-star-alignment-out-of-memory) |
| `create_bam` error (Cell Ranger / Space Ranger) | [5.1 create_bam required in CR 10+ and SR 3+](#51-create_bam-required-in-cell-ranger-10-and-space-ranger-3) |
| Chemistry `SC3Pv3LT` not found | [5.2 SC3Pv3LT chemistry dropped in CR 10](#52-sc3pv3lt-chemistry-dropped-in-cell-ranger-10) |
| `sample_name` not matching FASTQs | [5.3 sample_name must match FASTQ filename prefix](#53-sample_name-must-match-fastq-filename-prefix) |
| `--exclusive` not preventing node sharing | [5.4 Unexpected node sharing on exclusive job](#54-unexpected-node-sharing-on-exclusive-job) |
| `segmentation_file` required error (Xenium) | [5.5 Xenium import-segmentation missing segmentation_file](#55-xenium-import-segmentation-missing-segmentation_file) |
| Slide serial number unknown (Space Ranger) | [5.6 Space Ranger slide serial number not available](#56-space-ranger-slide-serial-number-not-available) |
| SQANTI3 SIF missing | [6.1 SQANTI3 container not pulled](#61-sqanti3-container-not-pulled) |
| SQANTI3 filter report fails | [6.2 SQANTI3 filter report generation fails](#62-sqanti3-filter-report-generation-fails) |
| wf-transcriptomes sub-jobs not submitting | [6.3 wf-transcriptomes SLURM executor not submitting sub-jobs](#63-wf-transcriptomes-slurm-executor-not-submitting-sub-jobs) |
| Scratch full / disk quota exceeded | [7.1 Scratch full or disk quota exceeded](#71-scratch-full-or-disk-quota-exceeded) |
| Symlinked path breaks bind mount | [7.2 Symlinked home directory breaks Apptainer bind mounts](#72-symlinked-home-directory-breaks-apptainer-bind-mounts) |
| Permission denied on shared paths | [7.3 Permission denied on shared paths](#73-permission-denied-on-shared-paths) |
| Submodule not initialized | [7.4 Submodule not initialized](#74-submodule-not-initialized) |
| Script missing execute permission on HPC | [7.5 Script not executable after git pull](#75-script-not-executable-after-git-pull) |
| `labdata find runs` returns empty | [8.1 labdata find runs returns no results](#81-labdata-find-runs-returns-no-results) |
| `labdata show` — PLR record not found | [8.2 PLR record not found](#82-plr-record-not-found) |
| DeconvATAC `CUDA not available` / falls back to CPU | [9.1 DeconvATAC GPU not detected](#91-deconvatac-gpu-not-detected) |
| DeconvATAC multi-section spatial data mixed together | [9.2 spatial_batch_key not set](#92-spatial_batch_key-not-set) |
| `juno_environment.json` fields stuck at `null` | [10.1 sacct fields not populating](#101-sacct-fields-not-populating) |
| `invocation.log` / `juno_environment.json` missing from run dir | [10.2 Reproducibility files missing from a run directory](#102-reproducibility-files-missing-from-a-run-directory) |
| `tjp-test-suite` dies after 1-2 checks, no error shown | [10.3 tjp-test-suite stops silently after the first check](#103-tjp-test-suite-stops-silently-after-the-first-check) |

---

## 1. Framework / Launch Errors

### 1.1 Commands not found

**Error pattern:**
```
tjp-launch: command not found
hyperion-launch: command not found
```

**Cause:** `/groups/tprice/pipelines/bin` is not on your `PATH`. This happens if `tjp-setup` was never run, or if you have not sourced `~/.bashrc` since setup.

**Fix — current session only:**
```bash
export PATH="/groups/tprice/pipelines/bin:$PATH"
```

**Fix — permanently (if `tjp-setup` was not run):**
```bash
echo 'export PATH="/groups/tprice/pipelines/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**Fix — run setup (recommended for new users):**
```bash
/groups/tprice/pipelines/bin/tjp-setup
# Then log out and back in, or:
source ~/.bashrc
```

**Verify the PATH is set:**
```bash
echo $PATH | grep -o 'groups/tprice/pipelines/bin'
```

---

### 1.2 Config not found or not yet created

**Error pattern:**
```
ERROR: Config file not found: /work/<user>/pipelines/<pipeline>/config.yaml
```

**Cause:** `tjp-setup` was not run, or the config was deleted.

**Fix:**
```bash
# Run setup to create all workspace configs
/groups/tprice/pipelines/bin/tjp-setup

# Then edit the generated config
vi /work/$USER/pipelines/<pipeline>/config.yaml
```

> Re-running `tjp-setup` is safe — it does not overwrite existing configs.

---

### 1.3 Container SIF not found

**Error pattern:**
```
ERROR: Container not found: /groups/tprice/pipelines/containers/<pipeline>/<name>.sif
```

**Cause:** `.sif` files are not stored in git (they are large binaries). The container must be built locally and transferred, or pulled on the HPC.

**Fix — for container pipelines (bulkrnaseq, psoma, virome):**
```bash
# Build locally and transfer
scp containers/<pipeline>/<name>.sif \
    YOUR_NETID@juno.hpcre.utdallas.edu:/groups/tprice/pipelines/containers/<pipeline>/

# Or build on HPC with fakeroot
module load apptainer
cd /groups/tprice/pipelines/containers/<pipeline>
apptainer build --fakeroot <name>.sif <name>.def
```

**Fix — for SQANTI3:**
```bash
apptainer pull /groups/tprice/pipelines/containers/sqanti3/sqanti3_v5.5.4.sif \
    docker://anaconesalab/sqanti3:v5.5.4
```

**Fix — for virome (multiple per-process SIFs):**
```bash
rsync -avP containers/virome/containers/*.sif \
    YOUR_NETID@juno.hpcre.utdallas.edu:/groups/tprice/pipelines/containers/virome/containers/
```

---

### 1.4 Unrecognized pipeline name

**Error pattern:**
```
ERROR: Unknown pipeline: <name>
Known pipelines: addone bulkrnaseq psoma virome cellranger cellranger-mkfastq cellranger-multi spaceranger xeniumranger sqanti3 wf-transcriptomes
```

**Cause:** Typo in the pipeline name, or the pipeline has not been registered.

**Fix:** Use the exact pipeline name as listed. Note that `wf-transcriptomes` uses a hyphen, and multi-word 10x pipelines use hyphens (`cellranger-mkfastq`, `cellranger-multi`).

---

## 2. SLURM Errors

### 2.1 Job fails immediately after submission

**Symptom:** Job appears in `squeue` and disappears within seconds. `sacct` shows `FAILED` or `NODE_FAIL`.

**Diagnosis:**
```bash
# Check the error log
cat /work/$USER/pipelines/<pipeline>/runs/<timestamp>/slurm_<JOBID>.err

# Or for direct sbatch logs
cat /groups/tprice/pipelines/logs/<pipeline>_<JOBID>.err

# Check job accounting
sacct -j <JOBID> --format=JobID,State,ExitCode,Elapsed,MaxRSS
```

**Common causes and fixes:**

| Cause | What to look for in `.err` | Fix |
|-------|---------------------------|-----|
| Config path wrong | `Config file not found` | Verify `--config` path or run `tjp-setup` |
| Container path wrong | `No such file or directory: *.sif` | Transfer the SIF (see §1.3) |
| Missing `module load apptainer` | `apptainer: command not found` | Load module: `module load apptainer` |
| Insufficient memory | `slurmstepd: error: Exceeded job memory limit` | Increase `--mem` in SLURM template |
| Time limit too short | Job state is `TIMEOUT` | Increase `--time` in SLURM template |
| Working directory missing | `logs/: No such file or directory` | `mkdir -p /groups/tprice/pipelines/logs` |

---

### 2.2 Job stuck in pending state

**Symptom:** Job stays in `PD` state indefinitely.

**Diagnosis:**
```bash
squeue -u $USER --format="%i %j %T %M %l %R"
# The %R column shows the pending reason
```

**Common reasons:**

| Reason shown | Cause | Fix |
|--------------|-------|-----|
| `Resources` | Waiting for CPUs/memory to free up | Wait — normal on a busy cluster |
| `QOSMaxJobsPerUserLimit` | Hit per-user job limit | Cancel some jobs or wait |
| `DependencyNeverSatisfied` | A dependency job failed | See §2.4 |
| `PartitionNodeLimit` | Requesting more nodes than partition allows | Reduce resource request |
| `InvalidAccount` | Account not set or wrong | Contact HPC support |

---

### 2.3 SQANTI3 DAG stuck pending

**Symptom:** The SQANTI3 orchestrator job completes, but stage jobs never start, or the orchestrator itself is stuck pending.

**Most likely cause:** The `sqanti3_v5.5.4.sif` container file does not exist on the HPC.

**Fix:**
```bash
apptainer pull /groups/tprice/pipelines/containers/sqanti3/sqanti3_v5.5.4.sif \
    docker://anaconesalab/sqanti3:v5.5.4
```

After pulling, re-run:
```bash
tjp-launch sqanti3
```

---

### 2.4 SLURM dependency chain broken

**Error pattern:**
```
slurmstepd: error: *** JOB <ID> CANCELLED AT ... DUE TO DEPENDENCY
```
Or `sacct` shows a stage job in `CANCELLED` state with reason `DependencyNeverSatisfied`.

**Cause:** A preceding stage in a SLURM DAG (e.g., SQANTI3 stages 1a/1b/2/3) failed. SLURM cancels all downstream jobs that depended on it.

**Diagnosis:**
```bash
# Find which stage failed
sacct -u $USER --format=JobID,JobName,State,ExitCode,Elapsed --starttime=today
```

**Fix:** Identify the failed stage's `.err` log, fix the underlying issue, then re-run `tjp-launch sqanti3` to submit a fresh DAG.

---

## 3. Container / Apptainer Errors

### 3.1 Bind mount source does not exist

**Error pattern:**
```
FATAL:   container creation failed: mount source doesn't exist
FATAL:   while running container: ... /work/<user>: no such file or directory
```

**Cause:** The path being bind-mounted either does not exist or is a symlink that Apptainer cannot resolve.

**Fix:**
```bash
# Resolve the real path
readlink -f ~/work
readlink -f ~/scratch

# Use the resolved real path in your bind mount
# e.g., use /work/<user> not ~/work
```

---

### 3.2 File not visible inside container

**Error pattern:**
```
FileNotFoundError: [Errno 2] No such file or directory: '/groups/tprice/...'
```
or
```
Error: /scratch/juno/<user>/...: No such file or directory
```

**Cause:** The directory containing the file is not bind-mounted into the container.

**Fix:** Ensure the Apptainer command includes `--bind` for all directories the pipeline needs to read:
```bash
apptainer exec \
    --bind /groups/tprice/pipelines:/groups/tprice/pipelines \
    --bind /scratch/juno/$USER:/scratch/juno/$USER \
    --bind /work/$USER:/work/$USER \
    <container.sif> <command>
```

All framework-managed SLURM templates already include this three-way bind. If you are running Apptainer manually, include all three paths.

---

### 3.3 Output directory not writable inside container

**Error pattern:**
```
OSError: [Errno 30] Read-only file system: '/scratch/juno/<user>/output.txt'
PermissionError: [Errno 13] Permission denied: '/scratch/juno/<user>/...'
```

**Cause:** The output directory on the host is not bind-mounted into the container, so from inside the container it appears as part of the read-only container filesystem.

**Fix:** Add `--bind $SCRATCH_ROOT:$SCRATCH_ROOT` to the `apptainer exec` call. All framework SLURM templates include this automatically.

---

### 3.4 gocryptfs warning

**Warning pattern:**
```
WARNING: gocryptfs not found, user namespace encrypted overlay will not be available
```

**Cause:** This is an informational message from Apptainer about optional encrypted filesystem support.

**Fix:** Ignore it. The pipeline will run normally.

---

### 3.5 Host environment leaking into container

**Symptom:** Pipeline fails with import errors, module version conflicts, or unexpected behavior that works on a clean system.

**Cause:** Without `--cleanenv`, Apptainer inherits all host environment variables including `PYTHONPATH`, `LD_LIBRARY_PATH`, and `PATH`. Host-installed Python packages can shadow container packages.

**Fix:** Ensure the Apptainer invocation includes both flags:
```bash
apptainer exec --cleanenv --env PYTHONNOUSERSITE=1 <container.sif> <command>
```

- `--cleanenv`: strips all inherited host environment variables
- `PYTHONNOUSERSITE=1`: prevents Python from loading packages from `~/.local/lib/`

All framework SLURM templates for container-based pipelines already include both. Do not remove them.

---

## 4. BulkRNASeq / Psoma Errors

### 4.1 Nextflow params missing the `params.` prefix

**Error pattern:**
```
WARN: Config parameter 'run_fastqc' is not declared by pipeline
```
Or the setting appears to have no effect (FastQC runs when disabled, or pipeline doesn't start).

**Cause:** In the legacy `pipeline.config` (direct Nextflow config), parameters must use the `params.` prefix. Without it, Nextflow ignores them.

**Fix:**
```groovy
// Wrong:
run_fastqc = true
run_rna_pipeline = true

// Correct:
params.run_fastqc = true
params.run_rna_pipeline = true
```

> This applies to the raw `Bulk-RNA-Seq-Nextflow-Pipeline/pipeline.config` only. The `tjp-launch` workflow uses `config.yaml` and handles the translation automatically.

---

### 4.2 No FASTQ files found

**Error pattern:**
```
ERROR: No fastq.gz files found in /scratch/juno/<user>/...
```
Or Nextflow reports 0 samples and exits immediately.

**Cause:** The `fastq_dir` path in your config is wrong, the files don't exist yet, or the files use a different naming convention than expected.

**Diagnosis:**
```bash
# Verify the directory contains FASTQ files
ls /scratch/juno/$USER/<your-fastq-dir>/

# Check that names match the expected suffix
ls /scratch/juno/$USER/<your-fastq-dir>/*_R1_001.fastq.gz   # bulkrnaseq
ls /scratch/juno/$USER/<your-fastq-dir>/*_1.fastq.gz        # psoma
```

**Fix:**
- Correct `fastq_dir` in `config.yaml` to point to the directory containing your FASTQ files
- If your files use a different suffix (e.g., `_R1.fastq.gz` instead of `_R1_001.fastq.gz`), update `read1_suffix` / `read2_suffix` in the config

---

### 4.3 Sample names do not match FASTQ prefixes

**Symptom:** Pipeline runs but skips some or all samples, or errors with `No reads found for sample`.

**Cause:** Each line in `samples.txt` must exactly match the FASTQ filename stem — everything before `_R1_001` (bulkrnaseq) or `_1` (psoma).

**Example:**
```
FASTQs:          Patient01_S1_R1_001.fastq.gz
samples.txt:     Patient01_S1            ← correct (no suffix, no .fastq.gz)
                 Patient01               ← wrong (missing _S1)
```

**Fix — generate `samples.txt` automatically from your FASTQs:**
```bash
# BulkRNASeq
ls /scratch/juno/$USER/fastq/*_R1_001.fastq.gz \
  | xargs -n1 basename \
  | sed 's/_R1_001.fastq.gz//' \
  > /work/$USER/pipelines/bulkrnaseq/samples.txt

# Psoma
ls /scratch/juno/$USER/fastq/*_1.fastq.gz \
  | xargs -n1 basename \
  | sed 's/_1.fastq.gz//' \
  > /work/$USER/pipelines/psoma/samples.txt
```

---

### 4.4 Pipeline runs but produces no outputs

**Symptom:** The job completes, Nextflow exits with code 0, but output directories are empty or missing.

**Cause:** `run_rna_pipeline` is set to `false` in the config, which skips all alignment and counting steps.

**Fix:**
```yaml
run_rna_pipeline: true
```

Also verify `run_fastqc: true` if you need QC reports.

---

### 4.5 Corrupted Nextflow work directory

**Symptom:** A resumed or re-run Nextflow job fails with cache errors, process re-runs unexpectedly, or exits with errors like:
```
FATAL: Failed to execute process ... Caused by: Not a valid task record
```
Or the pipeline completes but outputs are missing.

**Cause:** A previously failed or interrupted run left a corrupt Nextflow cache at `/scratch/juno/$USER/nextflow_work`.

**Fix:** Delete the work directory and resubmit from scratch:
```bash
rm -rf /scratch/juno/$USER/nextflow_work
tjp-launch bulkrnaseq   # or psoma
```

---

### 4.6 UTDal pipeline repo not cloned

**Error pattern:**
```
ERROR: UTDal pipeline repo not found at /groups/tprice/pipelines/Bulk-RNA-Seq-Nextflow-Pipeline
```

**Cause:** The UTDal pipeline code is not a git submodule — it must be cloned separately on the HPC.

**Fix:**
```bash
cd /groups/tprice/pipelines
git clone https://github.com/utdal/Bulk-RNA-Seq-Nextflow-Pipeline.git
```

Verify the main Nextflow file is present (note: it is not named `main.nf`):
```bash
ls /groups/tprice/pipelines/Bulk-RNA-Seq-Nextflow-Pipeline/bulk_rna_seq_nextflow_pipeline.nf
```

---

### 4.7 Trimmomatic Java out of memory

**Symptom:** Psoma job fails during the trimming stage with:
```
java.lang.OutOfMemoryError: Java heap space
```

**Cause:** Trimmomatic spawns one JVM per thread. At 40 threads, the default JVM heap is insufficient.

**Fix:** The SLURM template already sets `_JAVA_OPTIONS=-Xmx16g`. If the error persists, reduce `--cpus-per-task` in the psoma SLURM template to limit the number of parallel Trimmomatic threads.

---

### 4.8 STAR alignment out of memory

**Symptom:** BulkRNASeq or Virome job fails during the STAR alignment step with:
```
EXITING because of FATAL ERROR: not enough memory for BAM sorting
```
or the SLURM job is killed with state `OUT_OF_MEMORY`.

**Cause:** STAR requires approximately 32 GB just for the human genome index. The full alignment can peak higher.

**Fix:** Increase `--mem` in the SLURM template:

| Dataset | Recommended `--mem` |
|---------|-------------------|
| Mouse genome | 64G |
| Human genome (up to 20 samples) | 128G |
| Human genome (50+ samples) | 256G |

```bash
# Override at submission time without editing the template
sbatch --mem=256G slurm_templates/bulkrnaseq_slurm_template.sh configs/my_config.yaml
```

---

## 5. 10x Genomics Errors

### 5.1 `create_bam` required in Cell Ranger 10+ and Space Ranger 3+

**Error pattern:**
```
[error] The --no-bam flag is now required if you do not want a BAM file...
```
or the job exits with a non-zero code immediately after Cell Ranger starts.

**Cause:** Starting with Cell Ranger 10.0.0 and Space Ranger 3.0, the tool no longer produces BAM files by default — you must explicitly opt in.

**Fix:** Add `create_bam: true` to your config:
```yaml
create_bam: true
```

---

### 5.2 SC3Pv3LT chemistry dropped in Cell Ranger 10

**Error pattern:**
```
[error] Unknown chemistry: SC3Pv3LT
```

**Cause:** The `SC3Pv3LT` (3' v3 LT) chemistry was removed in Cell Ranger 10.0.0.

**Fix:** Do not use `SC3Pv3LT`. If your library was prepared with 3' v3 chemistry, use `SC3Pv3` or `auto`:
```yaml
chemistry: auto
```
Contact the compute team if you have LT (Low Throughput) data that was sequenced with an affected kit.

---

### 5.3 `sample_name` must match FASTQ filename prefix

**Symptom:** Cell Ranger or Space Ranger reports 0 reads, or fails with:
```
[error] No input FASTQs were found for the requested sample
```

**Cause:** `sample_name` (or the `fastq_id` in a `libraries` block for cellranger-multi) must match the FASTQ filename prefix exactly. Cell Ranger looks for files matching `<sample_name>_S*_L*_R*.fastq.gz`.

**Fix:** Verify the FASTQ filenames:
```bash
ls /scratch/juno/$USER/fastq/
```

Set `sample_name` to the stem of the FASTQ files before the `_S1_L001_R1_001` part:
```yaml
sample_name: MySample   # if FASTQs are MySample_S1_L001_R1_001.fastq.gz
```

---

### 5.4 Unexpected node sharing on exclusive job

**Symptom:** A cellranger/spaceranger/xeniumranger job is running on a node that another user's job also occupies, causing resource contention or slower-than-expected performance.

**Cause:** The `--exclusive` SLURM flag should give the job a full node; if sharing is still observed, it may be a scheduler configuration issue.

**Diagnosis:**
```bash
squeue -j <JOBID> -o "%i %j %T %N %R"
```

**Fix:** Contact HPC support. The `--exclusive` flag is present in all 10x SLURM templates. Do not remove it — 10x tools expect full node access and use `--localcores` / `--localmem` to manage their own threading.

---

### 5.5 Xenium import-segmentation missing `segmentation_file`

**Error pattern:**
```
ERROR: segmentation_file is required when command is import-segmentation
```

**Cause:** The `import-segmentation` command requires a segmentation CSV file. The `resegment` command does not.

**Fix:** Add `segmentation_file` to your config when using `command: import-segmentation`:
```yaml
command: import-segmentation
segmentation_file: /scratch/juno/$USER/xenium/my_run_segmentation.csv
```

For `command: resegment`, leave `segmentation_file` blank or omit it.

---

### 5.6 Space Ranger slide serial number not available

**Symptom:** Space Ranger fails with an error about invalid slide serial number, or you do not have the slide serial number from your experiment.

**Fix:** Use `unknown_slide` instead of `slide` + `area`:
```yaml
# Remove or comment out:
# slide: V10J14-049
# area: A1

# Add:
unknown_slide: visium-1     # or visium-2, visium-2-large, visium-hd
```

`unknown_slide` takes precedence over `slide` + `area` — if both are present, `unknown_slide` is used.

---

## 6. Long-Read Pipeline Errors

### 6.1 SQANTI3 container not pulled

**Error pattern:**
```
FATAL: Unable to open image: containers/sqanti3/sqanti3_v5.5.4.sif: no such file or directory
```

**Cause:** The SQANTI3 SIF file must be pulled from Docker Hub on the HPC. It is not in git.

**Fix (run on HPC):**
```bash
apptainer pull /groups/tprice/pipelines/containers/sqanti3/sqanti3_v5.5.4.sif \
    docker://anaconesalab/sqanti3:v5.5.4
```

This takes several minutes. Once pulled, re-run `tjp-launch sqanti3`.

---

### 6.2 SQANTI3 filter report generation fails

**Symptom:** SQANTI3 stage 2 (filter) fails with an R error about a missing package:
```
Error in library("RColorConesa") : there is no package called 'RColorConesa'
```

**Cause:** The `RColorConesa` R package is absent from the SQANTI3 v5.5.4 container when running in standard mode (without a writable overlay).

**Fix:** Ensure `--writable-tmpfs` is passed when running the filter stage. The current framework templates already include this flag. If you are invoking SQANTI3 manually, add:
```bash
apptainer exec --writable-tmpfs /groups/tprice/pipelines/containers/sqanti3/sqanti3_v5.5.4.sif ...
```

Alternatively, set `skip_report: true` in your config to skip HTML report generation entirely (faster, no R dependency):
```yaml
skip_report: true
```

---

### 6.3 wf-transcriptomes SLURM executor not submitting sub-jobs

**Symptom:** The wf-transcriptomes head job is running, but no per-process SLURM jobs are being submitted. Nextflow hangs or produces empty output.

**Cause:** Nextflow cannot find the SLURM executor config, or the Juno-specific `juno.config` is not being picked up.

**Diagnosis:**
```bash
tail -f /work/$USER/pipelines/wf-transcriptomes/runs/<timestamp>/slurm_<JOBID>.out
# Look for: "Launching ... [juno]" and SLURM job IDs being submitted
```

**Fix:** Verify the Nextflow config exists:
```bash
ls /groups/tprice/pipelines/containers/sqanti3/configs/wf_transcriptomes/juno.config
```

If missing, the longreads submodule was not initialized:
```bash
cd /groups/tprice/pipelines
git submodule update --init --recursive
```

---

## 7. Filesystem / Path Errors

### 7.1 Scratch full or disk quota exceeded

**Symptom:** Job fails with:
```
OSError: [Errno 28] No space left on device
```
or writes fail silently, producing truncated output files.

**Diagnosis:**
```bash
df -h /scratch/juno/$USER
du -sh /scratch/juno/$USER/*
```

**Fix:**
```bash
# Delete Nextflow intermediate work directory (often several GB)
rm -rf /scratch/juno/$USER/nextflow_work

# Delete old scratch run directories for completed runs
# (outputs are archived to /work/$USER after successful runs)
ls /scratch/juno/$USER/pipelines/

# Check what's large
du -sh /scratch/juno/$USER/pipelines/*/runs/* | sort -h | tail -20
```

> Scratch is purged periodically by the cluster. Durable results are archived to `/work/$USER/pipelines/<pipeline>/runs/<timestamp>/outputs/` automatically after a successful `tjp-launch` run.

---

### 7.2 Symlinked home directory breaks Apptainer bind mounts

**Error pattern:**
```
FATAL: container creation failed: mount source doesn't exist: /home/<user>/work
```
Or files that exist on the host are not visible inside the container.

**Cause:** Juno uses symlinked home directories. `~/work` resolves through `/home/<user>/work` → `/work/<user>`. Apptainer requires the real resolved path for bind mounts.

**Fix:**
```bash
# Find the real path
readlink -f ~/work     # should return /work/<user>
readlink -f ~/scratch  # should return /scratch/juno/<user>

# Use the real path in bind mounts
apptainer exec --bind /work/$USER:/work/$USER ...
```

All framework SLURM templates use `/work/$USER` and `/scratch/juno/$USER` directly (real paths) and avoid `~/work`. If you are writing custom Apptainer commands, do the same.

---

### 7.3 Permission denied on shared paths

**Symptom:**
```
Permission denied: /groups/tprice/pipelines/...
```

**Cause:** Writing to the shared project root is restricted. Users should only write to their own `/work/$USER` and `/scratch/juno/$USER` directories.

**Fix:**
- Never write pipeline outputs to `/groups/tprice/pipelines/`
- Output paths in configs must point to `/scratch/juno/$USER/` or `/work/$USER/`
- If you need a new reference file or shared resource added, contact the compute team

---

### 7.4 Submodule not initialized

**Symptom:** A container submodule directory exists but is empty, or SLURM template fails because stage scripts are missing:
```
containers/sqanti3/slurm_templates/: No such file or directory
```

**Cause:** The repo was cloned without `--recurse-submodules`, or a new submodule was added after your initial clone.

**Fix:**
```bash
cd /groups/tprice/pipelines
git submodule update --init --recursive

# Check status (- prefix means not initialized, + means ahead of pinned commit)
git submodule status
```

---

### 7.5 Script not executable after git pull

**Symptom:**
```
bash: /groups/tprice/pipelines/bin/tjp-launch: Permission denied
```

**Cause:** Juno does not preserve filesystem execute bits from git. New scripts added to `bin/` must have execute permission set via `git update-index`.

**Fix (run by the repo maintainer before pushing):**
```bash
git update-index --chmod=+x bin/<new-script>
git commit -m "Add execute permission to <new-script>"
```

**Fix (if already deployed and the bit is missing):**
```bash
chmod +x /groups/tprice/pipelines/bin/<script-name>
```

---

## 8. Metadata / labdata Errors

### 8.1 `labdata find runs` returns no results

**Symptom:** `labdata find runs` prints an empty table or returns nothing.

**Cause:** This is not an error — it means no runs have been submitted from this workspace yet, or `tjp-launch` was never used (direct `sbatch` does not register metadata).

**Verify the metadata store exists:**
```bash
ls /work/$USER/pipelines/metadata/pipeline_runs/
labdata status
```

If the directory is empty, submit a run with `tjp-launch` and it will be populated automatically.

---

### 8.2 PLR record not found

**Error pattern:**
```
ERROR: Record not found: PLR-xxxx
```

**Cause:** The PLR ID does not exist in your local metadata store, or belongs to a different user's workspace.

**Fix — find valid PLR IDs:**
```bash
labdata find runs                          # list all your runs
labdata find runs --pipeline psoma         # filter by pipeline
labdata find runs --format json            # full JSON for scripting
```

**Fix — look up a run by output path instead:**
```bash
labdata find runs --format paths           # list output paths
```

**Checking what a specific run produced:**
```bash
labdata show PLR-xxxx                      # prints output_path field
ls $(labdata find runs --format paths | grep PLR-xxxx)
```

---

## 9. DeconvATAC Errors

### 9.1 DeconvATAC GPU not detected

**Symptom:** `dconvatac-gpu` job runs but logs show it fell back to CPU, or `use_gpu: true` has no effect.

**Cause:** `use_gpu: true` only takes effect on the `dconvatac-gpu` registry entry (A30 partition, `--nv` + `--gres=gpu:nvidia_a30:1`) — launching plain `dconvatac` always runs CPU-only regardless of this config key.

**Fix:**
```bash
tjp-launch dconvatac-gpu     # not: tjp-launch dconvatac
```

---

### 9.2 spatial_batch_key not set

**Symptom:** Multi-section spatial data is deconvolved as if it were one section; results look averaged/blended across sections.

**Cause:** `spatial_batch_key` (added in the dconvatac submodule after v1.0.0) tells Cell2Location which `.obs` column separates sections. If omitted, all spots are treated as one batch.

**Fix:** Set `spatial_batch_key` in your config to the `.obs` column name that identifies each spatial section.

---

## 10. Reproducibility Logging Errors

### 10.1 sacct fields not populating

**Symptom:** `juno_environment.json`'s `sacct_state`, `sacct_elapsed`, and `sacct_maxrss` fields are `null` even though the job completed successfully.

**Cause:** Not a bug — `sacct` backfill is best-effort. The job's own SLURM accounting record is usually not finalized by the scheduler until a few seconds after the job's `EXIT` trap fires, so a few retries are attempted but can still come up empty. `end_time`, `duration_seconds`, and `exit_code` are self-reported by the trap and always populate regardless.

**Fix (get the numbers manually):**
```bash
sacct -j <jobid> --format=State,Elapsed,MaxRSS
```

---

### 10.2 Reproducibility files missing from a run directory

**Symptom:** A run directory is missing `juno_environment.json`, `invocation.log`, `slurm_template_used.sh`, or `pipeline_source.tar.gz`.

**Cause:** Most commonly, the SLURM template was invoked manually with `sbatch <template>.sh <config>` instead of via `tjp-launch`/`tjp-batch` — with no `$RUN_DIR` argument, `capture_juno_env`/`run_logged`/the manifest snapshot functions all no-op gracefully rather than erroring. Always launch through `tjp-launch`/`tjp-batch` if you want these artifacts.

**Also check:** `pipeline_source.tar.gz` requires the pipeline's submodule to actually be a git checkout (`git -C containers/<name> rev-parse --git-dir`); a submodule directory that was copied in some other way (not `git submodule update --init`) will silently skip the snapshot.

---

### 10.3 tjp-test-suite stops silently after the first check

**Symptom:** (Fixed in v7.0.0 — noted here for anyone who hasn't pulled past that point.) `tjp-test-suite` prints one or two checkmarks per pipeline/layer and then exits with code 1, no error message, no summary report.

**Cause:** A `set -u`/`set -e` bug in `_ts_update_layer_status` (`bin/lib/test_framework.sh`) — fixed in v7.0.0. If you still see this, confirm your checkout includes the fix:
```bash
grep -n "two-step indirection" bin/lib/test_framework.sh
```
If that comment isn't present, `git pull` to pick up the fix.

---

*This document consolidates troubleshooting content from USER_GUIDE.md (§17), COMMAND_REFERENCE.md (§9), TJP_HPC_COMPLETE_GUIDE.md (§13), and BULKRNASEQ_HPC_GUIDE.md. Update it when new error patterns are identified or framework behavior changes.*
