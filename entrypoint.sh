#!/bin/sh
set -e

CERT_DIR="/etc/freeswitch/tls"
CERT_FILE="${CERT_DIR}/wss.pem"

# --- Inject domain into vars.xml at startup ---
if [ -n "$DOMAIN" ]; then
    echo "[qwixpbx] Setting domain to ${DOMAIN}"
    # Write to tmp then move — avoids sed temp file permission issue
    sed "s|<X-PRE-PROCESS cmd=\"set\" data=\"domain=.*\"/>|<X-PRE-PROCESS cmd=\"set\" data=\"domain=${DOMAIN}\"/>|" \
        /etc/freeswitch/vars.xml > /tmp/vars.xml \
    && cp /tmp/vars.xml /etc/freeswitch/vars.xml \
    && rm -f /tmp/vars.xml
fi

# --- TLS cert handling ---
if [ -f "$CERT_FILE" ]; then
    echo "[qwixpbx] Using existing TLS cert: ${CERT_FILE}"
else
    echo "[qwixpbx] No TLS cert found — generating self-signed cert"
    echo "[qwixpbx] WARNING: Self-signed cert is for dev/testing only."
    echo "[qwixpbx]          For production, mount your cert at ${CERT_FILE}"

    openssl req -x509 -newkey rsa:2048 -nodes \
        -days   "${CERT_DAYS:-3650}" \
        -subj   "/CN=${CERT_CN:-qwixpbx.local}/O=${CERT_O:-QwixPBX}/C=${CERT_C:-US}" \
        -keyout /tmp/k.pem \
        -out    /tmp/c.pem 2>/dev/null

    cat /tmp/k.pem /tmp/c.pem > "$CERT_FILE"
    cp "$CERT_FILE" "${CERT_DIR}/agent.pem"
    cp "$CERT_FILE" "${CERT_DIR}/cafile.pem"
    rm -f /tmp/k.pem /tmp/c.pem

    echo "[qwixpbx] Self-signed cert generated — CN=${CERT_CN:-qwixpbx.local}"
fi

exec "$@"