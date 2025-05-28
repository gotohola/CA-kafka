FROM quay.io/strimzi/kafka:0.42.0-kafka-3.7.0

USER root

# utilidades mínimas
RUN microdnf install -y jq gettext unzip && microdnf clean all

# tini (init) – para orquestar los dos procesos
RUN curl -Lo /sbin/tini https://github.com/krallin/tini/releases/download/v0.19.0/tini-static \
    && chmod +x /sbin/tini

# Vault CLI
ARG VAULT_VERSION=1.17.6
RUN curl -sL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" \
    -o /tmp/vault.zip \
 && unzip /tmp/vault.zip -d /usr/local/bin \
 && rm /tmp/vault.zip

# plantillas / scripts
COPY vault-agent.hcl               /etc/vault/
COPY server.properties.tmpl        /opt/manual/server.properties.tmpl
COPY start-agent.sh start-kafka.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

ENTRYPOINT ["/sbin/tini","--","/usr/local/bin/start-agent.sh"]
