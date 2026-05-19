#!/usr/bin/env bash
# test_framework.sh — Hyperion Compute Test Suite framework
# Sourced by bin/tjp-test-suite; never executed directly.
#
# Depends on: bin/lib/common.sh (colors, _ts, yaml_get, REPO_ROOT, SCRATCH_ROOT,
#             WORK_ROOT) and bin/lib/branding.sh (hyperion_banner,
#             hyperion_milestone, hyperion_sign_off).

# ── Guard ────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf 'test_framework.sh must be sourced, not executed directly.\n' >&2
    exit 1
fi

# ── Global state ─────────────────────────────────────────────────────────────
declare -a _TS_RESULTS=()          # "pipeline:layer:name:status:detail"
declare -A _TS_PIPELINE_L1=()      # [pipeline] = pass|fail|skip|warn
declare -A _TS_PIPELINE_L2=()
declare -A _TS_PIPELINE_L3=()
_TS_TOTAL_PASS=0
_TS_TOTAL_FAIL=0
_TS_TOTAL_WARN=0
_TS_TOTAL_SKIP=0
_TS_CURRENT_PIPELINE=""
_TS_CURRENT_LAYER=""
_TS_LAYER_START_EPOCH=0
_TS_SUITE_START_EPOCH=$(date +%s)
_TS_SPINNER_PID=""

# ── Internal helpers ─────────────────────────────────────────────────────────

# _ts_dim <text>  — grey/dim text (no dedicated _DIM in common.sh, use bold+reset trick)
_ts_dim() { printf '\033[2m%s\033[0m' "$*"; }

# _ts_layer_map <layer_num> <pipeline>
# Echoes the associative-array variable name for that layer number.
_ts_layer_varname() {
    case "$1" in
        1) printf '_TS_PIPELINE_L1' ;;
        2) printf '_TS_PIPELINE_L2' ;;
        3) printf '_TS_PIPELINE_L3' ;;
    esac
}

# _ts_update_layer_status <pipeline> <layer_num> <new_status>
# Merges new_status into the pipeline's layer bucket using priority:
#   fail > warn > skip > pass  (existing fail stays fail, etc.)
_ts_update_layer_status() {
    local pipeline="$1" layer="$2" new_status="$3"
    local varname
    varname="$(_ts_layer_varname "$layer")"
    local current="${!varname[$pipeline]:-}"

    # Priority: fail > warn > skip > pass
    case "$current" in
        fail)   return ;;   # can't get worse
        warn)   [[ "$new_status" == "fail" ]] && eval "${varname}[$pipeline]=$new_status" ;;
        skip)   [[ "$new_status" == "fail" || "$new_status" == "warn" || "$new_status" == "pass" ]] \
                    && eval "${varname}[$pipeline]=$new_status" ;;
        pass)   [[ "$new_status" == "fail" || "$new_status" == "warn" ]] \
                    && eval "${varname}[$pipeline]=$new_status" ;;
        "")     eval "${varname}[$pipeline]=$new_status" ;;
    esac
}

