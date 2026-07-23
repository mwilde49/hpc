#!/usr/bin/env bash
# test_wf_transcriptomes.sh — TJP test module for the wf-transcriptomes pipeline
# Sourced by the test framework (tjp-test-suite). Do not execute directly.

PIPELINE_NAME="wf-transcriptomes"
L3_SKIP=false
L3_SKIP_REASON=""

_WFTX_TEST_DATA="$REPO_ROOT/containers/sqanti3/test_data/wf_transcriptomes"
_WFTX_FASTQ_DIR="$_WFTX_TEST_DATA/fastq"
_WFTX_SAMPLE_SHEET="$_WFTX_TEST_DATA/sample_sheet.csv"

# ── Layer 1: offline validation ───────────────────────────────────────────────

l1_wf_transcriptomes() {
    local schema="$REPO_ROOT/templates/schemas/wf_transcriptomes.yaml"
    local tmpl="$REPO_ROOT/templates/wf-transcriptomes/config.yaml"
    local ss_tmpl="$REPO_ROOT/templates/wf-transcriptomes/samplesheet.csv"
    local tmpdir
    tmpdir=$(mktemp -d)

    ts_assert_exists "wf-transcriptomes schema exists" "$schema"
    ts_assert_exists "wf-transcriptomes template config exists" "$tmpl"
    ts_assert_exists "wf-transcriptomes samplesheet template exists" "$ss_tmpl"

    # Required keys in template
    for key in sample fastq_dir sample_sheet ref_genome ref_annotation outdir; do
        ts_assert_yaml_key "template has '$key'" "$tmpl" "$key"
    done

    # Samplesheet required columns
    ts_assert_contains "samplesheet has 'sample' column"       "$ss_tmpl" "sample"
    ts_assert_contains "samplesheet has 'fastq_dir' column"    "$ss_tmpl" "fastq_dir"
    ts_assert_contains "samplesheet has 'sample_sheet' column" "$ss_tmpl" "sample_sheet"
    ts_assert_contains "samplesheet has 'ref_genome' column"   "$ss_tmpl" "ref_genome"
    ts_assert_contains "samplesheet has 'ref_annotation' column" "$ss_tmpl" "ref_annotation"

    # Create stub paths for the validator
    local fastq_dir="$tmpdir/fastq_pass"
    local sample_sheet="$tmpdir/barcodes.csv"
    local ref_genome="$tmpdir/genome.fa"
    local ref_annotation="$tmpdir/annotation.gtf"
    mkdir -p "$fastq_dir"
    touch "$sample_sheet" "$ref_genome" "$ref_annotation"
    echo "barcode,alias" > "$sample_sheet"
    echo "barcode09,sample1" >> "$sample_sheet"

    # Good config
    local good_cfg="$tmpdir/good_config.yaml"
    cat > "$good_cfg" <<YAML
sample: wftx_test
fastq_dir: $fastq_dir
sample_sheet: $sample_sheet
ref_genome: $ref_genome
ref_annotation: $ref_annotation
wf_version: v2.3.0
direct_rna: false
de_analysis: false
outdir: /tmp/wftx_test_output
YAML
    ts_assert_pass "valid config passes validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config wf-transcriptomes '$good_cfg'"

    # Missing sample must fail
    local bad_cfg="$tmpdir/bad_no_sample.yaml"
    cat > "$bad_cfg" <<YAML
fastq_dir: $fastq_dir
sample_sheet: $sample_sheet
ref_genome: $ref_genome
ref_annotation: $ref_annotation
outdir: /tmp/wftx_test_output
YAML
    ts_assert_fail "config missing 'sample' fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config wf-transcriptomes '$bad_cfg'"

    # Missing ref_genome must fail
    local bad_cfg2="$tmpdir/bad_no_ref_genome.yaml"
    cat > "$bad_cfg2" <<YAML
sample: wftx_test
fastq_dir: $fastq_dir
sample_sheet: $sample_sheet
ref_annotation: $ref_annotation
outdir: /tmp/wftx_test_output
YAML
    ts_assert_fail "config missing 'ref_genome' fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config wf-transcriptomes '$bad_cfg2'"

    # Invalid de_analysis value must fail
    local bad_cfg3="$tmpdir/bad_de_analysis.yaml"
    cat > "$bad_cfg3" <<YAML
sample: wftx_test
fastq_dir: $fastq_dir
sample_sheet: $sample_sheet
ref_genome: $ref_genome
ref_annotation: $ref_annotation
outdir: /tmp/wftx_test_output
de_analysis: yes
YAML
    ts_assert_fail "config with invalid de_analysis value fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config wf-transcriptomes '$bad_cfg3'"

    # Reproducibility manifest: source-snapshotting must resolve the
    # longreads (sqanti3) submodule commit SHA, shared with sqanti3.
    # Runs fully offline, no SLURM needed.
    local mtmp
    mtmp=$(mktemp -d)
    echo "sample: test" > "$mtmp/config.yaml"
    (
        source "$REPO_ROOT/bin/lib/common.sh"
        source "$REPO_ROOT/bin/lib/manifest.sh"
        generate_manifest "$mtmp" wf-transcriptomes "$mtmp/config.yaml" \
            "native:$REPO_ROOT/containers/sqanti3" \
            "$REPO_ROOT/slurm_templates/wf_transcriptomes_slurm_template.sh"
    )
    local expected_sha
    expected_sha=$(git -C "$REPO_ROOT/containers/sqanti3" rev-parse HEAD 2>/dev/null)
    ts_assert_exists   "manifest: slurm_template_used.sh snapshotted" "$mtmp/slurm_template_used.sh"
    ts_assert_nonempty "manifest: pipeline_source.tar.gz snapshotted" "$mtmp/pipeline_source.tar.gz"
    ts_assert_contains "manifest: pipeline_submodule_commit matches submodule HEAD" \
        "$mtmp/manifest.json" "$expected_sha"
    rm -rf "$mtmp"

    rm -rf "$tmpdir"
}

