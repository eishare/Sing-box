#!/bin/bash

# ==================== 变量定义 ====================
export UUID=${UUID:-''}
export TUIC_PORT=${TUIC_PORT:-''}
export HY2_PORT=${HY2_PORT:-''}
export REALITY_PORT=${REALITY_PORT:-''}
export FILE_PATH=${FILE_PATH:-'./.npm'}
export NAME=${NAME:-''}

# 读取 .env（若存在）
if [ -f ".env" ]; then
    set -o allexport
    source <(grep -v '^#' .env | sed 's/^export //')
    set +o allexport
fi

# 创建工作目录
[ ! -d "${FILE_PATH}" ] && mkdir -p "${FILE_PATH}"

# ==================== 下载核心二进制 ====================
ARCH=$(uname -m) && FILE_INFO=()
if [ "$ARCH" = "arm" ] || [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    BASE_URL="https://arm64.ssss.nyc.mn"
elif [ "$ARCH" = "amd64" ] || [ "$ARCH" = "x86_64" ]; then
    BASE_URL="https://amd64.ssss.nyc.mn"
elif [ "$ARCH" = "s390x" ]; then
    BASE_URL="https://s390x.ssss.nyc.mn"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

FILE_INFO+=("$BASE_URL/sb web" "$BASE_URL/bot bot")
[ -n "$TUIC_PORT" ]      && FILE_INFO+=("$BASE_URL/tuic tuic")
[ -n "$HY2_PORT" ]       && FILE_INFO+=("$BASE_URL/hy2 hy2")
[ -n "$REALITY_PORT" ]   && FILE_INFO+=("$BASE_URL/reality reality")

declare -A FILE_MAP
generate_random_name() { local chars=abcdefghijklmnopqrstuvwxyz1234567890; local name=""; for i in {1..6}; do name+="${chars:RANDOM%${#chars}:1}"; done; echo "$name"; }
download_file() { local URL=$1 NEW_FILENAME=$2; if command -v curl >/dev/null 2>&1; then curl -L -sS -o "$NEW_FILENAME" "$URL"; elif command -v wget >/dev/null 2>&1; then wget -q -O "$NEW_FILENAME" "$URL"; else echo "Neither curl nor wget available"; exit 1; fi; }
for entry in "${FILE_INFO[@]}"; do
    URL=$(echo "$entry" | cut -d' ' -f1)
    RAND_NAME=$(generate_random_name)
    NEW_NAME="${FILE_PATH}/$RAND_NAME"
    download_file "$URL" "$NEW_NAME"
    chmod +x "$NEW_NAME"
    FILE_MAP[$(echo "$CHMOD +x "$NEW_NAME"
    FILE_MAP[$(echo "$entry" | cut -d' ' -f2)]="$NEW_NAME"
done

# ==================== 生成 Reality 密钥对 ====================
if [ -f "${FILE_PATH}/key.txt" ]; then
    private_key=$(grep "PrivateKey:" "${FILE_PATH}/key.txt" | awk '{print $2}')
    public_key=$(grep "PublicKey:" "${FILE_PATH}/key.txt" | awk '{print $2}')
    if [ -n "$private_key" ] && [ -n "$public_key" ]; then
        true
    else
        output=$("${FILE_MAP[web]}" generate reality-keypair)
        echo "$output" > "${FILE_PATH}/key.txt"
        private_key=$(echo "$output" | awk '/PrivateKey:/ {print $2}')
        public_key=$(echo "$output" | awk '/PublicKey:/ {print $2}')
    fi
else
    output=$("${FILE_MAP[web]}" generate reality-keypair)
    echo "$output" > "${FILE_PATH}/key.txt"
    private_key=$(echo "$output" | awk '/PrivateKey:/ {print $2}')
    public_key=$(echo "$output" | awk '/PublicKey:/ {print $2}')
fi

# ==================== 生成自签名证书 ====================
if command -v openssl >/dev/null 2>&1; then
    openssl ecparam -genkey -name prime256v1 -out "${FILE_PATH}/private.key"
    openssl req -new -x509 -days 3650 -key "${FILE_PATH}/private.key" -out "${FILE_PATH}/cert.pem" -subj "/CN=bing.com"
else
    cat > "${FILE_PATH}/private.key" <<'EOF'
-----BEGIN EC PARAMETERS-----
BgqghkqBQQQBBw==
-----END EC PARAMETERS-----
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIM4792SEtPqIt1ywqTd/0bYidBqpYY/+siNnfBYsdUYoaOGCSqGSIb3
AwEHoUQDQgAELkHafPj07rJG+HboH2ekAI4r+e6TL38GWASANnngZreoQDF16ARa
/TsyLyFoPkhLxSbehH/NBEjHtSZGaDhMqQ==
-----END EC PRIVATE KEY-----
EOF
    cat > "${FILE_PATH}/cert.pem" <<'EOF'
-----BEGIN CERTIFICATE-----
MIIBejCCASGgAwIBAgIUFweQL3556PNJLp/veCFxGNj9crkwCgYIKoZIzj0EAwIw
EzERMA8GA1UEAwwIYmluZy5jb20wHhcNMjUwMTEwMDczNjU4WhcNMzUwMTEwMDcz
NjU4WjATMREwDwYDVQQDDAhiaW5nLmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEP
ADCCAQoCggEBANZB2nz49O6yRvh26B9npACOK/nuky9/BlgEgDZ54Ga3qEAxdeWv
07Mi8hD5IR8Um3oR/zQRHx7UmRmg4TKmjUzBRMB0GA1UdDgQWBQTV1cFID7UISE7PLTB
BfGbgkrMNzAfBgNVHSMEGDAWgBTV1cFID7UISE7PLTBRAf8EBTADAQH/MAoGCCqGSM49
BAMCA0cAMEQCIDAJvg0vd/ytrQVvEcSm6TlB+eQ6OFb9LbLYL9i+AiffoMbi4y/0YUSlTtz7as9S8/lciBF5VCUoVIKS+vX2g==
-----END CERTIFICATE-----
EOF
fi

# ==================== 生成 config.json ====================
cat > "${FILE_PATH}/config.json" <<EOF
{
  "log": { "disabled": true, "level": "error", "timestamp": true },
  "inbounds": [
EOF

# ---- 占位 vmess（不启用） ----
cat >> "${FILE_PATH}/config.json" <<'EOF'
    {
      "tag": "vmess-ws-in",
      "type": "vmess",
      "listen": "::",
      "listen_port": 0,
      "users": [ { "uuid": "" } ],
      "transport": { "type": "ws", "path": "/vmess-argo", "early_data_header_name": "Sec-WebSocket-Protocol" }
    }
EOF

# ---- Tuic ----
if [ -n "$TUIC_PORT" ]; then
  cat >> "${FILE_PATH}/config.json" <<EOF
,
    {
      "tag": "tuic-in",
      "type": "tuic",
      "listen": "::",
      "listen_port": ${TUIC_PORT},
      "users": [ { "uuid": "${UUID}", "password": "admin" } ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": [ "h3" ],
        "certificate_path": "${FILE_PATH}/cert.pem",
        "key_path": "${FILE_PATH}/private.key"
      }
    }
EOF
fi

# ---- Hysteria2 ----
if [ -n "$HY2_PORT" ]; then
  cat >> "${FILE_PATH}/config.json" <<EOF
,
    {
      "tag": "hysteria2-in",
      "type": "hysteria2",
      "listen": "::",
      "listen_port": ${HY2_PORT},
      "users": [ { "password": "${UUID}" } ],
      "masquerade": "https://bing.com",
      "tls": {
        "enabled": true,
        "alpn": [ "h3" ],
        "certificate_path": "${FILE_PATH}/cert.pem",
        "key_path": "${FILE_PATH}/private.key"
      }
    }
EOF
fi

# ---- Reality (vless) ----
if [ -n "$REALITY_PORT" ]; then
  cat >> "${FILE_PATH}/config.json" <<EOF
,
    {
      "tag": "vless-reality-vision",
      "type": "vless",
      "listen": "::",
      "listen_port": ${REALITY_PORT},
      "users": [ { "uuid": "${UUID}", "flow": "xtls-rprx-vision" } ],
      "tls": {
        "enabled": true,
        "server_name": "www.nazhumi.com",
        "reality": {
          "enabled": true,
          "handshake": { "server": "www.nazhumi.com", "server_port": 443 },
          "private_key": "${private_key}",
          "short_id": [ "" ]
        }
      }
    }
EOF
fi

cat >> "${FILE_PATH}/config.json" <<'EOF'
  ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ],
  "route": { "final": "direct" }
}
EOF

# ==================== 启动主进程 + 北京时间 00:00 重启 ====================

MAIN_PID=""

start_main() {
    if [ -e "${FILE_MAP[web]}" ]; then
        echo -e "\e[1;32m启动主进程...\e[0m"
        nohup "${FILE_MAP[web]}" run -c "${FILE_PATH}/config.json" > /dev/null 2>&1 &
        MAIN_PID=$!
        echo -e "\e[1;32m主进程 PID: $MAIN_PID\e[0m"
    fi

    # 生成订阅链接
    IP=$(curl -s --max-time 2 ipv4.ip.sb || curl -s --max-time 1 api.ipify.org || { ipv6=$(curl -s --max-time 1 ipv6.ip.sb); echo "[$ipv6]"; } || echo "X.X.X.X")
    ISP=$(curl -s --max-time 2 https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed 's/ /_/g' || echo "0.0")
    custom_name() { [ -n "$NAME" ] && echo "${NAME}_${ISP}" || echo "$ISP"; }

    > "${FILE_PATH}/list.txt"
    [ -n "$TUIC_PORT" ] && echo "tuic://${UUID}:admin@${IP}:${TUIC_PORT}?sni=www.bing.com&alpn=h3&congestion_control=bbr#$(custom_name)" >> "${FILE_PATH}/list.txt"
    [ -n "$HY2_PORT" ] && echo "hysteria2://${UUID}@${IP}:${HY2_PORT}/?sni=www.bing.com&alpn=h3&insecure=1#$(custom_name)" >> "${FILE_PATH}/list.txt"
    [ -n "$REALITY_PORT" ] && echo "vless://${UUID}@${IP}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.nazhumi.com&fp=firefox&pbk=${public_key}&type=tcp&headerType=none#$(custom_name)" >> "${FILE_PATH}/list.txt"

    base64 "${FILE_PATH}/list.txt" | tr -d '\n' > "${FILE_PATH}/sub.txt"
    echo -e "\n\e[1;32m${FILE_PATH}/sub.txt 已生成\e[0m"
    cat "${FILE_PATH}/list.txt"
}

# 北京时间 00:00 重启
schedule_beijing_midnight_restart() {
    local now=$(date -u +%s)
    local beijing_offset=28800  # UTC+8
    local beijing_now=$((now + beijing_offset))
    local today_midnight=$((beijing_now - (beijing_now % 86400)))
    local next_midnight=$((today_midnight + 86400))
    local delay=$((next_midnight - now))

    local next_time=$(date -d "@$next_midnight" -u '+%Y-%m-%d %H:%M:%S')
    echo -e "\e[1;33m[定时重启] 下次重启时间：${next_time} (北京时间 00:00)\e[0m"

    sleep "$delay"

    echo -e "\e[1;31m[定时重启] 北京时间 00:00，执行重启！\e[0m"
    if [ -n "$MAIN_PID" ] && kill -0 "$MAIN_PID" 2>/dev/null; then
        kill "$MAIN_PID"
        echo "已终止旧进程 PID: $MAIN_PID"
    fi

    rm -f "${FILE_PATH}/config.json" "${FILE_PATH}/sub.txt" "${FILE_PATH}/list.txt"
    exec bash "$0"  # 重新运行脚本
}

# 启动
start_main
schedule_beijing_midnight_restart &

# 保持容器运行
tail -f /dev/null