# _ts_record <status> <desc> <detail>
# Appends to _TS_RESULTS and updates counters + per-pipeline layer status.
_ts_record() {
    local status="$1" desc="$2" detail="${3:-}"
    local layer_num="${_TS_CURRENT_LAYER%%[^0-9]*}"   # extract leading digit(s)
    _TS_RESULTS+=("${_TS_CURRENT_PIPELINE}:${_TS_CURRENT_LAYER}:${desc}:${status}:${detail}")

    case "$status" in
        pass) _TS_TOTAL_PASS=$(( _TS_TOTAL_PASS + 1 ))
              [[ -n "$_TS_CURRENT_PIPELINE" && -n "$layer_num" ]] \
                  && _ts_update_layer_status "$_TS_CURRENT_PIPELINE" "$layer_num" "pass" ;;
        fail) _TS_TOTAL_FAIL=$(( _TS_TOTAL_FAIL + 1 ))
              [[ -n "$_TS_CURRENT_PIPELINE" && -n "$layer_num" ]] \
                  && _ts_update_layer_status "$_TS_CURRENT_PIPELINE" "$layer_num" "fail" ;;
        warn) _TS_TOTAL_WARN=$(( _TS_TOTAL_WARN + 1 ))
              [[ -n "$_TS_CURRENT_PIPELINE" && -n "$layer_num" ]] \
                  && _ts_update_layer_status "$_TS_CURRENT_PIPELINE" "$layer_num" "warn" ;;
        skip) _TS_TOTAL_SKIP=$(( _TS_TOTAL_SKIP + 1 ))
              [[ -n "$_TS_CURRENT_PIPELINE" && -n "$layer_num" ]] \
                  && _ts_update_layer_status "$_TS_CURRENT_PIPELINE" "$layer_num" "skip" ;;
    esac
}

# ── Elapsed time ─────────────────────────────────────────────────────────────

# ts_elapsed_str <start_epoch>
# Prints HH:MM:SS elapsed since start_epoch.
ts_elapsed_str() {
    local start="$1"
    local now elapsed hh mm ss
    now=$(date +%s)
    elapsed=$(( now - start ))
    hh=$(( elapsed / 3600 ))
    mm=$(( (elapsed % 3600) / 60 ))
    ss=$(( elapsed % 60 ))
    printf '%02d:%02d:%02d' "$hh" "$mm" "$ss"
}

# ── Context management ────────────────────────────────────────────────────────

# ts_pipeline_start <pipeline_name>
ts_pipeline_start() {
    _TS_CURRENT_PIPELINE="$1"
    printf "\n  ${_BOLD}▸ %s${_RESET}\n" "$1"
}

# ts_layer_start <layer_num> <layer_name>
ts_layer_start() {
    _TS_CURRENT_LAYER="$1"
    _TS_LAYER_START_EPOCH=$(date +%s)
    local label
    label=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')
    printf "\n${_BOLD}▶ LAYER %s — %s${_RESET}\n" "$1" "$label"
    printf '%0.s─' {1..62}
    printf '\n'
}

# ts_layer_end
ts_layer_end() {
    local layer_num="$_TS_CURRENT_LAYER"
    local elapsed
    elapsed=$(ts_elapsed_str "$_TS_LAYER_START_EPOCH")

    # Count pass/fail for this layer across ALL pipelines
    local lpass=0 lfail=0 lwarn=0 lskip=0
    local entry
    for entry in "${_TS_RESULTS[@]:-}"; do
        local el es
        local rest="${entry#*:}"
        el="${rest%%:*}"                             # layer
        rest="${rest#*:}"; rest="${rest#*:}"
        es="${rest%%:*}"                             # status

        if [[ "$el" == "$layer_num" ]]; then
            case "$es" in
                pass) lpass=$(( lpass + 1 )) ;;
                fail) lfail=$(( lfail + 1 )) ;;
                warn) lwarn=$(( lwarn + 1 )) ;;
                skip) lskip=$(( lskip + 1 )) ;;
            esac
        fi
    done

    local total=$(( lpass + lfail + lwarn + lskip ))
    if [[ $lfail -eq 0 ]]; then
        printf "${_GREEN}[✓] Layer %s: %d/%d passed  |  0 failures  |  %s${_RESET}\n" \
            "$layer_num" "$lpass" "$total" "$elapsed"
    else
        printf "${_RED}[✗] Layer %s: %d/%d passed  |  %d failure(s)  |  %s${_RESET}\n" \
            "$layer_num" "$lpass" "$total" "$lfail" "$elapsed"
    fi
}

# ── Assertion functions ───────────────────────────────────────────────────────

