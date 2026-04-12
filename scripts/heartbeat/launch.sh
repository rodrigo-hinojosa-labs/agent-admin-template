#!/bin/bash
# Heartbeat Launch — Gestiona el timer de heartbeat (Linux systemd / macOS launchd)
# El nombre del agente se detecta automáticamente del workspace
# Uso: ./launch.sh {install|run|stop|uninstall|status|test} [--prompt "..."] [--interval "..."]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_FILE="$SCRIPT_DIR/heartbeat.conf"

# Detectar nombre del agente desde el path del workspace
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENT_NAME="$(basename "$WORKSPACE_DIR")"

# Cargar config
if [ ! -f "$CONF_FILE" ]; then
  echo "ERROR: $CONF_FILE no encontrado"
  exit 1
fi
source "$CONF_FILE"

# Detectar OS
OS="$(uname -s)"

# Nombres dinámicos basados en el agente
TIMER_NAME="${AGENT_NAME}-heartbeat"

if [ "$OS" = "Darwin" ]; then
  PLIST_NAME="cloud.rodribot.${TIMER_NAME}"
  PLIST_DIR="$HOME/Library/LaunchAgents"
  PLIST_FILE="$PLIST_DIR/$PLIST_NAME.plist"
else
  SYSTEMD_DIR="$HOME/.config/systemd/user"
  SERVICE_FILE="$SYSTEMD_DIR/${TIMER_NAME}.service"
  TIMER_FILE="$SYSTEMD_DIR/${TIMER_NAME}.timer"
fi

# Parsear argumentos
ACTION="${1:-help}"
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt) HEARTBEAT_PROMPT="$2"; shift 2 ;;
    --interval) HEARTBEAT_INTERVAL="$2"; shift 2 ;;
    --timeout) HEARTBEAT_TIMEOUT="$2"; shift 2 ;;
    --retries) HEARTBEAT_RETRIES="$2"; shift 2 ;;
    --notify-every) NOTIFY_SUCCESS_EVERY="$2"; shift 2 ;;
    *) shift ;;
  esac
done

notify() {
  local msg="$1"
  if [ -n "${NOTIFY_BOT_TOKEN:-}" ] && [ -n "${NOTIFY_CHAT_ID:-}" ]; then
    curl -s -X POST "https://api.telegram.org/bot${NOTIFY_BOT_TOKEN}/sendMessage" \
      -d chat_id="${NOTIFY_CHAT_ID}" \
      -d text="[Heartbeat:${AGENT_NAME}] $msg" > /dev/null 2>&1 || true
  fi
}

update_conf() {
  cat > "$CONF_FILE" << EOF
# Heartbeat — Configuración
# Agente: ${AGENT_NAME} (detectado automáticamente del workspace)
# Modificado por launch.sh el $(date '+%Y-%m-%d %H:%M:%S')

# Intervalo entre heartbeats (formato systemd: 30m, 1h, 15m, etc.)
HEARTBEAT_INTERVAL="$HEARTBEAT_INTERVAL"

# Timeout en segundos para cada ejecución de claude (default: 300)
HEARTBEAT_TIMEOUT="${HEARTBEAT_TIMEOUT:-300}"

# Reintentos si claude falla o timeout (default: 1)
HEARTBEAT_RETRIES="${HEARTBEAT_RETRIES:-1}"

# Notificar éxito cada N ejecuciones (0 = siempre, 5 = cada 5). Errores siempre notifican.
NOTIFY_SUCCESS_EVERY="${NOTIFY_SUCCESS_EVERY:-1}"

# Prompt que se ejecuta en cada heartbeat
HEARTBEAT_PROMPT="$HEARTBEAT_PROMPT"

# Bot de notificaciones Telegram
NOTIFY_BOT_TOKEN="$NOTIFY_BOT_TOKEN"
NOTIFY_CHAT_ID="$NOTIFY_CHAT_ID"
EOF
}

