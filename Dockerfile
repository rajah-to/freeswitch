# syntax=docker/dockerfile:1.7

# ============================================================
# Stage 1: Builder
# ============================================================
FROM debian:trixie AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV FS_VERSION=v1.11
ENV BUILD_DIR=/usr/src

ARG FULL=false

RUN apt-get update && apt-get install -yq --no-install-recommends \
    git ca-certificates curl \
    build-essential cmake automake autoconf libtool libtool-bin pkg-config \
    libssl-dev zlib1g-dev libdb-dev unixodbc-dev libncurses5-dev \
    libexpat1-dev libgdbm-dev bison erlang-dev libtpl-dev libtiff-dev \
    libjpeg62-turbo-dev uuid-dev libxml2-dev libpng-dev \
    libpcre2-dev libedit-dev libsqlite3-dev libcurl4-openssl-dev \
    nasm yasm \
    libogg-dev libspeex-dev libspeexdsp-dev \
    libldns-dev python3-dev liblua5.2-dev libopus-dev libpq-dev \
    libsndfile1-dev libflac-dev libvorbis-dev \
    libshout3-dev libmpg123-dev libmp3lame-dev \
    libavformat-dev libswscale-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR ${BUILD_DIR}

RUN git clone https://github.com/signalwire/libks.git         libs/libks \
 && git clone https://github.com/freeswitch/sofia-sip.git     libs/sofia-sip \
 && git clone https://github.com/freeswitch/spandsp.git       libs/spandsp \
 && git clone https://github.com/signalwire/freeswitch.git    freeswitch \
 && git clone https://github.com/QwixPBX/freeswitch-conf.git  qwixpbx-freeswitch-conf

RUN cd libs/libks \
 && cmake . -DCMAKE_INSTALL_PREFIX=/usr -DWITH_LIBBACKTRACE=1 \
 && make -j"$(nproc)" && make install

RUN cd libs/sofia-sip \
 && ./bootstrap.sh \
 && ./configure CFLAGS="-g -ggdb" --with-pic --with-glib=no \
        --without-doxygen --disable-stun --prefix=/usr \
 && make -j"$(nproc)" && make install

RUN cd libs/spandsp \
 && ./bootstrap.sh \
 && ./configure CFLAGS="-g -ggdb" --with-pic --prefix=/usr \
 && make -j"$(nproc)" && make install

RUN ldconfig

WORKDIR ${BUILD_DIR}/freeswitch

RUN git checkout ${FS_VERSION} && ./bootstrap.sh -j

# Use QwixPBX curated modules.conf (replaces default + no sed patching needed)
RUN cp "${BUILD_DIR}/qwixpbx-freeswitch-conf/modules.conf" "${BUILD_DIR}/freeswitch/modules.conf"

# Pre-create confdir so make install skips vanilla conf entirely
RUN mkdir -p /etc/freeswitch \
 && ./configure \
        --prefix=/usr \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --runstatedir=/run \
        --with-modinstdir=/usr/lib/freeswitch/mod \
        --with-rundir=/run/freeswitch \
        --with-logfiledir=/var/log/freeswitch \
        --with-dbdir=/var/lib/freeswitch/db \
        --with-storagedir=/var/lib/freeswitch/storage \
        --with-recordingsdir=/var/lib/freeswitch/recordings \
        --with-htdocsdir=/usr/share/freeswitch/htdocs \
        --with-soundsdir=/usr/share/freeswitch/sounds \
        --with-scriptdir=/usr/share/freeswitch/scripts \
        --with-cachedir=/var/cache/freeswitch \
        --disable-dependency-tracking \
 && make -j"$(nproc)" \
 && make install

# Default: 8kHz en-us-callie sounds + MOH
RUN make sounds-install \
 && make moh-install

# FULL=true: all rates + all languages + all MOH rates
RUN if [ "$FULL" = "true" ]; then \
        make cd-sounds-install \
     && make cd-sounds-allison-install \
     && make cd-sounds-ru-install \
     && make cd-sounds-fr-install \
     && make cd-moh-install; \
    fi

