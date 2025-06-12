#!/bin/bash

set -e

echo "更新系统..."
apt update -y

echo "安装必要组件..."
apt install unzip curl wget git sudo -y

echo "安装 FNM 版本管理器..."
curl -fsSL https://fnm.vercel.app/install | bash

# 加载 FNM 环境（请根据实际情况调整）
export PATH="/root/.local/share/fnm:$PATH"
eval "$(fnm env)"

echo "安装 Node.js v20.18.0..."
fnm install v20.18.0
fnm use v20.18.0
node -v

echo "安装 pnpm..."
curl -fsSL https://get.pnpm.io/install.sh | sh -
source /root/.bashrc

echo "创建 Sub-Store 项目目录..."
mkdir -p /root/sub-store
cd /root/sub-store

echo "下载后端 sub-store.bundle.js..."
curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js

echo "下载并解压前端 dist.zip..."
curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
unzip dist.zip && mv dist frontend && rm dist.zip

echo "创建 systemd 服务..."

cat > /etc/systemd/system/sub-store.service <<EOF
[Unit]
Description=Sub-Store
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
LimitNOFILE=32767
Type=simple
Environment="SUB_STORE_FRONTEND_BACKEND_PATH=/9GgGyhWFEguXZBT3oHPY"
Environment="SUB_STORE_BACKEND_CRON=0 0 * * *"
Environment="SUB_STORE_FRONTEND_PATH=/root/sub-store/frontend"
Environment="SUB_STORE_FRONTEND_HOST=0.0.0.0"
Environment="SUB_STORE_FRONTEND_PORT=3001"
Environment="SUB_STORE_DATA_BASE_PATH=/root/sub-store"
Environment="SUB_STORE_BACKEND_API_HOST=127.0.0.1"
Environment="SUB_STORE_BACKEND_API_PORT=3000"
ExecStart=/root/.local/share/fnm/fnm exec --using v20.18.0 node /root/sub-store/sub-store.bundle.js
User=root
Group=root
Restart=on-failure
RestartSec=5s
ExecStartPre=/bin/sh -c ulimit -n 51200
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "重载 systemd 并启动 Sub-Store 服务..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable sub-store
systemctl start sub-store

echo "✅ 安装完成！"
echo "你可以使用以下地址访问 Sub-Store："
echo "http://你的IP:3001/?api=http://你的IP:3001/9GgGyhWFEguXZBT3oHPY"
echo "建议绑定域名并使用 CDN 隐藏真实 IP。"
