# Pipeline Design Review

This document compares the architecture of every pipeline in the framework,
assesses the strengths and weaknesses of each design, and provides
recommendations for parallel development going forward.

It is distinct from `DEVELOPER_ONBOARDING.md` (which describes *how* the
system works) — the focus here is *why* decisions were made, which ones aged
well, and what to do differently next time.

---

## Table of Contents

1. [Pipeline Comparison Matrix](#1-pipeline-comparison-matrix)
2. [Execution Model Breakdown](#2-execution-model-breakdown)
3. [Per-Pipeline Design Assessment](#3-per-pipeline-design-assessment)
4. [Cross-Cutting Observations](#4-cross-cutting-observations)
5. [Recommendations for Parallel Development](#5-recommendations-for-parallel-development)

---

## 1. Pipeline Comparison Matrix

### Architecture & Execution

| Pipeline | Type | Nextflow | Container strategy | Config handling |
|---|---|---|---|---|
| AddOne | Inline | No | Monolithic `.sif` | Direct YAML → script |
| BulkRNASeq | Submoduled | Inside container | Monolithic `.sif` | User YAML → generated `pipeline.config` |
| Psoma | Submoduled | Inside container | Monolithic `.sif` | User YAML → generated `pipeline.config` |
| Virome | Submoduled | Native on host | 6 per-process `.sif` files | User YAML as params-file (no generation) |
| Cell Ranger | Native | No | None (proprietary binary) | Direct YAML → wrapper script |
| Space Ranger | Native | No | None (proprietary binary) | Direct YAML → wrapper script |
| Xenium Ranger | Native | No | None (proprietary binary) | Direct YAML → wrapper script |
| SQANTI3 | Submoduled | No | Monolithic `.sif` (Apptainer) | Direct YAML → SLURM stage scripts (4-stage DAG) |
| wf-transcriptomes | Submoduled | Native on host (head job) | No container for head; Nextflow manages own containers | User YAML as params-file (no generation); Nextflow-managed SLURM executor |

### Resources & Dependencies

| Pipeline | Time | CPUs | Mem | Exclusive | External deps beyond submodule |
|---|---|---|---|---|---|
| AddOne | 5 min | 1 | 1 GB | No | None |
| BulkRNASeq | 12h | 40 | 128 GB | No | UTDal repo clone |
| Psoma | 12h | 40 | 128 GB | No | None |
| Virome | 12h | 16 | 128 GB | No | Nextflow on host, Kraken2 database |
| Cell Ranger | 24h | 16 | 128 GB | Yes | Tool tarball at `/groups/tprice/opt/` |
| Space Ranger | 24h | 16 | 128 GB | Yes | Tool tarball at `/groups/tprice/opt/` |
| Xenium Ranger | 12h | 16 | 128 GB | Yes | Tool tarball at `/groups/tprice/opt/` |
| SQANTI3 | varies | varies | varies | No | Container SIF (must be pulled: `apptainer pull ... docker://anaconesalab/sqanti3:v5.5.4`) |
| wf-transcriptomes | 24h head + sub-jobs | 8 head | 32 GB head | No | Nextflow on host; epi2me-labs/wf-transcriptomes (auto-fetched) |

### Input & Output

| Pipeline | Input descriptor | Aligner / classifier | Primary outputs |
|---|---|---|---|
| AddOne | Single text file | — | Single text file |
| BulkRNASeq | `fastq_dir` + `samples.txt` | STAR | BAMs, TPM counts, HTSeq raw counts |
| Psoma | `fastq_dir` + `samples.txt` | HISAT2 | BAMs, TPM counts, HTSeq raw counts |
| Virome | `samplesheet.csv` (sample, fastq_r1, fastq_r2) | STAR (host removal) + Kraken2 | Viral abundance matrix, MultiQC report |
| Cell Ranger | `fastq_dir` + `sample_name` prefix | Proprietary | Feature-barcode matrix, web summary |
| Space Ranger | `fastq_dir` + image + slide | Proprietary | Feature-barcode matrix + spatial coords |
| Xenium Ranger | `xenium_bundle` directory | Proprietary | Resegmented Xenium output |
| SQANTI3 | `isoforms` GTF + `ref_gtf` + `ref_fasta` | SQANTI3 classification | Filtered isoforms GTF, QC plots, classification TSV |
| wf-transcriptomes | `fastq_dir` + `sample_sheet` (EPI2ME) | Minimap2 + StringTie2 | Collapsed isoforms, expression matrix, QC report |

### Submodule Versioning

| Submodule | Repo | Current pin | Pin strategy |
|---|---|---|---|
| BulkRNASeq | `mwilde49/bulkseq` | v1.0.0 | Tag |
| Psoma | `mwilde49/psoma` | v2.0.0 | Tag |
| Virome | `mwilde49/virome-pipeline` | v1.4.0 | Tag |
| 10x | `mwilde49/10x` | v1.1.0 | Tag |
| longreads (SQANTI3 + wf-tx) | `mwilde49/longreads` | current HEAD | Tag pending |

---

## 2. Execution Model Breakdown

There are six distinct execution models in the framework. Every pipeline falls
into exactly one:

### Model A — Direct script (AddOne)
```
SLURM node → apptainer exec container → python script
```
Simplest possible model. The container is just an environment carrier.
No orchestration layer.

### Model B — Monolithic container Nextflow (BulkRNASeq, Psoma)
```
SLURM node → apptainer exec container → nextflow run pipeline.nf
```
Nextflow runs *inside* the container alongside all bioinformatics tools.
The container is a self-contained execution environment. The HPC repo
translates the user's YAML into a Nextflow `pipeline.config` before
submission.

### Model C — Native Nextflow with per-process containers (Virome)
```
SLURM node → nextflow run pipeline.nf → [apptainer exec fastqc.sif]
                                       → [apptainer exec star.sif]
                                       → [apptainer exec kraken2.sif]
                                       → ...
```
Nextflow runs natively on the node and manages its own container
invocations per process. The user's YAML is passed directly as a
Nextflow params-file. No config translation by the HPC repo.

### Model D — Native tool (Cell Ranger, Space Ranger, Xenium Ranger)
```
SLURM node → bash wrapper.sh → cellranger count [args...]
```
No containers, no Nextflow. Proprietary tools manage their own
parallelism via `--localcores`/`--localmem`. The `--exclusive` SLURM
flag gives them full node access.

### Model E — SLURM DAG (SQANTI3)
```
SLURM node (orchestrator) → sbatch stage_1a.sh
                           → sbatch stage_1b.sh
                           → sbatch stage_2.sh (depends on 1a+1b)
                           → sbatch stage_3.sh (depends on 2)
```
Orchestrator job submits 4 stage jobs via `sbatch --dependency`. Each stage
runs `apptainer exec sqanti3.sif`. Resources scale dynamically by transcript
count.

### Model F — Nextflow SLURM Executor (wf-transcriptomes)
```
SLURM head job → nextflow run wf-transcriptomes
                     → [SLURM job: pychopper]
                     → [SLURM job: minimap2]
                     → [SLURM job: stringtie2]
                     → [SLURM job: ...per-process]
```
Nextflow runs natively on the head node and submits per-process SLURM jobs
via the `executor = 'slurm'` configuration in
`containers/sqanti3/configs/wf_transcriptomes/juno.config`.

---

## 3. Per-Pipeline Design Assessment

### AddOne
**Purpose:** Demo and template pipeline.

**Strengths:**
- Dead simple — the right amount of complexity for a teaching example.
- SLURM template is the clearest reference for how the framework works.

**Weaknesses:**
- Has no real scientific value; exists only to demonstrate the pattern.
- The inline architecture (code in this repo, not submoduled) doesn't
  scale. It was never intended to.

**Verdict:** Fit for purpose as a demo. Should not be used as a template
for real pipelines.

---

### BulkRNASeq
**Purpose:** Bulk RNA-seq via STAR aligner. First production pipeline.

**Strengths:**
- Established the submodule pattern that all subsequent pipelines follow.
- Monolithic container is easy to reason about — one file, one environment.
- Well-tested on real data.

**Weaknesses:**
- **Split dependency is the main problem.** The pipeline code (UTDal repo)
  lives outside the submodule and must be manually cloned on each HPC
  node. This creates a second source of truth, makes `tjp-setup` warn
  instead of fix, and makes the pipeline impossible to run without a
  separate manual step.
- **Generated config adds a translation layer.** `tjp-launch` reads ~15
  YAML keys and re-emits them into a Nextflow `pipeline.config` via sed.
  When the pipeline adds a new parameter, the HPC repo must be updated
  in parallel to plumb it through. This creates coupling between the
  repos.
- 40-CPU allocation is coarse — the job requests max resources even
  when many steps are single-threaded.

**What to fix:** The UTDal dependency should be absorbed into the submodule
(fork it, or vendor the relevant scripts). Until then, BulkRNASeq is the
most fragile pipeline to deploy to a new HPC environment.

---

### Psoma
**Purpose:** Bulk RNA-seq via HISAT2 + Trimmomatic (Psomagen sample naming).

**Strengths:**
- Fixed BulkRNASeq's split dependency problem. The submodule is
  self-contained — the pipeline `.nf` file, helper scripts, adapter
  sequences, and container definition all live together.
- Cleaner mental model: one submodule = one complete unit of work.

**Weaknesses:**
- Inherits the **generated config translation layer** from BulkRNASeq.
  Same coupling problem: new Nextflow params require parallel changes
  in both repos.
- Monolithic container bundles Nextflow with the bioinformatics tools.
  Upgrading Nextflow means rebuilding the entire container.
- `samples.txt` format (one sample name per line) is implicit about
  file naming conventions and fragile if naming varies.

**What to fix:** The generated config is the main debt. Virome's approach
(params-file passthrough) is strictly better and should be the model for
any Psoma v3.

---

### Virome
**Purpose:** Viral profiling from bulk RNA-seq via host depletion + Kraken2.

**Strengths:**
- **Params-file passthrough** is the right design. The HPC repo doesn't
  need to know or care about individual pipeline parameters — the user
  YAML goes directly to Nextflow. Adding new pipeline params requires no
  changes to the HPC repo.
- **Per-process containers** are more maintainable long-term. Upgrading
  STAR doesn't require rebuilding FastQC, Trimmomatic, and MultiQC.
  Nextflow's caching also works better when containers don't change
  between unrelated runs.
- **CSV samplesheet** is more robust than `samples.txt`. Explicit R1/R2
  pairing handles arbitrary directory structures and naming conventions.
- Self-contained submodule (like Psoma, not BulkRNASeq).

**Weaknesses:**
- **Nextflow must be installed on the host.** This is a new HPC-level
  dependency that BulkRNASeq and Psoma don't have (they carry Nextflow
  inside the container). If Nextflow isn't a loadable module on Juno,
  it needs to be managed separately.
- **6 containers to manage instead of 1.** Each `.sif` must be built or
  copied to HPC. Missing a single one causes cryptic Nextflow errors
  rather than a clean pre-flight failure.
- The pre-flight check in the SLURM template only verifies `*.sif` files
  exist — it doesn't verify that all 6 expected containers are present
  by name.
- **Active development** (v1.4.0) means the pipeline is less battle-tested
  than BulkRNASeq/Psoma.

**What to fix:** Add named container existence checks to the SLURM
pre-flight (check for `fastqc.sif`, `star.sif`, etc. explicitly rather
than just `*.sif`). Consider documenting a `nextflow` module load step
in the HPC setup guide.

---

### Cell Ranger / Space Ranger / Xenium Ranger
**Purpose:** 10x Genomics single-cell, spatial, and in-situ transcriptomics.

**Strengths:**
- **No container overhead.** 10x tools are highly optimized; running
  them natively avoids the Apptainer bind-mount and overhead layers.
- **`--exclusive` flag** gives the tools what they want: full node
  access. This matches the 10x-recommended deployment model.
- The `containers/10x/` submodule cleanly separates the wrapper logic
  (YAML → CLI translation) from this repo.
- Per-tool validation scripts in the submodule are well-structured.

**Weaknesses:**
- **Not reproducible.** Proprietary tarballs at `/groups/tprice/opt/`
  have no version-pinned source. If a tool is updated in place, older
  runs can't be reproduced. The manifest records the version string but
  can't recreate the binary.
- **Manual tarball management.** Upgrading a tool means downloading,
  extracting, and updating `PIPELINE_TOOL_PATHS` in `common.sh`
  manually. There's no automated path.
- **No portability.** These pipelines are entirely Juno-specific; they
  cannot be run anywhere else without re-installing the tools.
- 24-hour time limit for Cell Ranger and Space Ranger is conservative —
  in practice most runs complete in 4–8 hours.

**What to fix:** Nothing structurally — the architecture is appropriate
for proprietary tools. The main operational gap is documentation of the
upgrade procedure.

---

### SQANTI3
**Purpose:** Long-read isoform quality control and filtering.

**Strengths:**
- SLURM DAG model avoids a persistent Nextflow process — each stage submits
  the next via `sbatch --dependency`, which is robust to head-node
  instability.
- Dynamic resource scaling: the orchestrator counts transcripts in the
  isoform GTF and adjusts memory/CPU requests for downstream stages.
- Stage granularity (1a QC long-read, 1b QC reference, 2 filter, 3 rescue)
  gives clear checkpointing — if stage 2 fails, restart from stage 2 only.

**Weaknesses:**
- SIF must be manually pulled (not auto-built):
  `apptainer pull docker://anaconesalab/sqanti3:v5.5.4`
- No sjdb-based short-read integration is currently set up (coverage column
  accepted but optional).
- Test data (UHR chr22) not yet staged on HPC.

**Verdict:** Solid architecture for a 4-stage pipeline. The main outstanding
work is SIF staging and test data setup.

---

### wf-transcriptomes
**Purpose:** ONT full-length transcript analysis (assembly + quantification).

**Strengths:**
- **Model F is the most scalable design in the framework.** Nextflow's SLURM
  executor distributes each process to its own SLURM job — this is how
  Nextflow is designed to run at scale. Each process gets exactly the
  CPUs/memory it needs, and Nextflow handles retries and resume.
- Zero HPC repo coupling: the pipeline is a pure EPI2ME Nextflow workflow;
  `tjp-launch` just sets up the head job. Adding a new pipeline parameter
  requires no changes to the HPC repo.
- Barcode-level samplesheet design (EPI2ME format) is already the standard
  for ONT demultiplexed data.

**Weaknesses:**
- Head job must remain running throughout — if the head node goes down,
  in-flight sub-jobs orphan. Use `screen` or `tmux` if the head job is on a
  login node, or ensure it runs on a compute node (as our SLURM template
  does).
- Version must be pinned (currently v1.7.2) — EPI2ME pipelines auto-update
  unless pinned.
- Test ONT FASTQs not yet staged on HPC.

**Verdict:** Best long-term design pattern in the framework. Should be the
model for any future Nextflow pipeline.

---

## 4. Cross-Cutting Observations

### The translation layer problem
BulkRNASeq and Psoma both require `tjp-launch` to translate user YAML into
a Nextflow config. This creates tight coupling: the HPC repo must be updated
every time the pipeline adds, renames, or removes a parameter. Virome's
params-file passthrough eliminates this entirely. **All future Nextflow
pipelines should use params-file passthrough.**

### Monolithic vs. per-process containers
Monolithic containers (BulkRNASeq, Psoma) are simpler to manage (one file)
but bundle unrelated tools together. Per-process containers (Virome) are
more granular and align with how Nextflow was designed to work. The
trade-off: per-process requires Nextflow on the host and more files to
transfer. As the pipeline portfolio grows, per-process is the better
long-term pattern.

### The UTDal dependency is unresolved
BulkRNASeq is the only pipeline that can silently fail to deploy because of
a missing dependency that isn't tracked by git. Every other pipeline is
either self-contained in its submodule or uses tools from
`/groups/tprice/opt/` (which are documented). This should be resolved.

### Config templates are slightly inconsistent
BulkRNASeq and Psoma use `samples.txt` (implicit naming conventions).
Virome uses a CSV samplesheet (explicit paths). The 10x pipelines use a
`sample_name` prefix. There is no single input descriptor standard. This
isn't a problem today but will matter when users move between pipelines.

### Submodule discipline is good
All submodules are tag-pinned (except longreads which is tag-pending),
self-contained (except BulkRNASeq), and have their own `CLAUDE.md` for
AI-assisted development. This is the right pattern and should be maintained.

### Samplesheet standardization achieved (v6.0.0)
All 9 pipelines now support CSV samplesheets with a consistent structure:
- Required columns per pipeline defined in `bin/lib/samplesheet.sh`
- Optional Titan ID columns (`project_id`, `sample_id`, `library_id`,
  `run_id`) on every sheet
- `tjp-batch` dispatches per-row (10x, long-read) or per-sheet (RNA-seq)
  based on pipeline type
- R3 (CSV samplesheets), R4 (SQANTI3/wf-tx use per-process or DAG model),
  and R1 (params-file passthrough for new pipelines) from the existing
  recommendations are now implemented

### Note on R2 (BulkRNASeq UTDal dependency)
Still unresolved. BulkRNASeq remains the only pipeline with a split
dependency (UTDal repo clone). Still the top debt item.

---

## 5. Recommendations for Parallel Development

### R1 — Use params-file passthrough for all new Nextflow pipelines ✓ Implemented in v6.0.0
Do not add a `_generate_<pipeline>_config()` function to `tjp-launch` for
new pipelines. The user YAML should go directly to Nextflow via
`-params-file`. This keeps the HPC repo ignorant of pipeline-internal
parameters and eliminates the coupling that makes BulkRNASeq and Psoma
maintenance-heavy.

### R2 — Make every submodule self-contained (Outstanding — tracked as top debt)
The submodule should contain everything needed to run the pipeline:
container definitions, pipeline scripts, adapter/reference files that are
small enough to version. No external clones, no assumed directory structure
outside the submodule. Psoma and Virome do this correctly; BulkRNASeq does
not.

### R3 — Standardize on CSV samplesheets ✓ Implemented in v6.0.0
The `samples.txt` format is implicit and fragile. New pipelines should use
a CSV samplesheet (like Virome) with explicit column headers and absolute
paths. This is more verbose but eliminates a class of "wrong suffix" and
"wrong directory" errors.

### R4 — Prefer per-process containers for new pipelines ✓ Implemented in v6.0.0
New Nextflow pipelines should use per-process containers managed by Nextflow
(Virome model) rather than a monolithic container that runs Nextflow inside
itself. This requires Nextflow on the host but produces more maintainable
pipelines: tool upgrades are isolated, Nextflow caching works correctly, and
rebuilds are cheaper.

### R5 — Keep CLAUDE.md current in every submodule
Each submodule is developed semi-independently with AI assistance. The
`CLAUDE.md` in each submodule is the primary context document for that
agent. Keep it up to date with architecture decisions, known gotchas, and
the integration contract with the HPC repo (what keys the config must have,
what the expected output structure is). This is what enables safe parallel
development without constant synchronization.

### R6 — Define the integration contract explicitly
Before starting a new pipeline submodule, agree on:
- What keys the user config YAML will contain
- What the output directory structure looks like (for `tjp-test-validate`)
- Whether it uses a samplesheet or a fastq_dir
- What the SLURM resource envelope is

Write these down in both `CLAUDE.md` files (HPC repo and submodule) before
any code is written. The Virome integration required back-and-forth because
the multi-container design wasn't anticipated. A pre-agreed contract would
have made that seamless.

### R7 — Add named container checks to multi-container pre-flights
The virome SLURM template checks `*.sif` exists but doesn't verify which
containers are present. A missing `kraken2.sif` will produce a Nextflow
process failure deep in the run rather than a clean pre-flight error. Add
explicit checks:
```bash
for sif in fastqc trimmomatic star kraken2 python multiqc; do
    if [ ! -f "$PIPELINE_REPO/${sif}.sif" ]; then
        echo "ERROR: Missing container: ${sif}.sif"
        exit 1
    fi
done
```

### R8 — Document the BulkRNASeq UTDal dependency as technical debt
The split dependency in BulkRNASeq should be tracked as a known issue.
When BulkRNASeq is next revised, the UTDal scripts should be absorbed into
the `mwilde49/bulkseq` submodule. Until then, `tjp-setup` should print a
clear warning when the UTDal clone is missing, not just a passive `warn`.

---

*Last updated: 2026-04-05*