interval_to_seconds() {
  local val="${1:-30m}"
  local num="${val%[smhd]}"
  local unit="${val##*[0-9]}"
  case "$unit" in
    s) echo "$num" ;;
    m) echo $(( num * 60 )) ;;
    h) echo $(( num * 3600 )) ;;
    d) echo $(( num * 86400 )) ;;
    *) echo $(( num * 60 )) ;;
  esac
}

# ── INSTALL ──────────────────────────────────────────────
do_install() {
  echo "Agente detectado: ${AGENT_NAME}"

  if [ "$OS" = "Darwin" ]; then
    mkdir -p "$PLIST_DIR"
    local seconds
    seconds=$(interval_to_seconds "$HEARTBEAT_INTERVAL")
    cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$PLIST_NAME</string>
  <key>ProgramArguments</key>
  <array>
    <string>$SCRIPT_DIR/heartbeat.sh</string>
  </array>
  <key>StartInterval</key>
  <integer>$seconds</integer>
  <key>RunAtLoad</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/${TIMER_NAME}.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/${TIMER_NAME}.log</string>
</dict>
</plist>
EOF
    echo "Instalado: $PLIST_FILE"
  else
    mkdir -p "$SYSTEMD_DIR"
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=${AGENT_NAME} Heartbeat — ejecuta prompt en nueva sesión

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/heartbeat.sh
Environment=HOME=$HOME
Environment=PATH=$HOME/.nvm/versions/node/v24.14.1/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
EOF

    cat > "$TIMER_FILE" << EOF
[Unit]
Description=${AGENT_NAME} Heartbeat Timer

[Timer]
OnBootSec=5m
OnUnitActiveSec=$HEARTBEAT_INTERVAL
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable "${TIMER_NAME}.timer"
    echo "Instalado: ${TIMER_NAME}.service + ${TIMER_NAME}.timer"
  fi

  update_conf
  notify "Instalado — intervalo: $HEARTBEAT_INTERVAL"
  echo "Heartbeat instalado para '${AGENT_NAME}' — intervalo: $HEARTBEAT_INTERVAL"
}

# ── RUN ──────────────────────────────────────────────────
do_run() {
  update_conf

  if [ "$OS" = "Darwin" ]; then
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    do_install
    launchctl load "$PLIST_FILE"
  else
    do_install
    systemctl --user restart "${TIMER_NAME}.timer"
  fi

  notify "Activado — intervalo: $HEARTBEAT_INTERVAL"
  echo "Heartbeat activado para '${AGENT_NAME}' — intervalo: $HEARTBEAT_INTERVAL"
}

# ── STOP ─────────────────────────────────────────────────
do_stop() {
  if [ "$OS" = "Darwin" ]; then
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
  else
    systemctl --user stop "${TIMER_NAME}.timer" 2>/dev/null || true
  fi

  notify "Pausado"
  echo "Heartbeat pausado para '${AGENT_NAME}'"
}

# ── UNINSTALL ────────────────────────────────────────────
do_uninstall() {
  if [ "$OS" = "Darwin" ]; then
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    rm -f "$PLIST_FILE"
  else
    systemctl --user stop "${TIMER_NAME}.timer" 2>/dev/null || true
    systemctl --user disable "${TIMER_NAME}.timer" 2>/dev/null || true
    rm -f "$SERVICE_FILE" "$TIMER_FILE"
    systemctl --user daemon-reload
  fi

  notify "Desinstalado"
  echo "Heartbeat desinstalado para '${AGENT_NAME}'"
}

