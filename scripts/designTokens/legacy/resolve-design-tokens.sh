#!/bin/bash

# Get the current directory name
current_dir=$(basename "$PWD")

# Check if the current directory is "designTokens"
if [ "$current_dir" != "designTokens" ]; then
    echo "Please run this script from the 'designTokens' directory."
    exit 1
fi

# Check if the "figma-design-tokens" folder exists
if [ ! -d "../figma-design-tokens" ]; then
    rm -rf figma-design-tokens
fi

# Clone the repository
git clone "git@github.com:plume-design/figma-design-tokens.git"
echo "figma-design-tokens Repository downloaded successfully."

# Navigate to the "figma-design-tokens" directory
cd figma-design-tokens || exit 1

# tokens.json file is on master branch and not main branch,
git checkout master

# Check if the "tokens.json" file exists
if [ ! -f "tokens.json" ]; then
    echo "Error: The 'tokens.json' file does not exist."
    exit 1
fi

# Move the "tokens.json" file to its parent directory
mv tokens.json ..

# navigate back to designTokens directory
cd ..

# run the swift script to generate swift file for all tokens
swift generateTokens.swift

# clean up: remove figma-design-tokens repo and tokens.json file
rm tokens.json
rm -rf figma-design-tokens