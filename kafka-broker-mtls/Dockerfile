FROM quay.io/strimzi/kafka:0.42.0-kafka-3.7.0
USER root
RUN microdnf install -y jq openssl && microdnf clean all
COPY vault-agent.hcl /etc/vault/
COPY start-broker.sh  /usr/local/bin/
RUN chmod +x /usr/local/bin/start-broker.sh
ENTRYPOINT ["/usr/local/bin/start-broker.sh"]
