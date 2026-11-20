# Build from the repository root so the canonical contracts can be copied in:
#   docker build -f services/telemetry/Dockerfile -t openrc-telemetry .
FROM python:3.12.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    OPENRC_TELEMETRY_SCHEMA_DIR=/app/contracts \
    OPENRC_TELEMETRY_DATA_DIR=/data \
    OPENRC_TELEMETRY_RAW_DIR=/data/raw \
    OPENRC_TELEMETRY_AGGREGATES_DIR=/data/aggregates

WORKDIR /app
COPY services/telemetry/requirements.txt /app/requirements.txt
# requirements.txt also pins httpx (test client only); it is small and never imported at runtime.
RUN pip install -r requirements.txt

COPY research/telemetry/contracts/batch.schema.json research/telemetry/contracts/report.schema.json /app/contracts/
# check-release validates this canonical batch with the candidate tag (it looks beside the schema directory).
COPY research/telemetry/examples/batch.json /app/examples/batch.json
COPY services/telemetry/openrc_telemetry /app/openrc_telemetry

# Two volumes: /data/raw (48 h records; never back up, snapshot or replicate; tmpfs is acceptable) and
# /data/aggregates (ID-free tables and publication intents; the only thing to back up).
RUN useradd --system --uid 10001 --home-dir /nonexistent --shell /usr/sbin/nologin telemetry \
    && mkdir -p /data/raw /data/aggregates && chown -R telemetry:telemetry /data
VOLUME ["/data/raw", "/data/aggregates"]
USER telemetry

EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD ["python", "-c", "import urllib.request as u; u.urlopen('http://127.0.0.1:8787/healthz', timeout=2)"]

# Bind publicly inside the container only; publish the port to localhost and put a TLS proxy in front.
CMD ["python", "-m", "openrc_telemetry", "serve", "--host", "0.0.0.0", "--port", "8787"]
