#!/bin/bash
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}========== nodex-argo 一键安装 ==========${NC}"

if command -v curl >/dev/null 2>&1; then
  DL="curl -sL"
  DL_O="-o"
elif command -v wget >/dev/null 2>&1; then
  DL="wget -q"
  DL_O="-O"
else
  echo -e "${RED}缺少 curl 或 wget${NC}"
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo -e "${RED}缺少 node，请先安装 Node.js${NC}"
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo -e "${RED}缺少 unzip，请先安装${NC}"
  exit 1
fi

BASE_URL="https://raw.githubusercontent.com/zaofengyue/nodex-argo/main"
APP_DIR="$HOME/nodex-argo"
mkdir -p "$APP_DIR" && cd "$APP_DIR"

echo -e "${GREEN}正在拉取文件...${NC}"
$DL "$BASE_URL/index.js" $DL_O index.js
$DL "$BASE_URL/package.json" $DL_O package.json
$DL "$BASE_URL/index.html" $DL_O index.html

INPUT_UUID="${UUID:-}"
INPUT_TROJAN_PASS="${TROJAN_PASS:-}"
INPUT_PORT="${PORT:-}"
INPUT_ARGO_PORT="${ARGO_PORT:-}"
INPUT_NAME="${NAME:-}"
INPUT_SUB="${SUB:-}"
INPUT_ARGO_DOMAIN="${ARGO_DOMAIN:-}"
INPUT_ARGO_AUTH="${ARGO_AUTH:-}"

if [ -z "$INPUT_UUID" ] && [ -z "$INPUT_PORT" ] && [ -z "$INPUT_ARGO_DOMAIN" ]; then
  echo ""
  echo -e "${YELLOW}========== 环境变量配置（留空使用默认值）==========${NC}"
  read -p "UUID（留空自动生成）: " INPUT_UUID
  read -p "TROJAN_PASS（留空自动生成）: " INPUT_TROJAN_PASS
  read -p "PORT（留空默认 3000）: " INPUT_PORT
  read -p "ARGO_PORT（留空默认 8001）: " INPUT_ARGO_PORT
  read -p "NAME/节点名称前缀（留空自动识别）: " INPUT_NAME
  read -p "SUB/订阅路径（留空默认 sub）: " INPUT_SUB
  echo ""
  echo -e "${YELLOW}--- Argo 隧道配置（留空使用临时隧道）---${NC}"
  read -p "ARGO_DOMAIN/固定隧道域名（留空临时隧道）: " INPUT_ARGO_DOMAIN
  read -p "ARGO_AUTH/固定隧道 Token（留空临时隧道）: " INPUT_ARGO_AUTH
fi

export UUID="$INPUT_UUID"
export TROJAN_PASS="$INPUT_TROJAN_PASS"
export PORT="$INPUT_PORT"
export ARGO_PORT="$INPUT_ARGO_PORT"
export NAME="$INPUT_NAME"
export SUB="$INPUT_SUB"
export ARGO_DOMAIN="$INPUT_ARGO_DOMAIN"
export ARGO_AUTH="$INPUT_ARGO_AUTH"

# ── 快捷命令：统一写入 ~/.local/bin（无需 root）──────────────────────────
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

cat > "$LOCAL_BIN/nodex-sub" << 'SUBCMD'
#!/bin/bash
SUB_FILE="$HOME/nodex-argo/sub.txt"
if [ -f "$SUB_FILE" ]; then
  cat "$SUB_FILE"
else
  echo "sub.txt 不存在，请等待服务启动完成"
fi
SUBCMD
chmod +x "$LOCAL_BIN/nodex-sub"

cat > "$LOCAL_BIN/nodex-del" << DELCMD
#!/bin/bash
echo "正在彻底删除 nodex-argo..."

# 停止用户级 systemd 服务（如果存在）
systemctl --user stop nodex-argo 2>/dev/null || true
systemctl --user disable nodex-argo 2>/dev/null || true
rm -f "\$HOME/.config/systemd/user/nodex-argo.service"
systemctl --user daemon-reload 2>/dev/null || true

# 停止 nohup 进程（如果存在）
if [ -f "$APP_DIR/nodex.pid" ]; then
  kill \$(cat "$APP_DIR/nodex.pid") 2>/dev/null || true
