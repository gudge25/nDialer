# nDialer Main Risks and Weaknesses

## Priority summary

The architecture is coherent for a small single-host deployment, but it carries significant security, supportability, and operational risk because it is built on an end-of-life software stack and exposes tightly coupled telephony services.

## Critical and high-priority risks

### 1. End-of-life software stack

The Compose and Docker files use several obsolete components:

- Python 2.7
- Django-era dependencies
- FreeSWITCH 1.4
- Debian Jessie
- Debian Buster
- PostgreSQL 9.6

These versions no longer receive normal security support and will be difficult to support on modern infrastructure. The archived Debian repositories used by the Dockerfiles are also a long-term reproducibility and availability risk.

Recommended action: plan a staged modernization, starting with a supported OS base and a dependency inventory. Upgrade the application runtime and Django first, then address the telephony dependencies.

### 2. ESL listens on all interfaces

The FreeSWITCH container sets:

```yaml
ESL_LISTEN_IP: 0.0.0.0
```

This allows bridge-network application containers to reach the host-networked FreeSWITCH service. However, it also exposes the Event Socket Layer on all host interfaces unless a firewall blocks it.

Recommended action: use a strong unique `ESL_SECRET`, restrict TCP 8021 to trusted source addresses at the host firewall, and avoid exposing it to the public Internet. Consider a private interface or a more isolated network design.

### 3. Default administrator credentials

`.env.example` contains:

```dotenv
DEFAULT_SUPERUSER_USERNAME=admin
DEFAULT_SUPERUSER_PASSWORD=admin123
```

The entrypoint creates or updates this account on startup when enabled. Leaving these values unchanged would create an immediate administrative compromise.

Recommended action: require strong, generated secrets during deployment, disable automatic account creation after bootstrap, and never commit the real `.env` file.

### 4. No TLS in the Compose stack

Nginx listens only on HTTP port 80, and the stack does not provide HTTPS termination.

Recommended action: terminate TLS at a trusted reverse proxy or load balancer, enforce HTTPS, secure cookies, and avoid exposing the admin interface over plain HTTP.

### 5. Host networking weakens isolation

FreeSWITCH uses:

```yaml
network_mode: host
```

This is understandable for SIP/RTP, but it removes normal container network isolation and allows FreeSWITCH to bind directly to host interfaces and ports.

Recommended action: document required host ports, apply host firewall rules, run with the minimum privileges possible, and evaluate a dedicated telephony host or controlled SIP/RTP network design.

## Significant operational and maintainability risks

### 6. Celery root execution and pickle support

The worker sets:

```yaml
C_FORCE_ROOT: "1"
```

The comment indicates this is needed because legacy Celery accepts pickle. Running workers as root while allowing pickle increases the exposure of a malicious or compromised task payload.

Recommended action: migrate task serialization away from pickle, remove the root requirement, create a non-root runtime user, and avoid unsafe task payloads.

### 7. Unpinned external build dependencies

The FreeSWITCH Dockerfile clones or downloads multiple dependencies using shallow clones and direct URLs without immutable commit or checksum verification. Rebuilding later may produce different binaries or fail unexpectedly.

Recommended action: pin every external source to a release or commit SHA, verify checksums for downloaded archives, and maintain a reproducible build process.

### 8. Legacy image coupling

The application image depends on a separately built image tag `newfies-freeswitch:v1.4` to copy the Python ESL bindings. If that image is missing, stale, or built from a different source tree, the application image can fail to build or load incompatible bindings.

Recommended action: publish versioned, digest-pinned artifacts or combine the build pipeline into a controlled release process that records the FreeSWITCH and application compatibility versions.

### 9. Database and media backups are not defined

Named volumes persist state, but they are not backups. Important data is stored in:

- `postgres_data`
- `media_data`
- `freeswitch_recordings`
- `freeswitch_db`

Loss of the host could remove application state, campaign media, and call recordings.

Recommended action: schedule encrypted off-host PostgreSQL backups and separately back up media and recordings. Test restoration regularly.

