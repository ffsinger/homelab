#!/usr/bin/env bash
#
# Generate WireGuard server configuration
#
# Usage: generate-wg-config.sh [options]
#
# Options:
#   -n, --name NAME           Interface name (default: wg0)
#   -a, --address ADDRESS     Server address (default: 10.0.0.1/24)
#   -p, --port PORT           Listen port (default: 51820)
#   -h, --help                Show this help message

set -euo pipefail

# Default values
INTERFACE_NAME="wg0"
SERVER_ADDRESS="10.0.0.1/24"
LISTEN_PORT="51820"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            INTERFACE_NAME="$2"
            shift 2
            ;;
        -a|--address)
            SERVER_ADDRESS="$2"
            shift 2
            ;;
        -p|--port)
            LISTEN_PORT="$2"
            shift 2
            ;;
        -h|--help)
            grep '^#' "$0" | tail -n +2 | head -n -1 | cut -c 3-
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Hardcoded paths
KEY_DIR="/etc/wireguard"
OUTPUT_FILE="/etc/wireguard/${INTERFACE_NAME}.conf"

# Set restrictive permissions
umask 077

# Create key directory if it doesn't exist
mkdir -p "$KEY_DIR"

# Generate server keys if they don't exist
SERVER_PRIVATE_KEY="$KEY_DIR/${INTERFACE_NAME}.key"
SERVER_PUBLIC_KEY="$KEY_DIR/${INTERFACE_NAME}.pub"

if [[ -f "$SERVER_PRIVATE_KEY" ]]; then
    echo "Warning: Server private key already exists at $SERVER_PRIVATE_KEY" >&2
    echo "Using existing key. Delete it if you want to generate a new one." >&2
else
    echo "Generating server keypair..." >&2
    wg genkey | tee "$SERVER_PRIVATE_KEY" | wg pubkey > "$SERVER_PUBLIC_KEY"
    echo "Server public key: $(cat "$SERVER_PUBLIC_KEY")" >&2
fi

# Read the private key
PRIVATE_KEY=$(cat "$SERVER_PRIVATE_KEY")

# Create the configuration file
echo "Creating WireGuard server configuration at $OUTPUT_FILE..." >&2

cat > "$OUTPUT_FILE" << EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $SERVER_ADDRESS
ListenPort = $LISTEN_PORT
EOF

echo "Server configuration created successfully!" >&2
echo "Server public key: $(cat "$SERVER_PUBLIC_KEY")" >&2
echo "Add peers using the add-peer.sh script." >&2
