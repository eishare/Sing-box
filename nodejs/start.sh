#!/bin/bash
set -e

# ================== 环境变量 ==================
export TUIC_PORT=${TUIC_PORT:-""}
export HY2_PORT=${HY2_PORT:-""}
export REALITY_PORT=${REALITY_PORT:-""}
export FILE_PATH=${FILE_PATH:-'./.npm'}
export CRON_FILE="/tmp/crontab_singbox"
DATA_PATH="$(pwd)/singbox_data"
mkdir -p "$DATA_PATH"

mkdir -p "${FILE_PATH}"

# ================== UUID 固定保存 ==================
UUID_FILE="${FILE_PATH}/uuid.txt"

if [ -f "$UUID_FILE" ]; then
  UUID=$(cat "$UUID_FILE")
  echo "[UUID] 已读取固定 UUID: $UUID"
else
  UUID=$(cat /proc/sys/kernel/random/uuid)
  echo "$UUID" > "$UUID_FILE"
  chmod 600 "$UUID_FILE"
  echo "[UUID] 首次生成 UUID: $UUID"
fi

# ================== 架构检测 & 下载 sing-box ==================
ARCH=$(uname -m)
if [[ "$ARCH" == "arm"* ]] || [[ "$ARCH" == "aarch64" ]]; then
  BASE_URL="https://arm64.ssss.nyc.mn"
elif [[ "$ARCH" == "amd64"* ]] || [[ "$ARCH" == "x86_64" ]]; then
  BASE_URL="https://amd64.ssss.nyc.mn"
elif [[ "$ARCH" == "s390x" ]]; then
  BASE_URL="https://s390x.ssss.nyc.mn"
else
  echo "不支持的架构: $ARCH"
  exit 1
fi

FILE_INFOS=("sb sing-box")
declare -A FILE_MAP

download_file() {
  local URL=$1
  local FILENAME=$2
  if command -v curl >/dev/null 2>&1; then
    curl -L -sS -o "$FILENAME" "$URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$FILENAME" "$URL"
  else
    echo "未找到 curl 或 wget"
    exit 1
  fi
}

for entry in "${FILE_INFOS[@]}"; do
  URL=$(echo "$entry" | cut -d ' ' -f1)
  NAME=$(echo "$entry" | cut -d ' ' -f2)
  NEW_NAME="${FILE_PATH}/$(head /dev/urandom | tr -dc a-z0-9 | head -c6)"
  download_file "${BASE_URL}/${URL}" "$NEW_NAME"
  chmod +x "$NEW_NAME"
  FILE_MAP[$NAME]="$NEW_NAME"
done

# ================== 固定 Reality 密钥 ==================
KEY_FILE="${FILE_PATH}/key.txt"
if [ -f "$KEY_FILE" ]; then
  private_key=$(grep "PrivateKey:" "$KEY_FILE" | awk '{print $2}')
  public_key=$(grep "PublicKey:"  "$KEY_FILE" | awk '{print $2}')
else
  output=$("${FILE_MAP[sing-box]}" generate reality-keypair)
  echo "$output" > "$KEY_FILE"
  private_key=$(echo "$output" | awk '/PrivateKey:/ {print $2}')
  public_key=$(echo "$output" | awk '/PublicKey:/  {print $2}')
  chmod 600 "$KEY_FILE"
fi

# ================== 生成证书 ==================
if ! command -v openssl >/dev/null 2>&1; then
  cat > "${FILE_PATH}/private.key" <<'EOF'
-----BEGIN EC PARAMETERS-----
BgqghkjOPQQBw==
-----END EC PARAMETERS-----
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIM4792SEtPqIt1ywqTd/0bYidBqpYV/+siNnfBYsdUYsAoGCCqGSM49
AwEHoUQDQgAE1kHafPj07rJG+HboH2ekAI4r+e6TL38GWASAnngZreoQDF16ARa
/TsyLyFoPkhTxSbehH/OBEjHtSZGaDhMqQ==
-----END EC PRIVATE KEY-----
EOF
  cat > "${FILE_PATH}/cert.pem" <<'EOF'
