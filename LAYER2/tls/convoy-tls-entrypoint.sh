#!/bin/sh
# Builds a stunnel mTLS config from env. Tunnel = "ACCEPT:CONNECTHOST:CONNECTPORT".
#  SERVER_TUNNELS: accept TLS, REQUIRE+verify a client cert, forward plaintext to the app.
#  CLIENT_TUNNELS: accept plaintext from the app, present our cert, verify the server cert+name.
set -eu
CONF=/tmp/stunnel.conf
# before
{ echo "foreground = yes"; echo "pid ="; echo "syslog = no"; echo "sslVersionMin = TLSv1.3"; } > "$CONF"
# after
{ echo "foreground = yes"; echo "pid ="; echo "syslog = no"; echo "sslVersionMin = TLSv1.3"; } > "$CONF"

n=0
for t in ${SERVER_TUNNELS:-}; do
  acc=${t%%:*}; rest=${t#*:}; ch=${rest%%:*}; cp=${rest##*:}
  { echo "[srv$n]"; echo "accept = 0.0.0.0:$acc"; echo "connect = $ch:$cp";
    echo "cert = /tls/${NODE}.pem"; echo "CAfile = /tls/ca.crt";
    echo "verifyChain = yes"; } >> "$CONF"        # require a CA-signed client cert = mTLS
  n=$((n+1))
done

m=0
for t in ${CLIENT_TUNNELS:-}; do
  acc=${t%%:*}; rest=${t#*:}; ch=${rest%%:*}; cp=${rest##*:}
  { echo "[cli$m]"; echo "client = yes"; echo "accept = 0.0.0.0:$acc";
    echo "connect = $ch:$cp"; echo "cert = /tls/${NODE}.pem";   # present our client cert
    echo "CAfile = /tls/ca.crt"; echo "verifyChain = yes";
    echo "checkHost = $ch"; } >> "$CONF"                        # server name must match cert
  m=$((m+1))
done

echo "=== convoy-tls [$NODE] ==="; cat "$CONF"; echo "=========================="
exec stunnel "$CONF"