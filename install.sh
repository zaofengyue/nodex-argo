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

INPUT_UUID="${UUID:-}"
INPUT_TROJAN_PASS="${TROJAN_PASS:-}"
INPUT_PORT="${PORT:-}"
INPUT_ARGO_PORT="${ARGO_PORT:-}"
INPUT_NAME="${NAME:-}"
INPUT_SUB="${SUB:-}"
INPUT_ARGO_DOMAIN="${ARGO_DOMAIN:-}"
INPUT_ARGO_AUTH="${ARGO_AUTH:-}"

# 任意一个变量有值就跳过交互，全部为空才进入交互模式
if [ -n "$INPUT_UUID" ] || \
   [ -n "$INPUT_TROJAN_PASS" ] || \
   [ -n "$INPUT_PORT" ] || \
   [ -n "$INPUT_ARGO_PORT" ] || \
   [ -n "$INPUT_NAME" ] || \
   [ -n "$INPUT_SUB" ] || \
   [ -n "$INPUT_ARGO_DOMAIN" ] || \
   [ -n "$INPUT_ARGO_AUTH" ]; then
  :
else
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

# 1. 停止用户级 systemd 服务（如果存在）
systemctl --user stop nodex-argo 2>/dev/null || true
systemctl --user disable nodex-argo 2>/dev/null || true
rm -f "\$HOME/.config/systemd/user/nodex-argo.service"
systemctl --user daemon-reload 2>/dev/null || true

# 2. 停止进程（读 PID 文件）
if [ -f "$APP_DIR/nodex.pid" ]; then
  PID=\$(cat "$APP_DIR/nodex.pid")
  kill "\$PID" 2>/dev/null || true
fi

# 3. 兜底：按进程名 kill
pkill -f "nodex-argo/index.js" 2>/dev/null || true

# 4. 清理所有启动文件中的自启条目
for RC_FILE in "\$HOME/.bashrc" "\$HOME/.profile" "\$HOME/.bash_profile" "\$HOME/.zshrc"; do
  sed -i '/# nodex-argo PATH/d' "\$RC_FILE" 2>/dev/null || true
  sed -i '/# nodex-argo autostart/d' "\$RC_FILE" 2>/dev/null || true
  sed -i '/nodex-argo/d' "\$RC_FILE" 2>/dev/null || true
done

# 5. 删除文件
rm -rf "$APP_DIR"
rm -f "\$HOME/xray.zip" "\$HOME/cloudflared"
rm -rf "\$HOME/xray"
rm -f "\$HOME/uuid.txt" "\$HOME/trojan.txt" "\$HOME/xray-config.json"
rm -f "$LOCAL_BIN/nodex-sub" "$LOCAL_BIN/nodex-del"
echo "删除完成"
DELCMD
chmod +x "$LOCAL_BIN/nodex-del"

# ── 确保 ~/.local/bin 在 PATH 中，写入所有存在的启动文件 ─────────────────
if ! echo "$PATH" | grep -q "$LOCAL_BIN"; then
  for RC_FILE in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    if [ -f "$RC_FILE" ]; then
      echo "" >> "$RC_FILE"
      echo "# nodex-argo PATH" >> "$RC_FILE"
      echo "export PATH=\"$LOCAL_BIN:\$PATH\"" >> "$RC_FILE"
    fi
  done
  export PATH="$LOCAL_BIN:$PATH"
fi

# ── 生成启动包装脚本（内含完整环境变量）────────────────────────────────
WRAPPER="$APP_DIR/start.sh"
NODE_BIN="$(command -v node)"

cat > "$WRAPPER" << WRAPEOF
#!/bin/bash
# nodex-argo 自动生成的启动包装脚本，请勿手动修改
export UUID="$INPUT_UUID"
export TROJAN_PASS="$INPUT_TROJAN_PASS"
export PORT="$INPUT_PORT"
export ARGO_PORT="$INPUT_ARGO_PORT"
export NAME="$INPUT_NAME"
export SUB="$INPUT_SUB"
export ARGO_DOMAIN="$INPUT_ARGO_DOMAIN"
export ARGO_AUTH="$INPUT_ARGO_AUTH"

cd "$APP_DIR"
nohup $NODE_BIN "$APP_DIR/index.js" >> "$APP_DIR/run.log" 2>&1 &
echo \$! > "$APP_DIR/nodex.pid"
WRAPEOF
chmod +x "$WRAPPER"

# ── 开机自启：优先用户级 systemd，否则写入所有启动文件 ───────────────────
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
ExecStart=$NODE_BIN $APP_DIR/index.js
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
  loginctl enable-linger "$USER" 2>/dev/null || true

  echo ""
  echo -e "${GREEN}服务已通过用户级 systemd 启动并设置开机自启${NC}"
  echo -e "${GREEN}查看日志: journalctl --user -u nodex-argo -f${NC}"

else
  # ── fallback：nohup 立即启动 + 写入所有启动文件 ──────────────────────
  bash "$WRAPPER"

  for RC_FILE in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    if [ -f "$RC_FILE" ] && ! grep -q "# nodex-argo autostart" "$RC_FILE" 2>/dev/null; then
      cat >> "$RC_FILE" << RCEOF

# nodex-argo autostart
if ! pgrep -f "nodex-argo/index.js" >/dev/null 2>&1; then
  bash "$WRAPPER" >/dev/null 2>&1
fi
RCEOF
    fi
  done

  echo ""
  echo -e "${GREEN}服务已通过 nohup 后台启动${NC}"
  echo -e "${GREEN}每次打开终端自动检测并恢复进程${NC}"
  echo -e "${GREEN}查看日志: tail -f $APP_DIR/run.log${NC}"
fi

echo -e "${GREEN}查看节点: nodex-sub${NC}"
echo -e "${GREEN}彻底删除: nodex-del${NC}"
echo ""
echo -e "${YELLOW}等待服务启动，节点链接将写入 $APP_DIR/sub.txt${NC}"
