#!/usr/bin/env bash
# provenance.sh — per-run console capture, software-version capture, and the
# human-readable PROVENANCE_README.md report.
# Sourced by SLURM templates (not tjp-launch), alongside repro.sh — depends
# on $SLURM_* env vars and on the run-directory artifacts repro.sh/manifest.sh
# already write (juno_environment.json, manifest.json, invocation.log).
#
# Wired into all 13 pipelines. Two templates (sqanti3, wf-transcriptomes) run
# under `set -euo pipefail`; every function below that does real work is
# either inherently pipefail-safe (pipelines ending in a command that always
# exits 0, like `head`) or explicitly runs its body in a `set +e` subshell —
# this file's best-effort instrumentation must never be able to abort the
# pipeline run it's trying to document. See _run_guarded below.

# start_console_log <run_dir>
# Tees all subsequent stdout/stderr to CONSOLE_LOG.txt, in addition to
# SLURM's own slurm_<jobid>.out/.err. Call once, immediately after
# capture_juno_env/the EXIT trap are set up, so pre-flight failures are
# captured too. No-ops if run_dir is empty (template run by hand, outside
# tjp-launch). Cannot run in a subshell (exec needs to modify the current
# shell's file descriptors), so it saves/restores `set -e` manually instead.
start_console_log() {
    local run_dir="$1"
    [[ -z "$run_dir" ]] && return 0
    mkdir -p "$run_dir"

    local had_e=0
    case "$-" in *e*) had_e=1 ;; esac
    set +e
    exec > >(tee -a "$run_dir/CONSOLE_LOG.txt") 2>&1
    [[ "$had_e" -eq 1 ]] && set -e
    return 0
}

# _run_guarded <function> [args...]
# Runs <function> in a `set +e` subshell so nothing inside it — probing a
# missing tool, an empty grep match, a pipeline whose middle stage fails —
# can trip the calling SLURM template's `set -e`. Safe to use for anything
# that only writes files and doesn't need to set variables the caller reads.
_run_guarded() {
    ( set +e; "$@" )
    return 0
}

# ── Software version capture ────────────────────────────────────────────────

# capture_software_versions <run_dir> <pipeline> <primary> [secondary]
# Writes software_versions.txt. What <primary>/<secondary> mean depends on
# the pipeline's architecture:
#   - single-container (psoma, bulkrnaseq, dconvatac, dconvatac-gpu, addone,
#     sqanti3): <primary> = path to the .sif
#   - virome (multi-container): <primary> = containers/virome dir (holds
#     fastqc.sif, trimmomatic.sif, star.sif, kraken2.sif, python.sif,
#     multiqc.sif — one tool per container)
#   - wf-transcriptomes: <primary> = path to the nextflow binary. It runs
#     natively (not in a container); per-process containers are pulled and
#     managed by the external epi2me-labs/wf-transcriptomes workflow itself
#     at run time, not declared anywhere in this repo — out of scope to
#     probe directly. nextflow_logs/report.html lists what each process
#     actually used.
#   - native 10x pipelines (cellranger, cellranger-mkfastq, cellranger-multi,
#     spaceranger, xeniumranger): <primary> = config.yaml path (to honor a
#     tool_path: override the same way the wrapper script does), <secondary>
#     = containers/10x repo root (to source its find_10x_binary/
#     get_10x_version helpers rather than re-implementing tool discovery)
# Call after confirming the container/wrapper/tool exists, before running
# the pipeline, so even a run that fails mid-pipeline still gets a record.
capture_software_versions() {
    local run_dir="$1"
    local pipeline="$2"
    local primary="$3"
    local secondary="${4:-}"
    [[ -z "$run_dir" ]] && return 0
    mkdir -p "$run_dir"

    case "$pipeline" in
        psoma|bulkrnaseq|dconvatac|dconvatac-gpu|addone)
            _run_guarded _capture_versions_container "$run_dir" "$pipeline" "$primary" ;;
        sqanti3)
            _run_guarded _capture_versions_sqanti3 "$run_dir" "$primary" ;;
        virome)
            _run_guarded _capture_versions_virome "$run_dir" "$primary" ;;
        wf-transcriptomes)
            _run_guarded _capture_versions_wf_transcriptomes "$run_dir" "$primary" ;;
        cellranger|cellranger-mkfastq|cellranger-multi|spaceranger|xeniumranger)
            _run_guarded _capture_versions_10x_native "$run_dir" "$pipeline" "$primary" "$secondary" ;;
        *)
            return 0 ;;
    esac
}

