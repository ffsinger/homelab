# Homelab

Installation instructions, config files and scripts for a homelab server setup.

## Software

### OS

Debian 13 (trixie)

### Dockerized services

- Traefik (reverse proxy serving `<service>.<domain>`)
- Technitium (DNS server)
- Jellyfin (media server)
- Sonarr, Radarr, Bazarr, Prowlarr (media management)
- qBittorrent, through a consumer VPN with Gluetun
- Homepage (dashboard with links to other services and with system information)
- Nextcloud (cloud storage)
- Syncthing (2-way sync between mobile phone and laptop with homelab as middleman)
- Mokuro (manga OCR), rclone serve WebDAV (for syncing manga with mokuro-reader)
- Gotify (notification server)
- Diun (notifications about new docker tags)
- n8n (easy automation, used for notifying about new manga volumes)

#### Bare metal services

- Wireguard VPN (for accessing services from outside the home network)
- nftables firewall
- samba (for easy access to the media library at the filesystem level)
- Borg backup (for docker volumes) with daily cron


## Hardware

- Minix NEO NGC N512 (16GB RAM, 512GB SSD, 2.5Gb ethernet)
- 5TB external HDD (USB) for storing : 
    - media (series, movies, books, music)
    - torrents
    - syncthing data
    - nextcloud data
    - backups (docker volumes)
- 1TB (to be upgraded) offline external HDD (USB) for storing :
    - backup of media library
