#!/usr/bin/env bash
# download_10x_fixtures.sh — Download 10x Genomics tiny BCL test data
# for cellranger-mkfastq Layer 3 testing.
#
# Downloads:
#   cellranger-tiny-bcl-1.2.0.tar.gz   Tiny Illumina BCL run folder
#   cellranger-tiny-bcl-simple-1.2.0.csv  Matching SampleSheet CSV
#
# Extracts to:
#   $REPO_ROOT/test_data/10x/cellranger-mkfastq/tiny-bcl/
#   $REPO_ROOT/test_data/10x/cellranger-mkfastq/cellranger-tiny-bcl-simple-1.2.0.csv
#
# Usage:
#   download_10x_fixtures.sh [--dest <output_dir>] [--force]
#
# Options:
#   --dest <dir>   Override the destination directory (default: repo test_data dir)
#   --force        Re-download even if files already exist
#
# After downloading, use with tjp-test-suite:
#   tjp-test-suite --pipeline cellranger-mkfastq --layer 3

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
BCL_URL="https://cf.10xgenomics.com/supp/cell-exp/cellranger-tiny-bcl-1.2.0.tar.gz"
CSV_URL="https://cf.10xgenomics.com/supp/cell-exp/cellranger-tiny-bcl-simple-1.2.0.csv"
BCL_TARBALL="cellranger-tiny-bcl-1.2.0.tar.gz"
CSV_FILENAME="cellranger-tiny-bcl-simple-1.2.0.csv"

# Derive REPO_ROOT from this script's location (test_data/fixtures/ → repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_DERIVED="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Argument parsing ──────────────────────────────────────────────────────────
DEST_DIR="$REPO_ROOT_DERIVED/test_data/10x/cellranger-mkfastq"
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dest)
            [[ $# -lt 2 ]] && { printf '[ERROR] --dest requires a path\n' >&2; exit 1; }
            DEST_DIR="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \?//'
            exit 0
            ;;
        *)
            printf '[ERROR] Unknown argument: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

BCL_DEST="$DEST_DIR/tiny-bcl"
CSV_DEST="$DEST_DIR/$CSV_FILENAME"

printf '[INFO]  Destination: %s\n' "$DEST_DIR"
mkdir -p "$DEST_DIR"

# ── Detect download tool ───────────────────────────────────────────────────────
if command -v wget &>/dev/null; then
    _download() { wget -q --show-progress -O "$1" "$2"; }
elif command -v curl &>/dev/null; then
    _download() { curl -fL --progress-bar -o "$1" "$2"; }
else
    printf '[ERROR] Neither wget nor curl found. Install one and retry.\n' >&2
    exit 1
fi

# ── Download SampleSheet CSV ──────────────────────────────────────────────────
if [[ -f "$CSV_DEST" && "$FORCE" == false ]]; then
    printf '[INFO]  SampleSheet CSV already exists: %s\n' "$CSV_DEST"
else
    printf '[INFO]  Downloading SampleSheet CSV...\n'
    printf '        URL: %s\n' "$CSV_URL"
    _download "$CSV_DEST" "$CSV_URL"
    printf '[INFO]  Saved: %s\n' "$CSV_DEST"
fi

# ── Download and extract BCL tarball ─────────────────────────────────────────
if [[ -d "$BCL_DEST" && "$FORCE" == false ]]; then
    printf '[INFO]  BCL directory already exists: %s\n' "$BCL_DEST"
    printf '[INFO]  Use --force to re-download.\n'
else
    local_tarball="$DEST_DIR/$BCL_TARBALL"

    printf '[INFO]  Downloading BCL tarball (%s)...\n' "$BCL_TARBALL"
    printf '        URL: %s\n' "$BCL_URL"
    _download "$local_tarball" "$BCL_URL"
    printf '[INFO]  Saved: %s\n' "$local_tarball"

    printf '[INFO]  Extracting tarball...\n'
    tar -xzf "$local_tarball" -C "$DEST_DIR"
    printf '[INFO]  Extracted to: %s\n' "$DEST_DIR"

    # Verify extraction
    if [[ ! -d "$BCL_DEST" ]]; then
        # The tarball may extract to a differently named directory
        local extracted
        extracted=$(tar -tzf "$local_tarball" 2>/dev/null | head -1 | cut -d/ -f1)
        if [[ -d "$DEST_DIR/$extracted" ]]; then
            mv "$DEST_DIR/$extracted" "$BCL_DEST"
            printf '[INFO]  Renamed %s -> tiny-bcl\n' "$extracted"
        else
            printf '[WARN]  Expected BCL directory not found at %s\n' "$BCL_DEST" >&2
            printf '        Check extraction manually in %s\n' "$DEST_DIR" >&2
        fi
    fi

    # Remove tarball to save space (BCL data is ~230 MB compressed)
    rm -f "$local_tarball"
    printf '[INFO]  Removed tarball (extracted data retained).\n'
fi

# ── Summary ───────────────────────────────────────────────────────────────────
printf '\n[INFO]  Download complete. Files:\n'
[[ -d "$BCL_DEST" ]]  && printf '          BCL run folder : %s\n' "$BCL_DEST"
[[ -f "$CSV_DEST" ]]  && printf '          SampleSheet CSV: %s\n' "$CSV_DEST"

printf '\n[INFO]  Use with the test suite:\n'
printf '          tjp-test-suite --pipeline cellranger-mkfastq --layer 3\n'
printf '\n'
printf '[INFO]  Or manually:\n'
printf '          cat > /tmp/mkfastq_test.yaml <<YAML\n'
printf '          run_id: tiny_bcl_test\n'
printf '          run_dir: %s\n' "$BCL_DEST"
printf '          samplesheet: %s\n' "$CSV_DEST"
printf '          localcores: 4\n'
printf '          localmem: 16\n'
printf '          YAML\n'
printf '          tjp-launch cellranger-mkfastq --dev --config /tmp/mkfastq_test.yaml\n'
