#!/usr/bin/env bash
# test_dconvatac.sh — TJP test module for the dconvatac pipeline
# Sourced by the test framework (tjp-test-suite). Do not execute directly.

PIPELINE_NAME="dconvatac"
L3_SKIP=true
L3_SKIP_REASON="No minimal h5ad test fixtures available yet"

# ── Layer 1: offline validation ───────────────────────────────────────────────

l1_dconvatac() {
    local schema="$REPO_ROOT/templates/schemas/dconvatac.yaml"
    local tmpl="$REPO_ROOT/templates/dconvatac/config.yaml"
    local ss_tmpl="$REPO_ROOT/templates/dconvatac/samplesheet.csv"
    local tmpdir
    tmpdir=$(mktemp -d)

    # Schema and template files exist
    ts_assert_exists "dconvatac schema exists"               "$schema"
    ts_assert_exists "dconvatac template config exists"      "$tmpl"
    ts_assert_exists "dconvatac samplesheet template exists" "$ss_tmpl"

    # Required keys in template
    for key in spatial_h5ad reference_h5ad labels_key output_dir \
               run_hvp N_cells_per_location detection_alpha \
               max_epochs_spatial max_epochs_ref use_gpu; do
        ts_assert_yaml_key "template has '$key'" "$tmpl" "$key"
    done

    # Samplesheet template has required columns
    ts_assert_contains "samplesheet has 'sample' column"         "$ss_tmpl" "sample"
    ts_assert_contains "samplesheet has 'spatial_h5ad' column"   "$ss_tmpl" "spatial_h5ad"
    ts_assert_contains "samplesheet has 'reference_h5ad' column" "$ss_tmpl" "reference_h5ad"
    ts_assert_contains "samplesheet has 'labels_key' column"     "$ss_tmpl" "labels_key"

    # Good config passes validator (use /path/to/ to skip existence checks)
    local good_cfg="$tmpdir/good_config.yaml"
    cat > "$good_cfg" <<YAML
spatial_h5ad: /path/to/spatial.h5ad
reference_h5ad: /path/to/reference.h5ad
labels_key: cell_type
output_dir: /scratch/juno/testuser/dconvatac_results
run_hvp: true
N_cells_per_location: 8
detection_alpha: 20
max_epochs_spatial: 400
max_epochs_ref: 400
use_gpu: false
YAML
    ts_assert_pass "valid config passes validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config dconvatac '$good_cfg'"

    # Missing spatial_h5ad fails
    local bad_cfg="$tmpdir/bad_no_spatial.yaml"
    cat > "$bad_cfg" <<YAML
reference_h5ad: /path/to/reference.h5ad
labels_key: cell_type
output_dir: /scratch/juno/testuser/dconvatac_results
YAML
    ts_assert_fail "config missing 'spatial_h5ad' fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config dconvatac '$bad_cfg'"

    # Missing labels_key fails
    local bad_cfg2="$tmpdir/bad_no_labels.yaml"
    cat > "$bad_cfg2" <<YAML
spatial_h5ad: /path/to/spatial.h5ad
reference_h5ad: /path/to/reference.h5ad
output_dir: /scratch/juno/testuser/dconvatac_results
YAML
    ts_assert_fail "config missing 'labels_key' fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config dconvatac '$bad_cfg2'"

    # Invalid boolean fails
    local bad_cfg3="$tmpdir/bad_bool.yaml"
    cat > "$bad_cfg3" <<YAML
spatial_h5ad: /path/to/spatial.h5ad
reference_h5ad: /path/to/reference.h5ad
labels_key: cell_type
output_dir: /scratch/juno/testuser/dconvatac_results
use_gpu: yes
YAML
    ts_assert_fail "config with invalid boolean 'use_gpu: yes' fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config dconvatac '$bad_cfg3'"

    rm -rf "$tmpdir"
}

# ── Layer 2: dry-run launch ───────────────────────────────────────────────────

l2_dconvatac() {
    local tmpdir
    tmpdir=$(mktemp -d)

    local cfg="$tmpdir/config.yaml"
    cat > "$cfg" <<YAML
spatial_h5ad: /path/to/spatial.h5ad
reference_h5ad: /path/to/reference.h5ad
labels_key: cell_type
output_dir: /scratch/juno/testuser/dconvatac_results
run_hvp: true
N_cells_per_location: 8
detection_alpha: 20
max_epochs_spatial: 400
max_epochs_ref: 400
use_gpu: false
YAML

    ts_assert_pass "l2: config validates" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config dconvatac '$cfg'"

    ts_assert_pass "l2: dconvatac in KNOWN_PIPELINES" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_known_pipeline dconvatac"

    ts_assert_pass "l2: dconvatac-gpu in KNOWN_PIPELINES" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_known_pipeline dconvatac-gpu"

    ts_assert_pass "l2: CPU SLURM template resolves" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && [[ -f \$(get_slurm_template dconvatac) ]]"

    ts_assert_pass "l2: GPU SLURM template resolves" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && [[ -f \$(get_slurm_template dconvatac-gpu) ]]"

    ts_assert_fail "l2: dconvatac is not a native pipeline" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_native_pipeline dconvatac"

    ts_assert_exists "l2: dconvatac submodule directory exists" \
        "$REPO_ROOT/containers/dconvatac"

    ts_assert_exists "l2: pipeline script exists in submodule" \
        "$REPO_ROOT/containers/dconvatac/pipeline/dconvatac.py"

    rm -rf "$tmpdir"
}

# ── Layer 3: full SLURM execution ─────────────────────────────────────────────
# Skipped — requires real h5ad files (spatial ATAC data, ~100s MB each).
# To enable L3 testing: stage minimal h5ad fixtures to test_data/fixtures/dconvatac/
# and set L3_SKIP=false above.

l3_fixture_dconvatac() { return 1; }
l3_submit_dconvatac()  { :; }
l3_validate_dconvatac() { :; }
l3_teardown_dconvatac() { :; }
