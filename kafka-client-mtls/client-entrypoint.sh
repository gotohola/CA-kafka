#!/bin/bash
set -e
# 1. Pide cert a Vault (apróle ya montado en /vault/)
TOKEN=$(curl -s --request POST --data "@/vault/login.json" http://vault:8200/v1/auth/approle/login | jq -r .auth.client_token)
CERT=$(curl -s -H "X-Vault-Token: $TOKEN" --data '{"common_name":"sensor1.client.kafka"}' http://vault:8200/v1/pki_int/issue/kafka-client | jq -r .data.certificate)
echo "$CERT" > /tmp/client.pem
# 2. Lanza productor o consumidor (modo demo):
python - <<'PY'
from confluent_kafka import Producer
p=Producer({'bootstrap.servers':'kafka:9093','security.protocol':'SSL',
            'ssl.certificate.location':'/tmp/client.pem','ssl.ca.location':'/certs/rootCA.pem'})
p.produce('sensors-data',key='demo',value='hello'); p.flush()
PY
