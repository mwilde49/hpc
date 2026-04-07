#!/bin/bash
#SBATCH --job-name=sqanti3_orchestrate
#SBATCH --output=logs/sqanti3_orchestrate_%j.out
#SBATCH --error=logs/sqanti3_orchestrate_%j.err
#SBATCH --time=00:30:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G

# SQANTI3 Orchestrator — submitted by tjp-launch
# Runs pre-flight validation, computes resources from GTF size, generates
# per-stage SQANTI3 YAML configs, and chains SLURM sub-jobs:
#
#   Stage 1a (QC long-read) ─┐
#                              ├─► Stage 2 (Filter) ─► Stage 3 (Rescue)
#   Stage 1b (QC reference) ─┘
#
# Args:
#   $1  Path to user config YAML (flat key-value format)
#   $2  Run directory (e.g. /work/$USER/pipelines/sqanti3/runs/<TS>)
#   $3  Scratch output dir (e.g. /scratch/juno/$USER/pipelines/sqanti3/runs/<TS>)

set -euo pipefail

module load apptainer

PROJECT_ROOT=/groups/tprice/pipelines
SCRATCH_ROOT=/scratch/juno/$USER
WORK_ROOT=/work/$USER

PIPELINE_REPO=$PROJECT_ROOT/containers/sqanti3
SIF=$PIPELINE_REPO/sqanti3_v5.5.4.sif
FILTER_JSON=/opt2/sqanti3/5.5.4/SQANTI3-5.5.4/src/utilities/filter/filter_default.json

USER_CONFIG=${1:-}
RUN_DIR=${2:-}
SCRATCH_OUTPUT_DIR=${3:-}

# ── Pre-flight checks ─────────────────────────────────────────────────────────

if [[ -z "$USER_CONFIG" || ! -f "$USER_CONFIG" ]]; then
    echo "ERROR: Config not found: ${USER_CONFIG:-<not specified>}"
    exit 1
fi

if [[ ! -f "$SIF" ]]; then
    echo "ERROR: SQANTI3 container not found: $SIF"
    echo "  Build it: apptainer pull $SIF docker://anaconesalab/sqanti3:v5.5.4"
    exit 1
fi

# ── Read user config ──────────────────────────────────────────────────────────

yaml_get() {
    local file="$1" key="$2"
    grep -E "^${key}:" "$file" 2>/dev/null | head -1 \
        | sed "s/^${key}:[[:space:]]*//; s/[[:space:]]*#.*$//; s/^['\"]//; s/['\"]$//" || true
}

yaml_has() {
    grep -qE "^${1}:" "$2" 2>/dev/null
}

SAMPLE=$(yaml_get "$USER_CONFIG" "sample")
ISOFORMS=$(yaml_get "$USER_CONFIG" "isoforms")
REF_GTF=$(yaml_get "$USER_CONFIG" "refGTF")
REF_FASTA=$(yaml_get "$USER_CONFIG" "refFasta")
COVERAGE=$(yaml_get "$USER_CONFIG" "coverage")
# SQANTI3 v5.5.4 bug: RTS computation requires a coverage-derived _tmp file
# that is never created when coverage is absent. Use an empty SJ.out.tab so
# SQANTI3 creates the _tmp file (with 0 junctions) and RTS can proceed.
EMPTY_SJ="$PROJECT_ROOT/references/empty.SJ.out.tab"
[[ -z "$COVERAGE" ]] && COVERAGE="$EMPTY_SJ"
FL_COUNT=$(yaml_get "$USER_CONFIG" "fl_count")
CAGE_PEAK=$(yaml_get "$USER_CONFIG" "CAGE_peak")
POLYA_MOTIF=$(yaml_get "$USER_CONFIG" "polyA_motif_list")
POLYA_PEAK=$(yaml_get "$USER_CONFIG" "polyA_peak")
FORCE_ID_IGNORE=$(yaml_get "$USER_CONFIG" "force_id_ignore")
SKIP_REPORT=$(yaml_get "$USER_CONFIG" "skip_report")
SKIP_ORF=$(yaml_get "$USER_CONFIG" "skip_orf")
FILTER_MODE=$(yaml_get "$USER_CONFIG" "filter_mode")
FILTER_MONO_EXONIC=$(yaml_get "$USER_CONFIG" "filter_mono_exonic")
RESCUE_MODE=$(yaml_get "$USER_CONFIG" "rescue_mode")
USER_CPUS=$(yaml_get "$USER_CONFIG" "cpus")
USER_CHUNKS=$(yaml_get "$USER_CONFIG" "chunks")
OUTDIR=$(yaml_get "$USER_CONFIG" "outdir")

