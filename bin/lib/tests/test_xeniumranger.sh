#!/usr/bin/env bash
# test_xeniumranger.sh — TJP test module for the Xenium Ranger pipeline
# Sourced by the test framework (tjp-test-suite). Do not execute directly.
#
# Layer 3 is SKIPPED: no minimal Xenium output bundle is currently available.
# Layers 1 and 2 run in full (config validation + registry wiring).

PIPELINE_NAME="xeniumranger"
L3_SKIP=true
L3_SKIP_REASON="No minimal Xenium bundle available. Generate one with test_data/fixtures/generate_xenium_fixture.py when Python deps are available."

# ── Layer 1: offline validation ───────────────────────────────────────────────

l1_xeniumranger() {
    local schema="$REPO_ROOT/templates/schemas/xeniumranger.yaml"
    local tmpl="$REPO_ROOT/templates/xeniumranger/config.yaml"
    local ss_tmpl="$REPO_ROOT/templates/xeniumranger/samplesheet.csv"
    local tmpdir
    tmpdir=$(mktemp -d)

    ts_assert_exists "xeniumranger schema exists" "$schema"
    ts_assert_exists "xeniumranger template config exists" "$tmpl"
    ts_assert_exists "xeniumranger samplesheet template exists" "$ss_tmpl"

    # Required keys in template
    for key in sample_id command xenium_bundle localcores localmem; do
        ts_assert_yaml_key "template has '$key'" "$tmpl" "$key"
    done

    # Samplesheet required columns
    ts_assert_contains "samplesheet has 'sample' column"        "$ss_tmpl" "sample"
    ts_assert_contains "samplesheet has 'xenium_bundle' column" "$ss_tmpl" "xenium_bundle"
    ts_assert_contains "samplesheet has 'command' column"       "$ss_tmpl" "command"

    local bundle_dir="$tmpdir/xenium_bundle"
    mkdir -p "$bundle_dir"

    # Good config: resegment command
    local good_cfg="$tmpdir/good_resegment.yaml"
    cat > "$good_cfg" <<YAML
sample_id: xenium_test
command: resegment
xenium_bundle: $bundle_dir
localcores: 4
localmem: 32
YAML
    ts_assert_pass "valid resegment config passes validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config xeniumranger '$good_cfg'"

    # import-segmentation requires segmentation_file
    local bad_no_seg="$tmpdir/bad_no_segfile.yaml"
    cat > "$bad_no_seg" <<YAML
sample_id: xenium_test
command: import-segmentation
xenium_bundle: $bundle_dir
localcores: 4
localmem: 32
YAML
    ts_assert_fail "import-segmentation config missing segmentation_file fails" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config xeniumranger '$bad_no_seg'"

    # import-segmentation with non-existent segmentation_file fails
    local bad_seg_path="$tmpdir/bad_seg_path.yaml"
    cat > "$bad_seg_path" <<YAML
sample_id: xenium_test
command: import-segmentation
xenium_bundle: $bundle_dir
segmentation_file: /does/not/exist/cells.csv.gz
localcores: 4
localmem: 32
YAML
    ts_assert_fail "import-segmentation config with missing segmentation_file path fails" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config xeniumranger '$bad_seg_path'"

    # Invalid command must fail
    local bad_cmd="$tmpdir/bad_command.yaml"
    cat > "$bad_cmd" <<YAML
sample_id: xenium_test
command: analyze
xenium_bundle: $bundle_dir
localcores: 4
localmem: 32
YAML
    ts_assert_fail "config with invalid command fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config xeniumranger '$bad_cmd'"

    # Missing sample_id must fail
    local bad_no_sample="$tmpdir/bad_no_sample.yaml"
    cat > "$bad_no_sample" <<YAML
command: resegment
xenium_bundle: $bundle_dir
localcores: 4
localmem: 32
YAML
    ts_assert_fail "config missing 'sample_id' fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config xeniumranger '$bad_no_sample'"

    # Reproducibility manifest: source-snapshotting must resolve the 10x
    # submodule commit SHA. Runs fully offline, no SLURM needed.
    local mtmp
    mtmp=$(mktemp -d)
    echo "sample_id: test" > "$mtmp/config.yaml"
    (
        source "$REPO_ROOT/bin/lib/common.sh"
        source "$REPO_ROOT/bin/lib/manifest.sh"
        generate_manifest "$mtmp" xeniumranger "$mtmp/config.yaml" \
            "native:$(get_tool_path xeniumranger 2>/dev/null || echo /groups/tprice/opt/xeniumranger-xenium4.0)" \
            "$REPO_ROOT/slurm_templates/xeniumranger_slurm_template.sh"
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

l2_xeniumranger() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local bundle_dir="$tmpdir/xenium_bundle"
    mkdir -p "$bundle_dir"

    local cfg="$tmpdir/config.yaml"
    cat > "$cfg" <<YAML
sample_id: xenium_l2_test
command: resegment
xenium_bundle: $bundle_dir
localcores: 4
localmem: 32
YAML

    ts_assert_pass "l2: config validates" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config xeniumranger '$cfg'"

    ts_assert_pass "l2: xeniumranger in KNOWN_PIPELINES" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_known_pipeline xeniumranger"

    ts_assert_pass "l2: SLURM template resolves" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && [[ -f \$(get_slurm_template xeniumranger) ]]"

    ts_assert_pass "l2: xeniumranger is a native pipeline" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_native_pipeline xeniumranger"

    ts_assert_pass "l2: get_tool_path returns non-empty for xeniumranger" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && [[ -n \$(get_tool_path xeniumranger) ]]"

    # Wrapper script must exist in 10x submodule
    ts_assert_exists "l2: xeniumranger-run.sh wrapper exists" \
        "$REPO_ROOT/containers/10x/bin/xeniumranger-run.sh"

    # Reproducibility logging: repro.sh sources cleanly and is wired into
    # the SLURM template
    ts_assert_pass "l2: repro.sh sources cleanly" \
        bash -c "source '$REPO_ROOT/bin/lib/repro.sh'"
    ts_assert_contains "l2: xeniumranger template sources repro.sh" \
        "$REPO_ROOT/slurm_templates/xeniumranger_slurm_template.sh" "repro.sh"

    # Provenance README: provenance.sh sources cleanly and is wired into the
    # SLURM template (L3 is skipped for this pipeline, so this L2 check is
    # the only automated coverage it gets)
    ts_assert_pass "l2: provenance.sh sources cleanly" \
        bash -c "source '$REPO_ROOT/bin/lib/repro.sh' && source '$REPO_ROOT/bin/lib/provenance.sh'"
    ts_assert_pass "l2: provenance.sh defines its hooks" \
        bash -c "source '$REPO_ROOT/bin/lib/repro.sh' && source '$REPO_ROOT/bin/lib/provenance.sh' && declare -f start_console_log capture_software_versions generate_provenance_readme >/dev/null"
    ts_assert_contains "l2: xeniumranger template sources provenance.sh" \
        "$REPO_ROOT/slurm_templates/xeniumranger_slurm_template.sh" "provenance.sh"
    ts_assert_contains "l2: xeniumranger template captures software versions" \
        "$REPO_ROOT/slurm_templates/xeniumranger_slurm_template.sh" "capture_software_versions"
    ts_assert_contains "l2: xeniumranger template generates provenance README on exit" \
        "$REPO_ROOT/slurm_templates/xeniumranger_slurm_template.sh" "generate_provenance_readme"
    ts_assert_contains "l2: xeniumranger template wraps invocation with run_logged" \
        "$REPO_ROOT/slurm_templates/xeniumranger_slurm_template.sh" "run_logged"

    rm -rf "$tmpdir"
}

# ── Layer 3: skipped ─────────────────────────────────────────────────────────
# L3_SKIP=true — the suite runner will skip these automatically.

l3_fixture_xeniumranger() {
    echo "$L3_SKIP_REASON" >&2
    return 1
}

l3_submit_xeniumranger() {
    echo "L3 skipped for xeniumranger" >&2
}

l3_validate_xeniumranger() {
    ts_skip "xeniumranger L3 validation" "$L3_SKIP_REASON"
}

l3_teardown_xeniumranger() {
    :
}
