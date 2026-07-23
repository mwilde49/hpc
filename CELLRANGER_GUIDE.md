# Cell Ranger Suite — HPC Guide

**Framework version:** 7.1.0 | **Cell Ranger version:** 10.0.0 | **Cluster:** Juno HPC, UT Dallas

The Cell Ranger suite covers three distinct pipelines that map a typical 10x Genomics single-cell workflow from raw instrument data to analysis-ready matrices:

| Pipeline | Command | Purpose |
|----------|---------|---------|
| Cell Ranger mkfastq | `tjp-launch cellranger-mkfastq` | BCL → FASTQ demultiplexing (run first if you got a BCL folder from the sequencing core) |
| Cell Ranger | `tjp-launch cellranger` | Single-library gene expression: one FASTQ dir → one count matrix |
| Cell Ranger Multi | `tjp-launch cellranger-multi` | Multi-library: GEX + VDJ (immune profiling), CITE-seq, CellPlex, Flex, CRISPR screens |

All three are **native pipelines** — no Apptainer container, no Nextflow. Cell Ranger manages its own threading via `--localcores`/`--localmem` and is given an exclusive SLURM node.

---

## Decision Tree: Which Pipeline Do I Need?

```
Did you receive a BCL folder from the sequencing core?
    YES ──→  Run cellranger-mkfastq first to get FASTQs,
             then continue below with those FASTQs.
    NO  ──→  You already have FASTQs. Continue below.

Do you have more than one library type for this sample?
(VDJ, antibodies, CMO multiplexing, CRISPR guides, Flex probes)
    YES ──→  Use cellranger-multi
    NO  ──→  Is it a plain single-cell GEX run (one FASTQ dir)?
                YES ──→  Use cellranger (count)
                NO  ──→  Confirm with the guide below or ask Michael
```

**Quick reference:**
- BCL folder from sequencer → `cellranger-mkfastq`
- Standard 3' or 5' GEX, no additional libraries → `cellranger`
- Immune profiling (GEX + TCR or BCR) → `cellranger-multi`
- Protein panels / CITE-seq → `cellranger-multi`
- CellPlex pooled samples → `cellranger-multi`
- Flex (fixed RNA) → `cellranger-multi`
- CRISPR screens → `cellranger-multi`

---

## Tool Installation

Cell Ranger 10.0.0 is pre-installed at a versioned directory with a stable symlink:

| | Path |
|--|------|
| Versioned install | `/groups/tprice/opt/cellranger-10.0.0/` |
| Stable symlink | `/groups/tprice/software/cellranger` → `cellranger-10.0.0` |

The framework always uses the symlink path. To confirm the active version:

```bash
/groups/tprice/software/cellranger/cellranger --version
```

You do not need to load any modules or set `PATH` for Cell Ranger itself — the SLURM template resolves the binary automatically via the symlink.

---

## Cell Ranger mkfastq (BCL Demultiplexing)

### When to Use

Use `cellranger-mkfastq` when you received an Illumina BCL run folder from the sequencing core instead of pre-demultiplexed FASTQs. The tool wraps Illumina's `bcl2fastq` with 10x-specific logic to produce per-sample FASTQ directories ready for `cellranger` or `cellranger-multi`.

If your sequencing core already delivered `.fastq.gz` files, skip this step entirely.

### Preparing Your SampleSheet.csv

`cellranger-mkfastq` uses a standard Illumina-format `SampleSheet.csv`. The critical section is `[Data]`, which must include at least these columns:

```
[Header]
Date,2024-01-15
Workflow,GenerateFASTQ

[Reads]
28
90

[Settings]
Adapter,CTGTCTCTTATACACATCT

[Data]
Lane,Sample_ID,Sample_Name,index,index2
1,sample01,sample01,SI-TT-A1,
1,sample02,sample02,SI-TT-B1,
```

For 10x Genomics libraries:
- `index` is the 10x dual-index name (e.g., `SI-TT-A1`) or the actual i7 sequence
- `index2` is the i5 sequence (leave blank for single-indexed libraries)
- `Lane` can be `*` to process all lanes

If you received the `SampleSheet.csv` from the sequencing core alongside the BCL folder, use it directly.

### Full Config Reference

Edit `/work/$USER/pipelines/cellranger-mkfastq/config.yaml`:

```yaml
run_id: my_run               # Output folder name (e.g., 20240115_RunA or ProjectName)

# Input paths
run_dir: /scratch/juno/YOUR_NETID/bcl/run_folder        # Illumina BCL run folder from sequencer
samplesheet: /scratch/juno/YOUR_NETID/bcl/SampleSheet.csv  # Illumina-format SampleSheet.csv

# Resource allocation (match your SLURM allocation)
localcores: 16
localmem: 120                # GB — leave ~8 GB headroom below SLURM --mem

# Tool path (default: /groups/tprice/software/cellranger)
tool_path: /groups/tprice/software/cellranger

# Optional parameters (uncomment to use)
# lanes: 1,2                 # Process specific lanes only (comma-separated)
# rc_i2_override: true       # Reverse-complement Index 2 (sometimes needed for NovaSeq X)
# filter_single_index: true  # Only process single-indexed samples
# filter_dual_index: true    # Only process dual-indexed samples
# qc: true                   # Generate QC metrics report

# Titan integration (optional)
titan_project_id:   # PRJ-xxxx
titan_sample_id:    # SMP-xxxx
titan_library_id:   # LIB-xxxx
titan_run_id:       # RUN-xxxx
```

### Example Launch

```bash
# Edit config
vi /work/$USER/pipelines/cellranger-mkfastq/config.yaml

# Single run
tjp-launch cellranger-mkfastq

# Batch (one demux job per BCL folder)
tjp-batch cellranger-mkfastq /work/$USER/pipelines/cellranger-mkfastq/samplesheet.csv

# Dry run to preview
tjp-batch cellranger-mkfastq samplesheet.csv --dry-run

# Monitor
squeue -u $USER
```

Batch samplesheet format:

```csv
run_id,run_dir,samplesheet,project_id,sample_id,library_id,run_id
run20240115,/scratch/juno/$USER/bcl/run20240115,/scratch/juno/$USER/bcl/SampleSheet.csv,,,,
```

### Output Structure

```
<run_id>/outs/fastq_path/
└── <project>/
    └── <sample>/
        ├── <sample>_S1_L001_R1_001.fastq.gz
        ├── <sample>_S1_L001_R2_001.fastq.gz
        ├── <sample>_S1_L001_I1_001.fastq.gz
        └── <sample>_S1_L001_I2_001.fastq.gz
```

Also written: `<run_id>/outs/qc_summary.json` (metrics), `<run_id>/outs/input_samplesheet.csv` (audit copy).

### What to Do With the Output

Pass the `fastq_path` directory to the next step. The path to give `cellranger` or `cellranger-multi` is:

```
/scratch/juno/$USER/pipelines/cellranger-mkfastq/runs/<timestamp>/<run_id>/outs/fastq_path/
```

Use this as `fastq_dir` in the `cellranger` config, or as `fastqs:` in the `libraries:` block of a `cellranger-multi` config.

**Edge cases:**
- `rc_i2_override: true` is sometimes required for newer NovaSeq X instruments where i5 orientation changed
- `lanes: 1,2` is useful when you only ran certain lanes and want to exclude undetermined reads from others
- The `SampleSheet.csv` `[Data]` section must include a `Sample_ID` column; mismatches between `Sample_ID` and the FASTQ prefix are a common source of "sample not found" errors in downstream steps

---

## Cell Ranger (Count — Single-Cell Gene Expression)

### When to Use

Use `cellranger` for standard single-library 10x scRNA-seq runs:
- 3' gene expression (3' v3, 3' v3.1, 3' HT)
- 5' gene expression (5' v2, 5' v3, 5' PE)
- Single-nucleus RNA-seq (snRNA-seq) with `include_introns: true`

Do not use `cellranger` if your sample has VDJ, antibody, CMO, or CRISPR libraries — use `cellranger-multi` instead.

### Required References (Pre-Installed on Juno)

| Reference | Path | Genome |
|-----------|------|--------|
| GEX transcriptome (GRCh38) | `/groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A` | Human |

The `2024-A` build includes GENCODE v44 annotations and is compatible with Cell Ranger 7.0+. Use this path for `transcriptome:` in all human GEX configs.

> If you need a mouse reference or a custom genome, contact Michael — these can be staged at `/groups/tprice/pipelines/references/` on request.

### Full Config Reference

Edit `/work/$USER/pipelines/cellranger/config.yaml`:

```yaml
# Required fields
sample_id: my_sample          # Output directory name (alphanumeric, hyphens, underscores only)
sample_name: MySample         # FASTQ filename prefix — must match <sample_name>_S*_L*_R*.fastq.gz exactly
fastq_dir: /scratch/juno/YOUR_NETID/myproject/fastq   # Directory containing FASTQ files
transcriptome: /groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A

# Resource limits (match your SLURM allocation)
localcores: 16
localmem: 120                 # GB — leave ~8 GB headroom below SLURM --mem

# BAM output — REQUIRED for Cell Ranger 10.0.0+
create_bam: true

# Optional parameters (uncomment to use)
# chemistry: auto             # auto | SC3Pv3 | SC3Pv3HT | SC5P-PE | SC5P-R2 | SC3Pv2
# expect_cells: 3000          # Expected cells hint (default: Cell Ranger auto-detects)
# force_cells: 5000           # Force exactly N cells (bypasses knee detection)
# include_introns: true       # Include intronic reads (recommended for snRNA-seq; default true in CR 7+)
# no_bam: false               # Skip BAM generation (mutually exclusive with create_bam)
# tool_path: /groups/tprice/opt/cellranger-10.0.0   # Override default install

# Titan integration (optional)
titan_project_id:   # PRJ-xxxx
titan_sample_id:    # SMP-xxxx
titan_library_id:   # LIB-xxxx
titan_run_id:       # RUN-xxxx
```

### Example Launch

```bash
# Setup (first time only)
tjp-setup    # copies template config to /work/$USER/pipelines/cellranger/config.yaml

# Edit config
vi /work/$USER/pipelines/cellranger/config.yaml

# Single run
tjp-launch cellranger

# Single run with explicit config path
tjp-launch cellranger --config /work/$USER/pipelines/cellranger/config.yaml

# Smoke test (requires test FASTQs on HPC)
tjp-test cellranger
tjp-test-validate cellranger

# Monitor
squeue -u $USER
cat /work/$USER/pipelines/cellranger/runs/<timestamp>/slurm_<JOBID>.out
```

**Batch launch (one SLURM job per sample):**

```bash
vi /work/$USER/pipelines/cellranger/samplesheet.csv
tjp-batch cellranger /work/$USER/pipelines/cellranger/samplesheet.csv
tjp-batch cellranger samplesheet.csv --dry-run    # preview without submitting
tjp-batch cellranger samplesheet.csv --dev        # submit to dev partition
```

Samplesheet format:

```csv
sample,fastqs,transcriptome,sample_name,create_bam,project_id,sample_id,library_id,run_id
sample01,/scratch/juno/$USER/fastq/,/groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A,sample01,true,,,,
sample02,/scratch/juno/$USER/fastq/,/groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A,sample02,true,,,,
```

The `sample` column maps to `sample_id` (the output directory name). `fastqs` maps to `fastq_dir`. All other columns override the corresponding config keys.

### Output Structure

```
<sample_id>/outs/
├── web_summary.html                   # QC summary — open in browser
├── metrics_summary.csv                # Cell count, median genes, saturation, etc.
├── filtered_feature_bc_matrix/        # Analysis-ready sparse matrix (filtered cells only)
│   ├── barcodes.tsv.gz
│   ├── features.tsv.gz
│   └── matrix.mtx.gz
├── raw_feature_bc_matrix/             # All barcodes (unfiltered)
│   ├── barcodes.tsv.gz
│   ├── features.tsv.gz
│   └── matrix.mtx.gz
├── filtered_feature_bc_matrix.h5      # HDF5 format (Seurat / Scanpy compatible)
├── raw_feature_bc_matrix.h5
├── molecule_info.h5                   # Per-molecule UMI data (used by aggr)
├── possorted_genome_bam.bam           # Only present when create_bam: true
├── possorted_genome_bam.bam.bai
├── analysis/                          # Clustering and dimensionality reduction
│   ├── clustering/
│   ├── diffexp/
│   ├── pca/
│   ├── tsne/
│   └── umap/
└── cloupe.cloupe                      # Loupe Browser file
```

The files most commonly used for downstream analysis:
- `filtered_feature_bc_matrix.h5` — load directly in Seurat (`Read10X_h5`) or Scanpy (`sc.read_10x_h5`)
- `filtered_feature_bc_matrix/` — load as a directory in Seurat (`Read10X`) or Scanpy (`sc.read_10x_mtx`)
- `web_summary.html` — review cell count, median genes/cell, sequencing saturation before proceeding

### Edge Cases

