# Changelog

All notable changes to this project are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [v7.3.1] — 2026-07-23

### Added
- `bin/tjp-test-local`: runs a SLURM template's body directly via `bash`, bypassing `sbatch`/SLURM entirely — for smoke-testing pipeline scaffolding and the provenance framework without Juno access. Sandboxes `PROJECT_ROOT`/`SCRATCH_ROOT`/`WORK_ROOT` under `~/.tjp_local_test/` (`PROJECT_ROOT` symlinked straight to the real checkout), patches only the 3 hardcoded path lines in a disposable copy of the target template (diffed to confirm nothing else changed), and reports which provenance artifacts came out the other end.
- `test_data/fixtures/generate_tier0_reference.sh`: generates a tiny synthetic reference FASTA/GTF, HISAT2 (psoma) and STAR (bulkrnaseq) indexes, and a placeholder exclude BED (bulkrnaseq's `filter_samples` process requires at least one of `exclude_bed_file_path`/`blacklist_bed_file_path` to be set — discovered by actually running the pipeline against this fixture). Closes a long-standing gap where `test_psoma.sh`/`test_bulkrnaseq.sh` required a tiny reference index that had no generator — only a comment saying "build one by hand."

### Fixed
- **`psoma`/`bulkrnaseq` SLURM templates called `capture_software_versions` with the pre-v7.3.0 argument order** (`<run_dir> <container> <pipeline>` instead of the current `<run_dir> <pipeline> <primary>`) — found by actually running both templates locally via the new `tjp-test-local` harness against real (stub) containers, not by unit-testing `provenance.sh`'s functions in isolation. Since `$pipeline` received a container path string instead of `"psoma"`/`"bulkrnaseq"`, it matched no case arm in the dispatcher and silently no-opped — every psoma/bulkrnaseq run since v7.3.0 was generated with **no `software_versions.txt`** and no error indicating why. The v7.3.0 changelog entry claiming "the real templates were always correct, only the CONTRIBUTING.md example was wrong" was itself wrong — only `CONTRIBUTING.md`'s example was fixed at the time; these two real call sites were missed. Strengthened `test_psoma.sh`/`test_bulkrnaseq.sh`'s L2 checks to assert the exact call (not just that the function name appears somewhere in the file) so this class of regression fails offline next time.
- `test_data/fixtures/generate_rnaseq_synthetic.sh`: the random-sequence generator (`tr -dc 'ACGT' < /dev/urandom | head -c "$rlen"`) aborted on its very first read under `set -o pipefail` — `head` closing the pipe early after reading `$rlen` bytes sends `tr` SIGPIPE (exit 141), which pipefail surfaces as the command substitution's exit status, tripping `set -e`. This has apparently never worked; found while generating tier-0 fixtures for the first time. Fixed with `{ tr ... || true; } | head ...`; same fix applied to the equivalent line in the new `generate_tier0_reference.sh`.

## [v7.3.0] — 2026-07-23

### Added
- **Provenance README rolled out to all remaining eleven pipelines** (`addone`, `virome`, `sqanti3`, `wf-transcriptomes`, `dconvatac`, `dconvatac-gpu`, `cellranger`, `cellranger-mkfastq`, `cellranger-multi`, `spaceranger`, `xeniumranger`) — every pipeline's SLURM template now sources `bin/lib/provenance.sh` and generates `CONSOLE_LOG.txt`, `software_versions.txt`, and `PROVENANCE_README.md`. `capture_software_versions` gained four new architecture-specific strategies beyond the original single-container probe:
  - **Multi-container** (`virome`) — loops over each per-process `.sif` (`fastqc.sif`, `star.sif`, `trimmomatic.sif`, `kraken2.sif`, `python.sif`, `multiqc.sif`), probing each one's own primary tool.
  - **Native, no container** (`cellranger`, `cellranger-mkfastq`, `cellranger-multi`, `spaceranger`, `xeniumranger`) — sources `containers/10x/lib/10x_common.sh`'s own `find_10x_binary`/`get_10x_version` in a guarded subshell to resolve the exact binary the wrapper script would use, correctly honoring a config-level `tool_path:` override rather than always reporting the registry default.
  - **Nextflow-managed, externally-defined containers** (`wf-transcriptomes`) — captures only the `nextflow` binary's own version; per-process containers are pulled and managed by the external `epi2me-labs/wf-transcriptomes` workflow at run time, not declared anywhere in this repo, so probing them directly would require vendoring or parsing a third-party repo's Nextflow config — out of scope, and noted as such in the generated report rather than silently omitted.
  - **Multi-job orchestrator** (`sqanti3`) — probes the shared container from the lightweight orchestrator job only; the 4 stage jobs it dispatches (qc/refqc/filter/rescue) run from scripts in the `containers/sqanti3` submodule, a separate repo, so per-stage instrumentation remains out of scope (same limit already documented for `juno_environment.json` since v7.0.0).
- `generate_provenance_readme` gained a `native:<tool>` convention for its `<container>` argument (relabels the summary table's "Container"/"Container checksum" rows to "Tool"/"Tool version" for pipelines with no Apptainer container), and now skips the "Per-step tool invocations" subsection entirely — rather than printing a misleading "trace.txt not found" message — for the 7 pipelines that never use Nextflow (`addone`, `dconvatac`, `dconvatac-gpu`, `sqanti3`, and the 5 10x pipelines).
- `_run_guarded` in `bin/lib/provenance.sh`: `capture_software_versions` and `generate_provenance_readme` now run their real work inside a `set +e` subshell. Two SLURM templates (`sqanti3`, `wf-transcriptomes`) already run under `set -euo pipefail` — without this guard, a missing tool, an empty `grep` match, or any other non-zero exit inside this file's best-effort instrumentation could have aborted the pipeline run it was trying to document. `start_console_log` is the one function that can't run in a subshell (it modifies the current shell's file descriptors via `exec`) and instead saves/restores `set -e` manually around its own `exec` call.
- Layer 2 (offline wiring) `tjp-test-suite` coverage for all eleven newly-wired pipelines, plus Layer 3 (post-run artifact) coverage for the ten that run L3 (`xeniumranger` and `dconvatac`/`dconvatac-gpu` skip L3 for pre-existing fixture-availability reasons unrelated to this change).
- `CONTRIBUTING.md` §3: rewrote the provenance-README wiring guide with an architecture-selection table (single-container / multi-container / native / Nextflow-managed-external / orchestrator) now that all five patterns exist in the codebase, and documented the `set -e` safety guarantee so future pipeline authors don't need to re-derive it.

### Fixed
- `CONTRIBUTING.md`'s v7.2.0-era wiring example had `capture_software_versions "$RUN_DIR" "$CONTAINER" "<pipeline>"` — backwards from the actual function signature, `capture_software_versions <run_dir> <pipeline> <primary> [secondary]`. The real templates were always correct; only the doc example had the argument order swapped. Fixed, and called out explicitly in the checklist so it doesn't happen again.

## [v7.2.0] — 2026-07-23

### Added
- **Provenance README** (`bin/lib/provenance.sh`), wired into `psoma` and `bulkrnaseq` so far (the other eleven pipelines still need this — see `CONTRIBUTING.md` §3):
  - `start_console_log` tees the full stdout+stderr transcript of every run into `CONSOLE_LOG.txt` from job start (including pre-flight failures), alongside SLURM's own split `slurm_<jobid>.out`/`.err`.
  - `capture_software_versions` queries real per-tool version strings (HISAT2, STAR, Trimmomatic, Samtools, Sambamba, Bedtools, StringTie, HTSeq, Qualimap, R/Rsubread, Python/pandas, Nextflow, Java) live from the run's own container into `software_versions.txt`, reusing the exact commands each container's own `.def` `%test` block already runs — necessary because `psomagen.def`/`bulkrnaseq.def` install tools via `mamba install` with no version pins, so the built `.sif` is the only authoritative source.
  - `generate_provenance_readme` assembles `PROVENANCE_README.md` — a single Hyperion-branded report combining run status/timing, the full `config.yaml`, the software-versions table, the exact pipeline invocation, one representative resolved shell command per Nextflow process (pulled from that task's `.command.sh`, deduplicated across samples), and a signpost table to every other run-directory artifact. Runs from the `EXIT` trap on both success and failure.
- Layer 2 (offline wiring) and Layer 3 (post-run artifact) `tjp-test-suite` coverage for the new provenance artifacts in `test_psoma.sh`/`test_bulkrnaseq.sh`.

## [v7.1.0] — 2026-07-23

### Added
- `templates/dconvatac-gpu/config.yaml` and `samplesheet.csv` — the GPU variant had no config/samplesheet templates of its own; `tjp-setup` was silently scaffolding nothing for it.
- `_validate_dconvatac_gpu()` in `bin/lib/validate.sh` — the dispatcher previously fell back to the CPU validator, so a `dconvatac-gpu` config with `use_gpu: false` (or unset) validated cleanly and would have wasted an A30 allocation running CPU-only. Now delegates to `_validate_dconvatac` plus enforces `use_gpu: true`.
- `bin/tjp-batch` support for `cellranger-mkfastq` and `cellranger-multi` (`_gen_cellranger_mkfastq_config`, `_gen_cellranger_multi_config`) — both were documented in COMMAND_REFERENCE.md/ONBOARDING.md as batch-capable but were never wired into `_BATCH_PER_ROW` or the dispatcher; `tjp-batch cellranger-multi ...` would `die "Batch submission not supported"`. Cell Ranger Multi's per-row `libraries_file` (a small CSV of `fastq_id,fastqs,feature_types`) is translated into the generated config's inline YAML `libraries:` block entirely within `tjp-batch` — no submodule changes needed. Also fixed a latent column collision in the shared per-row loop and `_titan_ids_from_row`: both pipelines reuse `run_id`/`sample_id` as their own primary-key column, which would otherwise have been misread as Titan RUN/SMP identifiers.
- `bin/tjp-setup` now scaffolds config + samplesheet for `cellranger-mkfastq`, `cellranger-multi`, `dconvatac`, and `dconvatac-gpu` — previously only `bulkrnaseq` through `wf-transcriptomes`/10x-count/spaceranger/xeniumranger were scaffolded; these four got an empty `runs/` directory and nothing else.

### Fixed
- **Submodule pins**: `containers/10x`, `containers/dconvatac`, and `containers/sqanti3` are 1, 4, and 6 commits ahead of their last tag respectively (untagged) — flagged across README.md, PIPELINE_DESIGN_REVIEW.md, HPC_SYSTEM_MAP.md, MASTER_DOCU.md, and DEVELOPER_ONBOARDING.md with the actual commit drift noted. New tags are **not** cut as part of this pass — left for a deliberate release decision.
- `templates/cellranger-multi/config.yaml` shipped with `fastq_path`/`sample_name` library fields, but `containers/10x/bin/cellranger-multi-run.sh` only reads `fastq_id`/`fastqs` — the template as shipped would fail at launch. Fixed the template and its `feature_types` enum comment (was missing `VDJ-T-GD`/had the old `CRISPR Screen` name instead of `CRISPR Guide Capture`).
- `capture_juno_env` was called *after* an early pre-flight exit in three SLURM templates (`addone`, `virome`, `wf_transcriptomes`) — a job that failed validation (bad config arg, missing nextflow, missing required arg) wrote no `juno_environment.json` at all, defeating the v7.0.0 design goal that "even a job that fails pre-flight still gets a record." Reordered so provenance capture and the `EXIT` trap are always set up first; worst case was `virome`, where the check ran before `repro.sh` was even sourced.
- `slurm_templates/wf_transcriptomes_slurm_template.sh`'s own fallback default for `wf_version` was `v1.7.2` — stale against `templates/wf-transcriptomes/config.yaml` and `tjp-batch`'s generator, both already on `v2.3.0`. A config that omitted `wf_version` would have silently run an old workflow release. Fixed to `v2.3.0`.
- `bin/check-docs-freshness`: fixed a false-positive "dconvatac-gpu missing from README.md pipeline table" (the checker's substring match doesn't know "dconvatac" → "DeconvATAC" is the same pipeline), and a false-positive "count pattern not found" warning on DEVELOPER_ONBOARDING.md (its number-word matcher didn't recognize "thirteen").
- `CONTRIBUTING.md`: pipeline checklists (§3) and the PR checklist (§7) didn't mention the v7.0.0 reproducibility framework — new pipelines could ship without `repro.sh` wired into their SLURM template. Added explicit steps and the `addone` template as a reference pattern. Also fixed its Table of Contents, which was one section behind after §4 (Test Module Requirements) was added without renumbering §5-§9, plus one stale internal `§7` cross-reference that should have pointed at §6.
- **Documentation now matches actual config/code across the board** — SQANTI3's YAML keys were documented as `ref_gtf`/`ref_fasta` (those are only valid as samplesheet CSV columns; the real YAML keys are camelCase `refGTF`/`refFasta`), plus wrong `filter_mode`/`rescue_mode` enums and a missing required `sample` field; wf-transcriptomes was missing required `sample`/`outdir` fields and had the same stale `wf_version` default noted above; USER_GUIDE.md's DeconvATAC field table was missing `spatial_batch_key`/`spatial_batch_size`, its Virome field table listed a nonexistent `ref_genome` key and was missing most real fields, and it had stale Cell Ranger/Space Ranger reference paths with an extra subdirectory that doesn't exist; ONBOARDING.md had the same Virome field-table problem and no DeconvATAC section at all (not even in the `tjp-launch` command list). Fixed across ONBOARDING.md, COMMAND_REFERENCE.md, and USER_GUIDE.md.
- **DEVELOPER_ONBOARDING.md** claimed execution-flow coverage for "all thirteen pipelines" but had no DeconvATAC/DeconvATAC GPU walkthrough, no DeconvATAC rows in its Pipeline Comparison Matrix or Key Files Reference tables (also missing Cell Ranger mkfastq/Multi from the matrix), and a submodule table with several wrong pins (psoma listed as v1.0.0, actually v2.0.2; bulkrnaseq listed as v1.0.0, actually v1.0.1; virome's repo given as `mwilde49/virome` instead of `mwilde49/virome-pipeline`; sqanti3 listed as just "current"; no dconvatac row). Added the missing sections/rows and corrected every pin.
- **MASTER_DOCU.md**: stale CHANGELOG coverage claim ("through v6.1.0"), stale submodule map (sqanti3/10x tags, missing dconvatac row), Pipeline × Document matrix missing DeconvATAC/DeconvATAC GPU rows, and three Quick Navigation links pointing at the wrong document-inventory item after a numbering shift.
- **PIPELINE_DESIGN_REVIEW.md**: submodule table wrongly marked 10x/longreads as cleanly tagged and had no dconvatac row; all three Pipeline Comparison Matrix tables (§1) were missing DeconvATAC/DeconvATAC GPU entirely; SQANTI3's input descriptor had the same `ref_gtf`/`ref_fasta` naming bug noted above.
- **HPC_SYSTEM_MAP.md**: SLURM resource table was missing Cell Ranger mkfastq/Multi and both DeconvATAC variants, and had wrong CPU/RAM values for BulkRNASeq/Psoma (said 20 CPU/64GB; SLURM templates actually request 40 CPU/128GB).
- **docs/architecture.md**: both Mermaid diagrams and their surrounding prose said "eight pipelines" and only drew 9 pipeline nodes — missing Cell Ranger mkfastq/Multi and both DeconvATAC variants. Updated prose to "thirteen" and added all four missing nodes to both diagrams.
- Version-string drift: `CELLRANGER_GUIDE.md` said framework v6.1.0 (six releases stale); `README.md`'s directory-tree ASCII art disagreed with its own pipeline table 20 lines above (v1.0.0/v2.0.0/v1.4.0 vs. the table's correct v1.0.1/v2.0.2/v1.5.0); `TJP_HPC_COMPLETE_GUIDE.md`'s directory tree had the same stale bulkrnaseq pin; `CLAUDE.md` said 9 samplesheet templates, actually 12.

## [v7.0.0] — 2026-07-20

### Added
- **Reproducibility & provenance logging framework**, wired into all 13 SLURM templates via a new shared library (`bin/lib/repro.sh`):
  - `capture_juno_env` / `finalize_juno_env` write `juno_environment.json` into every run directory — SLURM job ID, node, partition, allocated CPUs/mem, GPU/gres, requested time limit, start/end time, duration, exit code, and best-effort `sacct` accounting (state, elapsed, MaxRSS).
  - `run_logged` records the exact, fully-quoted, resolved command line for every pipeline invocation into `invocation.log` before running it.
  - For the four Nextflow-based pipelines (BulkRNASeq, Psoma, Virome, wf-transcriptomes), `-with-trace/-report/-timeline/-dag` are now enabled, writing per-process resource usage and an interactive HTML report directly into `$RUN_DIR/nextflow_logs/`.
  - The SQANTI3 orchestrator logs all four `sbatch` DAG-stage submissions (exact resources/configs per stage) to `invocation.log`; per-stage node capture is out of scope (those stage scripts live in the `containers/sqanti3` submodule).
- `bin/lib/manifest.sh`: `snapshot_slurm_template` and `snapshot_pipeline_source` freeze an exact copy of the SLURM template and pipeline source (`git archive` of the relevant submodule, or `pipelines/addone/` for the inline demo) into every run directory as `slurm_template_used.sh` and `pipeline_source.tar.gz`. `manifest.json` gained `pipeline_submodule_commit` — the actual submodule commit SHA at run time, which the hpc superproject's own `git_commit` field could not previously tell you.
- Every pipeline's `tjp-test-suite` module gained matching Layer 1 (offline manifest-snapshot verification, no SLURM needed), Layer 2 (repro.sh wiring verification), and Layer 3 (runtime artifact assertions) coverage for the new logging.

### Fixed
- **`bin/lib/test_framework.sh`**: `_ts_update_layer_status` used `${!varname[$pipeline]}` for indirect associative-array lookup — under `set -u`/`set -e` this silently killed the *entire* `tjp-test-suite` run after the first one or two assertions for any pipeline, any layer, because bash does not resolve that syntax as "array named by `$varname`, indexed by `$pipeline`". Non-verbose mode's `2>/dev/null` hid both the crash and the error message. This bug has existed since the test suite was introduced (v6.2.0) — `tjp-test-suite` has almost certainly never completed a full run for any pipeline before this fix. Fixed with two-step indirection and explicit `return 0` so a "no status change needed" outcome no longer reads as failure.
- `run_logged`'s own log line was written to stdout, which corrupts any caller doing `JOB_ID=$(sbatch ...)` (needed for the SQANTI3 orchestrator's 4-stage submission). Moved to stderr.
- `bin/lib/manifest.sh`: `snapshot_pipeline_source`'s submodule detection checked for `.git` as a directory, but git submodules use a `.git` *file* (gitlink) pointing into the superproject's `.git/modules/` — the check always failed, silently skipping the source snapshot for every submoduled pipeline. Fixed with `git -C <dir> rev-parse --git-dir`.
- `bulkrnaseq_slurm_template.sh`: stage-out archiving now dereferences symlinks (`rsync -aL`) — BulkRNASeq's numbered stage-output directories are symlinked into the shared UTDal repo rather than being real per-run directories, so plain `rsync -a` copied the symlinks (a few KB) instead of the data they point to, producing an archive that verified successfully but contained none of the actual pipeline output. After a verified archive, the shared repo's stage-output directories are now purged so the next run's symlink loop can't re-link stale samples from unrelated past runs into a new run (this happened in practice on 2026-07-13).
- `sqanti3` submodule bumped to pick up the RColorConesa filter fixes and the wf-transcriptomes outdir guard.

## [v6.4.0] — 2026-06-29

### Fixed
- wf-transcriptomes SLURM template: added an exit-on-error check when `outdir` is unset, non-absolute, or contains unexpanded `${...}` variables — this misconfiguration previously wrote large amounts of output into `~/output`, filling the home quota, before failing much later.

### Changed
- Documentation catch-up pass across `COMMAND_REFERENCE.md`, `DEVELOPER_ONBOARDING.md`, `HPC_SYSTEM_MAP.md`, `MASTER_DOCU.md`, `ONBOARDING.md`, `PIPELINE_DESIGN_REVIEW.md`, `README.md`, `TJP_HPC_COMPLETE_GUIDE.md`, and `USER_GUIDE.md` to reflect the DeconvATAC pipeline and `tjp-test-suite` (both shipped in v6.2.0/v6.3.0 without a changelog entry).

## [v6.3.0] — 2026-06-15

### Added
- **DeconvATAC pipeline**: spatial ATAC deconvolution via Cell2Location, submoduled at `containers/dconvatac/` (`mwilde49/dconvatac`). Python pipeline (not Nextflow) run inside Apptainer — both the container definition and pipeline script live in the submodule. Two registered pipelines: `dconvatac` (CPU, `normal` partition) and `dconvatac-gpu` (A30 GPU, `--nv` + `--gres=gpu:nvidia_a30:1`). Wired into the pipeline registry, validator, `tjp-batch` (per-row), and config/samplesheet templates.
- `dconvatac` gained `spatial_batch_key` support for multi-section spatial data.

## [v6.2.0] — 2026-05-19

### Added
- **`tjp-test-suite`**: a three-layer test harness for every registered pipeline — Layer 1 (offline config/schema/validator checks, ~30s), Layer 2 (SLURM template + registry wiring checks, no job submission, ~2min), Layer 3 (full SLURM execution on the dev partition using minimal test fixtures, ~20–40min). Test modules live in `bin/lib/tests/test_<pipeline>.sh`, one per registered pipeline. Supersedes `tjp-test`/`tjp-test-validate`, which are kept for backwards compatibility but deprecated.
- Synthetic test-fixture generators (`test_data/fixtures/generate_rnaseq_synthetic.sh`, `generate_virome_synthetic.sh`) and a 10x fixture downloader (`download_10x_fixtures.sh`), all seeded deterministically.

## [v6.1.0] — 2026-05-18

### Added
- `cellranger-mkfastq` pipeline for BCL-to-FASTQ demultiplexing via Cell Ranger's `mkfastq` command, with SLURM template, config template, and samplesheet template.
- `COMMAND_REFERENCE.md` — comprehensive 1,615-line quick-reference covering all CLI tools and pipeline options.
- Architecture design documents: Mermaid source diagrams (`docs/architecture.md`) and a `docs/generate_diagrams.py` script that renders six dark-theme SVGs under `docs/img/`.

### Fixed
- SQANTI3 filter stage: re-enabled the HTML filter report (previously disabled) now that the container is launched with `--writable-tmpfs`, resolving the temp-directory write error.
- SQANTI3 filter stage: `skip_report` config key is now correctly propagated so users can opt out of the filter report.
- SQANTI3 QC stage: raised memory tier thresholds to account for genome-loading overhead that was causing OOM failures on large inputs.
- SQANTI3 QC stage: added a workaround for a v5.5.4 container crash that occurred when no coverage BAM was provided.
- Submodule documentation pointers updated to include Hyperion Compute v6.0.0 integration docs across all five upstream repos.

### Changed
- 10x Genomics pipelines (Cell Ranger, Space Ranger, Xenium Ranger): the `scratch_output_dir` config key can now override the default scratch path per-run; falls back to the existing `$SCRATCH_ROOT/pipelines/$PIPELINE/runs/$TS` convention when absent.

## [v6.0.0] — 2026-04-05

### Added
- `tjp-batch` CLI tool: samplesheet-driven batch submission that launches one SLURM job per CSV row (10x and long-read pipelines) or one job per sheet (BulkRNASeq, Psoma, Virome). Supports `--dry-run`, `--dev`, and `--config` flags.
- `bin/lib/samplesheet.sh`: CSV samplesheet validation, per-pipeline column schemas (`_SAMPLESHEET_REQUIRED_COLS`), and row-to-config converters.
- `bin/lib/metadata.sh` and `bin/labdata` CLI: local Titan metadata prototype that generates a `PLR-xxxx` JSON record for every launch and stores it at `/work/$USER/pipelines/metadata/pipeline_runs/`. Commands: `find runs`, `show`, `new-id`, `status`.
- Titan metadata fields (`titan_project_id`, `titan_sample_id`, `titan_library_id`, `titan_run_id`) added to all nine pipeline config templates, prefixed with `titan_` to avoid collisions with native tool field names.
- `tjp-launch` now calls `labdata register-run` on every launch, records the `PLR-xxxx` ID in `manifest.json`, and exposes `get_pipeline_version()` for version detection.
- Samplesheet CSV templates for all nine pipelines added to `templates/<pipeline>/samplesheet.csv`; `tjp-setup` copies them all into the user workspace on first run.
- `hyperion-batch` and `biocruiser-batch` symlink aliases for `tjp-batch`.
- `metadata/SCHEMA.md` documenting the full Titan-compatible JSON schema.

### Changed
- `titan_` prefix adopted for all Titan-related YAML config keys to prevent naming collisions (particularly relevant for Cell Ranger / Space Ranger / Xenium Ranger which already define `sample_id` natively); samplesheet CSV columns remain unprefixed.
- All pipeline config templates updated to include the `titan_*` fields block.

## [v5.4.0] — 2026-04-04

### Added
- Virome pipeline integration: `mwilde49/virome-pipeline` added as a git submodule at `containers/virome/` (pinned to v1.4.0). Uses native Nextflow on the host with per-process Apptainer containers (Model C — multi-container architecture). `is_multicontainer_pipeline()` helper added to `bin/lib/common.sh`.
- SQANTI3 long-read QC pipeline: four-stage SLURM DAG (QC long-read, QC reference, filter, rescue) orchestrated by `slurm_templates/sqanti3_slurm_template.sh` with dynamic CPU/memory scaling based on GTF transcript count.
- `wf-transcriptomes` pipeline: Nextflow head-job pipeline running epi2me-labs/wf-transcriptomes with a SLURM executor; per-process jobs dispatched via `containers/sqanti3/configs/wf_transcriptomes/juno.config`.
- `mwilde49/longreads` git submodule at `containers/sqanti3/`, providing the SQANTI3 container definition, stage scripts, and wf-transcriptomes Nextflow config.
- `NEXTFLOW_MANAGED_PIPELINES` array and `is_nextflow_managed_pipeline()` function added to `bin/lib/common.sh` to gate wf-transcriptomes-specific logic.
- `tjp-test` and `tjp-test-validate` support for virome.
- All submodules pinned to explicit release tags (virome v1.4.0, longreads/sqanti3 v1.0.0).
- Pinned Nextflow invocation to the explicit project `bin/` path to prevent version conflicts.

### Fixed
- Virome container pre-flight checks corrected after pipeline design review.
- `wf-transcriptomes` SLURM template: removed invalid params; corrected version default to v1.7.2.

## [v5.3.1] — 2026-03-12

### Fixed
- `tjp-edit` now defaults to `nano` when `$EDITOR` is not set, ensuring the command works out of the box on Juno without extra configuration.
- Restored missing executable permission on the `tjp-edit` script.

## [v5.3.0] — 2026-03-12

### Added
- `tjp-edit` CLI tool: opens the pipeline config file for a given pipeline in the user's editor. Aliases: `hyperion-edit`, `biocruiser-edit`.
- `DEVELOPER_ONBOARDING.md`: comprehensive guide covering architecture, local development workflow, adding new pipelines, and contributing guidelines.

## [v5.2.0] — 2026-03-10

### Added
- Space Ranger smoke test support in `tjp-test` / `tjp-test-validate`, using bundled tiny inputs from the Space Ranger install directory.
- `unknown_slide: visium-1` config key support for Space Ranger smoke tests (replaces the `slide` + `area` combination when using a non-registered slide).
- `10x` submodule bumped to v1.1.0 to pull in `unknown_slide` support in `spaceranger-run.sh`.

### Changed
- `create_bam` is now a required config field for both Cell Ranger and Space Ranger (Cell Ranger 10+ and Space Ranger 3+ mandate `--create-bam`); validator rejects configs that omit it.

## [v5.1.0] — 2026-03-10

### Fixed
- 10x Genomics tool paths corrected to match actual HPC install locations under `/groups/tprice/opt/`.
- Transcriptome reference path fixed to resolve correctly under `/groups/tprice/pipelines/references/`.
- `create_bam` added to the Cell Ranger required-config-key validator so missing values are caught before submission.

## [v5.0.0] — 2026-03-10

### Added
- Cell Ranger, Space Ranger, and Xenium Ranger pipelines: native architecture (no Apptainer container, no Nextflow). Tools are installed from 10x Genomics tarballs at `/groups/tprice/opt/` and manage their own threading via `--localcores`/`--localmem`.
- `mwilde49/10x` git submodule at `containers/10x/` providing per-tool wrapper scripts (`bin/*-run.sh`), shared YAML parsing (`lib/10x_common.sh`), per-tool validators (`lib/validate_*.sh`), and binary smoke tests.
- `NATIVE_PIPELINES` array and `is_native_pipeline()` helper in `bin/lib/common.sh` to gate native-specific logic (no bind mounts, exclusive SLURM flag).
- `tool_path` config key for per-run tool path override (useful when testing new 10x tool versions).
- SLURM templates for all three 10x tools: 24 h / 16 CPU / 128 GB / `--exclusive` for Cell Ranger and Space Ranger; 12 h for Xenium Ranger.
- Per-tool config validators: Cell Ranger (`sample_id`, `sample_name`, `fastq_dir`, `transcriptome`), Space Ranger (adds `image`, `slide`, `area`), Xenium Ranger (`command`, `xenium_bundle`, conditional `segmentation_file`).
- Reproducibility manifest uses `native:<tool_path>` for `container_file` and the tool's version string for `container_checksum` in native runs.
- Hyperion Compute branding (`bin/lib/branding.sh`): "HYPERION COMPUTE" banner with live node count, timestamped `[HH:MM:SS] [INFO]` log tags, themed milestone messages, and sign-off line. All CLI tools and SLURM templates updated.
- `hyperion-*` and `biocruiser-*` symlink aliases added for all `tjp-*` tools; missing `validate` symlinks restored.
- `tjp-setup` now automatically adds `bin/` to `PATH` in `~/.bashrc` so users do not need manual PATH edits after first-time setup.

### Fixed
- Validation crash under `set -e`: `((PASS++))` returns exit 1 when `PASS` is 0; replaced with `PASS=$((PASS + 1))`.
- Validation check directories and file patterns updated to match actual pipeline output structure.

## [v3.1.0] — 2026-03-06

### Added
- Automatic stage-out archiving: after a successful pipeline run, inputs (FASTQs) and outputs are rsync'd from scratch to `inputs/` and `outputs/` subdirectories inside the durable work run directory, with checksum verification.
- `tjp-test` and `tjp-test-validate` smoke-test commands: copy pre-staged test FASTQs to scratch, generate a config, submit to the dev partition, and validate output files after completion. Supports `psoma` and `bulkrnaseq`; `--clean` flag to wipe previous test data.
- `--dev` flag on `tjp-launch` to submit to the SLURM dev partition (2-hour limit, fast queue).
- SLURM resource bump: default request raised to 128 GB RAM and 40 CPUs.
- `HPC_SYSTEM_MAP.md` documenting Juno cluster node types, QOS limits, and queue configuration.
- User guides for bulk RNA-seq pipeline setup and scp/editor workflows.

### Changed
- Pipeline outputs are now redirected to user scratch directories (`/scratch/juno/$USER/pipelines/...`) rather than the shared project directory.

## [v3.0.0] — 2026-03-04

### Added
- Psoma pipeline integration: HISAT2 + Trimmomatic RNA-seq pipeline added as a `mwilde49/psoma` git submodule at `containers/psoma/`. Combined container + pipeline repository (no separate Nextflow clone needed).
- HISAT2 index support: index configured as a prefix path (e.g., `/path/to/gencode48`) rather than a directory.
- Trimmomatic adapter trimming with Nextera adapters; Java heap set to 16 GB for multi-threaded operation.
- Shared reference files (`gencode48` GTF, `filter.bed`, `blacklist.bed`, HISAT2 index) staged at `/groups/tprice/pipelines/references/`.
- `SLURM_HOME=/tmp` workaround so Nextflow can write `~/.nextflow` on Juno's symlinked home filesystem.

### Fixed
- Executable permissions restored on `bin/` and `slurm_templates/` scripts.
- Java heap configured correctly for Trimmomatic under 20 SLURM threads.

## [v2.0.0] — 2026-03-04

### Added
- `tjp-setup`: one-time workspace initializer that creates `$WORK/pipelines/`, copies config templates, and adds `bin/` to `PATH`.
- `tjp-launch`: timestamped run launcher that creates a run directory under `/work/$USER/pipelines/<pipeline>/runs/`, snapshots the config, writes a `manifest.json` reproducibility record, and submits the SLURM job.
- `configs/` config templates and `templates/` directory with per-pipeline `config.yaml` stubs using `__USER__`/`__SCRATCH__`/`__WORK__` placeholders.
- Shared reference files migrated from user-specific paths to `/groups/tprice/pipelines/references/` so all group members can use them.
- BulkRNASeq pipeline documentation: `BULKRNASEQ_HPC_GUIDE.md` with tested walkthrough, data guide, and reference setup instructions.
- Top-level `README.md` with pipeline overview, quick-start instructions, and documentation index.
- `ONBOARDING.md` and `USER_GUIDE.md` covering first-time setup, config editing, job submission, and monitoring.

### Fixed
- `tjp-setup`: fixed `local` keyword used outside a function causing a bash error on source.
- BulkRNASeq SLURM template: corrected Nextflow pipeline filename.
- BulkRNASeq config: replaced multi-line BED params block with individual placeholders to fix `sed` substitution errors.
- Missing Nextflow params (`fastqc_cores`, `clipping`, `strandedness`, BED file defaults) added to the bulkrnaseq config template.
- Paths migrated from user-specific to the shared group location (`/groups/tprice/pipelines`).

---

[Unreleased]: https://github.com/mwilde49/hpc/compare/v7.3.1...HEAD
[v7.3.1]: https://github.com/mwilde49/hpc/compare/v7.3.0...v7.3.1
[v7.3.0]: https://github.com/mwilde49/hpc/compare/v7.2.0...v7.3.0
[v7.2.0]: https://github.com/mwilde49/hpc/compare/v7.1.0...v7.2.0
[v7.1.0]: https://github.com/mwilde49/hpc/compare/v7.0.0...v7.1.0
[v6.1.0]: https://github.com/mwilde49/hpc/compare/v6.0.0...v6.1.0
[v6.0.0]: https://github.com/mwilde49/hpc/compare/v5.4.0...v6.0.0
[v5.4.0]: https://github.com/mwilde49/hpc/compare/v5.3.1...v5.4.0
[v5.3.1]: https://github.com/mwilde49/hpc/compare/v5.3.0...v5.3.1
[v5.3.0]: https://github.com/mwilde49/hpc/compare/v5.2.0...v5.3.0
[v5.2.0]: https://github.com/mwilde49/hpc/compare/v5.1.0...v5.2.0
[v5.1.0]: https://github.com/mwilde49/hpc/compare/v5.0.0...v5.1.0
[v5.0.0]: https://github.com/mwilde49/hpc/compare/v3.1.0...v5.0.0
[v3.1.0]: https://github.com/mwilde49/hpc/compare/v3.0.0...v3.1.0
[v3.0.0]: https://github.com/mwilde49/hpc/compare/v2.0.0...v3.0.0
[v2.0.0]: https://github.com/mwilde49/hpc/releases/tag/v2.0.0
