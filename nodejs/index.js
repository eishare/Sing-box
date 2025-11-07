const http = require('http');
const fs = require('fs');
const { exec } = require("child_process");

// 动态读取 FILE_PATH，保持与 start.sh 一致
const FILE_PATH = process.env.FILE_PATH || './.npm';
const SUBTXT = `${FILE_PATH}/sub.txt`;
const PORT = process.env.PORT || 3000;

// 防止重复启动
let isRunning = false;

// 启动 start.sh
function startScript() {
  if (isRunning) {
    console.log('start.sh 已在运行，跳过重复启动');
    return;
  }

  fs.chmod("start.sh", 0o777, (err) => {
    if (err) {
      console.error(`start.sh 授权失败: ${err}`);
      return;
    }
    console.log('start.sh 授权成功');

    const child = exec('bash start.sh', { timeout: 0 });

    child.stdout.on('data', (data) => {
      console.log(data.toString());
    });

    child.stderr.on('data', (data) => {
      console.error(data.toString());
    });

    child.on('close', (code) => {
      console.log(`start.sh 退出，代码: ${code}`);
      isRunning = false;
      // 可选：自动重启
      // setTimeout(startScript, 5000);
    });

    child.on('error', (err) => {
      console.error('启动 start.sh 失败:', err);
      isRunning = false;
    });

    isRunning = true;
  });
}

// 创建 HTTP 服务器
const server = http.createServer((req, res) => {
  // 首页
  if (req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('TUIC + Hysteria2 + Reality 节点运行中！\n访问 /sub 获取订阅');
  }

  // 获取订阅（base64 编码的 sub.txt）
  else if (req.url === '/sub') {
    fs.readFile(SUBTXT, 'utf8', (err, data) => {
      if (err) {
        console.error('读取 sub.txt 失败:', err);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: '订阅文件不存在或读取失败' }));
      } else {
        res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end(data.trim());
      }
    });
  }

  // 404
  else {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('404 Not Found');
  }
});

// 启动服务
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Web 服务运行在 http://0.0.0.0:${PORT}`);
  console.log(`订阅地址: http://您的IP:${PORT}/sub`);
  startScript(); // 启动 start.sh
});

// 优雅退出
process.on('SIGTERM', () => {
  console.log('收到 SIGTERM，关闭服务...');
  server.close(() => {
    process.exit(0);
  });
});
