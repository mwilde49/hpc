#!/bin/bash
#SBATCH --job-name=addone_demo
#SBATCH --output=logs/addone_%j.out
#SBATCH --error=logs/addone_%j.err
#SBATCH --time=00:05:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G

# Load module if required by your HPC
module load apptainer

PROJECT_ROOT=/work/maw210003/projects/tjp
SCRATCH_ROOT=/scratch/juno/maw210003

CONTAINER=$PROJECT_ROOT/containers/addone_latest.sif
PIPELINE=$PROJECT_ROOT/pipelines/addone/addone.py

CONFIG=$1

if [ -z "$CONFIG" ]; then
    echo "Usage: sbatch addone_slurm_template.sh <config.yaml>"
    exit 1
fi

mkdir -p logs

apptainer exec \
    --bind $PROJECT_ROOT:$PROJECT_ROOT \
    --bind $SCRATCH_ROOT:$SCRATCH_ROOT \
    $CONTAINER \
    python $PIPELINE \
    --config $CONFIG
