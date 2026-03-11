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
        psoma)          _validate_psoma "$config" errors ;;
        cellranger)     _validate_cellranger "$config" errors ;;
        spaceranger)    _validate_spaceranger "$config" errors ;;
        xeniumranger)   _validate_xeniumranger "$config" errors ;;
        *)              die "No validator for pipeline: $pipeline" ;;
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

# ── Psoma validator ──────────────────────────────────────────────────────────
_validate_psoma() {
    local config="$1"
    local -n _errs=$2

    # Required keys
    local required_keys=(
        project_name species paired_end
        fastq_dir samples_file hisat2_index reference_gtf
        run_fastqc run_rna_pipeline
    )
    for key in "${required_keys[@]}"; do
        if ! yaml_has "$config" "$key"; then
            _errs+=("Missing required key: $key")
        fi
    done

    # Paths that must exist on disk
    local path_keys=(fastq_dir samples_file reference_gtf exclude_bed_file_path blacklist_bed_file_path)
    for key in "${path_keys[@]}"; do
        if yaml_has "$config" "$key"; then
            local val
            val=$(yaml_get "$config" "$key") || true
            if [[ -n "$val" && "$val" != /path/to/* && ! -e "$val" ]]; then
                _errs+=("Path does not exist for $key: $val")
            fi
        fi
    done

    # HISAT2 index prefix check (expects prefix.1.ht2 to exist)
    if yaml_has "$config" "hisat2_index"; then
        local idx
        idx=$(yaml_get "$config" "hisat2_index") || true
        if [[ -n "$idx" && "$idx" != /path/to/* && ! -f "${idx}.1.ht2" ]]; then
            _errs+=("HISAT2 index not found: ${idx}.1.ht2 (hisat2_index should be the prefix path)")
        fi
    fi

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

# ── Cell Ranger validator ─────────────────────────────────────────────────
_validate_cellranger() {
    local config="$1"
    local -n _errs=$2

    # Required keys
    local required_keys=(sample_id sample_name fastq_dir transcriptome localcores localmem create_bam)
    for key in "${required_keys[@]}"; do
        if ! yaml_has "$config" "$key"; then
            _errs+=("Missing required key: $key")
        fi
    done

    # Paths that must exist on disk
    local path_keys=(fastq_dir transcriptome)
    for key in "${path_keys[@]}"; do
        if yaml_has "$config" "$key"; then
            local val
            val=$(yaml_get "$config" "$key") || true
            if [[ -n "$val" && "$val" != __* && ! -e "$val" ]]; then
                _errs+=("Path does not exist for $key: $val")
            fi
        fi
    done

    # Numeric validation
    for key in localcores localmem; do
        if yaml_has "$config" "$key"; then
            local val
            val=$(yaml_get "$config" "$key") || true
            if [[ -n "$val" && ! "$val" =~ ^[0-9]+$ ]]; then
                _errs+=("$key must be a positive integer, got: $val")
            fi
        fi
    done

    # Optional tool_path check
    if yaml_has "$config" "tool_path"; then
        local tp
        tp=$(yaml_get "$config" "tool_path") || true
        if [[ -n "$tp" && ! -d "$tp" ]]; then
            _errs+=("tool_path directory does not exist: $tp")
        elif [[ -n "$tp" && ! -x "$tp/cellranger" ]]; then
            warn "cellranger binary not found at $tp/cellranger"
        fi
    fi
}

# ── Space Ranger validator ────────────────────────────────────────────────
_validate_spaceranger() {
    local config="$1"
    local -n _errs=$2

    # Required keys (slide+area OR unknown_slide)
    local required_keys=(sample_id sample_name fastq_dir transcriptome image localcores localmem create_bam)
    for key in "${required_keys[@]}"; do
        if ! yaml_has "$config" "$key"; then
            _errs+=("Missing required key: $key")
        fi
    done

    # Slide identification: either slide+area or unknown_slide
    if yaml_has "$config" "unknown_slide"; then
        local us
        us=$(yaml_get "$config" "unknown_slide") || true
        case "$us" in
            visium-1|visium-2|visium-2-large|visium-hd) ;;
            *) _errs+=("Invalid unknown_slide value: $us (expected visium-1, visium-2, visium-2-large, or visium-hd)") ;;
        esac
        if yaml_has "$config" "slide" || yaml_has "$config" "area"; then
            warn "Both unknown_slide and slide/area specified — unknown_slide takes precedence"
        fi
    else
        if ! yaml_has "$config" "slide"; then
            _errs+=("Missing required key: slide (or use unknown_slide)")
        fi
        if ! yaml_has "$config" "area"; then
            _errs+=("Missing required key: area (or use unknown_slide)")
        fi
    fi

    # Paths that must exist on disk
    local path_keys=(fastq_dir transcriptome image)
    for key in "${path_keys[@]}"; do
        if yaml_has "$config" "$key"; then
            local val
            val=$(yaml_get "$config" "$key") || true
            if [[ -n "$val" && "$val" != __* && ! -e "$val" ]]; then
                _errs+=("Path does not exist for $key: $val")
            fi
        fi
    done

    # Numeric validation
    for key in localcores localmem; do
        if yaml_has "$config" "$key"; then
            local val
            val=$(yaml_get "$config" "$key") || true
            if [[ -n "$val" && ! "$val" =~ ^[0-9]+$ ]]; then
                _errs+=("$key must be a positive integer, got: $val")
            fi
        fi
    done

    # Slide serial number format check
    if yaml_has "$config" "slide"; then
        local slide
        slide=$(yaml_get "$config" "slide") || true
        if [[ -n "$slide" && ! "$slide" =~ ^V[0-9] ]]; then
            warn "Slide serial number '$slide' doesn't match expected Visium format (V*)"
        fi
    fi

    # Area validation
    if yaml_has "$config" "area"; then
        local area
        area=$(yaml_get "$config" "area") || true
        case "$area" in
            A1|B1|C1|D1) ;;
            *) _errs+=("Invalid capture area: $area (expected A1, B1, C1, or D1)") ;;
        esac
    fi

    # Optional tool_path check
    if yaml_has "$config" "tool_path"; then
        local tp
        tp=$(yaml_get "$config" "tool_path") || true
        if [[ -n "$tp" && ! -d "$tp" ]]; then
            _errs+=("tool_path directory does not exist: $tp")
        elif [[ -n "$tp" && ! -x "$tp/spaceranger" ]]; then
            warn "spaceranger binary not found at $tp/spaceranger"
        fi
    fi
}

# ── Xenium Ranger validator ───────────────────────────────────────────────
_validate_xeniumranger() {
    local config="$1"
    local -n _errs=$2

    # Required keys
    local required_keys=(sample_id command xenium_bundle localcores localmem)
    for key in "${required_keys[@]}"; do
        if ! yaml_has "$config" "$key"; then
            _errs+=("Missing required key: $key")
        fi
    done

    # Xenium bundle path check
    if yaml_has "$config" "xenium_bundle"; then
        local val
        val=$(yaml_get "$config" "xenium_bundle") || true
        if [[ -n "$val" && "$val" != __* && ! -d "$val" ]]; then
            _errs+=("xenium_bundle directory does not exist: $val")
        fi
    fi

    # Numeric validation
    for key in localcores localmem; do
        if yaml_has "$config" "$key"; then
            local val
            val=$(yaml_get "$config" "$key") || true
            if [[ -n "$val" && ! "$val" =~ ^[0-9]+$ ]]; then
                _errs+=("$key must be a positive integer, got: $val")
            fi
        fi
    done

    # Command validation
    if yaml_has "$config" "command"; then
        local cmd
        cmd=$(yaml_get "$config" "command") || true
        case "$cmd" in
            resegment|import-segmentation) ;;
            *) _errs+=("Invalid command: $cmd (expected resegment or import-segmentation)") ;;
        esac

        # Conditional: segmentation_file required for import-segmentation
        if [[ "$cmd" == "import-segmentation" ]]; then
            if ! yaml_has "$config" "segmentation_file"; then
                _errs+=("Missing required key for import-segmentation: segmentation_file")
            else
                local sf
                sf=$(yaml_get "$config" "segmentation_file") || true
                if [[ -n "$sf" && ! -f "$sf" ]]; then
                    _errs+=("segmentation_file does not exist: $sf")
                fi
            fi
        fi
    fi

    # Optional tool_path check
    if yaml_has "$config" "tool_path"; then
        local tp
        tp=$(yaml_get "$config" "tool_path") || true
        if [[ -n "$tp" && ! -d "$tp" ]]; then
            _errs+=("tool_path directory does not exist: $tp")
        elif [[ -n "$tp" && ! -x "$tp/xeniumranger" ]]; then
            warn "xeniumranger binary not found at $tp/xeniumranger"
        fi
    fi
}
