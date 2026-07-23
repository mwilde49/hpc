#!/usr/bin/env bash
# generate_tier0_reference.sh — tiny synthetic reference FASTA/GTF + HISAT2
# (psoma) and STAR (bulkrnaseq) indexes for tier-0 (extra-small,
# non-scientific) smoke testing.
#
# Companion to generate_rnaseq_synthetic.sh, which makes the matching
# FASTQs. Together they remove the manual "build a tiny reference index by
# hand" step that test_psoma.sh/test_bulkrnaseq.sh have always required
# (see the comments in those files pointing here).
#
# The reference is a real, if trivial, FASTA + GTF: one 2kb random contig,
# two toy genes. Reads from generate_rnaseq_synthetic.sh are random and
# will not align to it — that's fine. Tier-0's job is to exercise pipeline
# scaffolding (config parsing -> container invocation -> provenance capture
# -> archiving), not to produce a scientifically valid alignment.
#
# Usage:
#   generate_tier0_reference.sh [references_dir] [--hisat2-container <sif>] [--star-container <sif>]
#
#   references_dir         Defaults to $REPO_ROOT/references/tiny, matching
#                           what test_psoma.sh/test_bulkrnaseq.sh expect
#                           ($_PSOMA_TINY_HISAT2, $_BULKRNASEQ_TINY_STAR).
#   --hisat2-container      Build a REAL HISAT2 index via
#                           `apptainer exec <sif> hisat2-build ...`.
#   --star-container         Build a REAL STAR index via
#                           `apptainer exec <sif> STAR --runMode genomeGenerate ...`.
#
#   Omitting a --*-container flag (and having no hisat2-build/STAR on
#   $PATH) writes a clearly-labeled PLACEHOLDER index instead — sufficient
#   for stub-container smoke tests, where the fake aligner binary never
#   reads the index anyway, but NOT sufficient for a real Layer-3 run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

OUT_DIR="$REPO_ROOT/references/tiny"
HISAT2_CONTAINER=""
STAR_CONTAINER=""

