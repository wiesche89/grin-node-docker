# =========================
# Stage 1: Qt WebAssembly Build (qmake + .pro, Source from GitHub main)
# =========================
FROM wiesche89/qt6-wasm:6.9.1-emsdk3.1.70 AS wasm-builder

ENV DEBIAN_FRONTEND=noninteractive

# Install git to fetch the repository + submodules
RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Working directory for the build
WORKDIR /src

# Clone source from GitHub (main branch) and initialize all submodules
RUN git clone --branch main --single-branch \
    https://github.com/wiesche89/grin-node-docker.git . \
 && git submodule update --init --recursive

# Qt WASM build using qmake (.pro) + make
# grin-node-docker.pro is located in the repo root
RUN qmake grin-node-docker.pro CONFIG+=release \
 && make -j"$(nproc)"

# Collect build artifacts (HTML/JS/WASM/DATA) into /dist
RUN mkdir -p /dist \
 && cp ./*.html ./*.js ./*.wasm ./*.data /dist 2>/dev/null || true


# =========================
# Stage 2: Nginx Runtime with built WASM app
# =========================
FROM nginx:stable

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Optional 'grin' user, similar to previous setup
RUN groupadd -r grin && useradd -r -g grin -d /data -s /bin/bash grin \
 && mkdir -p /data /app \
 && chown -R grin:grin /data /app \
 && chown -R grin:grin /usr/share/nginx /var/cache/nginx /var/log/nginx

# Copy WebAssembly artifacts from builder stage into nginx web root
COPY --from=wasm-builder /dist/ /usr/share/nginx/html/

# Ensure index.html exists
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
# CMD/ENTRYPOINT inherited from nginx base image