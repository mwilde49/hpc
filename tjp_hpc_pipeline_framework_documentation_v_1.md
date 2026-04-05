> **ARCHIVED — v1.0 Historical Document**
> 
> This document describes the initial MVP architecture (AddOne demo pipeline only). It has been
> superseded by the following current documentation:
> 
> - **[USER_GUIDE.md](USER_GUIDE.md)** — End-user guide for all pipelines
> - **[DEVELOPER_ONBOARDING.md](DEVELOPER_ONBOARDING.md)** — Developer technical reference  
> - **[PIPELINE_DESIGN_REVIEW.md](PIPELINE_DESIGN_REVIEW.md)** — Architecture decisions
> - **[HPC_SYSTEM_MAP.md](HPC_SYSTEM_MAP.md)** — Cluster and filesystem reference
> 
> Current framework version: **v6.0.0** (9 pipelines, samplesheet-driven batch execution, Titan metadata prototype)
> 
> ---

# TJP HPC Pipeline Framework
## MVP Architecture, Design Principles, and Operational Guide

Version: 1.0
Status: MVP validated on HPC
Audience: Developers, Bioinformaticians, HPC Administrators, Technical Managers, and Non-Technical Stakeholders

---

# 1. Executive Summary

This document describes the design, implementation, and operational architecture of the TJP HPC Pipeline Framework. The system enables group members to deploy reproducible computational workflows on a shared High Performance Computing (HPC) environment using:

- SLURM for job scheduling
- Apptainer for containerization
- Structured directory architecture for reproducibility
- Config-driven execution
- Group-based shared infrastructure

The MVP implementation uses a minimal example pipeline ("AddOne") to demonstrate the complete stack:

User → SLURM → Apptainer → Pipeline → Input → Output

This system is intentionally minimal but architected to scale to bioinformatics workflows, machine learning pipelines, or other computational research workloads.

The framework emphasizes:

- Reproducibility
- Isolation
- Scalability
- Maintainability
- Shared group governance

---

# 2. Project Objectives

## 2.1 Primary Goals

1. Create a reproducible HPC pipeline architecture
2. Allow group members to preload pipelines
3. Separate pipeline logic from infrastructure
4. Enable scalable future expansion
5. Provide clear handoff documentation

## 2.2 Non-Goals (MVP Phase)

- No workflow manager (Nextflow/Snakemake) yet
- No database tracking system
- No dynamic job generation service
- No web interface

These can be layered later without redesigning the foundation.

---

# 3. System Overview

## 3.1 Conceptual Stack

Layer 1 — HPC Infrastructure
Layer 2 — SLURM Scheduler
Layer 3 — Apptainer Container Runtime
Layer 4 — TJP Pipeline Logic
Layer 5 — User Input / Output

Each layer has a single responsibility.

## 3.2 Responsibility Separation

| Component | Responsibility |
|------------|---------------|
| HPC | Hardware resources |
| SLURM | Resource allocation + scheduling |
| Apptainer | Reproducible execution environment |
| Pipeline | Domain logic |
| Config | Parameterization |
| User | Experiment definition |

---

# 4. Directory Architecture

Shared group root:

/groups/tprice/pipelines/

Structure:

/groups/tprice/pipelines/
│
├── containers/
│   └── addone_latest.sif
│
├── pipelines/
│   └── addone/
│       ├── addone.py
│       ├── run_pipeline.sh
│       └── README.md
│
├── slurm_templates/
│   └── addone_slurm_template.sh
│
├── configs/
│   └── example_config.yaml
│
└── test_data/
    └── numbers.txt

## 4.1 Design Rationale

containers/
Stores versioned immutable execution environments.

pipelines/
Stores source-controlled pipeline logic.

slurm_templates/
Defines standardized job submission structure.

configs/
Stores reproducible parameter definitions.

test_data/
Allows validation without external dependencies.

This structure scales horizontally across pipelines.

---

# 5. MVP Demonstration Pipeline

## 5.1 Purpose

The AddOne pipeline reads a text file of numbers, adds one to each value, and writes output.

This trivial task demonstrates:

- Argument parsing
- File IO
- Container execution
- SLURM submission
- Bind mounting
- Log generation

## 5.2 Pipeline Script (addone.py)

Core responsibilities:

- Accept --input and --output arguments
- Read file
- Transform values
- Write output

This simulates real bioinformatics pipelines where input and output paths are configurable.

---

# 6. Containerization with Apptainer

## 6.1 Why Containers?

Without containers:

- Python version conflicts
- Library drift
- Non-reproducible results

With containers:

- Immutable runtime
- Portable execution
- Predictable dependencies

## 6.2 Apptainer Definition

Definition file includes:

- Base image (python slim)
- Dependency installation
- Default runscript

## 6.3 Container Build Process

apptainer build addone_latest.sif apptainer.def

Containers should be:

- Built in controlled environment
- Versioned
- Never edited directly

---

