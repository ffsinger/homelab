# Homelab

Installation instructions, config files and scripts for a homelab server running Debian.

## Services

| Service | Usage | Dockerized |
|---------|-------|------------|
| [Traefik](https://traefik.io/) | Reverse proxy serving `<service>.<domain>` | Yes |
| [Technitium](https://technitium.com/dns/) | DNS server | Yes |
| [Jellyfin](https://jellyfin.org/) | Media server | Yes |
| [Sonarr](https://sonarr.tv/) | Series management | Yes |
| [Radarr](https://radarr.video/) | Movie management | Yes |
| [Bazarr](https://www.bazarr.media/) | Subtitle management | Yes |
| [Prowlarr](https://prowlarr.com/) | Indexer management | Yes |
| [qBittorrent](https://www.qbittorrent.org/) | BitTorrent client | Yes |
| [Gluetun](https://github.com/qdm12/gluetun) | VPN client for qBittorrent | Yes |
| [Homepage](https://gethomepage.dev/) | Dashboard with system information and links to other services | Yes |
| [Nextcloud](https://nextcloud.com/) | Cloud storage | Yes |
| [Syncthing](https://syncthing.net/) | 2-way sync between mobile phone and laptop with homelab as middleman | Yes |
| [Mokuro](https://github.com/kha-white/mokuro) | Manga OCR | Yes |
| [rclone](https://rclone.org/) | WebDAV server for syncing manga with mokuro-reader | Yes |
| [Gotify](https://gotify.net/) | Notification server | Yes |
| [Diun](https://crazymax.dev/diun/) | Notifications about new docker tags | Yes |
| [n8n](https://n8n.io/) | Easy automation, used for notifying about new manga volumes | Yes |
| [Wireguard](https://www.wireguard.com/) | VPN for accessing services from outside the home network | No |
| [Samba](https://www.samba.org/) | Easy access to the media library at the filesystem level | No |
| [Borg](https://www.borgbackup.org/) | Docker volumes backup with daily cron | No |


## Hardware

| Device | Usage |
|--------|-------|
| Minix NEO NGC N512 (16GB RAM, 512GB SSD, 2.5Gb ethernet) | Main unit |
| 5TB external HDD (USB) | Media library (series, movies, books, music), torrents, syncthing data, nextcloud data, docker volumes backups |
| 1TB external HDD (USB, offline, to be upgraded) | Media library backup |
