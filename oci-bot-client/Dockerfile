FROM debian:bookworm-slim

ARG TARGETARCH
ARG OCI_BOT_VERSION=v10.2.1
ARG OCI_BOT_SHA256_AMD64=0b2143100fc6e74a8f99691efdbd448842c699980f06b3e59255bf09e4601079
ARG OCI_BOT_SHA256_ARM64=935cbafb9775598cb15adab5e90aca29256d528b056a9d6ee5fa624c6dc2402e

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget ca-certificates procps && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Download the correct binary based on architecture
RUN set -eux; \
    if [ "$TARGETARCH" = "arm64" ]; then \
        ASSET="gz_client_bot_aarch.tar.gz"; \
        EXPECTED_SHA256="$OCI_BOT_SHA256_ARM64"; \
    elif [ "$TARGETARCH" = "amd64" ]; then \
        ASSET="gz_client_bot_x86_compatible.tar.gz"; \
        EXPECTED_SHA256="$OCI_BOT_SHA256_AMD64"; \
    else \
        echo "Unsupported architecture: $TARGETARCH" && exit 1; \
    fi; \
    TARBALL_URL="https://github.com/semicons/java_oci_manage/releases/download/${OCI_BOT_VERSION}/${ASSET}"; \
    wget -q -O /tmp/client_bot.tar.gz "$TARBALL_URL" && \
    echo "$EXPECTED_SHA256  /tmp/client_bot.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/client_bot.tar.gz -C /app && \
    rm -f /tmp/client_bot.tar.gz && \
    chmod +x /app/r_client && \
    rm -f /app/sh_client_bot.sh /app/client_config

EXPOSE 9527

ENTRYPOINT ["/app/r_client"]
CMD ["--configPath=/app/client_config", "--server.port=9527"]
