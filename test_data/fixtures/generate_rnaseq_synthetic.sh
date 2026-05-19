#!/usr/bin/env bash
# generate_rnaseq_synthetic.sh — Generate minimal synthetic paired FASTQ files
# for bulkrnaseq and psoma pipeline testing.
#
# Usage:
#   generate_rnaseq_synthetic.sh <output_dir> [num_reads]
#
#   output_dir  - Directory where synthetic FASTQs will be written.
#                 Defaults to $SCRATCH_ROOT/pipelines/rnaseq_synthetic/fastq
#                 (requires SCRATCH_ROOT to be set, e.g., source bin/lib/common.sh)
#   num_reads   - Number of read pairs per sample (default: 1000)
#
# Output layout:
#   <output_dir>/
#     Sample_A_1.fastq.gz     bulkrnaseq suffix after rename: Sample_A_R1_001.fastq.gz
#     Sample_A_2.fastq.gz
#     Sample_B_1.fastq.gz
#     Sample_B_2.fastq.gz
#     samples.txt             one sample name per line (Sample_A, Sample_B)
#
# The reads are 50 bp of random ACGT sequence with Illumina-style FASTQ headers
# and a flat quality score of 'I' (Phred 40). They will not align to any real
# genome; they serve only to exercise the pipeline scaffolding without needing
# real sequencing data.
#
# NOTE: STAR and HISAT2 indexes are NOT generated here — those require the
# respective tools to be installed. Build a tiny chrM-only reference index
# separately using:
#   STAR --runMode genomeGenerate --genomeDir tiny/star_index \
#        --genomeFastaFiles chrM.fa --sjdbGTFfile chrM.gtf \
#        --genomeSAindexNbases 7 --runThreadN 4
#   hisat2-build chrM.fa tiny/hisat2_index/tiny

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
OUTPUT_DIR="${1:-}"
NUM_READS="${2:-1000}"

if [[ -z "$OUTPUT_DIR" ]]; then
    # Try to derive from SCRATCH_ROOT if the environment is set up
    if [[ -n "${SCRATCH_ROOT:-}" ]]; then
        OUTPUT_DIR="$SCRATCH_ROOT/pipelines/rnaseq_synthetic/fastq"
    else
        printf '[ERROR] Usage: %s <output_dir> [num_reads]\n' "$(basename "$0")" >&2
        exit 1
    fi
fi

if [[ ! "$NUM_READS" =~ ^[0-9]+$ ]] || [[ "$NUM_READS" -lt 1 ]]; then
    printf '[ERROR] num_reads must be a positive integer, got: %s\n' "$NUM_READS" >&2
    exit 1
fi

READ_LEN=50   # fixed 50 bp reads
SAMPLES=(Sample_A Sample_B)

printf '[INFO]  Output directory : %s\n' "$OUTPUT_DIR"
printf '[INFO]  Reads per sample : %s\n' "$NUM_READS"
printf '[INFO]  Samples          : %s\n' "${SAMPLES[*]}"

mkdir -p "$OUTPUT_DIR"

# ── FASTQ generation helper ───────────────────────────────────────────────────
# _gen_fastq <output_path.fastq.gz> <sample_name> <read_num> <num_reads> <read_len>
# read_num: 1 or 2 (used in read header)
_gen_fastq() {
    local out="$1"
    local sample="$2"
    local readnum="$3"
    local nreads="$4"
    local rlen="$5"
    local qual
    qual=$(printf 'I%.0s' $(seq 1 "$rlen"))   # all-I quality string (Phred 40)

    {
        local i
        for (( i = 1; i <= nreads; i++ )); do
            # Random $rlen-mer from /dev/urandom, converted to ACGT
            local seq
            seq=$(tr -dc 'ACGT' < /dev/urandom 2>/dev/null | head -c "$rlen")
            printf '@%s_r%d/%d\n%s\n+\n%s\n' "$sample" "$i" "$readnum" "$seq" "$qual"
        done
    } | gzip -c > "$out"
}

# ── Generate FASTQs for each sample ──────────────────────────────────────────
for sample in "${SAMPLES[@]}"; do
    r1_out="$OUTPUT_DIR/${sample}_1.fastq.gz"
    r2_out="$OUTPUT_DIR/${sample}_2.fastq.gz"

    if [[ -f "$r1_out" && -f "$r2_out" ]]; then
        printf '[INFO]  Skipping %s — files already exist\n' "$sample"
        continue
    fi

    printf '[INFO]  Generating %s R1 (%d reads, %d bp)...\n' "$sample" "$NUM_READS" "$READ_LEN"
    _gen_fastq "$r1_out" "$sample" 1 "$NUM_READS" "$READ_LEN"

    printf '[INFO]  Generating %s R2 (%d reads, %d bp)...\n' "$sample" "$NUM_READS" "$READ_LEN"
    _gen_fastq "$r2_out" "$sample" 2 "$NUM_READS" "$READ_LEN"
done

# ── Generate samples.txt ──────────────────────────────────────────────────────
SAMPLES_TXT="$OUTPUT_DIR/../samples.txt"
printf '[INFO]  Writing samples.txt -> %s\n' "$SAMPLES_TXT"
printf '%s\n' "${SAMPLES[@]}" > "$SAMPLES_TXT"

# ── Summary ──────────────────────────────────────────────────────────────────
printf '\n[INFO]  Done. Files written:\n'
ls -lh "$OUTPUT_DIR/"*.fastq.gz 2>/dev/null | awk '{printf "          %s  %s\n", $5, $NF}'
printf '          %s\n' "$SAMPLES_TXT"

printf '\n[INFO]  Next steps for bulkrnaseq testing:\n'
printf '          1. Rename R1/R2 files to Illumina convention:\n'
printf '               rename _1.fastq.gz _R1_001.fastq.gz %s/*_1.fastq.gz\n' "$OUTPUT_DIR"
printf '             (or use the test module which does this automatically)\n'
printf '          2. Build a tiny STAR index if not already present:\n'
printf '               See comments in this script for the STAR command.\n'
printf '          3. Run: tjp-test-suite --pipeline bulkrnaseq --layer 3\n'

printf '\n[INFO]  Next steps for psoma testing:\n'
printf '          1. The _1/_2 suffix files are ready (psoma uses _1/_2 natively)\n'
printf '          2. Build a tiny HISAT2 index if not already present:\n'
printf '               See comments in this script for the hisat2-build command.\n'
printf '          3. Run: tjp-test-suite --pipeline psoma --layer 3\n'
