#!/usr/bin/env bash
#
# Add a WireGuard peer to the server and generate client configuration
#
# Usage: add-peer.sh [options] <peer-name>
#
# Options:
#   -i, --ip ADDRESS          Peer IP address (required, e.g., 10.0.0.2)
#   -a, --allowed-ips ADDRESS  Server IP to allow in client config (default: 10.0.0.1)
#   -d, --dns ADDRESS         DNS server address (adds DNS and PostUp route if specified)
#   -e, --endpoint ENDPOINT   Server endpoint (required, <public-ip>:<port>)
#   -n, --server-interface NAME WireGuard server interface name (default: wg0)
#   -p, --peer-interface NAME Client interface name for config file (default: wg-home)
#   --resolvectl-rule         Add Linux-specific PostUp resolvectl rule for routing all DNS through WG
#   --no-qr                   Don't display QR code
#   --no-psk                  Don't generate and use preshared key
#   -h, --help                Show this help message

set -euo pipefail

# Default values
PEER_IP=""
ALLOWED_IPS="10.0.0.1/32"
DNS=""
SERVER_ENDPOINT=""
SERVER_INTERFACE_NAME="wg0"
PEER_INTERFACE_NAME="wg-home"
RESOLVECTL_RULE=false
SHOW_QR=true
USE_PSK=true
PEER_NAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--ip)
            PEER_IP="$2"
            shift 2
            ;;
        -a|--allowed-ips)
            ALLOWED_IPS="$2"
            shift 2
            ;;
        -d|--dns)
            DNS="$2"
            shift 2
            ;;
        -e|--endpoint)
            SERVER_ENDPOINT="$2"
            shift 2
            ;;
        -n|--server-interface)
            SERVER_INTERFACE_NAME="$2"
            shift 2
            ;;
        -p|--peer-interface)
            PEER_INTERFACE_NAME="$2"
            shift 2
            ;;
        --resolvectl-rule)
            RESOLVECTL_RULE=true
            shift
            ;;
        --no-qr)
            SHOW_QR=false
            shift
            ;;
        --no-psk)
            USE_PSK=false
            shift
            ;;
        -h|--help)
            grep '^#' "$0" | tail -n +2 | head -n -1 | cut -c 3-
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            PEER_NAME="$1"
            shift
            ;;
    esac
done

# Validate required arguments
if [[ -z "$PEER_NAME" ]]; then
    echo "Error: peer name is required" >&2
    echo "Usage: add-peer.sh [options] <peer-name>" >&2
    exit 1
fi

if [[ -z "$PEER_IP" ]]; then
    echo "Error: peer IP address is required (use -i or --ip)" >&2
    exit 1
fi

if [[ -z "$SERVER_ENDPOINT" ]]; then
    echo "Error: server endpoint is required (use -e or --endpoint)" >&2
    exit 1
fi

# Hardcoded paths
KEY_DIR="/etc/wireguard"
OUTPUT_DIR="/etc/wireguard/clients/$PEER_NAME"
SERVER_CONFIG="/etc/wireguard/${SERVER_INTERFACE_NAME}.conf"

# Set restrictive permissions
umask 077

# Create output directory
mkdir -p "$OUTPUT_DIR"
mkdir -p "$KEY_DIR"

# Check if server config exists
if [[ ! -f "$SERVER_CONFIG" ]]; then
    echo "Error: Server config file not found: $SERVER_CONFIG" >&2
    echo "Run generate-wg-config.sh first to create the server configuration." >&2
    exit 1
fi

# Check if server public key exists
SERVER_PUBLIC_KEY="$KEY_DIR/${SERVER_INTERFACE_NAME}.pub"
if [[ ! -f "$SERVER_PUBLIC_KEY" ]]; then
    echo "Error: Server public key not found: $SERVER_PUBLIC_KEY" >&2
    echo "Run generate-wg-config.sh first to generate server keys." >&2
    echo "Expected key for interface: $SERVER_INTERFACE_NAME" >&2
    exit 1
