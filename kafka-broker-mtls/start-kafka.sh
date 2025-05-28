#!/usr/bin/env bash
set -euo pipefail

# 1. Esperar a que Vault haya terminado
while [ ! -f /etc/kafka/certs/.tls_ready ]; do sleep 1; done

# 2. Variables por defecto (puedes sobreescribir en docker-compose)
export NODE_ID="${NODE_ID:-0}"
export CONTROLLER_QUORUM_VOTERS="${CONTROLLER_QUORUM_VOTERS:-0@${HOSTNAME}:9094}"
export ADVERTISED_HOST="${ADVERTISED_HOST:-${HOSTNAME}}"

mkdir -p /opt/kafka/config/manual
# 3. Generar server.properties
envsubst <<'EOF' > /opt/kafka/config/manual/server.properties
process.roles=broker,controller
node.id=${NODE_ID}
controller.listener.names=CONTROLLER
listeners=CONTROLLER://0.0.0.0:9094,SSL://0.0.0.0:9093
listener.security.protocol.map=CONTROLLER:PLAINTEXT,SSL:SSL
inter.broker.listener.name=SSL
controller.quorum.voters=${CONTROLLER_QUORUM_VOTERS}
advertised.listeners=SSL://${ADVERTISED_HOST}:9093
log.dirs=/var/lib/kafka/data

ssl.keystore.type=PEM
ssl.keystore.location=/etc/kafka/certs/broker.pem
ssl.truststore.type=PEM
ssl.truststore.location=/etc/kafka/certs/rootCA.pem
ssl.endpoint.identification.algorithm=
EOF

echo "📝 server.properties generado:"
grep -E '^(node.id|controller.quorum|advertised)' /opt/kafka/config/manual/server.properties

# 4. Formateo KRaft si es primera vez
if [ ! -f /var/lib/kafka/data/meta.properties ]; then
  CID=$(uuidgen | tr -d -)
  echo "📦 Formateando almacenamiento KRaft CLUSTER_ID=$CID"
  /opt/kafka/bin/kafka-storage.sh format -t "$CID" \
        -c /opt/kafka/config/manual/server.properties
fi

echo "🚀 Arrancando Kafka…"
exec /opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/manual/server.properties
