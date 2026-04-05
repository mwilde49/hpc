# Bulk RNA-Seq Pipeline — HPC Guide

This guide covers running the UTDal Bulk RNA-Seq Nextflow Pipeline on Juno HPC using the containerized environment from the `mwilde49/bulkseq` repo.

---

## Three-Repo Relationship

| Repo | Role | Location on HPC |
|------|------|-----------------|
| `mwilde49/hpc` | Deployment layer: SLURM templates, configs, docs | `/groups/tprice/pipelines` |
| `mwilde49/bulkseq` | Container definition + build/test scripts (submodule) | `/groups/tprice/pipelines/containers/bulkrnaseq/` |
| `utdal/Bulk-RNA-Seq-Nextflow-Pipeline` | Pipeline code (Nextflow workflows) | `/groups/tprice/pipelines/Bulk-RNA-Seq-Nextflow-Pipeline/` |

The HPC repo pins `bulkseq` as a git submodule. The UTDal pipeline repo is cloned separately on the HPC (it is not a submodule).

---

## Part 1: First-Time Setup Through Test Analysis

This walks through everything from a fresh start to a validated test run.

### 1.1 Clone the HPC repo with submodules

```bash
ssh <username>@<hpc-host>
cd /groups/tprice/pipelines
git clone --recurse-submodules https://github.com/mwilde49/hpc.git .
```

If you already cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

Verify the submodule is present:

```bash
git submodule status
# Should show: 7259423... containers/bulkrnaseq (v1.0.0)
ls containers/bulkrnaseq/
# Should show: bulkrnaseq.def, build.sh, test_container.sh, etc.
```

### 1.2 Get the container

The `.sif` file is too large for git. Either build it on the HPC (if `--fakeroot` is available):

```bash
module load apptainer
cd /groups/tprice/pipelines/containers/bulkrnaseq
apptainer build --fakeroot bulkrnaseq_v1.0.0.sif bulkrnaseq.def
```

Or build locally and transfer:

```bash
# On your local machine:
cd containers/bulkrnaseq
sudo ./build.sh

# Transfer to HPC:
scp bulkrnaseq_v1.0.0.sif <username>@<hpc-host>:/groups/tprice/pipelines/containers/bulkrnaseq/
```

Verify on HPC:

```bash
ls -lh /groups/tprice/pipelines/containers/bulkrnaseq/bulkrnaseq_v1.0.0.sif
```

### 1.3 Clone the UTDal pipeline repo

```bash
cd /groups/tprice/pipelines
git clone https://github.com/utdal/Bulk-RNA-Seq-Nextflow-Pipeline.git
```

Verify:

```bash
ls Bulk-RNA-Seq-Nextflow-Pipeline/bulk_rna_seq_nextflow_pipeline.nf
```

Note: the main Nextflow file is `bulk_rna_seq_nextflow_pipeline.nf`, **not** `main.nf`.

### 1.4 Generate test data

The bulkseq repo includes a test data generator. You must bind-mount the project root so the container can see the script:

```bash
cd /groups/tprice/pipelines/containers/bulkrnaseq
module load apptainer

apptainer exec \
  --bind /groups/tprice/pipelines:/groups/tprice/pipelines \
  bulkrnaseq_v1.0.0.sif \
  python3 /groups/tprice/pipelines/containers/bulkrnaseq/generate_test_data.py
```

Verify:

```bash
ls test_data/
# Should show: genes.gtf  genome.fa  ref_human_geneid_genename_genebiotype.tsv
#              sample1_R1_001.fastq.gz  sample1_R2_001.fastq.gz
```

This creates:
- A synthetic 10,000 bp genome (`genome.fa`)
- 3 test genes with splice junctions (`genes.gtf`)
- 200 paired-end read pairs (`sample1_R1_001.fastq.gz`, `sample1_R2_001.fastq.gz`)
- Gene ID/name/biotype mapping file

### 1.5 Create the samples file

The pipeline needs a file listing sample names (one per line):

```bash
echo "sample1" > /groups/tprice/pipelines/Bulk-RNA-Seq-Nextflow-Pipeline/rna_seq_samples.txt
```

### 1.6 Configure the pipeline for test data

Edit the UTDal pipeline config:

