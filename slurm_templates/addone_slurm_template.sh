#!/bin/bash
#SBATCH --job-name=addone_demo
#SBATCH --output=logs/addone_%j.out
#SBATCH --error=logs/addone_%j.err
#SBATCH --time=00:05:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G

# Load module if required by your HPC
module load apptainer

CONTAINER=/project/tjp/containers/addone_latest.sif
PIPELINE=/project/tjp/pipelines/addone/addone.py

CONFIG=$1

if [ -z "$CONFIG" ]; then
    echo "Usage: sbatch addone_slurm_template.sh <config.yaml>"
    exit 1
fi

mkdir -p logs

apptainer exec \
    --bind /project/tjp:/project/tjp \
    $CONTAINER \
    python $PIPELINE \
    --config $CONFIG
