# Archive

Unused configs and services.

## Tailscale

- [Docs](https://tailscale.com/kb/)
- Install on all devices (laptop, phone, homelab) and connect
    - [Arch wiki - Tailscale](https://wiki.archlinux.org/title/Tailscale)
        - Follow install instructions. Tips and tricks section (unmanaging tailscale0) doesn't seem to be necessary.
        - Use [systemd-resolved](https://wiki.archlinux.org/title/Systemd-resolved) if not already done, otherwise tailscale DNS won't be set when switching networks.
        - Disable "DNS over HTTPS" in Firefox to avoid conflicts with systemd-resolved.
    - Android : from Play Store
    - Homelab : `curl -fsSL https://tailscale.com/install.sh | sh`
- [Admin console](https://login.tailscale.com/admin/)
    - DNS settings
        - If internal DNS is installed : add the homelab IP address (in tailnet) as a global nameserver. This way, all devices using tailscale will use it for DNS resolution. Add a second global server as a fallback, like Quad9

### Options for exposing services to the tailnet

1. `tailscale serve --https=<new port> --bg <service port>` -> `https://<device>.<tailscale-domain>:<new port>`
2. `tailscale serve --set-path=/<service> --bg <service port>` -> `https://<device>.<tailscale-domain>/<service>`, but it often breaks apps that expect to be at the root path.
3. `tailscale serve --service=svc:<service> --https=443 127.0.0.1:8096` -> `https://<service>.<tailscale-domain>` (needs [Tailscale Services](https://tailscale.com/kb/1552/tailscale-services))
4. Tailscale docker container alongside each service, that handles networking, [guide](https://tailscale.com/blog/docker-tailscale-guide) (very annoying to setup and maintain)
5. https://almeidapaulopt.github.io/tsdproxy/, simpler but still in development
6. Traefik proxy that handles `https://<device>.<tailscale-domain>:<port>` with a different port entrypoint for each service. No real advantage over option 1.
7. Traefik proxy that handles `https://<device>.<tailscale-domain>/<service>`, same issues as option 2.
8. Traefik proxy that handles `https://<service>.<domain>`. MagicDNS disabled. Technitium configured to resolve `*.<domain>` with the homelab's tailnet IP for requests originating from the tailnet.

### Troubleshooting

- It happens that when connected to Tailscale with global DNS enabled as the pi-hole, `*.<domain>` suddenly can't be resolved. Flushing the cache or reconnecting to tailscale seems to solve it temporarily.
    - Added local DNS records on Pi-hole for ipv6, pointing to an unspecified address (e.g. `*.<domain>` -> `::`). This way AAAA queries do not result in NXDOMAIN, which could poison the cache
        - It's part of the solution but it still breaks. Note that we still get SOA responses for HTTPS queries because we can't set local records for this on the pi-hole, but it doesn't seem to be an issue.
    - If Tailscale somehow makes additional DNS queries to other servers, disabling MagicDNS or having only one global nameserver may help
        - Deleting the second global server doesn't help
        - Disabling MagicDNS seems to help
    - Still happens, here's what temporarily restores it :
        - `resolvectl query --cache=false foobar.<domain>`
        - `sudo tailscale down && sudo tailscale up`

## Pi-hole

- [Docs](https://docs.pi-hole.net)
- [docker-compose.yml](./services/pihole/docker-compose.yml)
- Pi-hole config on the dashboard :
    - Upstream DNS : set to "Quad9 (filtered, DNSSEC)"
    - Check "Never forward non-FQDN queries" and "Never forward reverse lookups for private IP ranges"

```bash
sudo mkdir -p /opt/pihole

read -s -p "Enter dashboard password: " PIHOLE_PASSWORD
echo
echo "PIHOLE_PASSWORD=$PIHOLE_PASSWORD" | sudo tee /opt/pihole/.env > /dev/null

echo "PIHOLE_VERSION=" | sudo tee -a /opt/pihole/.env > /dev/null

sudo chmod 600 /opt/pihole/.env
```

## Stirling-PDF

- https://docs.stirlingpdf.com/
- [docker-compose.yml](./services/stirling-pdf/docker-compose.yml)
- Initial login: username `admin`, password `stirling`
    - Change on first login

```bash
sudo mkdir -p /opt/stirling-pdf

echo "STIRLING_PDF_VERSION=" | sudo tee /opt/stirling-pdf/.env > /dev/null

sudo chmod 600 /opt/stirling-pdf/.env
```

## Jikan REST

- [Project](https://github.com/jikan-me/jikan-rest)
- [Docs](https://docs.api.jikan.moe/)
- [docker-compose.yml](./services/jikan/docker-compose.yml)
- [mongo-init.js](./services/jikan/mongo-init.js)

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
sudo chmod 750 /opt/jikan/secrets
sudo chmod 644 /opt/jikan/secrets/*.txt

echo "JIKAN_VERSION=" | sudo tee /opt/jikan/.env > /dev/null
echo "MONGO_VERSION=" | sudo tee -a /opt/jikan/.env > /dev/null
echo "REDIS_VERSION=" | sudo tee -a /opt/jikan/.env > /dev/null
echo "TYPESENSE_VERSION=" | sudo tee -a /opt/jikan/.env > /dev/null

sudo chmod 600 /opt/jikan/.env
```
