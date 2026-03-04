#!/usr/bin/env bash
# validate.sh — config validation for TJP pipelines
# Sourced by tjp-launch; never executed directly.

# ── Dispatcher ───────────────────────────────────────────────────────────────
# validate_config <pipeline> <config_file>
# Calls the per-pipeline validator. Collects all errors before failing.
validate_config() {
    local pipeline="$1" config="$2"
    local errors=()

    case "$pipeline" in
        addone)     _validate_addone "$config" errors ;;
        bulkrnaseq) _validate_bulkrnaseq "$config" errors ;;
        *)          die "No validator for pipeline: $pipeline" ;;
    esac

    if [[ ${#errors[@]} -gt 0 ]]; then
        error "Config validation failed for '$pipeline':"
        for e in "${errors[@]}"; do
            printf "  - %s\n" "$e" >&2
        done
        return 1
    fi
    return 0
}

# ── AddOne validator ─────────────────────────────────────────────────────────
_validate_addone() {
    local config="$1"
    local -n _errs=$2

    # Required keys
    if ! yaml_has "$config" "input"; then
        _errs+=("Missing required key: input")
    else
        local input_path
        input_path=$(yaml_get "$config" "input") || true
        if [[ -n "$input_path" && ! -f "$input_path" ]]; then
            _errs+=("Input file does not exist: $input_path")
        fi
    fi

    if ! yaml_has "$config" "output"; then
        _errs+=("Missing required key: output")
    fi
}

# ── BulkRNASeq validator ────────────────────────────────────────────────────
_validate_bulkrnaseq() {
    local config="$1"
    local -n _errs=$2

    # Required keys
    local required_keys=(
        project_name species paired_end
        fastq_dir samples_file star_index reference_gtf
        run_fastqc run_rna_pipeline
    )
    for key in "${required_keys[@]}"; do
        if ! yaml_has "$config" "$key"; then
            _errs+=("Missing required key: $key")
        fi
    done

    # Paths that must exist on disk
    local path_keys=(fastq_dir samples_file star_index reference_gtf exclude_bed_file_path blacklist_bed_file_path)
    for key in "${path_keys[@]}"; do
        if yaml_has "$config" "$key"; then
            local val
            val=$(yaml_get "$config" "$key") || true
            if [[ -n "$val" && "$val" != /path/to/* && ! -e "$val" ]]; then
                _errs+=("Path does not exist for $key: $val")
            fi
        fi
    done

    # Species soft warning
    if yaml_has "$config" "species"; then
        local species
        species=$(yaml_get "$config" "species") || true
        case "$species" in
            Human|Mouse|Rattus) ;;
            *) warn "Unrecognized species '$species' — expected Human, Mouse, or Rattus" ;;
        esac
    fi
}
