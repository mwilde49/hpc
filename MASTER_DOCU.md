# Hyperion Compute — Documentation Master Index

**Version:** v6.1.0 &nbsp;|&nbsp; **Last updated:** 2026-05-19

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
| Understand Titan metadata | [metadata/SCHEMA.md](#11-metadataschemamd) |
| Deploy or develop in this repo | [TJP_HPC_COMPLETE_GUIDE.md](#6-tjp_hpc_complete_guidemd) |

---

## Document Inventory

### 1. README.md

**Audience:** Everyone — first document a new user or developer sees.

**What it covers:**
- Project overview and version
- Pipeline table (all 11 pipelines, type, description, submodule pins)
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

**Pipelines covered in depth:** BulkRNASeq, Psoma, Virome, wf-transcriptomes, SQANTI3, Cell Ranger, Cell Ranger mkfastq, Cell Ranger Multi, Space Ranger, Xenium Ranger.

---

### 4. COMMAND_REFERENCE.md

**Audience:** Anyone who needs to look up a specific command, flag, config key, or path.

**What it covers:**
- Juno HPC general commands (SSH, modules, file transfer)
- SLURM job management (sbatch, squeue, scancel, sacct)
- Apptainer container commands (exec, build, pull, bind mounts)
- Git and submodule commands
- All framework CLI tools with every flag (`tjp-setup`, `tjp-launch`, `tjp-batch`, `tjp-test`, `tjp-test-validate`, `labdata`)
- Per-pipeline reference sections (§6.1–§6.11): commands, config keys, output layout, edge cases
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
- Step-by-step execution flows for all 11 pipelines (how `tjp-launch` dispatches each one)
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
3. **Pipeline Taxonomy** — all 11 pipelines organized by execution model
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
| `templates/<pipeline>/config.yaml` | User-facing config templates with placeholder substitution |
| `templates/<pipeline>/samplesheet.csv` | Samplesheet column templates |
| `metadata/SCHEMA.md` | Titan metadata JSON schema |

---

## Submodule Map

| Directory | Repo | Pinned version | Contents |
|-----------|------|----------------|----------|
| `containers/bulkrnaseq/` | `mwilde49/bulkseq` | v1.0.1 | Container def + build scripts |
| `containers/psoma/` | `mwilde49/psoma` | v2.0.2 | Container def + pipeline scripts |
| `containers/virome/` | `mwilde49/virome-pipeline` | v1.5.0 | Nextflow workflow + per-process container defs |
| `containers/sqanti3/` | `mwilde49/longreads` | v1.1.0 | SQANTI3 + wf-transcriptomes stage scripts, configs, SIF |
| `containers/10x/` | `mwilde49/10x` | v1.2.0 | Wrapper scripts + validators for all 5 10x tools |

---

## Proposed Additions for Industry-Standard Quality

The following are gaps between the current documentation and what a well-maintained open-source or lab-internal bioinformatics framework would typically have. Listed roughly in priority order:

### High priority

1. **CHANGELOG.md** — a version-by-version changelog in [Keep a Changelog](https://keepachangelog.com/) format. Right now version history lives in git tags and memory. A CHANGELOG lets users understand what changed between v6.0.0 and v6.1.0 without reading `git log`. Essential for any multi-user codebase.

2. **Pipeline-specific guides for 10x pipelines** — BULKRNASEQ_HPC_GUIDE.md exists for BulkRNASeq but the 10x pipelines (especially Cell Ranger Multi, which has 8 library-type combinations) have no dedicated guide. A `CELLRANGER_GUIDE.md` covering mkfastq → count vs multi → downstream analysis would be high-value for the typical user.

3. **CONTRIBUTING.md** — how to propose and add a new pipeline, branch naming conventions, PR checklist, how to tag submodule releases. Currently buried in README.md and DEVELOPER_ONBOARDING.md. Should be a top-level file so contributors know the rules without reading 80 pages.

4. **Schema/template for `config.yaml` files** — currently each pipeline's config format is documented only in prose and tables. Adding a brief comment block to every template config (already partially done) with `# Required` / `# Optional` / `# Default: X` annotations would reduce the most common user errors.

### Medium priority

5. **Automated doc freshness check** — a CI hook or script that asserts the `KNOWN_PIPELINES` list in `common.sh` matches the pipeline inventory in README.md. This would prevent the drift that just required this update (cellranger-mkfastq and cellranger-multi were missing from most docs for several weeks after being added to the code).

6. **Troubleshooting runbook as a standalone file** — currently troubleshooting sections exist in USER_GUIDE.md, TJP_HPC_COMPLETE_GUIDE.md, and COMMAND_REFERENCE.md separately. A single `TROUBLESHOOTING.md` with known error messages, root causes, and fixes — searchable in one place — would reduce repeated debugging cycles.

7. **Test data README** — `test_data/` contains 10x scaffold directories and RNA-seq FASTQs, but there is no file explaining what test data exists, where to get it, how to stage it on Juno, and which smoke tests depend on it. A `test_data/README.md` would make the smoke test framework self-contained.

8. **config.yaml schema validation** — the current `validate.sh` validators are hand-written per-pipeline. A lightweight JSON Schema or YAML Schema file per pipeline would allow IDE autocompletion, `yamllint`-style pre-flight checks, and self-documenting format specs without code.

### Lower priority

9. **Glossary** — short definitions of domain terms (PLR-xxxx, Titan, scratch vs work, SIF, SLURM DAG, per-row vs per-sheet) that recur across documents. New lab members without HPC background currently have to piece these together from context.

10. **Decision log** — a lightweight ADR (Architecture Decision Record) file capturing major choices (why SLURM over Nextflow for SQANTI3, why scratch staging instead of writing directly to work, why the `titan_` prefix convention). PIPELINE_DESIGN_REVIEW.md partially fills this role but is structured as assessment rather than formal decision records.

11. **User survey / feedback channel pointer** — a note in ONBOARDING.md and USER_GUIDE.md indicating where users should report bugs or request new pipelines (GitHub Issues, Slack, email). Currently absent, so users with problems have no obvious path to resolution.
