#!/usr/bin/env bash
set -euo pipefail

VAULT_CFG=/etc/vault/vault-agent-client.hcl
OUT_PEM=/output/client.pem
WORKDIR=/client
mkdir -p "$WORKDIR"

#──────── Lanzar Vault Agent ────────
vault agent -config="$VAULT_CFG" &
VAULT_AGENT_PID=$!

echo "⏳ Esperando a que aparezca $OUT_PEM ..."
while [[ ! -s $OUT_PEM ]]; do sleep 1; done
echo "✅ client.pem generado"

#──────── Extraer claves/certificados ────────
awk 'BEGIN{p=0}/-----BEGIN RSA PRIVATE KEY-----/{p=1}p;/-----END RSA PRIVATE KEY-----/{exit}' \
    "$OUT_PEM" > "$WORKDIR/client.key"

awk 'BEGIN{c=0}/-----BEGIN CERTIFICATE-----/{c++}c==1{print}/-----END CERTIFICATE-----/{if(c==1)exit}' \
    "$OUT_PEM" > "$WORKDIR/client.crt"

awk 'BEGIN{c=0}/-----BEGIN CERTIFICATE-----/{c++}c==2{print}/-----END CERTIFICATE-----/{if(c==2)exit}' \
    "$OUT_PEM" > "$WORKDIR/ca.crt"

openssl pkcs8 -topk8 -nocrypt \
        -in  /client/client.key \
        -out /client/client.key.pk8
cat /client/client.crt /client/client.key.pk8  > /client/client-keystore.pem
#──────── Copiar Root-CA si existe ────────
if [[ -f /certs/rootCA.pem ]]; then
  cp /certs/rootCA.pem "$WORKDIR/rootCA.pem"
else
  echo "[WARN] /certs/rootCA.pem no encontrado; usarás ca.crt como truststore"
  cp "$WORKDIR/ca.crt" "$WORKDIR/rootCA.pem"
fi
cat /client/ca.crt /client/rootCA.pem > /client/ca-chain.pem

#──────── Crear client.properties ────────
cat > "$WORKDIR/client.properties" <<EOF
security.protocol=SSL

ssl.keystore.type=PEM
ssl.keystore.location=/client/client-keystore.pem
ssl.truststore.type=PEM
ssl.truststore.location=/client/ca-chain.pem
EOF
echo "📝 client.properties creado"

echo "🏁 Contenedor listo.  Ejecuta utilidades Kafka con:"
echo "   kafka-console-producer.sh --bootstrap-server kafka:9093 --producer.config $WORKDIR/client.properties"
echo "   kafka-console-consumer.sh --bootstrap-server kafka:9093 --consumer.config $WORKDIR/client.properties ..."
echo
wait "$VAULT_AGENT_PID"
