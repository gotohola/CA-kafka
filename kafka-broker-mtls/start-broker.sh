#!/bin/bash
set -e

export KAFKA_SSL_KEYSTORE_TYPE=PEM
export KAFKA_SSL_KEYSTORE_LOCATION=/etc/kafka/certs/broker.pem
export KAFKA_SSL_TRUSTSTORE_TYPE=PEM
export KAFKA_SSL_TRUSTSTORE_LOCATION=/etc/kafka/certs/rootCA.pem
export KAFKA_LISTENERS="SSL://0.0.0.0:9093"
export KAFKA_ADVERTISED_LISTENERS="SSL://kafka:9093"
export KAFKA_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM=""

mkdir -p /etc/kafka/certs /vault
cp /certs/rootCA.pem /etc/kafka/certs/rootCA.pem

# Arranca Vault Agent (renueva cert)
vault agent -config=/etc/vault/vault-agent.hcl &

echo "⏳ Esperando a que broker.pem exista..."
until [ -s /etc/kafka/certs/broker.pem ]; do sleep 1; done

exec /opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties

