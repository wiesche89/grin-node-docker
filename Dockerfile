# ===========================================
# Stage 1: Qt/WASM-Build
# ===========================================
FROM forderud/qtwasm:v6.9.3 AS builder

WORKDIR /project
COPY . /project

ARG BUILD_CONFIG=Release

# Qt WASM-Toolchain ohne PThreads bauen, damit SharedArrayBuffer nicht benötigt wird
RUN mkdir -p build \
 && cd build \
 && QT_WASM_PTHREADS=OFF \
    EMCC_CFLAGS="-s USE_PTHREADS=0" \
    EMCC_CXXFLAGS="-s USE_PTHREADS=0" \
    EMCC_LINK_FLAGS="-s USE_PTHREADS=0" \
    /opt/Qt/bin/qt-cmake -G Ninja -DCMAKE_BUILD_TYPE=${BUILD_CONFIG} /project \
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

# Übernehme die nginx-Konfiguration aus dem Quellcode
COPY --from=builder /project/nginx.conf /etc/nginx/conf.d/default.conf

WORKDIR /usr/share/nginx/html

# Fertige Qt/WASM-Dateien bereitstellen
COPY --from=builder /project/dist/ ./

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
