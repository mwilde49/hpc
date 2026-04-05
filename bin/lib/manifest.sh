#!/usr/bin/env bash
# manifest.sh — reproducibility manifest generation
# Sourced by tjp-launch; never executed directly.

# ── Checksum ─────────────────────────────────────────────────────────────────
# compute_sif_checksum <sif_path>
# Partial md5 of first 10MB for sub-second execution on large containers.
compute_sif_checksum() {
    local sif="$1"
    if [[ "$sif" == native:* ]]; then
        # Native tool: return version string instead of hash
        local tool_dir="${sif#native:}"
        local tool_name
        tool_name=$(basename "$tool_dir")
        if [[ -x "$tool_dir/$tool_name" ]]; then
            "$tool_dir/$tool_name" --version 2>/dev/null | head -1 || echo "version_unknown"
        else
            echo "tool_not_found"
        fi
    elif [[ -d "$sif" ]]; then
        # Multi-container directory: partial checksum of each .sif combined
        local combined=""
        for f in "$sif"/*.sif; do
            [[ -f "$f" ]] || continue
            combined+=$(dd if="$f" bs=1M count=10 2>/dev/null | md5sum | awk '{print $1}')
        done
        if [[ -n "$combined" ]]; then
            printf '%s' "$combined" | md5sum | awk '{print $1}'
        else
            printf 'containers_not_built'
        fi
    elif [[ -f "$sif" ]]; then
        dd if="$sif" bs=1M count=10 2>/dev/null | md5sum | awk '{print $1}'
    else
        printf 'container_not_found'
    fi
}

# ── Manifest generation ─────────────────────────────────────────────────────
# generate_manifest <run_dir> <pipeline> <config_file> <container_path> <slurm_template>
# Writes manifest.json to the run directory.
generate_manifest() {
    local run_dir="$1"
    local pipeline="$2"
    local config="$3"
    local container="$4"
    local slurm_template="$5"

    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
    # Insert colon in timezone offset for ISO 8601 (e.g., -0600 → -06:00)
    ts="${ts:0:${#ts}-2}:${ts:${#ts}-2}"

    local git_commit="unknown"
    if command -v git &>/dev/null && [[ -d "$REPO_ROOT/.git" ]]; then
        git_commit=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    fi

    local checksum
    checksum=$(compute_sif_checksum "$container")

    # Extract input/output paths from config based on pipeline type
    # Extract timestamp from run_dir (last path component)
    local run_ts
    run_ts=$(basename "$run_dir")
    local input_paths="" output_paths=""
    case "$pipeline" in
        addone)
            input_paths=$(yaml_get "$config" "input" 2>/dev/null || echo "")
            output_paths=$(yaml_get "$config" "output" 2>/dev/null || echo "")
            ;;
        bulkrnaseq)
            input_paths=$(yaml_get "$config" "fastq_dir" 2>/dev/null || echo "")
            output_paths="$SCRATCH_ROOT/pipelines/bulkrnaseq/runs/$run_ts"
            ;;
        psoma)
            input_paths=$(yaml_get "$config" "fastq_dir" 2>/dev/null || echo "")
            output_paths="$SCRATCH_ROOT/pipelines/psoma/runs/$run_ts"
            ;;
        virome)
            input_paths=$(yaml_get "$config" "samplesheet" 2>/dev/null || echo "")
            output_paths=$(yaml_get "$config" "outdir" 2>/dev/null || echo "")
            ;;
        cellranger|spaceranger)
            input_paths=$(yaml_get "$config" "fastq_dir" 2>/dev/null || echo "")
            output_paths="$SCRATCH_ROOT/pipelines/$pipeline/runs/$run_ts"
            ;;
        xeniumranger)
            input_paths=$(yaml_get "$config" "xenium_bundle" 2>/dev/null || echo "")
            output_paths="$SCRATCH_ROOT/pipelines/xeniumranger/runs/$run_ts"
            ;;
    esac

    cat > "$run_dir/manifest.json" <<MANIFEST_EOF
{
    "timestamp": "$ts",
    "user": "$USER",
    "pipeline": "$pipeline",
    "git_commit": "$git_commit",
    "container_file": "$container",
    "container_checksum": "$checksum",
    "config": "config.yaml",
    "slurm_job_id": "pending",
    "slurm_template": "$slurm_template",
    "input_paths": "$input_paths",
    "output_paths": "$output_paths"
}
MANIFEST_EOF
}

# ── Post-submission updates ──────────────────────────────────────────────────

# update_manifest_job_id <run_dir> <job_id>
update_manifest_job_id() {
    local run_dir="$1"
    local job_id="$2"
    sed -i "s/\"slurm_job_id\": \"pending\"/\"slurm_job_id\": \"$job_id\"/" "$run_dir/manifest.json"
}

# update_manifest_titan_id <run_dir> <plr_id>
# Cross-references the Titan PLR-xxxx ID into manifest.json.
update_manifest_titan_id() {
    local run_dir="$1"
    local plr_id="$2"
    sed -i "s/\"slurm_template\":/\"titan_pipeline_run_id\": \"$plr_id\",\n    \"slurm_template\":/" \
        "$run_dir/manifest.json"
}
