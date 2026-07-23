#!/bin/bash
#SBATCH --job-name=addone_demo
#SBATCH --output=logs/addone_%j.out
#SBATCH --error=logs/addone_%j.err
#SBATCH --time=00:05:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G

# Load module if required by your HPC
module load apptainer

PROJECT_ROOT=/groups/tprice/pipelines
SCRATCH_ROOT=/scratch/juno/$USER
WORK_ROOT=/work/$USER

source "$PROJECT_ROOT/bin/lib/repro.sh"

CONTAINER=$PROJECT_ROOT/containers/addone_latest.sif
PIPELINE=$PROJECT_ROOT/pipelines/addone/addone.py

CONFIG=$1
RUN_DIR=${2:-}

# --- Reproducibility capture (node, partition, resources, invocation log) ---
capture_juno_env "$RUN_DIR"
trap 'finalize_juno_env "$RUN_DIR" "$?"' EXIT

if [ -z "$CONFIG" ]; then
    echo "Usage: sbatch addone_slurm_template.sh <config.yaml>"
    exit 1
fi

mkdir -p logs

run_logged "${RUN_DIR:+$RUN_DIR/invocation.log}" \
    apptainer exec \
    --bind $PROJECT_ROOT:$PROJECT_ROOT \
    --bind $SCRATCH_ROOT:$SCRATCH_ROOT \
    --bind $WORK_ROOT:$WORK_ROOT \
    $CONTAINER \
    python $PIPELINE \
    --config $CONFIG