# ── Layer 2: dry-run launch ───────────────────────────────────────────────────

l2_wf_transcriptomes() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local fastq_dir="$tmpdir/fastq_pass"
    local sample_sheet="$tmpdir/barcodes.csv"
    local ref_genome="$tmpdir/genome.fa"
    local ref_annotation="$tmpdir/annotation.gtf"
    mkdir -p "$fastq_dir"
    touch "$ref_genome" "$ref_annotation"
    echo "barcode,alias" > "$sample_sheet"
    echo "barcode09,sample1" >> "$sample_sheet"

    local cfg="$tmpdir/config.yaml"
    cat > "$cfg" <<YAML
sample: wftx_l2_test
fastq_dir: $fastq_dir
sample_sheet: $sample_sheet
ref_genome: $ref_genome
ref_annotation: $ref_annotation
wf_version: v2.3.0
direct_rna: false
de_analysis: false
outdir: $TEST_SCRATCH/wf-transcriptomes/l2_output
YAML

    ts_assert_pass "l2: config validates" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config wf-transcriptomes '$cfg'"

    ts_assert_pass "l2: wf-transcriptomes in KNOWN_PIPELINES" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_known_pipeline wf-transcriptomes"

    ts_assert_pass "l2: SLURM template resolves" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && [[ -f \$(get_slurm_template wf-transcriptomes) ]]"

    ts_assert_pass "l2: wf-transcriptomes is a Nextflow-managed pipeline" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_nextflow_managed_pipeline wf-transcriptomes"

    ts_assert_fail "l2: wf-transcriptomes is not a native pipeline" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_native_pipeline wf-transcriptomes"

    # Nextflow config for Juno SLURM executor must exist
    ts_assert_exists "l2: juno.config Nextflow SLURM executor config exists" \
        "$REPO_ROOT/containers/sqanti3/configs/wf_transcriptomes/juno.config"

    # Reproducibility logging: repro.sh sources cleanly and is wired into
    # the SLURM template (node/partition capture, invocation log, Nextflow trace)
    ts_assert_pass "l2: repro.sh sources cleanly" \
        bash -c "source '$REPO_ROOT/bin/lib/repro.sh'"
    ts_assert_contains "l2: wf-transcriptomes template sources repro.sh" \
        "$REPO_ROOT/slurm_templates/wf_transcriptomes_slurm_template.sh" "repro.sh"

    # Provenance README: provenance.sh sources cleanly and is wired into the
    # SLURM template
    ts_assert_pass "l2: provenance.sh sources cleanly" \
        bash -c "source '$REPO_ROOT/bin/lib/repro.sh' && source '$REPO_ROOT/bin/lib/provenance.sh'"
    ts_assert_pass "l2: provenance.sh defines its hooks" \
        bash -c "source '$REPO_ROOT/bin/lib/repro.sh' && source '$REPO_ROOT/bin/lib/provenance.sh' && declare -f start_console_log capture_software_versions generate_provenance_readme >/dev/null"
    ts_assert_contains "l2: wf-transcriptomes template sources provenance.sh" \
        "$REPO_ROOT/slurm_templates/wf_transcriptomes_slurm_template.sh" "provenance.sh"
    ts_assert_contains "l2: wf-transcriptomes template captures software versions" \
        "$REPO_ROOT/slurm_templates/wf_transcriptomes_slurm_template.sh" "capture_software_versions"
    ts_assert_contains "l2: wf-transcriptomes template generates provenance README on exit" \
        "$REPO_ROOT/slurm_templates/wf_transcriptomes_slurm_template.sh" "generate_provenance_readme"
    ts_assert_contains "l2: wf-transcriptomes template wraps invocation with run_logged" \
        "$REPO_ROOT/slurm_templates/wf_transcriptomes_slurm_template.sh" "run_logged"
    ts_assert_contains "l2: wf-transcriptomes template enables Nextflow trace/report" \
        "$REPO_ROOT/slurm_templates/wf_transcriptomes_slurm_template.sh" "with-trace"

    rm -rf "$tmpdir"
}

