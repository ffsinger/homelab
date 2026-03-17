#!/bin/bash

echo "Starting Tailscale..."
sudo tailscale up --snat-subnet-routes=false --accept-dns=false
echo "Tailscale can be stopped with 'sudo tailscale down'"
