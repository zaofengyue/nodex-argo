# nodex-argo

基于 xray + Cloudflare Argo 隧道的多协议代理工具，同时支持 VMess、VLESS、Trojan 三种协议，支持临时隧道和固定隧道，支持源码部署、Docker 镜像部署和一键脚本部署。

## 工作原理

```
客户端 → Cloudflare CDN → Argo 隧道(ARGO_PORT) → xray(内部)
                               ↓
                    Node.js HTTP(PORT) → 伪装页 / 订阅
```

## 部署方式

### 方式一：源码部署

上传以下文件即可：

```
index.js
package.json
index.html（可选）
```

或直接下载 [Releases](https://github.com/zaofengyue/nodex-argo/releases) 里的 `nodex-argo.zip` 解压后上传。

### 方式二：Docker 镜像部署

```bash
docker pull ghcr.io/zaofengyue/nodex-argo:latest
```

```bash
docker run -d \
  -e UUID=你的UUID \
  -e ARGO_DOMAIN=你的域名 \
  -e ARGO_AUTH=你的Token \
  -p 3000:3000 \
  ghcr.io/zaofengyue/nodex-argo:latest
```

### 方式三：一键脚本

curl：

```bash
bash <(curl -sL https://raw.githubusercontent.com/zaofengyue/nodex-argo/main/install.sh)
```

wget：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/zaofengyue/nodex-argo/main/install.sh)
```

命令前指定变量：

```bash
UUID=xxx ARGO_DOMAIN=你的域名 ARGO_AUTH=你的Token bash <(curl -sL https://raw.githubusercontent.com/zaofengyue/nodex-argo/main/install.sh)
```

## 环境变量

| 变量名 | 说明 | 默认值 |
|---|---|---|
| `UUID` | VMess/VLESS 唯一ID | 自动生成 |
| `TROJAN_PASS` | Trojan 密码 | 自动生成 |
| `PORT` | 对外监听端口 | `3000` |
| `ARGO_PORT` | Argo 内部转发端口 | `8001` |
| `NAME` | 节点名称前缀 | 自动生成 |
| `SUB` | 订阅路径 | `sub` |
| `ARGO_DOMAIN` | 固定隧道域名 | 留空用临时隧道 |
| `ARGO_AUTH` | 固定隧道 Token | 留空用临时隧道 |


## 访问地址

| 路径 | 内容 |
|---|---|
| `https://你的域名/` | 伪装页面 |
| `https://你的域名/sub` | 订阅链接（三个协议） |

## 获取固定隧道 Token

1. 登录 [Cloudflare Zero Trust](https://one.dash.cloudflare.com)
2. 进入 **Networks → Tunnels → Create a tunnel**
3. 选择 **Cloudflared** → 填写隧道名称
4. 复制 token（`ARGO_AUTH`）
5. 在 Public Hostname 里添加你的域名指向 `http://127.0.0.1:3000`（`ARGO_DOMAIN`）


## 注意事项

- 仅供学习研究使用，请遵守当地法律法规
- 临时隧道重启后域名会变，需要重新导入节点
- 固定隧道需要 Cloudflare 账号和托管域名
- xray 和 cloudflared 启动时自动下载，首次启动需要联网
