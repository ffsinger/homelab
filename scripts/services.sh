#!/bin/bash

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

# Load startup order from config
mapfile -t START_ORDER < <(yq -r '.start_order[]' "$CONFIG_FILE")

# Function to check if config has differences
check_config_diff() {
    local service=$1
    local has_diff=false
    
    # Check service-specific config files from YAML config
    local file_count=$(yq ".services.\"$service\".files // [] | length" "$CONFIG_FILE")
    
    for ((i=0; i<file_count; i++)); do
        local src=$(yq -r ".services.\"$service\".files[$i].src" "$CONFIG_FILE")
        local dst=$(yq -r ".services.\"$service\".files[$i].dst" "$CONFIG_FILE")
        local mode=$(yq -r ".services.\"$service\".files[$i].mode // \"copy\"" "$CONFIG_FILE")
        local delete_flag=$(yq -r ".services.\"$service\".files[$i].delete // false" "$CONFIG_FILE")
        
        local repo_path="$REPO_PATH/$src"
        
        # Check if source exists in repo
        if [[ ! -e "$repo_path" ]]; then
            continue
        fi
        
        # Get display name (file or directory name)
        local display_name=$(basename "$src")
        
        if [[ -d "$repo_path" ]]; then
            # Directory comparison
            if [[ ! -d "$dst" ]]; then
                echo "  - $display_name directory does not exist"
                has_diff=true
            elif ! diff -qr "$repo_path/" "$dst/" > /dev/null 2>&1; then
                echo "  - $display_name directory differs"
                has_diff=true
            fi
        else
            # File comparison
            if [[ ! -f "$dst" ]]; then
                echo "  - $display_name does not exist"
                has_diff=true
            elif [[ "$mode" == "envsubst" ]]; then
                # For envsubst mode, generate output and compare
                local temp_file=$(mktemp)
                envsubst < "$repo_path" > "$temp_file"
                if ! diff -q "$temp_file" "$dst" > /dev/null 2>&1; then
                    echo "  - $display_name differs"
                    has_diff=true
                fi
                rm -f "$temp_file"
            elif ! diff -q "$repo_path" "$dst" > /dev/null 2>&1; then
                echo "  - $display_name differs"
                has_diff=true
            fi
        fi
    done
    
    if $has_diff; then
        return 0  # has diff
    else
        return 1  # no diff
    fi
}

# Function to update service config
update_service_config() {
    local service=$1
    
    echo "Updating $service configuration..."
    
    # Update service-specific files from YAML config
    local file_count=$(yq ".services.\"$service\".files // [] | length" "$CONFIG_FILE")
    
    for ((i=0; i<file_count; i++)); do
        local src=$(yq -r ".services.\"$service\".files[$i].src" "$CONFIG_FILE")
        local dst=$(yq -r ".services.\"$service\".files[$i].dst" "$CONFIG_FILE")
        local mode=$(yq -r ".services.\"$service\".files[$i].mode // \"copy\"" "$CONFIG_FILE")
        local delete_flag=$(yq -r ".services.\"$service\".files[$i].delete // false" "$CONFIG_FILE")
        
        local repo_path="$REPO_PATH/$src"
        
        # Skip if source doesn't exist
        if [[ ! -e "$repo_path" ]]; then
            continue
        fi
        
        if [[ "$mode" == "sync" ]]; then
            # Use rsync for sync mode
            if [[ "$delete_flag" == "true" ]]; then
                sudo rsync -a --delete "$repo_path/" "$dst/"
            else
                sudo rsync -a "$repo_path/" "$dst/"
            fi
        elif [[ "$mode" == "envsubst" ]]; then
            # Use envsubst to replace environment variables
            envsubst < "$repo_path" | sudo tee "$dst" > /dev/null
            sudo chown root:root "$dst"
        else
            # Use cp for copy mode
            if [[ -d "$repo_path" ]]; then
                sudo cp -r "$repo_path/" "$dst/"
            else
                sudo cp "$repo_path" "$dst"
            fi
            sudo chown root:root "$dst"
        fi
    done
    
    echo "Configuration updated."
}

# Function to start a service
start_service() {
    local service=$1
    local container=$2
    
    # Check for config diff
    if check_config_diff "$service"; then
        echo ""
        read -p "Update $service configuration? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            update_service_config "$service"
        fi
    fi
    
    if [[ -n "$container" ]]; then
        echo "Starting $container (from $service stack)..."
        sudo docker compose --env-file "/opt/$service/.env" --env-file "$GLOBAL_ENV_FILE" -f "/opt/$service/docker-compose.yml" up -d --build "$container"
    else
        echo "Starting $service..."
        sudo docker compose --env-file "/opt/$service/.env" --env-file "$GLOBAL_ENV_FILE" -f "/opt/$service/docker-compose.yml" up -d --build
        
        # Execute on_start hook if defined
        local on_start_hook=$(yq -r ".services.\"$service\".hooks.on_start // \"\"" "$CONFIG_FILE")
        if [[ -n "$on_start_hook" ]]; then
            sudo $on_start_hook
        fi
    fi
    echo ""
}

# Function to stop a service
stop_service() {
    local service=$1
    local container=$2
    
    if [[ -n "$container" ]]; then
        echo "Stopping $container (from $service stack)..."
        sudo docker compose --env-file "/opt/$service/.env" --env-file "$GLOBAL_ENV_FILE" -f "/opt/$service/docker-compose.yml" stop "$container"
    else
        echo "Stopping $service..."
        
        # Execute on_stop hook if defined
        local on_stop_hook=$(yq -r ".services.\"$service\".hooks.on_stop // \"\"" "$CONFIG_FILE")
        if [[ -n "$on_stop_hook" ]]; then
            sudo $on_stop_hook
        fi
        
        sudo docker compose --env-file "/opt/$service/.env" --env-file "$GLOBAL_ENV_FILE" -f "/opt/$service/docker-compose.yml" down
    fi
    echo ""
}

