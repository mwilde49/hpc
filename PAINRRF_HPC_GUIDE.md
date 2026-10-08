# painrrf Pipeline — HPC Guide

DRG pain-state prediction from human single-nucleus RNA-seq — the V41
"Representation Robustness Framework." Container and pipeline code:
`mwilde49/painrrf` (submodule at `containers/painrrf/`).

Sample-level pseudobulk features (`pb_mean`/`pb_frac` per gene, aggregated
from single-cell data) → `StandardScaler` → `LogisticRegressionCV` →
predicted probability, evaluated via Leave-One-Batch-Out cross-validation.
**CPU-only, no GPU variant** — the underlying model is plain logistic
regression (no deep learning, no CUDA); a neural network was explicitly
ruled out for this work by the project lead. See `containers/painrrf/README.md`
for the full architecture and known limitations.

---

## Setup

### 1. Pull the submodule
```bash
cd /groups/tprice/pipelines
git submodule update --init containers/painrrf
```

### 2. Build the container (requires sudo or fakeroot)
```bash
cd containers/painrrf/pipeline/container
apptainer build --fakeroot ../../../containers/painrrf_v0.1.0.sif apptainer.def
# or, if fakeroot isn't usable on this node:
sudo apptainer build ../../../containers/painrrf_v0.1.0.sif apptainer.def
```

### 3. Run `tjp-setup` (if not done)
```bash
tjp-setup
# Creates /work/$USER/pipelines/painrrf/config.yaml
```

---

## Single run (CPU only — dev partition, 2h limit)
```bash
vi /work/$USER/pipelines/painrrf/config.yaml
tjp-launch painrrf
```

There is no `painrrf-gpu` variant and none is planned by default — see the
architecture note above. If the full ~664k-cell all-cell-types atlas load
step ever turns out to need GPU-accelerated array ops, that would be a
future, evidence-driven addition, not a day-one design choice.

---

## Config reference

| Key | Required | Description |
|-----|----------|--------------|
| `input_h5ad` | yes | Path to the Cody DRG neuron (or later, all-cell-type) h5ad |
| `output_dir` | yes | Not yet honored by `painrrf.py` — see **Outputs** below for where results actually land |
| `stage` | yes | One of `discovery` / `tier_filter` / `validate` / `external_check` / `transfer` / `all` |
| `h5ad_name` | — | Basename used by the real V41 scripts' own BASE_DIR-relative fallback resolution |
| `run_external_validation` | — | `false` by default; set `true` to have `stage: all` also run `external_check` + `transfer` |
| `seed`, `n_hvgs`, `min_cells`, `C_range` | — | Core model/data params, pulled verbatim from `04`/`05`/`06`'s own `CONFIG` dicts |
| `force_discovery` / `force_tier_filter` / `force_validate` | — | Re-run a stage even if a prior run's output would be reused |

Full field list, pulled verbatim from the real script `CONFIG` dicts (not
reinvented): `templates/painrrf/config.yaml` / `templates/schemas/painrrf.yaml`.

---

## Outputs

**`output_dir` is not yet honored.** `painrrf.py` wraps the real,
unmodified V41 scripts (`04`-`06`) without patching their internals, and
those scripts write to timestamped `run_*/` directories under their own
location: `containers/painrrf/V41/V41_Framework_Development/run_*/`. The
SLURM template collects each invocation's own `run_*` dirs (by mtime) into
`$RUN_DIR/outputs/` after the job finishes, so check there first — don't
expect anything at the `output_dir` path from `config.yaml` itself.

Per stage:
- `discovery` (`04`) → `v41_core_panel.csv`, `v41_bootstrap_stability.csv`, `v41_candidate_pool_summary.csv`, `v41_stable_panel_report.md`
- `tier_filter` (`05`) → `v41_gene_evidence.csv`, `v41_gene_evidence_report.md`
- `validate` (`06`) → `v41_tier1_panel_auc_summary.csv`, `v41_tier1_panel_lobo_folds.csv`, `v41_tier1_panel_report.md` — the headline LOBO-CV AUC numbers (raw vs. QC-residualized) live here
- `external_check`/`transfer` (`07`-`10`) → external-cohort replication/cross-dataset-transfer reports (needs `data/external_validation/` staged — see `containers/painrrf/data/external_validation/PROVENANCE.md`)

No real patient data is ever written to a committed location — gene-level/
aggregate CSVs only, no row-level sample metadata beyond `sampleID`/`Batch`/
predicted probability.

---

## SLURM resources

| Pipeline | Partition | Time | CPUs | Memory | GPU |
|----------|-----------|------|------|--------|-----|
| `painrrf` | dev | 2h | 8 | 32 GB | — |

**Not measured, an initial guess** sized for pseudobulk-scale work
(85-120-sample LOBO-CV, a few hundred features) — revisit with real numbers
once a full all-cell-types-atlas run exists.

---

## Batch launching

`painrrf` is **not** wired into `tjp-batch`, same reasoning as `dpnvisium`:
it processes one atlas jointly across its whole pipeline (LOBO
cross-validation over all batches, panel discovery over the full sample
set) — there's no natural "one row = one job" unit. `templates/painrrf/samplesheet.csv`
exists only for registry-convention parity, not a real batching input.

---

## Known limitations (read before trusting output)

- Three independently hand-rolled LOBO+QC-residualization implementations
  exist across `04`/`05`/`06`, not yet consolidated onto a single shared,
  leakage-safe version — a deliberate, flagged-for-sign-off decision.
- The exact ATF3/PEP/NP/Prop/LTMR neuronal-subtype view grouping is
  unrecovered; the V29-compatible shim defaults to one view per raw
  `anno_lvl3` category instead (affects discovery-stage view-level
  features, not panel-level validation AUCs).
- See `containers/painrrf/README.md` for the full, current list.

---

## References

- Source research workspace: `mlandi/` (`V30/`, `V31/`, `V41/` — original
  dev code; `docs/V27_V29_GAP.md` for the data-loading reconstruction
  history; `PRODUCTIONIZATION_STATUS.md` for the full validation history)
