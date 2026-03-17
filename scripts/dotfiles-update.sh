#!/bin/bash
# Copies dotfiles from this repository (dotfiles/) to their system locations.
# Files must be defined in config/dotfiles.yaml.
#
# Usage:
#   dotfiles-update.sh              # Update all dotfiles
#   dotfiles-update.sh bashrc       # Update only bashrc
#   dotfiles-update.sh bashrc sshd  # Update multiple specific configs

# Get repository root path (parent of scripts directory)
REPO_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Global .env file path
GLOBAL_ENV_FILE="/etc/homelab.env"

# Load global environment variables into shell for envsubst
if [ -f "$GLOBAL_ENV_FILE" ]; then
    set -a
    source "$GLOBAL_ENV_FILE"
    set +a
fi

# Export common system variables for envsubst
# These are shell variables by default and need to be exported
export HOSTNAME USER

# Config file path
CONFIG_FILE="$REPO_PATH/config/dotfiles.yaml"

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

# ============================================================
# LOAD CONFIGURATION FROM YAML
# ============================================================

# Load reload groups (in order of processing)
mapfile -t RELOAD_GROUPS < <(yq -r '.reload_groups[]' "$CONFIG_FILE")

# Build GROUP_CONFIGS associative array (group -> space-separated config IDs)
declare -A GROUP_CONFIGS=()
for group in "${RELOAD_GROUPS[@]}"; do
    GROUP_CONFIGS[$group]=""
done

# Load all config IDs and their groups
mapfile -t ALL_CONFIG_IDS < <(yq -r '.configs | keys[]' "$CONFIG_FILE")
for config_id in "${ALL_CONFIG_IDS[@]}"; do
    group=$(yq -r ".configs.\"$config_id\".group" "$CONFIG_FILE")
    if [[ -n "${GROUP_CONFIGS[$group]+x}" ]]; then
        if [[ -z "${GROUP_CONFIGS[$group]}" ]]; then
            GROUP_CONFIGS[$group]="$config_id"
        else
            GROUP_CONFIGS[$group]="${GROUP_CONFIGS[$group]} $config_id"
        fi
    fi
done

# Build CONFIG_SRC and CONFIG_DST associative arrays
declare -A CONFIG_SRC=()
declare -A CONFIG_DST=()
declare -A CONFIG_MODE=()
for config_id in "${ALL_CONFIG_IDS[@]}"; do
    src=$(yq -r ".configs.\"$config_id\".src" "$CONFIG_FILE")
    dst=$(yq -r ".configs.\"$config_id\".dst" "$CONFIG_FILE")
    mode=$(yq -r ".configs.\"$config_id\".mode // \"copy\"" "$CONFIG_FILE")
    CONFIG_SRC[$config_id]="$src"
    CONFIG_DST[$config_id]="$dst"
    CONFIG_MODE[$config_id]="$mode"
done

# Build RELOAD_COMMANDS associative array (group -> reload command)
declare -A RELOAD_COMMANDS=()
for group in "${RELOAD_GROUPS[@]}"; do
    reload_cmd=$(yq -r ".reload_commands.\"$group\".command // \"\"" "$CONFIG_FILE")
    if [[ -n "$reload_cmd" ]]; then
        RELOAD_COMMANDS[$group]="$reload_cmd"
    fi
done

# Build RELOAD_NOTES associative array (group -> note)
declare -A RELOAD_NOTES=()
for group in "${RELOAD_GROUPS[@]}"; do
    reload_note=$(yq -r ".reload_commands.\"$group\".note // \"\"" "$CONFIG_FILE")
    if [[ -n "$reload_note" ]]; then
        RELOAD_NOTES[$group]="$reload_note"
    fi
done

# ============================================================
# PARSE ARGUMENTS AND FILTER CONFIGS
# ============================================================

# Get requested config IDs from command line arguments
REQUESTED_CONFIGS=("$@")

