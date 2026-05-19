# ADR-003: Use `titan_` prefix for metadata fields in config YAMLs

**Status:** Accepted
**Date:** 2026-04-05 (implemented in v6.0.0)

---

## Context

Version 6.0.0 introduced Titan integration — optional metadata fields in config YAMLs that will eventually feed a LIMS PostgreSQL database. The fields are:
- `project_id` → PRJ-xxxx
- `sample_id` → SMP-xxxx
- `library_id` → LIB-xxxx
- `run_id` → RUN-xxxx

The problem: several native tools already use some of these bare names. Cell Ranger uses `sample_id` natively as the output directory name. Space Ranger also uses `sample_id`. If config YAMLs included both a native `sample_id` (for the tool) and a metadata `sample_id` (for Titan), the pipeline wrapper would need complex disambiguation logic.

---

## Decision

All Titan metadata fields are prefixed with `titan_` in config YAMLs:
- `titan_project_id`
- `titan_sample_id`
- `titan_library_id`
- `titan_run_id`

The `labdata` / `metadata.sh` library strips the prefix when writing to the Titan JSON schema.

Samplesheet CSV columns use the unprefixed names (`project_id`, `sample_id`, etc.) because there is no ambiguity in CSV context — the columns are separate from tool-specific fields.

---

## Alternatives Considered

**Namespace under a YAML block (e.g., `titan: { project_id: PRJ-xxxx }`):**
- Pros: cleaner YAML structure
- Cons: `yaml_get` — the existing flat-key parser used throughout the framework — cannot handle nested keys; would require a new YAML parser or a different parsing strategy for the Titan block

**Use bare names everywhere:**
- Pros: shorter config files
- Cons: direct naming conflict with Cell Ranger's native `sample_id` field; would require the wrapper to know which `sample_id` is which

**Separate metadata sidecar file:**
- Pros: complete separation of metadata from pipeline config
- Cons: users must manage two files per run; `tjp-launch` would need to locate and validate the sidecar; more complex onboarding

---

## Consequences

- Config files for all 11 pipelines contain a `titan_` section, adding ~5 lines to each config even when Titan is not yet active
- When Titan comes online, no user-visible config format change is needed — users already have the fields; they just need to populate them
- The `yaml_get` constraint (flat keys only) is now formally load-bearing; adding nested YAML support would require revisiting this decision
