#!/bin/bash
set -euo pipefail

DJANGO_SETTINGS_MODULE="newfies_dialer.settings_docker"
export DJANGO_SETTINGS_MODULE

cd /usr/share/newfies

echo "Waiting for PostgreSQL at ${POSTGRES_HOST:-db}:${POSTGRES_PORT:-5432}..."
python <<'PYEOF'
import os
import socket
import time

host = os.environ.get('POSTGRES_HOST', 'db')
port = int(os.environ.get('POSTGRES_PORT', '5432'))

for _ in range(60):
    try:
        socket.create_connection((host, port), timeout=2).close()
        break
    except socket.error:
        time.sleep(2)
else:
    raise SystemExit('Timed out waiting for PostgreSQL at %s:%s' % (host, port))
PYEOF
echo "PostgreSQL is up."

if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
    python manage.py migrate --noinput
    python manage.py collectstatic --noinput

    # install/newfies-dialer-functions.sh (func_django_newfiesdialer_install)
    # loads these same fixtures as part of a normal bare-metal install - none
    # of them are named `initial_data`, so syncdb/migrate never loads them
    # automatically. Without this, every tenant's UserProfile.dialersetting
    # has nothing to point at.
    python manage.py loaddata appointment/fixtures/default_appointment.json
    python manage.py loaddata dialer_gateway/fixtures/default_dialer_gateway.json
    python manage.py loaddata dialer_settings/fixtures/default_dialer_settings.json

    if [ "${CREATE_DEFAULT_SUPERUSER:-true}" = "true" ]; then
        # Plain `python`, not `manage.py shell` - the latter always drives an
        # InteractiveConsole (even fed via heredoc/non-tty stdin), which
        # requires a blank line to close every multi-line block; get that
        # wrong and it silently mis-parses instead of erroring loudly.
        DEFAULT_SUPERUSER_USERNAME="${DEFAULT_SUPERUSER_USERNAME:-admin}" \
        DEFAULT_SUPERUSER_PASSWORD="${DEFAULT_SUPERUSER_PASSWORD:-admin123}" \
        DEFAULT_SUPERUSER_EMAIL="${DEFAULT_SUPERUSER_EMAIL:-admin@example.com}" \
        python <<'PYEOF'
import os

import django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'newfies_dialer.settings_docker')
django.setup()

from django.contrib.auth.models import User

username = os.environ['DEFAULT_SUPERUSER_USERNAME']
password = os.environ['DEFAULT_SUPERUSER_PASSWORD']
email = os.environ['DEFAULT_SUPERUSER_EMAIL']

# This account is for /admin/ (configuring the system) - it deliberately
# has no UserProfile/DialerSetting, since it isn't meant to use the
# customer-facing frontend as a tenant. Seeing the "settings are not
# configured properly" banner there is expected, not a bug.
user, created = User.objects.get_or_create(
    username=username,
    defaults={'email': email, 'is_staff': True, 'is_superuser': True, 'is_active': True},
)
user.email = email
user.is_staff = True
user.is_superuser = True
user.is_active = True
user.set_password(password)
user.save()
print('%s default superuser %r' % ('Created' if created else 'Ensured', username))
PYEOF
    fi
fi

exec "$@"