fi

# Generate peer keys
PEER_PRIVATE_KEY="$OUTPUT_DIR/${PEER_INTERFACE_NAME}.key"
PEER_PUBLIC_KEY="$OUTPUT_DIR/${PEER_INTERFACE_NAME}.pub"

echo "Generating keypair for $PEER_NAME..." >&2
wg genkey | tee "$PEER_PRIVATE_KEY" | wg pubkey > "$PEER_PUBLIC_KEY"

# Generate preshared key if requested
PEER_PSK=""
if [[ "$USE_PSK" == true ]]; then
    echo "Generating preshared key..." >&2
    PEER_PSK_FILE="$OUTPUT_DIR/${PEER_INTERFACE_NAME}.psk"
    wg genpsk > "$PEER_PSK_FILE"
    PEER_PSK=$(cat "$PEER_PSK_FILE")
fi

# Add peer to server config
echo "" >> "$SERVER_CONFIG"
echo "# $PEER_NAME" >> "$SERVER_CONFIG"
echo "[Peer]" >> "$SERVER_CONFIG"
echo "PublicKey = $(cat "$PEER_PUBLIC_KEY")" >> "$SERVER_CONFIG"
if [[ -n "$PEER_PSK" ]]; then
    echo "PresharedKey = $PEER_PSK" >> "$SERVER_CONFIG"
fi
echo "AllowedIPs = ${PEER_IP}/32" >> "$SERVER_CONFIG"

echo "Added peer to $SERVER_CONFIG" >&2

# Create client configuration
CLIENT_CONFIG="$OUTPUT_DIR/${PEER_INTERFACE_NAME}.conf"

echo "Creating client configuration at $CLIENT_CONFIG..." >&2

cat > "$CLIENT_CONFIG" << EOF
[Interface]
PrivateKey = $(cat "$PEER_PRIVATE_KEY")
Address = ${PEER_IP}/24
EOF

if [[ -n "$DNS" ]]; then
    cat >> "$CLIENT_CONFIG" << EOF
DNS = $DNS
EOF
    if [[ "$RESOLVECTL_RULE" == true ]]; then
        cat >> "$CLIENT_CONFIG" << EOF
# Route ALL DNS queries through here:
PostUp = resolvectl domain %i "~."
EOF
    fi
fi

cat >> "$CLIENT_CONFIG" << EOF

[Peer]
PublicKey = $(cat "$SERVER_PUBLIC_KEY")
EOF

if [[ -n "$PEER_PSK" ]]; then
    cat >> "$CLIENT_CONFIG" << EOF
PresharedKey = $PEER_PSK
EOF
fi

cat >> "$CLIENT_CONFIG" << EOF
Endpoint = $SERVER_ENDPOINT
AllowedIPs = ${ALLOWED_IPS}
PersistentKeepalive = 25
EOF

echo "Client configuration created successfully!" >&2
echo "Client public key: $(cat "$PEER_PUBLIC_KEY")" >&2

# Display QR code if requested and qrencode is available
if [[ "$SHOW_QR" == true ]]; then
    if command -v qrencode &> /dev/null; then
        echo "" >&2
        echo "QR Code for mobile app:" >&2
        qrencode -t ansiutf8 < "$CLIENT_CONFIG"
    else
        echo "Note: qrencode not installed, skipping QR code generation" >&2
    fi
fi

# Sync the configuration if running on the server
if command -v wg &> /dev/null && [[ -d "/sys/class/net/$SERVER_INTERFACE_NAME" ]]; then
    echo "" >&2
    echo "Reloading WireGuard configuration..." >&2
    wg syncconf "$SERVER_INTERFACE_NAME" <(wg-quick strip "$SERVER_INTERFACE_NAME") || true
fi

echo "" >&2
echo "✓ Peer '$PEER_NAME' added successfully" >&2
echo "  Client config: $CLIENT_CONFIG" >&2
echo "  Keys stored in: $OUTPUT_DIR" >&2
