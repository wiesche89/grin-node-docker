# Nginx + glibc (Debian-basiert)
FROM nginx:stable

ENV DEBIAN_FRONTEND=noninteractive

# Tools + benötigte Runtime-Libs für grin
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl sed tar \
      libtinfo6 libncursesw6 \
    && rm -rf /var/lib/apt/lists/*

ENV GRIN_HOME=/data \
    GRIN_CHAIN_TYPE=Testnet \
    PATH=/usr/local/bin:$PATH

# --- User 'grin' anlegen ---
RUN groupadd -r grin && useradd -r -g grin -d /data -s /bin/bash grin \
 && mkdir -p /data /app \
 && chown -R grin:grin /data /app \
 && chown -R grin:grin /usr/share/nginx /var/cache/nginx /var/log/nginx

# Eigene Nginx-Configs einspielen:
#   - Hauptdatei (hier kommt 'user grin;' rein!)
COPY nginx/nginx.conf /etc/nginx/nginx.conf
#   - Server-Block
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

# Deine Qt WASM App kopieren
COPY build/WebAssembly_Qt_6_9_1_single_threaded-Release/ /usr/share/nginx/html/

# Grin-Tarball liegt NEBEN dem Dockerfile
COPY grin-v5.3.3_rebuild-linux-x86_64.tar.gz /tmp/grin.tar.gz

# Entpacken und Binary nach /usr/local/bin/grin installieren
RUN tar -xzf /tmp/grin.tar.gz -C /tmp \
 && GRIN_BIN_PATH="$(tar -tzf /tmp/grin.tar.gz | grep -m1 -E '(^|/)(grin)$')" \
 && test -n "$GRIN_BIN_PATH" \
 && install -m 0755 "/tmp/${GRIN_BIN_PATH}" /usr/local/bin/grin \
 && rm -f /tmp/grin.tar.gz

# Startskript einspielen (CRLF->LF & ausführbar machen)
COPY start.sh /app/start.sh
RUN sed -i 's/\r$//' /app/start.sh && chmod +x /app/start.sh \
 && chown grin:grin /app/start.sh

EXPOSE 80 13413 13414
VOLUME ["/data"]

# Container bleibt root (damit Port 80 bindbar ist und wir Dienste gezielt droppen können)
ENTRYPOINT ["/app/start.sh"]
