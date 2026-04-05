#!/usr/bin/env bash
# metadata.sh — Titan metadata store helpers
# Sourced by common.sh; never executed directly.
#
# Manages local JSON records that mirror the Titan pipeline_runs table schema.
# When Titan DB comes online, records with titan_registered=false can be
# migrated by a future push script.

# ── Metadata store path ───────────────────────────────────────────────────────

# metadata_get_store
# Returns path to the metadata store root: $WORK_ROOT/pipelines/metadata
# Creates the directory tree if it does not yet exist.
metadata_get_store() {
    local store="$WORK_ROOT/pipelines/metadata"
    mkdir -p "$store/pipeline_runs"
    printf '%s' "$store"
}

# ── ID generation ─────────────────────────────────────────────────────────────

# generate_titan_id <TYPE>
# Generates a Titan-format ID: TYPE-{4 random lowercase alphanumeric chars}
# e.g. generate_titan_id PLR → PLR-a4f2
# Checks for collisions against existing records in the metadata store.
# TYPE values: PRJ, SMP, LIB, RUN, PLR, REF, ANN
generate_titan_id() {
    local type="$1"
    local store
    store=$(metadata_get_store)
    local id candidate
    local max_attempts=20
    local attempt=0

    while true; do
        attempt=$((attempt + 1))
        if [[ $attempt -gt $max_attempts ]]; then
            printf 'ERROR: could not generate unique %s ID after %d attempts\n' "$type" "$max_attempts" >&2
            return 1
        fi
        # 4 random lowercase alphanumeric characters using /dev/urandom
        candidate=$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c 4 2>/dev/null)
        id="${type}-${candidate}"
        # Collision check: look for any existing record with this ID
        if [[ ! -f "$store/pipeline_runs/${id}.json" ]]; then
            break
        fi
    done

    printf '%s' "$id"
}

# ── JSON helpers ──────────────────────────────────────────────────────────────

# _metadata_json_str <value>
# Emits a JSON string ("value") or literal null if value is empty.
_metadata_json_str() {
    local val="$1"
    if [[ -z "$val" ]]; then
        printf 'null'
    else
        # Escape backslash, double-quote, and control characters
        local escaped
        escaped=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')
        printf '"%s"' "$escaped"
    fi
}

# _metadata_params_hash <params_json>
# Returns sha256:... hash of the given JSON string.
_metadata_params_hash() {
    local params="$1"
    local raw
    if command -v sha256sum &>/dev/null; then
        raw=$(printf '%s' "$params" | sha256sum | awk '{print $1}')
    elif command -v openssl &>/dev/null; then
        raw=$(printf '%s' "$params" | openssl dgst -sha256 | awk '{print $2}')
    else
        raw="unavailable"
    fi
    printf 'sha256:%s' "$raw"
}

# ── Pipeline run record ───────────────────────────────────────────────────────

