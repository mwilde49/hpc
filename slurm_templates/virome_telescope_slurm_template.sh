#!/bin/bash
#SBATCH --job-name=virome_telescope
#SBATCH --account=tprice
#SBATCH --qos=juno-pri
#SBATCH --partition=normal
#SBATCH --output=logs/virome_telescope_%j.out
#SBATCH --error=logs/virome_telescope_%j.err
#SBATCH --time=48:00:00
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G

# Load modules
module load apptainer

PROJECT_ROOT=/groups/tprice/pipelines
SCRATCH_ROOT=/scratch/juno/$USER
WORK_ROOT=/work/$USER

source "$PROJECT_ROOT/bin/lib/repro.sh"
source "$PROJECT_ROOT/bin/lib/provenance.sh"

PIPELINE_REPO=$PROJECT_ROOT/containers/virome

# Accept pipeline config as $1 (used by tjp-launch), fall back to default
PIPELINE_CONFIG=${1:-}

# Stage-out args (passed by tjp-launch)
RUN_DIR=${2:-}
SCRATCH_OUTPUT_DIR=${3:-}
# $4 (FASTQ_DIR) unused — samplesheet records input paths

# --- Reproducibility capture (node, partition, resources, invocation log) ---
capture_juno_env "$RUN_DIR"
start_console_log "$RUN_DIR"
trap '_EC=$?; finalize_juno_env "$RUN_DIR" "$_EC"; generate_provenance_readme "$RUN_DIR" "virome-telescope" "Virome — Telescope Locus-Level HERV-K Quantification Offshoot (Nextflow, multi-container)" "$_EC" "$PIPELINE_REPO (multi-container — see software_versions.txt)" "$SCRATCH_ROOT/nextflow_work/virome_telescope"' EXIT

# --- Pre-flight checks ---

# This job itself stays lightweight (4G/2cpu) -- it's just the Nextflow head
# process under -profile slurm. Nextflow submits its own per-process SLURM
# child jobs, sized via containers/virome/conf/base.config's process defaults
# and any withName overrides (unlike main.nf's virome_slurm_template.sh,
# which runs everything in one -profile standard job and therefore requests
# 16 CPU / 128 GB up front). See containers/virome/scripts/run_pathseq_config.sbatch
# and run_virome_config.sbatch for the precedent this mirrors.
command -v nextflow &>/dev/null || { module load nextflow 2>/dev/null || true; }
if ! command -v nextflow &>/dev/null; then
    echo "ERROR: nextflow not found. Run 'module load nextflow' or add it to PATH."
    exit 1
fi

if [ ! -d "$PIPELINE_REPO" ]; then
    echo "ERROR: Virome pipeline repo not found at $PIPELINE_REPO"
    echo "Run: git submodule update --init containers/virome"
    exit 1
fi

if [ ! -f "$PIPELINE_REPO/telescope_verify.nf" ]; then
    echo "ERROR: Pipeline script not found at $PIPELINE_REPO/telescope_verify.nf"
    exit 1
fi

if [ -z "$PIPELINE_CONFIG" ] || [ ! -f "$PIPELINE_CONFIG" ]; then
    echo "ERROR: Pipeline config not found: ${PIPELINE_CONFIG:-<not specified>}"
    exit 1
fi

# Only star.sif and telescope.sif are used by this offshoot (STAR_REALIGN_MULTIMAP,
# TELESCOPE_ASSIGN, AGGREGATE_TELESCOPE) -- confirmed against
# modules/star_realign_multimap.nf, modules/telescope_assign.nf, and
# modules/aggregate_telescope.nf directly, not assumed from the main pipeline's
# 6-container list.
for sif in star telescope; do
    if [ ! -f "$PIPELINE_REPO/${sif}.sif" ]; then
        echo "ERROR: Missing container: ${sif}.sif (expected at $PIPELINE_REPO/${sif}.sif)"
        echo "Copy built containers there, or build with:"
        echo "  apptainer build --fakeroot --force containers/${sif}.sif containers/${sif}.def"
        exit 1
    fi
done

# --- Software version capture (queried live from each per-process container) ---
capture_software_versions "$RUN_DIR" "virome-telescope" "$PIPELINE_REPO"

# --- Run pipeline ---

echo "====================================================================="
echo "  HYPERION COMPUTE — Virome Telescope Offshoot Executing"
echo "====================================================================="

mkdir -p logs

NF_LOG_DIR="${RUN_DIR:+$RUN_DIR/nextflow_logs}"
NF_LOG_DIR="${NF_LOG_DIR:-$SCRATCH_ROOT/pipelines/virome-telescope/nextflow_logs_$SLURM_JOB_ID}"
mkdir -p "$NF_LOG_DIR"

# Nextflow's own JVM heap must fit inside this job's 4G allocation since it
# runs -profile slurm (per-process work happens in Nextflow-submitted child
# jobs, not in this head process) -- matching the manual precedent scripts
# (run_pathseq_config.sbatch uses the same -Xms512m -Xmx2g for the same
# lightweight-head/heavy-children shape).
export NXF_JVM_ARGS="-Xms512m -Xmx2g"

# Separate workDir from main.nf's own ($SCRATCH_ROOT/nextflow_work/virome) —
# concurrent main-pipeline and telescope-offshoot runs must not share a
# Nextflow work/session directory (see virome/docs/juno_hpc_operations_guide.md
# on the shared-launch-directory -resume trap).
run_logged "${RUN_DIR:+$RUN_DIR/invocation.log}" \
    nextflow run "$PIPELINE_REPO/telescope_verify.nf" \
    -params-file "$PIPELINE_CONFIG" \
    -profile slurm \
    -w "$SCRATCH_ROOT/nextflow_work/virome_telescope" \
    -with-trace "$NF_LOG_DIR/trace.txt" \
    -with-report "$NF_LOG_DIR/report.html" \
    -with-timeline "$NF_LOG_DIR/timeline.html" \
    -with-dag "$NF_LOG_DIR/dag.html"

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