# Function to start all services
start_all() {
    for service in "${START_ORDER[@]}"; do
        start_service "$service"
    done
}

# Function to stop all services (reverse order)
stop_all() {
    for ((i=${#START_ORDER[@]}-1; i>=0; i--)); do
        stop_service "${START_ORDER[i]}"
    done
}

# Function to update version in .env file
update_version() {
    local service=$1
    local container=$2
    
    # Validate service exists
    if [[ ! " ${START_ORDER[*]} " =~ " ${service} " ]]; then
        echo "Error: Unknown service: $service"
        echo "Available services: ${START_ORDER[*]}"
        exit 1
    fi
    
    # Check .env file exists
    local env_file="/opt/$service/.env"
    if [[ ! -f "$env_file" ]]; then
        echo "Error: .env file not found: $env_file"
        exit 1
    fi
    
    # Derive version variable name (uppercase container + _VERSION)
    local version_var="$(echo "$container" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_VERSION"
    
    # Check if version variable exists in .env
    if sudo grep -q "^${version_var}=" "$env_file"; then
        # Read current version from .env
        local current_version=$(sudo grep "^${version_var}=" "$env_file" | cut -d'=' -f2)
        
        if [[ -z "$current_version" ]]; then
            echo "Current version: (not set)"
        else
            echo "Current version: $current_version"
        fi
    else
        echo "Warning: $version_var not found in $env_file"
        echo "Current version: (variable does not exist)"
    fi
    
    # Prompt for new version
    read -p "Enter new version: " new_version
    
    if [[ -z "$new_version" ]]; then
        echo "Error: Version cannot be empty"
        exit 1
    fi
    
    # Update .env file (or add if missing)
    echo "Updating $version_var to $new_version in $env_file..."
    if sudo grep -q "^${version_var}=" "$env_file"; then
        # Variable exists, update it
        sudo sed -i "s/^${version_var}=.*/${version_var}=${new_version}/" "$env_file"
    else
        # Variable doesn't exist, append it
        echo "${version_var}=${new_version}" | sudo tee -a "$env_file" > /dev/null
    fi
    
    # Pull new image
    echo "Pulling new image for $container..."
    sudo docker compose --env-file "/opt/$service/.env" --env-file "$GLOBAL_ENV_FILE" -f "/opt/$service/docker-compose.yml" pull "$container"
    
    # Restart service (with --build flag to rebuild if using build: directive)
    echo "Restarting $container..."
    sudo docker compose --env-file "/opt/$service/.env" --env-file "$GLOBAL_ENV_FILE" -f "/opt/$service/docker-compose.yml" up -d --build "$container"
    
    echo ""
    echo "Version updated successfully!"
}

# Main script
ACTION=$1
SERVICE=$2
CONTAINER=$3

case "$ACTION" in
    start)
        if [[ -z "$SERVICE" ]]; then
            start_all
        elif [[ -n "$CONTAINER" ]]; then
            # Starting individual container from a stack
            if [[ ! " ${START_ORDER[*]} " =~ " ${SERVICE} " ]]; then
                echo "Error: Unknown service: $SERVICE"
                echo "Available services: ${START_ORDER[*]}"
                exit 1
            fi
            start_service "$SERVICE" "$CONTAINER"
        else
            # Starting entire service/stack
            if [[ " ${START_ORDER[*]} " =~ " ${SERVICE} " ]]; then
                start_service "$SERVICE"
            else
                echo "Error: Unknown service: $SERVICE"
                echo "Available services: ${START_ORDER[*]}"
                exit 1
            fi
        fi
        ;;
    stop)
        if [[ -z "$SERVICE" ]]; then
            stop_all
        elif [[ -n "$CONTAINER" ]]; then
            # Stopping individual container from a stack
            if [[ ! " ${START_ORDER[*]} " =~ " ${SERVICE} " ]]; then
                echo "Error: Unknown service: $SERVICE"
                echo "Available services: ${START_ORDER[*]}"
                exit 1
            fi
            stop_service "$SERVICE" "$CONTAINER"
        else
            # Stopping entire service/stack
            if [[ " ${START_ORDER[*]} " =~ " ${SERVICE} " ]]; then
                stop_service "$SERVICE"
            else
                echo "Error: Unknown service: $SERVICE"
                echo "Available services: ${START_ORDER[*]}"
                exit 1
            fi
        fi
        ;;
    update)
        if [[ -z "$SERVICE" ]] || [[ -z "$CONTAINER" ]]; then
            echo "Error: update command requires both service and container"
            echo "Usage: $0 update <service> <container>"
            echo ""
            echo "Example:"
            echo "  $0 update torrent radarr"
            exit 1
        fi
        update_version "$SERVICE" "$CONTAINER"
        ;;
    *)
        echo "Usage: $0 {start|stop|update} [service] [container]"
        echo ""
        echo "Available services: ${START_ORDER[*]}"
        echo ""
        echo "Examples:"
        echo "  $0 start                    # Start all services"
        echo "  $0 start manga              # Start manga service"
        echo "  $0 start torrent radarr     # Start only radarr in torrent stack"
        echo "  $0 stop                     # Stop all services"
        echo "  $0 stop jellyfin            # Stop jellyfin service"
        echo "  $0 stop torrent qbittorrent # Stop only qbittorrent in torrent stack"
        echo "  $0 update torrent radarr    # Update radarr version in torrent stack"
        exit 1
        ;;
esac
