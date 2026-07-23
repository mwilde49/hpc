#!/usr/bin/env bash
# test_virome.sh — TJP test module for the Virome pipeline
# Sourced by the test framework (tjp-test-suite). Do not execute directly.

PIPELINE_NAME="virome"
L3_SKIP=false
L3_SKIP_REASON=""

_VIROME_SYNTHETIC_DIR="$SCRATCH_ROOT/pipelines/virome/test_data/fastq"
_VIROME_TINY_KRAKEN2="$REPO_ROOT/references/tiny/kraken2_db"
_VIROME_TINY_STAR="$REPO_ROOT/references/tiny/star_index"

# ── Layer 1: offline validation ───────────────────────────────────────────────

l1_virome() {
    local schema="$REPO_ROOT/templates/schemas/virome.yaml"
    local tmpl="$REPO_ROOT/templates/virome/config.yaml"
    local ss_tmpl="$REPO_ROOT/templates/virome/samplesheet.csv"
    local tmpdir
    tmpdir=$(mktemp -d)

    ts_assert_exists "virome schema exists" "$schema"
    ts_assert_exists "virome template config exists" "$tmpl"
    ts_assert_exists "virome samplesheet template exists" "$ss_tmpl"

    # Required keys
    for key in project_name samplesheet outdir star_index kraken2_db; do
        ts_assert_yaml_key "template has '$key'" "$tmpl" "$key"
    done

    # Samplesheet template has required columns
    ts_assert_contains "samplesheet has 'sample' column"    "$ss_tmpl" "sample"
    ts_assert_contains "samplesheet has 'fastq_r1' column"  "$ss_tmpl" "fastq_r1"
    ts_assert_contains "samplesheet has 'fastq_r2' column"  "$ss_tmpl" "fastq_r2"

    # Build a minimal samplesheet for validation
    local ss_file="$tmpdir/samplesheet.csv"
    cat > "$ss_file" <<CSV
sample,fastq_r1,fastq_r2
sample_01,/path/to/sample_01_R1.fastq.gz,/path/to/sample_01_R2.fastq.gz
CSV

    # Good config — use /path/to/ for existence-checked paths except adapters/container_dir
    # adapters and container_dir are auto-set and the validator checks them if set
    local good_cfg="$tmpdir/good_config.yaml"
    cat > "$good_cfg" <<YAML
project_name: Virome-Test
samplesheet: $ss_file
outdir: /tmp/virome_test_out
star_index: /path/to/star_index
kraken2_db: /path/to/kraken2_db
adapters: /path/to/NexteraPE-PE.fa
container_dir: /path/to/containers
YAML
    ts_assert_pass "valid config passes validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config virome '$good_cfg'"

    # Missing kraken2_db must fail
    local bad_cfg="$tmpdir/bad_no_kraken2.yaml"
    cat > "$bad_cfg" <<YAML
project_name: Virome-Test
samplesheet: $ss_file
outdir: /tmp/virome_test_out
star_index: /path/to/star_index
adapters: /path/to/NexteraPE-PE.fa
container_dir: /path/to/containers
YAML
    ts_assert_fail "config missing 'kraken2_db' fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config virome '$bad_cfg'"

    # Missing outdir must fail
    local bad_cfg2="$tmpdir/bad_no_outdir.yaml"
    cat > "$bad_cfg2" <<YAML
project_name: Virome-Test
samplesheet: $ss_file
star_index: /path/to/star_index
kraken2_db: /path/to/kraken2_db
adapters: /path/to/NexteraPE-PE.fa
container_dir: /path/to/containers
YAML
    ts_assert_fail "config missing 'outdir' fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config virome '$bad_cfg2'"

    # Samplesheet missing 'sample' column fails virome validator
    local bad_ss="$tmpdir/bad_samplesheet.csv"
    cat > "$bad_ss" <<CSV
id,fastq_r1,fastq_r2
sample_01,/path/to/r1.fastq.gz,/path/to/r2.fastq.gz
CSV
    local bad_ss_cfg="$tmpdir/bad_ss_config.yaml"
    cat > "$bad_ss_cfg" <<YAML
project_name: Virome-Test
samplesheet: $bad_ss
outdir: /tmp/virome_test_out
star_index: /path/to/star_index
kraken2_db: /path/to/kraken2_db
adapters: /path/to/NexteraPE-PE.fa
container_dir: /path/to/containers
YAML
    ts_assert_fail "config with samplesheet missing 'sample' column fails validator" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config virome '$bad_ss_cfg'"

    # Reproducibility manifest: source-snapshotting must resolve the virome
    # submodule commit SHA. Runs fully offline, no SLURM needed.
    local mtmp
    mtmp=$(mktemp -d)
    echo "project_name: test" > "$mtmp/config.yaml"
    (
        source "$REPO_ROOT/bin/lib/common.sh"
        source "$REPO_ROOT/bin/lib/manifest.sh"
        generate_manifest "$mtmp" virome "$mtmp/config.yaml" \
            "$REPO_ROOT/containers/virome" \
            "$REPO_ROOT/slurm_templates/virome_slurm_template.sh"
    )
    local expected_sha
    expected_sha=$(git -C "$REPO_ROOT/containers/virome" rev-parse HEAD 2>/dev/null)
    ts_assert_exists   "manifest: slurm_template_used.sh snapshotted" "$mtmp/slurm_template_used.sh"
    ts_assert_nonempty "manifest: pipeline_source.tar.gz snapshotted" "$mtmp/pipeline_source.tar.gz"
    ts_assert_contains "manifest: pipeline_submodule_commit matches submodule HEAD" \
        "$mtmp/manifest.json" "$expected_sha"
    rm -rf "$mtmp"

    rm -rf "$tmpdir"
}

