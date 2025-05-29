# Dockerfile.kafka-client
FROM alpine:3.20

# Instala Vault y utilidades necesarias
RUN apk add --no-cache curl jq openssl unzip && \
    curl -sL https://releases.hashicorp.com/vault/1.17.6/vault_1.17.6_linux_amd64.zip -o vault.zip && \
    unzip vault.zip -d /usr/local/bin && \
    chmod +x /usr/local/bin/vault && \
    rm vault.zip

# Copiamos configuración del agente Vault
COPY vault-agent-client.hcl /etc/vault/vault-agent-client.hcl

# Entrypoint que lanza el agente
ENTRYPOINT ["/usr/local/bin/vault", "agent", "-config=/etc/vault/vault-agent-client.hcl"]