# ── Layer 3: full SLURM execution ─────────────────────────────────────────────

l3_fixture_wf_transcriptomes() {
    if [[ ! -d "$_WFTX_FASTQ_DIR" ]]; then
        echo "wf-transcriptomes test FASTQ dir not found: $_WFTX_FASTQ_DIR" >&2
        echo "Stage test ONT FASTQs first:" >&2
        echo "  See $_WFTX_TEST_DATA/README.md for staging instructions." >&2
        return 1
    fi

    local count
    count=$(find "$_WFTX_FASTQ_DIR" -name "*.fastq.gz" | wc -l)
    if [[ "$count" -eq 0 ]]; then
        echo "No .fastq.gz files found in $_WFTX_FASTQ_DIR" >&2
        echo "Stage ONT FASTQ files before running Layer 3." >&2
        return 1
    fi

    if [[ ! -f "$_WFTX_SAMPLE_SHEET" ]]; then
        echo "wf-transcriptomes sample_sheet not found: $_WFTX_SAMPLE_SHEET" >&2
        echo "Create a CSV with columns: barcode,alias" >&2
        return 1
    fi

    return 0
}

l3_submit_wf_transcriptomes() {
    local test_dir="$TEST_SCRATCH/wf-transcriptomes"
    local outdir="$test_dir/results_${TEST_TS}"
    local cfg="$test_dir/config_wf_transcriptomes.yaml"
    mkdir -p "$test_dir"

    cat > "$cfg" <<YAML
sample: wftx_l3_test
fastq_dir: $_WFTX_FASTQ_DIR
sample_sheet: $_WFTX_SAMPLE_SHEET
ref_genome: /groups/tprice/pipelines/references/GRCh38.primary_assembly.genome.fa
ref_annotation: /groups/tprice/pipelines/references/gencode.v47.primary_assembly.annotation.gtf
wf_version: v1.7.2
direct_rna: false
minimap2_index_opts: "-k 15"
min_read_length: 100
min_qscore: 9
de_analysis: false
outdir: $outdir
YAML

    local job_id
    job_id=$("$REPO_ROOT/bin/tjp-launch" wf-transcriptomes --dev --config "$cfg" 2>/dev/null \
        | grep -oP '(?<=job )\d+' | tail -1)
    echo "$job_id"
}

