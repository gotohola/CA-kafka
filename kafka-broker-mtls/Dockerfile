FROM quay.io/strimzi/kafka:0.42.0-kafka-3.7.0
USER root

# Instala solo lo necesario sin tocar curl
RUN microdnf install -y jq openssl unzip && microdnf clean all

# Instala Vault Agent
ENV VAULT_VERSION=1.17.6
RUN curl -sL https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip \
      -o vault.zip \
 && unzip vault.zip -d /usr/local/bin \
 && chmod +x /usr/local/bin/vault \
 && rm vault.zip

COPY vault-agent.hcl /etc/vault/
COPY start-broker.sh  /usr/local/bin/
RUN chmod +x /usr/local/bin/start-broker.sh

ENTRYPOINT ["/usr/local/bin/start-broker.sh"]
