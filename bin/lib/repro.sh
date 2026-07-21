#!/usr/bin/env bash
# repro.sh — Juno/SLURM runtime environment capture and invocation logging.
# Sourced by SLURM templates (not tjp-launch) — depends on $SLURM_* env vars
# that only exist inside a running job.

# capture_juno_env <run_dir>
# Writes juno_environment.json at job start: node, partition, allocated
# resources, GPU, submit host, apptainer version, start time. Call once near
# the top of the template, right after RUN_DIR is parsed — before pre-flight
# checks — so even a job that fails pre-flight still gets a record.
capture_juno_env() {
    local run_dir="$1"
    [[ -z "$run_dir" ]] && return 0
    mkdir -p "$run_dir"

    local start_ts
    start_ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
    start_ts="${start_ts:0:${#start_ts}-2}:${start_ts:${#start_ts}-2}"
    date +%s > "$run_dir/.juno_env_start_epoch"

    local gpu_info="none"
    [[ -n "${SLURM_JOB_GPUS:-}" ]] && gpu_info="$SLURM_JOB_GPUS"
    [[ -z "${SLURM_JOB_GPUS:-}" && -n "${CUDA_VISIBLE_DEVICES:-}" ]] && gpu_info="$CUDA_VISIBLE_DEVICES"

    local time_limit="unknown"
    if [[ -n "${SLURM_JOB_ID:-}" ]] && command -v scontrol &>/dev/null; then
        time_limit=$(scontrol show job "$SLURM_JOB_ID" 2>/dev/null | grep -oP 'TimeLimit=\K\S+' || echo "unknown")
    fi

    local apptainer_version
    apptainer_version=$(apptainer version 2>/dev/null | head -1)
    apptainer_version="${apptainer_version:-unknown}"

    cat > "$run_dir/juno_environment.json" <<EOF
{
    "slurm_job_id": "${SLURM_JOB_ID:-unknown}",
    "job_name": "${SLURM_JOB_NAME:-unknown}",
    "node_list": "${SLURM_JOB_NODELIST:-unknown}",
    "node_running": "${SLURMD_NODENAME:-$(hostname)}",
    "partition": "${SLURM_JOB_PARTITION:-unknown}",
    "cpus_per_task": "${SLURM_CPUS_PER_TASK:-unknown}",
    "mem_per_node": "${SLURM_MEM_PER_NODE:-${SBATCH_MEM_PER_NODE:-unknown}}",
    "time_limit": "$time_limit",
    "gpu": "$gpu_info",
    "submit_host": "${SLURM_SUBMIT_HOST:-unknown}",
    "apptainer_version": "$apptainer_version",
    "start_time": "$start_ts",
    "end_time": null,
    "duration_seconds": null,
    "exit_code": null,
    "sacct_state": null,
    "sacct_elapsed": null,
    "sacct_maxrss": null
}
EOF
}

# finalize_juno_env <run_dir> <exit_code>
# Call from an EXIT trap: trap 'finalize_juno_env "$RUN_DIR" "$?"' EXIT
# (set that trap immediately after the capture_juno_env call, so it fires
# no matter where the script exits). Records end time, duration, exit code,
# and best-effort sacct accounting.
#
# sacct backfill is inherently racy: this job's own accounting record is
# usually not finalized in the scheduler until a few seconds after this trap
# fires, so a few retries are attempted but an empty sacct_* result here is
# expected sometimes — it does not mean anything went wrong. Run
# `sacct -j <jobid> --format=State,Elapsed,MaxRSS` by hand afterward if you
# need the numbers and they didn't land.
finalize_juno_env() {
    local run_dir="$1"
    local exit_code="${2:-$?}"
    [[ -z "$run_dir" ]] && return 0
    local env_file="$run_dir/juno_environment.json"
    [[ -f "$env_file" ]] || return 0

    local end_ts
    end_ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
    end_ts="${end_ts:0:${#end_ts}-2}:${end_ts:${#end_ts}-2}"

    local duration="null"
    if [[ -f "$run_dir/.juno_env_start_epoch" ]]; then
        local start_epoch
        start_epoch=$(cat "$run_dir/.juno_env_start_epoch")
        duration=$(( $(date +%s) - start_epoch ))
        rm -f "$run_dir/.juno_env_start_epoch"
    fi

    sed -i \
        -e "s/\"end_time\": null/\"end_time\": \"$end_ts\"/" \
        -e "s/\"duration_seconds\": null/\"duration_seconds\": $duration/" \
        -e "s/\"exit_code\": null/\"exit_code\": $exit_code/" \
        "$env_file"

    if [[ -n "${SLURM_JOB_ID:-}" ]] && command -v sacct &>/dev/null; then
        local sacct_line=""
        for _attempt in 1 2 3; do
            sacct_line=$(sacct -j "${SLURM_JOB_ID}.batch" --format=State,Elapsed,MaxRSS --noheader --parsable2 2>/dev/null | head -1)
            [[ -z "$sacct_line" ]] && sacct_line=$(sacct -j "$SLURM_JOB_ID" --format=State,Elapsed,MaxRSS --noheader --parsable2 2>/dev/null | head -1)
            [[ -n "$sacct_line" ]] && break
            sleep 5
        done
        if [[ -n "$sacct_line" ]]; then
            local sacct_state sacct_elapsed sacct_maxrss
            IFS='|' read -r sacct_state sacct_elapsed sacct_maxrss <<< "$sacct_line"
            sed -i \
                -e "s/\"sacct_state\": null/\"sacct_state\": \"${sacct_state:-unknown}\"/" \
                -e "s/\"sacct_elapsed\": null/\"sacct_elapsed\": \"${sacct_elapsed:-unknown}\"/" \
                -e "s/\"sacct_maxrss\": null/\"sacct_maxrss\": \"${sacct_maxrss:-unknown}\"/" \
                "$env_file"
        fi
    fi
}

# run_logged <logfile> <command...>
# Echoes the fully-resolved, correctly-quoted command line, appends it to
# <logfile> (skipped if empty — e.g. no RUN_DIR because the template was run
# by hand outside tjp-launch), then executes the command. Returns the
# command's own exit code.
#
# The log line itself is written to stderr, not stdout — some callers (e.g.
# the SQANTI3 orchestrator, which does `JOB_ID=$(run_logged ... sbatch ...)`)
# need the wrapped command's stdout to come through completely clean.
run_logged() {
    local logfile="$1"; shift
    local line
    line="+ $(printf '%q ' "$@")"
    if [[ -n "$logfile" ]]; then
        mkdir -p "$(dirname "$logfile")"
        { printf -- '--- %s ---\n%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$line" | tee -a "$logfile"; } >&2
    else
        printf '%s\n' "$line" >&2
    fi
    "$@"
}