# ── STATUS ───────────────────────────────────────────────
do_status() {
  echo "=== Heartbeat: ${AGENT_NAME} ==="
  echo "Intervalo: $HEARTBEAT_INTERVAL"
  echo "Timeout: ${HEARTBEAT_TIMEOUT:-300}s"
  echo "Retries: ${HEARTBEAT_RETRIES:-1}"
  echo "Notify éxito cada: ${NOTIFY_SUCCESS_EVERY:-1} ejecuciones"
  echo "Prompt: ${HEARTBEAT_PROMPT:0:80}..."
  echo "OS: $OS"
  echo "Timer: ${TIMER_NAME}"
  echo ""

  if [ "$OS" = "Darwin" ]; then
    if launchctl list | grep -q "$PLIST_NAME"; then
      echo "Estado: ACTIVO"
      launchctl list "$PLIST_NAME" 2>/dev/null
    else
      echo "Estado: INACTIVO"
    fi
  else
    echo "=== Timer ==="
    systemctl --user status "${TIMER_NAME}.timer" 2>/dev/null || echo "Timer no instalado"
    echo ""
    echo "=== Próxima ejecución ==="
    systemctl --user list-timers "${TIMER_NAME}.timer" 2>/dev/null || true
  fi

  # Mostrar sesiones de heartbeat activas
  echo ""
  echo "=== Sesiones activas ==="
  tmux list-sessions 2>/dev/null | grep "${AGENT_NAME}-hb" || echo "Ninguna"
}

# ── TEST ─────────────────────────────────────────────────
do_test() {
  echo "Ejecutando heartbeat manualmente para '${AGENT_NAME}'..."
  "$SCRIPT_DIR/heartbeat.sh"
  notify "Ejecutado manualmente"
}

# ── HISTORY ──────────────────────────────────────────────
do_history() {
  local log_dir="$SCRIPT_DIR/logs"
  local history_file="$log_dir/heartbeat-history.log"
  local n="${1:-20}"

  echo "=== Historial: ${AGENT_NAME} (últimas $n) ==="
  echo ""

  if [ ! -f "$history_file" ]; then
    echo "Sin historial todavía."
    return
  fi

  printf "%-20s %-8s %-8s %-10s %s\n" "FECHA" "ESTADO" "DURACIÓN" "INTENTO" "PROMPT"
  printf "%-20s %-8s %-8s %-10s %s\n" "----" "------" "--------" "-------" "-----"
  tail -n "$n" "$history_file" | while IFS='|' read -r ts status duration attempt prompt; do
    printf "%-20s %-8s %-8s %-10s %s\n" "$ts" "$status" "$duration" "$attempt" "$prompt"
  done

  echo ""
  local total ok timeout error
  total=$(wc -l < "$history_file")
  ok=$(grep -c "|ok|" "$history_file" 2>/dev/null || echo 0)
  timeout=$(grep -c "|timeout|" "$history_file" 2>/dev/null || echo 0)
  error=$(grep -c "|error|" "$history_file" 2>/dev/null || echo 0)
  echo "Total: $total | OK: $ok | Timeout: $timeout | Error: $error"
}

# ── HELP ─────────────────────────────────────────────────
do_help() {
  cat << EOF
Heartbeat Launch — Gestiona el timer de heartbeat
Agente detectado: ${AGENT_NAME}

Uso: ./launch.sh <acción> [opciones]

Acciones:
  install     Instala el timer en el sistema (systemd/launchd)
  run         Activa el timer (acepta --prompt y --interval para cambiar config)
  stop        Pausa el timer
  uninstall   Desinstala completamente
  status      Muestra estado actual
  test        Ejecuta heartbeat una vez (sin timer)
  history     Muestra historial de ejecuciones (últimas 20 por defecto)

Opciones:
  --prompt "..."       Cambiar el prompt del heartbeat
  --interval "..."     Cambiar el intervalo (ej: 15m, 1h, 30m)
  --timeout "..."      Timeout en segundos (default: 300)
  --retries "..."      Reintentos si falla (default: 1)
  --notify-every "..." Notificar éxito cada N ejecuciones (default: 1, 0=siempre)

Ejemplos:
  ./launch.sh install
  ./launch.sh run --prompt "revisa Jira KAN" --interval "30m"
  ./launch.sh run --timeout 600 --retries 2
  ./launch.sh stop
  ./launch.sh status
  ./launch.sh history
EOF
}

# ── Main ─────────────────────────────────────────────────
case "$ACTION" in
  install)   do_install ;;
  run)       do_run ;;
  stop)      do_stop ;;
  uninstall) do_uninstall ;;
  status)    do_status ;;
  test)      do_test ;;
  history)   do_history ;;
  help|*)    do_help ;;
esac
