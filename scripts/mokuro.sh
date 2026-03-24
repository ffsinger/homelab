#!/bin/bash
# Check for volume directories without matching .mokuro files and process them individually

LOG="/var/log/mokuro.log"

# If not root, re-launch with sudo nohup in the background and exit
if [ "$EUID" -ne 0 ]; then
  sudo -v
  sudo -n bash -c "nohup '$0' >> '$LOG' 2>&1 &"
  echo "Running in background. Follow progress with: tail -f $LOG"
  exit 0
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "=== mokuro run started ==="

MANGA_DIR="/data/downloads/media/books/Manga"

find "$MANGA_DIR" -mindepth 2 -maxdepth 2 -type d | sort | while read volume_dir; do
  # Get relative path from manga dir (e.g., "Frieren/15")
  rel_path="${volume_dir#$MANGA_DIR/}"
  
  # Skip _ocr directories
  if [[ "$(basename "$volume_dir")" == "_ocr" ]]; then
    continue
  fi
  
  # Check if matching .mokuro file exists
  mokuro_file="${volume_dir}.mokuro"
  
  if [ ! -f "$mokuro_file" ]; then
    log "Processing: $rel_path"
    docker exec mokuro mokuro --disable_confirmation=true "$rel_path"
  else
    log "Skipping (already processed): $rel_path"
  fi
done

log "=== mokuro run finished ==="
