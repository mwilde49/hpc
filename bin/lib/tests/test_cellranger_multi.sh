#!/usr/bin/env bash
# test_cellranger_multi.sh — TJP test module for the Cell Ranger Multi pipeline
# Sourced by the test framework (tjp-test-suite). Do not execute directly.

PIPELINE_NAME="cellranger-multi"
L3_SKIP=false
L3_SKIP_REASON=""

_CRM_TOOL_PATH=""
_CRM_TINY_FASTQ=""
_CRM_TINY_REF=""
_CRM_TINY_SAMPLE="bamtofastq"   # sample name inside tiny_fastq

# ── Layer 1: offline validation ───────────────────────────────────────────────

l1_cellranger_multi() {
    local schema="$REPO_ROOT/templates/schemas/cellranger_multi.yaml"
    local tmpl="$REPO_ROOT/templates/cellranger-multi/config.yaml"
    local ss_tmpl="$REPO_ROOT/templates/cellranger-multi/samplesheet.csv"
    local tmpdir
    tmpdir=$(mktemp -d)

    ts_assert_exists "cellranger-multi schema exists" "$schema"
    ts_assert_exists "cellranger-multi template config exists" "$tmpl"
    ts_assert_exists "cellranger-multi samplesheet template exists" "$ss_tmpl"

    # Required keys in template
    for key in sample_id transcriptome create_bam localcores localmem; do
        ts_assert_yaml_key "template has '$key'" "$tmpl" "$key"
    done

    # Samplesheet required columns
    ts_assert_contains "samplesheet has 'sample_id' column"     "$ss_tmpl" "sample_id"
    ts_assert_contains "samplesheet has 'transcriptome' column" "$ss_tmpl" "transcriptome"
    ts_assert_contains "samplesheet has 'libraries_file' column" "$ss_tmpl" "libraries_file"

    local txome="$tmpdir/transcriptome"
    mkdir -p "$txome"

    # Good config — inline GEX-only libraries block
    local good_cfg="$tmpdir/good_config.yaml"
    cat > "$good_cfg" <<YAML
sample_id: multi_test_sample
transcriptome: $txome
create_bam: true
localcores: 4
localmem: 32
libraries:
  - fastq_path: /path/to/gex/fastq
    sample_name: GEX_sample
    feature_types: Gene Expression
YAML
    ts_assert_pass "valid GEX-only config passes validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config cellranger-multi '$good_cfg'"

    # Missing sample_id must fail
    local bad_cfg="$tmpdir/bad_no_sample_id.yaml"
    cat > "$bad_cfg" <<YAML
transcriptome: $txome
create_bam: true
localcores: 4
localmem: 32
libraries:
  - fastq_path: /path/to/gex/fastq
    sample_name: GEX_sample
    feature_types: Gene Expression
YAML
    ts_assert_fail "config missing 'sample_id' fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config cellranger-multi '$bad_cfg'"

    rm -rf "$tmpdir"
}

# ── Layer 2: dry-run launch ───────────────────────────────────────────────────

l2_cellranger_multi() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local txome="$tmpdir/transcriptome"
    mkdir -p "$txome"

    local cfg="$tmpdir/config.yaml"
    cat > "$cfg" <<YAML
sample_id: multi_l2_test
transcriptome: $txome
create_bam: true
localcores: 4
localmem: 32
libraries:
  - fastq_path: /path/to/gex/fastq
    sample_name: GEX_sample
    feature_types: Gene Expression
YAML

    ts_assert_pass "l2: config validates" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config cellranger-multi '$cfg'"

    ts_assert_pass "l2: cellranger-multi in KNOWN_PIPELINES" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_known_pipeline cellranger-multi"

    ts_assert_pass "l2: SLURM template resolves" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && [[ -f \$(get_slurm_template cellranger-multi) ]]"

    ts_assert_pass "l2: cellranger-multi is a native pipeline" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_native_pipeline cellranger-multi"

    # Wrapper script must exist in 10x submodule
    ts_assert_exists "l2: cellranger-multi-run.sh wrapper exists" \
        "$REPO_ROOT/containers/10x/bin/cellranger-multi-run.sh"

    rm -rf "$tmpdir"
}