-----BEGIN CERTIFICATE-----
MIIBejCCASGgAwIBAgIUFWeQL3556PNJLp/veCFxGNj9crkwCgYIKoZIzj0EAwIw
EzERMA8GA1UEAwwIYmluZy5jb20wHhcNMjUwMTAxMDEwMTAwWhcNMzUwMTAxMDEw
MTAwWjATMREwDwYDVQQDDAhiaW5nLmNvbTBNBgqgGzM9AgEGCCqGSM49AwEHA0IA
BNZB2nz49O6yRvh26B9npACOK/nuky9/BlgEgDZ54Ga3qEAxdeWv07Mi8h
d5IR8Um3oR/zQRIx7UmRmg4TKmjUzBRMB0GA1UdDgQWBQTV1cFID7UISE7PLTBR
BfGbgrkMNzAfBgNVHSMEGDAWgBTV1cFID7UISE7PLTBRBfGbgrkMNzAPBgNVHRMB
Af8EBTADAQH/MAoGCCqGSM49BAMCA0cAMEQCIARDAJvg0vd/ytrQVvEcSm6XTlB+
eQ6OFb9LbLYL9Zi+AiffoMbi4y/0YUQlTtz7as9S8/lciBF5VCUoVIKS+vX2g==
-----END CERTIFICATE-----
EOF
else
  openssl ecparam -genkey -name prime256v1 -out "${FILE_PATH}/private.key" 2>/dev/null
  openssl req -new -x509 -days 3650 -key "${FILE_PATH}/private.key" -out "${FILE_PATH}/cert.pem" -subj "/CN=bing.com" 2>/dev/null
fi

chmod 600 "${FILE_PATH}/private.key"

# ================== 生成 config.json ==================
cat > "${FILE_PATH}/config.json" <<EOF
{
  "log": { "disabled": true },
  "inbounds": [$( \
    [ "$TUIC_PORT" != "" ] && [ "$TUIC_PORT" != "0" ] && echo "{
      \"type\": \"tuic\",
      \"listen\": \"::\",
      \"listen_port\": $TUIC_PORT,
      \"users\": [{\"uuid\": \"$UUID\", \"password\": \"admin\"}],
      \"congestion_control\": \"bbr\",
      \"tls\": {\"enabled\": true, \"alpn\": [\"h3\"], \"certificate_path\": \"${FILE_PATH}/cert.pem\", \"key_path\": \"${FILE_PATH}/private.key\"}
    },"; \
    [ "$HY2_PORT" != "" ] && [ "$HY2_PORT" != "0" ] && echo "{
      \"type\": \"hysteria2\",
      \"listen\": \"::\",
      \"listen_port\": $HY2_PORT,
      \"users\": [{\"password\": \"$UUID\"}],
      \"masquerade\": \"https://bing.com\",
      \"tls\": {\"enabled\": true, \"alpn\": [\"h3\"], \"certificate_path\": \"${FILE_PATH}/cert.pem\", \"key_path\": \"${FILE_PATH}/private.key\"}
    },"; \
    [ "$REALITY_PORT" != "" ] && [ "$REALITY_PORT" != "0" ] && echo "{
      \"type\": \"vless\",
      \"listen\": \"::\",
      \"listen_port\": $REALITY_PORT,
      \"users\": [{\"uuid\": \"$UUID\", \"flow\": \"xtls-rprx-vision\"}],
      \"tls\": {
        \"enabled\": true,
        \"server_name\": \"www.nazhumi.com\",
        \"reality\": {
          \"enabled\": true,
          \"handshake\": {\"server\": \"www.nazhumi.com\", \"server_port\": 443},
          \"private_key\": \"$private_key\",
          \"short_id\": [\"\"]
        }
      }
    }"; \
  )],
  "outbounds": [{"type": "direct"}]
}
EOF

# ================== 启动 sing-box（函数） ==================
start_singbox() {
  "${FILE_MAP[sing-box]}" run -c "${FILE_PATH}/config.json" > /dev/null 2>&1 &
  SINGBOX_PID=$!
  sleep 2
  echo "[SING-BOX] 启动完成 PID=$SINGBOX_PID"
}

start_singbox

# ================== 监控 sing-box（掉线自动重启） ==================
monitor_singbox() {
  while true; do
    wait "$SINGBOX_PID" 2>/dev/null || true
    echo "[监控] 检测到 sing-box 退出 → 3 秒后重启..."
    sleep 3
    start_singbox
  done
}
monitor_singbox &

# ================== 每日北京时间 0 点重启 ==================
schedule_restart() {
  echo "[定时重启] 已启动（北京时间 00:00 自动重启）"
  LAST_RESTART_DAY=-1

  while true; do
    now_ts=$(date +%s)
    beijing_ts=$((now_ts + 28800))
    beijing_hour=$(( (beijing_ts / 3600) % 24 ))
    beijing_min=$(( (beijing_ts / 60) % 60 ))
    beijing_day=$(( beijing_ts / 86400 ))

    if [ "$beijing_hour" -eq 0 ] &&
       [ "$beijing_min" -eq 3 ] &&
       [ "$beijing_day" -ne "$LAST_RESTART_DAY" ]; then

      echo "[定时重启] ✓ 到达北京时间 00:03 → 重启 sing-box..."
      kill "$SINGBOX_PID" 2>/dev/null || true
      LAST_RESTART_DAY=$beijing_day
      sleep 70
    fi

    sleep 20
  done
}
schedule_restart &

# ================== 防止容器退出 ==================
echo "[系统] sing-box 已启动，保持运行中..."
while true; do sleep 3600; done
