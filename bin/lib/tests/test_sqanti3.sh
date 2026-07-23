#!/usr/bin/env bash
# test_sqanti3.sh — TJP test module for the SQANTI3 pipeline
# Sourced by the test framework (tjp-test-suite). Do not execute directly.

PIPELINE_NAME="sqanti3"
L3_SKIP=false
L3_SKIP_REASON=""

_SQ3_TEST_DATA="$REPO_ROOT/containers/sqanti3/SQANTI3/data"
_SQ3_SIF="$REPO_ROOT/containers/sqanti3/sqanti3_v5.5.4.sif"

# ── Layer 1: offline validation ───────────────────────────────────────────────

l1_sqanti3() {
    local schema="$REPO_ROOT/templates/schemas/sqanti3.yaml"
    local tmpl="$REPO_ROOT/templates/sqanti3/config.yaml"
    local ss_tmpl="$REPO_ROOT/templates/sqanti3/samplesheet.csv"
    local tmpdir
    tmpdir=$(mktemp -d)

    ts_assert_exists "sqanti3 schema exists" "$schema"
    ts_assert_exists "sqanti3 template config exists" "$tmpl"
    ts_assert_exists "sqanti3 samplesheet template exists" "$ss_tmpl"

    # Required keys in template
    for key in sample isoforms refGTF refFasta outdir; do
        ts_assert_yaml_key "template has '$key'" "$tmpl" "$key"
    done

    # Samplesheet required columns
    ts_assert_contains "samplesheet has 'sample' column"   "$ss_tmpl" "sample"
    ts_assert_contains "samplesheet has 'isoforms' column" "$ss_tmpl" "isoforms"
    ts_assert_contains "samplesheet has 'ref_gtf' column"  "$ss_tmpl" "ref_gtf"
    ts_assert_contains "samplesheet has 'ref_fasta' column" "$ss_tmpl" "ref_fasta"

    # Create stub files so path-existence checks pass
    local isoforms="$tmpdir/isoforms.gtf"
    local refGTF="$tmpdir/refGTF.gtf"
    local refFasta="$tmpdir/refFasta.fa"
    touch "$isoforms" "$refGTF" "$refFasta"

    # Good config
    local good_cfg="$tmpdir/good_config.yaml"
    cat > "$good_cfg" <<YAML
sample: test_sample
isoforms: $isoforms
refGTF: $refGTF
refFasta: $refFasta
outdir: /tmp/sqanti3_test
cpus: 4
chunks: 1
skip_report: true
skip_orf: false
filter_mode: rules
filter_mono_exonic: false
rescue_mode: automatic
YAML
    ts_assert_pass "valid config passes validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config sqanti3 '$good_cfg'"

    # Missing isoforms must fail
    local bad_cfg="$tmpdir/bad_no_isoforms.yaml"
    cat > "$bad_cfg" <<YAML
sample: test_sample
refGTF: $refGTF
refFasta: $refFasta
outdir: /tmp/sqanti3_test
YAML
    ts_assert_fail "config missing 'isoforms' fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config sqanti3 '$bad_cfg'"

    # Invalid filter_mode must fail
    local bad_cfg2="$tmpdir/bad_filter_mode.yaml"
    cat > "$bad_cfg2" <<YAML
sample: test_sample
isoforms: $isoforms
refGTF: $refGTF
refFasta: $refFasta
outdir: /tmp/sqanti3_test
filter_mode: heuristic
YAML
    ts_assert_fail "config with invalid filter_mode fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config sqanti3 '$bad_cfg2'"

    # Invalid rescue_mode must fail
    local bad_cfg3="$tmpdir/bad_rescue_mode.yaml"
    cat > "$bad_cfg3" <<YAML
sample: test_sample
isoforms: $isoforms
refGTF: $refGTF
refFasta: $refFasta
outdir: /tmp/sqanti3_test
rescue_mode: aggressive
YAML
    ts_assert_fail "config with invalid rescue_mode fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config sqanti3 '$bad_cfg3'"

    # Reproducibility manifest: source-snapshotting must resolve the
    # longreads (sqanti3) submodule commit SHA. Runs fully offline, no SLURM needed.
    local mtmp
    mtmp=$(mktemp -d)
    echo "sample: test" > "$mtmp/config.yaml"
    (
        source "$REPO_ROOT/bin/lib/common.sh"
        source "$REPO_ROOT/bin/lib/manifest.sh"
        generate_manifest "$mtmp" sqanti3 "$mtmp/config.yaml" \
            "$REPO_ROOT/containers/sqanti3/sqanti3_v5.5.4.sif" \
            "$REPO_ROOT/slurm_templates/sqanti3_slurm_template.sh"
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

l2_sqanti3() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local isoforms="$tmpdir/isoforms.gtf"
    local refGTF="$tmpdir/refGTF.gtf"
    local refFasta="$tmpdir/refFasta.fa"
    touch "$isoforms" "$refGTF" "$refFasta"

    local cfg="$tmpdir/config.yaml"
    cat > "$cfg" <<YAML
sample: sqanti3_l2_test
isoforms: $isoforms
refGTF: $refGTF
refFasta: $refFasta
outdir: $TEST_SCRATCH/sqanti3/l2_output
cpus: 4
chunks: 1
skip_report: true
filter_mode: rules
rescue_mode: automatic
YAML

    ts_assert_pass "l2: config validates" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config sqanti3 '$cfg'"

    ts_assert_pass "l2: sqanti3 in KNOWN_PIPELINES" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_known_pipeline sqanti3"

    ts_assert_pass "l2: SLURM template resolves" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && [[ -f \$(get_slurm_template sqanti3) ]]"

    ts_assert_fail "l2: sqanti3 is not a native pipeline" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_native_pipeline sqanti3"

    # SQANTI3 orchestrator template must exist
    ts_assert_exists "l2: sqanti3 SLURM orchestrator exists" \
        "$REPO_ROOT/slurm_templates/sqanti3_slurm_template.sh"

    # Stage scripts directory must exist in submodule
    ts_assert_exists "l2: sqanti3 stage scripts dir exists" \
        "$REPO_ROOT/containers/sqanti3/slurm_templates"

    # Reproducibility logging: repro.sh sources cleanly and is wired into
    # the orchestrator template (node/partition capture + logged sbatch calls
    # for all 4 DAG stages). Per-stage node capture is out of scope here —
    # those stage scripts live in the containers/sqanti3 submodule.
    ts_assert_pass "l2: repro.sh sources cleanly" \
        bash -c "source '$REPO_ROOT/bin/lib/repro.sh'"
    ts_assert_contains "l2: sqanti3 orchestrator sources repro.sh" \
        "$REPO_ROOT/slurm_templates/sqanti3_slurm_template.sh" "repro.sh"

    # Provenance README: provenance.sh sources cleanly and is wired into the
    # orchestrator template
    ts_assert_pass "l2: provenance.sh sources cleanly" \
        bash -c "source '$REPO_ROOT/bin/lib/repro.sh' && source '$REPO_ROOT/bin/lib/provenance.sh'"
    ts_assert_pass "l2: provenance.sh defines its hooks" \
        bash -c "source '$REPO_ROOT/bin/lib/repro.sh' && source '$REPO_ROOT/bin/lib/provenance.sh' && declare -f start_console_log capture_software_versions generate_provenance_readme >/dev/null"
    ts_assert_contains "l2: sqanti3 orchestrator sources provenance.sh" \
        "$REPO_ROOT/slurm_templates/sqanti3_slurm_template.sh" "provenance.sh"
    ts_assert_contains "l2: sqanti3 orchestrator captures software versions" \
        "$REPO_ROOT/slurm_templates/sqanti3_slurm_template.sh" "capture_software_versions"
    ts_assert_contains "l2: sqanti3 orchestrator generates provenance README on exit" \
        "$REPO_ROOT/slurm_templates/sqanti3_slurm_template.sh" "generate_provenance_readme"
    ts_assert_contains "l2: sqanti3 orchestrator wraps sbatch calls with run_logged" \
        "$REPO_ROOT/slurm_templates/sqanti3_slurm_template.sh" "run_logged"

    rm -rf "$tmpdir"
}

# ── Layer 3: full SLURM execution ─────────────────────────────────────────────

l3_fixture_sqanti3() {
    if [[ ! -d "$_SQ3_TEST_DATA" ]]; then
        echo "SQANTI3 test data not found: $_SQ3_TEST_DATA" >&2
        echo "Ensure the sqanti3 submodule is checked out:" >&2
        echo "  git submodule update --init containers/sqanti3" >&2
        return 1
    fi

    if [[ ! -f "$_SQ3_TEST_DATA/UHR_chr22.gtf" ]]; then
        echo "UHR_chr22.gtf not found in SQANTI3 test data: $_SQ3_TEST_DATA" >&2
        echo "The test data must be staged — see containers/sqanti3/SQANTI3/data/README" >&2
        return 1
    fi

    if [[ ! -f "$_SQ3_SIF" ]]; then
        echo "SQANTI3 container SIF not found: $_SQ3_SIF" >&2
        echo "Pull it with:" >&2
        echo "  apptainer pull $_SQ3_SIF docker://anaconesalab/sqanti3:v5.5.4" >&2
        return 1
    fi

    return 0
}

l3_submit_sqanti3() {
    local test_dir="$TEST_SCRATCH/sqanti3"
    local outdir="$test_dir/results_${TEST_TS}"
    local cfg="$test_dir/config_sqanti3.yaml"
    mkdir -p "$test_dir"

    cat > "$cfg" <<YAML
sample: UHR_chr22_test
isoforms: ${_SQ3_TEST_DATA}/UHR_chr22.gtf
refGTF:   ${_SQ3_TEST_DATA}/reference/gencode.v38.basic_chr22.gtf
refFasta: ${_SQ3_TEST_DATA}/reference/GRCh38.p13_chr22.fasta
coverage: ""
fl_count: ${_SQ3_TEST_DATA}/UHR_abundance.tsv
CAGE_peak:        ${_SQ3_TEST_DATA}/ref_TSS_annotation/human.refTSS_v3.1.hg38.bed
polyA_motif_list: ${_SQ3_TEST_DATA}/polyA_motifs/mouse_and_human.polyA_motif.txt
polyA_peak: ""
force_id_ignore: false
cpus:   4
chunks: 1
skip_report: true
skip_orf: false
filter_mode: rules
filter_mono_exonic: false
rescue_mode: automatic
outdir: $outdir
YAML

    local job_id
    job_id=$("$REPO_ROOT/bin/tjp-launch" sqanti3 --dev --config "$cfg" 2>/dev/null \
        | grep -oP '(?<=job )\d+' | tail -1)
    echo "$job_id"
}

l3_validate_sqanti3() {
    local test_dir="$TEST_SCRATCH/sqanti3"

    # Find the most recent results directory
    local outdir
    outdir=$(ls -1td "$test_dir"/results_*/ 2>/dev/null | head -1)

    if [[ -z "$outdir" ]]; then
        ts_assert_exists "sqanti3: results directory exists under test scratch" "$test_dir"
        return
    fi

    ts_assert_exists "sqanti3: qc/ stage output"     "$outdir/qc"
    ts_assert_exists "sqanti3: filter/ stage output" "$outdir/filter"

    # Reproducibility artifacts live in the WORK run dir ($RUN_DIR) and cover
    # only the lightweight orchestrator job — not the 4 stage sub-jobs it submits.
    local work_run
    work_run=$(ls -1td "$WORK_ROOT/pipelines/sqanti3/runs"/*/ 2>/dev/null | head -1)

    if [[ -z "$work_run" ]]; then
        ts_assert_exists "sqanti3: WORK run directory exists" "$WORK_ROOT/pipelines/sqanti3/runs"
        return
    fi

    ts_assert_exists   "sqanti3: juno_environment.json"     "$work_run/juno_environment.json"
    ts_assert_exists   "sqanti3: slurm_template_used.sh"    "$work_run/slurm_template_used.sh"
    ts_assert_nonempty "sqanti3: pipeline_source.tar.gz"    "$work_run/pipeline_source.tar.gz"
    ts_assert_nonempty "sqanti3: invocation.log"            "$work_run/invocation.log"
    ts_assert_contains "sqanti3: invocation.log records all 4 stage submissions" \
                       "$work_run/invocation.log" "sqanti3_rescue_slurm_template.sh"
    ts_assert_fail     "sqanti3: juno_environment.json end_time populated" \
                       bash -c "grep -q '\"end_time\": null' '$work_run/juno_environment.json'"

    # Provenance README artifacts (orchestrator level only — see the note in
    # the SLURM template about why per-stage detail is out of scope)
    ts_assert_exists   "sqanti3: CONSOLE_LOG.txt"            "$work_run/CONSOLE_LOG.txt"
    ts_assert_nonempty "sqanti3: CONSOLE_LOG.txt"            "$work_run/CONSOLE_LOG.txt"
    ts_assert_exists   "sqanti3: software_versions.txt"      "$work_run/software_versions.txt"
    ts_assert_contains "sqanti3: software_versions.txt has SQANTI3 entry" \
                       "$work_run/software_versions.txt" "SQANTI3:"
    ts_assert_exists   "sqanti3: PROVENANCE_README.md"       "$work_run/PROVENANCE_README.md"
    ts_assert_nonempty "sqanti3: PROVENANCE_README.md"       "$work_run/PROVENANCE_README.md"
    ts_assert_contains "sqanti3: PROVENANCE_README.md has Hyperion banner" \
                       "$work_run/PROVENANCE_README.md" "H Y P E R I O N"
}

l3_teardown_sqanti3() {
    :
}
