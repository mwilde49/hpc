# Titan Local Metadata Store — Schema Reference

Developer reference for the local JSON metadata store that mirrors the Titan
PostgreSQL schema. When Titan comes online, records with `titan_registered: false`
are pushed by a migration script.

## Directory Structure

```
$WORK_ROOT/pipelines/metadata/     ← metadata store root (outside repo)
    pipeline_runs/
        PLR-a4f2.json
        PLR-c9m1.json
        ...
```

The store lives on the HPC work filesystem (`/work/$USER/pipelines/metadata/`),
not in the git repository. This directory (`metadata/`) contains only this
schema document; all data files are excluded via `.gitignore`.

## Titan ID Format

```
TYPE-xxxx
```

- `TYPE` — uppercase prefix identifying the record type (see table below)
- `xxxx` — 4 random lowercase alphanumeric characters (`[a-z0-9]`)
- Collision-checked against existing store records before returning

| Prefix | Entity          |
|--------|-----------------|
| PRJ    | Project         |
| SMP    | Sample          |
| LIB    | Library         |
| RUN    | Sequencing run  |
| PLR    | Pipeline run    |
| REF    | Reference       |
| ANN    | Annotation      |

## `pipeline_run` Record — Field Reference

| Field               | Type    | Required | Description |
|---------------------|---------|----------|-------------|
| `pipeline_run_id`   | string  | yes      | Titan ID, e.g. `PLR-a4f2` |
| `pipeline_name`     | string  | yes      | Pipeline name, e.g. `cellranger` |
| `pipeline_version`  | string  | yes      | Tool or workflow version |
| `project_id`        | string  | no       | Linked `PRJ-xxxx` or null |
| `sample_id`         | string  | no       | Linked `SMP-xxxx` or null |
| `library_id`        | string  | no       | Linked `LIB-xxxx` or null |
| `run_id`            | string  | no       | Linked `RUN-xxxx` or null |
| `output_path`       | string  | yes      | Absolute path to pipeline outputs |
| `status`            | string  | yes      | `pending` \| `running` \| `completed` \| `failed` \| `cancelled` |
| `parameters`        | object  | no       | Pipeline parameters as JSON object |
| `parameters_hash`   | string  | auto     | `sha256:<hex>` of the parameters JSON |
| `container_image`   | string  | no       | `native:<path>` for 10x tools; SIF path or image URI for containers |
| `container_hash`    | string  | no       | Checksum of the container image, or null |
| `slurm_job_id`      | string  | no       | SLURM job ID after submission, or null |
| `started_at`        | string  | no       | ISO-8601 timestamp when job started, or null |
| `completed_at`      | string  | no       | ISO-8601 timestamp when job completed, or null |
| `duration_seconds`  | integer | no       | Elapsed seconds, or null |
| `launched_by`       | string  | auto     | `$USER` at registration time |
| `launched_from`     | string  | auto     | `hostname` at registration time |
| `hyperion_run_dir`  | string  | no       | Hyperion run directory path (mirrors `output_path` for most pipelines) |
| `registered_at`     | string  | auto     | ISO-8601 UTC timestamp at record creation |
| `titan_registered`  | boolean | auto     | Always `false` locally; set to `true` after migration to Titan DB |

### `titan_registered` Migration Flag

All locally-created records carry `"titan_registered": false`. When Titan's
PostgreSQL database goes live, the migration script will:

1. Enumerate `metadata/pipeline_runs/*.json` where `titan_registered == false`
2. POST each record to the Titan API
3. Set `titan_registered: true` in the local file as a receipt

## Example Record

```json
{
    "pipeline_run_id": "PLR-a4f2",
    "pipeline_name": "cellranger",
    "pipeline_version": "10.0.0",
    "project_id": null,
    "sample_id": null,
    "library_id": null,
    "run_id": null,
    "output_path": "/work/maw210003/pipelines/cellranger/runs/2026-04-05_10-00-00/",
    "status": "pending",
    "parameters": {},
    "parameters_hash": "sha256:44136fa355ba77b9ad9648b265232e4d4b928c87c1c7b135c55a82059f5c0a1b",
    "container_image": "native:/groups/tprice/opt/cellranger-10.0.0",
    "container_hash": null,
    "slurm_job_id": null,
    "started_at": null,
    "completed_at": null,
    "duration_seconds": null,
    "launched_by": "maw210003",
    "launched_from": "juno.hpcre.utdallas.edu",
    "hyperion_run_dir": "/work/maw210003/pipelines/cellranger/runs/2026-04-05_10-00-00/",
    "registered_at": "2026-04-05T10:00:00+00:00",
    "titan_registered": false
}
```

## Example `labdata` Commands

```bash
# Generate a new ID without creating a record
labdata new-id PLR

# Register a pipeline run
labdata register-run \
    --pipeline cellranger \
    --version 10.0.0 \
    --output-path /work/maw210003/pipelines/cellranger/runs/2026-04-05_10-00-00/ \
    --status pending \
    --container "native:/groups/tprice/opt/cellranger-10.0.0" \
    --run-dir /work/maw210003/pipelines/cellranger/runs/2026-04-05_10-00-00/

# List all runs as a table
labdata find runs

# Filter by pipeline and status
labdata find runs --pipeline psoma --status completed

# Show full JSON for a specific run
labdata show PLR-a4f2

# Summary counts
labdata status
```
