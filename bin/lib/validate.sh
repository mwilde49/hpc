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
        virome)         _validate_virome "$config" errors ;;
        cellranger)     _validate_cellranger "$config" errors ;;
        spaceranger)    _validate_spaceranger "$config" errors ;;
        xeniumranger)   _validate_xeniumranger "$config" errors ;;
        sqanti3)           _validate_sqanti3 "$config" errors ;;
        wf-transcriptomes) _validate_wf_transcriptomes "$config" errors ;;
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

# ── Virome validator ─────────────────────────────────────────────────────
_validate_virome() {
    local config="$1"
    local -n _errs=$2

    # Required keys
    local required_keys=(project_name samplesheet outdir star_index kraken2_db adapters container_dir)
    for key in "${required_keys[@]}"; do
        if ! yaml_has "$config" "$key"; then
            _errs+=("Missing required key: $key")
        fi
    done

    # Paths that must exist on disk
    local path_keys=(samplesheet star_index kraken2_db adapters container_dir)
    for key in "${path_keys[@]}"; do
        if yaml_has "$config" "$key"; then
            local val
            val=$(yaml_get "$config" "$key") || true
            if [[ -n "$val" && "$val" != /path/to/* && ! -e "$val" ]]; then
                _errs+=("Path does not exist for $key: $val")
            fi
        fi
    done

    # Samplesheet format: must have sample and fastq_r1 headers
    if yaml_has "$config" "samplesheet"; then
        local ss
        ss=$(yaml_get "$config" "samplesheet") || true
        if [[ -n "$ss" && -f "$ss" ]]; then
            local header
            header=$(head -1 "$ss")
            if ! grep -q "sample" <<< "$header"; then
                _errs+=("Samplesheet missing 'sample' column header: $ss")
            fi
            if ! grep -q "fastq_r1" <<< "$header"; then
                _errs+=("Samplesheet missing 'fastq_r1' column header: $ss")
            fi
        fi
    fi

    # container_dir: warn if directory exists but no .sif files built yet
    if yaml_has "$config" "container_dir"; then
        local cdir
        cdir=$(yaml_get "$config" "container_dir") || true
        if [[ -n "$cdir" && -d "$cdir" ]] && ! ls "$cdir"/*.sif &>/dev/null 2>&1; then
            warn "No .sif containers found in container_dir: $cdir"
            warn "  → Copy built containers or run: sbatch $REPO_ROOT/containers/virome/scripts/build_containers.sh"
        fi
    fi

    # Numeric params (optional but validated if present)
    for key in trim_headcrop trim_leading trim_trailing trim_minlen min_reads_per_taxon; do
        if yaml_has "$config" "$key"; then
            local val
            val=$(yaml_get "$config" "$key") || true
            if [[ -n "$val" && ! "$val" =~ ^[0-9]+$ ]]; then
                _errs+=("$key must be a non-negative integer, got: $val")
            fi
        fi
    done
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

# ── SQANTI3 validator ────────────────────────────────────────────────────────
_validate_sqanti3() {
    local config="$1"
    local -n _errs=$2

    # Required keys
    local required_keys=(sample isoforms refGTF refFasta outdir)
    for key in "${required_keys[@]}"; do
        if ! yaml_has "$config" "$key"; then
            _errs+=("Missing required key: $key")
        fi
    done

    # Required file paths that must exist
    local path_keys=(isoforms refGTF refFasta)
    for key in "${path_keys[@]}"; do
        if yaml_has "$config" "$key"; then
            local val
            val=$(yaml_get "$config" "$key") || true
            if [[ -n "$val" && "$val" != /path/to/* && ! -f "$val" ]]; then
                _errs+=("File does not exist for $key: $val")
            fi
        fi
    done

    # Optional file paths (warn if set but missing)
    local opt_keys=(coverage fl_count CAGE_peak polyA_motif_list polyA_peak)
    for key in "${opt_keys[@]}"; do
        if yaml_has "$config" "$key"; then
            local val
            val=$(yaml_get "$config" "$key") || true
            if [[ -n "$val" && "$val" != /path/to/* && ! -f "$val" ]]; then
                warn "Optional path does not exist for $key: $val"
            fi
        fi
    done

    # filter_mode: must be "rules" or "ml"
    if yaml_has "$config" "filter_mode"; then
        local fm
        fm=$(yaml_get "$config" "filter_mode") || true
        case "$fm" in
            rules|ml) ;;
            *) _errs+=("filter_mode must be 'rules' or 'ml', got: $fm") ;;
        esac
    fi

    # rescue_mode: must be "automatic" or "full"
    if yaml_has "$config" "rescue_mode"; then
        local rm_val
        rm_val=$(yaml_get "$config" "rescue_mode") || true
        case "$rm_val" in
            automatic|full) ;;
            *) _errs+=("rescue_mode must be 'automatic' or 'full', got: $rm_val") ;;
        esac
    fi

    # Numeric validation for cpus/chunks
    for key in cpus chunks; do
        if yaml_has "$config" "$key"; then
            local val
            val=$(yaml_get "$config" "$key") || true
            if [[ -n "$val" && ! "$val" =~ ^[0-9]+$ ]]; then
                _errs+=("$key must be a non-negative integer, got: $val")
            fi
        fi
    done
}

# ── wf-transcriptomes validator ───────────────────────────────────────────────
_validate_wf_transcriptomes() {
    local config="$1"
    local -n _errs=$2

    # Required keys
    for key in sample fastq_dir sample_sheet ref_genome ref_annotation outdir; do
        if ! yaml_has "$config" "$key"; then
            _errs+=("Missing required key: $key")
        else
            local val
            val=$(yaml_get "$config" "$key") || true
            [[ -z "$val" ]] && _errs+=("$key is empty")
        fi
    done

    # fastq_dir must exist
    if yaml_has "$config" "fastq_dir"; then
        local fastq_dir
        fastq_dir=$(yaml_get "$config" "fastq_dir") || true
        if [[ -n "$fastq_dir" && ! -d "$fastq_dir" ]]; then
            _errs+=("fastq_dir not found: $fastq_dir")
        fi
    fi

    # sample_sheet must exist
    if yaml_has "$config" "sample_sheet"; then
        local ss
        ss=$(yaml_get "$config" "sample_sheet") || true
        if [[ -n "$ss" && ! -f "$ss" ]]; then
            _errs+=("sample_sheet not found: $ss")
        fi
    fi

    # ref_genome must exist
    if yaml_has "$config" "ref_genome"; then
        local rg
        rg=$(yaml_get "$config" "ref_genome") || true
        if [[ -n "$rg" && ! -f "$rg" ]]; then
            _errs+=("ref_genome not found: $rg")
        fi
    fi

    # ref_annotation must exist
    if yaml_has "$config" "ref_annotation"; then
        local ra
        ra=$(yaml_get "$config" "ref_annotation") || true
        if [[ -n "$ra" && ! -f "$ra" ]]; then
            _errs+=("ref_annotation not found: $ra")
        fi
    fi

    # de_analysis: must be true or false
    if yaml_has "$config" "de_analysis"; then
        local de
        de=$(yaml_get "$config" "de_analysis") || true
        case "$de" in
            true|false) ;;
            *) _errs+=("de_analysis must be 'true' or 'false', got: $de") ;;
        esac
    fi

    # direct_rna: must be true or false
    if yaml_has "$config" "direct_rna"; then
        local dr
        dr=$(yaml_get "$config" "direct_rna") || true
        case "$dr" in
            true|false) ;;
            *) _errs+=("direct_rna must be 'true' or 'false', got: $dr") ;;
        esac
    fi
}
