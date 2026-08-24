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
trap '_EC=$?; finalize_juno_env "$RUN_DIR" "$_EC"; generate_provenance_readme "$RUN_DIR" "psoma" "Psoma — HISAT2 + Trimmomatic Bulk RNA-Seq" "$_EC" "$CONTAINER" "${NF_WORK_DIR:-$SCRATCH_ROOT/nextflow_work}"' EXIT

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

# Per-run work dir (not the old fixed/shared $SCRATCH_ROOT/nextflow_work) so -resume's
# cache is scoped to THIS run and isn't clobbered by/doesn't clobber other psoma runs.
# To actually resume a timed-out run: resubmit with the SAME RUN_DIR/SCRATCH_OUTPUT_DIR
# args as the original submission (don't regenerate via tjp-batch, which mints a new
# timestamp and therefore a fresh, empty work dir with nothing to resume from).
#
# Also used as --pwd below: -w only scopes the task work dir, NOT Nextflow's
# .nextflow/ session-lock/history dir, which defaults to the process's cwd at launch.
# Without --pwd here that cwd is wherever the job was submitted from (typically the
# shared $PROJECT_ROOT), so with -resume enabled every psoma run submitted from the
# same directory fights over the same session lock -- "ERROR ~ Unable to acquire
# lock on session ..." if another run's session is still open/active there. Pointing
# --pwd at the per-run NF_WORK_DIR isolates .nextflow/ per run, same as -w does for
# task outputs.
NF_WORK_DIR="${RUN_DIR:+$SCRATCH_ROOT/pipelines/psoma/nextflow_work_$(basename "$RUN_DIR")}"
NF_WORK_DIR="${NF_WORK_DIR:-$SCRATCH_ROOT/nextflow_work}"
mkdir -p "$NF_WORK_DIR"

run_logged "${RUN_DIR:+$RUN_DIR/invocation.log}" \
    apptainer exec \
    --cleanenv \
    --env PYTHONNOUSERSITE=1 \
    --env HOME=/tmp \
    --env _JAVA_OPTIONS=-Xmx16g \
    --bind $PROJECT_ROOT:$PROJECT_ROOT \
    --bind $SCRATCH_ROOT:$SCRATCH_ROOT \
    --bind $WORK_ROOT:$WORK_ROOT \
    --pwd "$NF_WORK_DIR" \
    $CONTAINER \
    nextflow run $PIPELINE_REPO/psomagen_bulk_rna_seq_pipeline.nf \
    -c $PIPELINE_CONFIG \
    -w "$NF_WORK_DIR" \
    -resume \
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
# PAUSED 2026-08-24: deprecated in favor of a future scratch->Titan archival
# step (likely following the tjp-archive-one.sh / tjp-bulk-archive-to-titan.sh
# pattern -- checksum-verified rsync from a login node, since Titan isn't
# compute-node-mounted). Left in place, gated off by default, rather than
# deleted, since the eventual Titan version will probably reuse this shape.
# Known bug in this version, for whoever revives/replaces it: neither rsync
# copy below (outputs/ or inputs/) checks its own exit code -- only the
# separate dry-run diff after the fact does, so a copy that fails partway
# (e.g. disk quota) can still log "Archive verification PASSED" (observed on
# a real Astarush1 run, 2026-08-24 -- root-caused to this gap, exact diff-side
# mechanism not fully traced). Set ARCHIVE_TO_WORK=true to re-enable the
# current behavior as-is.
ARCHIVE_TO_WORK=${ARCHIVE_TO_WORK:-false}

if [ "$ARCHIVE_TO_WORK" = "true" ] && [ -n "$RUN_DIR" ] && [ -n "$SCRATCH_OUTPUT_DIR" ]; then
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
elif [ -n "$RUN_DIR" ] && [ -n "$SCRATCH_OUTPUT_DIR" ]; then
    echo "[HYPERION] Archive-to-work step is paused (ARCHIVE_TO_WORK != true) -- results remain on scratch at $SCRATCH_OUTPUT_DIR"
fi