```bash
vi /groups/tprice/pipelines/Bulk-RNA-Seq-Nextflow-Pipeline/pipeline.config
```

Set these values (use full real paths, no `~`):

```
params.config_directory = '/groups/tprice/pipelines/Bulk-RNA-Seq-Nextflow-Pipeline'
params.fastq_files = '/groups/tprice/pipelines/containers/bulkrnaseq/test_data'
params.samples_file = '/groups/tprice/pipelines/Bulk-RNA-Seq-Nextflow-Pipeline/rna_seq_samples.txt'

params.star_index = '/groups/tprice/pipelines/containers/bulkrnaseq/test_data'
params.reference_gtf = '/groups/tprice/pipelines/containers/bulkrnaseq/test_data/genes.gtf'
```

**Important**: The `run_fastqc` and `run_rna_pipeline` flags at the bottom of the config must use the `params.` prefix or Nextflow won't see them. Change them to:

```
params.run_fastqc = true
params.run_rna_pipeline = false
```

Start with just FastQC (`run_fastqc = true`, `run_rna_pipeline = false`) to smoke-test the integration before running the full pipeline.

Save and exit vim: press `Esc`, type `:wq`, press `Enter`.

### 1.7 Submit the test job

```bash
cd /groups/tprice/pipelines
mkdir -p logs
sbatch slurm_templates/bulkrnaseq_slurm_template.sh
```

### 1.8 Monitor

```bash
# Job status
squeue -u $USER

# Watch logs in real time
tail -f logs/bulkrnaseq_*.out

# After completion
cat logs/bulkrnaseq_<jobid>.out
cat logs/bulkrnaseq_<jobid>.err
```

### 1.9 Verify success

Look for Nextflow's completion message in the `.out` log. If FastQC ran successfully, you can then re-edit the config to enable the full pipeline:

```
params.run_fastqc = true
params.run_rna_pipeline = true
```

And resubmit:

```bash
sbatch slurm_templates/bulkrnaseq_slurm_template.sh
```

---

## Part 2: Loading New Data for Real Analysis

Once you've validated the pipeline with test data, here's how to run it on your own FASTQ files.

### 2.1 Transfer your FASTQ files to the HPC

From your local machine or data source, transfer FASTQs to a directory on the HPC. Use scratch for large data:

```bash
# Create a directory for your project's data
mkdir -p /scratch/juno/<username>/myproject/fastq

# Transfer from local machine
scp /path/to/your/*.fastq.gz <username>@<hpc-host>:/scratch/juno/<username>/myproject/fastq/
```

Or if copying from another location on the HPC:

```bash
cp /path/to/shared/data/*.fastq.gz /scratch/juno/<username>/myproject/fastq/
```

Verify your files landed and look right:

```bash
ls -lh /scratch/juno/<username>/myproject/fastq/
```

Files should follow the naming pattern: `<samplename>_R1_001.fastq.gz` and `<samplename>_R2_001.fastq.gz` for paired-end data. If your files use a different suffix, you'll update `params.read1_suffix` and `params.read2_suffix` in the config.

### 2.2 Prepare the STAR genome index

If you don't already have a STAR index for your reference genome, you'll need to generate one. This is a one-time step per genome/annotation version.

```bash
mkdir -p /scratch/juno/<username>/star_index

apptainer exec \
  --cleanenv \
  --env PYTHONNOUSERSITE=1 \
  --bind /groups/tprice/pipelines:/groups/tprice/pipelines \
  --bind /scratch/juno/<username>:/scratch/juno/<username> \
  /groups/tprice/pipelines/containers/bulkrnaseq/bulkrnaseq_v1.0.0.sif \
  STAR --runMode genomeGenerate \
  --genomeDir /scratch/juno/<username>/star_index \
  --genomeFastaFiles /path/to/genome.fa \
  --sjdbGTFfile /path/to/annotation.gtf \
  --runThreadN 20
```

This requires significant memory (~32G for human). You may want to run it as its own SLURM job or in an interactive session:

```bash
srun --time=02:00:00 --mem=40G --cpus-per-task=20 --pty bash
```

### 2.3 Create the samples file

List your sample names (one per line), without the read suffix or `.fastq.gz` extension.

For example, if your files are:

