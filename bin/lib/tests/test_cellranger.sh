#!/usr/bin/env bash
# test_cellranger.sh — TJP test module for the Cell Ranger (count) pipeline
# Sourced by the test framework (tjp-test-suite). Do not execute directly.

PIPELINE_NAME="cellranger"
L3_SKIP=false
L3_SKIP_REASON=""

# Tiny test data bundled with Cell Ranger install
_CR_TOOL_PATH=""          # populated in l3_fixture_cellranger
_CR_TINY_FASTQ=""
_CR_TINY_REF=""
_CR_TINY_SAMPLE="bamtofastq"   # sample name inside tiny_fastq

# ── Layer 1: offline validation ───────────────────────────────────────────────

l1_cellranger() {
    local schema="$REPO_ROOT/templates/schemas/cellranger.yaml"
    local tmpl="$REPO_ROOT/templates/cellranger/config.yaml"
    local ss_tmpl="$REPO_ROOT/templates/cellranger/samplesheet.csv"
    local tmpdir
    tmpdir=$(mktemp -d)

    ts_assert_exists "cellranger schema exists" "$schema"
    ts_assert_exists "cellranger template config exists" "$tmpl"
    ts_assert_exists "cellranger samplesheet template exists" "$ss_tmpl"

    # Required keys in template
    for key in sample_id sample_name fastq_dir transcriptome localcores localmem create_bam; do
        ts_assert_yaml_key "template has '$key'" "$tmpl" "$key"
    done

    # Samplesheet template has required columns
    ts_assert_contains "samplesheet has 'sample' column"       "$ss_tmpl" "sample"
    ts_assert_contains "samplesheet has 'fastqs' column"       "$ss_tmpl" "fastqs"
    ts_assert_contains "samplesheet has 'transcriptome' column" "$ss_tmpl" "transcriptome"

    local fastq_dir="$tmpdir/fastq"
    local txome="$tmpdir/transcriptome"
    mkdir -p "$fastq_dir" "$txome"

    # Good config
    local good_cfg="$tmpdir/good_config.yaml"
    cat > "$good_cfg" <<YAML
sample_id: test_sample
sample_name: TestSample
fastq_dir: $fastq_dir
transcriptome: $txome
localcores: 4
localmem: 32
create_bam: true
YAML
    ts_assert_pass "valid config passes validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config cellranger '$good_cfg'"

    # Missing sample_id must fail
    local bad_cfg="$tmpdir/bad_no_sample_id.yaml"
    cat > "$bad_cfg" <<YAML
sample_name: TestSample
fastq_dir: $fastq_dir
transcriptome: $txome
localcores: 4
localmem: 32
create_bam: true
YAML
    ts_assert_fail "config missing 'sample_id' fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config cellranger '$bad_cfg'"

    # Missing create_bam must fail (required in CR 10+)
    local bad_cfg2="$tmpdir/bad_no_create_bam.yaml"
    cat > "$bad_cfg2" <<YAML
sample_id: test_sample
sample_name: TestSample
fastq_dir: $fastq_dir
transcriptome: $txome
localcores: 4
localmem: 32
YAML
    ts_assert_fail "config missing 'create_bam' fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config cellranger '$bad_cfg2'"

    # Non-integer localcores must fail
    local bad_cfg3="$tmpdir/bad_localcores.yaml"
    cat > "$bad_cfg3" <<YAML
sample_id: test_sample
sample_name: TestSample
fastq_dir: $fastq_dir
transcriptome: $txome
localcores: sixteen
localmem: 32
create_bam: true
YAML
    ts_assert_fail "config with non-integer localcores fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config cellranger '$bad_cfg3'"

    rm -rf "$tmpdir"
}

# ── Layer 2: dry-run launch ───────────────────────────────────────────────────

l2_cellranger() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local fastq_dir="$tmpdir/fastq"
    local txome="$tmpdir/transcriptome"
    mkdir -p "$fastq_dir" "$txome"

    local cfg="$tmpdir/config.yaml"
    cat > "$cfg" <<YAML
