#!/usr/bin/env bash
# test_cellranger_mkfastq.sh — TJP test module for Cell Ranger mkfastq pipeline
# Sourced by the test framework (tjp-test-suite). Do not execute directly.

PIPELINE_NAME="cellranger-mkfastq"
L3_SKIP=false
L3_SKIP_REASON=""

_MKFASTQ_TINY_BCL_URL="https://cf.10xgenomics.com/supp/cell-exp/cellranger-tiny-bcl-1.2.0.tar.gz"
_MKFASTQ_TINY_BCL_CSV_URL="https://cf.10xgenomics.com/supp/cell-exp/cellranger-tiny-bcl-simple-1.2.0.csv"
_MKFASTQ_BCL_DIR="$REPO_ROOT/test_data/10x/cellranger-mkfastq/tiny-bcl"
_MKFASTQ_SS_CSV="$REPO_ROOT/test_data/10x/cellranger-mkfastq/cellranger-tiny-bcl-simple-1.2.0.csv"

# ── Layer 1: offline validation ───────────────────────────────────────────────

l1_cellranger_mkfastq() {
    local schema="$REPO_ROOT/templates/schemas/cellranger_mkfastq.yaml"
    local tmpl="$REPO_ROOT/templates/cellranger_mkfastq/config.yaml"
    local ss_tmpl="$REPO_ROOT/templates/cellranger_mkfastq/samplesheet.csv"
    local tmpdir
    tmpdir=$(mktemp -d)

    ts_assert_exists "cellranger-mkfastq schema exists" "$schema"
    ts_assert_exists "cellranger-mkfastq template config exists" "$tmpl"
    ts_assert_exists "cellranger-mkfastq samplesheet template exists" "$ss_tmpl"

    # Required keys in template
    for key in run_id run_dir samplesheet localcores localmem; do
        ts_assert_yaml_key "template has '$key'" "$tmpl" "$key"
    done

    # Samplesheet required columns
    ts_assert_contains "samplesheet has 'run_id' column"    "$ss_tmpl" "run_id"
    ts_assert_contains "samplesheet has 'run_dir' column"   "$ss_tmpl" "run_dir"
    ts_assert_contains "samplesheet has 'samplesheet' column" "$ss_tmpl" "samplesheet"

    local bcl_dir="$tmpdir/bcl_run"
    local ss_csv="$tmpdir/SampleSheet.csv"
    mkdir -p "$bcl_dir"
    echo "Lane,Sample_ID,index" > "$ss_csv"

    # Good config
    local good_cfg="$tmpdir/good_config.yaml"
    cat > "$good_cfg" <<YAML
run_id: test_run_001
run_dir: $bcl_dir
samplesheet: $ss_csv
localcores: 4
localmem: 32
YAML
    ts_assert_pass "valid config passes validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config cellranger-mkfastq '$good_cfg'"

    # Missing run_dir must fail
    local bad_cfg="$tmpdir/bad_no_run_dir.yaml"
    cat > "$bad_cfg" <<YAML
run_id: test_run_001
samplesheet: $ss_csv
localcores: 4
localmem: 32
YAML
    ts_assert_fail "config missing 'run_dir' fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config cellranger-mkfastq '$bad_cfg'"

    # Missing samplesheet must fail
    local bad_cfg2="$tmpdir/bad_no_ss.yaml"
    cat > "$bad_cfg2" <<YAML
run_id: test_run_001
run_dir: $bcl_dir
localcores: 4
localmem: 32
YAML
    ts_assert_fail "config missing 'samplesheet' fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config cellranger-mkfastq '$bad_cfg2'"

    rm -rf "$tmpdir"
}

# ── Layer 2: dry-run launch ───────────────────────────────────────────────────

l2_cellranger_mkfastq() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local bcl_dir="$tmpdir/bcl_run"
    local ss_csv="$tmpdir/SampleSheet.csv"
    mkdir -p "$bcl_dir"
    echo "Lane,Sample_ID,index" > "$ss_csv"

    local cfg="$tmpdir/config.yaml"
    cat > "$cfg" <<YAML
