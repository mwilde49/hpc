#!/bin/bash
#SBATCH --job-name=cellranger-mkfastq
#SBATCH --output=logs/cellranger_mkfastq_%j.out
#SBATCH --error=logs/cellranger_mkfastq_%j.err
#SBATCH --time=12:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --exclusive

# Cell Ranger manages its own threading via --localcores/--localmem.
# No Apptainer container — tool is installed from tarball on HPC.

PROJECT_ROOT=/groups/tprice/pipelines
SCRATCH_ROOT=/scratch/juno/$USER

TENX_WRAPPER=$PROJECT_ROOT/containers/10x/bin/cellranger-mkfastq-run.sh

# Arguments passed by tjp-launch
PIPELINE_CONFIG=${1:-}
RUN_DIR=${2:-}
SCRATCH_OUTPUT_DIR=${3:-}

# --- Pre-flight checks ---

if [ ! -f "$TENX_WRAPPER" ]; then
    echo "ERROR: Cell Ranger mkfastq wrapper not found at $TENX_WRAPPER"
    echo "Check that the 10x submodule is initialized: git submodule update --init --recursive"
    exit 1
fi

if [ -z "$PIPELINE_CONFIG" ] || [ ! -f "$PIPELINE_CONFIG" ]; then
    echo "ERROR: Pipeline config not found: $PIPELINE_CONFIG"
    exit 1
fi

if [ -z "$SCRATCH_OUTPUT_DIR" ]; then
    echo "ERROR: No scratch output directory specified."
    exit 1
fi

# --- Run pipeline ---

echo "====================================================================="
echo "  HYPERION COMPUTE — Cell Ranger mkfastq Executing"
echo "====================================================================="

mkdir -p logs

bash "$TENX_WRAPPER" "$PIPELINE_CONFIG" "$SCRATCH_OUTPUT_DIR"
PIPELINE_EXIT=$?

if [ $PIPELINE_EXIT -ne 0 ]; then
    echo "ERROR: Pipeline failed (exit $PIPELINE_EXIT). Skipping archive."
    exit $PIPELINE_EXIT
fi

# --- Stage-out: archive FASTQs from scratch to work ---

if [ -n "$RUN_DIR" ] && [ -n "$SCRATCH_OUTPUT_DIR" ]; then
    echo "[HYPERION] Data Relays Synchronizing — Archiving FASTQs to work"

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
