#!/bin/sh
set -eu

: "${GRIN_BIN:=/usr/local/bin/grin}"
: "${GRIN_HOME:=/data}"
: "${WAIT_TIMEOUT:=120}"

# Fest auf Testnet
GRIN_CHAIN_TYPE="Testnet"
CHAIN_DIR="test"

echo "[i] GRIN_HOME=$GRIN_HOME  GRIN_CHAIN_TYPE=$GRIN_CHAIN_TYPE ($CHAIN_DIR)"
mkdir -p "$GRIN_HOME" /var/cache/nginx /var/log/nginx /usr/share/nginx/html
export GRIN_HOME GRIN_CHAIN_TYPE

# Alles Nginx-/Data-Relevante dem User 'grin' geben (Volume kann root:root sein)
chown -R grin:grin "$GRIN_HOME" /var/cache/nginx /var/log/nginx /usr/share/nginx/html || true

cd "$GRIN_HOME"
CFG="$GRIN_HOME/grin-server.toml"

# 1) Config erzeugen, falls fehlt (als 'grin')
if [ ! -f "$CFG" ]; then
  echo "[i] generating config in $GRIN_HOME …"
  su -s /bin/sh -c "$GRIN_BIN server config || true" grin
fi

# 2) chain_type auf Testnet erzwingen (als 'grin')
su -s /bin/sh -c "
  if grep -q '^chain_type\\s*=' '$CFG'; then
    sed -i -E 's|^chain_type\\s*=.*$|chain_type = \"Testnet\"|' '$CFG'
  else
    if grep -q '^\\[server\\]' '$CFG'; then
      sed -i 's|\\[server\\]|[server]\nchain_type = \"Testnet\"|' '$CFG'
    else
      printf '\n[server]\nchain_type = \"Testnet\"\n' >> '$CFG'
    fi
  fi
" grin

# 3) TUI ausschalten + API nach außen binden (als 'grin')
su -s /bin/sh -c "
  if grep -q '^run_tui\\s*=' '$CFG'; then
    sed -i -E 's|^run_tui\\s*=.*$|run_tui = false|' '$CFG'
  else
    if grep -q '^\\[server\\]' '$CFG'; then
      sed -i 's|\\[server\\]|[server]\nrun_tui = false|' '$CFG'
    else
      printf '\n[server]\nrun_tui = false\n' >> '$CFG'
    fi
  fi

  if grep -q '^api_http_addr\\s*=' '$CFG'; then
    sed -i -E 's|^api_http_addr\\s*=.*$|api_http_addr = \"0.0.0.0:13413\"|' '$CFG'
  else
    if grep -q '^\\[server\\]' '$CFG'; then
      sed -i 's|\\[server\\]|[server]\napi_http_addr = \"0.0.0.0:13413\"|' '$CFG'
    else
      printf '\n[server]\napi_http_addr = \"0.0.0.0:13413\"\\n' >> '$CFG'
    fi
  fi
" grin

# 4) Node starten (server run) + Logs mitschreiben (als 'grin')
echo "[i] starting: $GRIN_BIN server run (Testnet)"
su -s /bin/sh -c "
  cd '$GRIN_HOME'
  '$GRIN_BIN' server run >> '$GRIN_HOME/grin.out.log' 2>&1 & echo \$! > '$GRIN_HOME/grin.pid'
" grin
GRIN_PID="$(cat "$GRIN_HOME/grin.pid")"

# Watchdog: wenn grin stirbt, Container beenden
( while kill -0 "$GRIN_PID" 2>/dev/null; do sleep 2; done; echo '[!] grin exited'; exit 1 ) &

# 5) Healthcheck: sobald HTTP-Code ≠ 000 -> OK
FOREIGN_SECRET_FILE="$GRIN_HOME/$CHAIN_DIR/.foreign_api_secret"
AUTH_OPT=""
if [ -f "$FOREIGN_SECRET_FILE" ]; then
  TOK="$(cat "$FOREIGN_SECRET_FILE" 2>/dev/null || true)"
  [ -n "$TOK" ] && AUTH_OPT="-u grin:$TOK"
fi

printf "[i] Waiting for API http://127.0.0.1:13413/v2/foreign … "
i=0; code="000"
while [ $i -lt "$WAIT_TIMEOUT" ]; do
  code="$(curl -s -o /dev/null -w '%{http_code}' $AUTH_OPT http://127.0.0.1:13413/v2/foreign || echo 000)"
  [ "$code" != "000" ] && break
  i=$((i+1)); sleep 1; printf "."
done
if [ "$code" = "000" ]; then
  echo "FAILED"
  LOG="$GRIN_HOME/$CHAIN_DIR/grin-server.log"
  echo "[i] tail $LOG:"; [ -f "$LOG" ] && tail -n 100 "$LOG" || echo "(no log yet)"
  echo "[i] tail $GRIN_HOME/grin.out.log:"; [ -f "$GRIN_HOME/grin.out.log" ] && tail -n 100 "$GRIN_HOME/grin.out.log" || echo "(no out log yet)"
  exit 1
fi
echo "OK ($code)"

# 6) Nginx starten (Master root; Worker laufen als 'grin' via /etc/nginx/nginx.conf)
echo "[i] Starting Nginx …"
exec nginx -g 'daemon off;'
