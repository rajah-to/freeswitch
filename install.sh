#!/bin/bash
# ==============================================================================
# FreeSWITCH Rajah-TO PBX Installer (Single Bash Script)
# Replicates the multi-stage Dockerfile environment
# ==============================================================================

set -e

# --- Configuration ---
FS_VERSION="v1.11"
BUILD_DIR="/usr/src"
FULL_INSTALL=${FULL:-false}
DEBUG_MODE=${DEBUG:-false}

# For TLS cert generation (from entrypoint.sh logic)
CERT_CN=${CERT_CN:-"rajah-to.local"}
CERT_O=${CERT_O:-"Rajah-TO"}
CERT_C=${CERT_C:-"US"}
CERT_DAYS=${CERT_DAYS:-"3650"}

echo "[install] Starting FreeSWITCH installation..."

# 1. Install Build Dependencies
echo "[install] Installing dependencies..."
apt-get update && apt-get install -yq --no-install-recommends \
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
    iproute2 openssl

if [ "$DEBUG_MODE" = "true" ]; then
    apt-get install -yq --no-install-recommends procps vim-tiny sngrep strace
fi

# 2. Clone Repositories
echo "[install] Cloning repositories..."
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

git clone https://github.com/signalwire/libks.git         libs/libks
git clone https://github.com/freeswitch/sofia-sip.git     libs/sofia-sip
git clone https://github.com/freeswitch/spandsp.git       libs/spandsp
git clone https://github.com/signalwire/freeswitch.git    freeswitch
git clone https://github.com/rajah-to/freeswitch.git      rajah-to-conf

# 3. Build & Install Dependencies
echo "[install] Building libks..."
cd "${BUILD_DIR}/libs/libks"
cmake . -DCMAKE_INSTALL_PREFIX=/usr -DWITH_LIBBACKTRACE=1
make -j"$(nproc)" && make install

echo "[install] Building sofia-sip..."
cd "${BUILD_DIR}/libs/sofia-sip"
./bootstrap.sh
./configure CFLAGS="-g -ggdb" --with-pic --with-glib=no \
        --without-doxygen --disable-stun --prefix=/usr
make -j"$(nproc)" && make install

echo "[install] Building spandsp..."
cd "${BUILD_DIR}/libs/spandsp"
./bootstrap.sh
./configure CFLAGS="-g -ggdb" --with-pic --prefix=/usr
make -j"$(nproc)" && make install

ldconfig

# 4. Build & Install FreeSWITCH
echo "[install] Building FreeSWITCH ${FS_VERSION}..."
cd "${BUILD_DIR}/freeswitch"
git checkout "${FS_VERSION}"
./bootstrap.sh -j

# Use Rajah-TO curated modules.conf
cp "${BUILD_DIR}/rajah-to-conf/modules.conf" "${BUILD_DIR}/freeswitch/modules.conf"

# Pre-create confdir so make install skips vanilla conf entirely
mkdir -p /etc/freeswitch

./configure \
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
    --disable-dependency-tracking

make -j"$(nproc)"
make install

# 5. Sounds & MOH
echo "[install] Installing sounds..."
make sounds-install
make moh-install

if [ "$FULL_INSTALL" = "true" ]; then
    echo "[install] Installing full sound sets..."
    make cd-sounds-install
    make cd-sounds-allison-install
    make cd-sounds-ru-install
    make cd-sounds-fr-install
    make cd-moh-install
fi

# 6. Post-Install Optimization & Cleanup
echo "[install] Stripping binaries..."
strip --strip-unneeded /usr/bin/freeswitch /usr/bin/fs_cli
find /usr/lib/freeswitch -name '*.so' -exec strip --strip-unneeded {} +
find /usr/lib -maxdepth 1 \
    \( -name 'libfreeswitch.so*' \
    -o -name 'libsofia-sip-ua*.so*' \
    -o -name 'libspandsp*.so*' \
    -o -name 'libks*.so*' \) \
    -exec strip --strip-unneeded {} +

# 7. Apply Rajah-TO Configuration
echo "[install] Applying Rajah-TO configuration..."
cp -rT "${BUILD_DIR}/rajah-to-conf/conf" /etc/freeswitch

# 8. System Setup (Users, Permissions, Dirs)
echo "[install] Setting up system environment..."
if ! getent group freeswitch >/dev/null; then
    groupadd --system freeswitch
fi
if ! getent passwd freeswitch >/dev/null; then
    useradd  --system --gid freeswitch \
             --no-create-home --home-dir /nonexistent \
             --shell /usr/sbin/nologin freeswitch
fi

mkdir -p /var/lib/freeswitch/db \
         /var/lib/freeswitch/storage \
         /var/lib/freeswitch/recordings \
         /var/log/freeswitch \
         /var/cache/freeswitch \
         /run/freeswitch \
         /etc/freeswitch/tls

chown -R freeswitch:freeswitch \
    /var/lib/freeswitch \
    /var/log/freeswitch \
    /var/cache/freeswitch \
    /run/freeswitch

chown -R root:freeswitch /etc/freeswitch
chmod -R u=rwX,g=rX,o= /etc/freeswitch
chown freeswitch:freeswitch /etc/freeswitch/tls
chmod 750 /etc/freeswitch/tls
chown -R root:root /usr/share/freeswitch
chmod -R u=rwX,go=rX /usr/share/freeswitch
chown freeswitch:freeswitch -R /etc/freeswitch
cp "${BUILD_DIR}/rajah-to-conf/systemd.freeswitch.service" /etc/systemd/system/freeswitch.service
systemctl daemon-reload
systemctl enable freeswitch
systemctl start freeswitch

# 9. TLS Generation (Optional initial setup)
CERT_DIR="/etc/freeswitch/tls"
CERT_FILE="${CERT_DIR}/wss.pem"
if [ ! -f "$CERT_FILE" ]; then
    echo "[install] Generating initial self-signed cert..."
    openssl req -x509 -newkey rsa:2048 -nodes \
        -days   "$CERT_DAYS" \
        -subj   "/CN=$CERT_CN/O=$CERT_O/C=$CERT_C" \
        -keyout /tmp/k.pem \
        -out    /tmp/c.pem 2>/dev/null

    cat /tmp/k.pem /tmp/c.pem > "$CERT_FILE"
    cp "$CERT_FILE" "${CERT_DIR}/agent.pem"
    cp "$CERT_FILE" "${CERT_DIR}/cafile.pem"
    rm -f /tmp/k.pem /tmp/c.pem
    chown freeswitch:freeswitch "$CERT_FILE" "${CERT_DIR}/agent.pem" "${CERT_DIR}/cafile.pem"
fi

ldconfig

echo "[install] Done! FreeSWITCH is installed."
echo "[info] Run as user 'freeswitch': freeswitch -nonat -nf"
