#!/usr/bin/env bash
# test_dconvatac_gpu.sh — TJP test module for the dconvatac-gpu pipeline
# GPU variant shares all logic with dconvatac; delegate to that module.

PIPELINE_NAME="dconvatac-gpu"
L3_SKIP=true
L3_SKIP_REASON="No minimal h5ad test fixtures available yet"

# Source the shared dconvatac module for L1/L2 implementations
_DCONVATAC_MODULE="$(dirname "${BASH_SOURCE[0]}")/test_dconvatac.sh"
# shellcheck source=test_dconvatac.sh
source "$_DCONVATAC_MODULE"

# Override function names to match the dconvatac-gpu pipeline slug
l1_dconvatac_gpu() { l1_dconvatac "$@"; }
l2_dconvatac_gpu() { l2_dconvatac "$@"; }
l3_fixture_dconvatac_gpu() { return 1; }
l3_submit_dconvatac_gpu()  { :; }
l3_validate_dconvatac_gpu() { :; }
l3_teardown_dconvatac_gpu() { :; }
