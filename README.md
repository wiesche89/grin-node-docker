# grin-node-docker

Qt dashboard for Grin Rust and Grin++, served through nginx. Requires
[grin-node-controller](https://github.com/wiesche89/grin-node-controller).

## Build

Install Qt 6.10.1 for desktop and WebAssembly (`wasm_singlethread`), including
Qt Charts, and Emscripten 4.0.7. These versions match CI.

```bash
git submodule update --init --recursive
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install 4.0.7
./emsdk activate 4.0.7
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

GitHub Actions builds and tests the UI, checks nginx, then publishes amd64/arm64
images. Main builds use `main` and commit tags; a Git tag such as `v0.2.17`
publishes image tag `0.2.17`. Pull requests only build and test.
WASM assets are also available as a workflow artifact.

Docker uses `build/wasm-dist` by default. To use another build directory, pass
`--build-arg PREBUILT_DIR=build/<kit-directory>`.

## License

Project source: Apache-2.0. Third-party components retain their licenses:
QRGen.js (Kazuhiko Arase, MIT), Noto fonts (SIL OFL), and Qt.
Qt Charts uses GPL-3.0 in this build; distributed UI binaries must retain those terms.
See `licenses/`, `fonts/OFL.txt` and https://doc.qt.io/qt-6/qtcharts-index.html#licenses.
