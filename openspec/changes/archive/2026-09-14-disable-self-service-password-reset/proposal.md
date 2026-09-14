## Why

The site's login page (`templates/registration/login.html`) routes "forgot password" through the stock Django `password_reset` view/form, wired in via `django-registration-redux`'s bundled `registration.auth_urls` (`newfies_dialer/urls.py`). Django is pinned at `1.7.7`, which predates the fix for CVE-2019-19844: `PasswordResetForm.get_users()` looks users up with a plain `email__iexact` filter and has no Unicode case-folding guard, so a case-insensitive/collation-dependent email match can route a password-reset token to the wrong recipient. A same-day Django upgrade isn't realistic given how far behind the stack is, so this change closes the hole immediately by turning off self-service password reset and falling back to the admin-mediated reset that already exists in Django admin. While the same URL include is being split apart, self-registration (`/accounts/register/`) is also pulled behind an explicit opt-in flag rather than left open by default.

## What Changes

- Remove the `password_reset*` URLs (request, done, confirm, complete) from the `/accounts/` flow entirely; `login`, `logout`, and in-session `password_change` (which requires knowing the current password) keep working.
- **BREAKING**: Self-service "forgot my password" is no longer available anywhere in the app. Locked-out users must be reset by a staff/superuser via Django admin's existing per-user "change password" action.
- Replace the `{% url 'auth_password_reset' %}` link in `templates/registration/login.html` with static "Please email support" copy (no link, no reachable view).
- Remove the dead `href="/password_reset/"` link in `frontend/forms.py`'s `LoginForm` (it already 404s today — no route resolves it — so this is a cosmetic cleanup alongside the real fix, not a second vulnerable path).
- **BREAKING**: Gate self-registration (`/accounts/register/`) behind a new `ALLOW_SELF_REGISTRATION` setting (env-backed, default `false`), following the existing `DJANGO_DEBUG`/`CREATE_DEFAULT_SUPERUSER` boolean-flag pattern in `docker/settings_docker.py` / `.env.example`. When off, only `login`/`logout`/`password_change` are mounted under `/accounts/`; when on, registration is also mounted. Password reset stays removed either way — the flag does not bring it back.
- No change to Django admin's built-in per-user "change password" action (`newfies/user_profile/admin.py`, `newfies/agent/admin.py`, `newfies/appointment/admin.py` all use stock `UserAdmin`) — this remains the fallback path for locked-out users who are staff-visible in admin.

## Capabilities

### New Capabilities
- `account-self-service`: What's reachable under `/accounts/` for an unauthenticated visitor — login, logout, in-session password change, self-registration eligibility, and the explicit absence of self-service password reset.

### Modified Capabilities
(none — no existing specs predate this change)

## Impact

- `newfies/newfies_dialer/urls.py` — replace the blanket `include('registration.backends.default.urls')` with a split include driven by `settings.ALLOW_SELF_REGISTRATION`; password-reset URL names no longer resolve.
- `newfies/newfies_dialer/settings.py` — add `ALLOW_SELF_REGISTRATION` default (`False`).
- `docker/settings_docker.py` — read `ALLOW_SELF_REGISTRATION` from the environment, same pattern as `DEBUG`.
- `.env.example` — document the new `ALLOW_SELF_REGISTRATION` flag next to `CREATE_DEFAULT_SUPERUSER`.
- `newfies/templates/registration/login.html` — copy change, drop the reset link.
- `newfies/frontend/forms.py` — drop the dead reset link.
- No database migrations. No change to `django.contrib.auth` internals, Django admin, or any other authenticated area of the app.
