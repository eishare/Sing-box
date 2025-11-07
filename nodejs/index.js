#!/usr/bin/env node
/**
 * =========================================
 * TUIC + Hysteria2 + Reality 一键部署
 * 仅需上传 node.js + package.json
 * 北京时间每天 00:00 自动重启
 * 订阅输出：./.npm/sub.txt
 * 
 *    每次部署前务必修改此区域！
 * =========================================
 */
import { execSync, spawn } from "child_process";
import fs from "fs";
import https from "https";
import crypto from "crypto";

// ================== 【手动设置区域】==================
// 请修改下方双引号内的值（不要删引号！）
const UUID = "";                                    // 修改这里！
const TUIC_PORT = "";                               // 修改这里！留 "" 或 "0" 则不启用
const HY2_PORT = "";                                // 修改这里！留 "" 或 "0" 则不启用
const REALITY_PORT = "";                            // 修改这里！留 "" 或 "0" 则不启用
// ==================================================

// 解析端口（支持字符串）
const parsePort = (p) => {
  if (p === "" || p === "0") return 0;
  const n = Number(p);
  return (Number.isInteger(n) && n > 0 && n <= 65535) ? n : null;
};

const tuicPort = parsePort(TUIC_PORT);
const hy2Port = parsePort(HY2_PORT);
const realityPort = parsePort(REALITY_PORT);

// 校验 UUID
if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(UUID)) {
  console.error("\nUUID 格式错误！请检查顶部设置");
  process.exit(1);
}

// 校验端口
if (tuicPort === null || hy2Port === null || realityPort === null) {
  console.error("\n端口必须是 1~65535 的数字，或留空/0 表示不启用！");
  process.exit(1);
}

const FILE_PATH = "./.npm";
fs.mkdirSync(FILE_PATH, { recursive: true });

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

// ================== 获取公网 IP ==================
async function getPublicIP() {
  const sources = ["https://api.ipify.org", "https://ifconfig.me", "https://icanhazip.com"];
  for (const url of sources) {
    try {
      const ip = await new Promise((resolve) => {
        https.get(url, { timeout: 3000 }, (res) => {
          let data = ""; res.on("data", d => data += d); res.on("end", () => resolve(data.trim()));
        }).on("error", () => resolve(""));
      });
      if (/^(\d+\.){3}\d+$/.test(ip) && !/^(10\.|172\.(1[6-9]|2[0-9]|3[1])|192\.168\.)/.test(ip)) {
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
  execSafe(`openssl req -new -x509 -days 3650 -key "${key}" -out "${cert}" -subj "/CN=bing.com"`);
  fs.chmodSync(key, 0o600);
  return { cert, key };
}

// ================== 下载 sing-box ==================
async function downloadSingBox() {
  const bin = `${FILE_PATH}/sing-box`;
  if (fileExists(bin)) return bin;
  console.log("下载 sing-box...");
  const arch = process.arch === "arm64" ? "arm64" : "amd64";
  const url = `https://${arch}.ssss.nyc.mn/sb`;
  await download(url, bin);
  fs.chmodSync(bin, 0o755);
  return bin;
}

// ================== 生成配置 ==================
async function generateConfig(ip) {
  const { cert, key } = generateCert();
  const bin = await downloadSingBox();

  // Reality 密钥
  let private_key = "", public_key = "";
  const keyFile = `${FILE_PATH}/reality.txt`;
  if (fileExists(keyFile)) {
    const lines = fs.readFileSync(keyFile, "utf8").split("\n");
    private_key = lines[0].split(": ")[1] || "";
    public_key = lines[1].split(": ")[1] || "";
  }
  if (!private_key) {
    const output = execSafe(`${bin} generate reality-keypair`);
    [private_key, public_key] = output.split("\n").map(l => l.split(": ")[1]);
    fs.writeFileSync(keyFile, output);
  }

  const inbounds = [];

  if (tuicPort > 0) inbounds.push({
    type: "tuic", listen: "::", listen_port: tuicPort,
    users: [{ uuid: UUID, password: "admin" }],
    congestion_control: "bbr",
    tls: { enabled: true, alpn: ["h3"], certificate_path: cert, key_path: key }
  });

  if (hy2Port > 0) inbounds.push({
    type: "hysteria2", listen: "::", listen_port: hy2Port,
    users: [{ password: UUID }],
    masquerade: "https://bing.com",
    tls: { enabled: true, alpn: ["h3"], certificate_path: cert, key_path: key }
  });

  if (realityPort > 0) inbounds.push({
    type: "vless", listen: "::", listen_port: realityPort,
    users: [{ uuid: UUID, flow: "xtls-rprx-vision" }],
    tls: { enabled: true, server_name: "www.nazhumi.com", reality: {
      enabled: true, handshake: { server: "www.nazhumi.com", server_port: 443 },
      private_key, short_id: [""]
    }}
  });

  if (inbounds.length === 0) {
    console.log("所有端口未启用，退出");
    process.exit(0);
  }

  const config = { log: { disabled: true }, inbounds, outbounds: [{ type: "direct" }], route: { final: "direct" } };
  fs.writeFileSync(`${FILE_PATH}/config.json`, JSON.stringify(config, null, 2));
  return { bin, public_key };
}

// ================== 生成订阅 ==================
function generateSub(ip, { public_key }) {
  const list = [];

  if (tuicPort > 0) list.push(`tuic://${UUID}:admin@${ip}:${tuicPort}?sni=www.bing.com&alpn=h3&congestion_control=bbr#FR`);
  if (hy2Port > 0) list.push(`hysteria2://${UUID}@${ip}:${hy2Port}/?sni=www.bing.com&alpn=h3&insecure=1#FR`);
  if (realityPort > 0) list.push(`vless://${UUID}@${ip}:${realityPort}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.nazhumi.com&fp=firefox&pbk=${public_key}&type=tcp#FR`);

  const txt = list.join("\n");
  fs.writeFileSync(`${FILE_PATH}/list.txt`, txt);
  fs.writeFileSync(`${FILE_PATH}/sub.txt`, Buffer.from(txt).toString("base64"));
  console.log("\n订阅链接（明文）：");
  console.log(txt);
  console.log(`\n订阅文件：${FILE_PATH}/sub.txt（base64）`);
}

// ================== 主流程 ==================
async function main() {
  console.log("启动 TUIC / Hysteria2 / Reality 节点...");
  console.log(`UUID: ${UUID}`);
  console.log(`TUIC: ${tuicPort || "关闭"} | HY2: ${hy2Port || "关闭"} | Reality: ${realityPort || "关闭"}`);

  scheduleBeijingMidnightRestart();

  const ip = await getPublicIP();
  const { bin, public_key } = await generateConfig(ip);
  generateSub(ip, { public_key });

  console.log("启动 sing-box...");
  const proc = spawn(bin, ["run", "-c", `${FILE_PATH}/config.json`], { stdio: "ignore" });
  proc.on("exit", () => setTimeout(() => spawn(bin, ["run", "-c", `${FILE_PATH}/config.json`], { stdio: "ignore" }), 5000));

  setInterval(() => {}, 1 << 30);
}

main().catch(console.error);
