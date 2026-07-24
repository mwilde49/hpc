#!/bin/bash
#SBATCH --job-name=psoma
#SBATCH --output=logs/psoma_%j.out
#SBATCH --error=logs/psoma_%j.err
#SBATCH --time=48:00:00
#SBATCH --cpus-per-task=40
#SBATCH --mem=128G

# Load module if required by your HPC
module load apptainer

PROJECT_ROOT=/groups/tprice/pipelines
SCRATCH_ROOT=/scratch/juno/$USER
WORK_ROOT=/work/$USER

source "$PROJECT_ROOT/bin/lib/repro.sh"
source "$PROJECT_ROOT/bin/lib/provenance.sh"

CONTAINER=$PROJECT_ROOT/containers/psoma/psomagen_v1.0.0.sif
PIPELINE_REPO=$PROJECT_ROOT/containers/psoma

# Accept pipeline config as $1 (used by tjp-launch), fall back to default
PIPELINE_CONFIG=${1:-$PIPELINE_REPO/pipeline.config}

# Stage-out args (passed by tjp-launch for archiving results to work)
RUN_DIR=${2:-}
SCRATCH_OUTPUT_DIR=${3:-}
FASTQ_DIR=${4:-}

# --- Reproducibility capture (node, partition, resources, invocation log) ---
capture_juno_env "$RUN_DIR"
start_console_log "$RUN_DIR"
trap '_EC=$?; finalize_juno_env "$RUN_DIR" "$_EC"; generate_provenance_readme "$RUN_DIR" "psoma" "Psoma — HISAT2 + Trimmomatic Bulk RNA-Seq" "$_EC" "$CONTAINER" "$SCRATCH_ROOT/nextflow_work"' EXIT

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

# --- Software version capture (queried live from the container — see
#     bin/lib/provenance.sh for why these tools aren't version-pinned at
#     build time) ---
capture_software_versions "$RUN_DIR" "psoma" "$CONTAINER"

# --- Run pipeline ---

echo "====================================================================="
echo "  HYPERION COMPUTE — Psoma Pipeline Executing"
echo "====================================================================="

mkdir -p logs

NF_LOG_DIR="${RUN_DIR:+$RUN_DIR/nextflow_logs}"
NF_LOG_DIR="${NF_LOG_DIR:-$SCRATCH_ROOT/pipelines/psoma/nextflow_logs_$SLURM_JOB_ID}"
mkdir -p "$NF_LOG_DIR"

run_logged "${RUN_DIR:+$RUN_DIR/invocation.log}" \
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
    -w $SCRATCH_ROOT/nextflow_work \
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

    if [ -n "$FASTQ_DIR" ]; then
        echo "Copying inputs: $FASTQ_DIR/ -> $RUN_DIR/inputs/"
        mkdir -p "$RUN_DIR/inputs"
        rsync -a --checksum "$FASTQ_DIR/" "$RUN_DIR/inputs/"
    fi

    echo "Verifying archive integrity..."
    VERIFY_FAIL=0
    OUTPUT_DIFF=$(rsync -a --checksum --dry-run "$SCRATCH_OUTPUT_DIR/" "$RUN_DIR/outputs/" 2>&1)
    [ -n "$OUTPUT_DIFF" ] && VERIFY_FAIL=1
    if [ -n "$FASTQ_DIR" ]; then
        INPUT_DIFF=$(rsync -a --checksum --dry-run "$FASTQ_DIR/" "$RUN_DIR/inputs/" 2>&1)
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
