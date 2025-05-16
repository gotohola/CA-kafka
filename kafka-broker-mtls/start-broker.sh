#!/bin/bash
set -e
vault agent -config=/etc/vault/vault-agent.hcl &
/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
