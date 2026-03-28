# Homelab - Installation and setup instructions

## Base setup

- Download Debian and make bootable USB
- Run installer
    - No root password, just a sudoer
    - Encrypted LVM partition
    - Single partition + swap
    - No desktop environment
    - SSH server
- Set a static IP for the homelab on the router
- If keyboard is wrong : `sudo dpkg-reconfigure keyboard-configuration`
- If language is wrong : `sudo dpkg-reconfigure locales`
- Create SSH key : `ssh-keygen -t ed25519 -C "$USER@$HOSTNAME"`

## Repository

- Add the SSH key to your GitHub repo as a deploy key (read-only)

```bash
sudo apt install git vim

# Repo is cloned in the home directory
cd ~
git clone git@github.com:<github-username>/homelab.git

# Setup env file
sudo cp ~/homelab/.env.example /etc/homelab.env
# Fill in your values
sudoedit /etc/homelab.env
```

## SSH

- Copy your client's public key to the server's `~/.ssh/authorized_keys` (e.g. `ssh-copy-id`)

### Server

- [sshd_config](./dotfiles/etc/ssh/sshd_config)
    - `PermitRootLogin no`
    - `PasswordAuthentication no`
    - `PubkeyAuthentication yes`

```bash
# Make user processes stay alive after closing the SSH tunnel
sudo loginctl enable-linger $USER

# Update sshd_config
homelab dotfiles-update sshd
```

#### During boot

- Dropbear is a SSH server that runs in initramfs, SSH before the system has finished loading
    - Needed to input the root partition decryption password
- [dropbear.conf](./dotfiles/etc/dropbear/initramfs/dropbear.conf)
- [initramfs.conf](./dotfiles/etc/initramfs-tools/initramfs.conf.template)

```bash
sudo apt install dropbear-initramfs
sudo cp ~/.ssh/authorized_keys /etc/dropbear/initramfs/

# Update dropbear.conf and initramfs.conf
homelab dotfiles-update dropbear_conf initramfs_conf
```

### Agent

- [config](./dotfiles/home/user/.ssh/config)
- Auto start ssh-agent in [.bashrc](./dotfiles/home/user/.bashrc)

```bash
# Update SSH config
homelab dotfiles-update ssh_user
```

## Bash

- [.bashrc](./dotfiles/home/user/.bashrc)
- [.profile](./dotfiles/home/user/.profile)
- [.inputrc](./dotfiles/home/user/.inputrc)

```bash
# Update .bashrc, .profile and .inputrc
homelab dotfiles-update bashrc profile inputrc
```

## Storage

```
data                    # Data drive
├── nextcloud
├── syncthing
├── backups
│   └── borg            # Docker volumes backups
└── downloads
    ├── torrents        # qbittorrent download location
    └── media           # Media library
        ├── books
        │   └── Manga   # Mangas as .jpg and .mokuro files
        ├── movies
        │   ├── Movies  # Jellyfin library
        │   └── ...
        ├── music
        └── series
            ├── Series  # Jellyfin library
            └── ...
mnt
└── hdd                 # Offline backup drive
    └── media           # Media library backup
```

- Both the data and backup drives are assumed to be already LUKS encrypted
- Drives can be decrypted automatically thanks to the keyfile
- Keyfile is unreadable at rest due to full system encryption

```bash
sudo apt install cryptsetup
sudo mkdir /data

# Create a keyfile with random data
sudo mkdir /etc/luks-keys/
sudo dd if=/dev/urandom of=/etc/luks-keys/data_drive.key bs=512 count=1
sudo chmod 600 /etc/luks-keys/data_drive.key

# Add the keyfile as an authorized key to your LUKS volume
sudo cryptsetup luksAddKey /dev/sda1 /etc/luks-keys/data_drive.key

# Mount drive
homelab storage-mount
```

### Auto decrypt and mount

- [fstab](./dotfiles/etc/fstab.template)
- [crypttab](./dotfiles/etc/crypttab.template)

```bash
# Update DATA_FS_UUID in env
sudoedit /etc/homelab.env

# Update fstab and crypttab
homelab dotfiles-update fstab crypttab
```

## System updates - unattended-upgrades

```bash
sudo apt install unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades
sudo unattended-upgrades --dry-run --debug
```

## Backups

### Media