# write_pipeline_run_record <json_path> <key=value pairs...>
# Writes a pipeline_run JSON record to the given path.
# Recognised keys (all optional except pipeline_run_id, pipeline_name):
#   pipeline_run_id, pipeline_name, pipeline_version, project_id, sample_id,
#   library_id, run_id, output_path, status, parameters, container_image,
#   container_hash, slurm_job_id, started_at, completed_at, duration_seconds,
#   launched_by, launched_from, hyperion_run_dir, registered_at
write_pipeline_run_record() {
    local json_path="$1"
    shift

    # Defaults
    local pipeline_run_id=""
    local pipeline_name=""
    local pipeline_version=""
    local project_id=""
    local sample_id=""
    local library_id=""
    local run_id=""
    local output_path=""
    local status="pending"
    local parameters="{}"
    local container_image=""
    local container_hash=""
    local slurm_job_id=""
    local started_at=""
    local completed_at=""
    local duration_seconds=""
    local launched_by="${USER:-}"
    local launched_from=""
    launched_from=$(hostname 2>/dev/null || printf 'unknown')
    local hyperion_run_dir=""
    local registered_at
    registered_at=$(date -u '+%Y-%m-%dT%H:%M:%S+00:00' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S+00:00')

    # Parse key=value pairs
    local kv key val
    for kv in "$@"; do
        key="${kv%%=*}"
        val="${kv#*=}"
        case "$key" in
            pipeline_run_id)   pipeline_run_id="$val" ;;
            pipeline_name)     pipeline_name="$val" ;;
            pipeline_version)  pipeline_version="$val" ;;
            project_id)        project_id="$val" ;;
            sample_id)         sample_id="$val" ;;
            library_id)        library_id="$val" ;;
            run_id)            run_id="$val" ;;
            output_path)       output_path="$val" ;;
            status)            status="$val" ;;
            parameters)        parameters="$val" ;;
            container_image)   container_image="$val" ;;
            container_hash)    container_hash="$val" ;;
            slurm_job_id)      slurm_job_id="$val" ;;
            started_at)        started_at="$val" ;;
            completed_at)      completed_at="$val" ;;
            duration_seconds)  duration_seconds="$val" ;;
            launched_by)       launched_by="$val" ;;
            launched_from)     launched_from="$val" ;;
            hyperion_run_dir)  hyperion_run_dir="$val" ;;
            registered_at)     registered_at="$val" ;;
        esac
    done

    local params_hash
    params_hash=$(_metadata_params_hash "$parameters")

    # duration_seconds must be numeric null or integer — emit bare null or number
    local duration_json
    if [[ -z "$duration_seconds" ]]; then
        duration_json="null"
    else
        duration_json="$duration_seconds"
    fi

    mkdir -p "$(dirname "$json_path")"

    cat > "$json_path" <<EOF
{
    "pipeline_run_id": $(_metadata_json_str "$pipeline_run_id"),
    "pipeline_name": $(_metadata_json_str "$pipeline_name"),
    "pipeline_version": $(_metadata_json_str "$pipeline_version"),
    "project_id": $(_metadata_json_str "$project_id"),
    "sample_id": $(_metadata_json_str "$sample_id"),
    "library_id": $(_metadata_json_str "$library_id"),
    "run_id": $(_metadata_json_str "$run_id"),
    "output_path": $(_metadata_json_str "$output_path"),
    "status": $(_metadata_json_str "$status"),
    "parameters": $parameters,
    "parameters_hash": $(_metadata_json_str "$params_hash"),
    "container_image": $(_metadata_json_str "$container_image"),
    "container_hash": $(_metadata_json_str "$container_hash"),
    "slurm_job_id": $(_metadata_json_str "$slurm_job_id"),
    "started_at": $(_metadata_json_str "$started_at"),
    "completed_at": $(_metadata_json_str "$completed_at"),
    "duration_seconds": $duration_json,
    "launched_by": $(_metadata_json_str "$launched_by"),
    "launched_from": $(_metadata_json_str "$launched_from"),
    "hyperion_run_dir": $(_metadata_json_str "$hyperion_run_dir"),
    "registered_at": $(_metadata_json_str "$registered_at"),
    "titan_registered": false
}
EOF
}

