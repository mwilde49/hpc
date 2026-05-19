# ADR-002: Stage pipeline outputs to scratch, archive to work

**Status:** Accepted
**Date:** 2026-03-08 (implemented in v3.1.0)

---

## Context

Juno HPC has two main user storage tiers:
- **Scratch** (`/scratch/juno/$USER/`): ~1 TB, fast NVMe/parallel filesystem, wiped every 45 days
- **Work** (`/work/$USER/`): durable (but quota-limited), slower, backed up

Pipelines write large intermediate files (BAMs, temporary alignment indices, per-sample intermediates). Writing all output directly to work would:
1. Exhaust work quotas quickly with transient intermediates
2. Be slower due to work's lower I/O bandwidth
3. Leave partial outputs in work if a job fails midway

---

## Decision

All pipeline I/O during execution goes to scratch. After a successful pipeline run, `tjp-launch` invokes rsync with `--checksum` to archive inputs (FASTQs) and final outputs (BAMs, count matrices, reports) from scratch into a timestamped run directory under work:

```
/work/$USER/pipelines/<pipeline>/runs/YYYY-MM-DD_HH-MM-SS/
├── config.yaml        # snapshot at launch time
├── manifest.json      # reproducibility record
├── slurm/            # SLURM job logs
├── inputs/           # archived input FASTQs
└── outputs/          # archived pipeline outputs
```

---

## Alternatives Considered

**Write directly to work**
- Pros: one fewer copy step; simpler code
- Cons: slower I/O; work quota fills with intermediates; partial failures leave debris in work

**Write to scratch only (no archive)**
- Pros: simplest
- Cons: 45-day wipe destroys results; users must manually copy outputs before scratch purge

**User-managed rsync after completion**
- Pros: user control
- Cons: requires user discipline; easy to forget; not reproducible (what gets archived depends on when the user remembers to run rsync)

---

## Consequences

- Every successful run generates two copies of large files (scratch + work) during the rsync window
- SQANTI3 and wf-transcriptomes write directly to their configured `outdir:` and do NOT use scratch staging — the rule is pipeline-specific, not universal. These long-read pipelines write outputs once, directly to work, because their intermediate files are smaller and the DAG structure makes scratch staging more complex
- Native 10x pipelines (Cell Ranger, Space Ranger, Xenium Ranger) use a `scratch_output_dir` key in the config to allow users to redirect scratch I/O when needed (e.g., a project-specific scratch path)
- The `rsync --checksum` flag catches bit-rot at archive time, but means rsync touches every file — slower than `--size-only` for large datasets