fi

# 清理 ~/.bashrc 中的自启条目
sed -i '/nodex-argo autostart/d' "\$HOME/.bashrc" 2>/dev/null || true
sed -i '/nodex-argo/d' "\$HOME/.bashrc" 2>/dev/null || true

rm -rf "$APP_DIR"
rm -f "\$HOME/xray.zip" "\$HOME/xray" "\$HOME/cloudflared"
rm -rf "\$HOME/xray" "\$HOME/v2ray"
rm -f "\$HOME/uuid.txt" "\$HOME/trojan.txt" "\$HOME/xray-config.json"
rm -f "$LOCAL_BIN/nodex-sub" "$LOCAL_BIN/nodex-del"
echo "删除完成"
DELCMD
chmod +x "$LOCAL_BIN/nodex-del"

# 确保 ~/.local/bin 在 PATH 中
if ! echo "$PATH" | grep -q "$LOCAL_BIN"; then
  echo "" >> "$HOME/.bashrc"
  echo "# nodex-argo PATH" >> "$HOME/.bashrc"
  echo "export PATH=\"$LOCAL_BIN:\$PATH\"" >> "$HOME/.bashrc"
  export PATH="$LOCAL_BIN:$PATH"
fi

# ── 开机自启：优先用户级 systemd，否则用 nohup + .bashrc ─────────────────
# 判断用户级 systemd 是否可用
USER_SYSTEMD_OK=false
if command -v systemctl >/dev/null 2>&1 && systemctl --user status >/dev/null 2>&1; then
  USER_SYSTEMD_OK=true
fi

if $USER_SYSTEMD_OK; then
  # ── 用户级 systemd（无需 root）────────────────────────────────────────
  SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_USER_DIR"

  cat > "$SYSTEMD_USER_DIR/nodex-argo.service" << EOF
[Unit]
Description=nodex-argo service
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
Environment=UUID=$INPUT_UUID
Environment=TROJAN_PASS=$INPUT_TROJAN_PASS
Environment=PORT=$INPUT_PORT
Environment=ARGO_PORT=$INPUT_ARGO_PORT
Environment=NAME=$INPUT_NAME
Environment=SUB=$INPUT_SUB
Environment=ARGO_DOMAIN=$INPUT_ARGO_DOMAIN
Environment=ARGO_AUTH=$INPUT_ARGO_AUTH
ExecStart=$(command -v node) $APP_DIR/index.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable nodex-argo
  systemctl --user start nodex-argo

  # 确保登出后服务仍运行（需要 loginctl，权限不足时静默跳过）
  loginctl enable-linger "$USER" 2>/dev/null || true

  echo ""
  echo -e "${GREEN}服务已通过用户级 systemd 启动并设置开机自启${NC}"
  echo -e "${GREEN}查看日志: journalctl --user -u nodex-argo -f${NC}"
  echo -e "${GREEN}查看节点: nodex-sub${NC}"
  echo -e "${GREEN}彻底删除: nodex-del${NC}"

else
  # ── fallback：nohup 后台运行 + .bashrc 自启 ──────────────────────────
  nohup node "$APP_DIR/index.js" > "$APP_DIR/run.log" 2>&1 &
  echo $! > "$APP_DIR/nodex.pid"

  AUTOSTART="nohup node $APP_DIR/index.js > $APP_DIR/run.log 2>&1 &"
  if ! grep -q "nodex-argo" "$HOME/.bashrc" 2>/dev/null; then
    echo "" >> "$HOME/.bashrc"
    echo "# nodex-argo autostart" >> "$HOME/.bashrc"
    echo "$AUTOSTART" >> "$HOME/.bashrc"
  fi

  echo ""
  echo -e "${GREEN}服务已通过 nohup 后台启动${NC}"
  echo -e "${GREEN}查看日志: tail -f $APP_DIR/run.log${NC}"
  echo -e "${GREEN}查看节点: nodex-sub${NC}"
  echo -e "${GREEN}彻底删除: nodex-del${NC}"
fi

echo ""
echo -e "${YELLOW}等待服务启动，节点链接将写入 $APP_DIR/sub.txt${NC}"
