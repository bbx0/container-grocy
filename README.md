# Grocy container

Distribution of [Grocy](https://github.com/grocy/grocy) as a Docker image.

- GitHub: [bbx0/container-grocy](https://github.com/bbx0/container-grocy): [Dockerfile](https://github.com/bbx0/container-grocy/blob/main/Dockerfile)
- Docker Hub: [bbx0/grocy](https://hub.docker.com/r/bbx0/grocy)

This is an unofficial community contribution. Please see [grocy-docker](https://github.com/grocy/grocy-docker) for an upstream container image.

## Tags and Variants

The latest patch release of Grocy release is continuously (daily) build and published here as container. The shared tags below link to the latest point release.

**Experimental:** The container automates update handling. In non-container Grocy updates are a simple manual process ([How to update](https://github.com/grocy/grocy/tree/release#how-to-update) and [#2384](https://github.com/grocy/grocy/issues/2384)). This process is automatically executed each time when the container is started. The container does not handle backups for you.

Please subscribe and watch the [Grocy releases](https://github.com/grocy/grocy/releases) for new versions and read the changelog.

The `:latest` tag follows the current version.

| Tag                    | Base image                                                                                                                            | Comment             |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ------------------- |
| ghcr.io/bbx0/grocy:4.4 | [php:8.3-fpm-alpine](https://github.com/docker-library/docs/blob/master/php/README.md#supported-tags-and-respective-dockerfile-links) | **current**         |
| ghcr.io/bbx0/grocy:4.3 | php:8.3-fpm-alpine                                                                                                                    | EOL, please upgrade |
| ghcr.io/bbx0/grocy:4.2 | php:8.3-fpm-alpine                                                                                                                    | EOL, please upgrade |
| ghcr.io/bbx0/grocy:4.1 | php:8.3-fpm-alpine                                                                                                                    | EOL, please upgrade |
| ghcr.io/bbx0/grocy:4.0 | php:8.2-fpm-alpine                                                                                                                    | EOL, please upgrade |
| ghcr.io/bbx0/grocy:3.3 | php:8.1-fpm-alpine                                                                                                                    | EOL, please upgrade |

The `EOL` tags are built on best-effort basis and will eventually be removed after a while.

You may use a pinned version (e.g. `4.1.0`) but be aware only the very latest patch release is part of the automatic rebuild.

## Usage

Please run the Grocy container behind a reverse proxy for SSL and HTTP configuration.

The container requires a `/data` volume and exposes Grocy on port `8080`.

Grocy configuration is supported via environment variables with prefix `GROCY_`. Please see the upstream reference file [config-dist.php](https://github.com/grocy/grocy/blob/release/config-dist.php) for available options.

### Quick Start

```bash
# Run an ephemeral Grocy Demo instance on port 8080
podman run --rm --read-only --publish 8080:8080 -e GROCY_MODE=demo ghcr.io/bbx0/grocy

# Run a Grocy instance on port 8080 with a /data volume and the currency Euro
podman run --rm --read-only --publish 8080:8080 -e GROCY_CURRENCY=EUR -v grocy_data:/data ghcr.io/bbx0/grocy
```

### Example with Caddy as reverse proxy

The following example exposes Grocy at `https://grocy.home.arpa:8443` by using Caddy as reverse proxy with a self-signed certificate and a file size limit of 10 MB for uploads.

```Caddyfile
# Caddyfile

https://grocy.home.arpa {
  request_body {
    max_size 10MB
  }
  encode zstd gzip
  reverse_proxy h2c://app:8080
}
```

```yml
# docker-compose.yml

name: grocy

services:
  app:
    image: ghcr.io/bbx0/grocy
    read_only: true
    volumes:
      - grocy_data:/data
    environment:
      - GROCY_CURRENCY=EUR

  reverse-proxy:
    image: docker.io/library/caddy:2
    ports:
      - "8443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data

volumes:
  grocy_data:
  caddy_data:
```

### Example with a Podman systemd unit (Quadlet)

Run Grocy on `127.0.0.1:8080` as user `grocy` with a bind mount for the `/data` volume.

```bash
# Create user grocy and allow running services in background
sudo useradd -m grocy
sudo loginctl enable-linger grocy

# Login as user grocy
sudo machinectl shell grocy@.host

# As user grocy
mkdir -p ~/.config/containers/systemd
mkdir -p ~/data

cat >.config/containers/systemd/grocy.container <<-'EOF'
[Unit]
Description=Grocy

[Container]
Image=ghcr.io/bbx0/grocy
AutoUpdate=registry
LogDriver=journald
ReadOnly=true

PublishPort=127.0.0.1:8080:8080/tcp
Volume=%h/data:/data

Environment=GROCY_CURRENCY=EUR

[Install]
WantedBy=default.target
EOF

# generate the systemd unit and start Grocy
systemctl --user daemon-reload
systemctl --user start grocy.service
```
