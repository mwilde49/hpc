#!/bin/bash
#SBATCH --job-name=bulkrnaseq
#SBATCH --output=logs/bulkrnaseq_%j.out
#SBATCH --error=logs/bulkrnaseq_%j.err
#SBATCH --time=12:00:00
#SBATCH --cpus-per-task=40
#SBATCH --mem=128G

# Load module if required by your HPC
module load apptainer

PROJECT_ROOT=/groups/tprice/pipelines
SCRATCH_ROOT=/scratch/juno/$USER
WORK_ROOT=/work/$USER

source "$PROJECT_ROOT/bin/lib/repro.sh"

CONTAINER=$PROJECT_ROOT/containers/bulkrnaseq/bulkrnaseq_v1.0.0.sif
PIPELINE_REPO=$PROJECT_ROOT/Bulk-RNA-Seq-Nextflow-Pipeline

# Accept pipeline config as $1 (used by tjp-launch), fall back to default
PIPELINE_CONFIG=${1:-$PIPELINE_REPO/pipeline.config}

# Stage-out args (passed by tjp-launch for archiving results to work)
RUN_DIR=${2:-}
SCRATCH_OUTPUT_DIR=${3:-}
FASTQ_DIR=${4:-}

# --- Reproducibility capture (node, partition, resources, invocation log) ---
capture_juno_env "$RUN_DIR"
trap 'finalize_juno_env "$RUN_DIR" "$?"' EXIT

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

echo "====================================================================="
echo "  HYPERION COMPUTE — BulkRNASeq Pipeline Executing"
echo "====================================================================="

mkdir -p logs

# Nextflow's own trace/report/timeline give per-process exact commands and
# resource usage for free — write them straight into the run directory
# (already bind-mounted via WORK_ROOT) so there's no separate archive step.
NF_LOG_DIR="${RUN_DIR:+$RUN_DIR/nextflow_logs}"
NF_LOG_DIR="${NF_LOG_DIR:-$SCRATCH_ROOT/pipelines/bulkrnaseq/nextflow_logs_$SLURM_JOB_ID}"
mkdir -p "$NF_LOG_DIR"

run_logged "${RUN_DIR:+$RUN_DIR/invocation.log}" \
    apptainer exec \
    --cleanenv \
    --env PYTHONNOUSERSITE=1 \
    --bind $PROJECT_ROOT:$PROJECT_ROOT \
    --bind $SCRATCH_ROOT:$SCRATCH_ROOT \
    --bind $WORK_ROOT:$WORK_ROOT \
    $CONTAINER \
    nextflow run $PIPELINE_REPO/bulk_rna_seq_nextflow_pipeline.nf \
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

    # -L dereferences symlinks. BulkRNASeq's numbered stage-output dirs under
    # $SCRATCH_OUTPUT_DIR are symlinked into the shared UTDal repo
    # ($PIPELINE_REPO) rather than being real per-run directories (see the
    # symlink loop in tjp-launch). Without -L, rsync -a copies the symlinks
    # themselves (a few KB) instead of the data they point to, producing an
    # archive that verifies successfully but contains none of the actual
    # pipeline output.
    echo "Copying outputs: $SCRATCH_OUTPUT_DIR/ -> $RUN_DIR/outputs/"
    mkdir -p "$RUN_DIR/outputs"
    rsync -aL --checksum "$SCRATCH_OUTPUT_DIR/" "$RUN_DIR/outputs/"

    if [ -n "$FASTQ_DIR" ]; then
        echo "Copying inputs: $FASTQ_DIR/ -> $RUN_DIR/inputs/"
        mkdir -p "$RUN_DIR/inputs"
        rsync -aL --checksum "$FASTQ_DIR/" "$RUN_DIR/inputs/"
    fi

    echo "Verifying archive integrity..."
    VERIFY_FAIL=0
    OUTPUT_DIFF=$(rsync -aL --checksum --dry-run "$SCRATCH_OUTPUT_DIR/" "$RUN_DIR/outputs/" 2>&1)
    [ -n "$OUTPUT_DIFF" ] && VERIFY_FAIL=1
    if [ -n "$FASTQ_DIR" ]; then
        INPUT_DIFF=$(rsync -aL --checksum --dry-run "$FASTQ_DIR/" "$RUN_DIR/inputs/" 2>&1)
        [ -n "$INPUT_DIFF" ] && VERIFY_FAIL=1
    fi

    if [ $VERIFY_FAIL -eq 0 ]; then
        echo "[HYPERION] Data Relays Synchronized — Archive verification PASSED"

        # Purge the shared UTDal repo's numbered stage-output dirs now that
        # results are safely and verifiably archived to work. Left alone,
        # these accumulate every run's output indefinitely, and tjp-launch's
        # symlink loop re-links each new run straight back into whatever is
        # still sitting here — silently contaminating future runs with stale
        # samples from unrelated past runs (this happened in practice on
        # 2026-07-13). Deleting them only here, gated on a verified archive,
        # means the next tjp-launch has nothing to symlink for these names,
        # so Nextflow creates fresh, genuinely isolated directories in its
        # own scratch dir instead.
        echo "[HYPERION] Purging shared pipeline output dirs to prevent cross-run contamination"
        BULKRNASEQ_STAGE_DIRS=(
            0_nextflow_logs
            1_fastqc_and_multiqc_reports
            2_star_mapping_output
            2_1_map_metrics_output_qc
            3_filter_output
            3_1_qualimap_filter_output_qc
            4_stringtie_counts_output
            5_raw_counts_output
        )
        for d in "${BULKRNASEQ_STAGE_DIRS[@]}"; do
            if [ -e "$PIPELINE_REPO/$d" ]; then
                rm -rf "$PIPELINE_REPO/$d"
                echo "  removed $PIPELINE_REPO/$d"
            fi
        done
        rm -f "$PIPELINE_REPO"/6_pipeline_stats_*.log
    else
        echo "[HYPERION] WARNING: Archive verification detected differences."
        [ -n "${OUTPUT_DIFF:-}" ] && echo "$OUTPUT_DIFF"
        [ -n "${INPUT_DIFF:-}" ] && echo "$INPUT_DIFF"
        echo "[HYPERION] Skipping shared-directory cleanup because archive verification failed — will retry on the next successful run."
    fi
fi
