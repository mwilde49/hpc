#!/usr/bin/env bash
# branding.sh — Hyperion Biocruiser themed output for TJP pipeline tools
# Sourced by common.sh; never executed directly.

# hyperion_banner [mode_label]
# Prints the full ASCII banner with system status readout.
# Only prints when stdout is a terminal. Optional $1 is a mode label
# (e.g., "LAUNCH", "SETUP", "SMOKE TEST", "VALIDATION").
hyperion_banner() {
    local mode="${1:-}"
    local mode_line=""
    if [[ -n "$mode" ]]; then
        mode_line="  Mode: ${_BOLD}${_CYAN}${mode}${_RESET}"
    fi

    printf "${_BOLD}${_CYAN}"
    cat <<'BANNER'
=====================================================================
        H Y P E R I O N   B I O C R U I S E R   S Y S T E M
=====================================================================
BANNER
    printf "${_RESET}"

    cat <<'BANNER'

██╗  ██╗██╗   ██╗██████╗ ███████╗██████╗ ██╗ ██████╗ ███╗   ██╗
██║  ██║╚██╗ ██╔╝██╔══██╗██╔════╝██╔══██╗██║██╔═══██╗████╗  ██║
███████║ ╚████╔╝ ██████╔╝█████╗  ██████╔╝██║██║   ██║██╔██╗ ██║
██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══╝  ██╔══██╗██║██║   ██║██║╚██╗██║
██║  ██║   ██║   ██║     ███████╗██║  ██║██║╚██████╔╝██║ ╚████║
╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝

BANNER

    printf "${_CYAN}"
    cat <<'BANNER'
---------------------------------------------------------------------
 Biocruiser-Class Computational Engine
 Distributed Bioinformatics Orchestration Platform
---------------------------------------------------------------------
BANNER
    printf "${_RESET}"

    echo ""
    echo "[CORE SYSTEMS]"
    echo " SLURM Scheduler............ ACTIVE"
    echo " Pipeline Execution......... READY"
    echo ""
    echo "[MISSION CONTROL]"
    echo " Center for Advanced Pain Studies"
    echo " UT Dallas"
    if [[ -n "$mode_line" ]]; then
        echo ""
        printf '%s\n' "$mode_line"
    fi

    printf "${_BOLD}${_CYAN}"
    cat <<'BANNER'

=====================================================================
   Biocruiser Operational. Awaiting Execution Orders.
=====================================================================
BANNER
    printf "${_RESET}"
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
=====================================================================
    Biocruiser Operational. Mission Complete.
=====================================================================
BANNER
    printf "${_RESET}"
}
