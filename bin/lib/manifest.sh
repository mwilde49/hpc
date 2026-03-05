#!/usr/bin/env bash
# manifest.sh — reproducibility manifest generation
# Sourced by tjp-launch; never executed directly.

# ── Checksum ─────────────────────────────────────────────────────────────────
# compute_sif_checksum <sif_path>
# Partial md5 of first 10MB for sub-second execution on large containers.
compute_sif_checksum() {
    local sif="$1"
    if [[ -f "$sif" ]]; then
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
    local input_paths="" output_paths=""
    case "$pipeline" in
        addone)
            input_paths=$(yaml_get "$config" "input" 2>/dev/null || echo "")
            output_paths=$(yaml_get "$config" "output" 2>/dev/null || echo "")
            ;;
        bulkrnaseq)
            input_paths=$(yaml_get "$config" "fastq_dir" 2>/dev/null || echo "")
            output_paths="$SCRATCH_ROOT/nextflow_work"
            ;;
        psoma)
            input_paths=$(yaml_get "$config" "fastq_dir" 2>/dev/null || echo "")
            output_paths="$REPO_ROOT/containers/psoma"
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

# ── Post-submission update ───────────────────────────────────────────────────
# update_manifest_job_id <run_dir> <job_id>
update_manifest_job_id() {
    local run_dir="$1"
    local job_id="$2"
    sed -i "s/\"slurm_job_id\": \"pending\"/\"slurm_job_id\": \"$job_id\"/" "$run_dir/manifest.json"
}