if [[ $# -gt 0 && "$1" != --* ]]; then
    OUT_DIR="$1"
    shift
fi
while [[ $# -gt 0 ]]; do
    case "$1" in
        --hisat2-container) HISAT2_CONTAINER="$2"; shift 2 ;;
        --star-container)   STAR_CONTAINER="$2"; shift 2 ;;
        *) echo "[ERROR] Unknown arg: $1" >&2; exit 1 ;;
    esac
done

mkdir -p "$OUT_DIR"
FASTA="$OUT_DIR/tiny.fa"
GTF="$OUT_DIR/tiny.gtf"

printf '[INFO]  References dir: %s\n' "$OUT_DIR"

# ── Tiny synthetic reference ────────────────────────────────────────────────
if [[ -s "$FASTA" ]]; then
    printf '[INFO]  %s already exists, skipping\n' "$FASTA"
else
    printf '[INFO]  Generating tiny synthetic reference: %s\n' "$FASTA"
    {
        echo ">chr_tiny synthetic tier-0 reference — random sequence, not derived from any real genome"
        # `|| true` on tr: under pipefail, head closing the pipe early after
        # reading 2000 bytes sends tr SIGPIPE (exit 141), which pipefail
        # would otherwise surface as this whole block's exit status.
        { tr -dc 'ACGT' < /dev/urandom || true; } | head -c 2000 | fold -w 70
        echo ""
    } > "$FASTA"
fi

if [[ -s "$GTF" ]]; then
    printf '[INFO]  %s already exists, skipping\n' "$GTF"
else
    printf '[INFO]  Generating tiny synthetic annotation: %s\n' "$GTF"
    cat > "$GTF" <<'EOF'
chr_tiny	tier0	gene	1	500	.	+	.	gene_id "TINY1"; gene_name "TINY1";
chr_tiny	tier0	transcript	1	500	.	+	.	gene_id "TINY1"; transcript_id "TINY1.1";
chr_tiny	tier0	exon	1	500	.	+	.	gene_id "TINY1"; transcript_id "TINY1.1"; exon_number "1";
chr_tiny	tier0	gene	1000	1500	.	-	.	gene_id "TINY2"; gene_name "TINY2";
chr_tiny	tier0	transcript	1000	1500	.	-	.	gene_id "TINY2"; transcript_id "TINY2.1";
chr_tiny	tier0	exon	1000	1500	.	-	.	gene_id "TINY2"; transcript_id "TINY2.1"; exon_number "1";
EOF
fi

# ── Placeholder exclude BED (bulkrnaseq's filter_samples process requires
#    at least one of exclude_bed_file_path/blacklist_bed_file_path to be
#    non-empty — discovered by actually running the pipeline against this
#    fixture, not documented anywhere beforehand) ──────────────────────────
EXCLUDE_BED="$OUT_DIR/tier0_exclude.bed"
if [[ -s "$EXCLUDE_BED" ]]; then
    printf '[INFO]  %s already exists, skipping\n' "$EXCLUDE_BED"
else
    printf '[INFO]  Generating placeholder exclude BED: %s\n' "$EXCLUDE_BED"
    printf 'chr_tiny\t1900\t2000\n' > "$EXCLUDE_BED"
fi

# ── HISAT2 index (psoma) ────────────────────────────────────────────────────
HISAT2_DIR="$OUT_DIR/hisat2_index"
HISAT2_PREFIX="$HISAT2_DIR/tiny"
mkdir -p "$HISAT2_DIR"
if [[ -f "${HISAT2_PREFIX}.1.ht2" ]]; then
    printf '[INFO]  HISAT2 index already exists, skipping\n'
elif [[ -n "$HISAT2_CONTAINER" ]]; then
    printf '[INFO]  Building real HISAT2 index via %s...\n' "$HISAT2_CONTAINER"
    apptainer exec --bind "$OUT_DIR:$OUT_DIR" "$HISAT2_CONTAINER" hisat2-build "$FASTA" "$HISAT2_PREFIX"
elif command -v hisat2-build &>/dev/null; then
    printf '[INFO]  Building real HISAT2 index via local hisat2-build...\n'
    hisat2-build "$FASTA" "$HISAT2_PREFIX"
else
    printf '[WARN]  No hisat2-build available (no --hisat2-container given, none on PATH).\n'
    printf '[WARN]  Writing PLACEHOLDER index files — fine for stub-container smoke\n'
    printf '[WARN]  tests, NOT sufficient for a real Juno Layer-3 run. Re-run with\n'
    printf '[WARN]  --hisat2-container pointing at the real psoma .sif for a genuine index.\n'
    for ext in 1.ht2 2.ht2 3.ht2 4.ht2 5.ht2 6.ht2 7.ht2 8.ht2; do
        : > "${HISAT2_PREFIX}.${ext}"
    done
    echo "PLACEHOLDER — not a real HISAT2 index, see generate_tier0_reference.sh" > "${HISAT2_PREFIX}.PLACEHOLDER.txt"
fi

# ── STAR index (bulkrnaseq) ─────────────────────────────────────────────────
STAR_DIR="$OUT_DIR/star_index"
mkdir -p "$STAR_DIR"
if [[ -f "$STAR_DIR/SA" && -s "$STAR_DIR/SA" ]]; then
    printf '[INFO]  STAR index already exists, skipping\n'
elif [[ -n "$STAR_CONTAINER" ]]; then
    printf '[INFO]  Building real STAR index via %s...\n' "$STAR_CONTAINER"
    apptainer exec --bind "$OUT_DIR:$OUT_DIR" "$STAR_CONTAINER" \
        STAR --runMode genomeGenerate --genomeDir "$STAR_DIR" \
        --genomeFastaFiles "$FASTA" --sjdbGTFfile "$GTF" \
        --genomeSAindexNbases 4 --runThreadN 2
elif command -v STAR &>/dev/null; then
    printf '[INFO]  Building real STAR index via local STAR...\n'
    STAR --runMode genomeGenerate --genomeDir "$STAR_DIR" \
        --genomeFastaFiles "$FASTA" --sjdbGTFfile "$GTF" \
        --genomeSAindexNbases 4 --runThreadN 2
else
    printf '[WARN]  No STAR available (no --star-container given, none on PATH).\n'
    printf '[WARN]  Writing PLACEHOLDER index files — fine for stub-container smoke\n'
    printf '[WARN]  tests, NOT sufficient for a real Juno Layer-3 run.\n'
    : > "$STAR_DIR/SA"
    : > "$STAR_DIR/SAindex"
    : > "$STAR_DIR/Genome"
    echo "PLACEHOLDER — not a real STAR index, see generate_tier0_reference.sh" > "$STAR_DIR/PLACEHOLDER.txt"
fi

printf '\n[INFO]  Done.\n'
printf '[INFO]    Reference FASTA: %s\n' "$FASTA"
printf '[INFO]    Reference GTF:   %s\n' "$GTF"
printf '[INFO]    HISAT2 index:    %s (psoma)\n' "$HISAT2_PREFIX"
printf '[INFO]    STAR index:      %s (bulkrnaseq)\n' "$STAR_DIR"
printf '[INFO]    Exclude BED:     %s (bulkrnaseq — pass as exclude_bed_file_path)\n' "$EXCLUDE_BED"