# ts_assert_pass <desc> [cmd args...]
ts_assert_pass() {
    local desc="$1"; shift
    local rc=0
    if [[ $# -gt 0 ]]; then
        "$@" >/dev/null 2>&1 || rc=$?
    fi
    if [[ $rc -eq 0 ]]; then
        printf "  ${_GREEN}✓${_RESET}  %s\n" "$desc"
        _ts_record pass "$desc" ""
    else
        printf "  ${_RED}✗${_RESET}  %s\n" "$desc"
        printf "     ${_RED}└─ cmd exited %d${_RESET}\n" "$rc"
        _ts_record fail "$desc" "cmd exited $rc"
    fi
}

# ts_assert_fail <desc> [cmd args...]
# PASS if cmd exits nonzero (expects failure).
ts_assert_fail() {
    local desc="$1"; shift
    local rc=0
    if [[ $# -gt 0 ]]; then
        "$@" >/dev/null 2>&1 || rc=$?
    fi
    if [[ $rc -ne 0 ]]; then
        printf "  ${_GREEN}✓${_RESET}  %s\n" "$desc"
        _ts_record pass "$desc" ""
    else
        printf "  ${_RED}✗${_RESET}  %s\n" "$desc"
        printf "     ${_RED}└─ cmd exited 0 (expected nonzero)${_RESET}\n"
        _ts_record fail "$desc" "cmd exited 0 (expected nonzero)"
    fi
}

# ts_assert_exists <desc> <path>
ts_assert_exists() {
    local desc="$1" path="$2"
    if [[ -e "$path" ]]; then
        printf "  ${_GREEN}✓${_RESET}  %s\n" "$desc"
        _ts_record pass "$desc" ""
    else
        printf "  ${_RED}✗${_RESET}  %s\n" "$desc"
        printf "     ${_RED}└─ path not found: %s${_RESET}\n" "$path"
        _ts_record fail "$desc" "path not found: $path"
    fi
}

# ts_assert_nonempty <desc> <path>
ts_assert_nonempty() {
    local desc="$1" path="$2"
    if [[ -s "$path" ]]; then
        printf "  ${_GREEN}✓${_RESET}  %s\n" "$desc"
        _ts_record pass "$desc" ""
    else
        if [[ ! -e "$path" ]]; then
            printf "  ${_RED}✗${_RESET}  %s\n" "$desc"
            printf "     ${_RED}└─ path not found: %s${_RESET}\n" "$path"
            _ts_record fail "$desc" "path not found: $path"
        else
            printf "  ${_RED}✗${_RESET}  %s\n" "$desc"
            printf "     ${_RED}└─ file is empty: %s${_RESET}\n" "$path"
            _ts_record fail "$desc" "file is empty: $path"
        fi
    fi
}

# ts_assert_contains <desc> <file> <pattern>
ts_assert_contains() {
    local desc="$1" file="$2" pattern="$3"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        printf "  ${_GREEN}✓${_RESET}  %s\n" "$desc"
        _ts_record pass "$desc" ""
    else
        printf "  ${_RED}✗${_RESET}  %s\n" "$desc"
        printf "     ${_RED}└─ pattern '%s' not found in %s${_RESET}\n" "$pattern" "$file"
        _ts_record fail "$desc" "pattern '$pattern' not found in $file"
    fi
}

# ts_assert_yaml_key <desc> <yaml_file> <key>
ts_assert_yaml_key() {
    local desc="$1" yaml_file="$2" key="$3"
    local val
    val=$(yaml_get "$yaml_file" "$key" 2>/dev/null) || val=""
    if [[ -n "$val" ]]; then
        printf "  ${_GREEN}✓${_RESET}  %s\n" "$desc"
        _ts_record pass "$desc" ""
    else
        printf "  ${_RED}✗${_RESET}  %s\n" "$desc"
        printf "     ${_RED}└─ key '%s' missing or empty in %s${_RESET}\n" "$key" "$yaml_file"
        _ts_record fail "$desc" "key '$key' missing or empty in $yaml_file"
    fi
}

# ts_warn <desc> <message>
ts_warn() {
    local desc="$1" message="$2"
    printf "  ${_YELLOW}⚠${_RESET}  %s: %s\n" "$desc" "$message"
    _ts_record warn "$desc" "$message"
}

# ts_skip <desc> <reason>
ts_skip() {
    local desc="$1" reason="$2"
    printf "  $(_ts_dim "─  ${desc}: ${reason}")\n"
    _ts_record skip "$desc" "$reason"
}

# ── Progress display ──────────────────────────────────────────────────────────

# ts_progress_bar <current> <total>
ts_progress_bar() {
    local current="$1" total="$2"
    local bar_width=40
    local filled=0 remaining=0
    if [[ $total -gt 0 ]]; then
        filled=$(( current * bar_width / total ))
    fi
    remaining=$(( bar_width - filled ))
    local bar=""
    local i
    for (( i=0; i<filled; i++ )); do bar="${bar}▓"; done
    for (( i=0; i<remaining; i++ )); do bar="${bar}░"; done
    printf '\r  [%s] %d/%d' "$bar" "$current" "$total"
}

# ts_spinner_start <message>
ts_spinner_start() {
    local message="$1"
    # Kill any existing spinner first
    ts_spinner_stop 2>/dev/null || true

    # Launch background spinner writing to stderr
    (
        local chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local i=0
        while true; do
            printf '\r  %s  %s' "${chars[$i]}" "$message" >&2
            i=$(( (i + 1) % 10 ))
            sleep 0.1
        done
    ) &
    _TS_SPINNER_PID=$!
}

# ts_spinner_stop
ts_spinner_stop() {
    if [[ -n "${_TS_SPINNER_PID:-}" ]]; then
        kill "$_TS_SPINNER_PID" 2>/dev/null || true
        wait "$_TS_SPINNER_PID" 2>/dev/null || true
        _TS_SPINNER_PID=""
        # Clear spinner line
        printf '\r%*s\r' 72 '' >&2
    fi
}

# ── SLURM helpers ─────────────────────────────────────────────────────────────

# ts_slurm_job_state <jobid>
# Returns one of: PENDING RUNNING COMPLETED FAILED TIMEOUT CANCELLED UNKNOWN
ts_slurm_job_state() {
    local jobid="$1"
    local state
    if ! state=$(squeue -j "$jobid" --noheader -o '%T' 2>/dev/null); then
        printf 'UNKNOWN'
        return
    fi
    state="${state%%[[:space:]]*}"   # trim whitespace
    if [[ -z "$state" ]]; then
        # No longer in queue → completed
        printf 'COMPLETED'
        return
    fi
    # Normalise to one of our known states
    case "$state" in
        PENDING|RUNNING|COMPLETED|FAILED|TIMEOUT|CANCELLED) printf '%s' "$state" ;;
        *)  printf 'UNKNOWN' ;;
    esac
}

# ts_slurm_live_table <assoc_array_name>
# Monitors a set of SLURM jobs, refreshing a table every 30s until all finish.
# The caller passes the *name* of an associative array: declare -A jobs=([jobid]=pipeline).
ts_slurm_live_table() {
    local array_name="$1"

    # Collect job IDs and pipeline names by iterating via eval-safe nameref trick
    # We use eval here intentionally to dereference the caller's array by name.
    local -a job_ids=()
    local jobid pipeline

    # Build ordered list of job IDs from the associative array
    eval "job_ids=(\"\${!${array_name}[@]}\")"

    local num_jobs=${#job_ids[@]}
    local num_lines=$(( num_jobs + 4 ))   # header box: top + header + separator + N rows + bottom

    # Status color helper (inline, no subshell)
    _ts_state_color() {
        case "$1" in
            RUNNING)   printf '%s' "$_CYAN" ;;
            COMPLETED) printf '%s' "$_GREEN" ;;
            FAILED|TIMEOUT|CANCELLED) printf '%s' "$_RED" ;;
            PENDING)   printf '%s' "$_YELLOW" ;;
            *)         printf '%s' "$_RESET" ;;
        esac
    }
    _ts_state_symbol() {
        case "$1" in
            RUNNING)   printf '⟳' ;;
            COMPLETED) printf '✓' ;;
            FAILED|TIMEOUT|CANCELLED) printf '✗' ;;
            PENDING)   printf '·' ;;
            *)         printf '?' ;;
        esac
    }

    local first_draw=1
    while true; do
        # Move cursor up to overwrite previous table (skip on first draw)
        if [[ $first_draw -eq 0 ]]; then
            local line
            for (( line=0; line<num_lines; line++ )); do
                printf '\033[1A\033[2K'   # up one line, clear it
            done
        fi
        first_draw=0

        # Draw table
        printf '┌─────────────────────────────────────────────────────┐\n'
        printf '│  %-18s %-9s %-11s %-10s │\n' 'Pipeline' 'Job ID' 'Status' 'Elapsed'
        printf '│  %-18s %-9s %-11s %-10s │\n' '------------------' '---------' '-----------' '----------'

        local all_done=1
        for jobid in "${job_ids[@]}"; do
            eval "pipeline=\"\${${array_name}[$jobid]}\""
            local state elapsed_str
            state=$(ts_slurm_job_state "$jobid")
            # Get elapsed from squeue
            elapsed_str=$(squeue -j "$jobid" --noheader -o '%M' 2>/dev/null | head -1 || true)
            [[ -z "$elapsed_str" ]] && elapsed_str="--:--"

            local color symbol label
            color="$(_ts_state_color "$state")"
            symbol="$(_ts_state_symbol "$state")"
            label="$symbol $state"

            printf "│  ${color}%-18s %-9s %-11s %-10s${_RESET} │\n" \
                "$pipeline" "$jobid" "$label" "$elapsed_str"

            case "$state" in
                COMPLETED|FAILED|TIMEOUT|CANCELLED) : ;;
                *) all_done=0 ;;
            esac
        done

        printf '└─────────────────────────────────────────────────────┘\n'

        if [[ $all_done -eq 1 ]]; then
            return 0
        fi

        sleep 30
    done
}

