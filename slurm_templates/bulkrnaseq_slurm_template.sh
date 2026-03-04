#!/bin/bash
#SBATCH --job-name=bulkrnaseq
#SBATCH --output=logs/bulkrnaseq_%j.out
#SBATCH --error=logs/bulkrnaseq_%j.err
#SBATCH --time=12:00:00
#SBATCH --cpus-per-task=20
#SBATCH --mem=64G

# Load module if required by your HPC
module load apptainer

PROJECT_ROOT=/work/maw210003/projects/tjp
SCRATCH_ROOT=/scratch/juno/maw210003

CONTAINER=$PROJECT_ROOT/containers/bulkrnaseq/bulkrnaseq_v1.0.0.sif
PIPELINE_REPO=$PROJECT_ROOT/Bulk-RNA-Seq-Nextflow-Pipeline

# --- Pre-flight checks ---

if [ ! -f "$CONTAINER" ]; then
    echo "ERROR: Container not found at $CONTAINER"
    echo "Build it first: cd containers/bulkrnaseq && sudo ./build.sh"
    exit 1
fi

if [ ! -d "$PIPELINE_REPO" ]; then
    echo "ERROR: UTDal pipeline repo not found at $PIPELINE_REPO"
    echo "Clone it first: cd $PROJECT_ROOT && git clone https://github.com/utdal/Bulk-RNA-Seq-Nextflow-Pipeline.git"
    exit 1
fi

# --- Run pipeline ---

mkdir -p logs

apptainer exec \
    --cleanenv \
    --env PYTHONNOUSERSITE=1 \
    --bind $PROJECT_ROOT:$PROJECT_ROOT \
    --bind $SCRATCH_ROOT:$SCRATCH_ROOT \
    $CONTAINER \
    nextflow run $PIPELINE_REPO/bulk_rna_seq_nextflow_pipeline.nf \
    -c $PIPELINE_REPO/pipeline.config \
    -w $SCRATCH_ROOT/nextflow_work
