ARG PREBUILT_DIR=build/WebAssembly_Qt_6_9_1_single_threaded-Release

FROM nginx:alpine

ARG PREBUILT_DIR

WORKDIR /usr/share/nginx/html

# Deine nginx-Konfiguration aus dem Repository
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Die schon erstellten Qt/WASM-Assets vom Host kopieren.
# Der COPY schlägt fehl (und der Build ab), wenn der Ordner nicht existiert.
COPY ${PREBUILT_DIR}/ ./

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
