<!-- markdownlint-configure-file { "no-inline-html": { "allowed_elements": [ "br" ] } } -->
# Grocy container

[![docker](https://img.shields.io/badge/Docker%20Hub-1D63ED?logo=docker&logoColor=white)](https://hub.docker.com/r/bbx0/grocy) [![GitHub](https://img.shields.io/badge/GitHub-black?logo=github&logoColor=white)](https://github.com/bbx0/container-grocy)

A distribution of [Grocy](https://github.com/grocy/grocy) based on the [Docker Official Images](https://github.com/docker-library/official-images#what-are-official-images) for [PHP](https://hub.docker.com/_/php).

This is a user contribution to the Grocy Community.

## Tags and Variants

The latest [Grocy release](https://github.com/grocy/grocy/releases) is continuously built and published as shared tag using a [GitHub workflow](https://github.com/bbx0/container-grocy/actions/workflows/main.yaml).

The `:latest` tag follows the current version. Please see the [Grocy releases](https://github.com/grocy/grocy/releases) for a changelog of new versions.

| Tag                    | Comment             |
| ---------------------- | ------------------- |
| [ghcr.io/bbx0/grocy:latest](https://github.com/bbx0/container-grocy/blob/main/Dockerfile)<br>[ghcr.io/bbx0/grocy:4.5](https://github.com/bbx0/container-grocy/blob/main/Dockerfile) | **current**         |
| [ghcr.io/bbx0/grocy:4.4](https://github.com/bbx0/container-grocy/blob/main/Dockerfile) | EOL, please upgrade |
| [ghcr.io/bbx0/grocy:4.3](https://github.com/bbx0/container-grocy/blob/main/Dockerfile) | EOL, please upgrade |

The container images are built multi-platform for: `linux/amd64` and `linux/arm64`.

The `EOL` tags are built on best-effort basis and will eventually be removed.

## Usage

The container requires a `/data` volume and exposes Grocy on port `8080`.

The default login is `admin:admin`, please change it!

### Quick Start

```yaml
# compose.yaml
# usage: 
#  - docker compose up
#  - docker-compose run --no-TTY --rm app
name: grocy
services:
  app:
    image: bbx0/grocy
    read_only: true
    ports:
      - "127.0.0.1:8080:8080" # Listen on http://127.0.0.1:8080
    environment:
      - GROCY_CURRENCY=EUR    # Set currency to Euro
    volumes:
      - ./data:/data          # The Grocy data directory
```

```bash
# Run a Grocy instance on port 8080 with a /data volume and the currency Euro
docker run --rm --read-only --publish 8080:8080 -e GROCY_CURRENCY=EUR -v ./data:/data bbx0/grocy

# Run an ephemeral Grocy Demo instance on port 8080
docker run --rm --read-only --publish 8080:8080 -e GROCY_MODE=demo bbx0/grocy
```

### Configuration

Configuration is supported using **Environment Variables** with the prefix `GROCY_`. Please see [config-dist.php](https://github.com/grocy/grocy/blob/release/config-dist.php) for the available options, e.g. use `GROCY_CURRENCY=EUR` to set the currency to Euro.

Please run the Grocy container behind a reverse proxy for SSL and HTTP configuration.

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
# compose.yml
name: grocy
services:
  app:
    image: bbx0/grocy
    read_only: true
    volumes:
      - grocy_data:/data
    environment:
      - GROCY_CURRENCY=EUR
  reverse-proxy:
    image: caddy:2
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
