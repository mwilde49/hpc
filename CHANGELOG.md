# Changelog

All notable changes to this project are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/mwilde49/hpc/compare/v6.1.0...HEAD
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
