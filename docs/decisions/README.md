# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) — short documents that capture significant design choices made in the TJP HPC Pipeline Framework.

Each ADR explains the context, the options considered, and the rationale for the choice made. These records help future maintainers understand *why* the system is built the way it is, not just *what* it does.

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-001](ADR-001-slurm-vs-nextflow-for-sqanti3.md) | Use SLURM DAG instead of Nextflow for SQANTI3 | Accepted |
| [ADR-002](ADR-002-scratch-staging.md) | Stage pipeline outputs to scratch, archive to work | Accepted |
| [ADR-003](ADR-003-titan-prefix-convention.md) | Use `titan_` prefix for metadata fields in config YAMLs | Accepted |
| [ADR-004](ADR-004-per-row-vs-per-sheet-batch.md) | Per-row vs per-sheet batch dispatch modes | Accepted |
| [ADR-005](ADR-005-native-execution-for-10x.md) | Run 10x Genomics tools natively without containers | Accepted |

## Format

Each ADR follows this structure:
- **Status**: Proposed / Accepted / Superseded / Deprecated
- **Context**: The problem or constraint that triggered this decision
- **Decision**: What was decided
- **Alternatives considered**: Other options that were evaluated
- **Consequences**: Trade-offs accepted as a result of this choice
