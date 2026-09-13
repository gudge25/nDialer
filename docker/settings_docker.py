#!/usr/bin/python
# -*- coding: utf-8 -*-

# Docker Compose settings override for Newfies-Dialer.
# Mirrors install/conf/settings_local.py but reads connection info from
# environment variables instead of hardcoded values, so the same image
# works across dev/prod compose files.

import os

from settings import *  # noqa

DEBUG = os.environ.get('DJANGO_DEBUG', 'false').lower() == 'true'
TEMPLATE_DEBUG = DEBUG

SECRET_KEY = os.environ.get('DJANGO_SECRET_KEY', SECRET_KEY)

ALLOWED_HOSTS = [h.strip() for h in os.environ.get('DJANGO_ALLOWED_HOSTS', '*').split(',') if h.strip()]

TIME_ZONE = os.environ.get('TIME_ZONE', 'UTC')

# DATABASE SETTINGS
# =================
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql_psycopg2',
        'NAME': os.environ.get('POSTGRES_DB', 'newfies'),
        'USER': os.environ.get('POSTGRES_USER', 'newfies'),
        'PASSWORD': os.environ.get('POSTGRES_PASSWORD', ''),
        'HOST': os.environ.get('POSTGRES_HOST', 'db'),
        'PORT': os.environ.get('POSTGRES_PORT', '5432'),
        'OPTIONS': {
            'autocommit': True,
        },
    }
}

# REDIS (cache + celery broker/result backend)
# =============================================
REDIS_HOST = os.environ.get('REDIS_HOST', 'redis')
REDIS_PORT = os.environ.get('REDIS_PORT', '6379')
REDIS_DB = os.environ.get('REDIS_DB', '0')
REDIS_URL = 'redis://%s:%s/%s' % (REDIS_HOST, REDIS_PORT, REDIS_DB)

CACHES = {
    'default': {
        'BACKEND': 'redis_cache.RedisCache',
        'LOCATION': '%s:%s' % (REDIS_HOST, REDIS_PORT),
    },
}

BROKER_URL = REDIS_URL
CELERY_RESULT_BACKEND = REDIS_URL
CELERY_DISABLE_RATE_LIMITS = True

# STATIC / MEDIA
# ==============
STATIC_ROOT = '/usr/share/newfies/static'
MEDIA_ROOT = '/usr/share/newfies/usermedia'

# ESL (FreeSWITCH event socket) - FreeSWITCH is NOT part of this compose
# stack; point these at wherever it actually runs.
ESL_HOSTNAME = os.environ.get('ESL_HOSTNAME', '127.0.0.1')
ESL_PORT = os.environ.get('ESL_PORT', '8021')
ESL_SECRET = os.environ.get('ESL_SECRET', 'ClueCon')

API_ALLOWED_IP = [h.strip() for h in os.environ.get('API_ALLOWED_IP', '127.0.0.1').split(',') if h.strip()]

# LOGGING - log to stdout/stderr so `docker compose logs` captures it,
# instead of the file paths under /var/log/newfies used by the bare-metal
# installer.
LOGGING = {
    'version': 1,
    'disable_existing_loggers': True,
    'formatters': {
        'verbose': {
            'format': '%(levelname)s %(asctime)s %(module)s '
                      '%(process)d %(thread)d %(message)s'
        },
    },
    'handlers': {
        'console': {
            'level': 'DEBUG',
            'class': 'logging.StreamHandler',
            'formatter': 'verbose',
        },
    },
    'loggers': {
        'django': {
            'handlers': ['console'],
            'propagate': False,
            'level': 'INFO',
        },
        'django.request': {
            'handlers': ['console'],
            'level': 'ERROR',
            'propagate': False,
        },
        'newfies.filelog': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
        'django.db.backends': {
            'handlers': ['console'],
            'level': 'ERROR',
            'propagate': False,
        },
        'audiofield_log': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
    },
}

TTS_ENGINE = os.environ.get('TTS_ENGINE', 'FLITE')
NEWFIES_DIALER_ENGINE = os.environ.get('NEWFIES_DIALER_ENGINE', 'esl')