- **`create_bam: true` is required.** Cell Ranger 10.0.0 removed the default BAM output. Without this field, the run will error. The validator will catch this before job submission, but always include it in your config.
- **`sample_name` must match the FASTQ prefix exactly.** Cell Ranger looks for files named `<sample_name>_S*_L*_R*.fastq.gz`. If the prefix is `SJ0134_GEX`, set `sample_name: SJ0134_GEX`, not the shorter project name. A mismatch produces "No input FASTQs were found" and the job fails immediately.
- **`SC3Pv3LT` chemistry was dropped in Cell Ranger 10.0.0.** If you have 3' v3 LT data, you cannot use Cell Ranger 10. Contact Michael — the previous version may need to be staged. Do not set `chemistry: SC3Pv3LT` in a CR 10 config.
- **`--exclusive` is set in the SLURM template.** The job gets a full 64-core node. `localcores: 16` limits Cell Ranger's thread count to avoid I/O saturation — do not raise `localcores` beyond 24 without testing.
- **Override the tool install** with `tool_path: /groups/tprice/opt/cellranger-11.0.0` if you need to test a newly staged version without changing the shared symlink.

---

## Cell Ranger Multi (Multi-Library)

### When to Use vs Count

Use `cellranger-multi` (not `cellranger`) when your sample includes any library type beyond plain gene expression:

| Scenario | Use |
|----------|-----|
| GEX only | `cellranger` |
| GEX + TCR (T cell immune profiling) | `cellranger-multi` |
| GEX + BCR (B cell immune profiling) | `cellranger-multi` |
| GEX + antibody tags (CITE-seq / TotalSeq) | `cellranger-multi` |
| GEX + CRISPR guide capture | `cellranger-multi` |
| CellPlex (CMO-based sample multiplexing) | `cellranger-multi` |
| Fixed RNA Profiling (Flex) | `cellranger-multi` |
| GEX + VDJ + antibodies (combined) | `cellranger-multi` |

The wrapper reads your YAML config, generates a Cell Ranger multi CSV internally, and invokes `cellranger multi`. You never write the CSV by hand.

### Feature Types Reference

The `feature_types` field in each `libraries:` entry must be one of:

| Value | Use case |
|-------|----------|
| `Gene Expression` | Standard GEX (3' or 5') |
| `VDJ-T` | T cell receptor (alpha/beta) |
| `VDJ-T-GD` | Gamma-delta T cell receptor |
| `VDJ-B` | B cell receptor (heavy/light) |
| `Antibody Capture` | CITE-seq / TotalSeq protein panels |
| `CRISPR Guide Capture` | CRISPR perturbation screens |
| `Multiplexing Capture` | CellPlex (CMO-based pooled samples) |
| `Fixed RNA Profiling` | Flex / fixed RNA profiling |

### Feature Reference CSV Format

Required for `Antibody Capture` and `CRISPR Guide Capture` libraries. Set `feature_reference:` in your config to point to this file.

**Antibody panel format (CITE-seq / TotalSeq):**

```csv
id,name,read,pattern,sequence,feature_type
CD3_TotalSeqC_0048,CD3,R2,5PNNNNNNNNNN(BC)NNNNNNNNN,CTCATTGTAACTCCT,Antibody Capture
CD4_TotalSeqC_0051,CD4,R2,5PNNNNNNNNNN(BC)NNNNNNNNN,TGTTCCCGCTCAACT,Antibody Capture
CD8a_TotalSeqC_0052,CD8a,R2,5PNNNNNNNNNN(BC)NNNNNNNNN,GCCTTGTCTGTTTGC,Antibody Capture
```

**CRISPR guide library format:**

```csv
id,name,read,pattern,sequence,feature_type
CTRL_guide_1,CTRL_guide_1,R2,5PNNNNNNNNNN(BC)NNNNNNNNN,ACGGAGAGCCAACGCGTCTG,CRISPR Guide Capture
GENE_A_guide_1,GENE_A_guide_1,R2,5PNNNNNNNNNN(BC)NNNNNNNNN,GCGCAACGTTTCCGTTCAGA,CRISPR Guide Capture
```