# ── Suite banner ──────────────────────────────────────────────────────────────

# ts_suite_banner <pipeline_count> <layer_count>
ts_suite_banner() {
    local pipeline_count="${1:-11}"
    local layer_count="${2:-3}"
    local now nodes
    now=$(date '+%Y-%m-%d %H:%M:%S')
    nodes=$(sinfo -h -o '%D' 2>/dev/null | awk '{s+=$1} END {print s}') || nodes="N/A"

    printf "${_BOLD}${_CYAN}"
    printf '╔══════════════════════════════════════════════════════════════╗\n'
    printf '║   H Y P E R I O N   C O M P U T E                          ║\n'
    printf '║   T E S T   S U I T E                                       ║\n'
    printf '║                                                             ║\n'
    printf "║   %-11s pipelines  ·  %s layers  ·  %-20s║\n" \
        "$pipeline_count" "$layer_count" "$now  "
    printf "║   Juno: %s compute nodes available%-26s║\n" \
        "$nodes" " "
    printf '╚══════════════════════════════════════════════════════════════╝\n'
    printf "${_RESET}\n"
}

# ── Results table ─────────────────────────────────────────────────────────────

# _ts_layer_symbol <status>  — single char with color codes
_ts_layer_symbol() {
    case "${1:-}" in
        pass) printf "${_GREEN}✓${_RESET}" ;;
        fail) printf "${_RED}✗${_RESET}" ;;
        warn) printf "${_YELLOW}⚠${_RESET}" ;;
        skip) printf "$(_ts_dim '─')" ;;
        "")   printf "$(_ts_dim '─')" ;;
        *)    printf "$(_ts_dim '?')" ;;
    esac
}

