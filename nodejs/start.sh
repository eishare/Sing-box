#!/bin/bash
export UUID=${UUID:-""}
export TUIC_PORT=${TUIC_PORT:-""}
export HY2_PORT=${HY2_PORT:-""}
export REALITY_PORT=${REALITY_PORT:-""}
export FILE_PATH=${FILE_PATH:-'./.npm'}

# ================== 北京时间 00:00 重启（无 root 兼容版）==================
schedule_restart() {
  local now_utc=$(date -u +%s)
  local today_beijing_midnight=$(TZ=Asia/Shanghai date -d "today 00:00:00" +%s)
  local tomorrow_beijing_midnight=$((today_beijing_midnight + 86400))
  local delay=$((tomorrow_beijing_midnight - now_utc))
  [ $delay -lt 0 ] && delay=$((delay + 86400))
  local hours=$((delay / 3600))
  local minutes=$(((delay % 3600) / 60))
  local seconds=$((delay % 60))
  local target_time=$(TZ=Asia/Shanghai date -d "@$tomorrow_beijing_midnight" '+%Y/%m/%d %H:%M:%S')

  echo -e "\n\e[1;33m[定时重启] 下次重启：${hours}小时${minutes}分${seconds}秒 后\e[0m"
  echo -e "\e[1;33m          目标时间：${target_time} (北京时间 00:00)\e[0m"

  (
    sleep "$delay"
    echo -e "\n\e[1;31m[定时重启] 北京时间 00:00，执行无 root 重启！\e[0m"
    # 无 root 环境下安全重启方式：通过自执行脚本
    bash "$0" &
    exit 0
  ) &
}
# ========================================================================

[ ! -d "${FILE_PATH}" ] && mkdir -p "${FILE_PATH}"

ARCH=$(uname -m)
BASE_URL=""
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

download_file() {
  local URL=$1
  local FILENAME=$2
  if command -v curl >/dev/null 2>&1; then
    curl -L -sS -o "$FILENAME" "$URL" && echo -e "\e[1;32m下载 $FILENAME (curl)\e[0m"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$FILENAME" "$URL" && echo -e "\e[1;32m下载 $FILENAME (wget)\e[0m"
  else
    echo -e "\e[1;31m未找到 curl 或 wget\e[0m"
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

# 生成 Reality 密钥
if [ -f "${FILE_PATH}/key.txt" ]; then
  private_key=$(grep "PrivateKey:" "${FILE_PATH}/key.txt" | awk '{print $2}')
  public_key=$(grep "PublicKey:" "${FILE_PATH}/key.txt" | awk '{print $2}')
else
  output=$("${FILE_MAP[sing-box]}" generate reality-keypair)
  echo "$output" > "${FILE_PATH}/key.txt"
  private_key=$(echo "$output" | awk '/PrivateKey:/ {print $2}')
  public_key=$(echo "$output" | awk '/PublicKey:/ {print $2}')
fi

# 生成证书
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
BNZB2nz49O6yRvh26B9npACOK/nuky9/BlgEgDZ54Ga3qEAxdeWv07Mi8hd5IR8U
m3oR/zQRIx7UmRmg4TKmjUzBRMB0GA1UdDgQWBQTV1cFID7UISE7PLTBRBfGbgrk
MNzAfBgNVHSMEGDAWgBTV1cFID7UISE7PLTBRBfGbgrkMNzAPBgNVHRMBAf8EBTA
DAQH/MAoGCCqGSM49BAMCA0cAMEQCIARDAJvg0vd/ytrQVvEcSm6XTlB+eQ6OFb9
LbLYL9Zi+AiffoMbi4y/0YUQlTtz7as9S8/lciBF5VCUoVIKS+vX2g==
-----END CERTIFICATE-----
EOF
else
  openssl ecparam -genkey -name prime256v1 -out "${FILE_PATH}/private.key" 2>/dev/null
  openssl req -new -x509 -days 3650 -key "${FILE_PATH}/private.key" -out "${FILE_PATH}/cert.pem" -subj "/CN=bing.com" 2>/dev/null
fi
chmod 600 "${FILE_PATH}/private.key"

# 生成 config.json
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
        \"server_name\": \"www.bing.com\",
        \"reality\": {
          \"enabled\": true,
          \"handshake\": {\"server\": \"www.bing.com\", \"server_port\": 443},
          \"private_key\": \"$private_key\",
          \"short_id\": [\"\"]
        }
      }
    }"; \
  )],
  "outbounds": [{"type": "direct"}]
}
EOF

# 启动 sing-box
nohup "${FILE_MAP[sing-box]}" run -c "${FILE_PATH}/config.json" > /dev/null 2>&1 &
sleep 2
echo -e "\e[1;32msing-box 已启动\e[0m"

# 启动定时重启
schedule_restart

# 保持运行
tail -f /dev/null
