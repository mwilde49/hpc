#!/usr/bin/env bash
# common.sh — shared constants and helpers for TJP pipeline tools
# Sourced by tjp-setup and tjp-launch; never executed directly.

set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────
# Derive REPO_ROOT from this script's location (bin/lib/ → repo root)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_ROOT="/work/$USER"
SCRATCH_ROOT="/scratch/juno/$USER"
USER_PIPELINES="$WORK_ROOT/pipelines"

# ── Pipeline registry ────────────────────────────────────────────────────────
# Maps pipeline name → container .sif path (relative to REPO_ROOT)
declare -A PIPELINE_CONTAINERS=(
    [addone]="containers/addone_latest.sif"
    [bulkrnaseq]="containers/bulkrnaseq/bulkrnaseq_v1.0.0.sif"
    [psoma]="containers/psoma/psomagen_v1.0.0.sif"
)

# Maps pipeline name → SLURM template path (relative to REPO_ROOT)
declare -A PIPELINE_TEMPLATES=(
    [addone]="slurm_templates/addone_slurm_template.sh"
    [bulkrnaseq]="slurm_templates/bulkrnaseq_slurm_template.sh"
    [psoma]="slurm_templates/psoma_slurm_template.sh"
    [cellranger]="slurm_templates/cellranger_slurm_template.sh"
    [spaceranger]="slurm_templates/spaceranger_slurm_template.sh"
    [xeniumranger]="slurm_templates/xeniumranger_slurm_template.sh"
)

# Maps native pipeline name → tool install directory
declare -A PIPELINE_TOOL_PATHS=(
    [cellranger]="/groups/tprice/software/cellranger"
    [spaceranger]="/groups/tprice/software/spaceranger"
    [xeniumranger]="/groups/tprice/software/xeniumranger"
)

# Native pipelines: no container, tool installed from tarball
NATIVE_PIPELINES=(cellranger spaceranger xeniumranger)

# Ordered list of known pipelines (bash 3 compat for iteration)
KNOWN_PIPELINES=(addone bulkrnaseq psoma cellranger spaceranger xeniumranger)

# ── Color output ─────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    _RED='\033[0;31m'
    _YELLOW='\033[0;33m'
    _GREEN='\033[0;32m'
    _CYAN='\033[0;36m'
    _BOLD='\033[1m'
    _RESET='\033[0m'
else
    _RED='' _YELLOW='' _GREEN='' _CYAN='' _BOLD='' _RESET=''
fi

_ts()    { date '+%H:%M:%S'; }
info()   { printf "${_CYAN}[%s]${_RESET} ${_GREEN}[INFO]${_RESET}  %s\n" "$(_ts)" "$*"; }
warn()   { printf "${_CYAN}[%s]${_RESET} ${_YELLOW}[WARN]${_RESET}  %s\n" "$(_ts)" "$*" >&2; }
error()  { printf "${_CYAN}[%s]${_RESET} ${_RED}[ERROR]${_RESET} %s\n" "$(_ts)" "$*" >&2; }
die()    { error "$@"; exit 1; }
header() { printf "\n${_BOLD}${_CYAN}=== %s ===${_RESET}\n\n" "$*"; }

# ── YAML helpers ─────────────────────────────────────────────────────────────
# yaml_get <file> <key>
# Reads a flat YAML key-value pair. Handles: key: value and key: "value"
# Returns empty string + exit 1 if key not found.
yaml_get() {
    local file="$1" key="$2"
    local val
    val=$(grep -E "^${key}:" "$file" 2>/dev/null | head -1 | sed "s/^${key}:[[:space:]]*//; s/[[:space:]]*#.*$//; s/^['\"]//; s/['\"]$//" || true)
    if [[ -z "$val" ]]; then
        return 1
    fi
    printf '%s' "$val"
}

# yaml_has <file> <key>
# Returns 0 if the key exists (even if value is empty after comment strip)
yaml_has() {
    local file="$1" key="$2"
    grep -qE "^${key}:" "$file" 2>/dev/null
}

# ── Utility functions ────────────────────────────────────────────────────────
timestamp() {
    date '+%Y-%m-%d_%H-%M-%S'
}

is_known_pipeline() {
    local name="$1"
    [[ -n "${PIPELINE_CONTAINERS[$name]+x}" || -n "${PIPELINE_TEMPLATES[$name]+x}" ]]
}

is_native_pipeline() {
    local n="$1"
    for p in "${NATIVE_PIPELINES[@]}"; do [[ "$p" == "$n" ]] && return 0; done
    return 1
}

get_tool_path() {
    local name="$1"
    local custom_path
    # Allow per-run override via config (checked by caller), fall back to registry
    printf '%s' "${PIPELINE_TOOL_PATHS[$name]:-}"
}

get_container_path() {
    local name="$1"
    printf '%s' "$REPO_ROOT/${PIPELINE_CONTAINERS[$name]}"
}

get_slurm_template() {
    local name="$1"
    printf '%s' "$REPO_ROOT/${PIPELINE_TEMPLATES[$name]}"
}

# ── Branding ────────────────────────────────────────────────────────────────
source "$(dirname "${BASH_SOURCE[0]}")/branding.sh"
