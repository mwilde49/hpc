#!/bin/bash
#SBATCH --job-name=xeniumranger
#SBATCH --output=logs/xeniumranger_%j.out
#SBATCH --error=logs/xeniumranger_%j.err
#SBATCH --time=12:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --exclusive

PROJECT_ROOT=/groups/tprice/pipelines
SCRATCH_ROOT=/scratch/juno/$USER
WORK_ROOT=/work/$USER

WRAPPER=$PROJECT_ROOT/containers/10x/bin/xeniumranger-run.sh

# Accept config as $1 (used by tjp-launch)
CONFIG=${1:-}
RUN_DIR=${2:-}
SCRATCH_OUTPUT_DIR=${3:-}
INPUT_DIR=${4:-}

# --- Pre-flight checks ---

if [ -z "$CONFIG" ]; then
    echo "Usage: sbatch xeniumranger_slurm_template.sh <config.yaml> <run_dir> <scratch_output_dir> <input_dir>"
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config file not found: $CONFIG"
    exit 1
fi

if [ ! -f "$WRAPPER" ]; then
    echo "ERROR: Xenium Ranger wrapper not found: $WRAPPER"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

# --- Run pipeline ---

echo "====================================================================="
echo "  HYPERION COMPUTE — Xenium Ranger Pipeline Executing"
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

    if [ -n "$INPUT_DIR" ]; then
        echo "Copying inputs: $INPUT_DIR/ -> $RUN_DIR/inputs/"
        mkdir -p "$RUN_DIR/inputs"
        rsync -a --checksum "$INPUT_DIR/" "$RUN_DIR/inputs/"
    fi

    echo "Verifying archive integrity..."
    VERIFY_FAIL=0
    OUTPUT_DIFF=$(rsync -a --checksum --dry-run "$SCRATCH_OUTPUT_DIR/" "$RUN_DIR/outputs/" 2>&1)
    [ -n "$OUTPUT_DIFF" ] && VERIFY_FAIL=1
    if [ -n "$INPUT_DIR" ]; then
        INPUT_DIFF=$(rsync -a --checksum --dry-run "$INPUT_DIR/" "$RUN_DIR/inputs/" 2>&1)
        [ -n "$INPUT_DIFF" ] && VERIFY_FAIL=1
    fi

    if [ $VERIFY_FAIL -eq 0 ]; then
        echo "[HYPERION] Data Relays Synchronized — Archive verification PASSED"
    else
        echo "[HYPERION] WARNING: Archive verification detected differences."
        [ -n "${OUTPUT_DIFF:-}" ] && echo "$OUTPUT_DIFF"
        [ -n "${INPUT_DIFF:-}" ] && echo "$INPUT_DIFF"
    fi
fi
