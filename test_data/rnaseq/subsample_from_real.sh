#!/usr/bin/env bash
# subsample_from_real.sh — create subsampled test FASTQs from real data
# One-time utility. Run on HPC where seqtk is available (inside container).
#
# Usage: ./subsample_from_real.sh <source_fastq_dir> <output_dir> [num_reads]
#
# Example:
#   apptainer exec containers/psoma/psomagen_v1.0.0.sif \
#     ./test_data/rnaseq/subsample_from_real.sh /scratch/juno/$USER/fastq \
#     ./test_data/rnaseq/fastq 50000

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <source_fastq_dir> <output_dir> [num_reads]"
    echo "  source_fastq_dir  Directory with Sample_XX_1_paired.fastq.gz files"
    echo "  output_dir        Where to write subsampled FASTQs"
    echo "  num_reads         Reads to subsample per file (default: 50000)"
    exit 1
fi

SOURCE_DIR="$1"
OUTPUT_DIR="$2"
NUM_READS="${3:-50000}"
SEED=42
SAMPLES=(Sample_19 Sample_20)

mkdir -p "$OUTPUT_DIR"

for sample in "${SAMPLES[@]}"; do
    for read in 1 2; do
        src="${SOURCE_DIR}/${sample}_${read}_paired.fastq.gz"
        # Psoma naming: Sample_XX_1.fastq.gz / Sample_XX_2.fastq.gz
        dst="${OUTPUT_DIR}/${sample}_${read}.fastq.gz"

        if [[ ! -f "$src" ]]; then
            echo "ERROR: Source file not found: $src" >&2
            exit 1
        fi

        echo "Subsampling $src -> $dst ($NUM_READS reads, seed=$SEED)"
        seqtk sample -s "$SEED" "$src" "$NUM_READS" | gzip > "$dst"
    done
done

echo ""
echo "Done. Subsampled FASTQs written to: $OUTPUT_DIR/"
echo "Files:"
ls -lh "$OUTPUT_DIR"/*.fastq.gz