# ── Layer 2: dry-run launch ───────────────────────────────────────────────────

l2_virome() {
    local tmpdir
    tmpdir=$(mktemp -d)

    local ss_file="$tmpdir/samplesheet.csv"
    cat > "$ss_file" <<CSV
sample,fastq_r1,fastq_r2
sample_01,/path/to/sample_01_R1.fastq.gz,/path/to/sample_01_R2.fastq.gz
CSV

    local cfg="$tmpdir/config.yaml"
    cat > "$cfg" <<YAML
project_name: Virome-L2-Test
samplesheet: $ss_file
outdir: /tmp/virome_l2_out
star_index: /path/to/star_index
kraken2_db: /path/to/kraken2_db
adapters: /path/to/NexteraPE-PE.fa
container_dir: /path/to/containers
YAML

    ts_assert_pass "l2: config validates" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && source '$REPO_ROOT/bin/lib/validate.sh' && validate_config virome '$cfg'"

    ts_assert_pass "l2: virome in KNOWN_PIPELINES" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_known_pipeline virome"

    ts_assert_pass "l2: SLURM template resolves" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && [[ -f \$(get_slurm_template virome) ]]"

    ts_assert_pass "l2: virome is a multi-container pipeline" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_multicontainer_pipeline virome"

    ts_assert_fail "l2: virome is not a native pipeline" \
        bash -c "source '$REPO_ROOT/bin/lib/common.sh' && is_native_pipeline virome"

    # Container directory (submodule) must exist
    ts_assert_exists "l2: virome container submodule directory exists" \
        "$REPO_ROOT/containers/virome"

    # Reproducibility logging: repro.sh sources cleanly and is wired into
    # the SLURM template (node/partition capture, invocation log, Nextflow trace)
    ts_assert_pass "l2: repro.sh sources cleanly" \
        bash -c "source '$REPO_ROOT/bin/lib/repro.sh'"
    ts_assert_contains "l2: virome template sources repro.sh" \
        "$REPO_ROOT/slurm_templates/virome_slurm_template.sh" "repro.sh"

    # Provenance README: provenance.sh sources cleanly and is wired into the
    # SLURM template
    ts_assert_pass "l2: provenance.sh sources cleanly" \
        bash -c "source '$REPO_ROOT/bin/lib/repro.sh' && source '$REPO_ROOT/bin/lib/provenance.sh'"
    ts_assert_pass "l2: provenance.sh defines its hooks" \
        bash -c "source '$REPO_ROOT/bin/lib/repro.sh' && source '$REPO_ROOT/bin/lib/provenance.sh' && declare -f start_console_log capture_software_versions generate_provenance_readme >/dev/null"
    ts_assert_contains "l2: virome template sources provenance.sh" \
        "$REPO_ROOT/slurm_templates/virome_slurm_template.sh" "provenance.sh"
    ts_assert_contains "l2: virome template captures software versions" \
        "$REPO_ROOT/slurm_templates/virome_slurm_template.sh" "capture_software_versions"
    ts_assert_contains "l2: virome template generates provenance README on exit" \
        "$REPO_ROOT/slurm_templates/virome_slurm_template.sh" "generate_provenance_readme"
    ts_assert_contains "l2: virome template wraps invocation with run_logged" \
        "$REPO_ROOT/slurm_templates/virome_slurm_template.sh" "run_logged"
    ts_assert_contains "l2: virome template enables Nextflow trace/report" \
        "$REPO_ROOT/slurm_templates/virome_slurm_template.sh" "with-trace"

    rm -rf "$tmpdir"
}

# ── Layer 3: full SLURM execution ─────────────────────────────────────────────

l3_fixture_virome() {
    if [[ ! -d "$_VIROME_SYNTHETIC_DIR" ]]; then
        echo "Synthetic FASTQ dir not found: $_VIROME_SYNTHETIC_DIR" >&2
        echo "Run: $REPO_ROOT/test_data/fixtures/generate_virome_synthetic.sh $(dirname "$_VIROME_SYNTHETIC_DIR")" >&2
        return 1
    fi

    local count
    count=$(find "$_VIROME_SYNTHETIC_DIR" -name "*_1.fastq.gz" | wc -l)
    if [[ "$count" -eq 0 ]]; then
        echo "No *_1.fastq.gz files in $_VIROME_SYNTHETIC_DIR" >&2
        return 1
    fi

    if [[ ! -d "$_VIROME_TINY_KRAKEN2" ]]; then
        echo "Tiny Kraken2 DB not found: $_VIROME_TINY_KRAKEN2" >&2
        echo "A tiny Kraken2 DB is required for Layer 3 virome testing." >&2
        echo "Build one with kraken2-build --special viral --db $_VIROME_TINY_KRAKEN2" >&2
        return 1
    fi

    if [[ ! -d "$_VIROME_TINY_STAR" ]]; then
        echo "Tiny STAR index not found: $_VIROME_TINY_STAR" >&2
        return 1
    fi

    return 0
}

