# ADR-005: Run 10x Genomics tools natively without containers

**Status:** Accepted
**Date:** 2026-03-10 (implemented in v5.0.0)

---

## Context

All other pipelines in this framework use Apptainer containers for reproducibility and environment isolation. Adding Cell Ranger, Space Ranger, and Xenium Ranger required a decision: containerize the 10x tools, or install them natively on the HPC?

10x Genomics tools are distributed as self-contained tarballs. They ship with their own internal binaries, Rust dependencies, and reference-genome-building toolchains. They are designed to manage their own execution environment.

---

## Decision

Run 10x tools natively — install from tarballs to `/groups/tprice/opt/<tool>-<version>/`, create symlinks at `/groups/tprice/software/<tool>`, and call the tools directly from SLURM wrapper scripts. No Apptainer.

The framework's `is_native_pipeline()` function gates native-specific logic (no bind mounts, no SIF checksum in manifest, `--exclusive` SLURM flag, tool version in manifest instead of container hash).

---

## Alternatives Considered

**Build Apptainer containers for 10x tools:**
- Pros: consistent with all other pipelines; reproducibility enforced by container SIF checksum
- Cons: 10x tools are closed-source, distributed as compiled tarballs; building from source is not supported; wrapping a tarball extraction in a container definition file adds complexity with no benefit; 10x tools' self-contained design means the tarball IS the reproducible artifact; Cell Ranger is ~6 GB uncompressed — building a container would add another 6 GB SIF file to manage

**Use Docker + conversion to Apptainer:**
- Pros: 10x publishes Docker images for some tools
- Cons: Docker is not available on Juno; converting Docker → Apptainer adds a build step; version management becomes more complex

**Native execution via module system:**
- Pros: standard HPC approach
- Cons: Juno does not have the 10x tools in its module system; maintaining module files requires sysadmin involvement; the group's tools live in `/groups/tprice/opt/`, not in the system module tree

---

## Consequences

- Upgrading a 10x tool requires a manual tarball installation and symlink update — no automated container rebuild
- The manifest records `native:<tool_path>` as the container_file and the tool version (from `cellranger --version`) as the container_checksum — less rigorous than a SIF checksum but still useful for audit trails
- The `--exclusive` SLURM flag is required because 10x tools expect sole access to the node's memory; this increases queue wait time compared to non-exclusive jobs
- The `tool_path:` config key allows per-run tool version overrides without changing the default symlink — useful for testing new Cell Ranger versions before upgrading the shared symlink
- Long-term: if 10x publishes official Apptainer images or a lightweight Docker image becomes practical, this decision should be revisited
