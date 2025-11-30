ARG PREBUILT_DIR=build/WebAssembly_Qt_6_9_1_single_threaded-Release

FROM nginx:alpine

ARG PREBUILT_DIR

WORKDIR /usr/share/nginx/html

# nginx-Konfiguration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Qt/WASM-Assets aus dem Build-Verzeichnis
COPY ${PREBUILT_DIR}/ ./

# 1) Translations aus dem QML-Ordner mit einpacken
#    (Pfad ggf. anpassen, wenn dein Ordner anders heißt)
COPY qml/translation ./qml/translation

# 2) Qt-Logo überschreiben
#    Empfehlung: ein SVG im Repo haben, z.B. media/grin-node/logo.svg
COPY media/grin-node/logo.svg ./qtlogo.svg

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