l3_submit_virome() {
    local test_dir="$TEST_SCRATCH/virome"
    local outdir="$test_dir/results"
    local ss_file="$test_dir/samplesheet.csv"
    local cfg="$test_dir/config_virome.yaml"
    mkdir -p "$test_dir"

    # Build samplesheet CSV from synthetic FASTQs
    echo "sample,fastq_r1,fastq_r2" > "$ss_file"
    for r1 in "$_VIROME_SYNTHETIC_DIR"/*_1.fastq.gz; do
        [[ -f "$r1" ]] || continue
        local r2="${r1/_1.fastq.gz/_2.fastq.gz}"
        if [[ -f "$r2" ]]; then
            local sample
            sample=$(basename "$r1" _1.fastq.gz)
            echo "$sample,$r1,$r2" >> "$ss_file"
        fi
    done

    cat > "$cfg" <<YAML
project_name: Virome-L3-Test
samplesheet: $ss_file
outdir: $outdir
star_index: $_VIROME_TINY_STAR
kraken2_db: $_VIROME_TINY_KRAKEN2
adapters: $REPO_ROOT/containers/virome/assets/NexteraPE-PE.fa
container_dir: $REPO_ROOT/containers/virome
trim_headcrop: 0
trim_leading: 3
trim_trailing: 3
trim_slidingwindow: "4:15"
trim_minlen: 36
kraken2_confidence: 0.1
min_reads_per_taxon: 1
YAML

    local job_id
    job_id=$("$REPO_ROOT/bin/tjp-launch" virome --dev --config "$cfg" 2>/dev/null \
        | grep -oP '(?<=job )\d+' | tail -1)
    echo "$job_id"
}

l3_validate_virome() {
    local test_dir="$TEST_SCRATCH/virome"
    local outdir="$test_dir/results"

    ts_assert_exists "virome: output directory exists" "$outdir"
    ts_assert_exists "virome: results/ directory"      "$outdir/results"
    ts_assert_exists "virome: multiqc/ directory"      "$outdir/multiqc"

    # Reproducibility artifacts live in the WORK run dir ($RUN_DIR)
    local work_run
    work_run=$(ls -1td "$WORK_ROOT/pipelines/virome/runs"/*/ 2>/dev/null | head -1)

    if [[ -z "$work_run" ]]; then
        ts_assert_exists "virome: WORK run directory exists" "$WORK_ROOT/pipelines/virome/runs"
        return
    fi

    ts_assert_exists   "virome: juno_environment.json"     "$work_run/juno_environment.json"
    ts_assert_exists   "virome: slurm_template_used.sh"    "$work_run/slurm_template_used.sh"
    ts_assert_nonempty "virome: pipeline_source.tar.gz"    "$work_run/pipeline_source.tar.gz"
    ts_assert_nonempty "virome: invocation.log"            "$work_run/invocation.log"
    ts_assert_contains "virome: invocation.log records nextflow run" \
                       "$work_run/invocation.log" "nextflow run"
    ts_assert_exists   "virome: nextflow_logs/trace.txt"   "$work_run/nextflow_logs/trace.txt"
    ts_assert_fail     "virome: juno_environment.json end_time populated" \
                       bash -c "grep -q '\"end_time\": null' '$work_run/juno_environment.json'"
    ts_assert_fail     "virome: manifest submodule commit resolved" \
                       bash -c "grep -q '\"pipeline_submodule_commit\": \"unknown\"' '$work_run/manifest.json'"

    # Provenance README artifacts
    ts_assert_exists   "virome: CONSOLE_LOG.txt"            "$work_run/CONSOLE_LOG.txt"
    ts_assert_nonempty "virome: CONSOLE_LOG.txt"            "$work_run/CONSOLE_LOG.txt"
    ts_assert_exists   "virome: software_versions.txt"      "$work_run/software_versions.txt"
    ts_assert_contains "virome: software_versions.txt has fastqc entry" \
                       "$work_run/software_versions.txt" "fastqc:"
    ts_assert_exists   "virome: PROVENANCE_README.md"       "$work_run/PROVENANCE_README.md"
    ts_assert_nonempty "virome: PROVENANCE_README.md"       "$work_run/PROVENANCE_README.md"
    ts_assert_contains "virome: PROVENANCE_README.md has Hyperion banner" \
                       "$work_run/PROVENANCE_README.md" "H Y P E R I O N"
}

l3_teardown_virome() {
    :
}