# Strip debug symbols — .so files only, skip .la libtool archives
RUN strip --strip-unneeded /usr/bin/freeswitch /usr/bin/fs_cli \
 && find /usr/lib/freeswitch -name '*.so' -exec strip --strip-unneeded {} + \
 && find /usr/lib -maxdepth 1 \
        \( -name 'libfreeswitch.so*' \
        -o -name 'libsofia-sip-ua*.so*' \
        -o -name 'libspandsp*.so*' \
        -o -name 'libks*.so*' \) \
        -exec strip --strip-unneeded {} +

# Overlay QwixPBX conf — conf/ subdirectory is the actual tree
RUN cp -rT "${BUILD_DIR}/qwixpbx-freeswitch-conf/conf" /etc/freeswitch

# ============================================================
# Stage 2: Runtime
# ============================================================
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

# Cert env vars — overridable at runtime via -e, no rebuild needed
ENV CERT_CN="qwixpbx.local"
ENV CERT_O="QwixPBX"
ENV CERT_C="US"
ENV CERT_DAYS="3650"

ARG DEBUG=false

RUN apt-get update && apt-get install -yq --no-install-recommends \
    ca-certificates openssl \
    libssl3 libodbc2 libncurses6 libexpat1 libgdbm6 \
    libtpl0 libtiff6 libjpeg62-turbo libxml2 libpng16-16 libpcre2-8-0 \
    libedit2 libsqlite3-0 libcurl4 libuuid1 libdb5.3t64 \
    libogg0 libspeex1 libspeexdsp1 \
    libldns3 python3 liblua5.2-0 libopus0 libpq5 \
    libsndfile1 libflac14 libvorbis0a \
    libshout3 libmpg123-0 libmp3lame0 \
    libavformat61 libswscale8 \
    iproute2 \
 && if [ "$DEBUG" = "true" ]; then \
        apt-get install -yq --no-install-recommends \
            procps vim-tiny sngrep strace; \
    fi \
 && rm -rf /var/lib/apt/lists/* \
           /usr/share/doc \
           /usr/share/man \
           /usr/share/locale/* \
           /usr/share/info

# Binaries
COPY --from=builder /usr/bin/freeswitch /usr/bin/freeswitch
COPY --from=builder /usr/bin/fs_cli     /usr/bin/fs_cli

# FreeSWITCH core lib + modules
COPY --from=builder /usr/lib/libfreeswitch.so* /usr/lib/
COPY --from=builder /usr/lib/freeswitch        /usr/lib/freeswitch

# Built-from-source libs
COPY --from=builder /usr/lib/libsofia-sip-ua*  /usr/lib/
COPY --from=builder /usr/lib/libspandsp*       /usr/lib/
COPY --from=builder /usr/lib/libks*            /usr/lib/

# Configs (QwixPBX conf already applied in builder)
COPY --from=builder /etc/freeswitch            /etc/freeswitch

# Sounds + MOH
COPY --from=builder /usr/share/freeswitch      /usr/share/freeswitch

RUN ldconfig

RUN groupadd --system freeswitch \
 && useradd  --system --gid freeswitch \
             --no-create-home --home-dir /nonexistent \
             --shell /usr/sbin/nologin freeswitch

RUN mkdir -p /var/lib/freeswitch/db \
             /var/lib/freeswitch/storage \
             /var/lib/freeswitch/recordings \
             /var/log/freeswitch \
             /var/cache/freeswitch \
             /run/freeswitch \
             /etc/freeswitch/tls \
 && chown -R freeswitch:freeswitch \
        /var/lib/freeswitch \
        /var/log/freeswitch \
        /var/cache/freeswitch \
        /run/freeswitch \
 && chown -R root:freeswitch /etc/freeswitch \
 && chmod -R u=rwX,g=rX,o= /etc/freeswitch \
 && chown freeswitch:freeswitch /etc/freeswitch/tls \
 && chmod 750 /etc/freeswitch/tls \
 && chown -R root:root /usr/share/freeswitch \
 && chmod -R u=rwX,go=rX /usr/share/freeswitch \
 && chown freeswitch:freeswitch -R /etc/freeswitch

COPY entrypoint.sh /entrypoint.sh

USER freeswitch

EXPOSE 5060/udp 5061/tcp \
       5070/udp 5071/tcp \
       5080/udp 5080/tcp \
       8021/tcp \
       16384-32768/udp

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/freeswitch", "-nonat", "-nf"]