### 10. Redis persistence may not be a complete recovery strategy

Redis is used for cache, the Celery broker, and result storage. Persisting the Redis volume does not necessarily provide a reliable task recovery strategy, and stale queued tasks may be unsafe after restore.

Recommended action: treat PostgreSQL as the source of truth, define expected Redis recovery behavior, and document how queued work is discarded or rebuilt after recovery.

### 11. Single-instance scheduling assumptions

Only one `celery_beat` instance should normally run. Accidentally scaling it can submit duplicate periodic tasks, which may trigger duplicate campaigns or maintenance jobs.

Recommended action: enforce a singleton Beat deployment and monitor duplicate periodic execution.

### 12. No explicit resource limits

The Compose file does not define CPU, memory, or process limits. Celery autoscaling and telephony workloads could consume host resources and affect the database or web tier.

Recommended action: establish capacity limits, monitor queue depth and call concurrency, and configure resource reservations/limits appropriate for the host.

## Application and data risks

### 13. Shared media volume has multiple writers

`media_data` is mounted read-write by Django, FreeSWITCH, and Nginx. Django uploads files, FreeSWITCH reads audio and may write recordings, and Nginx serves the same volume.

This is convenient but creates risks around file naming, permissions, partial files, retention, and untrusted uploads.

Recommended action: validate and sanitize uploads, use atomic file placement, separate uploaded media from generated recordings where practical, and define retention rules.

### 14. Direct Lua-to-PostgreSQL access bypasses application boundaries

FreeSWITCH Lua code connects directly to PostgreSQL through LuaSQL. This means telephony logic depends directly on database schema and credentials instead of going through a service API or Django layer.

Recommended action: restrict database user permissions, document the schema contract, and validate monitoring/error handling. Consider a more controlled service boundary during modernization.

### 15. Environment secrets are injected broadly

Database credentials and ESL credentials are passed through Compose environment variables. Environment variables are convenient but can appear in process metadata or debugging output depending on tooling.

Recommended action: use a secret-management solution where available, restrict access to Docker/Compose control, rotate credentials frequently, and ensure logs do not print secrets.

### 16. Automatic migrations and fixture loading during web startup

The web entrypoint runs migrations, `collectstatic`, and fixture loading on startup. This can make restarts slow and can create race conditions if multiple web replicas are started simultaneously.

Recommended action: run migrations and fixture/bootstrap operations as explicit deployment jobs, then start application replicas separately.

### 17. No visible production observability layer

The Compose configuration sends logs to container output, but it does not define metrics, centralized logs, alerting, or telephony monitoring.

Recommended action: track PostgreSQL health, Redis health, Celery queue depth, worker failures, ESL connectivity, FreeSWITCH registrations, SIP response codes, active calls, disk usage, and recording volume growth.

## Lower-priority weaknesses

### 18. HTTP port defaults to 8000

This is suitable for local use, but it encourages direct exposure without a proper TLS reverse proxy.

### 19. Long proxy timeouts

Nginx uses 300-second proxy connect and read timeouts. These may be appropriate for some operations but can tie up connections during stalled requests.

### 20. Old dependency installation workarounds

The Dockerfiles contain many compatibility shims for old packages and pinned versions. These workarounds signal a fragile build process that may break when base images or package environments change.

## Recommended remediation order

1. Change all default credentials and generate strong Django and ESL secrets.
2. Place a firewall in front of ESL port 8021 and all SIP/RTP ports.
3. Put HTTPS in front of Nginx and protect the admin interface.
4. Create and test backups for PostgreSQL, media, and recordings.
5. Run Celery as non-root and remove pickle-based task serialization.
6. Pin all external build inputs to immutable versions and record image digests.
7. Add monitoring, queue and call metrics, and service health checks.
8. Separate bootstrap migrations from normal startup.
9. Plan a Python/Django/PostgreSQL/FreeSWITCH modernization path.
10. Reassess the host-networking design as part of the telephony modernization.
