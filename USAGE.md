# Usage

## Connection

### From a Linux client

Example `/etc/hosts` for the client :
```
<local-ip>	<host>.internal
10.0.0.1	<host>-vpn.internal
10.0.1.1	<host>-vpn-boot.internal
```

- SSH
    - `ssh <host>.internal` (local)
    - `ssh <host>-vpn.internal` (VPN)
- Dropbear (during boot)
    - `ssh -p 2222 root@<host>.internal` (local)
    - `ssh -p 2222 root@<host>-vpn-boot.internal` (VPN)

## Scripts

| Script | Description | Usage |
|--------|-------------|-------|
| [homelab.sh](./scripts/homelab.sh) | Main entry point with tampering prevention | `homelab <script-name> [args...]` |
| [pull.sh](./scripts/pull.sh) | Pull changes | `homelab pull` |
| [services.sh](./scripts/services.sh) | Manage docker services | `homelab services <start\|stop\|update> [stack-name] [container-name]` |
| [dotfiles-update.sh](./scripts/dotfiles-update.sh) | Manage dotfiles | `homelab dotfiles-update [files...]` |
| [mokuro.sh](./scripts/mokuro.sh) | Run mokuro in background | `homelab mokuro; tail -f /var/log/mokuro.log` |
| [jikan.sh](./scripts/jikan.sh) | Run jikan indexers in background | `homelab jikan <execute-indexers\|index-incrementally>; tail -f /var/log/jikan.log` |
| [backup-services.sh](./scripts/backup-services.sh) | Backup docker volumes with Borg | `homelab backup-services` |
| [backup-media.sh](./scripts/backup-media.sh) | Backup media to the offline HDD, handling mounting and unmounting of the backup drive | `homelab backup-media` |
| [borg.sh](./scripts/borg.sh) | Wrapper for Borg with environment variables | `homelab borg <args>` |
| [storage-mount.sh](./scripts/storage-mount.sh) | Mount external HDD | `homelab storage-mount` |
| [storage-umount.sh](./scripts/storage-umount.sh) | Unmount external HDD | `homelab storage-umount` |
