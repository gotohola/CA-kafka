FROM alpine:3.20

ARG KAFKA_VERSION=3.7.0
ARG SCALA_VERSION=2.13

# ▸ utilidades básicas + Java + Vault
RUN apk add --no-cache \
      bash curl jq openssl unzip openjdk17-jre-headless tar tini

# ▸ Vault CLI
RUN curl -sL https://releases.hashicorp.com/vault/1.17.6/vault_1.17.6_linux_amd64.zip -o vault.zip && \
    unzip vault.zip -d /usr/local/bin && \
    chmod +x /usr/local/bin/vault && \
    rm vault.zip

# ▸ Kafka CLI (usamos el archivo de archive.apache.org)
RUN curl -sL -o /tmp/kafka.tgz https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz && \
    tar -xzf /tmp/kafka.tgz -C /opt && \
    ln -s /opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION} /opt/kafka && \
    rm /tmp/kafka.tgz

ENV PATH="/opt/kafka/bin:${PATH}"

# ─── Vault Agent CFG + script de arranque ──────────────────────────────
COPY vault-agent-client.hcl /etc/vault/vault-agent-client.hcl
COPY start-client.sh        /usr/local/bin/
RUN chmod +x /usr/local/bin/start-client.sh

ENTRYPOINT ["/sbin/tini","--","start-client.sh"]
CMD ["bash"]          # por defecto abre una shell interactiva
