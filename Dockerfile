ARG PREBUILT_DIR=build/WebAssembly_Qt_6_10_1_single_threaded-Release

FROM nginx:alpine

ARG PREBUILT_DIR

WORKDIR /usr/share/nginx/html

RUN apk add --no-cache gettext

ENV CONTROLLER_PROXY=controller:8080

# nginx-Konfiguration (templatisiertes Proxy-Ziel)
COPY nginx.conf.template /etc/nginx/conf.d/default.conf.template

# Qt/WASM-Assets aus dem Build-Verzeichnis
COPY ${PREBUILT_DIR}/ ./

# 1) Translations aus dem QML-Ordner mit einpacken
#    (Pfad ggf. anpassen, wenn dein Ordner anders heißt)
COPY qml/translation ./translation

# 2) Qt-Logo überschreiben
#    Empfehlung: ein SVG im Repo haben, z.B. media/grin-node/logo.svg
COPY media/grin-node/logo.svg ./qtlogo.svg

# 3) Fonts mit einpacken
COPY fonts ./fonts

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh


EXPOSE 80
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