# _apptainer_probe <container> <cmd>
# Runs <cmd> inside <container> via `bash -c`, returns the cleaned first
# line of output, or "(not captured)" if empty. Pipefail-safe: always ends
# in `head -1`, which exits 0 even when the upstream command failed or
# produced nothing.
_apptainer_probe() {
    local container="$1" cmd="$2"
    local out
    out=$(apptainer exec --cleanenv "$container" bash -c "$cmd" 2>/dev/null | tr -d '\r' | head -1)
    [[ -z "$out" ]] && out="(not captured)"
    printf '%s' "$out"
}

_write_versions_header() {
    local run_dir="$1" source_desc="$2"
    {
        echo "# Software versions captured live from this run's $source_desc."
        echo "# Captured: $(date '+%Y-%m-%dT%H:%M:%S%z')"
        echo ""
    } > "$run_dir/software_versions.txt"
}

_capture_versions_container() {
    local run_dir="$1" pipeline="$2" container="$3"
    local -a probes=()
    case "$pipeline" in
        psoma)
            probes=(
                "FastQC|fastqc --version"
                "MultiQC|multiqc --version"
                "HISAT2|hisat2 --version 2>&1 | head -1"
                "Trimmomatic|trimmomatic -version 2>&1 | head -1"
                "Samtools|samtools --version | head -1"
                "Sambamba|sambamba --version 2>&1 | head -1"
                "Bedtools|bedtools --version"
                "StringTie|stringtie --version"
                "HTSeq|htseq-count --version 2>&1 | head -1"
                "Qualimap|qualimap --version 2>&1 | head -1"
                "R|R --version | head -1"
                "Rsubread|Rscript -e 'suppressMessages(library(Rsubread)); cat(as.character(packageVersion(\"Rsubread\")))'"
                "Python|python --version 2>&1"
                "pandas|python -c 'import pandas; print(pandas.__version__)'"
                "Nextflow|nextflow -version 2>&1 | grep -i version | head -1"
                "Java|java -version 2>&1 | head -1"
            )
            ;;
        bulkrnaseq)
            probes=(
                "FastQC|fastqc --version"
                "MultiQC|multiqc --version"
                "STAR|STAR --version"
                "Samtools|samtools --version | head -1"
                "Sambamba|sambamba --version 2>&1 | head -1"
                "Bedtools|bedtools --version"
                "StringTie|stringtie --version"
                "HTSeq|htseq-count --version 2>&1 | head -1"
                "Qualimap|qualimap --version 2>&1 | head -1"
                "R|R --version | head -1"
                "Rsubread|Rscript -e 'suppressMessages(library(Rsubread)); cat(as.character(packageVersion(\"Rsubread\")))'"
                "Python|python --version 2>&1"
                "pandas|python -c 'import pandas; print(pandas.__version__)'"
                "Nextflow|nextflow -version 2>&1 | grep -i version | head -1"
                "Java|java -version 2>&1 | head -1"
            )
            ;;
        dconvatac|dconvatac-gpu)
            probes=(
                "Python|python --version 2>&1"
                "scanpy|python -c 'import scanpy; print(scanpy.__version__)'"
                "pandas|python -c 'import pandas; print(pandas.__version__)'"
                "numpy|python -c 'import numpy; print(numpy.__version__)'"
                "matplotlib|python -c 'import matplotlib; print(matplotlib.__version__)'"
                "torch|python -c 'import torch; print(torch.__version__)'"
                "cell2location|python -c 'import cell2location; print(cell2location.__version__)'"
                "deconvATAC|pip show deconvatac 2>/dev/null | grep -i '^Version' | head -1"
            )
            ;;
        addone)
            probes=(
                "Python|python --version 2>&1"
                "PyYAML|python -c 'import yaml; print(yaml.__version__)'"
            )
            ;;
    esac

    _write_versions_header "$run_dir" "container ($container)"
    local probe label cmd
    for probe in "${probes[@]}"; do
        label="${probe%%|*}"
        cmd="${probe#*|}"
        printf '%s: %s\n' "$label" "$(_apptainer_probe "$container" "$cmd")" >> "$run_dir/software_versions.txt"
    done
}