# If specific configs were requested, validate and filter
if [[ ${#REQUESTED_CONFIGS[@]} -gt 0 ]]; then
    echo "Requested configs: ${REQUESTED_CONFIGS[*]}"
    echo ""
    
    # Validate that all requested configs exist
    for config_id in "${REQUESTED_CONFIGS[@]}"; do
        if [[ ! " ${ALL_CONFIG_IDS[@]} " =~ " ${config_id} " ]]; then
            echo "Error: Config '$config_id' not found in $CONFIG_FILE"
            echo "Available configs:"
            printf '  - %s\n' "${ALL_CONFIG_IDS[@]}"
            exit 1
        fi
    done
    
    # Filter GROUP_CONFIGS to only include requested configs
    for group in "${RELOAD_GROUPS[@]}"; do
        filtered_configs=""
        for config_id in ${GROUP_CONFIGS[$group]}; do
            if [[ " ${REQUESTED_CONFIGS[@]} " =~ " ${config_id} " ]]; then
                if [[ -z "$filtered_configs" ]]; then
                    filtered_configs="$config_id"
                else
                    filtered_configs="$filtered_configs $config_id"
                fi
            fi
        done
        GROUP_CONFIGS[$group]="$filtered_configs"
    done
fi

# ============================================================
# FUNCTIONS
# ============================================================

# Function to check and update a config file
check_and_update() {
    local repo_file="$1"
    local system_file="$2"
    local mode="$3"

    echo "=================================================="
    echo "  Checking $system_file..."
    
    # Check if repo file exists
    if [ ! -f "$repo_file" ]; then
        echo "  ⚠ WARNING: Repository file $repo_file does not exist."
        return 1
    fi
    
    # Check if system file exists
    if [ ! -f "$system_file" ]; then
        echo "  System file does not exist."
        
        # Ask if user wants to create
        read -p "  Create $system_file? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [[ "$mode" == "envsubst" ]]; then
                envsubst < "$repo_file" | sudo tee "$system_file" > /dev/null
            else
                sudo cp "$repo_file" "$system_file"
            fi
            echo "  ✓ Created $system_file"
            return 0
        else
            echo "  Skipped."
            return 1
        fi
    fi
    
    # Check for differences
    if [[ "$mode" == "envsubst" ]]; then
        # For envsubst mode, generate output and compare
        local temp_file=$(mktemp)
        envsubst < "$repo_file" > "$temp_file"
        if diff -q "$temp_file" "$system_file" > /dev/null 2>&1; then
            echo "  ✓ No differences found."
            rm -f "$temp_file"
            return 1
        fi
        echo "  Differences found:"
        diff --color=always -u "$system_file" "$temp_file" || true
        rm -f "$temp_file"
    else
        if diff -q "$repo_file" "$system_file" > /dev/null 2>&1; then
            echo "  ✓ No differences found."
            return 1
        fi
        echo "  Differences found:"
        diff --color=always -u "$system_file" "$repo_file" || true
    fi
    
    # Ask if user wants to update
    read -p "  Update $system_file? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ "$mode" == "envsubst" ]]; then
            envsubst < "$repo_file" | sudo tee "$system_file" > /dev/null
        else
            sudo cp "$repo_file" "$system_file"
        fi
        echo "  ✓ Updated $system_file"
        return 0
    else
        echo "  Skipped."
        return 1
    fi
}

# Function to ask about reloading
ask_reload() {
    local group="$1"
    local reload_cmd="$2"
    local note="$3"
    
    if [ -n "$note" ]; then
        echo "Note: $note"
    fi
    
    read -p "Reload $group with '$reload_cmd'? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        eval "$reload_cmd"
        echo "✓ Reloaded $group"
    else
        echo "Skipped reload."
    fi
}

# ============================================================
# MAIN SCRIPT
# ============================================================

# Process each reload group
for group in "${RELOAD_GROUPS[@]}"; do
    # Skip groups with no configs to process
    if [[ -z "${GROUP_CONFIGS[$group]}" ]]; then
        continue
    fi
    
    echo ""
    echo "=================================================="
    echo "$group"
    group_updated=false
    
    # Process each config in the group
    for config_id in ${GROUP_CONFIGS[$group]}; do
        src="${CONFIG_SRC[$config_id]}"
        dst="${CONFIG_DST[$config_id]}"
        mode="${CONFIG_MODE[$config_id]}"
        
        # Expand variables in destination path
        dst=$(eval echo "$dst")
        
        # Build full repo file path
        repo_file="$REPO_PATH/$src"
        
        if check_and_update "$repo_file" "$dst" "$mode"; then
            group_updated=true
        fi
    done
    
    # Ask to reload if any config in the group was updated
    if [ "$group_updated" = true ]; then
        reload_cmd="${RELOAD_COMMANDS[$group]}"
        
        # Only ask to reload if a reload command exists for this group
        if [ -n "$reload_cmd" ]; then
            echo "=================================================="
            reload_note="${RELOAD_NOTES[$group]}"
            ask_reload "$group" "$reload_cmd" "$reload_note"
        fi
    fi
done

echo "=================================================="
echo ""
echo "Configuration check complete!"
echo ""
