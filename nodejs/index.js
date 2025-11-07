#!/usr/bin/env node
/**
 * =========================================
 * TUIC + Hysteria2 + Reality 独立部署
 * 仅 2 文件 | 手动输入 | 北京时间重启
 * 避开 sing-box | TUIC 跳过证书
 * =========================================
 */
import { execSync, spawn } from "child_process";
import fs from "fs";
import https from "https";
import crypto from "crypto";

// ================== 【手动设置区域】==================
// 请修改下方双引号内的值（不要删引号！）
const UUID = "94d6d70f-c2cd-455d-b00d-dab94953a9ab";     // 修改这里！
const TUIC_PORT = "";                               // 修改这里！留 "" 或 "0" 则不启用
const HY2_PORT = "14233";                                // 修改这里！留 "" 或 "0" 则不启用
const REALITY_PORT = "14233";                            // 修改这里！留 "" 或 "0" 则不启用
// ==================================================

const FILE_PATH = "./.npm";
fs.mkdirSync(FILE_PATH, { recursive: true });

// 解析端口
const parsePort = (p) => {
  if (p === "" || p === "0") return 0;
  const n = Number(p);
  return (Number.isInteger(n) && n > 0 && n <= 65535) ? n : null;
};
const tuicPort = parsePort(TUIC_PORT);
const hy2Port = parsePort(HY2_PORT);
const realityPort = parsePort(REALITY_PORT);

// 校验
if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(UUID)) {
  console.error("UUID 格式错误！");
  process.exit(1);
}
if ([tuicPort, hy2Port, realityPort].every(p => p === null)) {
  console.error("至少启用一个端口！");
  process.exit(1);
}

// ================== 北京时间 00:00 重启 ==================
function scheduleBeijingMidnightRestart() {
  const now = new Date();
  const beijing = new Date(now.toLocaleString("en-US", { timeZone: "Asia/Shanghai" }));
  let target = new Date(beijing);
  target.setHours(0, 0, 0, 0);
  if (beijing >= target) target.setDate(target.getDate() + 1);
  const delay = target - beijing;

  console.log(`\n[定时重启] 下次重启：${target.toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' })}`);

  setTimeout(() => {
    console.log("[定时重启] 北京时间 00:00，执行重启！");
    process.exit(0);
  }, delay);
}

// ================== 工具函数 ==================
const fileExists = (p) => fs.existsSync(p);
const execSafe = (cmd) => { try { return execSync(cmd, { encoding: "utf8" }).trim(); } catch { return ""; } };
const randomStr = () => crypto.randomBytes(16).toString("hex");

// ================== 获取公网 IP ==================
async function getPublicIP() {
  const sources = ["https://api.ipify.org", "https://ifconfig.me", "https://ipv4.icanhazip.com"];
  for (const url of sources) {
    try {
      const ip = await new Promise((resolve) => {
        https.get(url, { timeout: 3000 }, (res) => {
          let data = ""; res.on("data", d => data += d); res.on("end", () => resolve(data.trim()));
        }).on("error", () => resolve(""));
      });
      if (/^(\d+\.){3}\d+$/.test(ip) && !/^(10\.|172\.(1[6-9]|2[0-9]|3[1])|192\.168\.|127\.)/.test(ip)) {
        console.log(`公网 IP: ${ip}`);
        return ip;
      }
    } catch {}
  }
  return "127.0.0.1";
}

// ================== 下载文件 ==================
async function download(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    https.get(url, (res) => {
      if (res.statusCode !== 200) return reject(`HTTP ${res.statusCode}`);
      res.pipe(file);
      file.on("finish", () => { file.close(); resolve(); });
    }).on("error", reject);
  });
}

// ================== 生成证书 ==================
function generateCert() {
  const cert = `${FILE_PATH}/cert.pem`, key = `${FILE_PATH}/private.key`;
  if (fileExists(cert) && fileExists(key)) return { cert, key };
  console.log("生成自签名证书...");
  execSafe(`openssl ecparam -genkey -name prime256v1 -out "${key}"`);
  execSafe(`openssl req -new -x509 -days 3650 -key "${key}" -out "${cert}" -subj "/CN=www.bing.com"`);
  fs.chmodSync(key, 0o600);
  return { cert, key };
}

// ================== 部署 TUIC ==================
async function deployTuic(port, ip) {
  if (port <= 0) return null;
  console.log(`部署 TUIC 到端口 ${port}...`);
  const bin = `${FILE_PATH}/tuic-server`;
  if (!fileExists(bin)) {
    await download("https://github.com/EAimTY/tuic/releases/download/tuic-server-1.0.0/tuic-server-1.0.0-x86_64-linux", bin);
    fs.chmodSync(bin, 0o755);
  }

  const password = randomStr();
  const { cert, key } = generateCert();

  const config = `
[server]
address = "0.0.0.0:${port}"
certificate = "${cert}"
private_key = "${key}"
log_level = "warn"

[users]
"${UUID}" = "${password}"
  `.trim();
  fs.writeFileSync(`${FILE_PATH}/tuic.toml`, config);

  spawn(bin, ["-c", `${FILE_PATH}/tuic.toml`], { stdio: "ignore" });
  const link = `tuic://${UUID}:${password}@${ip}:${port}?sni=www.bing.com&congestion_control=bbr&alpn=h3&allowInsecure=1#TUIC-FR`;
  fs.appendFileSync(`${FILE_PATH}/list.txt`, link + "\n");
  console.log("TUIC 节点已启动");
  return link;
}

