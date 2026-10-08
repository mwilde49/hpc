#!/bin/bash
#SBATCH --job-name=painrrf
#SBATCH --output=logs/painrrf_%j.out
#SBATCH --error=logs/painrrf_%j.err
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --partition=dev

# CPU-only -- no --nv, no GPU gres. See mlandi/docs/PRODUCTION_PACKAGING_PLAN.md:
# robustness_eval.py is StandardScaler+LogisticRegression only, fitting on 85
# samples x a few hundred features is millisecond-scale. Resource numbers below
# are an initial guess sized for the pseudobulk-scale (85-sample) discovery/
# validation scripts (04-06); revisit with real numbers once Tier 3 local runs
# exist (PRODUCTIONIZATION_STATUS.md Phase 4/5) -- NOT speculatively. A second,
# heavier template (bigger --mem, longer --time) would only be needed if
# full-664k-cell-atlas loading turns out to require more than this locally/on
# Juno's dev partition; don't build that ahead of evidence.

module load apptainer

PROJECT_ROOT=/groups/tprice/pipelines
SCRATCH_ROOT=/scratch/juno/$USER
WORK_ROOT=/work/$USER

source "$PROJECT_ROOT/bin/lib/repro.sh"
source "$PROJECT_ROOT/bin/lib/provenance.sh"

CONTAINER=$PROJECT_ROOT/containers/painrrf/painrrf_v0.1.0.sif
PIPELINE_SCRIPT=$PROJECT_ROOT/containers/painrrf/pipeline/painrrf.py
# NOTE: painrrf.py does not yet honor config['output_dir'] -- it writes
# discovery/tier_filter/validate outputs to timestamped run_* directories
# under $PROJECT_ROOT/containers/painrrf/V41/V41_Framework_Development/
# (the real 04/05/06 scripts' own BASE_DIR convention, left unmodified by
# design -- see painrrf.py's module docstring point 3). Point stage-out at
# that fixed location, not a configured scratch dir.
PAINRRF_RUN_ROOT=$PROJECT_ROOT/containers/painrrf/V41/V41_Framework_Development

CONFIG=${1:-}
RUN_DIR=${2:-}
SCRATCH_OUTPUT_DIR=${3:-}

# --- Reproducibility capture (node, partition, resources, invocation log) ---
capture_juno_env "$RUN_DIR"
start_console_log "$RUN_DIR"
trap '_EC=$?; finalize_juno_env "$RUN_DIR" "$_EC"; generate_provenance_readme "$RUN_DIR" "painrrf" "painrrf — DRG Pain-State Representation Robustness Framework (CPU, dev partition)" "$_EC" "$CONTAINER" ""' EXIT

# --- Pre-flight checks ---

if [ -z "$CONFIG" ]; then
    echo "Usage: sbatch painrrf_slurm_template.sh <config.yaml> [run_dir] [scratch_output_dir]"
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config file not found: $CONFIG"
    exit 1
fi

if [ ! -f "$CONTAINER" ]; then
    echo "ERROR: Container not found: $CONTAINER"
    echo "Build it with: cd containers/painrrf/container && sudo apptainer build ../painrrf_v0.1.0.sif apptainer.def"
    echo "Then scp painrrf_v0.1.0.sif juno:$PROJECT_ROOT/containers/painrrf/"
    exit 1
fi

if [ ! -f "$PIPELINE_SCRIPT" ]; then
    echo "ERROR: Pipeline script not found: $PIPELINE_SCRIPT"
    echo "NOTE: painrrf.py (the chained 04-10 entry point) does not exist yet as"
    echo "of this template's authoring -- it depends on the V27/V29-compatible"
    echo "loader reconstruction (PRODUCTIONIZATION_STATUS.md Phase 3), which is"
    echo "still in progress. This template documents the target shape."
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

# --- Software version capture ---
capture_software_versions "$RUN_DIR" "painrrf" "$CONTAINER"

# --- Run pipeline ---

echo "====================================================================="
echo "  HYPERION COMPUTE — painrrf Pipeline Executing (CPU, dev partition)"
echo "====================================================================="

mkdir -p logs

_PAINRRF_START_MARKER=$(mktemp)

run_logged "${RUN_DIR:+$RUN_DIR/invocation.log}" \
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

# --- Stage-out: copy this invocation's run_* output dirs to $RUN_DIR ---
#
# painrrf.py writes directly to $PAINRRF_RUN_ROOT (shared, persistent
# storage already -- not node-local scratch), so there's no scratch->work
# staging in the dpnvisium/dconvatac sense. This just organizes this
# invocation's own run_* dirs under the caller's RUN_DIR for discoverability,
# identified by mtime since this script started (SLURM_JOB_START not
# reliably available; use a marker file instead).
if [ -n "$RUN_DIR" ]; then
    echo "[HYPERION] Collecting run_* outputs into $RUN_DIR/outputs"
    mkdir -p "$RUN_DIR/outputs"
    find "$PAINRRF_RUN_ROOT" -maxdepth 1 -type d -name 'run_*' -newer "$_PAINRRF_START_MARKER" \
        -exec cp -r {} "$RUN_DIR/outputs/" \;
    echo "Collected: $(find "$RUN_DIR/outputs" -maxdepth 1 -type d -name 'run_*' | wc -l) run dir(s)"
fi
