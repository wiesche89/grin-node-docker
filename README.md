# grin-node-docker

## 📦 Installation

### 1 Qt 6.9.2 installieren
- Qt Online Installer benutzen  
  **→ Component → Qt 6.9.2 → WebAssembly auswählen**

---

### 2️ Python installieren
- **Python 3.8 oder höher** installieren

---

### 3️ EMSDK installieren
```bash
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
emsdk install 3.1.70
emsdk activate 3.1.70 --permanent
emsdk_env```


### 4 Qt Config
- WebAssemply Kit
https://thinkinginqt.com/doc/qtcreator/creator-setup-webassembly.html
(Important: Qt Creator must be restarted after EMSDK has been installed.)


### 5 Docker
Build docker image
```docker build -t grin-wasm .```

Start docker container
```docker run --rm -p 8081:80 -p 13413:13413 -p 13414:13414 --name grin-wasm grin-wasm```

Testing
```docker exec -it grin-wasm sh -lc "T=\`cat \$GRIN_HOME/test/.api_secret 2>/dev/null || echo ''\`; echo '{\"jsonrpc\":\"2.0\",\"method\":\"get_status\",\"params\":[],\"id\":1}' | curl -i -u grin:\$T -H 'Content-Type: application/json' --data @- http://127.0.0.1:13413/v2/owner || true"```

## CI

GitHub Actions builds the UI with Qt 6.10.1 and Emscripten 4.0.7, checks nginx,
then publishes amd64/arm64 images. Main builds use `main` and commit tags;
a Git tag such as `v0.2.16` publishes image tag `0.2.16`. Pull requests only build
and test. WASM assets are also available as a workflow artifact.

Docker uses `build/wasm-dist` by default. For an existing Qt Creator build, pass
`--build-arg PREBUILT_DIR=build/<kit-directory>`.
