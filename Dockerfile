# ===========================================
# Stage 1: Qt/WASM-Build
# ===========================================
FROM forderud/qtwasm:v6.9.3 AS builder

WORKDIR /project
COPY . /project

ARG BUILD_CONFIG=Release

RUN mkdir -p build \
 && cd build \
 && /opt/Qt/bin/qt-cmake -G Ninja -DCMAKE_BUILD_TYPE=${BUILD_CONFIG} /project \
 && ninja \
 && mkdir -p /project/dist \
 && cd /project/build \
 && release_dir=$(find . -maxdepth 1 -type d -name 'WebAssembly*' | head -n 1) \
 && release_dir=${release_dir#./} \
 && [ -n "$release_dir" ] \
 && cp -r "$release_dir"/. /project/dist/

# ===========================================
# Stage 2: nginx Runtime (nur fertige Artefakte)
# ===========================================
FROM nginx:alpine

# Deine funktionierende nginx.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf

WORKDIR /usr/share/nginx/html

# -> hier: die im Container gebauten Dateien übernehmen
COPY --from=builder /project/dist/ ./

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