_capture_versions_sqanti3() {
    local run_dir="$1" container="$2"
    _write_versions_header "$run_dir" "container ($container, conda env 'sqanti3')"
    {
        printf 'SQANTI3: %s\n' "$(_apptainer_probe "$container" "HOME=/tmp conda run --no-capture-output -n sqanti3 sqanti3 --version 2>&1 | head -1")"
        printf 'minimap2: %s\n' "$(_apptainer_probe "$container" "HOME=/tmp conda run --no-capture-output -n sqanti3 minimap2 --version 2>&1 | head -1")"
        echo ""
        echo "# Only the orchestrator-level container is probed here. The 4 stage"
        echo "# jobs (qc/refqc/filter/rescue) use this same SIF but run from scripts"
        echo "# in the containers/sqanti3 submodule, a separate repo — per-stage"
        echo "# instrumentation is out of scope (see CLAUDE.md)."
    } >> "$run_dir/software_versions.txt"
}

_capture_versions_virome() {
    local run_dir="$1" repo_dir="$2"
    _write_versions_header "$run_dir" "per-process containers ($repo_dir/*.sif)"
    local name cmd sif
    for name in fastqc trimmomatic star kraken2 python multiqc; do
        case "$name" in
            fastqc)      cmd="fastqc --version" ;;
            trimmomatic) cmd="trimmomatic -version 2>&1 | head -1" ;;
            star)        cmd="STAR --version" ;;
            kraken2)     cmd="kraken2 --version 2>&1 | head -1" ;;
            python)      cmd="python --version 2>&1" ;;
            multiqc)     cmd="multiqc --version" ;;
        esac
        sif="$repo_dir/${name}.sif"
        if [[ -f "$sif" ]]; then
            printf '%s: %s\n' "$name" "$(_apptainer_probe "$sif" "$cmd")" >> "$run_dir/software_versions.txt"
        else
            printf '%s: (container not found: %s)\n' "$name" "$sif" >> "$run_dir/software_versions.txt"
        fi
    done
}

_capture_versions_wf_transcriptomes() {
    local run_dir="$1" nextflow_bin="$2"
    _write_versions_header "$run_dir" "Nextflow binary ($nextflow_bin)"
    local nf_ver
    nf_ver=$("$nextflow_bin" -version 2>&1 | grep -i version | head -1)
    [[ -z "$nf_ver" ]] && nf_ver="(not captured)"
    {
        printf 'Nextflow: %s\n' "$nf_ver"
        echo ""
        echo "# Per-process tool versions are managed by the external"
        echo "# epi2me-labs/wf-transcriptomes workflow's own container"
        echo "# definitions, not this repo — out of scope to probe directly."
        echo "# See nextflow_logs/report.html, which lists the container each"
        echo "# process actually used."
    } >> "$run_dir/software_versions.txt"
}

_capture_versions_10x_native() {
    local run_dir="$1" pipeline="$2" config="$3" tenx_root="$4"
    local tool=""
    case "$pipeline" in
        cellranger|cellranger-mkfastq|cellranger-multi) tool="cellranger" ;;
        spaceranger) tool="spaceranger" ;;
        xeniumranger) tool="xeniumranger" ;;
    esac
    [[ -z "$tool" || -z "$tenx_root" || ! -f "$tenx_root/lib/10x_common.sh" ]] && return 0

    _write_versions_header "$run_dir" "resolved tool binary (honors a config-level tool_path: override — see containers/10x/lib/10x_common.sh)"

    # 10x_common.sh sets -euo pipefail itself; _run_guarded's `set +e`
    # subshell already isolates that from the calling template.
    # shellcheck disable=SC1091
    source "$tenx_root/lib/10x_common.sh" 2>/dev/null

    local tool_path_cfg=""
    if [[ -n "$config" && -f "$config" ]]; then
        tool_path_cfg=$(yaml_get "$config" "tool_path" 2>/dev/null)
    fi

    local binary=""
    binary=$(find_10x_binary "$tool" "$tool_path_cfg" 2>/dev/null)

    if [[ -n "$binary" ]]; then
        {
            echo "$tool binary: $binary"
            printf '%s: %s\n' "$tool" "$(get_10x_version "$binary")"
        } >> "$run_dir/software_versions.txt"
    else
        printf '%s: (not captured — binary not found)\n' "$tool" >> "$run_dir/software_versions.txt"
    fi
}

# _fmt_duration <seconds>
# Renders an integer seconds count as "Xh Ym Zs"; passes through non-numeric
# input (e.g. "null") unchanged.
_fmt_duration() {
    local secs="$1"
    [[ "$secs" =~ ^[0-9]+$ ]] || { echo "$secs"; return; }
    printf '%dh %dm %ds' $((secs/3600)) $(((secs%3600)/60)) $((secs%60))
}

