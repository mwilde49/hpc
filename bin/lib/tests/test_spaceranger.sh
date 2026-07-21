#!/usr/bin/env bash
# test_spaceranger.sh — TJP test module for the Space Ranger pipeline
# Sourced by the test framework (tjp-test-suite). Do not execute directly.

PIPELINE_NAME="spaceranger"
L3_SKIP=false
L3_SKIP_REASON=""

_SR_TOOL_PATH=""
_SR_TINY_FASTQ=""
_SR_TINY_REF=""
_SR_TINY_IMAGE=""

# ── Layer 1: offline validation ───────────────────────────────────────────────

l1_spaceranger() {
    local schema="$REPO_ROOT/templates/schemas/spaceranger.yaml"
    local tmpl="$REPO_ROOT/templates/spaceranger/config.yaml"
    local ss_tmpl="$REPO_ROOT/templates/spaceranger/samplesheet.csv"
    local tmpdir
    tmpdir=$(mktemp -d)

    ts_assert_exists "spaceranger schema exists" "$schema"
    ts_assert_exists "spaceranger template config exists" "$tmpl"
    ts_assert_exists "spaceranger samplesheet template exists" "$ss_tmpl"

    # Required keys in template
    for key in sample_id sample_name fastq_dir transcriptome image \
               localcores localmem create_bam; do
        ts_assert_yaml_key "template has '$key'" "$tmpl" "$key"
    done

    # Samplesheet required columns
    ts_assert_contains "samplesheet has 'sample' column"       "$ss_tmpl" "sample"
    ts_assert_contains "samplesheet has 'fastqs' column"       "$ss_tmpl" "fastqs"
    ts_assert_contains "samplesheet has 'transcriptome' column" "$ss_tmpl" "transcriptome"
    ts_assert_contains "samplesheet has 'image' column"        "$ss_tmpl" "image"

    local fastq_dir="$tmpdir/fastq"
    local txome="$tmpdir/transcriptome"
    local img="$tmpdir/image.tif"
    mkdir -p "$fastq_dir" "$txome"
    touch "$img"

    # Good config with unknown_slide (no slide+area required)
    local good_cfg_us="$tmpdir/good_unknown_slide.yaml"
    cat > "$good_cfg_us" <<YAML
sample_id: sr_test
sample_name: SRTest
fastq_dir: $fastq_dir
transcriptome: $txome
image: $img
unknown_slide: visium-1
localcores: 4
localmem: 32
create_bam: true
YAML
    ts_assert_pass "valid config with unknown_slide passes validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config spaceranger '$good_cfg_us'"

    # Good config with explicit slide+area
    local good_cfg_slide="$tmpdir/good_slide_area.yaml"
    cat > "$good_cfg_slide" <<YAML
sample_id: sr_test
sample_name: SRTest
fastq_dir: $fastq_dir
transcriptome: $txome
image: $img
slide: V19J25-123
area: A1
localcores: 4
localmem: 32
create_bam: true
YAML
    ts_assert_pass "valid config with slide+area passes validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config spaceranger '$good_cfg_slide'"

    # Invalid unknown_slide value must fail
    local bad_cfg_us="$tmpdir/bad_unknown_slide.yaml"
    cat > "$bad_cfg_us" <<YAML
sample_id: sr_test
sample_name: SRTest
fastq_dir: $fastq_dir
transcriptome: $txome
image: $img
unknown_slide: visium-99
localcores: 4
localmem: 32
create_bam: true
YAML
    ts_assert_fail "invalid unknown_slide value fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config spaceranger '$bad_cfg_us'"

    # Missing image must fail
    local bad_cfg_noimg="$tmpdir/bad_no_image.yaml"
    cat > "$bad_cfg_noimg" <<YAML
sample_id: sr_test
sample_name: SRTest
fastq_dir: $fastq_dir
transcriptome: $txome
unknown_slide: visium-1
localcores: 4
localmem: 32
create_bam: true
YAML
    ts_assert_fail "config missing 'image' fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config spaceranger '$bad_cfg_noimg'"

    # Invalid area value must fail
    local bad_cfg_area="$tmpdir/bad_area.yaml"
    cat > "$bad_cfg_area" <<YAML
sample_id: sr_test
sample_name: SRTest
fastq_dir: $fastq_dir
transcriptome: $txome
image: $img
slide: V19J25-123
area: E1
localcores: 4
localmem: 32
create_bam: true
YAML
    ts_assert_fail "config with invalid area fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config spaceranger '$bad_cfg_area'"

    # Reproducibility manifest: source-snapshotting must resolve the 10x
    # submodule commit SHA. Runs fully offline, no SLURM needed.
    local mtmp
    mtmp=$(mktemp -d)
    echo "sample_id: test" > "$mtmp/config.yaml"
    (
        source "$REPO_ROOT/bin/lib/common.sh"
        source "$REPO_ROOT/bin/lib/manifest.sh"
        generate_manifest "$mtmp" spaceranger "$mtmp/config.yaml" \
            "native:$(get_tool_path spaceranger 2>/dev/null || echo /groups/tprice/opt/spaceranger-4.0.1)" \
            "$REPO_ROOT/slurm_templates/spaceranger_slurm_template.sh"
    )
    local expected_sha
    expected_sha=$(git -C "$REPO_ROOT/containers/10x" rev-parse HEAD 2>/dev/null)
    ts_assert_exists   "manifest: slurm_template_used.sh snapshotted" "$mtmp/slurm_template_used.sh"
    ts_assert_nonempty "manifest: pipeline_source.tar.gz snapshotted" "$mtmp/pipeline_source.tar.gz"
    ts_assert_contains "manifest: pipeline_submodule_commit matches submodule HEAD" \
        "$mtmp/manifest.json" "$expected_sha"
    rm -rf "$mtmp"

    rm -rf "$tmpdir"
}

