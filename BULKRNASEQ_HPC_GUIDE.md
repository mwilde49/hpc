# Bulk RNA-Seq Pipeline — HPC Guide

This guide covers running the UTDal Bulk RNA-Seq Nextflow Pipeline on Juno HPC using the containerized environment from the `mwilde49/bulkseq` repo.

---

## Three-Repo Relationship

| Repo | Role | Location on HPC |
|------|------|-----------------|
| `mwilde49/hpc` | Deployment layer: SLURM templates, configs, docs | `~/work/projects/tjp/` |
| `mwilde49/bulkseq` | Container definition + build/test scripts (submodule) | `~/work/projects/tjp/containers/bulkrnaseq/` |
| `utdal/Bulk-RNA-Seq-Nextflow-Pipeline` | Pipeline code (Nextflow workflows) | `~/work/projects/tjp/Bulk-RNA-Seq-Nextflow-Pipeline/` |

The HPC repo pins `bulkseq` as a git submodule. The UTDal pipeline repo is cloned separately on the HPC (it is not a submodule).

---

## First-Time Setup

### 1. Clone the HPC repo with submodules

```bash
ssh maw210003@<hpc-host>
cd ~/work/projects/tjp
git clone --recurse-submodules https://github.com/mwilde49/hpc.git .
```

If you already cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

### 2. Build the container

On a machine with `sudo` access (local dev machine or build node):

```bash
cd containers/bulkrnaseq
sudo ./build.sh
```

This produces `bulkrnaseq_v1.0.0.sif`. Transfer it to the HPC if built locally:

```bash
scp containers/bulkrnaseq/bulkrnaseq_v1.0.0.sif maw210003@<hpc-host>:~/work/projects/tjp/containers/bulkrnaseq/
```

### 3. Clone the UTDal pipeline repo

```bash
cd ~/work/projects/tjp
git clone https://github.com/utdal/Bulk-RNA-Seq-Nextflow-Pipeline.git
```

### 4. Configure the pipeline

Edit the UTDal pipeline's own config file:

```bash
vi Bulk-RNA-Seq-Nextflow-Pipeline/pipeline.config
```

Set your input FASTQ paths, reference genome paths, and output directories. Outputs should point to scratch space (`/scratch/juno/maw210003/...`).

---

## Running a Job

### Submit via SLURM

```bash
cd ~/work/projects/tjp
mkdir -p logs
sbatch slurm_templates/bulkrnaseq_slurm_template.sh
```

The SLURM template runs pre-flight checks to verify the container and UTDal pipeline repo exist before launching.

### What the template does

1. Loads the Apptainer module
2. Checks that the `.sif` container and UTDal pipeline repo exist
3. Runs `nextflow run` inside the container with `--cleanenv` and `--env PYTHONNOUSERSITE=1`
4. Bind-mounts `PROJECT_ROOT` and `SCRATCH_ROOT` into the container
5. Points Nextflow's work directory to scratch (`$SCRATCH_ROOT/nextflow_work`)

---

## Monitoring and Output

### Check job status

```bash
squeue -u $USER
```

### Check logs

```bash
cat logs/bulkrnaseq_<jobid>.out
cat logs/bulkrnaseq_<jobid>.err
```

### Check Nextflow logs

Nextflow writes its own log to the launch directory:

```bash
cat .nextflow.log
```

### Check output

Outputs are written to scratch space as configured in `pipeline.config`.

---

## Updating the Container Version

When the `bulkseq` repo releases a new version:

```bash
# Update the submodule to the new tag
cd containers/bulkrnaseq
git fetch --tags
git checkout v2.0.0    # or whatever the new tag is
cd ../..

# Stage and commit
git add containers/bulkrnaseq
git commit -m "Update bulkrnaseq submodule to v2.0.0"

# Rebuild the container and transfer to HPC
cd containers/bulkrnaseq
sudo ./build.sh
scp bulkrnaseq_v2.0.0.sif maw210003@<hpc-host>:~/work/projects/tjp/containers/bulkrnaseq/

# Update the SLURM template to reference the new .sif filename
```

---

## Nextflow Work Directory

Nextflow creates a `work/` directory containing intermediate files for each process. This can grow very large. The SLURM template points it to scratch:

```
-w $SCRATCH_ROOT/nextflow_work
```

Clean it after successful runs:

```bash
rm -rf ~/scratch/nextflow_work
```

Or use Nextflow's built-in cleanup:

```bash
nextflow clean -f
```

---

## Troubleshooting

### "Container not found" error

The SLURM template expects the container at `$PROJECT_ROOT/containers/bulkrnaseq/bulkrnaseq_v1.0.0.sif`. Build it with `./build.sh` in the submodule directory and transfer it to the HPC.

### "UTDal pipeline repo not found" error

Clone the UTDal repo to `$PROJECT_ROOT/Bulk-RNA-Seq-Nextflow-Pipeline`:

```bash
cd ~/work/projects/tjp
git clone https://github.com/utdal/Bulk-RNA-Seq-Nextflow-Pipeline.git
```

### Bind mount errors

Apptainer needs real paths, not symlinks. The SLURM template uses hardcoded real paths (`/work/maw210003/projects/tjp` and `/scratch/juno/maw210003`). If your paths differ, edit the template.

### `--cleanenv` flag

The `--cleanenv` flag prevents host environment variables from leaking into the container. This is required for bulkrnaseq to avoid conflicts with host Python installations. Do not remove it.

### `PYTHONNOUSERSITE=1`

This prevents Python from loading packages from `~/.local/lib/`. Without it, host-installed Python packages can shadow container packages and cause version conflicts.

### STAR aligner runs out of memory

STAR genome indexing and alignment require significant memory. The SLURM template requests 64G. If your reference genome is large (e.g., human), you may need to increase `--mem` to `128G` or more.

### Nextflow caching issues

If a resumed run behaves unexpectedly, clear the work directory:

```bash
rm -rf ~/scratch/nextflow_work
```

Then resubmit.
