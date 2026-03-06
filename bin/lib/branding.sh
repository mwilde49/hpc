#!/usr/bin/env bash
# branding.sh — Hyperion Compute themed output for TJP pipeline tools
# Sourced by common.sh; never executed directly.

# hyperion_banner [mode_label]
# Prints the Hyperion Compute banner with dynamic system status.
# Optional $1 is a mode label (e.g., "LAUNCH", "SETUP").
hyperion_banner() {
    local mode="${1:-}"
    local nodes
    nodes=$(sinfo -h -o '%D' 2>/dev/null | awk '{s+=$1} END {print s}') 2>/dev/null || nodes="N/A"

    printf "${_BOLD}${_CYAN}"
    cat <<'BANNER'
============================================================
            H Y P E R I O N   C O M P U T E
------------------------------------------------------------
  Distributed Bioinformatics Execution Framework
  SLURM Orchestration • Pipeline Automation • HPC Scale
============================================================
BANNER
    printf "${_RESET}"
    echo ""

    if [[ -n "$mode" ]]; then
        printf "  ${_BOLD}${_CYAN}Mode:${_RESET} %s\n\n" "$mode"
    fi

    echo "Initializing Hyperion Pipeline Engine..."
    echo "Cluster nodes detected: $nodes"
    echo "SLURM scheduler online."
    echo ""
}

# hyperion_milestone <message>
# Themed milestone line for major events (job submit, archive done, etc.)
hyperion_milestone() {
    printf "${_BOLD}${_CYAN}[HYPERION]${_RESET} ${_BOLD}%s${_RESET}\n" "$*"
}

# hyperion_sign_off
# Closing banner printed at the very end of a tool's execution.
hyperion_sign_off() {
    echo ""
    printf "${_BOLD}${_CYAN}"
    cat <<'BANNER'
============================================================
    Hyperion Compute — Mission Complete.
============================================================
BANNER
    printf "${_RESET}"
}
