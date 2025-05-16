FROM python:3.12-slim
RUN pip install --no-cache-dir confluent-kafka hvac jq
COPY client-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["/usr/local/bin/client-entrypoint.sh"]