# ts_results_table <pipeline_array_name>
# Takes name of indexed array of pipeline names (same order as KNOWN_PIPELINES).
ts_results_table() {
    local array_name="$1"
    local -a pipelines=()
    eval "pipelines=(\"\${${array_name}[@]}\")"

    local elapsed
    elapsed=$(ts_elapsed_str "$_TS_SUITE_START_EPOCH")

    # Count overall pass/fail for the summary line (pipelines that have any fail)
    local pipe_pass=0 pipe_fail=0
    local pipeline
    for pipeline in "${pipelines[@]}"; do
        local l1="${_TS_PIPELINE_L1[$pipeline]:-}"
        local l2="${_TS_PIPELINE_L2[$pipeline]:-}"
        local l3="${_TS_PIPELINE_L3[$pipeline]:-}"
        if [[ "$l1" == "fail" || "$l2" == "fail" || "$l3" == "fail" ]]; then
            pipe_fail=$(( pipe_fail + 1 ))
        else
            pipe_pass=$(( pipe_pass + 1 ))
        fi
    done
    local pipe_total=${#pipelines[@]}

    printf "${_BOLD}${_CYAN}"
    printf '═══════════════════════════════════════════════════════════════\n'
    printf '         ◈  HYPERION COMPUTE — MISSION REPORT  ◈\n'
    printf '═══════════════════════════════════════════════════════════════\n'
    printf "${_RESET}"

    # Header row
    printf "  ${_BOLD}%-20s  %-5s %-5s %-5s${_RESET}\n" 'Pipeline' 'L1' 'L2' 'L3'
    printf '  ─────────────────────────────────────\n'

    for pipeline in "${pipelines[@]}"; do
        local l1_st="${_TS_PIPELINE_L1[$pipeline]:-}"
        local l2_st="${_TS_PIPELINE_L2[$pipeline]:-}"
        local l3_st="${_TS_PIPELINE_L3[$pipeline]:-}"

        local l1_sym l2_sym l3_sym
        l1_sym="$(_ts_layer_symbol "$l1_st")"
        l2_sym="$(_ts_layer_symbol "$l2_st")"
        l3_sym="$(_ts_layer_symbol "$l3_st")"

        # Annotation
        local note=""
        if [[ "$l3_st" == "skip" || -z "$l3_st" ]]; then
            if [[ "$l2_st" == "fail" ]]; then
                note="(layer 3 skipped)"
            elif [[ -z "$l3_st" ]]; then
                note="(layer 3 skipped)"
            fi
        fi

        # Print with fixed-width name col; color codes make printf width math wrong,
        # so we print name + symbol columns separately.
        printf '  %-20s  %b     %b     %b    %s\n' \
            "$pipeline" "$l1_sym" "$l2_sym" "$l3_sym" "$note"
    done

    printf '  ─────────────────────────────────────\n'
    printf '  Total elapsed: %s\n' "$elapsed"
    printf '  Passed: %d/%d  ·  Warnings: %d  ·  Skipped: %d  ·  Failed: %d\n' \
        "$pipe_pass" "$pipe_total" "$_TS_TOTAL_WARN" "$_TS_TOTAL_SKIP" "$_TS_TOTAL_FAIL"

    printf "${_BOLD}${_CYAN}"
    printf '═══════════════════════════════════════════════════════════════\n'
    printf "${_RESET}"

    if [[ $_TS_TOTAL_FAIL -eq 0 ]]; then
        printf "     ${_BOLD}${_GREEN}Hyperion Compute — All systems nominal.${_RESET}\n"
    else
        printf "     ${_BOLD}${_RED}Hyperion Compute — Anomalies detected. Review failures above.${_RESET}\n"
    fi

    printf '\n'
}