[[ -z "$SAMPLE"   ]] && { echo "ERROR: 'sample' not set in config"; exit 1; }
[[ -z "$ISOFORMS" ]] && { echo "ERROR: 'isoforms' not set in config"; exit 1; }
[[ -z "$REF_GTF"  ]] && { echo "ERROR: 'refGTF' not set in config"; exit 1; }
[[ -z "$REF_FASTA" ]] && { echo "ERROR: 'refFasta' not set in config"; exit 1; }
[[ -z "$OUTDIR"   ]] && { echo "ERROR: 'outdir' not set in config"; exit 1; }

# ── Pre-flight validation ─────────────────────────────────────────────────────

echo "====================================================================="
echo "  SQANTI3 Pipeline — Pre-flight Validation"
echo "====================================================================="

bash "$PIPELINE_REPO/scripts/sqanti3_preflight.sh" "$USER_CONFIG"

# ── Compute resources from GTF size ──────────────────────────────────────────

GTF_LINES=$(wc -l < "$ISOFORMS")
GTF_TRANSCRIPTS=$((GTF_LINES / 10))  # approximate; GTF has ~10 lines per transcript

if [[ "$USER_CPUS" -gt 0 && "$USER_CHUNKS" -gt 0 ]] 2>/dev/null; then
    CPUS_1A=$USER_CPUS
    CHUNKS_1A=$USER_CHUNKS
    MEM_1A=$(( CHUNKS_1A * 12 ))
elif [[ $GTF_TRANSCRIPTS -lt 50000 ]]; then
    CPUS_1A=8;  MEM_1A=32;  CHUNKS_1A=4
elif [[ $GTF_TRANSCRIPTS -lt 200000 ]]; then
    CPUS_1A=16; MEM_1A=64;  CHUNKS_1A=8
elif [[ $GTF_TRANSCRIPTS -lt 1000000 ]]; then
    CPUS_1A=32; MEM_1A=128; CHUNKS_1A=14
else
    CPUS_1A=32; MEM_1A=256; CHUNKS_1A=20
fi

echo "Input transcripts (est.): $GTF_TRANSCRIPTS"
echo "Stage 1a resources:       CPUs=$CPUS_1A  MEM=${MEM_1A}G  Chunks=$CHUNKS_1A"

# ── Resolve optional paths (empty string if blank) ────────────────────────────

REPORT_MODE="skip"
[[ "$SKIP_REPORT" == "false" ]] && REPORT_MODE="both"

SKIP_ORF_FLAG=""
[[ "$SKIP_ORF" == "true" ]] && SKIP_ORF_FLAG="true" || SKIP_ORF_FLAG="false"

[[ -z "$FORCE_ID_IGNORE" ]] && FORCE_ID_IGNORE="true"
[[ -z "$FILTER_MODE"     ]] && FILTER_MODE="rules"
[[ -z "$FILTER_MONO_EXONIC" ]] && FILTER_MONO_EXONIC="false"
[[ -z "$RESCUE_MODE"     ]] && RESCUE_MODE="automatic"

# ── Resolve stage output paths ────────────────────────────────────────────────

OUTDIR_QC="$OUTDIR/qc"
OUTDIR_REFQC="$OUTDIR/refqc"
OUTDIR_FILTER="$OUTDIR/filter"
OUTDIR_RESCUE="$OUTDIR/rescue"

mkdir -p "$OUTDIR_QC" "$OUTDIR_REFQC" "$OUTDIR_FILTER" "$OUTDIR_RESCUE"

# ── Generate per-stage SQANTI3 YAML configs ───────────────────────────────────

STAGE_CONFIGS="$RUN_DIR/stage_configs"
mkdir -p "$STAGE_CONFIGS"

# Stage 1a: Long-read QC
cat > "$STAGE_CONFIGS/qc.yaml" <<YAML
main:
  refGTF: '${REF_GTF}'
  refFasta: '${REF_FASTA}'
  cpus: ${CPUS_1A}
  dir: '${OUTDIR_QC}'
  output: '${SAMPLE}'
  log_level: INFO
qc:
  enabled: true
  options:
    isoforms: '${ISOFORMS}'
    min_ref_len: 0
    force_id_ignore: ${FORCE_ID_IGNORE}
    fasta: false
    genename: false
    short_reads: ''
    SR_bam: ''
    novel_gene_prefix: ''
    aligner_choice: minimap2
    gmap_index: ''
    sites: ATAC,GCAG,GTAG
    skipORF: ${SKIP_ORF_FLAG}
    orf_input: ''
    CAGE_peak: '${CAGE_PEAK}'
    polyA_motif_list: '${POLYA_MOTIF}'
    polyA_peak: '${POLYA_PEAK}'
    phyloP_bed: ''
    saturation: false
    report: ${REPORT_MODE}
    isoform_hits: false
    ratio_TSS_metric: max
    chunks: ${CHUNKS_1A}
    is_fusion: false
    expression: ''
    coverage: '${COVERAGE}'
    window: 20
    fl_count: '${FL_COUNT}'
    isoAnnotLite: false
    gff3: ''
