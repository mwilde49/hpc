#!/usr/bin/env bash
# test_addone.sh — TJP test module for the AddOne pipeline
# Sourced by the test framework (tjp-test-suite). Do not execute directly.
#
# Layer 1: offline config/schema validation
# Layer 2: dry-run launch wiring check
# Layer 3: full SLURM execution on dev partition

PIPELINE_NAME="addone"
L3_SKIP=false
L3_SKIP_REASON=""

# ── Layer 1: offline validation ───────────────────────────────────────────────

l1_addone() {
    local schema="$REPO_ROOT/templates/schemas/addone.yaml"
    local tmpl="$REPO_ROOT/templates/addone/config.yaml"
    local tmpdir
    tmpdir=$(mktemp -d)

    # Schema file exists
    ts_assert_exists "addone schema file exists" "$schema"

    # Template config exists
    ts_assert_exists "addone template config exists" "$tmpl"

    # Template has required key: input
    ts_assert_yaml_key "template config has 'input' key" "$tmpl" "input"

    # Template has required key: output
    ts_assert_yaml_key "template config has 'output' key" "$tmpl" "output"

    # Good config with real input file passes validation
    local good_cfg="$tmpdir/good_config.yaml"
    cat > "$good_cfg" <<YAML
input: $REPO_ROOT/test_data/numbers.txt
output: /tmp/addone_test_output.txt
YAML
    ts_assert_pass "valid config passes validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config addone '$good_cfg'"

    # Bad config missing 'output' key fails validation
    local bad_cfg="$tmpdir/bad_config_no_output.yaml"
    cat > "$bad_cfg" <<YAML
input: $REPO_ROOT/test_data/numbers.txt
YAML
    ts_assert_fail "config missing 'output' key fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config addone '$bad_cfg'"

    # Bad config missing 'input' key fails validation
    local bad_cfg2="$tmpdir/bad_config_no_input.yaml"
    cat > "$bad_cfg2" <<YAML
output: /tmp/addone_test_output.txt
YAML
    ts_assert_fail "config missing 'input' key fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config addone '$bad_cfg2'"

    # addone has no samplesheet (per-sheet batch not applicable); just verify
    # the SLURM template exists
    ts_assert_exists "addone SLURM template exists" \
        "$REPO_ROOT/slurm_templates/addone_slurm_template.sh"

    # Reproducibility manifest: source-snapshotting must archive the inline
    # pipelines/addone/ directory and resolve the hpc superproject commit.
    # Runs fully offline, no SLURM needed.
    local mtmp
    mtmp=$(mktemp -d)
    echo "input: /tmp/x" > "$mtmp/config.yaml"
    (
        source "$REPO_ROOT/bin/lib/common.sh"
        source "$REPO_ROOT/bin/lib/manifest.sh"
        generate_manifest "$mtmp" addone "$mtmp/config.yaml" \
            "$REPO_ROOT/containers/addone_latest.sif" \
            "$REPO_ROOT/slurm_templates/addone_slurm_template.sh"
    )
    local expected_sha
    expected_sha=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)
    ts_assert_exists   "manifest: slurm_template_used.sh snapshotted" "$mtmp/slurm_template_used.sh"
    ts_assert_nonempty "manifest: pipeline_source.tar.gz snapshotted" "$mtmp/pipeline_source.tar.gz"
    ts_assert_contains "manifest: pipeline_submodule_commit matches repo HEAD" \
        "$mtmp/manifest.json" "$expected_sha"
    rm -rf "$mtmp"

    rm -rf "$tmpdir"
}

# ── Layer 2: dry-run launch ───────────────────────────────────────────────────

l2_addone() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local cfg="$tmpdir/config.yaml"

    cat > "$cfg" <<YAML