# ── Layer 2: dry-run launch ───────────────────────────────────────────────────

l2_spaceranger() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local fastq_dir="$tmpdir/fastq"
    local txome="$tmpdir/transcriptome"
    local img="$tmpdir/image.tif"
    mkdir -p "$fastq_dir" "$txome"
    touch "$img"

    local cfg="$tmpdir/config.yaml"
    cat > "$cfg" <<YAML
sample_id: sr_l2_test
sample_name: SRL2Test
fastq_dir: $fastq_dir
transcriptome: $txome
image: $img
unknown_slide: visium-1
localcores: 4
localmem: 32
create_bam: true
YAML

    ts_assert_pass "l2: config validates" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config spaceranger '$cfg'"

    ts_assert_pass "l2: spaceranger in KNOWN_PIPELINES" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_known_pipeline spaceranger"

    ts_assert_pass "l2: SLURM template resolves" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && [[ -f \$(get_slurm_template spaceranger) ]]"

    ts_assert_pass "l2: spaceranger is a native pipeline" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_native_pipeline spaceranger"

    # Wrapper script must exist in 10x submodule
    ts_assert_exists "l2: spaceranger-run.sh wrapper exists" \
        "$REPO_ROOT/containers/10x/bin/spaceranger-run.sh"

    # Reproducibility logging: repro.sh sources cleanly and is wired into
    # the SLURM template
    ts_assert_pass "l2: repro.sh sources cleanly" \
        bash -c "source '$REPO_ROOT/bin/lib/repro.sh'"
    ts_assert_contains "l2: spaceranger template sources repro.sh" \
        "$REPO_ROOT/slurm_templates/spaceranger_slurm_template.sh" "repro.sh"
    ts_assert_contains "l2: spaceranger template wraps invocation with run_logged" \
        "$REPO_ROOT/slurm_templates/spaceranger_slurm_template.sh" "run_logged"

    rm -rf "$tmpdir"
}

# ── Layer 3: full SLURM execution ─────────────────────────────────────────────

