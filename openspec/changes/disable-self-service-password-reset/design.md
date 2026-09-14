## Context

`/accounts/` is currently one blanket include in `newfies/newfies_dialer/urls.py:59`:

```python
(r'^accounts/', include('registration.backends.default.urls')),
```

`django-registration-redux`'s `backends/default/urls.py` mounts self-registration (`register/`, `activate/...`) and then does `include('registration.auth_urls')`, which pulls in the stock `django.contrib.auth.views` for `login`, `logout`, `password_change`, and `password_reset*` — all under one name, `auth_password_reset` being the one that must stop resolving. There's no local `auth_urls.py` override in this project today; the fix has to happen at the include, not by patching django-registration-redux.

Two independent config surfaces exist for env-driven settings:
- `newfies/newfies_dialer/settings.py` — base defaults (this is what `runserver`/tests use directly).
- `docker/settings_docker.py` — `from settings import *` then overrides from `os.environ`, e.g. `DEBUG = os.environ.get('DJANGO_DEBUG', 'false').lower() == 'true'`. This is the pattern the new `ALLOW_SELF_REGISTRATION` flag should follow.

See proposal.md - Why for the CVE-2019-19844 motivation.

## Goals / Non-Goals

**Goals:**
- Make password-reset URL names unresolvable under `/accounts/`, unconditionally.
- Keep `login`, `logout`, and `password_change` working exactly as they do today.
- Make self-registration conditional on one boolean setting, off by default, following the existing `docker/settings_docker.py` env-flag pattern.
- Leave Django admin's own auth URLs and password-change view untouched — they're a separate include (`r'^admin/'`) and out of scope.

**Non-Goals:**
- Upgrading Django or backporting the upstream `_unicode_ci_compare` fix (that's options A/B from the earlier discussion, not this change).
- Building any new "request an unlock" support flow — "email support" is static copy, not a new feature.
- Touching `frontend`'s separate customer-dashboard login (`frontend/views.py` / `frontend/urls.py`) beyond deleting the one dead link in `frontend/forms.py` — that login flow has no working password-reset entry point today and none is being added.

## Decisions

**Split the include instead of patching django-registration-redux.** Rather than vendoring or monkey-patching `registration.auth_urls`, replace the single include with a small local urlconf list that mounts exactly `login`, `logout`, `password_change`, `password_change_done` from `django.contrib.auth.views` under `/accounts/`, plus `registration.backends.default.urls` only when `settings.ALLOW_SELF_REGISTRATION` is true. This keeps the change to one file (`urls.py`) and makes "what's mounted" auditable by reading the urlconf, rather than relying on a downstream package's internals staying the same across upgrades.

Alternative considered: keep `include('registration.backends.default.urls')` wholesale and 404 the reset views by overriding `handler404`-style redirects. Rejected — it leaves the vulnerable view registered and reachable in principle (e.g. if template changes elsewhere ever re-link to it), and doesn't give a clean way to also gate registration.

**One flag, not two.** A single `ALLOW_SELF_REGISTRATION` setting gates registration; password-reset removal is unconditional and has no flag. Considered adding a symmetrical `ALLOW_SELF_SERVICE_PASSWORD_RESET` flag for consistency, but the whole point of this change is that the reset path is unsafe on the current Django version — leaving a flag that could re-enable it defeats the purpose. If/when Django is upgraded past the CVE fix, removing this change (or a follow-up) restores it deliberately.

**Static copy, no settings-driven support address.** "Please email support" ships as plain template text, not a `SUPPORT_EMAIL` setting or mailto link, since no such setting exists today and inventing one is out of scope. If the user wants a live mailto/link later, that's a follow-up.

## Risks / Trade-offs

- **[Risk]** Any user who doesn't already know their password and isn't staff-visible in Django admin has no way to self-recover → **Mitigation**: this is the accepted, explicit trade-off of the stopgap (see proposal.md - Why); staff/superusers can reset any account via admin's built-in "change password" action.
- **[Risk]** Splitting the include by hand means future django-registration-redux upgrades could add new URL names (e.g. a new auth view) that this project's local urlconf doesn't know to mount → **Mitigation**: the local urlconf only needs to name the four views actually in use (`login`, `logout`, `password_change`, `password_change_done`); nothing else is currently linked to from any template, so a silent gap is low-risk and would show up as a 404 on a page that used to work, not a security regression.
- **[Risk]** `ALLOW_SELF_REGISTRATION` could be left `true` in an environment's `.env` from a prior manual test and mask the intended default → **Mitigation**: default is `false` in both `settings.py` and `.env.example`; nothing sets it to `true` automatically.

## Migration Plan

- No database migration. No data affects this change — purely urlconf, settings, and two templates.
- Deploy: ship the settings/urls/template changes; `.env` files that don't define `ALLOW_SELF_REGISTRATION` fall back to `false` automatically, so no `.env` edit is required to get the security fix — only deployments that currently want self-registration need to add `ALLOW_SELF_REGISTRATION=true`.
- Rollback: revert the commit. No stateful migration to unwind.
