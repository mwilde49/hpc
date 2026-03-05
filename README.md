# TJP HPC Pipeline Framework

HPC pipeline framework for the TJP group on Juno HPC. Uses Apptainer containers, SLURM scheduling, and config-driven YAML/Nextflow execution.

## Pipelines

| Pipeline | Type | Description |
|----------|------|-------------|
| **AddOne** | Inline (demo) | Adds 1 to every number in a file. Teaching example for the framework. |
| **BulkRNASeq** | Submoduled | UTDal Bulk RNA-Seq Nextflow Pipeline (STAR aligner) in an Apptainer container. |
| **Psoma** | Submoduled | Psomagen Bulk RNA-Seq Nextflow Pipeline (HISAT2 + Trimmomatic) in an Apptainer container. |

## Directory Structure

```
hpc/
├── bin/
│   ├── tjp-setup                      # One-time workspace setup
│   ├── tjp-launch                     # Launch a pipeline run
│   ├── tjp-test                       # Smoke-test a pipeline (2 samples, dev partition)
│   ├── tjp-test-validate              # Validate smoke-test outputs
│   └── lib/                           # Shared shell libraries
├── containers/
│   ├── apptainer.def                  # AddOne container definition
│   ├── bulkrnaseq/                    # Git submodule → mwilde49/bulkseq @ v1.0.0
│   └── psoma/                         # Git submodule → mwilde49/psoma @ v2.0.0
├── pipelines/
│   └── addone/                        # AddOne pipeline code
├── slurm_templates/
│   ├── addone_slurm_template.sh
│   ├── bulkrnaseq_slurm_template.sh
│   └── psoma_slurm_template.sh
├── templates/                         # Per-pipeline config templates
├── configs/
│   └── example_config.yaml            # AddOne example config (legacy)
└── test_data/
    ├── numbers.txt                    # AddOne test input
    └── rnaseq/                        # RNA-Seq smoke test data
        ├── subsample_from_real.sh     # Utility to create test FASTQs
        ├── psoma/samples.txt
        ├── bulkrnaseq/samples.txt
        └── fastq/                     # Test FASTQs (gitignored, generated on HPC)
```

## Quick Start

### Clone

```bash
git clone --recurse-submodules https://github.com/mwilde49/hpc.git
```

### AddOne (demo pipeline)

```bash
# Build container (requires sudo)
sudo apptainer build containers/addone_latest.sif containers/apptainer.def

# Test locally
apptainer exec containers/addone_latest.sif python pipelines/addone/addone.py \
  --input test_data/numbers.txt --output /tmp/addone_output.txt

# Submit on HPC
sbatch slurm_templates/addone_slurm_template.sh configs/example_config.yaml
```

### BulkRNASeq

```bash
# Build container (requires sudo)
cd containers/bulkrnaseq && sudo ./build.sh

# Clone UTDal pipeline on HPC
git clone https://github.com/utdal/Bulk-RNA-Seq-Nextflow-Pipeline.git

# Configure and submit
vi Bulk-RNA-Seq-Nextflow-Pipeline/pipeline.config
sbatch slurm_templates/bulkrnaseq_slurm_template.sh
```

See [BULKRNASEQ_HPC_GUIDE.md](BULKRNASEQ_HPC_GUIDE.md) for full setup and usage.

### Smoke Testing

Verify either RNA-seq pipeline works end-to-end with 2 test samples on the dev partition:

```bash
tjp-test psoma              # submit smoke test
tjp-test-validate psoma     # validate outputs after completion
```

See [USER_GUIDE.md](USER_GUIDE.md) for details.

## Documentation

| Guide | Description |
|-------|-------------|
| [USER_GUIDE.md](USER_GUIDE.md) | End-user guide for both RNA-Seq pipelines |
| [ONBOARDING.md](ONBOARDING.md) | Quick-start onboarding for new users |
| [BULKRNASEQ_HPC_GUIDE.md](BULKRNASEQ_HPC_GUIDE.md) | Bulk RNA-Seq setup, test analysis walkthrough, and loading new data |
| [TJP_HPC_COMPLETE_GUIDE.md](TJP_HPC_COMPLETE_GUIDE.md) | Complete operational guide — architecture, deployment, troubleshooting |
| [tjp_hpc_pipeline_framework_documentation_v_1.md](tjp_hpc_pipeline_framework_documentation_v_1.md) | Framework design document for technical and non-technical stakeholders |
| [CLAUDE.md](CLAUDE.md) | AI assistant instructions and project reference |
| [containers/bulkrnaseq/README.md](containers/bulkrnaseq/README.md) | BulkRNASeq container repo documentation |
| [containers/bulkrnaseq/BULKRNASEQ_CONTAINER_GUIDE.md](containers/bulkrnaseq/BULKRNASEQ_CONTAINER_GUIDE.md) | Detailed container build, test, and HPC integration guide |

## HPC Path Conventions (Juno)

The repo is deployed to a shared group location. Each user's data stays on their own directories:

| What | Path |
|------|------|
| Shared pipelines repo | `/groups/tprice/pipelines` |
| User work directory | `/work/<username>` |
| User scratch directory | `/scratch/juno/<username>` |

SLURM templates auto-detect user paths via `$USER`. Apptainer bind mounts require real paths, not symlinks.

## Adding a New Pipeline

**Inline** (code in this repo): create `pipelines/<name>/`, add container def, SLURM template, and config. See the addone pipeline as a template.

**Submoduled** (external container repo): add as a git submodule in `containers/<name>/`, pin to a release tag, add SLURM template with pre-flight checks, and create an HPC guide. See the bulkrnaseq pipeline as a template.

See [TJP_HPC_COMPLETE_GUIDE.md](TJP_HPC_COMPLETE_GUIDE.md) for detailed instructions on both patterns.
