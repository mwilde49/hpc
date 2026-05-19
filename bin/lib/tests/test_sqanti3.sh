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
}

l3_teardown_sqanti3() {
    :
}
