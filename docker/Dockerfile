# Vendor JS/CSS (jQuery, Bootstrap, etc.) that BOWER_INSTALLED_APPS
# (newfies/newfies_dialer/settings.py) expects under STATIC's bower finder.
# Built in a throwaway Node stage so the final image doesn't need Node/bower
# at all - `bower install` just needs to run once at build time.
FROM node:12-buster-slim AS bower-builder

RUN sed -i \
    -e 's|deb.debian.org/debian |archive.debian.org/debian |g' \
    -e 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' \
    -e '/buster-updates/d' \
    /etc/apt/sources.list \
    && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until \
    && apt-get update && apt-get install -y --no-install-recommends ca-certificates git \
    && update-ca-certificates --fresh \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g bower@1.8.14

WORKDIR /build
COPY docker/bower.json .
# django-bower (djangobower/bower.py) runs plain `bower install` with cwd
# set to BOWER_COMPONENTS_ROOT and no .bowerrc, so it expects the default
# `bower_components` output directory - matched by finders.py's lookup order.
RUN bower install --allow-root --config.interactive=false

FROM python:2.7-slim-buster

# Newfies-Dialer app tier image (Django/gunicorn + Celery worker/beat).
# FreeSWITCH is NOT built here; it's assumed to run externally (see
# docker-compose.yml comments) and this image only talks to it over ESL.

# Debian buster is EOL; its repos moved to archive.debian.org.
RUN sed -i \
    -e 's|deb.debian.org/debian |archive.debian.org/debian |g' \
    -e 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' \
    -e '/buster-updates/d' \
    /etc/apt/sources.list \
    && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until \
    && apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    libpq-dev \
    libjpeg-dev \
    zlib1g-dev \
    libxml2-dev \
    libxslt1-dev \
    libffi-dev \
    libssl-dev \
    flite \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/share/newfies

COPY requirements/basic.txt requirements/django.txt /tmp/requirements/
# Two fixes applied only to the copies used for this Docker build - the
# project's actual requirements files are left untouched:
#  1. psycopg2==2.6 can't parse the version string of any libpq newer than
#     9.x, so it fails to build against modern base images. Use
#     psycopg2-binary instead.
#  2. git+http://github.com/pinax/django-mailer has no ref, so it always
#     resolves to current master - which has moved to a PEP 517 build
#     requiring setuptools>=61.2 and no longer installs under Python 2.7.
#     Pin it to tag 1.2.6, the last pre-Python3-only release.
#  3. `six` isn't pinned anywhere, so pip resolves the latest release. But
#     django-picklefield==0.3.1 combines an explicit `__metaclass__` with
#     `six.with_metaclass(...)` on the same Field class - a pattern that
#     only works with the older `with_metaclass` implementation and raises
#     a metaclass conflict on six>=1.10. Pin an older six first.
#  4. `django-qsstats-magic` (pulled in transitively by
#     django-admin-tools-stats==0.5.5, which powers the admin dashboard)
#     isn't pinned either, so pip resolves 1.1.0 - which does
#     `from django.db.models.functions import Trunc`, a module that doesn't
#     exist before Django 1.8. That 500s every request to /admin/ on this
#     project's Django 1.7.7. Pin 0.7.2, the last release before that import
#     was introduced.
RUN grep -v '^psycopg2==' /tmp/requirements/basic.txt > /tmp/requirements/basic-docker.txt \
    && sed -e 's#git+http://github.com/pinax/django-mailer#git+http://github.com/pinax/django-mailer@1.2.6#' \
        /tmp/requirements/django.txt > /tmp/requirements/django-docker.txt \
    && pip install --no-cache-dir psycopg2-binary==2.8.6 six==1.9.0 \
    && pip install --no-cache-dir -r /tmp/requirements/basic-docker.txt \
    && pip install --no-cache-dir -r /tmp/requirements/django-docker.txt \
    && pip install --no-cache-dir --no-deps six==1.9.0 django-qsstats-magic==0.7.2

# Two runtime compatibility shims, applied via sitecustomize.py (imported
# automatically by the interpreter on every startup):
#  1. kombu==3.0.24 does `from uuid import _uuid_generate_random`, an
#     attribute provided by the legacy `uuid==1.30` PyPI backport (also
#     pinned in basic.txt) - but Python 2.7's stdlib uuid module always wins
#     on sys.path and has no such attribute, so importing kombu/celery fails
#     on any modern Python 2.7, container or not.
#  2. django_lets_go.only_one_task (used by several periodic tasks, e.g.
#     appointment.tasks.alarm_dispatcher) does `redis.Redis()` with no
#     arguments, hardcoding localhost:6379 - correct only when Celery and
#     Redis share one host, as in the original bare-metal install. In this
#     compose stack Redis is its own service, so point it at REDIS_HOST.
RUN { \
      printf 'import uuid\nif not hasattr(uuid, "_uuid_generate_random"):\n    uuid._uuid_generate_random = None\n'; \
      printf 'import os\ntry:\n    import redis\n    import django_lets_go.only_one_task as _oot\n    _oot.REDIS_CLIENT = redis.Redis(host=os.environ.get("REDIS_HOST", "localhost"), port=int(os.environ.get("REDIS_PORT", "6379")))\nexcept ImportError:\n    pass\n'; \
    } > /usr/local/lib/python2.7/site-packages/sitecustomize.py

COPY newfies/ /usr/share/newfies/
COPY docker/settings_docker.py /usr/share/newfies/newfies_dialer/settings_docker.py
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN mkdir -p /usr/share/newfies/static /usr/share/newfies/usermedia
COPY --from=bower-builder /build/bower_components /usr/share/newfies/components/bower_components

ENV DJANGO_SETTINGS_MODULE=newfies_dialer.settings_docker
ENV PYTHONUNBUFFERED=1

EXPOSE 8000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["gunicorn", "newfies_dialer.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3", "--timeout", "120"]
