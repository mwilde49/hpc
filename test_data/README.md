# Test Data — TJP HPC Pipeline Framework

This directory contains small test datasets used by the smoke test framework (`tjp-test` / `tjp-test-validate`). Most actual test files are excluded from git (gitignored) because they are large binaries. This README documents what data exists, where it lives on HPC, and which pipelines depend on it.

---

## Directory Layout

```
test_data/
├── numbers.txt                 # AddOne pipeline: 5 integers
├── rnaseq/
│   ├── bulkrnaseq/
│   │   └── samples.txt         # Sample list for BulkRNASeq smoke test
│   ├── psoma/
│   │   └── samples.txt         # Sample list for Psoma smoke test
│   └── subsample_from_real.sh  # Script to generate subsampled FASTQs from real data
└── 10x/
    ├── cellranger/             # .gitkeep — actual data must be staged on HPC
    ├── spaceranger/            # .gitkeep — Space Ranger uses bundled tiny inputs
    └── xeniumranger/           # .gitkeep — needs real Xenium output bundle
```

---

## AddOne

**File:** `test_data/numbers.txt`

Five integers, one per line. The pipeline adds 1 to each.

**Used by:** not a formal smoke test pipeline — run manually:
```bash
apptainer exec containers/addone_latest.sif \
    python pipelines/addone/addone.py \
    --input test_data/numbers.txt --output /tmp/addone_output.txt
```

---

## BulkRNASeq and Psoma

**Files in git:**
- `test_data/rnaseq/bulkrnaseq/samples.txt` — two sample IDs (Sample_19, Sample_20)
- `test_data/rnaseq/psoma/samples.txt` — same two samples
- `test_data/rnaseq/subsample_from_real.sh` — subsamples real FASTQs to ~500K reads for fast testing

**Actual FASTQ files (not in git, must be staged on HPC):**
Located at `/scratch/juno/maw210003/fastq/` on Juno:
- `Sample_19_1_paired.fastq.gz` / `Sample_19_2_paired.fastq.gz`
- `Sample_20_1_paired.fastq.gz` / `Sample_20_2_paired.fastq.gz`

To regenerate subsampled FASTQs from real data:
```bash
cd test_data/rnaseq
bash subsample_from_real.sh /scratch/juno/$USER/fastq/real 500000 /scratch/juno/$USER/fastq/test
```

**Smoke test:**
```bash
tjp-test psoma      # copies FASTQs to scratch, generates config, submits on dev partition
tjp-test bulkrnaseq
squeue -u $USER     # monitor
tjp-test-validate psoma     # check outputs after job completes
tjp-test-validate bulkrnaseq
```

---

## Cell Ranger (10x Genomics)

**Directory:** `test_data/10x/cellranger/` (empty; `.gitkeep` only)

**Status:** Blocked. The standard 500 PBMC 3'v3 LT test dataset uses SC3Pv3LT chemistry, which was dropped in Cell Ranger 10.0.0. A compatible test dataset is needed.

**To stage test data once available:**
```bash
# Copy a compatible 10x FASTQ set to HPC
scp -r /local/cellranger_test_data/ maw210003@juno.hpcre.utdallas.edu:/scratch/juno/maw210003/cellranger_test/

# Run smoke test (edit test config in bin/tjp-test first)
tjp-test cellranger
tjp-test-validate cellranger
```

---

## Space Ranger (10x Genomics)

**Directory:** `test_data/10x/spaceranger/` (empty; `.gitkeep` only)

**Source:** Space Ranger ships with bundled tiny inputs at:
```
/groups/tprice/opt/spaceranger-4.0.1/external/spaceranger_tiny_inputs/
```

`tjp-test spaceranger` uses these bundled inputs automatically — no additional staging required.

```bash
tjp-test spaceranger
squeue -u $USER
tjp-test-validate spaceranger
```

---

## Xenium Ranger (10x Genomics)

**Directory:** `test_data/10x/xeniumranger/` (empty; `.gitkeep` only)

**Status:** Not yet supported by `tjp-test`. Xenium Ranger requires a full Xenium output bundle (typically 10–50 GB), which cannot be practically stored in git or generated from synthetic data.

**To add smoke test support:**
1. Obtain a minimal Xenium output bundle (contact 10x Genomics support for a test dataset)
2. Stage it on HPC: `/scratch/juno/$USER/xeniumranger_test/xenium_bundle/`
3. Add smoke test logic to `bin/tjp-test` following the spaceranger pattern

---

## SQANTI3

**Location (not in git — must be staged on HPC):**
```
containers/sqanti3/SQANTI3/data/
```

The SQANTI3 repo ships with a chr22 UHR test dataset. After pulling the container SIF, the test data is available inside the submodule at the above path.

**Stage the SQANTI3 SIF:**
```bash
apptainer pull containers/sqanti3/sqanti3_v5.5.4.sif docker://anaconesalab/sqanti3:v5.5.4
```

**Run with test data:**
```bash
# Use the test config in the SQANTI3 data directory
tjp-launch sqanti3 --config containers/sqanti3/SQANTI3/data/test_config.yaml --dev
```

---

## wf-transcriptomes

**Location (not in git — must be staged on HPC):**
```
containers/sqanti3/test_data/wf_transcriptomes/
```

ONT FASTQ files must be obtained separately (e.g., from EPI2ME's public test datasets or a real nanopore run subsampled to chr22).

**Staging:**
```bash
# Copy ONT FASTQs to the submodule's test data directory on HPC
scp -r /local/ont_fastq/ maw210003@juno.hpcre.utdallas.edu:\
  /groups/tprice/pipelines/containers/sqanti3/test_data/wf_transcriptomes/
```

---

## Adding New Test Data

When adding test data for a new pipeline:
1. Keep files small — aim for <10 MB per sample so smoke tests complete on the dev partition (2-hour limit)
2. If files are binary (FASTQs, BAMs), add them to `.gitignore` and document staging instructions here
3. If files are plain text (configs, metadata), commit them to git
4. Update `bin/tjp-test` and `bin/tjp-test-validate` to support the new pipeline
5. Update this README with the new section
