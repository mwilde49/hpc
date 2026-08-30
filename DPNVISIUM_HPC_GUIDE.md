# dpnvisium Pipeline — HPC Guide

Visium spatial transcriptomics deconvolution using
[Cell2Location](https://cell2location.readthedocs.io) for the ish_dpn
(Diabetic Peripheral Neuropathy) collaboration project. Container and
pipeline code: `mwilde49/dpnvisium` (submodule at `containers/dpnvisium/`).

Two-stage workflow: (1) RegressionModel signature training on an snRNA-seq
reference, (2) Cell2location spatial deconvolution jointly across all
concatenated Visium samples. See `ishdpn/c2l_TEMPLATE.ipynb` in the workspace
for the original notebook this pipeline was converted from.

---

## Setup

### 1. Pull the submodule
```bash
cd /groups/tprice/pipelines
git submodule update --init containers/dpnvisium
```

### 2. Build the container (requires sudo or fakeroot)
```bash
cd containers/dpnvisium/container
sudo apptainer build ../dpnvisium_v1.0.0.sif apptainer.def
```

### 3. Run `tjp-setup` (if not done)
```bash
tjp-setup
# Creates /work/$USER/pipelines/dpnvisium/config.yaml
```

---

## Single run (CPU, small/test configs only — dev partition, 2h limit)
```bash
vi /work/$USER/pipelines/dpnvisium/config.yaml
tjp-launch dpnvisium
```

## Production run (GPU — H100 partition, full-batch, all samples)
```bash
tjp-launch dpnvisium-gpu
```

The GPU template requests one NVIDIA H100 (80GB VRAM). This is deliberately
H100, not A30 (24GB) — production config trains with `spatial_batch_size:
null` (full-batch) across all 16 concatenated Visium samples (40,599
spots), which the dconvatac guide's own precedent already flags as exceeding
A30's 24GB for datasets this size. Set `spatial_batch_size` to a bounded
integer (e.g. 2048) in config.yaml if you need to run on A30 instead —
substitute the partition/gres lines in the GPU SLURM template.

---

## Config reference

| Key | Default | Description |
|-----|---------|-------------|
| `input_sn_counts` / `input_sn_meta` | **required** | snRNA-seq reference counts/metadata CSVs |
| `input_visium_dir` | **required** | Directory containing one subdirectory per Visium sample (10x Space Ranger output layout) |
| `output_dir` | **required** | Directory for outputs (created if absent) |
| `sample_subset` | `null` | Optional list to process only specific sample dirs |
| `N_cells_per_location` | `15` | Tissue-density hyperprior (DRG-specific — see source notebook) |
| `detection_alpha` | `20` | Human Visium value; use `200` for mouse |
| `max_epochs_ref` / `max_epochs_spatial` | `250` / `5000` | Training epochs, reference / spatial stage |
| `spatial_batch_size` | `null` | `null` = full-batch (production, needs H100); set an int to bound memory |
| `run_nmf_colocation` | `true` | NMF cellular-compartment colocation analysis |
| `compute_expected_per_cell_type` | `true` | Per-cell-type expected expression (needed for downstream NCEM) |
| `force_ref` / `force_spatial` | `false` | Retrain even if a saved model already exists (save/resume by default) |

Full field list: `templates/dpnvisium/config.yaml`.

---

## Outputs

Written to `output_dir`:
- `reference_signatures/` — RegressionModel + `sc.h5ad`
- `cell2location_map/` — Cell2location model, `sp.h5ad`, `CoLocatedComb/` (NMF)
- `cell2location_{means,stds,q05,q95}_cell_abundance_w_sf.csv`
- `rna_percentages_by_cell_type.csv`, `rna_content_per_cell_type_total.csv`
- `region_cluster_labels.csv`
- `{sample}_deconv.pdf` — one per Visium sample

---

## SLURM resources

| Pipeline | Partition | Time | CPUs | Memory | GPU |
|----------|-----------|------|------|--------|-----|
| `dpnvisium` | dev | 2h | 8 | 32 GB | — |
| `dpnvisium-gpu` | h100 | 12h | 16 | 128 GB | 1× H100 (80 GB) |

---

## Batch launching

`dpnvisium` is **not** wired into `tjp-batch`. Unlike dconvatac (per-row) or
bulkrnaseq/psoma/virome (per-sheet), `dpnvisium.py` doesn't read a
samplesheet at all — it auto-discovers every sample directory under
`input_visium_dir` (or the config's `sample_subset` list) and trains
Cell2location jointly across all of them in a single job, since that's how
the underlying model works. The samplesheet template that ships with this
pipeline exists only for registry-convention parity; the real launch path is
always `tjp-launch dpnvisium[-gpu]` against a single `config.yaml`. If a
per-cohort batch is ever needed, set `sample_subset` per config and launch
each cohort as its own `tjp-launch` run.

---

## References

- [Cell2location tutorial](https://cell2location.readthedocs.io/en/latest/notebooks/cell2location_tutorial.html)
- [Cell2location paper](https://doi.org/10.1038/s41587-021-01139-4)
- Source notebook: `ishdpn/c2l_TEMPLATE.ipynb`
