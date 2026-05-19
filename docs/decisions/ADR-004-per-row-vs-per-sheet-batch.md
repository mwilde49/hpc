# ADR-004: Per-row vs per-sheet batch dispatch modes

**Status:** Accepted
**Date:** 2026-04-05 (implemented in v6.0.0)

---

## Context

`tjp-batch` was introduced in v6.0.0 to allow submitting multiple pipeline runs from a CSV samplesheet. The question was: for a samplesheet with N rows, should `tjp-batch` submit N SLURM jobs (one per row), or one SLURM job that processes all rows?

The answer depends on the pipeline's execution model:
- **Nextflow pipelines** (BulkRNASeq, Psoma, Virome) internally manage per-sample parallelism. They accept a samplesheet as input and handle all samples within one Nextflow invocation.
- **Native 10x pipelines** (Cell Ranger, Space Ranger, Xenium Ranger) are designed for single-sample runs. Each tool invocation processes exactly one sample and manages its own parallelism within the node.
- **Long-read pipelines** (SQANTI3, wf-transcriptomes) are also single-sample per invocation.

---

## Decision

Two modes:
- **Per-sheet**: BulkRNASeq, Psoma, Virome — `tjp-batch` submits one SLURM job, passes the entire CSV to Nextflow as a samplesheet.
- **Per-row**: Cell Ranger, Space Ranger, Xenium Ranger, SQANTI3, wf-transcriptomes — `tjp-batch` submits one SLURM job per CSV row.

The dispatch logic lives in `bin/tjp-batch`, gated by pipeline name.

---

## Alternatives Considered

**Per-row for all pipelines:**
- Pros: simple, uniform
- Cons: Nextflow pipelines would lose their internal parallelism; each row would spin up a new Nextflow head job, defeating the whole point of Nextflow's DAG executor

**Per-sheet for all pipelines:**
- Pros: one job to monitor
- Cons: 10x tools cannot process multiple samples in one invocation; would require wrapping them in a loop script, adding complexity and making monitoring harder

**User-specified mode:**
- Pros: maximum flexibility
- Cons: requires users to understand the difference; more error-prone; violates the principle that the framework should hide execution complexity

---

## Consequences

- New pipelines added to the framework must be explicitly assigned to one mode in `bin/tjp-batch`
- Per-row mode creates N separate run directories and N PLR-xxxx records, which is appropriate for independent samples
- Per-sheet mode creates one run directory for all samples; the Titan record captures the batch as a single PLR-xxxx entry — this may need refinement when Titan comes online and multi-sample records need individual tracking
- The batch run directory structure differs between modes: per-row creates `batch_runs/$BATCH_TS/row_$N/`, per-sheet creates `batch_runs/$BATCH_TS/` directly