filter:
  enabled: false
  options:
    common:
      sqanti_class: ''
      isoAnnotGFF3: ''
      filter_isoforms: ''
      filter_gtf: ''
      filter_sam: ''
      filter_faa: ''
      skip_report: false
      filter_mono_exonic: false
    rules:
      enabled: true
      options:
        json_filter: '${FILTER_JSON}'
    ml:
      enabled: false
rescue:
  enabled: false
YAML

# Stage 1b: Reference QC (GTF self-QC, needed by rescue)
cat > "$STAGE_CONFIGS/refqc.yaml" <<YAML
main:
  refGTF: '${REF_GTF}'
  refFasta: '${REF_FASTA}'
  cpus: 8
  dir: '${OUTDIR_REFQC}'
  output: 'ref'
  log_level: INFO
qc:
  enabled: true
  options:
    isoforms: '${REF_GTF}'
    min_ref_len: 0
    force_id_ignore: false
    fasta: false
    genename: false
    short_reads: ''
    SR_bam: ''
    novel_gene_prefix: ''
    aligner_choice: minimap2
    gmap_index: ''
    sites: ATAC,GCAG,GTAG
    skipORF: true
    orf_input: ''
    CAGE_peak: '${CAGE_PEAK}'
    polyA_motif_list: '${POLYA_MOTIF}'
    polyA_peak: ''
    phyloP_bed: ''
    saturation: false
    report: skip
    isoform_hits: false
    ratio_TSS_metric: max
    chunks: 1
    is_fusion: false
    expression: ''
    coverage: '${COVERAGE}'
    window: 20
    fl_count: ''
    isoAnnotLite: false
    gff3: ''
filter:
  enabled: false
rescue:
  enabled: false
YAML

# Stage 2: Filter
FILTER_ML_ENABLED="false"
FILTER_RULES_ENABLED="true"
if [[ "$FILTER_MODE" == "ml" ]]; then
    FILTER_ML_ENABLED="true"
    FILTER_RULES_ENABLED="false"
fi

cat > "$STAGE_CONFIGS/filter.yaml" <<YAML
main:
  refGTF: '${REF_GTF}'
  refFasta: '${REF_FASTA}'
  cpus: 4
  dir: '${OUTDIR_FILTER}'
  output: '${SAMPLE}'
  log_level: INFO
qc:
  enabled: false
filter:
  enabled: true
  options:
    common:
      sqanti_class: '${OUTDIR_QC}/${SAMPLE}_classification.txt'
      isoAnnotGFF3: ''
      filter_isoforms: '${OUTDIR_QC}/${SAMPLE}_corrected.fasta'
      filter_gtf: '${OUTDIR_QC}/${SAMPLE}_corrected.gtf'
      filter_sam: ''
      filter_faa: '${OUTDIR_QC}/${SAMPLE}_corrected.faa'
      skip_report: ${SKIP_REPORT}
      filter_mono_exonic: ${FILTER_MONO_EXONIC}
    rules:
      enabled: ${FILTER_RULES_ENABLED}
      options:
        json_filter: '${FILTER_JSON}'
    ml:
      enabled: ${FILTER_ML_ENABLED}
      options:
        percent_training: 0.8
        TP: ''
        TN: ''
        threshold: 0.7
        force_fsm_in: false
        intermediate_files: false
        remove_columns: ''
        max_class_size: 3000
        intrapriming: 60
rescue:
  enabled: false
YAML

# Stage 3: Rescue — filter classification filename depends on mode
if [[ "$FILTER_MODE" == "ml" ]]; then
    FILTER_CLASS="${OUTDIR_FILTER}/${SAMPLE}_MLfilter_result_classification.txt"
    FILTER_GTF="${OUTDIR_FILTER}/${SAMPLE}.filtered.gtf"
else
    FILTER_CLASS="${OUTDIR_FILTER}/${SAMPLE}_RulesFilter_result_classification.txt"
    FILTER_GTF="${OUTDIR_FILTER}/${SAMPLE}.filtered.gtf"
fi

RESCUE_ML_ENABLED="false"
RESCUE_RULES_ENABLED="true"
if [[ "$RESCUE_MODE" == "ml" ]]; then
    RESCUE_ML_ENABLED="true"
    RESCUE_RULES_ENABLED="false"
fi