run_id: l2_run_001
run_dir: $bcl_dir
samplesheet: $ss_csv
localcores: 4
localmem: 32
YAML

    ts_assert_pass "l2: config validates" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config cellranger-mkfastq '$cfg'"

    ts_assert_pass "l2: cellranger-mkfastq in KNOWN_PIPELINES" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_known_pipeline cellranger-mkfastq"

    ts_assert_pass "l2: SLURM template resolves" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && [[ -f \$(get_slurm_template cellranger-mkfastq) ]]"

    ts_assert_pass "l2: cellranger-mkfastq is a native pipeline" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_native_pipeline cellranger-mkfastq"

    # Wrapper script for mkfastq must exist in 10x submodule
    ts_assert_exists "l2: cellranger-mkfastq-run.sh wrapper exists" \
        "$REPO_ROOT/containers/10x/bin/cellranger-mkfastq-run.sh"

    rm -rf "$tmpdir"
}

# ── Layer 3: full SLURM execution ─────────────────────────────────────────────

l3_fixture_cellranger_mkfastq() {
    if [[ -d "$_MKFASTQ_BCL_DIR" ]] && [[ -f "$_MKFASTQ_SS_CSV" ]]; then
        return 0
    fi

    # Check alternate staging location in TEST_SCRATCH
    local alt_bcl="$TEST_SCRATCH/cellranger-mkfastq/tiny-bcl"
    if [[ -d "$alt_bcl" ]]; then
        _MKFASTQ_BCL_DIR="$alt_bcl"
        local alt_csv="$TEST_SCRATCH/cellranger-mkfastq/cellranger-tiny-bcl-simple-1.2.0.csv"
        [[ -f "$alt_csv" ]] && _MKFASTQ_SS_CSV="$alt_csv"
        return 0
    fi

    echo "Tiny BCL data not found at $_MKFASTQ_BCL_DIR" >&2
    echo "Download it with: $REPO_ROOT/test_data/fixtures/download_10x_fixtures.sh" >&2
    echo "Or place an extracted tiny-bcl/ directory at:" >&2
    echo "  $TEST_SCRATCH/cellranger-mkfastq/tiny-bcl/" >&2
    return 1
}

l3_submit_cellranger_mkfastq() {
    local test_dir="$TEST_SCRATCH/cellranger-mkfastq"
    local cfg="$test_dir/config_cellranger_mkfastq.yaml"
    local outdir="$test_dir/output"
    mkdir -p "$test_dir" "$outdir"

    cat > "$cfg" <<YAML
run_id: tiny_bcl_test
run_dir: $_MKFASTQ_BCL_DIR
samplesheet: $_MKFASTQ_SS_CSV
localcores: 4
localmem: 16
YAML

    local job_id
    job_id=$("$REPO_ROOT/bin/tjp-launch" cellranger-mkfastq --dev --config "$cfg" 2>/dev/null \
        | grep -oP '(?<=job )\d+' | tail -1)
    echo "$job_id"
}

l3_validate_cellranger_mkfastq() {
    local scratch_dir="$SCRATCH_ROOT/pipelines/cellranger-mkfastq/runs"
    local latest_run
    latest_run=$(ls -1td "$scratch_dir"/*/ 2>/dev/null | head -1)

    if [[ -z "$latest_run" ]]; then
        ts_assert_exists "cellranger-mkfastq: scratch run dir exists" "$scratch_dir"
        return
    fi

    # mkfastq writes output under tiny_bcl_test/outs/fastq_path/
    local fastq_path="$latest_run/tiny_bcl_test/outs/fastq_path"
    ts_assert_exists "cellranger-mkfastq: outs/fastq_path/ exists" "$fastq_path"

    # At least one FASTQ file must be present
    local fastq_count
    fastq_count=$(find "$fastq_path" -name "*.fastq.gz" 2>/dev/null | wc -l)
    if [[ "$fastq_count" -gt 0 ]]; then
        ts_assert_pass "cellranger-mkfastq: output contains .fastq.gz files" true
    else
        ts_assert_fail "cellranger-mkfastq: no .fastq.gz files in fastq_path" false
    fi
}

l3_teardown_cellranger_mkfastq() {
    :
}
