#!/bin/bash
set -e

: ${VAULT_ADDR:=http://vault:8200}
ROLE_ID=$(cat /vault/client/role_id)
SECRET_ID=$(cat /vault/client/secret_id)

# ---------- Vault Agent CFG ----------
cat >/client/agent.hcl <<EOF
pid_file = "/tmp/vault-agent.pid"

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path   = "/vault/client/role_id"
      secret_id_file_path = "/vault/client/secret_id"
    }
  }

  sink "file" {
    config = {
      path = "/client/token"
    }
  }
}

template {
  contents = <<EOT
{{- with secret "pki_int/issue/kafka-client" "common_name=app1.client.kafka" -}}
{{ .Data.certificate }}
{{ .Data.private_key }}
{{ .Data.issuing_ca }}
{{- end }}
EOT
  destination = "/client/client.pem"
  perms = "0644"
}
EOF
# ---------- Lanzar agente -------------
vault agent -config=/client/agent.hcl &
VAULT_AGENT_PID=$!

# Esperar a que se genere client.pem
echo "⏳ Esperando client.pem ..."
while [ ! -s /client/client.pem ]; do sleep 1; done
echo "✅ client.pem listo"

# Copiamos rootCA para truststore
cp /certs/rootCA.pem /client/rootCA.pem

# ---------- Producir y consumir --------
CONFIG=/client/client.properties
cat >$CONFIG <<EOF
security.protocol=SSL
ssl.truststore.type=PEM
ssl.truststore.location=/client/rootCA.pem
ssl.keystore.type=PEM
ssl.keystore.location=/client/client.pem
ssl.endpoint.identification.algorithm=
EOF

TOPIC=testtls
echo "Creando topic $TOPIC ..."
kafka-topics --bootstrap-server kafka:9093 \
             --create --if-not-exists --topic $TOPIC \
             --command-config $CONFIG \
             --replication-factor 1 --partitions 1

echo "Enviando mensaje ..."
echo "hola_mtls" | kafka-console-producer \
        --topic $TOPIC --bootstrap-server kafka:9093 \
        --producer.config $CONFIG

echo "Consumiendo ..."
kafka-console-consumer \
        --topic $TOPIC --from-beginning --max-messages 1 \
        --bootstrap-server kafka:9093 --consumer.config $CONFIG

kill $VAULT_AGENT_PID
