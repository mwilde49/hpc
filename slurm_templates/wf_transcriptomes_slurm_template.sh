#!/bin/bash
#SBATCH --job-name=wf_transcriptomes
#SBATCH --output=logs/wf_transcriptomes_%j.out
#SBATCH --error=logs/wf_transcriptomes_%j.err
#SBATCH --time=48:00:00
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --partition=normal

# wf-transcriptomes head job — submitted by tjp-launch
#
# This is a lightweight orchestrator: Nextflow runs here and submits
# per-process SLURM jobs (alignment, assembly, merge, etc.) itself.
# All heavy compute happens in Nextflow-managed sub-jobs on the normal partition.
#
# Args:
#   $1  Path to user config YAML
#   $2  Run directory (e.g. /work/$USER/pipelines/wf-transcriptomes/runs/<TS>)
#   $3  Output dir (from outdir: in config — unused here, Nextflow writes directly)

set -euo pipefail

PROJECT_ROOT=/groups/tprice/pipelines
PIPELINE_REPO=$PROJECT_ROOT/containers/sqanti3   # longreads repo deployment path
NEXTFLOW=$PROJECT_ROOT/bin/nextflow

USER_CONFIG="${1:?ERROR: Config not provided}"
RUN_DIR="${2:?ERROR: Run dir not provided}"

NF_CONFIG="$PIPELINE_REPO/configs/wf_transcriptomes/juno.config"
PREFLIGHT="$PIPELINE_REPO/scripts/wf_transcriptomes_preflight.sh"

# ── Helper ────────────────────────────────────────────────────────────────────

yaml_get() {
    grep -E "^${2}:" "$1" 2>/dev/null | head -1 \
        | sed "s/^${2}:[[:space:]]*//; s/[[:space:]]*#.*$//; s/^['\"]//; s/['\"]$//" || true
}

# ── Pre-flight checks ─────────────────────────────────────────────────────────

if [[ ! -f "$NF_CONFIG" ]]; then
    echo "ERROR: Nextflow config not found: $NF_CONFIG"
    echo "  Ensure the longreads repo is deployed at: $PIPELINE_REPO"
    exit 1
fi

bash "$PREFLIGHT" "$USER_CONFIG"

# ── Read config ───────────────────────────────────────────────────────────────

SAMPLE=$(yaml_get "$USER_CONFIG" "sample")
FASTQ_DIR=$(yaml_get "$USER_CONFIG" "fastq_dir")
SAMPLE_SHEET=$(yaml_get "$USER_CONFIG" "sample_sheet")
REF_GENOME=$(yaml_get "$USER_CONFIG" "ref_genome")
REF_ANNOTATION=$(yaml_get "$USER_CONFIG" "ref_annotation")
OUTDIR=$(yaml_get "$USER_CONFIG" "outdir")
WF_VERSION=$(yaml_get "$USER_CONFIG" "wf_version")
DIRECT_RNA=$(yaml_get "$USER_CONFIG" "direct_rna")
DE_ANALYSIS=$(yaml_get "$USER_CONFIG" "de_analysis")
MINIMAP2_OPTS=$(yaml_get "$USER_CONFIG" "minimap2_index_opts")
# Defaults
[[ -z "$WF_VERSION" ]]       && WF_VERSION="v1.7.2"
[[ -z "$DIRECT_RNA" ]]       && DIRECT_RNA="false"
[[ -z "$DE_ANALYSIS" ]]      && DE_ANALYSIS="false"
[[ -z "$MINIMAP2_OPTS" ]]    && MINIMAP2_OPTS="-k 15"

# Per-sample Nextflow work dir — sample-specific so -resume works on resubmit
NF_WORK_DIR="/scratch/juno/$USER/nf_work/wf_transcriptomes/$SAMPLE"

mkdir -p "$OUTDIR" "$NF_WORK_DIR"

echo "====================================================================="
echo "  wf-transcriptomes — Nextflow head job"
echo "  Sample:    $SAMPLE"
echo "  Version:   $WF_VERSION"
echo "  Direct RNA: $DIRECT_RNA"
echo "  DE:        $DE_ANALYSIS"
echo "  Output:    $OUTDIR"
echo "  Work dir:  $NF_WORK_DIR"
echo "====================================================================="

# ── Run Nextflow ──────────────────────────────────────────────────────────────
# Nextflow submits per-process SLURM jobs via juno.config (slurm executor).
# -resume allows restart from last successful task if this job is resubmitted.

"$NEXTFLOW" run epi2me-labs/wf-transcriptomes \
    -r "$WF_VERSION" \
    -profile singularity \
    -c "$NF_CONFIG" \
    -work-dir "$NF_WORK_DIR" \
    -resume \
    --fastq "$FASTQ_DIR" \
    --sample_sheet "$SAMPLE_SHEET" \
    --ref_genome "$REF_GENOME" \
    --ref_annotation "$REF_ANNOTATION" \
    --de_analysis "$DE_ANALYSIS" \
    --direct_rna "$DIRECT_RNA" \
    --minimap2_index_opts "$MINIMAP2_OPTS" \
    --out_dir "$OUTDIR"

# ── Locate merged GTF ─────────────────────────────────────────────────────────
# wf-transcriptomes writes the merged assembly GTF to $OUTDIR; find and report it.

echo ""
echo "====================================================================="
echo "  wf-transcriptomes complete — locating merged GTF"
echo "====================================================================="

MERGED_GTF=$(find "$OUTDIR" -maxdepth 3 -name "*.gtf" \
    \( -name "all_transcriptomes*" -o -name "str_merged*" -o -name "*merged*" \) \
    -not -path "*/work/*" 2>/dev/null | head -1 || true)

if [[ -n "$MERGED_GTF" ]]; then
    echo "Merged GTF found: $MERGED_GTF"
    echo ""
    echo "Pass to SQANTI3:"
    echo "  isoforms: $MERGED_GTF"
else
    echo "WARNING: Could not auto-locate merged GTF in $OUTDIR"
    echo "  Check $OUTDIR for a *merged*.gtf or *transcriptomes*.gtf file"
fi

echo ""
echo "Run dir (config snapshot + logs): $RUN_DIR"
echo "Monitor sub-jobs: squeue -u $USER"
