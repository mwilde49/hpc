# TJP HPC Pipeline Framework — Complete Operational Guide

Version: 2.0
Status: MVP validated and tested on Juno HPC
Audience: Group members, new developers, bioinformaticians

This guide walks through the entire process from developing a pipeline on your local machine to running it on the HPC via SLURM. It uses the AddOne demo pipeline as a working example but the process applies to any pipeline.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture at a Glance](#2-architecture-at-a-glance)
3. [HPC Filesystem Layout](#3-hpc-filesystem-layout)
4. [Phase 1: Local Development](#4-phase-1-local-development)
5. [Phase 2: Build the Apptainer Container](#5-phase-2-build-the-apptainer-container)
6. [Phase 3: Test Locally](#6-phase-3-test-locally)
7. [Phase 4: Deploy to HPC](#7-phase-4-deploy-to-hpc)
8. [Phase 5: Interactive Testing on HPC](#8-phase-5-interactive-testing-on-hpc)
9. [Phase 6: Submit via SLURM](#9-phase-6-submit-via-slurm)
10. [Phase 7: Monitor and Verify](#10-phase-7-monitor-and-verify)
11. [Key Concepts Explained](#11-key-concepts-explained)
12. [Adding a New Pipeline](#12-adding-a-new-pipeline)
13. [Troubleshooting](#13-troubleshooting)
14. [File Reference](#14-file-reference)
15. [Quick Reference Card](#15-quick-reference-card)

---

## 1. Overview

The TJP HPC Pipeline Framework lets group members run reproducible computational pipelines on a shared HPC cluster. The system uses four core components:

| Component | What It Does |
|-----------|-------------|
| **Pipeline** | Your actual code (Python, R, etc.) |
| **Apptainer Container** | Packages all dependencies into a single portable file (.sif) |
| **SLURM** | Schedules and runs your job on compute nodes |
| **Config** | Defines input/output paths and parameters |

The workflow is:

```
Write code locally → Build container → Push to HPC → Submit job via SLURM
```

---

## 2. Architecture at a Glance

```
User submits job
       │
       ▼
   ┌────────┐
   │ SLURM  │  Allocates CPUs, memory, time on a compute node
   └───┬────┘
       │
       ▼
 ┌───────────┐
 │ Apptainer │  Runs your code inside an isolated container
 └─────┬─────┘
       │
       ▼
  ┌──────────┐
  │ Pipeline │  Reads config, processes input, writes output
  └──────────┘
```

Each layer has a single responsibility. SLURM doesn't know about your code. Apptainer doesn't know about scheduling. Your pipeline doesn't know about the HPC infrastructure.

---

## 3. HPC Filesystem Layout

### Juno HPC Path Structure

The shared pipelines repo lives at `/groups/tprice/pipelines`. Each user's data stays on their own work and scratch directories:

| What | Path |
|------|------|
| Shared pipelines repo | `/groups/tprice/pipelines` |
| User work directory | `/work/<username>` |
| User scratch directory | `/scratch/juno/<username>` |

Juno uses symlinked home directories (`~/work` → `/work/<username>`, `~/scratch` → `/scratch/juno/<username>`). **Apptainer bind mounts require the real (resolved) path**, not the symlinked path. Always use `readlink -f` to resolve paths before passing them to Apptainer.

### Project Directory Structure

```
/groups/tprice/pipelines/             (shared group project root)
│
├── .gitmodules                   (tracks git submodules)
│
├── containers/
│   ├── apptainer.def             (addone container definition — source controlled)
│   ├── addone_latest.sif         (built container — NOT in git)
│   └── bulkrnaseq/               (git submodule → mwilde49/bulkseq @ v1.0.0)
│       ├── bulkrnaseq.def        (container definition)
│       ├── build.sh              (build script)
│       └── bulkrnaseq_v1.0.0.sif (built container — NOT in git)
│
├── pipelines/
│   └── addone/
│       ├── addone.py             (pipeline logic)
│       ├── run_pipeline.sh       (optional wrapper script)
│       └── README.md             (pipeline documentation)
│
├── Bulk-RNA-Seq-Nextflow-Pipeline/  (cloned separately — NOT in git)
│
├── slurm_templates/
│   ├── addone_slurm_template.sh     (addone SLURM template)
│   └── bulkrnaseq_slurm_template.sh (bulkrnaseq SLURM template)
│
├── configs/
│   └── example_config.yaml       (addone example configuration)
│
└── test_data/
    └── numbers.txt               (sample input data)
```

### Where Things Live

| Directory | Purpose | Persistence | Access |
|-----------|---------|-------------|--------|
| `/groups/tprice/pipelines/` | Shared code, containers, templates | Persistent | Group read, restricted write |
| `/scratch/juno/<username>/` | Job outputs, temporary large files | Temporary (purged periodically) | User only |
| `logs/` (in working dir) | SLURM stdout/stderr logs | User-managed | User only |

---

## 4. Phase 1: Local Development

### 4.1 Set Up the Project

On your local machine (e.g., WSL2 on Windows):

```bash
mkdir -p hpc/{containers,pipelines/addone,slurm_templates,configs,test_data}
cd hpc
git init
```

### 4.2 Write Your Pipeline

Create `pipelines/addone/addone.py`:

```python
#!/usr/bin/env python3

import argparse
import yaml
import sys
import os


def add_one(input_path, output_path):
    with open(input_path, "r") as f:
        numbers = [float(line.strip()) for line in f if line.strip()]

    new_numbers = [x + 1 for x in numbers]

    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    with open(output_path, "w") as f:
        for n in new_numbers:
            f.write(f"{n}\n")


def main():
    parser = argparse.ArgumentParser(description="Add 1 to every number in a file.")
    parser.add_argument("--input", help="Path to input file")
    parser.add_argument("--output", help="Path to output file")
    parser.add_argument("--config", help="Optional YAML config file")

    args = parser.parse_args()

    if args.config:
        with open(args.config, "r") as f:
            config = yaml.safe_load(f)
        input_path = config["input"]
        output_path = config["output"]
    else:
        if not args.input or not args.output:
            print("Must provide --input and --output or --config", file=sys.stderr)
            sys.exit(1)
        input_path = args.input
        output_path = args.output

    add_one(input_path, output_path)


if __name__ == "__main__":
    main()
```

Key design principles:
- **Config-driven**: Accepts a YAML config file OR direct arguments
- **Explicit paths**: No hardcoded paths — everything is parameterized
- **Output directory creation**: Creates output directories automatically

### 4.3 Write Test Data

Create `test_data/numbers.txt`:

```
1
2
3
4
5
10.5
42
```

### 4.4 Write the Container Definition

Create `containers/apptainer.def`:

```
Bootstrap: docker
From: python:3.11-slim

%post
    pip install pyyaml

%environment
    export LC_ALL=C
    export LANG=C

%runscript
    exec python "$@"
```

What each section does:
- **Bootstrap/From**: Base image — uses official Python 3.11 slim Docker image
- **%post**: Commands run during build — install your Python dependencies here
- **%environment**: Environment variables set at runtime
- **%runscript**: Default command when container is run directly

### 4.5 Write the Config

Create `configs/example_config.yaml`:

```yaml
input: /groups/tprice/pipelines/test_data/numbers.txt
output: /scratch/juno/<username>/addone_output.txt  # Replace <username> with your HPC username
```

**Important**: Use real resolved HPC paths here, not symlinked paths.

### 4.6 Write the SLURM Template

Create `slurm_templates/addone_slurm_template.sh`:

```bash
#!/bin/bash
#SBATCH --job-name=addone_demo
#SBATCH --output=logs/addone_%j.out
#SBATCH --error=logs/addone_%j.err
#SBATCH --time=00:05:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G

# Load module if required by your HPC
module load apptainer

PROJECT_ROOT=/groups/tprice/pipelines
SCRATCH_ROOT=/scratch/juno/$USER
WORK_ROOT=/work/$USER

CONTAINER=$PROJECT_ROOT/containers/addone_latest.sif
PIPELINE=$PROJECT_ROOT/pipelines/addone/addone.py

CONFIG=$1

if [ -z "$CONFIG" ]; then
    echo "Usage: sbatch addone_slurm_template.sh <config.yaml>"
    exit 1
fi

mkdir -p logs

apptainer exec \
    --bind $PROJECT_ROOT:$PROJECT_ROOT \
    --bind $SCRATCH_ROOT:$SCRATCH_ROOT \
    --bind $WORK_ROOT:$WORK_ROOT \
    $CONTAINER \
    python $PIPELINE \
    --config $CONFIG
```

SLURM directives explained:

| Directive | Purpose |
|-----------|---------|
| `--job-name` | Human-readable name (shows in `squeue`) |
| `--output` | File for stdout (`%j` = job ID) |
| `--error` | File for stderr |
| `--time` | Maximum wall time (HH:MM:SS) |
| `--cpus-per-task` | Number of CPU cores |
| `--mem` | Memory allocation |

### 4.7 Set Up Git

Create `.gitignore`:

```
# Apptainer containers (large binaries)
*.sif

# SLURM logs
logs/

# User-specific configs
my_config.yaml

# Python
__pycache__/
*.pyc

# OS
.DS_Store
```

Push to GitHub:

```bash
git add -A
git commit -m "Initial commit: HPC addone demo pipeline"
gh repo create hpc --private --source=. --remote=origin --push
```

---

## 5. Phase 2: Build the Apptainer Container

### 5.1 Install Apptainer (Ubuntu 24.04 / WSL2)

```bash
sudo add-apt-repository -y ppa:apptainer/ppa
sudo apt update
sudo apt install -y apptainer
```

Fix the Ubuntu 24.04 namespace restriction:

```bash
echo "kernel.apparmor_restrict_unprivileged_userns = 0" | sudo tee /etc/sysctl.d/99-userns.conf
sudo sysctl --system
```

Verify:

```bash
apptainer --version
```

### 5.2 Build the .sif File

```bash
cd /path/to/hpc
sudo apptainer build containers/addone_latest.sif containers/apptainer.def
```

This downloads the base Docker image, installs dependencies, and produces a single immutable `.sif` file. The build requires `sudo` locally but typically not on the HPC itself.

The `.sif` file is a complete, portable execution environment. It contains Python 3.11, pyyaml, and everything needed to run the pipeline.

---

## 6. Phase 3: Test Locally

Before deploying to the HPC, verify the container works on your local machine:

```bash
apptainer exec containers/addone_latest.sif python pipelines/addone/addone.py --input test_data/numbers.txt --output /tmp/addone_output.txt
```

Check the output:

```bash
cat /tmp/addone_output.txt
```

Expected:

```
2.0
3.0
4.0
5.0
6.0
11.5
43.0
```

If this works, your container and pipeline are correct. Any failure here will also fail on the HPC, so fix issues locally first.

---

## 7. Phase 4: Deploy to HPC

### 7.1 Clone the Repository

SSH into the HPC and clone (use `--recurse-submodules` to pull container submodules):

```bash
ssh <username>@<hpc-host>
cd /groups/tprice/pipelines
git clone --recurse-submodules https://github.com/<username>/hpc.git .
```

If you already cloned without `--recurse-submodules`, initialize submodules manually:

```bash
git submodule update --init --recursive
```

### 7.2 Transfer the Container

The `.sif` file is not in git (it's a large binary). Transfer it separately from your local machine:

```bash
# Run this from your LOCAL machine, not the HPC
scp containers/addone_latest.sif <username>@<hpc-host>:/groups/tprice/pipelines/containers/
```

### 7.3 Verify on HPC

```bash
ls -la /groups/tprice/pipelines/containers/addone_latest.sif
ls /groups/tprice/pipelines/pipelines/addone/
```

---

## 8. Phase 5: Interactive Testing on HPC

Before submitting to SLURM, test interactively on a compute node. This catches path and bind mount issues before they become mysterious SLURM failures.

### 8.1 Get an Interactive Session

```bash
srun --time=00:05:00 --mem=1G --pty bash
```

This gives you a shell on a compute node (not the login node).

### 8.2 Resolve Real Paths

The HPC uses symlinks. Apptainer needs real paths for bind mounts:

```bash
export REAL_SCRATCH=$(readlink -f ~/scratch)
echo "Project: /groups/tprice/pipelines"
echo "Scratch: $REAL_SCRATCH"
```

On Juno, scratch resolves to `/scratch/juno/<username>`. The project root `/groups/tprice/pipelines` is already a real path (no symlink).

### 8.3 Run the Pipeline

```bash
cd /groups/tprice/pipelines
module load apptainer

apptainer exec --bind /groups/tprice/pipelines:/groups/tprice/pipelines --bind $REAL_SCRATCH:$REAL_SCRATCH containers/addone_latest.sif python /groups/tprice/pipelines/pipelines/addone/addone.py --input /groups/tprice/pipelines/test_data/numbers.txt --output $REAL_SCRATCH/addone_output.txt
```

### 8.4 Verify Output

```bash
cat ~/scratch/addone_output.txt
```

Expected output:

```
2.0
3.0
4.0
5.0
6.0
11.5
43.0
```

---

## 9. Phase 6: Submit via SLURM

Once interactive testing passes, submit as a scheduled job.

### 9.1 Prepare

```bash
cd /groups/tprice/pipelines
mkdir -p logs
```

### 9.2 Submit

```bash
sbatch slurm_templates/addone_slurm_template.sh configs/example_config.yaml
```

SLURM will return a job ID:

```
Submitted batch job 123456
```

---

## 10. Phase 7: Monitor and Verify

### 10.1 Check Job Status

```bash
squeue -u $USER
```

States you'll see:

| State | Meaning |
|-------|---------|
| `PD` | Pending — waiting for resources |
| `R` | Running |
| `CG` | Completing |
| (gone) | Finished (completed or failed) |

### 10.2 Check Logs

```bash
# stdout
cat logs/addone_<jobid>.out

# stderr
cat logs/addone_<jobid>.err
```

### 10.3 Check Output

```bash
cat ~/scratch/addone_output.txt
```

### 10.4 Check Job History

```bash
sacct -j <jobid> --format=JobID,State,ExitCode,Elapsed,MaxRSS
```

---

## 11. Key Concepts Explained

### 11.1 Why Containers?

Without containers, your pipeline depends on whatever Python version and libraries are installed on the HPC. Different nodes might have different versions. Updates can break your code. Other users' installs can conflict.

An Apptainer container is a single `.sif` file that bundles:
- The operating system
- Python (exact version)
- All libraries (exact versions)
- Your environment variables

It runs the same way everywhere, every time.

### 11.2 Why Bind Mounts?

Containers are isolated — they can't see the host filesystem by default. Bind mounts map host directories into the container:

```
--bind /groups/tprice/pipelines:/groups/tprice/pipelines
```

This means: "Make the host path `/groups/tprice/pipelines` visible inside the container at the same path."

You need bind mounts for:
- Your project directory (so the container can read your pipeline code and input data)
- Your scratch directory (so the container can write output)
- Your work directory (so the container can see your input data)

### 11.3 Why Config-Driven?

Hardcoding paths in your pipeline means everyone has to edit the code to run it. Config files separate "what the code does" from "where things are":

```yaml
input: /groups/tprice/pipelines/test_data/numbers.txt
output: /scratch/juno/<username>/addone_output.txt
```

Users copy the config, change their paths, and submit. The pipeline code stays untouched.

### 11.4 Symlinks and Real Paths

On Juno, `~/work` is a symlink:

```
~/work → /home/<username>/work → /work/<username>
```

And `~/scratch` is:

```
~/scratch → /home/<username>/scratch → /scratch/juno/<username>
```

Apptainer needs the **real** path for bind mounts. Always resolve with:

```bash
readlink -f ~/work
```

The shared project root `/groups/tprice/pipelines` is a real path and doesn't need resolution.

---

## 12. Adding a New Pipeline

There are two patterns for adding pipelines, depending on whether the pipeline code lives in this repo or in an external repo.

### Pattern A: Inline Pipeline (code lives in this repo)

Use this for simple pipelines you write yourself (like addone).

#### Step 1: Create pipeline directory

```bash
mkdir -p pipelines/fastqc
```

#### Step 2: Write the pipeline script

```bash
# pipelines/fastqc/fastqc_pipeline.py
```

#### Step 3: Update the container definition (if new dependencies are needed)

Edit `containers/apptainer.def` to add dependencies, then rebuild:

```bash
sudo apptainer build containers/fastqc_latest.sif containers/fastqc.def
```

#### Step 4: Create a SLURM template

Copy the addone template as a starting point and adjust resources (time, memory, CPUs):

```bash
cp slurm_templates/addone_slurm_template.sh slurm_templates/fastqc_slurm_template.sh
```

#### Step 5: Create an example config

```bash
# configs/fastqc_example_config.yaml
```

#### Step 6: Test locally, then interactively on HPC, then via SLURM

Follow the same phased testing approach documented above.

### Pattern B: Submoduled Pipeline (container repo is external)

Use this when the container definition lives in its own repo and/or the pipeline code is third-party (like bulkrnaseq).

#### Step 1: Add the container repo as a submodule

```bash
git submodule add https://github.com/<org>/<container-repo>.git containers/<name>/
cd containers/<name> && git checkout v1.0.0
cd ../..
git add containers/<name> .gitmodules
```

#### Step 2: Build the container

```bash
cd containers/<name>
sudo ./build.sh   # or: sudo apptainer build <name>.sif <name>.def
```

#### Step 3: Create a SLURM template with pre-flight checks

Copy the bulkrnaseq template as a starting point. Include checks for the container `.sif` and any external pipeline repos:

```bash
cp slurm_templates/bulkrnaseq_slurm_template.sh slurm_templates/<name>_slurm_template.sh
```

#### Step 4: Clone any external pipeline repos on the HPC

```bash
cd /groups/tprice/pipelines
git clone https://github.com/<org>/<pipeline-repo>.git
```

#### Step 5: Create an HPC guide

Create a top-level `<NAME>_HPC_GUIDE.md` documenting the multi-repo relationship, setup steps, and troubleshooting.

#### Step 6: Test and submit

Follow the same phased testing approach documented above.

### Updating a Submodule to a New Version

```bash
cd containers/<name>
git fetch --tags
git checkout v2.0.0
cd ../..
git add containers/<name>
git commit -m "Update <name> submodule to v2.0.0"
```

Then rebuild the container and transfer the new `.sif` to the HPC.

---

## 13. Troubleshooting

### "No such file or directory" inside the container

**Cause**: The file exists on the host but the container can't see it.
**Fix**: Add a `--bind` mount for the directory containing the file. Use `readlink -f` to get the real path.

### "Read-only file system" when writing output

**Cause**: The output directory isn't bind-mounted into the container.
**Fix**: Add `--bind $SCRATCH_ROOT:$SCRATCH_ROOT` to the apptainer exec command.

### "mount source doesn't exist"

**Cause**: You're trying to bind a symlinked path instead of the real path.
**Fix**: Use `readlink -f <path>` and bind the resolved path.

### "gocryptfs not found" warning

**Cause**: Informational message from Apptainer about encrypted filesystem support.
**Fix**: Ignore it. It's a warning, not an error.

### Arguments not recognized / "command not found"

**Cause**: Line breaks when pasting multi-line commands. The backslash line continuations didn't carry over.
**Fix**: Paste the entire command on a single line.

### SLURM job fails immediately

Check the error log:

```bash
cat logs/addone_<jobid>.err
```

Common causes:
- Wrong container path
- Wrong config path
- Missing `module load apptainer`
- Insufficient memory or time

### Container build fails

- Ensure you have `sudo` access (for local builds)
- Check internet connectivity (needs to pull Docker base image)
- Verify the definition file syntax

---

## 14. File Reference

### containers/apptainer.def

The container definition. Specifies base image, dependencies, and runtime configuration. Edit this when you need to add Python packages or system libraries.

### pipelines/addone/addone.py

The pipeline logic. Reads numbers from a file, adds 1 to each, writes output. Supports both direct arguments (`--input`, `--output`) and config-driven execution (`--config`).

### pipelines/addone/run_pipeline.sh

Optional convenience wrapper that calls the Python script with a config file.

### pipelines/addone/README.md

Pipeline-specific documentation.

### slurm_templates/addone_slurm_template.sh

SLURM job submission script. Defines resource requirements, loads Apptainer, sets up bind mounts, and runs the pipeline inside the container.

### configs/example_config.yaml

Example configuration with input and output paths. Users should copy this and modify paths for their own runs.

### test_data/numbers.txt

Sample input file for validating the pipeline works end-to-end.

### containers/bulkrnaseq/ (git submodule)

The `mwilde49/bulkseq` container repo, pinned to a release tag. Contains the Apptainer definition, build script, and test scripts for the Bulk RNA-Seq container. The `.sif` is built here but gitignored.

### slurm_templates/bulkrnaseq_slurm_template.sh

SLURM job submission script for the Bulk RNA-Seq pipeline. Runs Nextflow inside the bulkrnaseq container with `--cleanenv`. Includes pre-flight checks for the container and UTDal pipeline repo.

### BULKRNASEQ_HPC_GUIDE.md

Complete setup and usage guide for running the Bulk RNA-Seq pipeline on the HPC, including the three-repo relationship, first-time setup, and troubleshooting.

### .gitignore

Excludes `.sif` files (large binaries), logs, and user-specific configs from version control.

---

## 15. Quick Reference Card

### First-time setup (local machine)

```bash
# Install Apptainer (Ubuntu 24.04)
sudo add-apt-repository -y ppa:apptainer/ppa
sudo apt update && sudo apt install -y apptainer

# Build container
sudo apptainer build containers/addone_latest.sif containers/apptainer.def

# Test locally
apptainer exec containers/addone_latest.sif python pipelines/addone/addone.py --input test_data/numbers.txt --output /tmp/test_output.txt
```

### Deploy to HPC

```bash
# Clone repo on HPC (--recurse-submodules pulls container submodules)
cd /groups/tprice/pipelines
git clone --recurse-submodules https://github.com/<username>/hpc.git .

# Transfer container from local machine
scp containers/addone_latest.sif <username>@<hpc-host>:/groups/tprice/pipelines/containers/
```

### Run on HPC

```bash
# Submit job
cd /groups/tprice/pipelines
mkdir -p logs
sbatch slurm_templates/addone_slurm_template.sh configs/example_config.yaml

# Monitor
squeue -u $USER

# Check output
cat ~/scratch/addone_output.txt

# Check logs
cat logs/addone_*.out
cat logs/addone_*.err
```

### Update pipeline after code changes

```bash
# Local: commit and push
git add -A && git commit -m "Update pipeline" && git push

# HPC: pull updates
cd /groups/tprice/pipelines && git pull

# If container definition changed, rebuild and re-transfer the .sif
```

---

## Appendix: What This MVP Demonstrates

- Shared group directory structure
- Containerized execution with Apptainer
- SLURM job scheduling
- Config-driven workflow
- Reproducibility (versioned code + immutable container)
- User-level job submission model
- Proper logging with job ID traceability
- Scratch output separation from project space
- Symlink-aware bind mounting on Juno HPC
