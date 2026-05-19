#!/bin/bash
#SBATCH --job-name=cellranger-multi
#SBATCH --output=logs/cellranger_multi_%j.out
#SBATCH --error=logs/cellranger_multi_%j.err
#SBATCH --time=24:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --exclusive

PROJECT_ROOT=/groups/tprice/pipelines
SCRATCH_ROOT=/scratch/juno/$USER
WORK_ROOT=/work/$USER

WRAPPER=$PROJECT_ROOT/containers/10x/bin/cellranger-multi-run.sh

# Accept config as $1 (used by tjp-launch)
CONFIG=${1:-}
RUN_DIR=${2:-}
SCRATCH_OUTPUT_DIR=${3:-}

# --- Pre-flight checks ---

if [ -z "$CONFIG" ]; then
    echo "Usage: sbatch cellranger_multi_slurm_template.sh <config.yaml> <run_dir> <scratch_output_dir>"
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config file not found: $CONFIG"
    exit 1
fi

if [ ! -f "$WRAPPER" ]; then
    echo "ERROR: Cell Ranger Multi wrapper not found: $WRAPPER"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

# --- Run pipeline ---

echo "====================================================================="
echo "  HYPERION COMPUTE — Cell Ranger Multi Pipeline Executing"
echo "====================================================================="

mkdir -p logs

bash "$WRAPPER" "$CONFIG" "$SCRATCH_OUTPUT_DIR"
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