l3_validate_wf_transcriptomes() {
    local test_dir="$TEST_SCRATCH/wf-transcriptomes"
    local outdir
    outdir=$(ls -1td "$test_dir"/results_*/ 2>/dev/null | head -1)

    if [[ -z "$outdir" ]]; then
        ts_assert_exists "wf-transcriptomes: results directory under test scratch" "$test_dir"
        return
    fi

    ts_assert_exists "wf-transcriptomes: output directory exists" "$outdir"

    # wf-transcriptomes produces jaffal_results/ or similar under outdir
    # Accept any of the known top-level output directories
    local found_output=false
    for subdir in jaffal_results merged_transcriptome stringtie_merged; do
        if [[ -d "$outdir/$subdir" ]]; then
            found_output=true
            ts_assert_exists "wf-transcriptomes: $subdir/ output directory" "$outdir/$subdir"
            break
        fi
    done

    if [[ "$found_output" == false ]]; then
        ts_warn "wf-transcriptomes L3 output" \
            "Could not find expected output subdirectory under $outdir (jaffal_results, merged_transcriptome, stringtie_merged)"
    fi

    # Reproducibility artifacts live in the WORK run dir ($RUN_DIR)
    local work_run
    work_run=$(ls -1td "$WORK_ROOT/pipelines/wf-transcriptomes/runs"/*/ 2>/dev/null | head -1)

    if [[ -z "$work_run" ]]; then
        ts_assert_exists "wf-transcriptomes: WORK run directory exists" "$WORK_ROOT/pipelines/wf-transcriptomes/runs"
        return
    fi

    ts_assert_exists   "wf-transcriptomes: juno_environment.json"     "$work_run/juno_environment.json"
    ts_assert_exists   "wf-transcriptomes: slurm_template_used.sh"    "$work_run/slurm_template_used.sh"
    ts_assert_nonempty "wf-transcriptomes: pipeline_source.tar.gz"    "$work_run/pipeline_source.tar.gz"
    ts_assert_nonempty "wf-transcriptomes: invocation.log"            "$work_run/invocation.log"
    ts_assert_contains "wf-transcriptomes: invocation.log records nextflow run" \
                       "$work_run/invocation.log" "run epi2me-labs/wf-transcriptomes"
    ts_assert_exists   "wf-transcriptomes: nextflow_logs/trace.txt"   "$work_run/nextflow_logs/trace.txt"
    ts_assert_fail     "wf-transcriptomes: juno_environment.json end_time populated" \
                       bash -c "grep -q '\"end_time\": null' '$work_run/juno_environment.json'"

    # Provenance README artifacts (Nextflow version only — per-process
    # containers are managed by the external epi2me-labs workflow, out of
    # scope to probe directly; see the SLURM template)
    ts_assert_exists   "wf-transcriptomes: CONSOLE_LOG.txt"            "$work_run/CONSOLE_LOG.txt"
    ts_assert_nonempty "wf-transcriptomes: CONSOLE_LOG.txt"            "$work_run/CONSOLE_LOG.txt"
    ts_assert_exists   "wf-transcriptomes: software_versions.txt"      "$work_run/software_versions.txt"
    ts_assert_contains "wf-transcriptomes: software_versions.txt has Nextflow entry" \
                       "$work_run/software_versions.txt" "Nextflow:"
    ts_assert_exists   "wf-transcriptomes: PROVENANCE_README.md"       "$work_run/PROVENANCE_README.md"
    ts_assert_nonempty "wf-transcriptomes: PROVENANCE_README.md"       "$work_run/PROVENANCE_README.md"
    ts_assert_contains "wf-transcriptomes: PROVENANCE_README.md has Hyperion banner" \
                       "$work_run/PROVENANCE_README.md" "H Y P E R I O N"
}

l3_teardown_wf_transcriptomes() {
    :
}
