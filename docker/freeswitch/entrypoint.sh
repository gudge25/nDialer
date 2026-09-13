#!/bin/bash
set -euo pipefail

# lua/libs/settings.lua is this project's DB-connection config for the
# Lua side (the equivalent of newfies_dialer/settings_local.py) - listener.lua
# and the dialplan scripts read DBHOST/DBNAME/DBUSER/DBPASS/DBPORT from it.
cat > /usr/share/newfies-lua/libs/settings.lua <<EOF
DBHOST = '${DBHOST:-127.0.0.1}'
DBNAME = '${DBNAME:-newfies}'
DBUSER = '${DBUSER:-newfies}'
DBPASS = '${DBPASS:-}'
DBPORT = ${DBPORT:-5432}
TTS_ENGINE = '${TTS_ENGINE:-flite}'
EOF

# event_socket.conf.xml ships with listen-ip=127.0.0.1 - fine when Django/
# Celery run on the same host, but here they're in separate containers on
# a bridge network reaching this host-networked container via
# host.docker.internal, so ESL needs to listen on all interfaces. The
# password is exposed beyond localhost as a result, so it must not stay at
# the "ClueCon" default in any real deployment.
sed -i \
    -e "s#<param name=\"listen-ip\" value=\"127.0.0.1\"/>#<param name=\"listen-ip\" value=\"${ESL_LISTEN_IP:-0.0.0.0}\"/>#" \
    -e "s#<param name=\"password\" value=\"ClueCon\"/>#<param name=\"password\" value=\"${ESL_SECRET:-ClueCon}\"/>#" \
    /etc/freeswitch/autoload_configs/event_socket.conf.xml

mkdir -p /usr/local/freeswitch/log /usr/local/freeswitch/db /usr/local/freeswitch/recordings
chown -R freeswitch:freeswitch /usr/local/freeswitch/log /usr/local/freeswitch/db /usr/local/freeswitch/recordings /usr/share/newfies-lua/libs/settings.lua

exec "$@"
