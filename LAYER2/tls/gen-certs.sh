#!/bin/sh
# Internal CA + one cert per node, each valid as BOTH a server and a client cert
# (extendedKeyUsage=serverAuth,clientAuth) so mTLS works in both directions. Idempotent.
set -eu
TLS=/tls
NODES="node1 node2 node3 node4 node5 node1b node2b node3b node4b node5b shipa devops"

[ -s "$TLS/ca.crt" ] || openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TLS/ca.key" -out "$TLS/ca.crt" -days 3650 -subj "/CN=convoy-tls-ca"

for N in $NODES; do
  [ -s "$TLS/$N.pem" ] && continue
  openssl req -newkey rsa:2048 -nodes -keyout "$TLS/$N.key" -out "$TLS/$N.csr" \
    -subj "/CN=convoy-tls-$N"
  cat > "$TLS/$N.ext" <<EOF
subjectAltName=DNS:convoy-tls-$N,DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth,clientAuth
EOF
  openssl x509 -req -in "$TLS/$N.csr" -CA "$TLS/ca.crt" -CAkey "$TLS/ca.key" \
    -CAcreateserial -out "$TLS/$N.crt" -days 3650 -extfile "$TLS/$N.ext"
  cat "$TLS/$N.key" "$TLS/$N.crt" > "$TLS/$N.pem"
  chmod 600 "$TLS/$N.key" "$TLS/$N.pem"
  rm -f "$TLS/$N.csr" "$TLS/$N.ext"
done
rm -f "$TLS/ca.srl"
echo "[tls] CA + mTLS certs ready for: $NODES"