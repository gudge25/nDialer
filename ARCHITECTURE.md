# nDialer Architecture Findings

## Overview

`nDialer` is a single-host, multi-container cloud dialer based on the Newfies-Dialer application. The stack combines a Django/Python application, Celery background processing, PostgreSQL, Redis, Nginx, and FreeSWITCH telephony services.

## High-level topology

```text
                         SIP / RTP
                            │
                    ┌───────▼────────┐
                    │   FreeSWITCH   │
                    │ host networking│
                    │ SIP + telephony│
                    └───────┬────────┘
                            │ ESL :8021
                            │
┌──────────────┐     ┌──────▼──────┐     ┌──────────────┐
│    nginx     │────▶│    web      │────▶│ PostgreSQL   │
│ public HTTP  │     │ Gunicorn/   │     │ application  │
│ static/media │     │ Django      │     └──────────────┘
└──────────────┘     └──────┬──────┘
                            │
                    ┌───────▼────────┐
                    │     Redis      │
                    │ cache + Celery │
                    │ broker/results │
                    └───────┬────────┘
                            │
                 ┌──────────▼──────────┐
                 │ Celery worker/beat  │
                 │ async and scheduled │
                 │ dialer jobs         │
                 └─────────────────────┘
```

## Compose services

### `db` — PostgreSQL

- Uses PostgreSQL 9.6.
- Stores users, tenants, campaigns, phonebooks, subscribers, gateways, call records, configuration, and reporting data.
- Persists data in the `postgres_data` named volume.
- Publishes `127.0.0.1:5432` on the host so the host-networked FreeSWITCH container can connect to PostgreSQL.
- Provides a `pg_isready` health check.

Application containers use the Compose DNS name `db:5432`; FreeSWITCH uses `127.0.0.1:5432`.

### `redis` — cache and Celery transport

- Uses Redis 6 Alpine.
- Acts as the Django cache, Celery broker, and Celery result backend.
- Persists data in `redis_data`.
- Provides a `redis-cli ping` health check.

### `web` — Django/Gunicorn application

- Runs `newfies_dialer.wsgi:application` under Gunicorn.
- Provides the customer frontend, admin interface, APIs, campaign configuration, and reporting.
- Listens internally on port 8000.
- Shares the application image and volumes with the Celery services.

### `celery_worker` — asynchronous execution

- Consumes background tasks from Redis.
- Uses autoscaling between 2 and 10 worker processes.
- Handles asynchronous campaign, scheduling, call, reporting, and related tasks.
- Connects to FreeSWITCH through the Event Socket Layer (ESL) to originate or control calls.

### `celery_beat` — periodic scheduling

- Publishes scheduled tasks to Redis for Celery workers.
- Should normally run as a single instance to avoid duplicate periodic task submission.

### `nginx` — HTTP ingress and static-file server

- Exposes the configurable host HTTP port, defaulting to 8000.
- Proxies dynamic requests to `web:8000`.
- Serves `/static/` from `static_data`.
- Serves `/usermedia/` from `media_data`.

### `freeswitch` — telephony engine

- Compiles and runs FreeSWITCH v1.4.
- Handles SIP signaling, RTP media, outbound calls, IVR, audio playback, TTS, recordings, and gateway/trunk connectivity.
- Runs with `network_mode: host` so SIP and RTP can use real host ports without Docker bridge/NAT complexity.
- Runs the project’s Lua call-flow code and connects directly to PostgreSQL through LuaSQL.
- Mounts gateway configuration from `freeswitch-conf/sip_profiles/external`.

## Control and call flow

1. A user reaches the system through Nginx.
2. Nginx proxies dynamic requests to Django/Gunicorn.
3. Django stores campaign and subscriber configuration in PostgreSQL.
4. Celery Beat schedules campaign-related tasks.
5. Celery workers consume tasks from Redis.
6. A worker connects to FreeSWITCH over ESL at port 8021.
7. FreeSWITCH selects a SIP gateway and places the call.
8. FreeSWITCH executes Lua call-flow logic, reading campaign state and audio from shared storage.
9. Recordings and call results are stored or processed for reporting.

## Networking model

Most services use the default Docker Compose bridge network. FreeSWITCH is the exception and uses host networking.

The application reaches FreeSWITCH through `host.docker.internal:8021`. On native Linux, Compose adds the `host-gateway` alias explicitly. FreeSWITCH reaches PostgreSQL through the host loopback publication at `127.0.0.1:5432`.

## Shared storage

- `postgres_data`: PostgreSQL database files.
- `redis_data`: Redis persistence.
- `static_data`: Django-collected static assets, served read-only by Nginx.
- `media_data`: uploaded campaign audio and user media; shared by Django, Celery, FreeSWITCH, and Nginx.
- `freeswitch_recordings`: FreeSWITCH recordings.
- `freeswitch_db`: FreeSWITCH runtime database.

The `media_data` volume is particularly important: Django writes uploaded campaign audio, FreeSWITCH reads it during calls and may write recordings, and Nginx serves it under `/usermedia/`.

## Build architecture

There are two important images:

1. `newfies-freeswitch:v1.4`, built from `docker/freeswitch/Dockerfile`.
   - Builds FreeSWITCH and its Python ESL bindings.
   - Builds LuaSQL PostgreSQL support and additional Lua modules.
   - Copies the project’s Lua code and FreeSWITCH configuration.

2. `newfies-dialer:latest`, built from `docker/Dockerfile`.
   - Uses Python 2.7 and the legacy Django application.
   - Builds frontend Bower assets in a temporary Node stage.
   - Copies the ESL Python bindings from the FreeSWITCH image.
   - Is reused by `web`, `celery_worker`, and `celery_beat`.

The FreeSWITCH image must be built first because the application image uses a multi-stage `COPY --from=newfies-freeswitch:v1.4` for ESL.

## Startup behavior

The main application entrypoint:

1. Waits for PostgreSQL.
2. Runs migrations and `collectstatic` when `RUN_MIGRATIONS=true`.
3. Loads default fixtures.
4. Ensures the configured default superuser exists.
5. Starts the requested web or Celery command.

The FreeSWITCH entrypoint:

1. Generates Lua database settings from environment variables.
2. Configures the ESL listen address and password.
3. Creates runtime directories and sets ownership.
4. Starts FreeSWITCH as the `freeswitch` user.

## Deployment implication

This is best understood as a tightly coupled, single-host deployment. It is not a fully independent microservices architecture: FreeSWITCH depends on host networking, the application depends on a legacy runtime, and the Django, Celery, Lua, PostgreSQL, and shared-volume integrations must remain compatible.
