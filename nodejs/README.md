### 更新说明：

* 精简化：去除哪吒、argo隧道；保留3种协议：tuic、hy2、vless+xtls+reality
  
* 设置每日零时自动重启服务器，避免内存溢出停机
  
* 持久化运行，服务器重启节点不掉
  
* TCP/UDP端口可共用
  
### 使用说明：

1：start.sh+index.js+package.json上传至服务器

2：手动编辑uuid，输入tuic/hy2/vless端口，保存

3：开机
