# =========================
# Stage 1: Qt WebAssembly Build (qmake + .pro, Submodule kommen aus Build-Context)
# =========================
FROM madmanfred/qt-webassembly AS wasm-builder

# Arbeitsverzeichnis im Builder
WORKDIR /src

# Alles aus dem Build-Context ins Image kopieren
# WICHTIG: Der Build-Context muss bereits alle Submodule enthalten!
COPY . .

# Qt WASM-Build über qmake (.pro) + make
# grin-node-docker.pro liegt im Repo-Root
RUN qmake grin-node-docker.pro CONFIG+=release \
 && make -j"$(nproc)"

# Build-Artefakte einsammeln (HTML/JS/WASM/DATA) nach /dist
RUN mkdir -p /dist \
 && cp ./*.html ./*.js ./*.wasm ./*.data /dist 2>/dev/null || true


# =========================
# Stage 2: Nginx Runtime mit fertiger WASM-App
# =========================
FROM nginx:stable

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Optionaler User 'grin' – wie in deinem bisherigen Dockerfile
RUN groupadd -r grin && useradd -r -g grin -d /data -s /bin/bash grin \
 && mkdir -p /data /app \
 && chown -R grin:grin /data /app \
 && chown -R grin:grin /usr/share/nginx /var/cache/nginx /var/log/nginx

# Die gesammelten WebAssembly-Artefakte aus Stage 1 ins nginx-Webroot kopieren
COPY --from=wasm-builder /dist/ /usr/share/nginx/html/

# index.html setzen:
# 1. Falls deine Hauptdatei grin-node-docker.html heißt → als index.html verwenden
# 2. Falls nicht: nimm einfach die erste gefundene .html-Datei
RUN set -e; \
    if [ -f /usr/share/nginx/html/grin-node-docker.html ]; then \
      cp /usr/share/nginx/html/grin-node-docker.html /usr/share/nginx/html/index.html; \
    elif [ ! -f /usr/share/nginx/html/index.html ]; then \
      first_html=$(ls /usr/share/nginx/html/*.html 2>/dev/null | head -n 1); \
      if [ -n "$first_html" ]; then \
        cp "$first_html" /usr/share/nginx/html/index.html; \
      fi; \
    fi

EXPOSE 80
# CMD/ENTRYPOINT kommen vom nginx-Base-Image (daemon off;)
