FROM debian:jessie

# Faithful build of FreeSWITCH v1.4, matching
# install/install-freeswitch.sh (func_install_fs_sources) as closely as
# possible. Debian 8 (jessie) is used deliberately instead of a modern base
# - it's the same era the install script targets, so the toolchain
# (gcc 4.9, autoconf2.64, OpenSSL 1.0.x, etc) is what this 2014-era source
# actually expects, rather than fighting a decade of API drift.

# jessie is long EOL; its repos moved to archive.debian.org.
RUN cat > /etc/apt/sources.list <<'EOF'
deb http://archive.debian.org/debian jessie main
deb http://archive.debian.org/debian-security jessie/updates main
EOF
RUN echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until

RUN apt-get update && apt-get -y --force-yes install \
    locales-all pkg-config unzip zip sox sqlite3 ncftp nmap \
    autoconf2.64 automake autotools-dev binutils bison build-essential cpp curl flex gcc \
    libaudiofile-dev libc6-dev libexpat1 libexpat1-dev mcrypt libmcrypt-dev libnewt-dev \
    libpopt-dev libsctp-dev libx11-dev libxml2 libxml2-dev lksctp-tools lynx m4 openssl \
    ssl-cert zlib1g-dev \
    autoconf automake devscripts gawk g++ git-core libjpeg62-turbo-dev libncurses5-dev \
    libtool make python-dev pkg-config libtiff5-dev libperl-dev libgdbm-dev libdb-dev \
    gettext libssl-dev libcurl4-openssl-dev libpcre3-dev libspeex-dev libspeexdsp-dev \
    libsqlite3-dev libedit-dev libldns-dev libpq-dev libmp3lame-dev \
    libgnutls28-dev libtiff5-dev libtiff5 \
    libvorbis0a libogg0 libogg-dev libvorbis-dev \
    flite flite1-dev \
    unixodbc-dev odbc-postgresql \
    lua5.2 liblua5.2-dev \
    ca-certificates wget \
    && rm -rf /var/lib/apt/lists/*

# func_install_fs_sources adds this system user/group before building.
RUN groupadd -r -f freeswitch && useradd -r -c "freeswitch" -g freeswitch freeswitch

WORKDIR /usr/src
RUN git clone --branch=v1.4 https://github.com/signalwire/freeswitch.git --depth=1 freeswitch

WORKDIR /usr/src/freeswitch
RUN ./bootstrap.sh -j

RUN ./configure --without-pgsql --prefix=/usr/local/freeswitch --sysconfdir=/etc/freeswitch/

# Same module toggles as func_install_fs_sources, EXCEPT mod_flite: its
# bundled/downloaded flite-2.0.0-release sub-library fails to compile
# (flite_lang_list.c has a malformed generated function, then a linker
# error) - a decade-old bundled-source rot issue, unrelated to FreeSWITCH
# core. Costs nothing: the app's own TTS code
# (lua/libs/texttospeech.lua:177) shells out to the system `flite` CLI
# binary directly, never to this FreeSWITCH module.
RUN [ -f modules.conf ] && cp modules.conf modules.conf.bak; \
    sed -i -e \
    "s/#applications\/mod_curl/applications\/mod_curl/g" \
    -e "s/#applications\/mod_avmd/applications\/mod_avmd/g" \
    -e "s/#asr_tts\/mod_tts_commandline/asr_tts\/mod_tts_commandline/g" \
    -e "s/#formats\/mod_shout/formats\/mod_shout/g" \
    -e "s/#endpoints\/mod_dingaling/endpoints\/mod_dingaling/g" \
    -e "s/#formats\/mod_shell_stream/formats\/mod_shell_stream/g" \
    -e "s/#say\/mod_say_de/say\/mod_say_de/g" \
    -e "s/#say\/mod_say_es/say\/mod_say_es/g" \
    -e "s/#say\/mod_say_fr/say\/mod_say_fr/g" \
    -e "s/#say\/mod_say_it/say\/mod_say_it/g" \
    -e "s/#say\/mod_say_nl/say\/mod_say_nl/g" \
    -e "s/#say\/mod_say_ru/say\/mod_say_ru/g" \
    -e "s/#say\/mod_say_zh/say\/mod_say_zh/g" \
    -e "s/#say\/mod_say_hu/say\/mod_say_hu/g" \
    -e "s/#say\/mod_say_th/say\/mod_say_th/g" \
    -e "s/#xml_int\/mod_xml_cdr/xml_int\/mod_xml_cdr/g" \
    modules.conf

RUN make -j"$(nproc)" && make install && make sounds-install && make moh-install

# Build the Python 2 ESL bindings too - the Django/Celery side (in the app
# image) needs `import ESL` from the exact same FreeSWITCH source tree to
# originate calls (newfies/dialer_cdr/tasks.py:dial_out). Built here and
# extracted via a multi-stage COPY --from into the app image's Dockerfile.
WORKDIR /usr/src/freeswitch/libs/esl
RUN make pymod

# LuaSQL 2.3.0 (func_install_luasql) - listener.lua does
# `require "luasql.postgres"` to poll campaign state directly from
# Postgres. Written directly instead of installer's original config,
# which is fetched from a personal gist at build time (a fragile
# single-point-of-failure to depend on); this targets the lua5.2/libpq-dev
# paths actually present in this image.
WORKDIR /usr/src
RUN wget -q https://github.com/keplerproject/luasql/archive/v2.3.0.zip -O luasql.zip \
    && python -c "import zipfile; zipfile.ZipFile('luasql.zip').extractall('.')"
WORKDIR /usr/src/luasql-2.3.0
RUN cat > config <<'EOF'
T = postgres
PREFIX = /usr/local
LUA_LIBDIR = $(PREFIX)/lib/lua/5.2
LUA_DIR = $(PREFIX)/share/lua/5.2
LUA_INC = /usr/include/lua5.2
LUA_VERSION_NUM = 502
LIB_OPTION = -shared
LIBNAME = $T.so
DRIVER_LIBS = -lpq
DRIVER_INCS = -I/usr/include/postgresql
WARN = -Wall -Wmissing-prototypes -Wmissing-declarations -fPIC
INCS = -I$(LUA_INC)
CFLAGS = -O2 $(WARN) -fPIC $(DRIVER_INCS) $(INCS) -DLUASQL_VERSION_NUMBER='"$V"' $(DEFS)
CC = gcc
EOF
RUN make && make install

# lua/libs/dbhandler.lua and dbh_fs.lua do `require 'cmsgpack'` (MessagePack
# pack/unpack for caching row data) - a library FreeSWITCH itself only
# started bundling into mod_lua in later versions (1.6+); this v1.4 source
# tree has no such thing, so newfies.lua's require chain
# (newfies -> fsm_callflow -> database -> dbhandler) errored out on every
# call before ever reaching session:answer()/streamFile() - the call would
# just hang up with no greeting. Build the standalone antirez/lua-cmsgpack
# instead, installed where lua.conf.xml's module-directory already looks.
WORKDIR /usr/src
RUN git clone --depth=1 https://github.com/antirez/lua-cmsgpack.git \
    && cd lua-cmsgpack \
    && gcc -O2 -fPIC -shared -I/usr/include/lua5.2 -o cmsgpack.so lua_cmsgpack.c \
    && install -m 755 cmsgpack.so /usr/local/lib/lua/5.2/cmsgpack.so

# Newfies-Dialer's own Lua application code (listener.lua, newfies.lua,
# the fsm_callflow/database/session helpers under libs/) - what
# lua.conf.xml's startup-script and settings_local.py's ESL_SCRIPT point at.
COPY lua/ /usr/share/newfies-lua/
COPY install/freeswitch-conf/lua.conf.xml /etc/freeswitch/autoload_configs/lua.conf.xml

# func_configure_fs's runtime module-load toggles, minus mod_lua (already
# loaded by default in this version's vanilla modules.conf.xml) and minus
# mod_xml_cdr (the project's own install script leaves this commented out
# too - "this is commented as we don't use xml_cdr anymore").
RUN sed -i -r \
    -e 's/<\!--\s?<load module="mod_dingaling"\/>\s?-->/<load module="mod_dingaling"\/>/g' \
    -e 's/<\!--\s?<load module="mod_shell_stream"\/>\s?-->/<load module="mod_shell_stream"\/>/g' \
    -e 's/<\!-- \s?<load module="mod_shell_stream"\/>\s? -->/<load module="mod_shell_stream"\/>/g' \
    -e 's/<\!--\s?<load module="mod_shout"\/>\s?-->/<load module="mod_shout"\/>/g' \
    -e 's/<\!--\s?<load module="mod_tts_commandline"\/>\s?-->/<load module="mod_tts_commandline"\/>/g' \
    -e 's/<\!--\s?<load module="mod_say_ru"\/>\s?-->/<load module="mod_say_ru"\/>/g' \
    -e 's/<\!--\s?<load module="mod_say_zh"\/>\s?-->/<load module="mod_say_zh"\/>/g' \
    -e 's/mod_say_zh.*$/&\n    <load module="mod_say_de"\/>\n    <load module="mod_say_es"\/>\n    <load module="mod_say_fr"\/>\n    <load module="mod_say_it"\/>\n    <load module="mod_say_nl"\/>\n    <load module="mod_say_hu"\/>\n    <load module="mod_say_th"\/>/' \
    /etc/freeswitch/autoload_configs/modules.conf.xml

COPY docker/freeswitch/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && chown -R freeswitch:freeswitch /usr/local/freeswitch /etc/freeswitch /usr/share/newfies-lua

WORKDIR /usr/local/freeswitch
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/freeswitch/bin/freeswitch", "-u", "freeswitch", "-g", "freeswitch", "-nonat"]
