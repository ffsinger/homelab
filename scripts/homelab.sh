#!/bin/bash

# Script to check if the repository is clean before running another script
# This prevents privilege escalation that could occur by tampering scripts, as many of them run sudo commands

# Setup :
# 1. Check manually that the source script is clean and safe
# 2. sudo cp ~/homelab/scripts/homelab.sh /usr/local/bin/homelab

set -euo pipefail

# Get repository root path and scripts directory
REPO_PATH="$HOME/homelab"
SCRIPTS_DIR="$REPO_PATH/scripts"

# Check if a script argument was provided
if [ $# -eq 0 ]; then
    echo "Error: No script specified" >&2
    echo "Usage: $0 <script-name> [args...]" >&2
    echo "Examples:" >&2
    echo "  $0 storage-mount           # runs storage-mount.sh" >&2
    echo "  $0 services start          # runs services.sh with args 'start'" >&2
    echo "" >&2
    echo "Note: Only scripts in $SCRIPTS_DIR can be executed" >&2
    exit 1
fi

SCRIPT_NAME="$1"
shift  # Remove first argument, leaving any additional args

# Add .sh extension if not present
if [[ "$SCRIPT_NAME" != *.sh ]]; then
    SCRIPT_NAME="${SCRIPT_NAME}.sh"
fi

# Always resolve script path relative to scripts directory
# Even if user provides a path, we'll derive the basename
SCRIPT_BASENAME=$(basename "$SCRIPT_NAME")
SCRIPT_TO_RUN="$SCRIPTS_DIR/$SCRIPT_BASENAME"

# Check if the script exists and is executable
if [ ! -f "$SCRIPT_TO_RUN" ]; then
    echo "Error: Script '$SCRIPT_TO_RUN' not found" >&2
    exit 1
fi

if [ ! -x "$SCRIPT_TO_RUN" ]; then
    echo "Error: Script '$SCRIPT_TO_RUN' is not executable" >&2
    exit 1
fi

# Verify script is within the scripts directory
SCRIPT_REAL_PATH=$(realpath "$SCRIPT_TO_RUN")
SCRIPTS_DIR_REAL_PATH=$(realpath "$SCRIPTS_DIR")

if [[ "$SCRIPT_REAL_PATH" != "$SCRIPTS_DIR_REAL_PATH"* ]]; then
    echo "Error: Script must be within the scripts directory" >&2
    echo "Script: $SCRIPT_REAL_PATH" >&2
    echo "Scripts dir: $SCRIPTS_DIR_REAL_PATH" >&2
    exit 1
fi

# Change to repository directory
cd "$REPO_PATH"

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    echo "Error: Not in a git repository" >&2
    exit 1
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "Error: Repository has uncommitted changes" >&2
    echo "Please commit or stash your changes before running this script" >&2
    echo "" >&2
    echo "Uncommitted changes:" >&2
    git status --short >&2
    exit 1
fi

# Verify local branch matches remote origin
# This prevents attacks where someone commits malicious changes locally
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
LOCAL_COMMIT=$(git rev-parse HEAD)
REMOTE_COMMIT=$(git rev-parse "origin/$CURRENT_BRANCH" 2>/dev/null || echo "")

if [ -z "$REMOTE_COMMIT" ]; then
    echo "Error: No remote tracking branch found for '$CURRENT_BRANCH'" >&2
    echo "Cannot verify repository integrity" >&2
    exit 1
fi

if [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
    echo "Error: Local branch does not match remote origin" >&2
    echo "Branch: $CURRENT_BRANCH" >&2
    echo "Local:  $LOCAL_COMMIT" >&2
    echo "Remote: $REMOTE_COMMIT" >&2
    echo "" >&2
    echo "This could indicate:" >&2
    echo "  - Unpushed local commits (potential tampering)" >&2
    echo "  - Local branch is behind remote (run: git pull)" >&2
    echo "" >&2
    echo "For security, only scripts matching remote origin can be executed" >&2
    exit 1
fi

# Verify the script is tracked by git (not an untracked file)
SCRIPT_RELATIVE_PATH=$(realpath --relative-to="$REPO_PATH" "$SCRIPT_TO_RUN")
if ! git ls-files --error-unmatch "$SCRIPT_RELATIVE_PATH" >/dev/null 2>&1; then
    echo "Error: Script is not tracked by git" >&2
    echo "File: $SCRIPT_RELATIVE_PATH" >&2
    echo "Only git-tracked scripts can be executed for security" >&2
    exit 1
fi

# Check for untracked files that might be important
if [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo "Warning: Repository has untracked files" >&2
    git ls-files --others --exclude-standard >&2
    echo "" >&2
fi

# Repository is clean, run the script
exec "$SCRIPT_TO_RUN" "$@"
