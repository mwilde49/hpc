# DeconvATAC Pipeline — HPC Guide

Spatial ATAC/transcriptomics deconvolution using
[deconvATAC](https://github.com/theislab/deconvATAC) + Cell2Location.
Container and pipeline code: `mwilde49/dconvatac` (submodule at `containers/dconvatac/`).

---

## Setup

### 1. Pull the submodule

```bash
cd /groups/tprice/pipelines
git submodule update --init containers/dconvatac
```

### 2. Build the container (requires sudo or fakeroot)

```bash
cd containers/dconvatac/container
sudo ./build.sh
# Produces: dconvatac_v1.0.0.sif
```

If building on a local machine, transfer to HPC:

```bash
scp containers/dconvatac/container/dconvatac_v1.0.0.sif \
    juno:/groups/tprice/pipelines/containers/dconvatac/
```

### 3. Run `tjp-setup` (if not done)

```bash
tjp-setup
# Creates /work/$USER/pipelines/dconvatac/config.yaml
```

---

## Single run (CPU)

```bash
vi /work/$USER/pipelines/dconvatac/config.yaml
tjp-launch dconvatac
```

## Single run (GPU — A30 partition)

Set `use_gpu: true` in your config, then:

```bash
tjp-launch dconvatac-gpu
```

The GPU template requests one NVIDIA A30 (24 GB VRAM, partition `a30`).
For very large datasets or many epochs, substitute `h100` partition and
`gpu:nvidia_h100_80gb_hbm3:1` in the SLURM template.

## Batch run (multiple spatial samples)

```bash
cp templates/dconvatac/samplesheet.csv /work/$USER/pipelines/dconvatac/samplesheet.csv
vi /work/$USER/pipelines/dconvatac/samplesheet.csv   # one row per sample
tjp-batch dconvatac samplesheet.csv
# or for GPU:
tjp-batch dconvatac-gpu samplesheet.csv --config /work/$USER/pipelines/dconvatac-gpu/config.yaml
```

One SLURM job per samplesheet row.

---

## Config reference

| Key | Default | Description |
|-----|---------|-------------|
| `spatial_h5ad` | **required** | Path to spatial AnnData `.h5ad` |
| `reference_h5ad` | **required** | Path to single-cell reference `.h5ad` |
| `labels_key` | **required** | `obs` column name for cell type labels |
| `output_dir` | **required** | Directory for outputs (created if absent) |
| `run_hvp` | `true` | Run highly variable peak selection |
| `N_cells_per_location` | `8` | Expected cells per spatial location |
| `detection_alpha` | `20` | Cell2Location detection model parameter |
| `max_epochs_spatial` | `400` | Training epochs — spatial model |
| `max_epochs_ref` | `400` | Training epochs — reference model |
| `use_gpu` | `false` | Enable GPU training (requires `dconvatac-gpu` pipeline) |

---

## Outputs

Written to `output_dir`:

| File | Description |
|------|-------------|
| `spatial_deconvolved.h5ad` | Spatial AnnData with posterior cell abundances in `.obsm` |
| `reference_annotated.h5ad` | Reference AnnData with Cell2Location model metadata |
| `spatial_cell_abundances.png` | Spatial plots — one panel per cell type |

Cell abundances in `adata_st.obsm`:
- `means_cell_abundance_w_sf` — posterior mean
- `q05_cell_abundance_w_sf` — 5th percentile (plotted)
- `q95_cell_abundance_w_sf` — 95th percentile

---

## SLURM resources

| Pipeline | Partition | Time | CPUs | Memory | GPU |
|----------|-----------|------|------|--------|-----|
| `dconvatac` | normal | 24h | 16 | 128 GB | — |
| `dconvatac-gpu` | a30 | 24h | 16 | 128 GB | 1× A30 (24 GB) |

---

## References

- [deconvATAC documentation](https://deconvatac.readthedocs.io)
- [Cell2Location paper](https://doi.org/10.1038/s41587-021-01139-4)
- [Russell et al. tutorial](https://deconvatac.readthedocs.io/en/latest/notebooks/run_cell2location_russell.html)