# register_pipeline_run [--pipeline <name>] [--version <ver>] [--output-path <path>]
#                       [--status <status>] [--project <id>] [--sample <id>]
#                       [--library <id>] [--run-id <id>] [--slurm-job-id <id>]
#                       [--container <image>] [--params <json>] [--run-dir <path>]
#                       [--started-at <iso8601>]
# Generates a PLR-xxxx ID, writes the record to the metadata store, and
# optionally copies it to <run_dir>/titan_metadata.json.
# Prints the generated PLR-xxxx ID on stdout.
register_pipeline_run() {
    local pipeline_name=""
    local pipeline_version=""
    local output_path=""
    local status="pending"
    local project_id=""
    local sample_id=""
    local library_id=""
    local run_id=""
    local slurm_job_id=""
    local container_image=""
    local parameters="{}"
    local run_dir=""
    local started_at=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pipeline)      pipeline_name="$2";  shift 2 ;;
            --version)       pipeline_version="$2"; shift 2 ;;
            --output-path)   output_path="$2";    shift 2 ;;
            --status)        status="$2";          shift 2 ;;
            --project)       project_id="$2";      shift 2 ;;
            --sample)        sample_id="$2";        shift 2 ;;
            --library)       library_id="$2";       shift 2 ;;
            --run-id)        run_id="$2";           shift 2 ;;
            --slurm-job-id)  slurm_job_id="$2";    shift 2 ;;
            --container)     container_image="$2";  shift 2 ;;
            --params)        parameters="$2";       shift 2 ;;
            --run-dir)       run_dir="$2";          shift 2 ;;
            --started-at)    started_at="$2";       shift 2 ;;
            *) printf 'register_pipeline_run: unknown option: %s\n' "$1" >&2; return 1 ;;
        esac
    done

    local store
    store=$(metadata_get_store)

    local plr_id
    plr_id=$(generate_titan_id PLR)

    local record_path="$store/pipeline_runs/${plr_id}.json"

    write_pipeline_run_record "$record_path" \
        "pipeline_run_id=${plr_id}" \
        "pipeline_name=${pipeline_name}" \
        "pipeline_version=${pipeline_version}" \
        "project_id=${project_id}" \
        "sample_id=${sample_id}" \
        "library_id=${library_id}" \
        "run_id=${run_id}" \
        "output_path=${output_path}" \
        "status=${status}" \
        "parameters=${parameters}" \
        "container_image=${container_image}" \
        "slurm_job_id=${slurm_job_id}" \
        "started_at=${started_at}" \
        "hyperion_run_dir=${run_dir}" \
        "launched_by=${USER:-}"

    # Copy to run directory if --run-dir was provided
    if [[ -n "$run_dir" && -d "$run_dir" ]]; then
        cp "$record_path" "$run_dir/titan_metadata.json"
    fi

    printf '%s\n' "$plr_id"
}

# ── Status update ─────────────────────────────────────────────────────────────

# update_pipeline_run_status <plr_id> <status>
#                            [--completed-at <iso8601>] [--duration <secs>]
#                            [--slurm-job-id <id>]
# Updates fields in an existing pipeline_run JSON record using sed.
# No jq required.
update_pipeline_run_status() {
    local plr_id="$1"
    local new_status="$2"
    shift 2

    local completed_at=""
    local duration_secs=""
    local slurm_job_id=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --completed-at)  completed_at="$2";  shift 2 ;;
            --duration)      duration_secs="$2"; shift 2 ;;
            --slurm-job-id)  slurm_job_id="$2";  shift 2 ;;
            *) printf 'update_pipeline_run_status: unknown option: %s\n' "$1" >&2; return 1 ;;
        esac
    done

    local store
    store=$(metadata_get_store)
    local record_path="$store/pipeline_runs/${plr_id}.json"

    if [[ ! -f "$record_path" ]]; then
        printf 'update_pipeline_run_status: record not found: %s\n' "$record_path" >&2
        return 1
    fi

    # Update status field (sed in-place, POSIX-compatible)
    sed -i "s|\"status\": \"[^\"]*\"|\"status\": \"${new_status}\"|" "$record_path"

    if [[ -n "$completed_at" ]]; then
        sed -i "s|\"completed_at\": null|\"completed_at\": \"${completed_at}\"|" "$record_path"
        sed -i "s|\"completed_at\": \"[^\"]*\"|\"completed_at\": \"${completed_at}\"|" "$record_path"
    fi

    if [[ -n "$duration_secs" ]]; then
        sed -i "s|\"duration_seconds\": null|\"duration_seconds\": ${duration_secs}|" "$record_path"
        sed -i "s|\"duration_seconds\": [0-9][0-9]*|\"duration_seconds\": ${duration_secs}|" "$record_path"
    fi

    if [[ -n "$slurm_job_id" ]]; then
        sed -i "s|\"slurm_job_id\": null|\"slurm_job_id\": \"${slurm_job_id}\"|" "$record_path"
        sed -i "s|\"slurm_job_id\": \"[^\"]*\"|\"slurm_job_id\": \"${slurm_job_id}\"|" "$record_path"
    fi
}
