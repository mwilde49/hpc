# Hyperion Compute — Documentation Master Index

**Version:** v7.3.0 &nbsp;|&nbsp; **Last updated:** 2026-07-23 (v7.3.0 — Provenance README rolled out to all 13 pipelines: PROVENANCE_README.md, CONSOLE_LOG.txt, live software-version capture)

This file is the single entry point for all documentation in the TJP HPC pipeline framework. It describes what every document covers, who should read it, and where to look for specific information.

---

## Quick Navigation

| I want to… | Start here |
|------------|-----------|
| Run my first pipeline | [ONBOARDING.md](#2-onboardingmd) |
| Configure a specific pipeline | [USER_GUIDE.md](#3-user_guidemd) |
| Look up a command or config key | [COMMAND_REFERENCE.md](#4-command_referencemd) |
| Understand the system architecture | [DEVELOPER_ONBOARDING.md](#5-developer_onboardingmd) |
| See architecture diagrams | [docs/architecture.md](#10-docsarchitecturemd) |
| Understand design decisions | [PIPELINE_DESIGN_REVIEW.md](#7-pipeline_design_reviewmd) |
| Check Juno cluster specs | [HPC_SYSTEM_MAP.md](#8-hpc_system_mapmd) |
| Set up BulkRNASeq specifically | [BULKRNASEQ_HPC_GUIDE.md](#9-bulkrnaseq_hpc_guidemd) |
| Set up Cell Ranger / multi specifically | [CELLRANGER_GUIDE.md](#15-cellranger_guidemd) |
| Set up DeconvATAC specifically | [DCONVATAC_HPC_GUIDE.md](#16-dconvatac_hpc_guidemd) |
| Understand Titan metadata | [metadata/SCHEMA.md](#11-metadataschemamd) |
| Deploy or develop in this repo | [TJP_HPC_COMPLETE_GUIDE.md](#6-tjp_hpc_complete_guidemd) |
| Debug a pipeline failure | [TROUBLESHOOTING.md](#17-troubleshootingmd) |
| Understand an unfamiliar term | [GLOSSARY.md](#18-glossarymd) |
| See what changed in a release | [CHANGELOG.md](#13-changelogmd) |
| Contribute a new pipeline | [CONTRIBUTING.md](#14-contributingmd) |
| Understand a design choice | [docs/decisions/](docs/decisions/README.md) |
| See all config keys for a pipeline | [templates/schemas/](#21-templatesschemas) |

---

## Document Inventory

### 1. README.md

**Audience:** Everyone — first document a new user or developer sees.

**What it covers:**
- Project overview and version
- Pipeline table (all 13 pipelines, type, description, submodule pins)
- Directory structure overview
- Quick start (4 steps: clone, setup, launch, batch)
- CLI tool reference table
- HPC path conventions
- How to add a new pipeline (three patterns)
- Documentation index (links to every other doc)

**When to read:** Read this first. It is the authoritative one-page summary of everything. If you only read one document, make it this one.

---

### 2. ONBOARDING.md

**Audience:** New group members running pipelines for the first time.

**What it covers:**
- One-time workspace setup (`tjp-setup`)
- Workspace directory structure
- Config field reference for every pipeline (quick-reference tables)
- How to launch a pipeline and interpret output
- Batch launching with `tjp-batch`
- Smoke testing
- Monitoring jobs
- Metadata and run tracking (`labdata`)
- Run directory structure and `manifest.json`
- FAQ (8 common questions)

**When to read:** After README.md. Written for someone who just got a Juno account and wants to run their first analysis. No prior HPC or bioinformatics pipeline experience assumed.

---

### 3. USER_GUIDE.md

**Audience:** Bench scientists and bioinformaticians running analyses.

**What it covers:**
- Pipeline selection guide (short-read RNA-seq, long-read, viral, 10x)
- Step-by-step instructions for every pipeline (configure → launch)
- Config tables with every field, required/optional, and descriptions
- Uploading data to Juno via SCP/rsync
- Batch launching and samplesheet formats
- Monitoring, metadata, results location, smoke testing, reproducibility
- Troubleshooting section (common errors and fixes)

**When to read:** The day-to-day reference for running analyses. More detailed than ONBOARDING.md. Use `Ctrl+F` to jump to your specific pipeline.

**Pipelines covered in depth:** BulkRNASeq, Psoma, Virome, wf-transcriptomes, SQANTI3, Cell Ranger, Cell Ranger mkfastq, Cell Ranger Multi, Space Ranger, Xenium Ranger, DeconvATAC.

---

### 4. COMMAND_REFERENCE.md

**Audience:** Anyone who needs to look up a specific command, flag, config key, or path.

**What it covers:**
- Juno HPC general commands (SSH, modules, file transfer)
- SLURM job management (sbatch, squeue, scancel, sacct)
- Apptainer container commands (exec, build, pull, bind mounts)
- Git and submodule commands
- All framework CLI tools with every flag (`tjp-setup`, `tjp-launch`, `tjp-batch`, `tjp-edit`, `tjp-validate`, `tjp-test-suite`, `tjp-test`, `tjp-test-validate`, `labdata`)
- Per-pipeline reference sections (§6.1–§6.13): commands, config keys, output layout, edge cases
- Shared reference paths (all pre-installed references on Juno)
- Titan integration key reference
- Environment variables and path conventions
- Troubleshooting: common errors with root causes and fixes
- Tool upgrade procedures (how to install a new Cell Ranger version)

**When to read:** As a lookup reference, not cover-to-cover. 1,700+ lines. Use `Ctrl+F`. Particularly useful for edge cases (`create_bam`, `unknown_slide`, `import-segmentation`, etc.).

---

### 5. DEVELOPER_ONBOARDING.md

**Audience:** Developers adding pipelines, maintaining the framework, or debugging execution flows.

**What it covers:**
- System overview and pipeline inventory table
- Architecture: the four-layer stack (Config → SLURM → Execution → Pipeline)
- Shared infrastructure deep-dives:
  - Pipeline registry (`bin/lib/common.sh`)
  - Config validation (`bin/lib/validate.sh`)
  - Reproducibility manifest (`bin/lib/manifest.sh`)
  - Branding (`bin/lib/branding.sh`)
  - Workspace setup (`bin/tjp-setup`)
  - Samplesheet library (`bin/lib/samplesheet.sh`)
  - Metadata (`bin/lib/metadata.sh`)
- Step-by-step execution flows for all 13 pipelines (how `tjp-launch` dispatches each one)
- Pipeline comparison matrix (resources, container strategy, config handling)
- Testing infrastructure (smoke test framework, test data locations)
- How to add a new pipeline (checklist for all three patterns)
- HPC environment notes (Juno-specific constraints)
- Key files reference table

**When to read:** When developing or debugging. The ground truth for how each pipeline is wired together. Cross-reference with PIPELINE_DESIGN_REVIEW.md for the *why* behind design choices.

---

### 6. TJP_HPC_COMPLETE_GUIDE.md

**Audience:** Group members setting up from scratch, or anyone who wants a single end-to-end narrative.

**What it covers:**
- Full lifecycle walkthrough: local development → container build → HPC deployment → SLURM submission → monitoring → results
- Architecture at a glance
- HPC filesystem layout
- Phase-by-phase guide (7 phases)
- Key concepts explained (containers, SLURM, scratch vs work, bind mounts)
- Adding a new pipeline (narrative walkthrough, complements DEVELOPER_ONBOARDING.md)
- Troubleshooting section
- File reference card
- Quick reference card

**When to read:** For a holistic, narrative understanding of the full system. Useful for onboarding someone who wants to understand *everything* in one sitting, or for deploying a completely fresh instance of the framework.

---

### 7. PIPELINE_DESIGN_REVIEW.md

**Audience:** Developers and team leads making architectural decisions.

**What it covers:**
- Pipeline comparison matrix (architecture, execution model, resources, inputs/outputs)
- Submodule versioning table (current pins for all 5 submodules)
- Execution model breakdown (inline, submoduled-container, native, multi-container, Nextflow)
- Per-pipeline design assessments (strengths, weaknesses, known limitations)
- Cross-cutting observations (what patterns worked, what didn't)
- Recommendations for new pipeline development (implemented and pending)

**When to read:** When designing a new pipeline, evaluating architectural tradeoffs, or reviewing why something was built the way it was. This is the "why" document — DEVELOPER_ONBOARDING.md is the "how."

---

### 8. HPC_SYSTEM_MAP.md

**Audience:** Anyone working directly with the Juno cluster (resource allocation, storage, job tuning).

**What it covers:**
- Cluster partition specs (normal, dev, GPU: A30, H100, VDI)
- QOS limits per partition
- Storage tiers (home, work, scratch, groups) — quotas, speeds, persistence
- Symlinks and bind mounts (how Juno's symlinked home directories affect Apptainer)
- How SLURM jobs run (allocation, execution, stage-out)
- Resource allocation table (CPUs, memory, walltime per pipeline)
- Partition selection guidance (when to use dev vs normal)
- Optimization opportunities (scratch I/O, exclusive node usage, memory headroom)
- Metadata and Titan integration overview
- Batch execution parallelism model

**When to read:** When tuning resource requests, debugging Apptainer bind mount issues, or understanding why scratch vs work matters for pipeline I/O.

---

### 9. BULKRNASEQ_HPC_GUIDE.md

**Audience:** Users running BulkRNASeq specifically; developers maintaining that pipeline.

**What it covers:**
- Three-repo relationship (hpc framework + bulkseq submodule + UTDal pipeline clone)
- Container build and test instructions
- Full step-by-step HPC walkthrough (samples file, config, references, launch)
- Batch execution with samplesheets
- Stage-out archiving behavior
- Titan integration fields
- Submodule update procedure (how to bump the bulkseq pin)
- Troubleshooting BulkRNASeq-specific issues

**When to read:** The dedicated reference for BulkRNASeq. More detailed than USER_GUIDE.md for this specific pipeline. Also useful as a worked example of the submoduled-container pattern.

---

### 10. docs/architecture.md

**Audience:** Visual learners, presenters, anyone getting oriented.

**What it covers:**
Six diagrams (Mermaid source + pre-rendered SVGs in `docs/img/`):
1. **System Architecture** — four-layer stack with all components
2. **Execution Flow** — `tjp-launch` → SLURM → container/native → stage-out
3. **Pipeline Taxonomy** — all 13 pipelines organized by execution model
4. **Filesystem Layout** — scratch, work, groups, and their relationships
5. **Titan Roadmap** — local metadata → Titan migration path
6. **Batch Workflow** — `tjp-batch` samplesheet dispatch (per-row vs per-sheet)

**When to read:** For visual orientation. The SVGs are presentation-ready. The Mermaid source in `architecture.md` is editable with standard Mermaid tooling.

To regenerate SVGs:
```bash
python3 docs/generate_diagrams.py
```

---

### 11. metadata/SCHEMA.md

**Audience:** Developers integrating with Titan; anyone building tooling around `labdata`.

**What it covers:**
- Local metadata store directory structure (`$WORK_ROOT/pipelines/metadata/`)
- Titan ID format (`TYPE-xxxx`: PRJ, SMP, LIB, RUN, PLR, REF, ANN)
- Full field reference for pipeline run records (17 fields)
- Example PLR-xxxx JSON record
- `labdata` commands for reading and querying records
- Migration plan: local JSON → Titan PostgreSQL (~6 months from v6.0.0 release)

**When to read:** When building integrations, writing scripts that consume run metadata, or preparing for the Titan database migration.

---

### 13. CHANGELOG.md

**Audience:** All users and contributors.

**What it covers:**
- Version-by-version changelog in [Keep a Changelog](https://keepachangelog.com/) format
- Sections for every release from v2.0.0 through v7.3.0, plus an `[Unreleased]` section
- Added / Changed / Fixed / Removed categories per release

**When to read:** When upgrading to a new framework version to understand what changed.

---

### 14. CONTRIBUTING.md

**Audience:** Contributors adding pipelines, fixing bugs, or maintaining the framework.

**What it covers:**
- Branch naming conventions (`feat/`, `fix/`, `docs/`, `chore/`)
- Three pipeline-adding checklists (Pattern A: Inline, B: Submoduled, C: Native)
- Submodule release procedure (tagging, bumping, version pin updates)
- PR checklist (code quality, testing, documentation, submodules)
- Release process (MAJOR/MINOR/PATCH versioning, step-by-step)
- Documentation standards

**When to read:** Before opening a PR or adding a new pipeline.

---

### 15. CELLRANGER_GUIDE.md

**Audience:** Users running any Cell Ranger pipeline; developers maintaining 10x pipelines.

**What it covers:**
- Decision tree: mkfastq vs count vs multi
- Cell Ranger mkfastq: when to use, SampleSheet.csv format, full config reference, output structure
- Cell Ranger count: pre-installed references, config with all keys annotated, output tree, edge cases (chemistry, SC3Pv3LT, create_bam)
- Cell Ranger multi: all 8 feature types, feature reference CSV format, 8 use-case config examples (GEX-only, VDJ-T, VDJ-B, CITE-seq, CRISPR, CellPlex, Flex, combined)
- Shared reference paths and how to verify them
- Upgrading Cell Ranger (4-step process + per-run tool_path override)
- Troubleshooting (9 specific error scenarios)

**When to read:** The dedicated reference for all Cell Ranger workflows. More detailed than USER_GUIDE.md §9 for this suite.

---

### 16. DCONVATAC_HPC_GUIDE.md

**Audience:** Users running DeconvATAC; developers maintaining the dconvatac submodule.

**What it covers:**
- Submodule relationship (hpc framework + mwilde49/dconvatac @ v1.0.0)
- Container build instructions (local, requires sudo)
- Input requirements: spatial ATAC `.h5ad` and single-cell reference `.h5ad`
- Full config reference with all Cell2Location parameters (`N_cells_per_location`, `detection_alpha`, epoch counts)
- CPU vs GPU variant — when to use `dconvatac` vs `dconvatac-gpu`
- Batch execution (per-row mode: one SLURM job per spatial sample)
- `.sif` transfer to HPC
- Titan integration fields

**When to read:** The dedicated reference for DeconvATAC. More detailed than USER_GUIDE.md for this pipeline.

---

### 17. TROUBLESHOOTING.md

**Audience:** Anyone debugging a pipeline failure.

**What it covers:**
- Quick symptom lookup table (37 rows — find your error in one place)
- SLURM failures (job states, failure causes, pending reasons)
- Apptainer / container errors (bind mounts, missing SIF, read-only filesystem)
- RNA-seq pipeline errors (BulkRNASeq, Psoma)
- 10x Genomics pipeline errors (Cell Ranger, Space Ranger, Xenium Ranger)
- Long-read pipeline errors (SQANTI3, wf-transcriptomes)
- Framework CLI errors (tjp-launch, tjp-batch, labdata)
- Environment and cluster errors (module load, PATH, scratch quota)

**When to read:** When a job fails and the error message is not self-explanatory. Consolidates troubleshooting content from USER_GUIDE.md, COMMAND_REFERENCE.md, TJP_HPC_COMPLETE_GUIDE.md, and BULKRNASEQ_HPC_GUIDE.md into one searchable file.

---

### 18. GLOSSARY.md

**Audience:** New group members and anyone encountering unfamiliar terms.

**What it covers:**
- ~40 terms covering Apptainer, BCL, CITE-seq, CellPlex, DAG, EPI2ME, Flex, GEX, GTF, Juno, labdata, PLR-xxxx, per-row/per-sheet batch modes, SIF, SLURM, Titan, VDJ, scratch, work directory, yaml_get, and more.

**When to read:** As a reference when you encounter an unfamiliar term in any other document.

---

### 19. test_data/README.md

**Audience:** Developers running smoke tests; anyone staging test data on Juno.

**What it covers:**
- What test data exists in each subdirectory
- Which files are in git vs. must be staged on HPC
- Staging instructions for RNA-seq, 10x, SQANTI3, and wf-transcriptomes test data
- Current status of each pipeline's smoke test support (including blockers)
- How to add test data for a new pipeline

**When to read:** When running smoke tests for the first time or adding test data for a new pipeline.

---

### 20. bin/check-docs-freshness

**Audience:** Developers; CI/CD automation.

**What it covers:**
This is a shell script, not a document. It checks that:
- Every pipeline in `KNOWN_PIPELINES` appears in `README.md`'s pipeline table
- Pipeline counts are consistent across key docs
- SLURM templates, config templates, samplesheet templates, validators, and samplesheet column definitions all exist for every registered pipeline

**When to run:** Before merging any PR that adds or removes a pipeline. Also useful as a pre-push hook.

---

### 21. templates/schemas/

**Audience:** Developers and users who want field-level documentation for config YAMLs.

**What it covers:**
One annotated YAML schema file per pipeline (13 files). Each schema documents every config key with its type, required/optional status, default value, description, and example.

**When to read:** When writing a config from scratch and you want to understand all available fields beyond what the template shows. Also useful for IDE integration.

---

### 22. docs/decisions/

**Audience:** Developers making architectural changes; anyone wondering "why was it built this way?"

**What it covers:**
Five Architecture Decision Records (ADRs):
- [ADR-001](docs/decisions/ADR-001-slurm-vs-nextflow-for-sqanti3.md): Why SQANTI3 uses SLURM DAG instead of Nextflow
- [ADR-002](docs/decisions/ADR-002-scratch-staging.md): Why outputs stage through scratch before archiving to work
- [ADR-003](docs/decisions/ADR-003-titan-prefix-convention.md): Why Titan metadata fields use the `titan_` prefix
- [ADR-004](docs/decisions/ADR-004-per-row-vs-per-sheet-batch.md): Why batch dispatch uses two modes (per-row vs per-sheet)
- [ADR-005](docs/decisions/ADR-005-native-execution-for-10x.md): Why 10x tools run natively instead of in containers

**When to read:** Before making a change that touches one of these areas — to understand constraints before proposing alternatives.

---

### 12. CLAUDE.md

**Audience:** Claude Code AI assistant (not a human-facing document).

**What it covers:**
- Project overview and version for AI context
- Build and run commands
- Architecture summary
- User workflow
- Per-pipeline details (key differences, critical flags, references)
- Adding new pipeline checklist
- Key constraints

**When to read:** This document is loaded automatically by Claude Code when working in this repo. Human readers can use it as a dense technical summary, but DEVELOPER_ONBOARDING.md is the better reference for humans.

---

## Pipeline × Document Matrix

Use this table to find which documents cover a specific pipeline.

| Pipeline | ONBOARDING | USER_GUIDE | CMD_REF | DEV_ONBOARD | DESIGN_REVIEW |
|----------|-----------|------------|---------|-------------|---------------|
| AddOne | § config | — | §6.1 | §4.2 | §3 |
| BulkRNASeq | § config | §4 | §6.2 | §4.3 | §3 + BULKRNASEQ_HPC_GUIDE |
| Psoma | § config | §5 | §6.3 | §4.4 | §3 |
| Virome | § config | §6 | §6.4 | §4.8 | §3 |
| wf-transcriptomes | § config | §7 | §6.6 | §4.10 | §3 |
| SQANTI3 | § config | §8 | §6.5 | §4.9 | §3 |
| Cell Ranger | § config | §9 | §6.7 | §4.5 | §3 |
| Cell Ranger mkfastq | § config | §9 | §6.10 | §4.5 | §3 |
| Cell Ranger Multi | § config | §9 | §6.11 | §4.5 | §3 |
| Space Ranger | § config | §9 | §6.8 | §4.6 | §3 |
| Xenium Ranger | § config | §9 | §6.9 | §4.7 | §3 |
| DeconvATAC | § config | §10 | §6.12 | §1 (overview table only — no dedicated §4.x flow) | §1 (comparison matrix only — no dedicated §3 assessment) |
| DeconvATAC GPU | § config | §10 | §6.13 | §1 (overview table only — no dedicated §4.x flow) | §1 (comparison matrix only — no dedicated §3 assessment) |

---

## Key Files Outside of Documentation

These are not documentation but are essential references when developing:

| File | Purpose |
|------|---------|
| `bin/lib/common.sh` | Central pipeline registry — add any new pipeline here first |
| `bin/lib/validate.sh` | Per-pipeline config validators |
| `bin/lib/samplesheet.sh` | Required samplesheet columns per pipeline |
| `bin/tjp-launch` | Main launch dispatcher — pipeline-specific routing logic |
| `bin/tjp-batch` | Batch launcher — per-row vs per-sheet dispatch |
| `bin/check-docs-freshness` | Script to verify docs are in sync with the pipeline registry |
| `templates/<pipeline>/config.yaml` | User-facing config templates with placeholder substitution |
| `templates/<pipeline>/samplesheet.csv` | Samplesheet column templates |
| `templates/schemas/<pipeline>.yaml` | Annotated field-level schemas for all config keys |
| `metadata/SCHEMA.md` | Titan metadata JSON schema |
| `docs/decisions/` | Architecture Decision Records (ADRs) |

---

## Submodule Map

| Directory | Repo | Pinned version | Contents |
|-----------|------|----------------|----------|
| `containers/bulkrnaseq/` | `mwilde49/bulkseq` | v1.0.1 | Container def + build scripts |
| `containers/psoma/` | `mwilde49/psoma` | v2.0.2 | Container def + pipeline scripts |
| `containers/virome/` | `mwilde49/virome-pipeline` | v1.5.0 | Nextflow workflow + per-process container defs |
| `containers/sqanti3/` | `mwilde49/longreads` | v1.1.0 +6 commits | SQANTI3 + wf-transcriptomes stage scripts, configs, SIF |
| `containers/10x/` | `mwilde49/10x` | v1.2.0 +1 commit | Wrapper scripts + validators for all 5 10x tools |
| `containers/dconvatac/` | `mwilde49/dconvatac` | v1.0.0 +4 commits | Container def + Python pipeline script (Cell2Location, CPU + GPU) |

---

## Documentation Completeness Status

All 11 documentation additions originally proposed for industry-standard quality have been implemented as of v6.1.1.

| # | Item | File | Status |
|---|------|------|--------|
| 1 | Version changelog | `CHANGELOG.md` | ✓ Done |
| 2 | Cell Ranger suite guide | `CELLRANGER_GUIDE.md` | ✓ Done |
| 3 | Contributing guide | `CONTRIBUTING.md` | ✓ Done |
| 4 | Config schema annotations | `templates/schemas/` (13 files) + `# Required fields` in all templates | ✓ Done |
| 5 | Automated doc freshness check | `bin/check-docs-freshness` | ✓ Done |
| 6 | Consolidated troubleshooting | `TROUBLESHOOTING.md` | ✓ Done |
| 7 | Test data documentation | `test_data/README.md` | ✓ Done |
| 8 | Per-pipeline YAML schemas | `templates/schemas/*.yaml` (13 files) | ✓ Done |
| 9 | Glossary | `GLOSSARY.md` | ✓ Done |
| 10 | Architecture Decision Records | `docs/decisions/` (5 ADRs) | ✓ Done |
| 11 | Bug reporting / feedback pointer | Added to `ONBOARDING.md` and `USER_GUIDE.md` | ✓ Done |