l3_fixture_spaceranger() {
    _SR_TOOL_PATH=$(bash -c "source '$REPO_ROOT/bin/lib/common.sh' && get_tool_path spaceranger")

    if [[ -z "$_SR_TOOL_PATH" || ! -d "$_SR_TOOL_PATH" ]]; then
        echo "Space Ranger tool not found at: $_SR_TOOL_PATH" >&2
        return 1
    fi

    _SR_TINY_FASTQ="$_SR_TOOL_PATH/external/spaceranger_tiny_inputs/fastqs"
    _SR_TINY_IMAGE="$_SR_TOOL_PATH/external/spaceranger_tiny_inputs/image/tinyimage.jpg"
    _SR_TINY_REF="$_SR_TOOL_PATH/external/spaceranger_tiny_ref"

    if [[ ! -d "$_SR_TINY_FASTQ" ]]; then
        echo "spaceranger_tiny_inputs/fastqs not found: $_SR_TINY_FASTQ" >&2
        echo "This ships with Space Ranger — ensure the install is intact." >&2
        return 1
    fi

    if [[ ! -f "$_SR_TINY_IMAGE" ]]; then
        echo "tiny image not found: $_SR_TINY_IMAGE" >&2
        return 1
    fi

    if [[ ! -d "$_SR_TINY_REF" ]]; then
        echo "spaceranger_tiny_ref not found: $_SR_TINY_REF" >&2
        return 1
    fi

    return 0
}

l3_submit_spaceranger() {
    _SR_TOOL_PATH=$(bash -c "source '$REPO_ROOT/bin/lib/common.sh' && get_tool_path spaceranger")
    _SR_TINY_FASTQ="$_SR_TOOL_PATH/external/spaceranger_tiny_inputs/fastqs"
    _SR_TINY_IMAGE="$_SR_TOOL_PATH/external/spaceranger_tiny_inputs/image/tinyimage.jpg"
    _SR_TINY_REF="$_SR_TOOL_PATH/external/spaceranger_tiny_ref"

    local test_dir="$TEST_SCRATCH/spaceranger"
    local cfg="$test_dir/config_spaceranger.yaml"
    mkdir -p "$test_dir"

    cat > "$cfg" <<YAML
sample_id: spaceranger_tiny_test
sample_name: tinytest
fastq_dir: $_SR_TINY_FASTQ
transcriptome: $_SR_TINY_REF
image: $_SR_TINY_IMAGE
unknown_slide: visium-1
localcores: 4
localmem: 16
create_bam: true
YAML

    local job_id
    job_id=$("$REPO_ROOT/bin/tjp-launch" spaceranger --dev --config "$cfg" 2>/dev/null \
        | grep -oP '(?<=job )\d+' | tail -1)
    echo "$job_id"
}

l3_validate_spaceranger() {
    local scratch_dir="$SCRATCH_ROOT/pipelines/spaceranger/runs"
    local latest_run
    latest_run=$(ls -1td "$scratch_dir"/*/ 2>/dev/null | head -1)

    if [[ -z "$latest_run" ]]; then
        ts_assert_exists "spaceranger: scratch run dir exists" "$scratch_dir"
        return
    fi

    local outs="$latest_run/spaceranger_tiny_test/outs"
    ts_assert_exists  "spaceranger: sample outs/ directory"    "$outs"
    ts_assert_exists  "spaceranger: spatial/ output directory" "$outs/spatial"
    ts_assert_exists  "spaceranger: web_summary.html"          "$outs/web_summary.html"
    ts_assert_nonempty "spaceranger: web_summary.html non-empty" "$outs/web_summary.html"

    # Reproducibility artifacts live in the WORK run dir ($RUN_DIR), not the
    # scratch output dir checked above
    local work_run
    work_run=$(ls -1td "$WORK_ROOT/pipelines/spaceranger/runs"/*/ 2>/dev/null | head -1)

    if [[ -z "$work_run" ]]; then
        ts_assert_exists "spaceranger: WORK run directory exists" "$WORK_ROOT/pipelines/spaceranger/runs"
        return
    fi

    ts_assert_exists   "spaceranger: juno_environment.json"  "$work_run/juno_environment.json"
    ts_assert_exists   "spaceranger: slurm_template_used.sh" "$work_run/slurm_template_used.sh"
    ts_assert_nonempty "spaceranger: pipeline_source.tar.gz" "$work_run/pipeline_source.tar.gz"
    ts_assert_nonempty "spaceranger: invocation.log"         "$work_run/invocation.log"
    ts_assert_contains "spaceranger: invocation.log records spaceranger-run.sh" \
                       "$work_run/invocation.log" "spaceranger-run.sh"
    ts_assert_fail     "spaceranger: juno_environment.json end_time populated" \
                       bash -c "grep -q '\"end_time\": null' '$work_run/juno_environment.json'"
}

l3_teardown_spaceranger() {
    :
}
