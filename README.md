# grin-node-docker

Qt dashboard for Grin Rust and Grin++, served through nginx. Requires
[grin-node-controller](https://github.com/wiesche89/grin-node-controller).

## Build

Install Qt for desktop and WebAssembly (`wasm_singlethread`), including Qt Charts.
Use the Qt and Emscripten versions in `releases.json`, as CI does.

```bash
git submodule update --init --recursive
EMSDK_VERSION=$(python3 -c 'import json; print(json.load(open("releases.json"))["emscripten"])')
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install "$EMSDK_VERSION"
./emsdk activate "$EMSDK_VERSION"
source ./emsdk_env.sh
cd ..
```

Set `QT_WASM_PATH` to your Qt `wasm_singlethread` directory, then build:

```bash
mkdir -p build/wasm
cd build/wasm
"$QT_WASM_PATH/bin/qmake" ../../grin-node-docker.pro -spec wasm-emscripten CONFIG+=release
make -j4
cd ../..
mkdir -p build/wasm-dist
cp build/wasm/{grin-node-docker.html,grin-node-docker.js,grin-node-docker.wasm,qtloader.js} build/wasm-dist/
docker build -t grin-ui .
```

Set `CONTROLLER_PROXY` to the controller's reachable `host:port` when starting
the container. The image serves the UI on port 80; it does not run a node.

## CI

`releases.json` defines the UI and toolchain versions.
Push to `main` to build new releases. Published versions are skipped.
Bump the UI version to release changes.

CI tests the UI and nginx before publishing amd64 and arm64 images.
New releases also update `main` and the commit tag.
Pull requests only build and test. WASM files are available as a workflow artifact.

Docker uses `build/wasm-dist` by default. To use another build directory, pass
`--build-arg PREBUILT_DIR=build/<kit-directory>`.

## Umbrel authentication

Pass the same `CONTROLLER_PASSWORD` to UI and controller; start the controller
with `--require-auth`. On Umbrel 2.0, set `TRUSTED_PROXY_MODE=host` to trust
the container's default IPv4 gateway. For older Umbrel versions, use
`TRUSTED_PROXY_MODE=container` and `TRUSTED_PROXY_HOST=<app-id>_app_proxy_1`.
Umbrel derives the secret in `exports.sh`; users only need their Umbrel login.

nginx allows the resolved proxy IP and adds credentials to `/api/` requests.
`/wallet/v2/foreign` retains the wallet's node credentials. This requires the
updated controller. Missing credentials or proxy resolution stop startup.
Restart the app if the proxy IP changes. Without `CONTROLLER_PASSWORD`, standalone
behavior is unchanged. The generated nginx config is mode 0600.

Test with Python 3, nginx and gettext:

```sh
python3 tests/proxy_auth.py /path/to/nginx /path/to/envsubst
```

## License

Project source: Apache-2.0. Third-party components retain their licenses:
QRGen.js (Kazuhiko Arase, MIT), Noto fonts (SIL OFL), and Qt.
Qt Charts uses GPL-3.0 in this build; distributed UI binaries must retain those terms.
See `licenses/`, `fonts/OFL.txt` and https://doc.qt.io/qt-6/qtcharts-index.html#licenses.
