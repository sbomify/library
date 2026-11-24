# sbomify SBOM Library

A collection of Software Bill of Materials (SBOMs) for popular open-source projects, automatically extracted and uploaded to [sbomify](https://sbomify.com) for public browsing.

## Overview

This repository manages SBOM extraction from multiple sources:

- **Docker OCI Attestations** - Extract SBOMs embedded in Docker images via BuildKit attestations
- **Chainguard Images** - Download signed SBOM attestations from Chainguard images via cosign
- **GitHub Releases** - Download SBOMs published as release assets
- **Lockfile Sources** - Download lockfiles for SBOM generation by sbomify

Each app has its own folder with version tracking. When you bump the `version` in `config.yaml`, only that app's SBOM is rebuilt and uploaded - not the entire repository.

**Note:** Each version only needs to be processed once. Once an SBOM is uploaded to sbomify, it is permanently stored there. There is no need to re-process the same version.

## Projects

Each SBOM is discoverable via the [Transparency Exchange API (TEA)](https://tc54.org/tea/) using the TEI identifiers listed below. Each TEI is a TEA 1.0.0 `tei://` URI that carries the project's PURL in Base64URL. Resolve one with `tea-cli discover <TEI>` from [libtea](https://github.com/sbomify/py-libtea).

### Operating Systems

| Project | Source | TEI | Job |
|---------|--------|-----|-----|
| [Alpine Linux](https://hub.docker.com/_/alpine) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2FscGluZQ` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-alpine.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-alpine.yml) |
| [Amazon Linux](https://hub.docker.com/_/amazonlinux) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2FtYXpvbmxpbnV4` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-amazonlinux.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-amazonlinux.yml) |
| [Debian](https://hub.docker.com/_/debian) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2RlYmlhbg` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-debian.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-debian.yml) |
| [Fedora](https://hub.docker.com/_/fedora) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2ZlZG9yYQ` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-fedora.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-fedora.yml) |
| [Oracle Linux](https://hub.docker.com/_/oraclelinux) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L29yYWNsZWxpbnV4` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-oraclelinux.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-oraclelinux.yml) |
| [Rocky Linux](https://hub.docker.com/_/rockylinux) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3JvY2t5bGludXg` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-rockylinux.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-rockylinux.yml) |
| [Ubuntu](https://hub.docker.com/_/ubuntu) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3VidW50dQ` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-ubuntu.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-ubuntu.yml) |

### Languages & Runtimes

| Project | Source | TEI | Job |
|---------|--------|-----|-----|
| [Eclipse Temurin](https://hub.docker.com/_/eclipse-temurin) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2VjbGlwc2UtdGVtdXJpbg` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-eclipse-temurin.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-eclipse-temurin.yml) |
| [Elixir](https://hub.docker.com/_/elixir) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2VsaXhpcg` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-elixir.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-elixir.yml) |
| [Erlang](https://hub.docker.com/_/erlang) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2VybGFuZw` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-erlang.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-erlang.yml) |
| [Go](https://hub.docker.com/_/golang) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2dvbGFuZw` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-golang.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-golang.yml) |
| [Haskell (GHC)](https://hub.docker.com/_/haskell) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2hhc2tlbGw` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-haskell.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-haskell.yml) |
| [Julia](https://hub.docker.com/_/julia) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2p1bGlh` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-julia.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-julia.yml) |
| [Node.js](https://hub.docker.com/_/node) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L25vZGU` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-node.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-node.yml) |
| [Perl](https://hub.docker.com/_/perl) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3Blcmw` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-perl.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-perl.yml) |
| [PHP](https://hub.docker.com/_/php) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3BocA` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-php.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-php.yml) |
| [Python](https://hub.docker.com/_/python) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3B5dGhvbg` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-python.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-python.yml) |
| [R](https://hub.docker.com/_/r-base) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3ItYmFzZQ` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-r-base.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-r-base.yml) |
| [Ruby](https://hub.docker.com/_/ruby) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3J1Ynk` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-ruby.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-ruby.yml) |
| [Rust](https://hub.docker.com/_/rust) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3J1c3Q` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-rust.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-rust.yml) |
| [Swift](https://hub.docker.com/_/swift) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3N3aWZ0` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-swift.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-swift.yml) |

### Databases

| Project | Source | TEI | Job |
|---------|--------|-----|-----|
| [Apache Cassandra](https://hub.docker.com/_/cassandra) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2Nhc3NhbmRyYQ` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-cassandra.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-cassandra.yml) |
| [InfluxDB](https://hub.docker.com/_/influxdb) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2luZmx1eGRi` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-influxdb.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-influxdb.yml) |
| [MariaDB](https://hub.docker.com/_/mariadb) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L21hcmlhZGI` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-mariadb.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-mariadb.yml) |
| [Memcached](https://hub.docker.com/_/memcached) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L21lbWNhY2hlZA` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-memcached.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-memcached.yml) |
| [MongoDB](https://hub.docker.com/_/mongo) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L21vbmdv` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-mongo.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-mongo.yml) |
| [Mongo Express](https://hub.docker.com/_/mongo-express) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L21vbmdvLWV4cHJlc3M` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-mongo-express.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-mongo-express.yml) |
| [MySQL](https://hub.docker.com/_/mysql) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L215c3Fs` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-mysql.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-mysql.yml) |
| [Neo4j](https://hub.docker.com/_/neo4j) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L25lbzRq` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-neo4j.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-neo4j.yml) |
| [PostgreSQL](https://hub.docker.com/_/postgres) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3Bvc3RncmVz` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-postgres.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-postgres.yml) |
| [Redis](https://hub.docker.com/_/redis) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3JlZGlz` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-redis.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-redis.yml) |
| [Apache Solr](https://hub.docker.com/_/solr) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3NvbHI` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-solr.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-solr.yml) |

### Web & Application Servers

| Project | Source | TEI | Job |
|---------|--------|-----|-----|
| [Apache HTTP Server](https://hub.docker.com/_/httpd) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2h0dHBk` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-httpd.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-httpd.yml) |
| [Apache Tomcat](https://hub.docker.com/_/tomcat) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3RvbWNhdA` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-tomcat.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-tomcat.yml) |
| [Caddy](https://github.com/caddyserver/caddy) | GitHub Release | `tei://library.sbomify.com/purl/cGtnOmdpdGh1Yi9jYWRkeXNlcnZlci9jYWRkeQ` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-caddy.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-caddy.yml) |
| [HAProxy](https://hub.docker.com/_/haproxy) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2hhcHJveHk` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-haproxy.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-haproxy.yml) |
| [Kong Gateway](https://hub.docker.com/_/kong) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2tvbmc` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-kong.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-kong.yml) |
| [Nginx](https://images.chainguard.dev/directory/image/nginx/overview) | Chainguard | `tei://library.sbomify.com/purl/cGtnOm9jaS9jZ3IuZGV2L2NoYWluZ3VhcmQvbmdpbng` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-nginx.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-nginx.yml) |
| [Traefik](https://hub.docker.com/_/traefik) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3RyYWVmaWs` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-traefik.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-traefik.yml) |

### Applications & Platforms

| Project | Source | TEI | Job |
|---------|--------|-----|-----|
| [Drupal](https://hub.docker.com/_/drupal) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2RydXBhbA` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-drupal.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-drupal.yml) |
| [Ghost](https://hub.docker.com/_/ghost) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2dob3N0` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-ghost.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-ghost.yml) |
| [Keycloak](https://github.com/keycloak/keycloak) | Lockfile | `tei://library.sbomify.com/purl/cGtnOmdpdGh1Yi9rZXljbG9hay9rZXljbG9haw` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-keycloak.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-keycloak.yml) |
| [Keycloak JS](https://github.com/keycloak/keycloak) | Lockfile | `tei://library.sbomify.com/purl/cGtnOmdpdGh1Yi9rZXljbG9hay9rZXljbG9haw` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-keycloak-js.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-keycloak-js.yml) |
| [SonarQube](https://hub.docker.com/_/sonarqube) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3NvbmFycXViZQ` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-sonarqube.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-sonarqube.yml) |
| [WordPress](https://hub.docker.com/_/wordpress) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3dvcmRwcmVzcw` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-wordpress.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-wordpress.yml) |

### Build Tools

| Project | Source | TEI | Job |
|---------|--------|-----|-----|
| [Gradle](https://hub.docker.com/_/gradle) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2dyYWRsZQ` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-gradle.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-gradle.yml) |
| [Apache Maven](https://hub.docker.com/_/maven) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L21hdmVu` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-maven.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-maven.yml) |

### Infrastructure & Messaging

| Project | Source | TEI | Job |
|---------|--------|-----|-----|
| [Bash](https://hub.docker.com/_/bash) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2Jhc2g` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-bash.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-bash.yml) |
| [Docker Registry](https://hub.docker.com/_/registry) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3JlZ2lzdHJ5` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-registry.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-registry.yml) |
| [Eclipse Mosquitto](https://hub.docker.com/_/eclipse-mosquitto) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L2VjbGlwc2UtbW9zcXVpdHRv` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-eclipse-mosquitto.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-eclipse-mosquitto.yml) |
| [RabbitMQ](https://hub.docker.com/_/rabbitmq) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3JhYmJpdG1x` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-rabbitmq.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-rabbitmq.yml) |
| [Telegraf](https://hub.docker.com/_/telegraf) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3RlbGVncmFm` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-telegraf.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-telegraf.yml) |
| [Apache ZooKeeper](https://hub.docker.com/_/zookeeper) | Docker | `tei://library.sbomify.com/purl/cGtnOmRvY2tlci9saWJyYXJ5L3pvb2tlZXBlcg` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-zookeeper.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-zookeeper.yml) |

### Security & SBOM Tools

| Project | Source | TEI | Job |
|---------|--------|-----|-----|
| [Dependency Track](https://github.com/DependencyTrack/dependency-track) | GitHub Release | `tei://library.sbomify.com/purl/cGtnOmdpdGh1Yi9EZXBlbmRlbmN5VHJhY2svZGVwZW5kZW5jeS10cmFjaw` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-dependency-track.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-dependency-track.yml) |
| [Dependency Track Frontend](https://github.com/DependencyTrack/frontend) | GitHub Release | `tei://library.sbomify.com/purl/cGtnOmdpdGh1Yi9EZXBlbmRlbmN5VHJhY2svZnJvbnRlbmQ` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-dependency-track-frontend.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-dependency-track-frontend.yml) |
| [OSV Scanner](https://github.com/google/osv-scanner) | Lockfile | `tei://library.sbomify.com/purl/cGtnOmdpdGh1Yi9nb29nbGUvb3N2LXNjYW5uZXI` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-osv-scanner.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-osv-scanner.yml) |
| [Syft](https://github.com/anchore/syft) | Lockfile | `tei://library.sbomify.com/purl/cGtnOmdpdGh1Yi9hbmNob3JlL3N5ZnQ` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-syft.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-syft.yml) |
| [Trivy](https://github.com/aquasecurity/trivy) | GitHub Release | `tei://library.sbomify.com/purl/cGtnOmdpdGh1Yi9hcXVhc2VjdXJpdHkvdHJpdnk` | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-trivy.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-trivy.yml) |

## Directory Structure

```
.
├── .github/
│   └── workflows/
│       ├── sbom-builder.yml          # Reusable workflow (main logic)
│       ├── _sbom-template.yml        # Template for new app workflows
│       └── sbom-<app-name>.yml       # Per-app workflow
├── apps/
│   └── <app-name>/                   # Example app
│       └── config.yaml               # App configuration (includes version)
├── scripts/
│   ├── fetch-sbom.sh                 # Main entry point
│   ├── check-updates.sh              # Check for upstream version updates
│   ├── install-tools.sh              # Install crane/cosign from sbomify/sbom-tools
│   ├── lib/
│   │   └── common.sh                 # Shared utilities
│   └── sources/
│       ├── docker-attestation.sh     # Docker extraction
│       ├── github-release.sh         # GitHub release download
│       └── lockfile-generator.sh     # Lockfile download
├── .sbom-tools-version               # Pinned sbomify/sbom-tools release
└── README.md
```

## Quick Start

### Adding a New App

1. **Create the app folder:**
   ```bash
   mkdir -p apps/myapp
   ```

2. **Create `apps/myapp/config.yaml`:**
   ```yaml
   name: myapp
   version: "1.0.0"  # Must be valid semver
   format: cyclonedx  # or spdx

   source:
     type: docker  # or github_release, lockfile, chainguard
     image: "library/myapp"
     registry: "docker.io"

   sbomify:
     component_id: "your-component-id"
     component_name: "My App"
   ```

   Valid version formats: `1.2.3`, `1.2.3-rc1`, `1.2.3-alpha.1+build`. **Note:** `latest` is not allowed.

3. **Create the workflow file:**
   ```bash
   cp .github/workflows/_sbom-template.yml .github/workflows/sbom-myapp.yml
   # Edit the file and replace 'example-app' with 'myapp'
   ```

4. **Commit and push:**
   ```bash
   git add apps/myapp .github/workflows/sbom-myapp.yml
   git commit -m "Add myapp SBOM"
   git push
   ```

### Bumping a Version

Simply update the `version` field in `config.yaml`:

```yaml
# apps/nginx/config.yaml
name: nginx
version: "1.26.0"  # Update this line
...
```

```bash
git add apps/nginx/config.yaml
git commit -m "Bump nginx to 1.26.0"
git push
```

Merging the bump to `master` runs that app's workflow (`sbom-nginx.yml`), which fetches the SBOM and uploads it to
sbomify. Only apps whose `config.yaml` changed are rebuilt. Locally you can run the same pipeline without the
upload:

```bash
./scripts/run.sh nginx --dry-run
```

Most bumps don't need to be made by hand. `./scripts/check-updates.sh --verify --update` finds and applies them
(see [Checking for Updates](#checking-for-updates)), and `.claude/skills/update-library/SKILL.md` describes the
full maintenance routine.

## Configuration Reference

### App Configuration (`config.yaml`)

```yaml
# Required: App name (should match folder name)
name: nginx

# Required: Version (must be valid semver)
version: "1.25.4"

# Required: SBOM format
format: cyclonedx  # cyclonedx | spdx

# Required: Source configuration
source:
  type: docker  # docker | github_release | lockfile | chainguard

  # ... source-specific options (see below)

# Required for upload: sbomify configuration
sbomify:
  component_id: "abc123-def456"
  component_name: "Nginx"
```

### Source Types

#### Docker OCI Attestations

Extract SBOMs from Docker image attestations (requires images built with BuildKit SBOM support):

```yaml
source:
  type: docker
  image: "library/nginx"          # Image name (required)
  registry: "docker.io"           # Registry (default: docker.io)
  platform: "linux/amd64"         # Platform (default: linux/amd64)
```

#### Chainguard Images

Download signed SBOM attestations from Chainguard images using cosign:

```yaml
source:
  type: chainguard
  image: "nginx"                  # Chainguard image name (required)
  registry: "cgr.dev/chainguard"  # Registry (default: cgr.dev/chainguard)
  platform: "linux/amd64"         # Platform (default: linux/amd64)
```

Note: Chainguard images use SPDX format by default. Set `format: spdx` in your config.

#### GitHub Release

Download SBOMs from GitHub release assets:

```yaml
source:
  type: github_release
  repo: "owner/repo"              # GitHub repository (required)
  asset: "bom.json"               # Asset filename (required, supports ${version})
  tag_prefix: "v"                 # Tag prefix (default: "")
  tag_suffix: ""                  # Tag suffix (default: "")
```

The `asset` field supports `${version}` substitution for projects that include the version in the asset filename:

```yaml
source:
  type: github_release
  repo: "caddyserver/caddy"
  asset: "caddy_${version}_linux_amd64.sbom"  # Becomes caddy_2.10.1_linux_amd64.sbom
  tag_prefix: "v"
```

#### Lockfile Sources

Download lockfiles for SBOM generation by the sbomify GitHub Action:

```yaml
source:
  type: lockfile
  repo: "owner/repo"              # GitHub repository (required)
  lockfile: "package-lock.json"   # Path to lockfile (required)
  tag_prefix: "v"                 # Tag prefix
  clone: false                    # Shallow clone repo instead of downloading lockfile
```

For projects with complex dependency structures (e.g., Maven multi-module projects), set `clone: true` to perform a shallow clone of the entire repository:

```yaml
source:
  type: lockfile
  repo: "keycloak/keycloak"
  lockfile: "pom.xml"
  clone: true                     # Clone repo for full dependency resolution
```

Note: SBOM generation from lockfiles is handled automatically by the sbomify GitHub Action.

## Local Development

### Prerequisites

- **bash** 4.0+
- **jq** - JSON processor
- **yq** - YAML processor

- **gh** - GitHub CLI, authenticated (used to download and verify the tools below)

For Docker and Chainguard sources, **crane** and **cosign** come from
[sbomify/sbom-tools](https://github.com/sbomify/sbom-tools), the same builds sbomify-action uses:

```bash
./scripts/install-tools.sh
```

This downloads the `sigstore` bundle for the release pinned in `.sbom-tools-version`, verifies its build provenance
with `gh attestation verify`, and unpacks it into `.tools/bin`. The scripts in `scripts/` put `.tools/bin` on `PATH`
themselves, so there is nothing else to configure. To use the tools in your own shell, run
`eval "$(./scripts/install-tools.sh --env)"`. CI runs the same script.

For lockfile sources:
- No additional tools required (SBOM generation handled by sbomify GitHub Action)

### Running Locally

```bash
# Fetch SBOM for an app
./scripts/fetch-sbom.sh nginx

# Fetch with verbose output
./scripts/fetch-sbom.sh nginx --verbose

# Dry-run mode (no actual fetching)
./scripts/fetch-sbom.sh nginx --dry-run
```

### Checking for Updates

```bash
# Check all apps for upstream version updates
./scripts/check-updates.sh

# Only check specific source type
./scripts/check-updates.sh --type docker

# Check specific apps
./scripts/check-updates.sh --app redis,trivy

# Auto-update config.yaml files
./scripts/check-updates.sh --update

# Preview updates without writing
./scripts/check-updates.sh --update --dry-run

# JSON output (for CI)
./scripts/check-updates.sh --json

# Only report/apply versions whose SBOM actually exists upstream
# (docker attestation, release asset, or lockfile at the tag)
./scripts/check-updates.sh --verify --update

# Docker lookups go through mirror.gcr.io by default (fast, no Docker Hub rate limit).
# Query Docker Hub directly instead (e.g. to catch tags the mirror hasn't picked up yet):
DOCKER_HUB_MIRROR= ./scripts/check-updates.sh --verify
```

How the latest version is picked for Docker sources:

1. Read the `org.opencontainers.image.version` annotation from the `:latest` tag.
2. If it is less specific than the tracked version (`26` vs `25.0.0`, `1-trixie` vs `1.93.1`), or is a codename
   (`trixie`), or the image has no `:latest` tag at all, list the tags and pick the highest one with the same shape as
   the tracked version. When the annotation is numeric, the pick stays within that release line, so `26` resolves to
   `26.x.y`.

Exit codes: `0` all current, `1` updates available (including unverified), `2` at least one error.

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LOG_LEVEL` | Logging level: DEBUG, INFO, WARN, ERROR | `INFO` |
| `DRY_RUN` | Run in dry-run mode | `false` |
| `GH_TOKEN` | GitHub token for API access | - |
| `DOCKER_HUB_MIRROR` | Read-only Docker Hub mirror used by `check-updates.sh`; empty = Docker Hub directly | `mirror.gcr.io` |

## GitHub Actions

### Authentication (OIDC)

No secrets are used. Uploads authenticate to sbomify with OIDC trusted publishing: the workflow (with
`permissions: id-token: write`) exchanges a GitHub-issued token for a short-lived sbomify token scoped to one
component. Every component in `apps/*/config.yaml` needs an OIDC binding for `sbomify/library` in sbomify
(Component → Settings → Trusted Publishing). Without one, the upload fails with a 403.

Because OIDC only exists on GitHub Actions, uploads only happen there. `run.sh` without `--dry-run` refuses to run
anywhere else.

### Manual Trigger

Each app workflow can be manually triggered from the Actions tab with optional dry-run mode.

### Workflow Structure

- **Per-app workflows** (`sbom-<app-name>.yml`) - Thin wrappers that trigger on config.yaml changes
- **Reusable workflow** (`sbom-builder.yml`) - Contains all the build logic
- **Template** (`_sbom-template.yml`) - Copy this to create new app workflows

This design ensures:
1. Only the changed app is rebuilt (via path filters on config.yaml)
2. Build logic is centralized and maintainable
3. New apps just need a simple workflow file

## Contributing

1. Fork the repository
2. Add your app following the Quick Start guide
3. Test locally with `./scripts/fetch-sbom.sh <app-name>`
4. Submit a pull request

## License

See [LICENSE](LICENSE) for details.