# _json_str <file> <key>
# Extracts a quoted string field's value from a flat manifest/env JSON file.
# No jq dependency (see bin/lib/metadata.sh) — these files are always
# single-line-per-field with no nested objects, so grep -P is sufficient
# (the same approach repro.sh already uses to parse `scontrol` output).
_json_str() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 0
    grep -oP "(?<=\"$key\": \")[^\"]*" "$file" | head -1
}

# _json_raw <file> <key>
# Same as _json_str but for unquoted values (numbers, null).
_json_raw() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 0
    grep -oP "(?<=\"$key\": )[^,}[:space:]]*" "$file" | head -1 | tr -d '"'
}

# _tool_invocations_section <trace_file> <nextflow_work_dir>
# Renders one representative resolved command per unique Nextflow process
# in this run, pulled from Nextflow's own <hash>/.command.sh (Nextflow
# always writes this per task, independent of -with-trace). Deduplicated by
# process name — a run over N samples has the same command shape per
# process, just different sample names, so showing one is complete without
# being repetitive; the full per-task breakdown remains in
# nextflow_logs/report.html and trace.txt for anyone who needs it.
_tool_invocations_section() {
    local trace_file="$1"
    local nf_work_dir="$2"

    if [[ ! -f "$trace_file" ]]; then
        echo "_No \`nextflow_logs/trace.txt\` found — the pipeline may not have reached Nextflow, or failed before any task was scheduled. See \`CONSOLE_LOG.txt\` for what ran._"
        return
    fi

    local header hash_col proc_col
    header=$(head -1 "$trace_file")
    hash_col=$(echo "$header" | tr '\t' '\n' | grep -nx 'hash' | cut -d: -f1 | head -1)
    proc_col=$(echo "$header" | tr '\t' '\n' | grep -nx 'process' | cut -d: -f1 | head -1)
    [[ -z "$proc_col" ]] && proc_col=$(echo "$header" | tr '\t' '\n' | grep -nx 'name' | cut -d: -f1 | head -1)

    if [[ -z "$hash_col" || -z "$proc_col" ]]; then
        echo "_\`trace.txt\` is present but its \`hash\`/\`process\` columns could not be located — Nextflow's trace format may have changed. Raw file: \`nextflow_logs/trace.txt\`._"
        return
    fi

    local seen=" "
    local hash proc_raw proc_name hash_prefix hash_suffix cmd_file line cand
    local -a fields
    while IFS=$'\t' read -r line; do
        IFS=$'\t' read -r -a fields <<< "$line"
        hash="${fields[$((hash_col-1))]:-}"
        proc_raw="${fields[$((proc_col-1))]:-}"
        [[ -z "$hash" || -z "$proc_raw" ]] && continue
        proc_name="${proc_raw%% (*}"

        [[ "$seen" == *" $proc_name "* ]] && continue
        seen+="$proc_name "

        hash_prefix="${hash%%/*}"
        hash_suffix="${hash#*/}"
        cmd_file=""
        for cand in "$nf_work_dir/$hash_prefix/$hash_suffix"*/.command.sh; do
            [[ -f "$cand" ]] && { cmd_file="$cand"; break; }
        done

        echo "#### \`$proc_name\`"
        echo ""
        if [[ -n "$cmd_file" ]]; then
            echo '```bash'
            grep -v '^#!' "$cmd_file" || true
            echo '```'
        else
            echo "_Work directory for this task was not found under \`nextflow_work/\` (already cleaned up, or run on a different scratch path)._"
        fi
        echo ""
    done < <(tail -n +2 "$trace_file")
}

# generate_provenance_readme <run_dir> <pipeline> <display_name> <exit_code> <container> <nextflow_work_dir>
# Assembles PROVENANCE_README.md — the single, professional, human-readable
# entry point into everything else in the run directory: what ran, with what
# parameters, using what software, and where to find the rest of the raw
# evidence. Call from the EXIT trap, after finalize_juno_env, so
# juno_environment.json is already finalized (end time, duration, exit code,
# sacct). Runs on both success and failure — a failed run's provenance is as
# valuable as a successful one.
#
# <container> is informational and rendered as-is in the summary table,
# except for two special forms:
#   - "native:<tool>" (5x 10x pipelines, no container) → relabels the row
#     "Tool" instead of "Container"
#   - any other string (multi-container virome, workflow-managed
#     wf-transcriptomes) → shown under "Container" verbatim
# <nextflow_work_dir> is optional — pass "" for non-Nextflow pipelines
# (addone, dconvatac(-gpu), sqanti3, all 10x pipelines) to skip the
# "Per-step tool invocations" subsection entirely rather than print a
# misleading "trace.txt not found" message for a pipeline that never uses
# Nextflow in the first place.
generate_provenance_readme() {
    local run_dir="$1"
    local pipeline="$2"
    local display_name="$3"
    local exit_code="$4"
    local container="$5"
    local nf_work_dir="${6:-}"
    [[ -z "$run_dir" ]] && return 0

    _run_guarded _generate_provenance_readme_body \
        "$run_dir" "$pipeline" "$display_name" "$exit_code" "$container" "$nf_work_dir"
}

