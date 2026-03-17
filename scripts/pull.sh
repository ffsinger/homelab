#!/bin/bash

# git pull that works wherever we are in the filesystem

# Get the repository root path
REPO_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Change to the repository root
cd "$REPO_PATH"

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    echo "Error: Not a git repository" >&2
    exit 1
fi

# Perform git pull
git pull
