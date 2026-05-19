# ADR-001: Use SLURM DAG instead of Nextflow for SQANTI3

**Status:** Accepted
**Date:** 2026-04-04

---

## Context

SQANTI3 is a four-stage long-read transcript quality control pipeline:
1. Stage 1a — long-read QC (`sqanti3_qc.py`)
2. Stage 1b — reference QC (separate process, can run concurrently with 1a)
3. Stage 2 — filtering (depends on 1a)
4. Stage 3 — rescue (depends on 2, optionally references 1b output)

The two preceding pipelines in this codebase (BulkRNASeq and Psoma) use Nextflow for orchestration. Adding SQANTI3 required a choice between Nextflow and native SLURM dependency chaining.

The key constraint: SQANTI3's Python scripts require unpredictably large memory (depending on transcript count) and benefit from dynamic resource allocation at submission time — something Nextflow can do but requires more infrastructure to configure on Juno.

---

## Decision

Implement the SQANTI3 DAG using SLURM's native `--dependency afterok:<job_id>` mechanism. The orchestrator script (`sqanti3_slurm_template.sh`) submits all four SLURM jobs at once, with the dependency chain wired in bash. Resources (CPU, memory) are computed from the GTF transcript count before submission.

---

## Alternatives Considered

**Nextflow with SLURM executor**
- Pros: consistent with BulkRNASeq/Psoma, portable to other clusters
- Cons: requires a Nextflow head job running for the full pipeline duration; adds Nextflow infrastructure to the `longreads` submodule; dynamic resource scaling would need a custom `beforeScript` hook

**Single large SLURM job (sequential stages)**
- Pros: simplest implementation
- Cons: wastes walltime — stages 1a and 1b can run in 4–6 hours concurrently, but sequential execution would double that; the node sits idle during the wait

**Snakemake**
- Pros: expressive DAG syntax, good SLURM support
- Cons: not installed on Juno; would require a container or module; adds a new dependency to the framework

---

## Consequences

- The SQANTI3 pipeline does not use Nextflow, making it the only non-Nextflow multi-stage pipeline in the framework
- Dynamic resource scaling (auto-sizing CPUs and memory based on GTF size) was implemented in the orchestrator script — this logic must be maintained whenever resource defaults change
- Stage scripts live in the `containers/sqanti3/` submodule (`containers/sqanti3/slurm_templates/`), not in the top-level `slurm_templates/`; the top-level orchestrator is a thin wrapper
- `wf-transcriptomes` (the pipeline that *precedes* SQANTI3) was later added using Nextflow as a head job — the two long-read pipelines use different execution models, which can confuse new contributors