input: $REPO_ROOT/test_data/numbers.txt
output: $TEST_SCRATCH/addone/addone_out.txt
YAML

    # tjp-launch --dry-run is not a real flag; instead we test that the
    # framework correctly locates the config, validates it, resolves the
    # SLURM template, and creates the run directory structure.
    # We simulate the pre-submission steps that don't need sbatch.

    # Validator must pass on our minimal config
    ts_assert_pass "l2: minimal config validates cleanly" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config addone '$cfg'"

    # SLURM template resolves to an existing file via the registry
    ts_assert_pass "l2: SLURM template resolves in registry" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && [[ -f \$(get_slurm_template addone) ]]"

    # Container path resolves in the registry (file may not exist on local dev
    # machine, but the path string must be non-empty)
    ts_assert_pass "l2: container path resolves in registry" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && [[ -n \$(get_container_path addone) ]]"

    # is_known_pipeline recognises addone
    ts_assert_pass "l2: addone is a known pipeline" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_known_pipeline addone"

    # is_native_pipeline returns false for addone (it uses a container)
    ts_assert_fail "l2: addone is not a native pipeline" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_native_pipeline addone"

    # Reproducibility logging: repro.sh sources cleanly and is wired into
    # the SLURM template
    ts_assert_pass "l2: repro.sh sources cleanly" \
        bash -c "source '$REPO_ROOT/bin/lib/repro.sh'"
    ts_assert_contains "l2: addone template sources repro.sh" \
        "$REPO_ROOT/slurm_templates/addone_slurm_template.sh" "repro.sh"
    ts_assert_contains "l2: addone template wraps invocation with run_logged" \
        "$REPO_ROOT/slurm_templates/addone_slurm_template.sh" "run_logged"

    rm -rf "$tmpdir"
}

# ── Layer 3: full SLURM execution ─────────────────────────────────────────────

l3_fixture_addone() {
    # The numbers.txt file ships with the repo — always available.
    if [[ ! -f "$REPO_ROOT/test_data/numbers.txt" ]]; then
        echo "test_data/numbers.txt not found in repo" >&2
        return 1
    fi
    return 0
}

l3_submit_addone() {
    local cfg="$TEST_SCRATCH/addone/config_addone.yaml"
    mkdir -p "$TEST_SCRATCH/addone"

    cat > "$cfg" <<YAML
input: $REPO_ROOT/test_data/numbers.txt
output: $TEST_SCRATCH/addone/addone_out_${TEST_TS}.txt
YAML

    local job_id
    job_id=$("$REPO_ROOT/bin/tjp-launch" addone --dev --config "$cfg" 2>/dev/null \
        | grep -oP '(?<=job )\d+' | tail -1)
    echo "$job_id"
}

l3_validate_addone() {
    local output_file="$TEST_SCRATCH/addone/addone_out_${TEST_TS}.txt"
    ts_assert_exists "addone: output file exists" "$output_file"
    ts_assert_nonempty "addone: output file is non-empty" "$output_file"

    # Reproducibility artifacts live in the WORK run dir ($RUN_DIR)
    local work_run
    work_run=$(ls -1td "$WORK_ROOT/pipelines/addone/runs"/*/ 2>/dev/null | head -1)

    if [[ -z "$work_run" ]]; then
        ts_assert_exists "addone: WORK run directory exists" "$WORK_ROOT/pipelines/addone/runs"
        return
    fi

    ts_assert_exists   "addone: juno_environment.json"     "$work_run/juno_environment.json"
    ts_assert_exists   "addone: slurm_template_used.sh"    "$work_run/slurm_template_used.sh"
    ts_assert_nonempty "addone: pipeline_source.tar.gz"    "$work_run/pipeline_source.tar.gz"
    ts_assert_nonempty "addone: invocation.log"            "$work_run/invocation.log"
    ts_assert_fail     "addone: juno_environment.json end_time populated" \
                       bash -c "grep -q '\"end_time\": null' '$work_run/juno_environment.json'"
}

l3_teardown_addone() {
    # Leave outputs in place for inspection; just note location.
    : # no-op — test scratch is cleaned by the suite runner if requested
}
