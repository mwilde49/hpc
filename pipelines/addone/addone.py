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
