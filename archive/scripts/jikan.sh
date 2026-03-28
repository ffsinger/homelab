#!/bin/bash

set -euo pipefail

LOG="/var/log/jikan.log"
COMPOSE_FILE="/opt/jikan/docker-compose.yml"
DOCKER_COMPOSE_CMD="sudo docker compose"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <command>" >&2
    echo "Commands:" >&2
    echo "  execute-indexers      Index all anime, manga, characters, people, genres, and producers" >&2
    echo "  index-incrementally   Incrementally index anime and manga" >&2
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
  sudo -v
  sudo -n bash -c "nohup '$0' '$1' >> '$LOG' 2>&1 &"
  echo "Running in background. Follow progress with: tail -f $LOG"
  exit 0
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

case "$1" in
    "execute-indexers")
        log "Indexing anime..."
        $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" exec jikan php /app/artisan indexer:anime
        log "Indexing manga..."
        $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" exec jikan php /app/artisan indexer:manga
        log "Indexing characters and people..."
        $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" exec jikan php /app/artisan indexer:common
        log "Indexing genres..."
        $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" exec jikan php /app/artisan indexer:genres
        log "Indexing producers..."
        $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" exec jikan php /app/artisan indexer:producers
        log "Indexing done!"
        ;;
    "index-incrementally")
        log "Indexing..."
        $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" exec jikan php /app/artisan indexer:incremental anime manga
        log "Indexing done!"
        ;;
    *)
        echo "Error: Unknown command '$1'" >&2
        exit 1
        ;;
esac