cat > "$STAGE_CONFIGS/rescue.yaml" <<YAML
main:
  refGTF: '${REF_GTF}'
  refFasta: '${REF_FASTA}'
  cpus: 8
  dir: '${OUTDIR_RESCUE}'
  output: '${SAMPLE}'
  log_level: INFO
qc:
  enabled: false
filter:
  enabled: false
rescue:
  enabled: true
  options:
    common:
      filter_class: '${FILTER_CLASS}'
      rescue_isoforms: '${OUTDIR_QC}/${SAMPLE}_corrected.fasta'
      rescue_gtf: '${FILTER_GTF}'
      refClassif: '${OUTDIR_REFQC}/ref_classification.txt'
      counts: '${FL_COUNT}'
      rescue_mono_exonic: all
      mode: ${RESCUE_MODE}
      requant: false
    rules:
      enabled: ${RESCUE_RULES_ENABLED}
      options:
        json_filter: '${FILTER_JSON}'
    ml:
      enabled: ${RESCUE_ML_ENABLED}
      options:
        random_forest: ''
        threshold: 0.7
YAML

echo "Stage configs written to: $STAGE_CONFIGS"

# ── Common sub-job flags ──────────────────────────────────────────────────────

STAGE_SCRIPT_DIR="$PIPELINE_REPO/slurm_templates"
LOG_DIR="$RUN_DIR/logs"
mkdir -p "$LOG_DIR"

COMMON_FLAGS=(
    "--output=${LOG_DIR}/sqanti3_%x_%j.out"
    "--error=${LOG_DIR}/sqanti3_%x_%j.err"
    "--parsable"
    "--export=ALL"
)

# ── Submit stage 1a and 1b in parallel ───────────────────────────────────────

echo ""
echo "====================================================================="
echo "  Submitting SQANTI3 stages"
echo "====================================================================="

JOB_1A=$(sbatch \
    "${COMMON_FLAGS[@]}" \
    --job-name="sqanti3_qc_${SAMPLE}" \
    --time=48:00:00 \
    --cpus-per-task="$CPUS_1A" \
    --mem="${MEM_1A}G" \
    "$STAGE_SCRIPT_DIR/sqanti3_qc_slurm_template.sh" \
    "$STAGE_CONFIGS/qc.yaml" "$SIF")

echo "Stage 1a (QC long-read):  job $JOB_1A"

JOB_1B=$(sbatch \
    "${COMMON_FLAGS[@]}" \
    --job-name="sqanti3_rfqc_${SAMPLE}" \
    --time=12:00:00 \
    --cpus-per-task=8 \
    --mem=16G \
    "$STAGE_SCRIPT_DIR/sqanti3_refqc_slurm_template.sh" \
    "$STAGE_CONFIGS/refqc.yaml" "$SIF")

echo "Stage 1b (QC reference):  job $JOB_1B"

# Stage 2: filter — depends on 1a only
JOB_2=$(sbatch \
    "${COMMON_FLAGS[@]}" \
    --job-name="sqanti3_filter_${SAMPLE}" \
    --time=04:00:00 \
    --cpus-per-task=4 \
    --mem=8G \
    --dependency="afterok:${JOB_1A}" \
    "$STAGE_SCRIPT_DIR/sqanti3_filter_slurm_template.sh" \
    "$STAGE_CONFIGS/filter.yaml" "$SIF")

echo "Stage 2  (Filter):        job $JOB_2  [after $JOB_1A]"

# Stage 3: rescue — depends on both 2 (filter) and 1b (ref QC)
JOB_3=$(sbatch \
    "${COMMON_FLAGS[@]}" \
    --job-name="sqanti3_rescue_${SAMPLE}" \
    --time=08:00:00 \
    --cpus-per-task=8 \
    --mem=16G \
    --dependency="afterok:${JOB_2}:${JOB_1B}" \
    "$STAGE_SCRIPT_DIR/sqanti3_rescue_slurm_template.sh" \
    "$STAGE_CONFIGS/rescue.yaml" "$SIF" \
    "$OUTDIR" "$RUN_DIR")

echo "Stage 3  (Rescue):        job $JOB_3  [after $JOB_2 and $JOB_1B]"

# ── Print monitoring info ────────────────────────────────────────────────────

echo ""
cat <<EOF
===================================================================
  SQANTI3 — DAG submitted successfully
===================================================================
  Sample:     $SAMPLE
  Jobs:       1a=$JOB_1A  1b=$JOB_1B  filter=$JOB_2  rescue=$JOB_3

  Monitor:    squeue -u $USER
  QC logs:    $LOG_DIR/sqanti3_qc_*
  Output:     $OUTDIR/
  Archived:   $RUN_DIR/outputs/  (after rescue completes)

  Cancel all: scancel $JOB_1A $JOB_1B $JOB_2 $JOB_3
EOF