```
Patient01_S1_R1_001.fastq.gz
Patient01_S1_R2_001.fastq.gz
Patient02_S2_R1_001.fastq.gz
Patient02_S2_R2_001.fastq.gz
```

Then your samples file should contain:

```
Patient01_S1
Patient02_S2
```

Create it:

```bash
vi /groups/tprice/pipelines/Bulk-RNA-Seq-Nextflow-Pipeline/rna_seq_samples.txt
```

Or generate it from your FASTQ filenames:

```bash
ls /scratch/juno/<username>/myproject/fastq/*_R1_001.fastq.gz \
  | xargs -n1 basename \
  | sed 's/_R1_001.fastq.gz//' \
  > /groups/tprice/pipelines/Bulk-RNA-Seq-Nextflow-Pipeline/rna_seq_samples.txt
```

Verify:

```bash
cat /groups/tprice/pipelines/Bulk-RNA-Seq-Nextflow-Pipeline/rna_seq_samples.txt
```

### 2.4 Edit the pipeline config

```bash
vi /groups/tprice/pipelines/Bulk-RNA-Seq-Nextflow-Pipeline/pipeline.config
```

Update these fields for your data:

```
params.proj_name = 'My-Project-Name'
params.species = 'Human'  // or 'Mouse', 'Rattus'

params.config_directory = '/groups/tprice/pipelines/Bulk-RNA-Seq-Nextflow-Pipeline'
params.fastq_files = '/scratch/juno/<username>/myproject/fastq'
params.samples_file = '/groups/tprice/pipelines/Bulk-RNA-Seq-Nextflow-Pipeline/rna_seq_samples.txt'

params.star_index = '/scratch/juno/<username>/star_index'
params.reference_gtf = '/path/to/annotation.gtf'

params.paired_end = true   // false for single-end
params.read1_suffix = "_R1_001"   // adjust to match your filenames
params.read2_suffix = "_R2_001"   // adjust to match your filenames

params.run_fastqc = true
params.run_rna_pipeline = true
```

If you have BED files for filtering/blacklisting:

```
params.exclude_bed_file_path = '/path/to/filter.bed'
params.blacklist_bed_file_path = '/path/to/blacklist.bed'
```

If not, leave them as-is — Nextflow will warn but continue.

### 2.5 Adjust SLURM resources if needed

The default template requests 20 CPUs, 64G RAM, and 12 hours. For a real human dataset you may need more:

```bash
vi /groups/tprice/pipelines/slurm_templates/bulkrnaseq_slurm_template.sh
```

Typical adjustments:

| Dataset | `--mem` | `--time` | `--cpus-per-task` |
|---------|---------|----------|-------------------|
| Test data (synthetic) | 64G | 00:30:00 | 20 |
| Small (2-4 samples, mouse) | 64G | 04:00:00 | 20 |
| Medium (10-20 samples, human) | 128G | 12:00:00 | 20 |
| Large (50+ samples, human) | 128G | 24:00:00 | 20 |

STAR alignment is the memory bottleneck — human genomes need ~32G just for the index.

### 2.6 Submit

```bash
cd /groups/tprice/pipelines
mkdir -p logs
sbatch slurm_templates/bulkrnaseq_slurm_template.sh
```

### 2.7 Monitor and collect results

```bash
# Job status
squeue -u $USER

# Watch logs
tail -f logs/bulkrnaseq_*.out

# After completion, check for errors
cat logs/bulkrnaseq_<jobid>.err
```

Outputs will be in the directories specified in your `pipeline.config`.

### 2.8 Clean up after a successful run

Nextflow's work directory can be very large (intermediate BAMs for every process step). Clean it once you've verified your results:

```bash
rm -rf /scratch/juno/<username>/nextflow_work
```

---

## Updating the Container Version

When the `bulkseq` repo releases a new version:

```bash
# On your local machine
cd containers/bulkrnaseq
git fetch --tags
git checkout v2.0.0
cd ../..
git add containers/bulkrnaseq
git commit -m "Update bulkrnaseq submodule to v2.0.0"
git push

# Build and transfer
cd containers/bulkrnaseq
sudo ./build.sh
scp bulkrnaseq_v2.0.0.sif <username>@<hpc-host>:/groups/tprice/pipelines/containers/bulkrnaseq/

# On HPC: pull and update the SLURM template .sif filename
cd /groups/tprice/pipelines
git pull
git submodule update --init --recursive
# Edit slurm_templates/bulkrnaseq_slurm_template.sh to reference new .sif
```