// ================== 部署 Hysteria2 ==================
async function deployHy2(port, ip) {
  if (port <= 0) return null;
  console.log(`部署 Hysteria2 到端口 ${port}...`);
  const bin = `${FILE_PATH}/hysteria2`;
  if (!fileExists(bin)) {
    await download("https://github.com/apernet/hysteria/releases/download/app%2Fv2.6.0/hysteria-linux-amd64", bin);
    fs.chmodSync(bin, 0o755);
  }

  const password = randomStr();
  const { cert, key } = generateCert();

  const yaml = `
listen: :${port}
auth:
  type: password
  password: ${password}

tls:
  cert: ${cert}
  key: ${key}

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
  `.trim();
  fs.writeFileSync(`${FILE_PATH}/hy2.yaml`, yaml);

  spawn(bin, ["server", "-c", `${FILE_PATH}/hy2.yaml`], { stdio: "ignore" });
  const link = `hysteria2://${password}@${ip}:${port}/?sni=www.bing.com&insecure=1#Hysteria2-FR`;
  fs.appendFileSync(`${FILE_PATH}/list.txt`, link + "\n");
  console.log("Hysteria2 节点已启动");
  return link;
}

// ================== 部署 Reality ==================
async function deployReality(port, ip) {
  if (port <= 0) return null;
  console.log(`部署 Reality 到端口 ${port}...`);
  const bin = `${FILE_PATH}/xray`;
  if (!fileExists(bin)) {
    await download("https://github.com/XTLS/Xray-core/releases/download/v1.8.23/Xray-linux-64.zip", `${FILE_PATH}/xray.zip`);
    execSafe(`unzip -o "${FILE_PATH}/xray.zip" xray -d "${FILE_PATH}"`);
    fs.unlinkSync(`${FILE_PATH}/xray.zip`);
    fs.chmodSync(bin, 0o755);
  }

  const shortId = crypto.randomBytes(4).toString("hex");
  const { privateKey, publicKey } = JSON.parse(execSafe(`${bin} x25519`));

  const config = {
    log: { loglevel: "warning" },
    inbounds: [{
      port: port,
      protocol: "vless",
      settings: { clients: [{ id: UUID, flow: "xtls-rprx-vision" }], decryption: "none" },
      streamSettings: {
        network: "tcp",
        security: "reality",
        realitySettings: {
          show: false,
          dest: "www.nazhumi.com:443",
          xver: 0,
          serverNames: ["www.nazhumi.com"],
          privateKey,
          minClientVer: "",
          maxClientVer: "",
          maxTimeDiff: 0,
          shortIds: [shortId],
          publicKey,
          fingerprint: "chrome"
        }
      },
      sniffing: { enabled: true, destOverride: ["http", "tls"] }
    }],
    outbounds: [{ protocol: "freedom" }]
  };
  fs.writeFileSync(`${FILE_PATH}/reality.json`, JSON.stringify(config, null, 2));

  spawn(bin, ["run", "-c", `${FILE_PATH}/reality.json`], { stdio: "ignore" });
  const link = `vless://${UUID}@${ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.nazhumi.com&fp=chrome&pbk=${publicKey}&sid=${shortId}&type=tcp#Reality-FR`;
  fs.appendFileSync(`${FILE_PATH}/list.txt`, link + "\n");
  console.log("Reality 节点已启动");
  return link;
}

// ================== 主流程 ==================
async function main() {
  console.log("启动 TUIC / Hysteria2 / Reality 节点...");
  console.log(`UUID: ${UUID}`);
  console.log(`TUIC: ${tuicPort || "关闭"} | HY2: ${hy2Port || "关闭"} | Reality: ${realityPort || "关闭"}`);

  scheduleBeijingMidnightRestart();

  const ip = await getPublicIP();
  fs.writeFileSync(`${FILE_PATH}/list.txt`, "");

  await Promise.all([
    deployTuic(tuicPort, ip),
    deployHy2(hy2Port, ip),
    deployReality(realityPort, ip)
  ]);

  const txt = fs.readFileSync(`${FILE_PATH}/list.txt`, "utf8").trim();
  fs.writeFileSync(`${FILE_PATH}/sub.txt`, Buffer.from(txt).toString("base64"));
  console.log("\n订阅链接（明文）：");
  console.log(txt || "无节点启用");
  console.log(`\n订阅文件：${FILE_PATH}/sub.txt（base64）`);

  setInterval(() => {}, 1 << 30);
}

main().catch(console.error);
