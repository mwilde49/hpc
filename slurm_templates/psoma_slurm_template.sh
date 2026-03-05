#!/bin/bash
#SBATCH --job-name=psoma
#SBATCH --output=logs/psoma_%j.out
#SBATCH --error=logs/psoma_%j.err
#SBATCH --time=12:00:00
#SBATCH --cpus-per-task=40
#SBATCH --mem=128G

# Load module if required by your HPC
module load apptainer

PROJECT_ROOT=/groups/tprice/pipelines
SCRATCH_ROOT=/scratch/juno/$USER
WORK_ROOT=/work/$USER

CONTAINER=$PROJECT_ROOT/containers/psoma/psomagen_v1.0.0.sif
PIPELINE_REPO=$PROJECT_ROOT/containers/psoma

# Accept pipeline config as $1 (used by tjp-launch), fall back to default
PIPELINE_CONFIG=${1:-$PIPELINE_REPO/pipeline.config}

# --- Pre-flight checks ---

if [ ! -f "$CONTAINER" ]; then
    echo "ERROR: Container not found at $CONTAINER"
    echo "Build it first: cd containers/psoma/container && sudo ./build.sh"
    exit 1
fi

if [ ! -d "$PIPELINE_REPO" ]; then
    echo "ERROR: Psoma pipeline repo not found at $PIPELINE_REPO"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

if [ ! -f "$PIPELINE_REPO/psomagen_bulk_rna_seq_pipeline.nf" ]; then
    echo "ERROR: Pipeline script not found at $PIPELINE_REPO/psomagen_bulk_rna_seq_pipeline.nf"
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
    --env HOME=/tmp \
    --env _JAVA_OPTIONS=-Xmx16g \
    --bind $PROJECT_ROOT:$PROJECT_ROOT \
    --bind $SCRATCH_ROOT:$SCRATCH_ROOT \
    --bind $WORK_ROOT:$WORK_ROOT \
    $CONTAINER \
    nextflow run $PIPELINE_REPO/psomagen_bulk_rna_seq_pipeline.nf \
    -c $PIPELINE_CONFIG \
    -w $SCRATCH_ROOT/nextflow_work
