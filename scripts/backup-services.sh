#!/bin/bash

# Get repository root path (parent of scripts directory)
REPO_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Config file path
CONFIG_FILE="$REPO_PATH/config/services.yaml"

# Check for yq dependency
if ! command -v yq &> /dev/null; then
    echo "Error: yq is not installed. Please install yq to use this script."
    exit 1
fi

# Check config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Setting this, so the repo does not need to be given on the commandline:
export BORG_REPO=/data/backups/borg

# See the section "Passphrase notes" for more infos.
# export BORG_PASSPHRASE='...'
export BORG_PASSCOMMAND="cat /opt/borg/passphrase"

# Load backup paths from config
BACKUP_PATHS=()
while IFS= read -r path; do
    BACKUP_PATHS+=("$path")
done < <(yq -r '.backups[].paths[]' "$CONFIG_FILE")

# Load exclude patterns from config
EXCLUDE_PATTERNS=()
while IFS= read -r pattern; do
    EXCLUDE_PATTERNS+=("$pattern")
done < <(yq -r '.backups[].exclude[]? // empty' "$CONFIG_FILE")

# some helpers and error handling:
info() { printf "\n%s %s\n\n" "$( date )" "$*" >&2; }
trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

info "Starting backup"

# Build exclude arguments
EXCLUDE_ARGS=()
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    EXCLUDE_ARGS+=(--exclude "$pattern")
done

# Backup the most important directories into an archive named after
# the machine this script is currently running on:

sudo -E borg create \
    --filter AME \
    --stats \
    --show-rc \
    --compression lz4 \
    --exclude-caches \
    "${EXCLUDE_ARGS[@]}" \
    ::'{hostname}-{now}' \
    "${BACKUP_PATHS[@]}"

backup_exit=$?

info "Pruning repository"

# Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
# archives of THIS machine. The '{hostname}-*' matching is very important to
# limit prune's operation to this machine's archives and not apply to
# other machines' archives also:

sudo -E borg prune \
    --glob-archives '{hostname}-*' \
    --show-rc \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6

prune_exit=$?

# actually free repo disk space by compacting segments

info "Compacting repository"

sudo -E borg compact

compact_exit=$?

# use highest exit code as global exit code
global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))
global_exit=$(( compact_exit > global_exit ? compact_exit : global_exit ))

if [ ${global_exit} -eq 0 ]; then
    info "Backup, Prune, and Compact finished successfully"
elif [ ${global_exit} -eq 1 ]; then
    info "Backup, Prune, and/or Compact finished with warnings"
else
    info "Backup, Prune, and/or Compact finished with errors"
fi

exit ${global_exit}
