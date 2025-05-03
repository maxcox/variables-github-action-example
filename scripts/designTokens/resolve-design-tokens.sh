#!/bin/bash

# Get the current directory name
current_dir=$(basename "$PWD")

# Check if the current directory is "designTokens"
if [ "$current_dir" != "designTokens" ]; then
    echo "Please run this script from the 'designTokens' directory."
    exit 1
fi

# run the swift script to generate swift file for all tokens
swift ./generateTokens.swift
swift ./generateStyleTokens.swift