sample_id: l2_test
sample_name: L2TestSample
fastq_dir: $fastq_dir
transcriptome: $txome
localcores: 4
localmem: 32
create_bam: true
YAML

    ts_assert_pass "l2: config validates" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config cellranger '$cfg'"

    ts_assert_pass "l2: cellranger in KNOWN_PIPELINES" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_known_pipeline cellranger"

    ts_assert_pass "l2: SLURM template resolves" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && [[ -f \$(get_slurm_template cellranger) ]]"

    ts_assert_pass "l2: cellranger is a native pipeline" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_native_pipeline cellranger"

    ts_assert_pass "l2: get_tool_path returns non-empty for cellranger" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && [[ -n \$(get_tool_path cellranger) ]]"

    # 10x submodule wrapper script must exist
    ts_assert_exists "l2: cellranger-run.sh wrapper exists" \
        "$REPO_ROOT/containers/10x/bin/cellranger-run.sh"

    rm -rf "$tmpdir"
}

# ── Layer 3: full SLURM execution ─────────────────────────────────────────────

l3_fixture_cellranger() {
    _CR_TOOL_PATH=$(bash -c "source '$REPO_ROOT/bin/lib/common.sh' && get_tool_path cellranger")

    if [[ -z "$_CR_TOOL_PATH" || ! -d "$_CR_TOOL_PATH" ]]; then
        echo "Cell Ranger tool not found at: $_CR_TOOL_PATH" >&2
        echo "Install Cell Ranger to /groups/tprice/opt/cellranger-10.0.0" >&2
        return 1
    fi

    _CR_TINY_FASTQ="$_CR_TOOL_PATH/external/cellranger_tiny_fastq"
    _CR_TINY_REF="$_CR_TOOL_PATH/external/cellranger_tiny_ref"

    if [[ ! -d "$_CR_TINY_FASTQ" ]]; then
        echo "cellranger_tiny_fastq not found: $_CR_TINY_FASTQ" >&2
        echo "This ships with Cell Ranger — ensure the install is intact." >&2
        return 1
    fi

    if [[ ! -d "$_CR_TINY_REF" ]]; then
        echo "cellranger_tiny_ref not found: $_CR_TINY_REF" >&2
        echo "This ships with Cell Ranger — ensure the install is intact." >&2
        return 1
    fi

    # Detect sample name from tiny_fastq directory
    local detected
    detected=$(find "$_CR_TINY_FASTQ" -name "*_R1_*" -printf '%f\n' 2>/dev/null \
        | sed 's/_S[0-9]*_L[0-9]*_R1.*//' | sort -u | head -1)
    [[ -n "$detected" ]] && _CR_TINY_SAMPLE="$detected"

    return 0
}

l3_submit_cellranger() {
    # Refresh tool path variables in case fixture ran in a subshell
    _CR_TOOL_PATH=$(bash -c "source '$REPO_ROOT/bin/lib/common.sh' && get_tool_path cellranger")
    _CR_TINY_FASTQ="$_CR_TOOL_PATH/external/cellranger_tiny_fastq"
    _CR_TINY_REF="$_CR_TOOL_PATH/external/cellranger_tiny_ref"

    local test_dir="$TEST_SCRATCH/cellranger"
    local cfg="$test_dir/config_cellranger.yaml"
    mkdir -p "$test_dir"

    cat > "$cfg" <<YAML
sample_id: cellranger_tiny_test
sample_name: $_CR_TINY_SAMPLE
fastq_dir: $_CR_TINY_FASTQ
transcriptome: $_CR_TINY_REF
localcores: 4
localmem: 16
create_bam: true
YAML

    local job_id
    job_id=$("$REPO_ROOT/bin/tjp-launch" cellranger --dev --config "$cfg" 2>/dev/null \
        | grep -oP '(?<=job )\d+' | tail -1)
    echo "$job_id"
}

l3_validate_cellranger() {
    local scratch_dir="$SCRATCH_ROOT/pipelines/cellranger/runs"
    local latest_run
    latest_run=$(ls -1td "$scratch_dir"/*/ 2>/dev/null | head -1)

    if [[ -z "$latest_run" ]]; then
        ts_assert_exists "cellranger: scratch run dir exists" "$scratch_dir"
        return
    fi

    local outs="$latest_run/cellranger_tiny_test/outs"
    ts_assert_exists "cellranger: sample outs/ directory"         "$outs"
    ts_assert_exists "cellranger: web_summary.html"               "$outs/web_summary.html"
    ts_assert_exists "cellranger: filtered_feature_bc_matrix/"    "$outs/filtered_feature_bc_matrix"
    ts_assert_nonempty "cellranger: web_summary.html non-empty"   "$outs/web_summary.html"
}

l3_teardown_cellranger() {
    :
}