# ── Layer 3: full SLURM execution ─────────────────────────────────────────────

l3_fixture_cellranger_multi() {
    _CRM_TOOL_PATH=$(bash -c "source '$REPO_ROOT/bin/lib/common.sh' && get_tool_path cellranger-multi")

    if [[ -z "$_CRM_TOOL_PATH" || ! -d "$_CRM_TOOL_PATH" ]]; then
        echo "Cell Ranger tool not found at: $_CRM_TOOL_PATH" >&2
        return 1
    fi

    _CRM_TINY_FASTQ="$_CRM_TOOL_PATH/external/cellranger_tiny_fastq"
    _CRM_TINY_REF="$_CRM_TOOL_PATH/external/cellranger_tiny_ref"

    if [[ ! -d "$_CRM_TINY_FASTQ" ]]; then
        echo "cellranger_tiny_fastq not found: $_CRM_TINY_FASTQ" >&2
        return 1
    fi

    if [[ ! -d "$_CRM_TINY_REF" ]]; then
        echo "cellranger_tiny_ref not found: $_CRM_TINY_REF" >&2
        return 1
    fi

    # Detect sample name from tiny_fastq directory
    local detected
    detected=$(find "$_CRM_TINY_FASTQ" -name "*_R1_*" -printf '%f\n' 2>/dev/null \
        | sed 's/_S[0-9]*_L[0-9]*_R1.*//' | sort -u | head -1)
    [[ -n "$detected" ]] && _CRM_TINY_SAMPLE="$detected"

    return 0
}

l3_submit_cellranger_multi() {
    _CRM_TOOL_PATH=$(bash -c "source '$REPO_ROOT/bin/lib/common.sh' && get_tool_path cellranger-multi")
    _CRM_TINY_FASTQ="$_CRM_TOOL_PATH/external/cellranger_tiny_fastq"
    _CRM_TINY_REF="$_CRM_TOOL_PATH/external/cellranger_tiny_ref"

    local test_dir="$TEST_SCRATCH/cellranger-multi"
    local cfg="$test_dir/config_cellranger_multi.yaml"
    mkdir -p "$test_dir"

    # GEX-only multi test using tiny_fastq data
    cat > "$cfg" <<YAML
sample_id: multi_tiny_test
transcriptome: $_CRM_TINY_REF
create_bam: true
localcores: 4
localmem: 16
libraries:
  - fastq_path: $_CRM_TINY_FASTQ
    sample_name: $_CRM_TINY_SAMPLE
    feature_types: Gene Expression
YAML

    local job_id
    job_id=$("$REPO_ROOT/bin/tjp-launch" cellranger-multi --dev --config "$cfg" 2>/dev/null \
        | grep -oP '(?<=job )\d+' | tail -1)
    echo "$job_id"
}

l3_validate_cellranger_multi() {
    local scratch_dir="$SCRATCH_ROOT/pipelines/cellranger-multi/runs"
    local latest_run
    latest_run=$(ls -1td "$scratch_dir"/*/ 2>/dev/null | head -1)

    if [[ -z "$latest_run" ]]; then
        ts_assert_exists "cellranger-multi: scratch run dir exists" "$scratch_dir"
        return
    fi

    # GEX-only multi produces the same outs/ structure as cellranger count
    local outs="$latest_run/multi_tiny_test/outs"
    ts_assert_exists  "cellranger-multi: sample outs/ directory"    "$outs"
    ts_assert_exists  "cellranger-multi: web_summary.html"          "$outs/web_summary.html"
    ts_assert_nonempty "cellranger-multi: web_summary.html non-empty" "$outs/web_summary.html"
}

l3_teardown_cellranger_multi() {
    :
}