- [backup-media.sh](./scripts/backup-media.sh)
    - Depending on the setup, 2 HDDs without a powered USB hub may draw too much power and cause one to disconnect, in which case backup must be done with rsync over SSH.

### Docker volumes

- [Borg](https://github.com/borgbackup/borg)
- [backup-services.sh](./scripts/backup-services.sh)
- [cron.daily/backup-services](./dotfiles/etc/cron.daily/backup-services)
- [config](./config/services.yaml)
- Could also send the backup to cloud storage with rclone

```bash
sudo apt install borgbackup
sudo mkdir -p /data/backups/borg
sudo mkdir -p /opt/borg

read -s -p "Enter borg password: " BORG_PASSPHRASE
echo
echo "$BORG_PASSPHRASE" | sudo tee /opt/borg/passphrase > /dev/null
sudo chmod 600 /opt/borg/passphrase

sudo borg init --encryption=repokey /data/backups/borg
# Save this file to a password manager
sudo borg key export /data/backups/borg/ encrypted-key-backup

# Update daily cron job
homelab dotfiles-update backup_services_cron
```

## Firewall - nftables

- [nftables.conf](./dotfiles/etc/nftables.conf)
- Don't drop forward packets, it breaks docker bridge network drivers (i.e. no internet access inside container)
- Docker managed its own NAT table, so it's not affected by my filter table, and thus no need to open ports for docker services, they're already accessible. If I wanted to restrict it to localhost, I would have done `"127.0.0.1:8096:8096"` in the compose file.

```bash
sudo apt install nftables
sudo systemctl enable --now nftables

# Update nftables.conf
homelab dotfiles-update nftables
```

## VPN - Wireguard

- [wg-generate-config.sh](./scripts/wg-generate-config.sh)
- [wg-add-peer.sh](./scripts/wg-add-peer.sh)
- Must have open port in firewall
- Must add port forwarding to the homelab on the router for port `51820` (UDP only)

```bash
sudo apt install qrencode

sudo ./scripts/wg-generate-config.sh -n wg0 -a 10.0.0.1/24 -p 51820
# Linux device
sudo ./scripts/wg-add-peer.sh -i 10.0.0.2 -a 10.0.0.1/32 -d 10.0.0.1 -e ${PUBLIC_IP}:51820 -n wg0 -p wg-home --no-qr --resolvectl-rule <device-name>
# Android device
sudo ./scripts/wg-add-peer.sh -i 10.0.0.3 -a 10.0.0.1/32 -d 10.0.0.1 -e ${PUBLIC_IP}:51820 -n wg0 -p wg-home <device-name>
```

- For Android : scan the QR code with the Wireguard app
- For Linux : copy the config in `/etc/wireguard/clients` to the client's machine, then **either**
    - NetworkManager : `sudo nmcli connection import type wireguard file /etc/wireguard/wg-home.conf`
    - CLI based : `sudo systemctl enable --now wg-quick@wg-home`

```bash
sudo systemctl enable --now wg-quick@wg0
sudo rm -r /etc/wireguard/clients
```

### When booting

```bash
sudo ./scripts/wg-generate-config.sh -n initramfs -a 10.0.1.1/24 -p 51820
# Linux device
sudo ./scripts/wg-add-peer.sh -i 10.0.1.2 -a 10.0.1.1/32 -e ${PUBLIC_IP}:51820 -n initramfs -p wg-home-boot --no-qr <device-name>
```

- Copy the config in `/etc/wireguard/clients` to the client's machine

```bash
sudo rm -r /etc/wireguard/clients
```

- Install [wireguard-initramfs](https://github.com/r-pufky/wireguard-initramfs/) :

```bash
sudo apt install build-essential

cd /tmp
RELEASE=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/r-pufky/wireguard-initramfs/releases/latest | tr "/" "\n" | tail -n 1)

wget https://github.com/r-pufky/wireguard-initramfs/archive/refs/tags/"${RELEASE}".tar.gz
tar xvf "${RELEASE}".tar.gz
rm "${RELEASE}".tar.gz

sudo mv wireguard-initramfs-"${RELEASE}" /opt/

cd /opt/wireguard-initramfs-"${RELEASE}"
sudo make install
sudo make build_initramfs
```

## Samba

- [Arch Wiki](https://wiki.archlinux.org/title/Samba)
- [smb.conf](./etc/samba/smb.conf)
- For accessing the media library

```bash
sudo apt install samba

sudo smbpasswd -a $USER

# Update smb.conf
homelab dotfiles-update samba
```

## Docker

- [Docs](https://docs.docker.com/)
- [Install](https://docs.docker.com/engine/install/debian/) (do not use the default apt repository)
- [daemon.json](./dotfiles/etc/docker/daemon.json)
- Auto update : `sudoedit /etc/apt/apt.conf.d/50unattended-upgrades`
    - `"origin=Docker,label=Docker CE";` in `Unattended-Upgrade::Origins-Pattern { }`
- IP forward is required for creating networks

```bash
sudo sysctl -w net.ipv4.ip_forward=1
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-docker.conf

# Update daemon.json
homelab dotfiles-update docker
```

## Syncthing

- [Docs](https://docs.syncthing.net/)
- [docker-compose.yml](./services/syncthing/docker-compose.yml)
- Set a password for the GUI on first launch
- Can add the direct address in the connection settings for a peer instead of relying on the relay servers
- Can add [file versioning](https://docs.syncthing.net/v2.0.0/users/versioning) on the server side (applies only to changes received from other devices, not local changes)

```bash
sudo mkdir -p /opt/syncthing
sudo mkdir -p /opt/syncthing/config
sudo chown -R $USER:$USER /opt/syncthing/config

echo "SYNCTHING_VERSION=" | sudo tee /opt/syncthing/.env > /dev/null

sudo chmod 600 /opt/syncthing/.env
```

## Reverse proxy - Traefik

- [Docs Traefik](https://doc.traefik.io/traefik)
- [docker-compose.yml](./services/traefik/docker-compose.yml)
- [dynamic.yml.template](./services/traefik/dynamic.yml.template) for non-Docker services (generates dynamic.yml)
- Use a purchased domain name and add local DNS records in an internal DNS server (Technitium, Pi-hole or AdGuard)
- Let's Encrypt DNS challenge via [Traefik's built-in ACME provider](https://doc.traefik.io/traefik/reference/install-configuration/tls/certificate-resolvers/acme/), handling certificate generation and renewal automatically
- [Docker Socket Proxy](https://github.com/Tecnativa/docker-socket-proxy) for secure Docker API access (only CONTAINERS and NETWORKS permissions)

```bash
sudo mkdir -p /opt/traefik

sudo apt install apache2-utils
read -s -p "Enter dashboard password: " DASHBOARD_PASSWORD
echo
HASH=$(htpasswd -nb admin "$DASHBOARD_PASSWORD" | sed -e s/\\$/\\$\\$/g)
echo "TRAEFIK_DASHBOARD_AUTH=$HASH" | sudo tee /opt/traefik/.env > /dev/null

echo "DOCKER_SOCKET_PROXY_VERSION=" | sudo tee -a /opt/traefik/.env > /dev/null
echo "TRAEFIK_VERSION=" | sudo tee -a /opt/traefik/.env > /dev/null

sudo chmod 600 /opt/traefik/.env

# Let's Encrypt
read -p "Enter DNS provider code (https://go-acme.github.io/lego/dns/index.html): " DNS_PROVIDER
echo "DNS_PROVIDER=$DNS_PROVIDER" | sudo tee -a /opt/traefik/.env > /dev/null

# Add any required env vars for the chosen DNS provider, e.g.
# read -p -s "Enter API token for DNS provider: " <PROVIDER>_API_TOKEN
# echo "<PROVIDER>_API_TOKEN=$<PROVIDER>_API_TOKEN" | sudo tee -a /opt/traefik/.env > /dev/null

read -p "Enter email for ACME notifications: " LETSENCRYPT_EMAIL
echo "LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL" | sudo tee -a /opt/traefik/.env > /dev/null

sudo mkdir -p /opt/traefik/letsencrypt
sudo chmod 700 /opt/traefik/letsencrypt
```

### Public access

- Add a DNS A record for `<service>.<domain>` pointing to the router's public IP
    - Both in a public DNS and in the local DNS (Technitium)
    - Note : don't use wildcard `*.<domain>`, it would override local DNS records for private services
- Forward ports 80 and 443 to the homelab
- Remove the `private-access@file` ipAllowList middleware for services that must be public
- Warning : can be dangerous if running behind a proxy that passes X-Forwarded-For header, like Cloudflare orange cloud
- Additional considerations :
    - Rate limiting (e.g. Traefik middleware)
    - fail2ban
    - Logging and monitoring

## Torrent

- [docker-compose.yml](./services/torrent/docker-compose.yml)
    - [gluetun](https://github.com/qdm12/gluetun) for VPN
    - [qbittorrent](https://www.qbittorrent.org/)
- [Servarr docs](https://wiki.servarr.com/) 
    - [sonarr](https://sonarr.tv)
    - [radarr](https://radarr.video/)
- [TRaSH guides](https://trash-guides.info/)
- Hard links : sonarr/radarr can create hard links of downloaded files so that there is one copy for seeding (in `data/torrents/...`) and one copy for jellyfin (in `data/media/Shows/...`), but without duplicating data. Both copies must be on the same partition

```bash
sudo mkdir -p /opt/torrent/

read -p "Enter VPN service provider: " VPN_SERVICE_PROVIDER
echo
echo "VPN_SERVICE_PROVIDER=$VPN_SERVICE_PROVIDER" | sudo tee /opt/torrent/.env > /dev/null

read -s -p "Enter WireGuard private key for VPN: " WIREGUARD_PRIVATE_KEY
echo
echo "WIREGUARD_PRIVATE_KEY=$WIREGUARD_PRIVATE_KEY" | sudo tee /opt/torrent/.env > /dev/null

read -p "Enter server countries for VPN: " SERVER_COUNTRIES
echo "SERVER_COUNTRIES=$SERVER_COUNTRIES" | sudo tee /opt/torrent/.env > /dev/null

# Any other env vars for gluetun (https://github.com/qdm12/gluetun-wiki/tree/main/setup/providers) depending on the provider
# ...

echo "GLUETUN_VERSION=" | sudo tee -a /opt/torrent/.env > /dev/null
echo "QBITTORRENT_VERSION=" | sudo tee -a /opt/torrent/.env > /dev/null
echo "PROWLARR_VERSION=" | sudo tee -a /opt/torrent/.env > /dev/null
echo "SONARR_VERSION=" | sudo tee -a /opt/torrent/.env > /dev/null
echo "RADARR_VERSION=" | sudo tee -a /opt/torrent/.env > /dev/null
echo "BAZARR_VERSION=" | sudo tee -a /opt/torrent/.env > /dev/null

sudo chmod 600 /opt/torrent/.env
```

### qBittorrent config

- On first launch, show the logs with `sudo docker logs qbittorrent` to get the Web UI credentials. Then go change the password from the UI. This adds the hashed password in the config file (`/opt/torrent/qbittorrent_config/qBittorrent/config/qBittorrent.conf`).
- Enable "Bypass authentication for clients on localhost" for the port update to work
- Enable "Bypass authentication for clients in the following subnets" and add `172.21.0.0/16` (stable IP range for the starrs network) so that sonarr/radarr can connect without authentication
- Set download location to `/data/downloads/torrents` (based on volume mapping in the compose file)
- [Recommended qBittorrent settings](https://trash-guides.info/Downloaders/qBittorrent/Basic-Setup/)

### Prowlarr config

- Create admin account on first launch
- Indexers -> Add Indexer
- Settings -> Apps -> Add Application -> Sonarr / Radarr / ...
    - Prowlarr Server : `http://prowlarr.internal:9696`
    - Sonarr Server : `http://sonarr.internal:8989`
    - API Key : get it from Sonarr Settings -> General -> Security
- Settings -> UI
    - Change date formats
- Settings -> General -> Backups
    - Interval : 1 day

### Sonarr config

- Settings -> Download Client -> Add Download Client -> qBittorrent
    - Host : `gluetun.internal`
    - Port : `8999`
    - Either add authentication bypassing in qbittorrent (recommended) or provide username and password
- Settings -> Media Management
    - Enable "Rename Episodes"
        - Episode / Anime format : `{Series CleanTitle} {(Series Year)} - S{season:00}E{episode:00} {[Quality Full]}{[Custom Formats]}{[Release Group]}`
        - Daily Episode format : `{Series CleanTitle} - {Air-Date} - {Episode CleanTitle} {[Quality Full]}{[Custom Formats]}{[Release Group]}`
        - Series folder : `{Series TitleYear}`
        - Season folder : `Season {season:00}`
    - Enable "Use Hardlinks instead of Copy"
    - Enable "Import Extra Files"
    - Enable "Unmonitor Deleted Episodes"
    - Add Root Folders (Jellyfin libraries)
        - `/data/downloads/media/series/Series`
        - ...
- Settings -> UI
    - Change date formats
- Settings -> General -> Backups
    - Interval : 1 day

### Radarr config

- Settings -> Download Client -> Add Download Client -> qBittorrent
    - Same as Sonarr
- Settings -> Media Management
    - Enable "Rename Movies"
        - Movie format : `{Movie CleanTitle} {(Release Year)} - {Edition Tags }{[Quality Full]}{[Custom Formats]}{[Release Group]}`
        - Movie folder format : `{Movie Title} {(Release Year)}`
    - Enable "Use Hardlinks instead of Copy"
    - Enable "Import Extra Files"
    - Enable "Unmonitor Deleted Movies"
    - Add Root Folders (Jellyfin libraries)
        - `/data/downloads/media/movies/Movies`
        - ...
- Settings -> UI
    - Change date formats
- Settings -> General -> Backups
    - Interval : 1 day

### Bazarr config

- Settings -> General
    - Add authentication
    - Disable automatic updates
- Settings -> Sonarr / Radarr
    - Address : `sonarr.internal` / `radarr.internal`
    - Port : `8989` / `7878`
    - API Key : get it from Sonarr / Radarr Settings -> General -> Security
- Settings -> Providers
    - Add providers (e.g. OpenSubtitles.com, Jimaku.cc)
- Settings -> Subtitles
    - Store alongside media file (for Jellyfin compatibility)
- Settings -> Languages
    - Languages filter : English, French, Japanese, ...
    - Create profiles : EN+JP, EN+FR, EN+FR+JP, ...

## DNS server - Technitium

- [Docker image](https://hub.docker.com/r/technitium/dns-server)
- [docker-compose.yml](./services/technitium/docker-compose.yml)
- Settings
    - General
        - Disable DNSSEC due to NTP issues
            - TODO see how to enable
    - Blocking
        - [Steven Black adware + malware](https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts)
        - [Hagezi Pro](https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.txt)
        - [Blocklistproject SmartTV](https://blocklistproject.github.io/Lists/smart-tv.txt)
    - Forwarders
        - Quad9 Secure (DNS-over-TLS)
- Zones
    - Install Split Horizon app
    - Add primary zone for domain
    - Add APP record for @ and *, see config below

```bash
sudo mkdir -p /opt/technitium

read -s -p "Enter dashboard password: " TECHNITIUM_DNS_ADMIN_PASSWORD
echo
echo "TECHNITIUM_DNS_ADMIN_PASSWORD=$TECHNITIUM_DNS_ADMIN_PASSWORD" | sudo tee /opt/technitium/.env > /dev/null

echo "TECHNITIUM_VERSION=" | sudo tee -a /opt/technitium/.env > /dev/null

sudo chmod 600 /opt/technitium/.env
```

APP record config for SplitHorizon.SimpleAddress :
```json
{
  "192.168.0.0/24": [
    "<homelab-local-ip>"
  ],
  "100.64.0.0/10": [
    "<homelab-tailscale-ip>"
  ],
  "10.0.0.0/24": [
    "10.0.0.1"
  ]
}
```

### Router config

- Router still handles DHCP
- Router advertises the homelab as a DNS server to DHCP clients
    - DNS server 1 : homelab local IP
    - DNS server 2 : fallback (e.g. the router's local IP, which will forward DNS queries based on its own config)

## Jellyfin

- [Docs](https://jellyfin.org/docs/)
- [docker-compose.yml](./services/jellyfin/docker-compose.yml)
- [Hardware selection](https://jellyfin.org/docs/general/administration/hardware-selection)
- [Install directly on a NAS](https://nas.ugreen.com/blogs/how-to/install-jellyfin-setup-step-by-step)
- Configuration
    - Creates libraries
        - `/data/downloads/media/movies/Movies` for movies
        - `/data/downloads/media/series/Series` for series
        - ...
    - Metadata
        - Use TMDB for movies
        - Use TVDB for series (need to install plugin. TMDB is the default and also works but doesn't have movie arcs and recaps as part of the series. Also sonarr uses TVDB)

```bash
sudo mkdir -p /opt/jellyfin

echo "JELLYFIN_VERSION=" | sudo tee /opt/jellyfin/.env > /dev/null

sudo chmod 600 /opt/jellyfin/.env
```

## Nextcloud

- [Nextcloud All-in-One Github](https://github.com/nextcloud/all-in-one)
- [Nextcloud admin docs](https://docs.nextcloud.com/server/latest/admin_manual/contents.html)
- [Nextcloud with reverse proxy guide](https://github.com/nextcloud/all-in-one/blob/main/reverse-proxy.md)
- [docker-compose.yml](./services/nextcloud/docker-compose.yml)
    - There is only one container defined, but it spins up multiple containers because it has access to the docker socket
        - Direct access to the docker socket is a security risk (basically root access to the host). It's theoretically possible to use a [Docker Socket Proxy](https://github.com/Tecnativa/docker-socket-proxy) but it would most likely break things with Nextcloud AIO.
        - Nextcloud's own "Docker Socket Proxy" implementation is only for Apps and ExApps, not for the main Nextcloud container.
        - There are alternative ways to install that don't require the socket (AIO manual install, helm chart, docker rootless), but they have significant drawbacks (auto updates, backups, community containers, etc.)
    - As containers are dynamically created, we cannot use traefik labels, so we must configure it in [dynamic.yml.template](./services/traefik/dynamic.yml.template)
- Hard to change the data directory after install
- `occ` commands can be run with `sudo docker exec --user www-data -it nextcloud-aio-nextcloud php occ <command>`

```bash
sudo mkdir -p /opt/nextcloud
sudo mkdir -p /data/nextcloud/ncdata
sudo chown -R 33:0 /data/nextcloud
sudo chmod -R 750 /data/nextcloud
```

## Manga

- [docker-compose.yml](./services/manga/docker-compose.yml)
- [Mokuro](https://github.com/kha-white/mokuro)
- [Mokuro reader](https://github.com/Gnathonic/mokuro-reader)
    - `rclone serve webdav` for launching a webdav server for sync

```bash
sudo apt install apache2-utils

sudo mkdir -p /opt/manga

sudo mkdir -p /opt/manga/config/mokuro-webdav
sudo chown -R $USER:$USER /opt/manga/config/mokuro-webdav

read -p "Enter mokuro webdav media username: " MOKURO_WEBDAV_USERNAME
echo
read -s -p "Enter mokuro webdav media password: " MOKURO_WEBDAV_PASSWORD
echo
echo "$MOKURO_WEBDAV_PASSWORD" | htpasswd -i -c /opt/manga/config/mokuro-webdav/htpasswd "$MOKURO_WEBDAV_USERNAME"

echo "MOKURO_WEBDAV_VERSION=" | sudo tee /opt/manga/.env > /dev/null
echo "MOKURO_VERSION=" | sudo tee -a /opt/manga/.env > /dev/null

sudo chmod 600 /opt/manga/.env
```

## Gotify

- Notifications server
- [Docs](https://gotify.net/docs/)
- [docker-compose.yml](./services/gotify/docker-compose.yml)
- Change credentials (admin:admin) on first login

```bash
sudo mkdir -p /opt/gotify

echo "GOTIFY_VERSION=" | sudo tee /opt/gotify/.env > /dev/null

sudo chmod 600 /opt/gotify/.env
```

## n8n

- https://docs.n8n.io/hosting
- https://docs.n8n.io/hosting/installation/server-setups/docker-compose
- [docker-compose.yml](./services/n8n/docker-compose.yml)
- Task runners are set as external, i.e. they have their own container
    - [Dockerfile](./services/n8n/Dockerfile)
    - [Runners config](./services/n8n/n8n-task-runners.json)
    - In there we can install extra packages for code blocks (python and javascript)
- Webhooks won't work unless we run with `--tunnel` (which is not safe, don't do it)

```bash
sudo mkdir -p /opt/n8n

read -s -p "Enter n8n runners auth token: " N8N_RUNNERS_AUTH_TOKEN
echo
echo "N8N_RUNNERS_AUTH_TOKEN=$N8N_RUNNERS_AUTH_TOKEN" | sudo tee /opt/n8n/.env > /dev/null

echo "N8N_VERSION=" | sudo tee -a /opt/n8n/.env > /dev/null

sudo chmod 600 /opt/n8n/.env
```

## Jikan REST

- [Project](https://github.com/jikan-me/jikan-rest)
- [Docs](https://docs.api.jikan.moe/)
- [docker-compose.yml](./services/jikan/docker-compose.yml)
- [mongo-init.js](./services/jikan/mongo-init.js)
- [.env.compose](./services/jikan/.env.compose)

```bash
sudo mkdir -p /opt/jikan
sudo mkdir -p /opt/jikan/secrets

read -p "Enter DB username: " JIKAN_DB_USERNAME
echo
echo "$JIKAN_DB_USERNAME" | sudo tee /opt/jikan/secrets/db_username.txt > /dev/null

read -s -p "Enter DB password: " JIKAN_DB_PASSWORD
echo
echo "$JIKAN_DB_PASSWORD" | sudo tee /opt/jikan/secrets/db_password.txt > /dev/null

read -p "Enter DB admin username: " JIKAN_DB_ADMIN_USERNAME
echo
echo "$JIKAN_DB_ADMIN_USERNAME" | sudo tee /opt/jikan/secrets/db_admin_username.txt > /dev/null

read -s -p "Enter DB admin password: " JIKAN_DB_ADMIN_PASSWORD
echo
echo "$JIKAN_DB_ADMIN_PASSWORD" | sudo tee /opt/jikan/secrets/db_admin_password.txt > /dev/null

read -s -p "Enter Redis password: " JIKAN_REDIS_PASSWORD
echo
echo "$JIKAN_REDIS_PASSWORD" | sudo tee /opt/jikan/secrets/redis_password.txt > /dev/null

read -s -p "Enter Typesense API key: " JIKAN_TYPESENSE_API_KEY
echo
echo "$JIKAN_TYPESENSE_API_KEY" | sudo tee /opt/jikan/secrets/typesense_api_key.txt > /dev/null

sudo useradd --no-create-home --shell /usr/sbin/nologin --uid 10001 jikan
sudo chown -R jikan:root /opt/jikan/secrets
sudo chmod 640 /opt/jikan/secrets/*.txt

echo "JIKAN_VERSION=" | sudo tee /opt/jikan/.env > /dev/null
echo "MONGO_VERSION=" | sudo tee -a /opt/jikan/.env > /dev/null
echo "REDIS_VERSION=" | sudo tee -a /opt/jikan/.env > /dev/null
echo "TYPESENSE_VERSION=" | sudo tee -a /opt/jikan/.env > /dev/null

sudo chmod 600 /opt/jikan/.env
```

## Diun

- Notifications for docker image updates
- [Docs](https://crazymax.dev/diun/)
- [docker-compose.yml](./services/diun/docker-compose.yml)

```bash
sudo mkdir -p /opt/diun

read -s -p "Enter gotify app token: " DIUN_NOTIF_GOTIFY_TOKEN
echo
echo "DIUN_NOTIF_GOTIFY_TOKEN=$DIUN_NOTIF_GOTIFY_TOKEN" | sudo tee /opt/diun/.env > /dev/null

echo "DOCKER_SOCKET_PROXY_VERSION=" | sudo tee -a /opt/diun/.env > /dev/null
echo "DIUN_VERSION=" | sudo tee -a /opt/diun/.env > /dev/null

sudo chmod 600 /opt/diun/.env
```

## Homepage

- [Homepage](https://gethomepage.dev/)
- [docker-compose.yml](./services/homepage/docker-compose.yml)
- [settings.yaml](./services/homepage/config/settings.yaml)
- [bookmarks.yaml](./services/homepage/config/bookmarks.yaml)
- [services.yaml.template](./services/homepage/config/services.yaml.template) (generates services.yaml when updated with envsubst mode)
- [widgets.yaml](./services/homepage/config/widgets.yaml)
- [docker.yaml](./services/homepage/config/docker.yaml)

```bash
sudo mkdir -p /opt/homepage/

echo "DOCKER_SOCKET_PROXY_VERSION=" | sudo tee /opt/homepage/.env > /dev/null
echo "HOMEPAGE_VERSION=" | sudo tee -a /opt/homepage/.env > /dev/null

sudo chmod 600 /opt/homepage/.env
```
