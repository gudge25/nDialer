## Purpose

Ensures the application's cryptographic secret and security-sensitive default settings are not committed to source control in a usable, exploitable form, so a leaked repository or public git history does not directly compromise a running deployment.

## Requirements

### Requirement: Secret key is not hardcoded to a real value in source control
The system SHALL derive its Django `SECRET_KEY` from deployment configuration (an environment variable or a `settings_local.py` override) rather than from a fixed literal committed to `newfies/newfies_dialer/settings.py`. The literal value committed prior to this change SHALL be treated as compromised and SHALL NOT remain the effective key in any environment after rollout.

#### Scenario: Deployment provides a secret key via environment variable
- **WHEN** the `DJANGO_SECRET_KEY` environment variable is set at process start
- **THEN** the application uses that value as `SECRET_KEY`

#### Scenario: Deployment provides a secret key via settings_local.py
- **WHEN** `settings_local.py` defines `SECRET_KEY`
- **THEN** that value overrides both the environment variable and the built-in fallback, consistent with the existing `settings_local` override mechanism

#### Scenario: No secret key is configured
- **WHEN** neither `DJANGO_SECRET_KEY` nor a `settings_local.py` override is present
- **THEN** the application still starts, using a fallback value that is distinct from the previously-committed key and is documented as unsuitable for production use

### Requirement: Default database configuration does not present a false credential-safety signal
The system's default (sqlite3) database configuration SHALL NOT claim or imply username/password protection that sqlite3 does not support, and this SHALL be documented at the configuration site so it is not mistaken for an oversight. A deployment that configures a networked database engine (e.g. via `settings_local.py`) SHALL supply real, non-empty credentials for that engine.

#### Scenario: Default sqlite3 configuration is used
- **WHEN** the application runs with the default `DATABASES['default']` sqlite3 configuration and no `settings_local.py` override
- **THEN** the empty `USER`/`PASSWORD` fields are accompanied by an explanation that sqlite3 requires no network authentication, rather than appearing as an unaddressed credential gap

#### Scenario: Deployment overrides with a networked database engine
- **WHEN** `settings_local.py` sets `DATABASES['default']['ENGINE']` to a networked backend (e.g. PostgreSQL)
- **THEN** it SHALL also set non-empty `USER` and `PASSWORD` values for that connection
