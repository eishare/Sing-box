### 更新说明：

### 适用128M内存以上环境，不建议freecloudpanel使用（只有64M内存）

* 精简化：去除哪吒、argo隧道；保留3种协议：tuic、hy2、vless+xtls+reality
  
* 自动重启：每天00:03自动执行一次singbox重启，清除缓存，起到一定保活作用
  
* TCP/UDP端口可共用
  
### 使用说明：

1：start.sh+index.js+package.json上传至服务器

2：手动编辑uuid，输入tuic/hy2/vless端口，保存

3：开机
