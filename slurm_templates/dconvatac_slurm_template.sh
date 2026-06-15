#!/bin/bash
#SBATCH --job-name=dconvatac
#SBATCH --output=logs/dconvatac_%j.out
#SBATCH --error=logs/dconvatac_%j.err
#SBATCH --time=24:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G

module load apptainer

PROJECT_ROOT=/groups/tprice/pipelines
SCRATCH_ROOT=/scratch/juno/$USER
WORK_ROOT=/work/$USER

CONTAINER=$PROJECT_ROOT/containers/dconvatac/dconvatac_v1.0.0.sif
PIPELINE_SCRIPT=$PROJECT_ROOT/containers/dconvatac/pipeline/dconvatac.py

CONFIG=${1:-}
RUN_DIR=${2:-}
SCRATCH_OUTPUT_DIR=${3:-}

# --- Pre-flight checks ---

if [ -z "$CONFIG" ]; then
    echo "Usage: sbatch dconvatac_slurm_template.sh <config.yaml> [run_dir] [scratch_output_dir]"
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config file not found: $CONFIG"
    exit 1
fi

if [ ! -f "$CONTAINER" ]; then
    echo "ERROR: Container not found: $CONTAINER"
    echo "Build it with: cd containers/dconvatac/container && sudo ./build.sh"
    echo "Then scp dconvatac_v1.0.0.sif juno:$PROJECT_ROOT/containers/dconvatac/"
    exit 1
fi

if [ ! -f "$PIPELINE_SCRIPT" ]; then
    echo "ERROR: Pipeline script not found: $PIPELINE_SCRIPT"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

# --- Run pipeline ---

echo "====================================================================="
echo "  HYPERION COMPUTE — DeconvATAC Pipeline Executing (CPU)"
echo "====================================================================="

mkdir -p logs

apptainer exec \
    --cleanenv \
    --env PYTHONNOUSERSITE=1 \
    --env MPLBACKEND=Agg \
    --bind $PROJECT_ROOT:$PROJECT_ROOT \
    --bind $SCRATCH_ROOT:$SCRATCH_ROOT \
    --bind $WORK_ROOT:$WORK_ROOT \
    $CONTAINER \
    python $PIPELINE_SCRIPT --config $CONFIG
PIPELINE_EXIT=$?

if [ $PIPELINE_EXIT -ne 0 ]; then
    echo "ERROR: Pipeline failed (exit $PIPELINE_EXIT). Skipping archive."
    exit $PIPELINE_EXIT
fi

# --- Stage-out: archive results from scratch to work ---

if [ -n "$RUN_DIR" ] && [ -n "$SCRATCH_OUTPUT_DIR" ]; then
    echo "[HYPERION] Data Relays Synchronizing — Archiving results to work"

    echo "Copying outputs: $SCRATCH_OUTPUT_DIR/ -> $RUN_DIR/outputs/"
    mkdir -p "$RUN_DIR/outputs"
    rsync -a --checksum "$SCRATCH_OUTPUT_DIR/" "$RUN_DIR/outputs/"

    echo "Verifying archive integrity..."
    OUTPUT_DIFF=$(rsync -a --checksum --dry-run "$SCRATCH_OUTPUT_DIR/" "$RUN_DIR/outputs/" 2>&1)
    if [ -z "$OUTPUT_DIFF" ]; then
        echo "[HYPERION] Data Relays Synchronized — Archive verification PASSED"
    else
        echo "[HYPERION] WARNING: Archive verification detected differences."
        echo "$OUTPUT_DIFF"
    fi
fi
