# Config YAML Schemas

Each `.yaml` file in this directory is a lightweight schema for a pipeline's `config.yaml`. These schemas document the expected fields, types, and constraints without requiring a full YAML Schema implementation.

## Format

Each schema file uses a simple annotation format:

```yaml
# field_name:
#   type:       string | integer | boolean | path | enum[val1, val2]
#   required:   true | false
#   default:    <value> (if optional)
#   description: <one-line description>
#   example:    <example value>
```

## IDE Integration

For VS Code YAML validation, install the [YAML extension](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml) and associate schema files with config YAMLs. The schemas here use human-readable comments rather than JSON Schema syntax to remain accessible without tooling.

## Files

| Schema | Pipeline |
|--------|----------|
| `addone.yaml` | AddOne (demo pipeline) |
| `bulkrnaseq.yaml` | BulkRNASeq (STAR + StringTie) |
| `psoma.yaml` | Psoma (HISAT2 + StringTie) |
| `virome.yaml` | Virome (viral metagenomics) |
| `cellranger.yaml` | Cell Ranger count |
| `cellranger_mkfastq.yaml` | Cell Ranger mkfastq |
| `cellranger_multi.yaml` | Cell Ranger multi |
| `spaceranger.yaml` | Space Ranger |
| `xeniumranger.yaml` | Xenium Ranger |
| `sqanti3.yaml` | SQANTI3 |
| `wf_transcriptomes.yaml` | wf-transcriptomes |
