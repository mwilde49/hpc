# Contributing to the TJP HPC Pipeline Framework

This guide covers how to propose changes, add new pipelines, maintain submodules, and cut releases. Read this before opening a PR or adding a pipeline.

---

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [Branch Conventions](#2-branch-conventions)
3. [Adding a New Pipeline](#3-adding-a-new-pipeline)
4. [Test Module Requirements](#4-test-module-requirements)
5. [Modifying Existing Pipelines](#5-modifying-existing-pipelines)
6. [Submodule Releases](#6-submodule-releases)
7. [PR Checklist](#7-pr-checklist)
8. [Release Process](#8-release-process)
9. [Documentation Standards](#9-documentation-standards)

---

## 1. Getting Started

```bash
git clone --recurse-submodules https://github.com/mwilde49/hpc.git
cd hpc
```

All development happens on `master`. There is no separate `main`/`develop` split — the repo is a group tool, not a public library. Deploy to Juno with `git pull && git submodule update --init --recursive`.

---

## 2. Branch Conventions

| Branch pattern | Use for |
|----------------|---------|
| `feat/<name>` | New pipeline or major new feature |
| `fix/<name>` | Bug fix |
| `docs/<name>` | Documentation-only changes |
| `chore/<name>` | Dependency bumps, submodule updates, cleanup |

Keep branches short-lived. Merge to `master` and delete when done.

---

## 3. Adding a New Pipeline

Follow the checklist that matches your pipeline's execution model. The central registry is `bin/lib/common.sh` — add your pipeline there first, and everything else follows.

### Pattern A: Inline (addone model)

For pipelines where code lives directly in this repo.

- [ ] Create `pipelines/<name>/` with pipeline script and README
- [ ] Add or extend a container definition in `containers/`; rebuild `.sif`
- [ ] Add `slurm_templates/<name>_slurm_template.sh`
- [ ] Wire in the reproducibility framework (`bin/lib/repro.sh`) — see below
- [ ] Add `templates/<name>/config.yaml` with `__USER__`/`__SCRATCH__`/`__WORK__` placeholders and Titan block
- [ ] Add `templates/<name>/samplesheet.csv` if batch mode is needed
- [ ] Add `_SAMPLESHEET_REQUIRED_COLS[<name>]` in `bin/lib/samplesheet.sh`
- [ ] Add `_validate_<name>()` in `bin/lib/validate.sh`; wire it into the dispatcher
- [ ] Add `[<name>]` to `PIPELINE_CONTAINERS` and `PIPELINE_TEMPLATES` in `bin/lib/common.sh`
- [ ] Add `<name>` to `KNOWN_PIPELINES` in `bin/lib/common.sh`
- [ ] Add batch dispatch logic in `bin/tjp-batch` (per-row or per-sheet)
- [ ] Add config sections to `ONBOARDING.md`, `USER_GUIDE.md`, `COMMAND_REFERENCE.md`
- [ ] Add pipeline row to all pipeline tables in all docs
- [ ] `.sif` files are NOT in git — build locally, transfer via `scp`

### Pattern B: Submoduled (bulkrnaseq/psoma model)

For pipelines with their own container repo.

- [ ] `git submodule add <url> containers/<name>/`
- [ ] Pin to a release tag: `cd containers/<name> && git checkout v1.0.0 && cd ..`
- [ ] `git add .gitmodules containers/<name> && git commit -m "chore: add <name> submodule at v1.0.0"`
- [ ] All Pattern A steps (SLURM template, config template, samplesheet, validator, registry, docs)
- [ ] Create `<NAME>_HPC_GUIDE.md` at repo root
- [ ] Note the submodule pin in `PIPELINE_DESIGN_REVIEW.md`

### Pattern C: Native (cellranger model)

For tools that manage their own execution without a container.

- [ ] `git submodule add <url> containers/<name>/` (wrappers + validators)
- [ ] Install tool from tarball to `/groups/tprice/opt/<name>-<version>/`
- [ ] Create symlink: `ln -sfn /groups/tprice/opt/<name>-<version> /groups/tprice/software/<name>`
- [ ] Add `[<name>]` to `PIPELINE_TOOL_PATHS` in `bin/lib/common.sh`
- [ ] Add `<name>` to `NATIVE_PIPELINES` in `bin/lib/common.sh`
- [ ] All other Pattern A steps

### Wiring in the reproducibility framework (all patterns)

Every SLURM template — inline, submoduled, or native — must source `bin/lib/repro.sh`
and call its three hooks so the run directory gets `juno_environment.json` and
`invocation.log` like every other pipeline. Copy the pattern from
`slurm_templates/addone_slurm_template.sh`:

```bash
source "$PROJECT_ROOT/bin/lib/repro.sh"
...
capture_juno_env "$RUN_DIR"
trap 'finalize_juno_env "$RUN_DIR" "$?"' EXIT
...
run_logged "${RUN_DIR:+$RUN_DIR/invocation.log}" \
    apptainer exec ... $CONTAINER ...
```

- [ ] `source "$PROJECT_ROOT/bin/lib/repro.sh"` near the top of the template
- [ ] `capture_juno_env "$RUN_DIR"` called right after `RUN_DIR` is parsed, before any pre-flight checks
- [ ] `trap 'finalize_juno_env "$RUN_DIR" "$?"' EXIT` set immediately after the `capture_juno_env` call
- [ ] The actual pipeline invocation wrapped in `run_logged "${RUN_DIR:+$RUN_DIR/invocation.log}" ...` (for SQANTI3-style multi-job orchestrators, wrap each `sbatch` call individually)
- [ ] If the pipeline is Nextflow-based, add `-with-trace -with-report -with-timeline -with-dag` writing into `$RUN_DIR/nextflow_logs/` (see the bulkrnaseq/psoma/virome/wf-transcriptomes templates for the exact flags)

No action needed for `manifest.sh` — `snapshot_slurm_template`/`snapshot_pipeline_source`
run automatically for every pipeline in the registry at manifest-generation time
(before the job is submitted), as long as the pipeline was added to
`bin/lib/common.sh` per the steps above.

### After adding any pipeline

- [ ] Run `bin/check-docs-freshness` and fix any reported gaps
- [ ] Create `bin/lib/tests/test_<name>.sh` (see §4 below)
- [ ] Run `tjp-test-suite --layer 1 --pipeline <name>` and confirm it passes

---

## 4. Test Module Requirements

Every pipeline in `KNOWN_PIPELINES` must have a corresponding test module at
`bin/lib/tests/test_<name>.sh` (dashes converted to underscores, e.g.
`cellranger-multi` → `test_cellranger_multi.sh`). The module is sourced by
`tjp-test-suite` and must define these six functions:

| Function | Layer | Purpose |
|---|---|---|
| `l1_<name>()` | 1 | Offline: assert template/schema/validator correctness |
| `l2_<name>()` | 2 | Dry-run: assert registry/SLURM wiring (no job submission) |
| `l3_fixture_<name>()` | 3 | Return 0 if test data ready, 1 if not (print reason to stderr) |
| `l3_submit_<name>()` | 3 | Submit SLURM job; echo job ID to stdout |
| `l3_validate_<name>()` | 3 | Call `ts_assert_*` on job outputs |
| `l3_teardown_<name>()` | 3 | Post-run cleanup (may be a no-op) |

Plus two module-level variables:

```bash
PIPELINE_NAME="<name>"    # matches KNOWN_PIPELINES entry
L3_SKIP=false             # set true if no minimal test data can ever exist
L3_SKIP_REASON=""         # human-readable reason shown in suite output
```

Copy `bin/lib/tests/test_addone.sh` as a starting template. The suite runner
auto-discovers modules by name, so no registration step is needed.

---

## 5. Modifying Existing Pipelines

**Config key changes:** If you add or remove required keys, update the validator in `validate.sh`, the config template in `templates/<name>/config.yaml`, and all documentation tables.

**SLURM resource changes:** Update `slurm_templates/<name>_slurm_template.sh`, `PIPELINE_DESIGN_REVIEW.md` (resources table), and `DEVELOPER_ONBOARDING.md` (Layer 2 table).

**Submodule updates:** See §6.

**Version bumps:** See §8.

---

## 6. Submodule Releases

### Updating a submodule to a new release

```bash
# 1. Pull the new tag in the submodule
cd containers/<name>
git fetch origin
git checkout v2.0.0

# 2. Update the parent pointer
cd ../..
git add containers/<name>
git commit -m "chore(<name>): bump submodule to v2.0.0"

# 3. Update version pins in documentation
#    - README.md pipeline table
#    - HPC_SYSTEM_MAP.md filesystem listing
#    - PIPELINE_DESIGN_REVIEW.md submodule versioning table
#    - DEVELOPER_ONBOARDING.md key files reference table
```

### Tagging a submodule release

Before bumping a submodule's pin in the parent, the submodule should have a tag at the commit you're pinning to:

```bash
cd containers/<name>
git tag v2.0.0 -m "Release description"
git push origin v2.0.0
```

### Stable framework snapshots

Before major development work, tag the parent at its current state so you have a rollback point:

```bash
git tag v6.x.0 -m "Stable pre-development snapshot"
git push origin v6.x.0
```

To restore: `git checkout v6.x.0 && git submodule update --init --recursive`

---

## 7. PR Checklist

Before merging any PR to `master`:

**Code quality**
- [ ] `bin/check-docs-freshness` passes (no pipeline count drift)
- [ ] Config validator handles all new keys
- [ ] Template config has comments for all fields
- [ ] New SLURM templates source `bin/lib/repro.sh` and wire `capture_juno_env`/`finalize_juno_env`/`run_logged` (see §3)

**Testing**
- [ ] Create `bin/lib/tests/test_<name>.sh` with all six functions (see §4 below)
- [ ] `tjp-test-suite --layer 1 --pipeline <name>` passes (offline validation)
- [ ] `tjp-test-suite --layer 2 --pipeline <name>` passes (registry/SLURM wiring)
- [ ] `tjp-test-suite --layer 3 --pipeline <name>` submits and completes on dev partition

**Documentation**
- [ ] Pipeline appears in all pipeline tables across all docs
- [ ] `COMMAND_REFERENCE.md` has a §6.x section for the pipeline
- [ ] `ONBOARDING.md` and `USER_GUIDE.md` have config field tables
- [ ] `PIPELINE_DESIGN_REVIEW.md` matrices include the new pipeline
- [ ] `MASTER_DOCU.md` pipeline×document matrix updated
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]`

**Submodules**
- [ ] Any new submodule is pinned to a tag (not a branch or HEAD)
- [ ] `.gitmodules` shows the correct URL
- [ ] Version pins are updated in docs if submodule was bumped

---

## 8. Release Process

Releases are tagged on `master`. Version scheme: `v<MAJOR>.<MINOR>.<PATCH>`

- **MAJOR** — breaking changes to config format, pipeline removal, or incompatible workflow changes
- **MINOR** — new pipeline, new CLI feature, or significant behavior change
- **PATCH** — bug fix, documentation update, dependency bump

### Steps

```bash
# 1. Move CHANGELOG entries from [Unreleased] to the new version
vi CHANGELOG.md

# 2. Update version strings
#    - README.md: **Version:** line
#    - COMMAND_REFERENCE.md: Version header
#    - TJP_HPC_COMPLETE_GUIDE.md: Version line
#    - MASTER_DOCU.md: Version line
#    - CLAUDE.md: if mentioned

# 3. Commit
git add -A
git commit -m "chore: release vX.Y.Z"

# 4. Tag parent and submodules that changed
git tag vX.Y.Z -m "Release vX.Y.Z — brief description"
git push origin master vX.Y.Z
# Tag any submodules that changed in this release
```

---

## 9. Documentation Standards

- **No bare commit messages in changelogs** — summarize the user-facing effect
- **All new config keys get comments** in the template config: `# Required`, `# Optional`, `# Default: X`, or a brief description inline
- **Pipeline tables are additive** — never remove a row from a pipeline table; instead mark deprecated pipelines as `(deprecated)` until they are fully removed and the version is bumped
- **Submodule docs** — each submodule repo has its own `CLAUDE.md` and `README.md`; keep those in sync when you change the framework's expectations of that submodule