---

## Troubleshooting

### "Container not found" error

The SLURM template expects the container at `$PROJECT_ROOT/containers/bulkrnaseq/bulkrnaseq_v1.0.0.sif`. Build it with `./build.sh` in the submodule directory and transfer it to the HPC.

### "UTDal pipeline repo not found" error

Clone the UTDal repo:

```bash
cd /groups/tprice/pipelines
git clone https://github.com/utdal/Bulk-RNA-Seq-Nextflow-Pipeline.git
```

### "No such file or directory" when running scripts inside the container

Apptainer can't see host files unless their directories are bind-mounted. Use `--bind` with real paths:

```bash
apptainer exec \
  --bind /groups/tprice/pipelines:/groups/tprice/pipelines \
  bulkrnaseq_v1.0.0.sif \
  python3 /groups/tprice/pipelines/containers/bulkrnaseq/generate_test_data.py
```

### `run_fastqc` / `run_rna_pipeline` not recognized

These config params must use the `params.` prefix:

```
// Wrong:
run_fastqc = true

// Right:
params.run_fastqc = true
```

### Bind mount errors

Apptainer needs real paths, not symlinks. The SLURM template uses `/groups/tprice/pipelines` for the project root and auto-detects user paths via `$USER` (`/scratch/juno/$USER`, `/work/$USER`). If your paths differ, edit the template. Resolve symlinks with `readlink -f ~/work`.

### `--cleanenv` flag

Required to prevent host environment variables from leaking into the container and causing conflicts. Do not remove it.

### `PYTHONNOUSERSITE=1`

Prevents Python from loading packages from `~/.local/lib/`. Without it, host-installed Python packages can shadow container packages and cause version conflicts.

### STAR aligner runs out of memory

STAR requires ~32G for human genome indexing/alignment. Increase `--mem` in the SLURM template to `128G` if needed.

### Nextflow caching issues

If a resumed run behaves unexpectedly, clear the work directory and resubmit:

```bash
rm -rf /scratch/juno/<username>/nextflow_work
sbatch slurm_templates/bulkrnaseq_slurm_template.sh
```

### "gocryptfs not found" warning

Informational message from Apptainer. Ignore it — it's a warning, not an error.

---

## Batch Execution (v6.0.0)

Run all samples from a CSV samplesheet in one command:

```bash
# Edit the samplesheet template (created by tjp-setup)
vi /work/$USER/pipelines/bulkrnaseq/samplesheet.csv

# Launch all rows as a single SLURM job
tjp-batch bulkrnaseq /work/$USER/pipelines/bulkrnaseq/samplesheet.csv \
    --config /work/$USER/pipelines/bulkrnaseq/config.yaml
```

Samplesheet format (one sample per row):

```
sample,fastq_1,fastq_2
Patient01,/scratch/juno/$USER/fastq/Patient01_R1_001.fastq.gz,/scratch/juno/$USER/fastq/Patient01_R2_001.fastq.gz
Patient02,/scratch/juno/$USER/fastq/Patient02_R1_001.fastq.gz,/scratch/juno/$USER/fastq/Patient02_R2_001.fastq.gz
```

The batch launcher automatically:
- Infers `fastq_dir` from the first row's `fastq_1` path
- Generates a `samples_file` from the `sample` column
- Submits one SLURM job for all samples (Nextflow handles per-sample parallelism)

Optional Titan metadata columns: `project_id,sample_id,library_id,run_id`

---

## Titan Integration (v6.0.0)

Add optional Titan metadata fields to your `config.yaml` to associate runs with Titan IDs:

```yaml
# ── Titan Integration (optional) ─────────────────────────────────────────────
titan_project_id:   # PRJ-xxxx
titan_sample_id:    # SMP-xxxx
titan_library_id:   # LIB-xxxx
titan_run_id:       # RUN-xxxx
```

These fields are recorded in a local PLR-xxxx metadata record (viewable with `labdata show PLR-xxxx`)
and will sync to the Titan database when it comes online. They are not passed to the Nextflow pipeline.