_generate_provenance_readme_body() {
    local run_dir="$1"
    local pipeline="$2"
    local display_name="$3"
    local exit_code="$4"
    local container="$5"
    local nf_work_dir="$6"

    local manifest="$run_dir/manifest.json"
    local juno_env="$run_dir/juno_environment.json"
    local out="$run_dir/PROVENANCE_README.md"

    local status_line
    if [[ "$exit_code" == "0" ]]; then
        status_line="SUCCESS"
    else
        status_line="FAILED (exit code $exit_code)"
    fi

    local container_label="Container"
    local container_display="$container"
    local checksum_label="Container checksum"
    if [[ "$container" == native:* ]]; then
        container_label="Tool"
        container_display="${container#native:}"
        checksum_label="Tool version (from manifest.json)"
    fi

    local job_id node partition cpus mem start_time end_time duration sacct_state sacct_elapsed sacct_maxrss
    job_id=$(_json_str "$juno_env" "slurm_job_id")
    node=$(_json_str "$juno_env" "node_running")
    partition=$(_json_str "$juno_env" "partition")
    cpus=$(_json_str "$juno_env" "cpus_per_task")
    mem=$(_json_str "$juno_env" "mem_per_node")
    start_time=$(_json_str "$juno_env" "start_time")
    end_time=$(_json_str "$juno_env" "end_time")
    duration=$(_json_raw "$juno_env" "duration_seconds")
    sacct_state=$(_json_str "$juno_env" "sacct_state")
    sacct_elapsed=$(_json_str "$juno_env" "sacct_elapsed")
    sacct_maxrss=$(_json_str "$juno_env" "sacct_maxrss")

    local git_commit submodule_commit checksum plr_id
    git_commit=$(_json_str "$manifest" "git_commit")
    submodule_commit=$(_json_str "$manifest" "pipeline_submodule_commit")
    checksum=$(_json_str "$manifest" "container_checksum")
    plr_id=$(_json_str "$manifest" "titan_pipeline_run_id")

    local run_ts
    run_ts=$(basename "$run_dir")

    {
        echo '```'
        echo '============================================================'
        echo '            H Y P E R I O N   C O M P U T E'
        echo '------------------------------------------------------------'
        echo '  Distributed Bioinformatics Execution Framework'
        echo '  SLURM Orchestration • Pipeline Automation • HPC Scale'
        echo '============================================================'
        echo '```'
        echo ""
        echo "# Provenance Record — $display_name"
        echo ""
        echo "**Status:** $status_line &nbsp;|&nbsp; **Run:** $run_ts &nbsp;|&nbsp; **SLURM Job:** ${job_id:-unknown} &nbsp;|&nbsp; **User:** $USER"
        [[ -n "$plr_id" ]] && echo "**Titan Run ID:** $plr_id"
        echo ""
        echo "This file is generated automatically at the end of every run. It is the single entry point into everything captured about this run — see §5 for the raw artifacts it summarizes."
        echo ""
        echo "---"
        echo ""
        echo "## 1. Summary"
        echo ""
        echo "| | |"
        echo "|---|---|"
        echo "| Pipeline | \`$pipeline\` — $display_name |"
        echo "| hpc framework commit | \`${git_commit:-unknown}\` |"
        echo "| Pipeline source commit | \`${submodule_commit:-unknown}\` |"
        echo "| $container_label | \`$container_display\` |"
        echo "| $checksum_label | \`${checksum:-unknown}\` |"
        echo "| Node / Partition | \`${node:-unknown}\` / \`${partition:-unknown}\` |"
        echo "| Allocated CPUs / Mem | $cpus / $mem |"
        echo "| Start / End | $start_time / ${end_time:-unknown} |"
        echo "| Duration | $(_fmt_duration "$duration") |"
        echo "| sacct (state / elapsed / maxrss) | ${sacct_state:-pending} / ${sacct_elapsed:-pending} / ${sacct_maxrss:-pending} |"
        echo ""
        echo "---"
        echo ""
        echo "## 2. Parameters (\`config.yaml\`)"
        echo ""
        echo '```yaml'
        if [[ -f "$run_dir/config.yaml" ]]; then
            cat "$run_dir/config.yaml"
        else
            echo "# config.yaml not found in this run directory"
        fi
        echo '```'
        echo ""
        echo "---"
        echo ""
        echo "## 3. Software Versions"
        echo ""
        if [[ -f "$run_dir/software_versions.txt" ]]; then
            echo "Queried live from this run's own container/binary — see \`software_versions.txt\` for the full raw capture, including why some pipelines only cover part of the toolchain."
            echo ""
            echo "| Tool | Version |"
            echo "|---|---|"
            grep -v '^#' "$run_dir/software_versions.txt" | grep -v '^[[:space:]]*$' | while IFS=':' read -r tool ver; do
                echo "| $tool | ${ver# } |"
            done
        else
            echo "_Not captured for this run (pre-flight failed before the container/tool was confirmed, or this pipeline has not yet been wired into \`capture_software_versions\`)._"
        fi
        echo ""
        echo "---"
        echo ""
        echo "## 4. Commands Executed"
        echo ""
        echo "### Pipeline invocation"
        echo ""
        echo '```'
        if [[ -f "$run_dir/invocation.log" ]]; then
            cat "$run_dir/invocation.log"
        else
            echo "invocation.log not found — pipeline likely failed before reaching the run_logged call."
        fi
        echo '```'
        echo ""
        if [[ -n "$nf_work_dir" ]]; then
            echo "### Per-step tool invocations"
            echo ""
            echo "One representative resolved command per Nextflow process (deduplicated across samples — same command shape, different inputs). Full per-task detail, including every sample, lives in \`nextflow_logs/report.html\` and \`nextflow_logs/trace.txt\`."
            echo ""
            _tool_invocations_section "$run_dir/nextflow_logs/trace.txt" "$nf_work_dir"
        fi
        echo "---"
        echo ""
        echo "## 5. Logs & Provenance Artifacts"
        echo ""
        echo "All paths relative to this directory (\`$run_dir\`):"
        echo ""
        echo "| Artifact | What it is |"
        echo "|---|---|"
        echo "| \`manifest.json\` | Reproducibility manifest — commit SHAs, container checksum, Titan ID, input/output paths |"
        echo "| \`juno_environment.json\` | SLURM/node runtime record — node, partition, resources, timing, exit code, sacct |"
        echo "| \`invocation.log\` | Exact, fully-quoted pipeline invocation command |"
        echo "| \`software_versions.txt\` | Raw per-tool version output this report's §3 table is built from |"
        echo "| \`CONSOLE_LOG.txt\` | Full console transcript (stdout+stderr) of this run |"
        echo "| \`slurm_template_used.sh\` | Frozen copy of the SLURM template exactly as it existed at launch |"
        echo "| \`pipeline_source.tar.gz\` | Frozen copy (\`git archive\`) of the pipeline source at launch time |"
        [[ -d "$run_dir/nextflow_logs" ]] && echo "| \`nextflow_logs/\` | Nextflow's own \`trace.txt\`, \`report.html\`, \`timeline.html\`, \`dag.html\` |"
        [[ -d "$run_dir/stage_configs" ]] && echo "| \`stage_configs/\` | Per-stage SQANTI3 YAML configs generated by the orchestrator |"
        [[ -d "$run_dir/inputs" ]] && echo "| \`inputs/\` | Archived input FASTQs (rsync'd + checksum-verified from scratch) |"
        [[ -d "$run_dir/outputs" ]] && echo "| \`outputs/\` | Archived pipeline outputs (rsync'd + checksum-verified from scratch) |"
        echo ""
        echo "---"
        echo ""
        if [[ "$exit_code" == "0" ]]; then
            echo '```'
            echo '============================================================'
            echo '    Hyperion Compute — Mission Complete.'
            echo '============================================================'
            echo '```'
        else
            echo '```'
            echo '============================================================'
            echo "    Hyperion Compute — Mission Failed (exit $exit_code)."
            echo '    See CONSOLE_LOG.txt and slurm_'"${job_id:-*}"'.err for details.'
            echo '============================================================'
            echo '```'
        fi
    } > "$out"
}