# 7. SLURM Integration

## 7.1 Role of SLURM

SLURM is the scheduler.

It:

- Allocates compute nodes
- Enforces time limits
- Manages memory
- Queues jobs
- Tracks usage
- Captures logs

It does not understand pipeline logic.

## 7.2 Sample SLURM Template

Key components:

#SBATCH --job-name
#SBATCH --output
#SBATCH --error
#SBATCH --time
#SBATCH --cpus-per-task
#SBATCH --mem

These define resource allocation.

## 7.3 Execution Command

apptainer exec \
  --bind /groups/tprice/pipelines:/groups/tprice/pipelines \
  container.sif \
  python pipeline.py \
    --input $INPUT \
    --output $OUTPUT

This connects scheduler → container → pipeline.

---

# 8. User Workflow

## 8.1 Basic Execution Model

1. Copy SLURM template
2. Create logs directory
3. Submit job via sbatch

Example:

sbatch my_run.sh input.txt output.txt

## 8.2 Logs

Two log streams are generated:

- STDOUT
- STDERR

Logs include job ID for traceability.

---

# 9. Security and Governance

## 9.1 File Permissions

Group should enforce:

- Shared read access
- Restricted write access for containers

Containers should be write-protected.

## 9.2 Scratch vs Project Space

Project space:

- Shared
- Persistent

Scratch space:

- User-specific
- Temporary
- Faster IO

Outputs should default to scratch.

---

# 10. Reproducibility Model

Reproducibility requires:

- Versioned container
- Versioned pipeline code
- Saved config file
- Recorded SLURM parameters
- Preserved logs

Recommended practice:

Archive per experiment:

- Config
- Job script
- Container version
- Output
- Logs

---

# 11. Scaling Strategy

## 11.1 Adding New Pipelines

To add a pipeline:

1. Create new folder under pipelines/
2. Write pipeline logic
3. Create container if needed
4. Add SLURM template
5. Provide config example

Infrastructure remains unchanged.

## 11.2 Resource Expansion

Future expansions may include:

- GPU support
- SLURM array jobs
- Large memory nodes
- Partition targeting

---

# 12. Advanced Extensions (Future Phases)

## 12.1 Workflow Managers

Potential integrations:

- Nextflow
- Snakemake
- CWL

These would replace manual orchestration.

## 12.2 Auto SLURM Generation

A wrapper CLI could:

- Accept config
- Generate SLURM file
- Submit automatically

## 12.3 Version Registry

Containers could follow:

pipeline_v1.0.0.sif

Semantic versioning recommended.

---

# 13. Operational Playbook

## 13.1 If Job Fails

Check:

1. SLURM logs
2. Input path correctness
3. Container path
4. Memory limits

## 13.2 If Container Fails

Check:

- Missing dependency
- Bind mount paths
- Permissions

## 13.3 HPC Manager Considerations

Ensure:

- Fair usage
- Partition limits
- Module compatibility
- Apptainer availability

---

# 14. Dev Handoff Guide

A new developer should understand:

- Separation of concerns
- Container immutability
- Config-driven design
- Scheduler responsibility

They should NOT:

- Hardcode file paths
- Modify containers directly
- Bypass SLURM

---

# 15. Bioinformatics Adaptation

Replace AddOne with:

- RNA-seq alignment
- Variant calling
- GWAS processing
- Deep learning training

The architecture remains identical.

Only the pipeline logic changes.

---

# 16. Layperson Explanation

Imagine:

- SLURM = receptionist assigning rooms
- Apptainer = standardized lab bench
- Pipeline = experiment protocol
- Config = experiment recipe
- HPC = building

Users submit an experiment request. The system runs it safely and predictably.

---

# 17. Risk Analysis

Potential risks:

- Container sprawl
- Version confusion
- Resource overuse
- Lack of documentation

Mitigations:

- Strict naming conventions
- Central container governance
- Template enforcement
- Version tagging

---

# 18. Governance Model for TJP

Suggested policies:

1. Only designated maintainers build containers
2. Pipelines must include README
3. Config examples required
4. All jobs must run through SLURM

---

# 19. Current State Summary

Completed:

- MVP pipeline
- Containerization
- SLURM integration
- Directory architecture
- HPC validation

Validated on live HPC.

---

# 20. Strategic Vision

This MVP is not the end product.

It is foundational infrastructure for:

- Multi-pipeline research computing
- Scalable bioinformatics
- ML training workloads
- Reproducible computational science

The design intentionally mirrors industry-grade systems while remaining simple enough for academic teams.

---

# 21. Conclusion

The TJP HPC Pipeline Framework establishes:

- Clear separation of infrastructure and science
- Reproducible execution via containers
- Controlled scheduling via SLURM
- Config-driven experimentation
- Scalable architecture

It is minimal, correct, and extensible.

Any developer, researcher, or HPC manager can continue this project using this document as a foundation.

---

END OF DOCUMENT
