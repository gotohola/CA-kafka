#!/usr/bin/env bash
set -euo pipefail

mkdir -p /output /vault /etc/kafka/certs

echo "▶️  Lanzando Vault Agent…"
vault agent -config=/etc/vault/vault-agent.hcl &
VAULT_AGENT_PID=$!

echo "⏳ Esperando broker.pem…"
while [ ! -s /output/broker.pem ]; do sleep 1; done
echo "✅ broker.pem recibido"

# ── Procesar broker.pem ──────────────────────────────────────────
TMP=/tmp/tls; mkdir -p "$TMP"
cp /output/broker.pem "$TMP/"

# 1. extraer clave privada PEM
awk '/BEGIN RSA PRIVATE KEY/,/END RSA PRIVATE KEY/' "$TMP/broker.pem" > "$TMP/key.pem"

# 2. convertir a PKCS#8 (Kafka lo exige)
openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt \
        -in "$TMP/key.pem" -out "$TMP/key8.pem"

# 3. extraer certificado servido (primer bloque CERTIFICATE)
awk 'c==0 && /BEGIN CERTIFICATE/{c=1}
     c==1 {print}
     /END CERTIFICATE/{exit}' "$TMP/broker.pem" > "$TMP/cert.pem"

# 4. extraer CA intermedia (segundo bloque CERTIFICATE)
awk '
/BEGIN CERTIFICATE/ { n++ }
n==2, /END CERTIFICATE/ { print }
' "$TMP/broker.pem" > /etc/kafka/certs/rootCA.pem

# 5. ensamblar key+cert+chain → broker.pem definitivo
cat "$TMP/key8.pem" "$TMP/cert.pem" /etc/kafka/certs/rootCA.pem \
    > /etc/kafka/certs/broker.pem
chmod 640 /etc/kafka/certs/*.pem

echo "🔒 TLS listo:"
openssl x509 -in "$TMP/cert.pem" -noout -subject -issuer

# ── Señal para start-kafka.sh ───────────────────────────────────
touch /etc/kafka/certs/.tls_ready

# Lanzar Kafka (en foreground para que tini supervise)
exec /usr/local/bin/start-kafka.sh
