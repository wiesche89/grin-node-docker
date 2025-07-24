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

