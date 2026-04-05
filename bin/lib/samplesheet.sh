#!/usr/bin/env bash
# samplesheet.sh — CSV samplesheet validation and parsing helpers for TJP pipeline tools
# Sourced by common.sh; never executed directly.

# ── Per-pipeline required column definitions ──────────────────────────────────
# Each entry is a space-separated list of required column names.
declare -A _SAMPLESHEET_REQUIRED_COLS=(
    [virome]="sample fastq_r1 fastq_r2"
    [bulkrnaseq]="sample fastq_1 fastq_2"
    [psoma]="sample fastq_1 fastq_2"
    [cellranger]="sample fastqs transcriptome"
    [spaceranger]="sample fastqs transcriptome image slide area"
    [xeniumranger]="sample xenium_bundle command"
    [wf-transcriptomes]="barcode alias"
)

# ── Internal helpers ──────────────────────────────────────────────────────────

# _ss_error <message>
# Prints to stderr. Uses error() from common.sh when available, falls back to printf.
_ss_error() {
    if declare -f error &>/dev/null; then
        error "$*"
    else
        printf '[ERROR] %s\n' "$*" >&2
    fi
}

# _ss_header_line <samplesheet_path>
# Prints the first non-blank, non-comment line (the header row).
_ss_header_line() {
    local file="$1"
    grep -v '^[[:space:]]*$' "$file" | grep -v '^[[:space:]]*#' | head -1
}

# _ss_col_index <header_line> <column_name>
# Returns the 1-based column index of the named column, or 0 if not found.
_ss_col_index() {
    local header="$1" col="$2"
    printf '%s' "$header" | awk -F',' -v col="$col" '
    {
        for (i = 1; i <= NF; i++) {
            gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", $i)
            if ($i == col) { print i; exit }
        }
        print 0
    }'
}

# _ss_data_rows <samplesheet_path>
# Prints all data rows (skips header, blank lines, and comment lines).
_ss_data_rows() {
    local file="$1"
    local header_done=0
    while IFS= read -r line; do
        # Skip blank lines
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        # Skip comment lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ $header_done -eq 0 ]]; then
            header_done=1
            continue  # skip header row
        fi
        printf '%s\n' "$line"
    done < "$file"
}

# ── Public API ────────────────────────────────────────────────────────────────

# validate_samplesheet <pipeline> <samplesheet_path>
# Checks that the file exists, is readable, and contains all required columns
# for the given pipeline. Prints errors and returns 1 on failure.
validate_samplesheet() {
    local pipeline="$1" file="$2"
    local ok=0

    if [[ ! -f "$file" ]]; then
        _ss_error "Samplesheet not found: $file"
        return 1
    fi
    if [[ ! -r "$file" ]]; then
        _ss_error "Samplesheet is not readable: $file"
        return 1
    fi

    local required="${_SAMPLESHEET_REQUIRED_COLS[$pipeline]:-}"
    if [[ -z "$required" ]]; then
        _ss_error "No samplesheet schema defined for pipeline: $pipeline"
        return 1
    fi

    local header
    header="$(_ss_header_line "$file")"
    if [[ -z "$header" ]]; then
        _ss_error "Samplesheet appears empty or has no header row: $file"
        return 1
    fi

    for col in $required; do
        local idx
        idx="$(_ss_col_index "$header" "$col")"
        if [[ "$idx" -eq 0 ]]; then
            _ss_error "Samplesheet missing required column '$col' (pipeline: $pipeline)"
            ok=1
        fi
    done

    return $ok
}

# samplesheet_row_count <samplesheet_path>
# Prints the number of data rows (excluding header, blank lines, and comments).
samplesheet_row_count() {
    local file="$1"
    _ss_data_rows "$file" | wc -l | tr -d ' '
}

# samplesheet_get_col <samplesheet_path> <column_name> <row_num>
# Extracts the value at the given 1-indexed data row for the named column.
# Row 1 is the first data row (after the header). Prints empty string if not found.
samplesheet_get_col() {
    local file="$1" col="$2" row_num="$3"
    local header
    header="$(_ss_header_line "$file")"
    local idx
    idx="$(_ss_col_index "$header" "$col")"
    if [[ "$idx" -eq 0 ]]; then
        printf ''
        return 0
    fi
    _ss_data_rows "$file" | awk -F',' -v r="$row_num" -v c="$idx" '
    NR == r {
        gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", $c)
        print $c
        exit
    }'
}

# samplesheet_to_samples_file <samplesheet_path> <output_file>
# Writes one sample name per line to output_file, taken from the `sample` column.
# Used by bulkrnaseq and psoma to generate the samples_file config value.
samplesheet_to_samples_file() {
    local file="$1" output="$2"
    local header
    header="$(_ss_header_line "$file")"
    local idx
    idx="$(_ss_col_index "$header" "sample")"
    if [[ "$idx" -eq 0 ]]; then
        _ss_error "Samplesheet has no 'sample' column: $file"
        return 1
    fi
    _ss_data_rows "$file" | awk -F',' -v c="$idx" '
    {
        gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", $c)
        if ($c != "") print $c
    }' > "$output"
}

# samplesheet_infer_fastq_dir <samplesheet_path>
# For bulkrnaseq/psoma: prints dirname of the first fastq_1 value in the samplesheet.
samplesheet_infer_fastq_dir() {
    local file="$1"
    local header
    header="$(_ss_header_line "$file")"
    local idx
    idx="$(_ss_col_index "$header" "fastq_1")"
    if [[ "$idx" -eq 0 ]]; then
        _ss_error "Samplesheet has no 'fastq_1' column: $file"
        return 1
    fi
    local first_r1
    first_r1="$(_ss_data_rows "$file" | awk -F',' -v c="$idx" '
    NR == 1 {
        gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", $c)
        print $c
        exit
    }')"
    if [[ -z "$first_r1" ]]; then
        _ss_error "Could not read fastq_1 value from first data row: $file"
        return 1
    fi
    dirname "$first_r1"
}

# samplesheet_get_titan_ids <samplesheet_path> <row_num>
# Prints Titan ID fields for the given data row (1-indexed) in key=value format,
# one per line. Returns empty string for any column not present in the samplesheet.
# Titan columns: project_id, sample_id, library_id, run_id
samplesheet_get_titan_ids() {
    local file="$1" row_num="$2"
    local titan_cols="project_id sample_id library_id run_id"
    for col in $titan_cols; do
        local val
        val="$(samplesheet_get_col "$file" "$col" "$row_num")"
        printf '%s=%s\n' "$col" "$val"
    done
}
