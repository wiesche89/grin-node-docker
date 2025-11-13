FROM nginx:stable

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# User 'grin' nur, falls du ihn später brauchst – kannst du notfalls auch weglassen
RUN groupadd -r grin && useradd -r -g grin -d /data -s /bin/bash grin \
 && mkdir -p /data /app \
 && chown -R grin:grin /data /app \
 && chown -R grin:grin /usr/share/nginx /var/cache/nginx /var/log/nginx

# Qt WASM App ins Standard-Dokumentenverzeichnis von nginx kopieren
COPY build/WebAssembly_Qt_6_9_1_single_threaded-Release/ /usr/share/nginx/html/

# Deine App heißt grin-node-docker.html → als index.html verwenden
RUN cp /usr/share/nginx/html/grin-node-docker.html /usr/share/nginx/html/index.html

EXPOSE 80

# ENTRYPOINT/CMD kommen vom nginx-Base-Image (daemon off;)
