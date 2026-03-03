#!/bin/bash

CONFIG=$1

if [ -z "$CONFIG" ]; then
    echo "Usage: run_pipeline.sh <config.yaml>"
    exit 1
fi

python addone.py --config $CONFIG
