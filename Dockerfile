# ===========================================
# Stage 1: Qt/WASM-Build
# ===========================================
FROM forderud/qtwasm:v6.9.3 AS builder

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN git clone --branch main --single-branch https://github.com/wiesche89/grin-node-docker.git . \
 && git submodule update --init --recursive

ARG BUILD_CONFIG=Release

RUN mkdir -p build \
 && cd build \
 && /opt/Qt/bin/qt-cmake -G Ninja -DCMAKE_BUILD_TYPE=${BUILD_CONFIG} /src \
 && ninja \
 && mkdir -p /src/dist \
 && cp /src/build/grin-node-docker.html /src/dist/ \
 && cp /src/build/grin-node-docker.js /src/dist/ \
 && cp /src/build/grin-node-docker.wasm /src/dist/ \
 && cp /src/build/qtloader.js /src/dist/ \
 && cp /src/build/qtlogo.svg /src/dist/ \
 && cp /src/build/*.data /src/dist/ 2>/dev/null || true

# ===========================================
# Stage 2: nginx Runtime (nur fertige Artefakte)
# ===========================================
# ===========================================
# Stage 2: nginx Runtime (nur fertige Artefakte)
# ===========================================
FROM nginx:alpine

# nginx.conf aus dem repo
COPY --from=builder /src/nginx.conf /etc/nginx/conf.d/default.conf

WORKDIR /usr/share/nginx/html

# -> hier: die im Container gebauten Dateien übernehmen
COPY --from=builder /src/dist/ ./

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
