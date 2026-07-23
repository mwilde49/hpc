#!/usr/bin/env bash
# provenance.sh — per-run console capture, software-version capture, and the
# human-readable PROVENANCE_README.md report.
# Sourced by SLURM templates (not tjp-launch), alongside repro.sh — depends
# on $SLURM_* env vars and on the run-directory artifacts repro.sh/manifest.sh
# already write (juno_environment.json, manifest.json, invocation.log).

# start_console_log <run_dir>
# Tees all subsequent stdout/stderr to CONSOLE_LOG.txt, in addition to
# SLURM's own slurm_<jobid>.out/.err. Call once, immediately after
# capture_juno_env/the EXIT trap are set up, so pre-flight failures are
# captured too. No-ops if run_dir is empty (template run by hand, outside
# tjp-launch).
start_console_log() {
    local run_dir="$1"
    [[ -z "$run_dir" ]] && return 0
    mkdir -p "$run_dir"
    exec > >(tee -a "$run_dir/CONSOLE_LOG.txt") 2>&1
}

# capture_software_versions <run_dir> <container> <pipeline>
# Queries the exact tool versions baked into this run's container (these
# containers do not pin tool versions at build time — see the mamba install
# blocks in containers/psoma/container/psomagen.def and
# containers/bulkrnaseq/bulkrnaseq.def — so the built .sif is the only source
# of truth). Reuses the same tool list/commands each container's own %test
# block already validates at build time. Writes a flat "Label: version"
# text file so PROVENANCE_README.md can render it without a JSON parser
# (this codebase deliberately has no jq dependency — see bin/lib/metadata.sh).
# Call after confirming the container exists, before running the pipeline,
# so even a run that fails mid-pipeline still gets a versions record.
capture_software_versions() {
    local run_dir="$1"
    local container="$2"
    local pipeline="$3"
    [[ -z "$run_dir" ]] && return 0
    mkdir -p "$run_dir"

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
        *)
            # Unwired pipeline: nothing to probe yet.
            return 0
            ;;
    esac

    {
        echo "# Software versions captured live from the container at run time."
        echo "# Container: $container"
        echo "# Captured: $(date '+%Y-%m-%dT%H:%M:%S%z')"
        echo ""
        local probe label cmd version_out
        for probe in "${probes[@]}"; do
            label="${probe%%|*}"
            cmd="${probe#*|}"
            version_out=$(apptainer exec --cleanenv "$container" bash -c "$cmd" 2>/dev/null | tr -d '\r' | head -1)
            [[ -z "$version_out" ]] && version_out="(not captured)"
            printf '%s: %s\n' "$label" "$version_out"
        done
    } > "$run_dir/software_versions.txt"
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
    local hash proc_raw proc_name hash_prefix hash_suffix cmd_file line
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
            grep -v '^#!' "$cmd_file"
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
generate_provenance_readme() {
    local run_dir="$1"
    local pipeline="$2"
    local display_name="$3"
    local exit_code="$4"
    local container="$5"
    local nf_work_dir="$6"
    [[ -z "$run_dir" ]] && return 0

    local manifest="$run_dir/manifest.json"
    local juno_env="$run_dir/juno_environment.json"
    local out="$run_dir/PROVENANCE_README.md"

    local status_line
    if [[ "$exit_code" == "0" ]]; then
        status_line="SUCCESS"
    else
        status_line="FAILED (exit code $exit_code)"
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
        echo "| Container | \`$container\` |"
        echo "| Container checksum | \`${checksum:-unknown}\` |"
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
            echo "Queried live from this run's container — these containers resolve tool versions at build time via \`mamba install\` without pinning, so the built \`.sif\` is the only authoritative source."
            echo ""
            echo "| Tool | Version |"
            echo "|---|---|"
            grep -v '^#' "$run_dir/software_versions.txt" | grep -v '^\s*$' | while IFS=':' read -r tool ver; do
                echo "| $tool | ${ver# } |"
            done
        else
            echo "_Not captured for this run (pre-flight failed before the container was confirmed, or this pipeline has not yet been wired into \`capture_software_versions\`)._"
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
        echo "### Per-step tool invocations"
        echo ""
        echo "One representative resolved command per Nextflow process (deduplicated across samples — same command shape, different inputs). Full per-task detail, including every sample, lives in \`nextflow_logs/report.html\` and \`nextflow_logs/trace.txt\`."
        echo ""
        _tool_invocations_section "$run_dir/nextflow_logs/trace.txt" "$nf_work_dir"
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
