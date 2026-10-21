"""Standalone NPR extension: original main.py and HW2 commands remain unchanged."""
import argparse
from pathlib import Path
import os
from hw2 import npr

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Slang cel shading + feature lines + hatching')
    parser.add_argument('-output', '--output', type=str)
    npr.add_arguments(parser)
    args = parser.parse_args()
    # Existing shader loaders resolve modules relative to the repository root.
    os.chdir(Path(__file__).resolve().parent)
    args.func(args)