Columns:
- `id` — unique identifier (used internally)
- `name` — display name in outputs
- `read` — which read contains the barcode (`R2` for most protocols)
- `pattern` — barcode pattern (`5P` = 5' of read, `(BC)` = barcode position)
- `sequence` — barcode sequence
- `feature_type` — must match the value used in `libraries[].feature_types`

10x Genomics provides pre-built feature reference files for TotalSeq panels at [support.10xgenomics.com](https://support.10xgenomics.com). Download the CSV for your panel version and stage it to scratch.

### All 8 Use Cases With Example Configs

#### Use Case 1: GEX Only (via multi)

For a single GEX library. Only use `cellranger-multi` for this if you specifically need multi-specific features; otherwise use `cellranger count` above.

```yaml
sample_id: my_gex_sample
localcores: 16
localmem: 64
scratch_output_dir: /scratch/juno/YOUR_NETID/myproject/cellranger
transcriptome: /groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A
create_bam: true
chemistry: threeprime

libraries:
  - fastq_id: MySample_GEX
    fastqs: /scratch/juno/YOUR_NETID/myproject/fastq
    feature_types: Gene Expression
```

---

#### Use Case 2: GEX + VDJ-T (T Cell Immune Profiling)

```yaml
sample_id: my_tcell_sample
localcores: 16
localmem: 64
scratch_output_dir: /scratch/juno/YOUR_NETID/myproject/cellranger
transcriptome: /groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A
create_bam: true
vdj_reference: /groups/tprice/pipelines/references/refdata-cellranger-vdj-GRCh38-alts-ensembl-7.1.0

libraries:
  - fastq_id: MySample_GEX
    fastqs: /scratch/juno/YOUR_NETID/myproject/fastq
    feature_types: Gene Expression
  - fastq_id: MySample_VDJ
    fastqs: /scratch/juno/YOUR_NETID/myproject/fastq
    feature_types: VDJ-T
```

For gamma-delta TCR profiling, change `feature_types: VDJ-T-GD`.

---

#### Use Case 3: GEX + VDJ-B (B Cell Immune Profiling)

Same structure as VDJ-T; change `feature_types` to `VDJ-B`:

```yaml
sample_id: my_bcell_sample
localcores: 16
localmem: 64
scratch_output_dir: /scratch/juno/YOUR_NETID/myproject/cellranger
transcriptome: /groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A
create_bam: true
vdj_reference: /groups/tprice/pipelines/references/refdata-cellranger-vdj-GRCh38-alts-ensembl-7.1.0

libraries:
  - fastq_id: MySample_GEX
    fastqs: /scratch/juno/YOUR_NETID/myproject/fastq
    feature_types: Gene Expression
  - fastq_id: MySample_VDJ
    fastqs: /scratch/juno/YOUR_NETID/myproject/fastq
    feature_types: VDJ-B
```

---

#### Use Case 4: GEX + Antibody Capture (CITE-seq)

Requires a `feature_reference` CSV listing the antibody panel (see Feature Reference CSV Format above).

```yaml
sample_id: my_citeseq_sample
localcores: 16
localmem: 64
scratch_output_dir: /scratch/juno/YOUR_NETID/myproject/cellranger
transcriptome: /groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A
create_bam: true
feature_reference: /scratch/juno/YOUR_NETID/myproject/antibody_panel.csv

libraries:
  - fastq_id: MySample_GEX
    fastqs: /scratch/juno/YOUR_NETID/myproject/fastq
    feature_types: Gene Expression
  - fastq_id: MySample_AB
    fastqs: /scratch/juno/YOUR_NETID/myproject/fastq
    feature_types: Antibody Capture
```

---

#### Use Case 5: GEX + CRISPR Guide Capture

Requires a `feature_reference` CSV listing the guide library.

```yaml
sample_id: my_crispr_sample
localcores: 16
localmem: 64
scratch_output_dir: /scratch/juno/YOUR_NETID/myproject/cellranger
transcriptome: /groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A
create_bam: true
feature_reference: /scratch/juno/YOUR_NETID/myproject/crispr_guide_ref.csv

libraries:
  - fastq_id: MySample_GEX
    fastqs: /scratch/juno/YOUR_NETID/myproject/fastq
    feature_types: Gene Expression
  - fastq_id: MySample_CRISPR
    fastqs: /scratch/juno/YOUR_NETID/myproject/fastq
    feature_types: CRISPR Guide Capture
```

---

#### Use Case 6: Cell Multiplexing — CellPlex (CMO-Based)

Multiple biological samples pooled in one 10x capture, demultiplexed by Cell Multiplexing Oligos (CMOs). Outputs one `per_sample_outs/` directory per sample.

```yaml
sample_id: my_cellplex_run
localcores: 16
localmem: 64
scratch_output_dir: /scratch/juno/YOUR_NETID/myproject/cellranger
transcriptome: /groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A
create_bam: true

libraries:
  - fastq_id: MyRun_GEX
    fastqs: /scratch/juno/YOUR_NETID/myproject/fastq
    feature_types: Gene Expression
  - fastq_id: MyRun_CMO
    fastqs: /scratch/juno/YOUR_NETID/myproject/fastq
    feature_types: Multiplexing Capture

samples:
  - sample_id: PatientA
    cmo_ids: CMO301
    description: Patient A PBMC
  - sample_id: PatientB
    cmo_ids: CMO302
    description: Patient B PBMC
  - sample_id: PatientC
    cmo_ids: CMO303
    description: Patient C PBMC
```

CMO IDs (CMO301–CMO312) correspond to the 10x CellPlex kit barcodes. If you used a custom CMO set, add `cmo_set: /path/to/custom_cmo.csv` alongside the `libraries:` block.

---

#### Use Case 7: Fixed RNA Profiling (Flex)

Samples are multiplexed via probe barcodes rather than CMOs. Used with the 10x Flex (formerly Singleplex and Multiplex Fixed RNA Profiling) kit.

```yaml
sample_id: my_flex_run
localcores: 16
localmem: 64
scratch_output_dir: /scratch/juno/YOUR_NETID/myproject/cellranger
transcriptome: /groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A
create_bam: true

libraries:
  - fastq_id: MyFlex_Library
    fastqs: /scratch/juno/YOUR_NETID/myproject/fastq
    feature_types: Fixed RNA Profiling

samples:
  - sample_id: SampleA
    probe_barcode_ids: BC001
    description: Sample A — fixed PBMC
  - sample_id: SampleB
    probe_barcode_ids: BC002
    description: Sample B — fixed PBMC
```

Probe barcode IDs (BC001–BC016) correspond to the Flex kit barcodes. Check your kit certificate of analysis for the assignment.

---

#### Use Case 8: GEX + VDJ-T + Antibody Capture (Combined Immune Profiling)

The most comprehensive single-sample multi-omic run: transcriptome + TCR clonotypes + protein surface markers in one config.

```yaml
sample_id: my_multimodal_sample
localcores: 16
localmem: 64
scratch_output_dir: /scratch/juno/YOUR_NETID/myproject/cellranger
transcriptome: /groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A
create_bam: true
vdj_reference: /groups/tprice/pipelines/references/refdata-cellranger-vdj-GRCh38-alts-ensembl-7.1.0
feature_reference: /scratch/juno/YOUR_NETID/myproject/antibody_panel.csv

libraries:
  - fastq_id: MySample_GEX
    fastqs: /scratch/juno/YOUR_NETID/myproject/fastq
    feature_types: Gene Expression
  - fastq_id: MySample_VDJ
    fastqs: /scratch/juno/YOUR_NETID/myproject/fastq
    feature_types: VDJ-T
  - fastq_id: MySample_AB
    fastqs: /scratch/juno/YOUR_NETID/myproject/fastq
    feature_types: Antibody Capture
```

### Full Config Reference (All Optional Fields)

```yaml
# Required for all multi runs
sample_id: my_sample                  # Output directory name
transcriptome: /groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A
localcores: 16
localmem: 64                          # GB
create_bam: true                      # REQUIRED for Cell Ranger 10.0.0+

# Optional output location override
# scratch_output_dir: /scratch/juno/$USER/myproject/cellranger

# References for non-GEX library types
# vdj_reference: /groups/tprice/pipelines/references/refdata-cellranger-vdj-GRCh38-alts-ensembl-7.1.0
# feature_reference: /path/to/feature_reference.csv   # Required for Antibody Capture / CRISPR

# Library block — one entry per library type
libraries:
  - fastq_id: MySample_GEX           # Matches FASTQ filename prefix: <fastq_id>_S*_L*_R*.fastq.gz
    fastqs: /scratch/juno/$USER/myproject/fastq
    feature_types: Gene Expression
  # Add more library entries as needed

# Sample demultiplexing block (CellPlex and Flex only)
# samples:
#   - sample_id: SampleA
#     cmo_ids: CMO301              # CellPlex only
#     probe_barcode_ids: BC001     # Flex only
#     description: optional label

# Chemistry and cell detection overrides (optional)
# chemistry: auto                  # auto | SC3Pv3 | SC5P-PE | threeprime | fiveprime
# include_introns: true
# expect_cells: 5000
# force_cells: 5000

# CellPlex custom CMO set (optional)
# cmo_set: /path/to/custom_cmo.csv

# Override default tool install
# tool_path: /groups/tprice/opt/cellranger-11.0.0

# Titan integration (optional)
titan_project_id:   # PRJ-xxxx
titan_sample_id:    # SMP-xxxx
titan_library_id:   # LIB-xxxx
titan_run_id:       # RUN-xxxx
```

### Example Launch

```bash
# Edit config
vi /work/$USER/pipelines/cellranger-multi/config.yaml

# Single run
tjp-launch cellranger-multi

# Single run with explicit config path
tjp-launch cellranger-multi --config /path/to/config.yaml

# Batch run (per-row — one job per sample)
tjp-batch cellranger-multi /work/$USER/pipelines/cellranger-multi/samplesheet.csv
tjp-batch cellranger-multi samplesheet.csv --dry-run

# Monitor
squeue -u $USER
```

Batch samplesheet format:

```csv
sample,transcriptome,libraries,feature_reference,vdj_reference,project_id,sample_id,library_id,run_id
my_sample,/groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A,,,,,,,
```

For complex multi-library batch runs, it is usually easier to write one config file per sample and launch each with `tjp-launch cellranger-multi --config <sample>.yaml` rather than encoding library blocks in a samplesheet row.

### Output Structure

**Single-sample output** (GEX-only, VDJ, or CITE-seq without CMO/Flex multiplexing):

```
<sample_id>/outs/
├── web_summary.html
├── count/
│   ├── filtered_feature_bc_matrix/
│   │   ├── barcodes.tsv.gz
│   │   ├── features.tsv.gz
│   │   └── matrix.mtx.gz
│   ├── filtered_feature_bc_matrix.h5
│   └── molecule_info.h5
├── vdj_t/                             # Present when VDJ-T library included
│   ├── filtered_contig_annotations.csv
│   ├── clonotypes.csv
│   ├── all_contig_annotations.json
│   └── vdj_reference/
├── vdj_b/                             # Present when VDJ-B library included
│   └── (same structure as vdj_t/)
└── cloupe.cloupe
```

**Multiplexed output** (CellPlex or Flex):

```
<sample_id>/outs/
├── web_summary.html
├── per_sample_outs/
│   ├── SampleA/
│   │   ├── web_summary.html
│   │   ├── count/
│   │   │   └── filtered_feature_bc_matrix/
│   │   └── metrics_summary.csv
│   ├── SampleB/
│   │   └── (same structure)
│   └── SampleC/
│       └── (same structure)
└── multi/
    └── multiplexing_analysis/
        ├── assignment_confidence_table.csv
        └── tag_calls_per_cell.csv
```

### Edge Cases

- **`create_bam: true` is required** for Cell Ranger 10.0.0+. The validator enforces this.
- **`vdj_reference` is required** when any library entry has `feature_types: VDJ-T`, `VDJ-T-GD`, or `VDJ-B`. Omitting it produces a validation error before job submission.
- **`feature_reference` is required** for `Antibody Capture` and `CRISPR Guide Capture` libraries. Without it, the job will fail after submission.
- **`fastq_id` must match the FASTQ filename prefix exactly.** Cell Ranger resolves files as `<fastq_id>_S*_L*_R*.fastq.gz`. If your GEX FASTQ is named `SJ0134_GEX_S1_L001_R1_001.fastq.gz`, the `fastq_id` must be `SJ0134_GEX`.
- **All library FASTQs do not have to be in the same directory.** Each `libraries:` entry has its own `fastqs:` path — GEX, VDJ, and antibody FASTQs can live in different directories.
- **CellPlex CMO IDs must be in the right order.** Confirm which CMO was loaded in which position when the pool was assembled. Swapped assignments cannot be corrected after the run.

---

## Shared Reference Paths on Juno

| Reference | Full path | Used by |
|-----------|-----------|---------|
| Human GEX transcriptome (GRCh38 2024-A) | `/groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A` | cellranger, cellranger-multi, spaceranger |
| Human VDJ reference | `/groups/tprice/pipelines/references/refdata-cellranger-vdj-GRCh38-alts-ensembl-7.1.0` | cellranger-multi (VDJ libraries) |

These are read-only shared references. Do not write into these directories.

To verify the references are intact:

```bash
ls /groups/tprice/pipelines/references/refdata-gex-GRCh38-2024-A/
# Expected: fasta/  genes/  pickle/  reference.json

ls /groups/tprice/pipelines/references/refdata-cellranger-vdj-GRCh38-alts-ensembl-7.1.0/
# Expected: fasta/  reference.json
```

---

## Upgrading Cell Ranger

To install a new Cell Ranger version without disrupting running jobs:

```bash
# 1. Download and extract the new tarball to the opt directory
tar -xzf cellranger-11.0.0.tar.gz -C /groups/tprice/opt/

# 2. Update the stable symlink
ln -sfn /groups/tprice/opt/cellranger-11.0.0 /groups/tprice/software/cellranger

# 3. Verify
/groups/tprice/software/cellranger/cellranger --version

# 4. Run the smoke test
tjp-test cellranger
```

No changes are needed to the submodule (`containers/10x/`) or the HPC framework repo. The symlink at `/groups/tprice/software/cellranger` is what the SLURM templates resolve.

If you want to test a new version without updating the shared symlink, set `tool_path:` in your config:

```yaml
tool_path: /groups/tprice/opt/cellranger-11.0.0
```

This overrides the default path for that run only.

---

## Troubleshooting

### "No input FASTQs were found"

**Cause:** `sample_name` (for `cellranger`) or `fastq_id` (for `cellranger-multi`) does not match the FASTQ filename prefix.

Cell Ranger looks for files matching `<name>_S*_L*_R*.fastq.gz`. The name comparison is exact.

```bash
# Check actual FASTQ filenames
ls /scratch/juno/$USER/myproject/fastq/*.fastq.gz | head -5
# Typical output: SJ0134_GEX_S1_L001_R1_001.fastq.gz
# Correct config: sample_name: SJ0134_GEX   (not "SJ0134")
```

### "create_bam must be set" / BAM-related error

**Cause:** `create_bam:` is missing from the config. This is required in Cell Ranger 10.0.0+.

```yaml
# Add this to your config
create_bam: true
```

The validator (`tjp-launch`) will catch this before the job is submitted. If you see it at submission time, re-run `tjp-launch` — the validator should flag it before SLURM sees it.

### "SC3Pv3LT chemistry is not supported"

**Cause:** `chemistry: SC3Pv3LT` was set in the config. This chemistry was dropped in Cell Ranger 10.0.0.

**Fix:** Either remove the `chemistry:` line (let Cell Ranger auto-detect) or contact Michael if you specifically have 3' v3 LT data, which requires staging the Cell Ranger 9.x binary.

### Chemistry mismatch warning / low confidence barcodes

**Cause:** Cell Ranger's auto-detection guessed the wrong chemistry.

**Fix:** Explicitly set `chemistry:` in your config. Common values:

| Kit | Chemistry value |
|-----|----------------|
| Chromium Next GEM Single Cell 3' v3.1 | `SC3Pv3` |
| Chromium Next GEM Single Cell 3' HT v3.1 | `SC3Pv3HT` |
| Chromium Next GEM Single Cell 5' v2 PE | `SC5P-PE` |
| Chromium Next GEM Single Cell 5' v3 | `SC5P-R2` |
| Chromium Single Cell 3' v2 | `SC3Pv2` |

### Job fails immediately with "config not found"

```bash
cat /work/$USER/pipelines/cellranger/runs/<timestamp>/slurm_<JOBID>.err
```

**Cause:** The config YAML path was not found when the SLURM job started. This happens if the config was on scratch (purged) or a path was mis-typed.

**Fix:** Verify `ls /work/$USER/pipelines/cellranger/config.yaml` exists. The `tjp-launch` tool snapshots the config to the run directory automatically — check the snapshot at `/work/$USER/pipelines/cellranger/runs/<timestamp>/config.yaml`.

### `rc_i2_override` for mkfastq — Index 2 errors

**Cause:** NovaSeq X and some newer instruments output the i5 index in the reverse complement orientation relative to the `SampleSheet.csv` convention.

**Fix:** Add `rc_i2_override: true` to the `cellranger-mkfastq` config. If you are unsure, check the instrument runinfo: look for `IsReverseComplement` in `RunInfo.xml` inside the BCL folder.

### SLURM job running but Cell Ranger appears stalled

Cell Ranger pipelines take 2–6+ hours for a typical 10k cell sample. Check real-time progress:

```bash
# Find the _log file in the run output directory
ls /scratch/juno/$USER/pipelines/cellranger/runs/<timestamp>/<sample_id>/_log

# Or check pipestance state
cat /scratch/juno/$USER/pipelines/cellranger/runs/<timestamp>/<sample_id>/_invocation
```

The run directory is under scratch. Look for the timestamped run at `/scratch/juno/$USER/pipelines/cellranger/runs/`.

### VDJ reference not found (cellranger-multi)

**Symptom:** `ERROR: vdj_reference path does not exist` at submission time.

**Fix:** Verify the path is correct:

```bash
ls /groups/tprice/pipelines/references/refdata-cellranger-vdj-GRCh38-alts-ensembl-7.1.0/reference.json
```

If the file is missing, the VDJ reference needs to be staged. Contact Michael.

### Feature reference CSV format errors (CITE-seq / CRISPR)

**Symptom:** `ERROR: Feature reference CSV missing required column` or barcode sequences not recognized.

**Common issues:**
- Header row has extra whitespace
- `feature_type` column value does not match exactly (must be `Antibody Capture` or `CRISPR Guide Capture` — case-sensitive)
- Barcode sequences contain non-ACGT characters or are the wrong length for your kit

**Check with:**

```bash
head -3 /path/to/feature_reference.csv
# Verify: id,name,read,pattern,sequence,feature_type header is present and clean
```
