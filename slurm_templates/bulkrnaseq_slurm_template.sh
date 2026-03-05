#!/bin/bash
#SBATCH --job-name=bulkrnaseq
#SBATCH --output=logs/bulkrnaseq_%j.out
#SBATCH --error=logs/bulkrnaseq_%j.err
#SBATCH --time=12:00:00
#SBATCH --cpus-per-task=20
#SBATCH --mem=64G

# Load module if required by your HPC
module load apptainer

PROJECT_ROOT=/groups/tprice/pipelines
SCRATCH_ROOT=/scratch/juno/$USER
WORK_ROOT=/work/$USER

CONTAINER=$PROJECT_ROOT/containers/bulkrnaseq/bulkrnaseq_v1.0.0.sif
PIPELINE_REPO=$PROJECT_ROOT/Bulk-RNA-Seq-Nextflow-Pipeline

# Accept pipeline config as $1 (used by tjp-launch), fall back to default
PIPELINE_CONFIG=${1:-$PIPELINE_REPO/pipeline.config}

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

if [ ! -f "$PIPELINE_CONFIG" ]; then
    echo "ERROR: Pipeline config not found at $PIPELINE_CONFIG"
    exit 1
fi

# --- Run pipeline ---

mkdir -p logs

apptainer exec \
    --cleanenv \
    --env PYTHONNOUSERSITE=1 \
    --bind $PROJECT_ROOT:$PROJECT_ROOT \
    --bind $SCRATCH_ROOT:$SCRATCH_ROOT \
    --bind $WORK_ROOT:$WORK_ROOT \
    $CONTAINER \
    nextflow run $PIPELINE_REPO/bulk_rna_seq_nextflow_pipeline.nf \
    -c $PIPELINE_CONFIG \
    -w $SCRATCH_ROOT/nextflow_work
