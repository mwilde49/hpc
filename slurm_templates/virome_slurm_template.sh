#!/bin/bash
#SBATCH --job-name=virome
#SBATCH --output=logs/virome_%j.out
#SBATCH --error=logs/virome_%j.err
#SBATCH --time=12:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G

# Load modules
module load apptainer

# Nextflow runs natively (not inside a container) and invokes each per-process
# container. Ensure nextflow is available on the PATH or loaded as a module.
command -v nextflow &>/dev/null || { module load nextflow 2>/dev/null || true; }
if ! command -v nextflow &>/dev/null; then
    echo "ERROR: nextflow not found. Run 'module load nextflow' or add it to PATH."
    exit 1
fi

PROJECT_ROOT=/groups/tprice/pipelines
SCRATCH_ROOT=/scratch/juno/$USER
WORK_ROOT=/work/$USER

PIPELINE_REPO=$PROJECT_ROOT/containers/virome

# Accept pipeline config as $1 (used by tjp-launch), fall back to default
PIPELINE_CONFIG=${1:-}

# Stage-out args (passed by tjp-launch)
RUN_DIR=${2:-}
SCRATCH_OUTPUT_DIR=${3:-}
# $4 (FASTQ_DIR) unused — samplesheet records input paths

# --- Pre-flight checks ---

if [ ! -d "$PIPELINE_REPO" ]; then
    echo "ERROR: Virome pipeline repo not found at $PIPELINE_REPO"
    echo "Run: git submodule update --init containers/virome"
    exit 1
fi

if [ ! -f "$PIPELINE_REPO/main.nf" ]; then
    echo "ERROR: Pipeline script not found at $PIPELINE_REPO/main.nf"
    exit 1
fi

if [ -z "$PIPELINE_CONFIG" ] || [ ! -f "$PIPELINE_CONFIG" ]; then
    echo "ERROR: Pipeline config not found: ${PIPELINE_CONFIG:-<not specified>}"
    exit 1
fi

for sif in fastqc trimmomatic star kraken2 python multiqc; do
    if [ ! -f "$PIPELINE_REPO/${sif}.sif" ]; then
        echo "ERROR: Missing container: ${sif}.sif (expected at $PIPELINE_REPO/${sif}.sif)"
        echo "Copy built containers there, or build with:"
        echo "  sbatch $PIPELINE_REPO/scripts/build_containers.sh"
        exit 1
    fi
done

# --- Run pipeline ---

echo "====================================================================="
echo "  HYPERION COMPUTE — Virome Pipeline Executing"
echo "====================================================================="

mkdir -p logs

# Virome uses per-process Apptainer containers managed by Nextflow.
# Nextflow reads container paths from params.container_dir in the config.
nextflow run "$PIPELINE_REPO/main.nf" \
    -params-file "$PIPELINE_CONFIG" \
    -profile standard \
    -w "$SCRATCH_ROOT/nextflow_work/virome"

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
