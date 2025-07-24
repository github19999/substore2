#!/bin/bash

set -e

echo "🔄 更新系统..."
apt update -y

echo "📦 安装必要组件..."
apt install -y curl wget unzip git openssl

echo "🐳 安装 Docker（官方推荐脚本）..."
curl -fsSL https://get.docker.com -o get-docker.sh 
sh get-docker.sh
rm get-docker.sh

echo "🔧 启动 Docker 并设置开机自启..."
systemctl enable docker
systemctl start docker

echo "🔍 检查 docker compose 是否可用..."
if ! docker compose version &>/dev/null; then
  echo "❌ docker compose 命令不可用，请检查 Docker 安装情况！"
  exit 1
fi

echo "📁 创建 Sub-Store 目录..."
mkdir -p /root/docker/substore
cd /root/docker/substore

echo "🔐 生成随机 API 请求路径..."
API_PATH=$(openssl rand -hex 12)

echo "⬇️ 下载 Sub-Store 后端文件..."
curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js

echo "⬇️ 下载 Sub-Store 前端文件..."
curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
unzip -o dist.zip && mv dist frontend && rm dist.zip

echo "📋 写入 docker-compose.yml..."
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  substore:
    image: node:20.18.0
    container_name: substore
    restart: unless-stopped
    working_dir: /app
    command: ["node", "sub-store.bundle.js"]
    ports:
      - "3001:3001"
    environment:
      SUB_STORE_FRONTEND_BACKEND_PATH: "/$API_PATH"
      SUB_STORE_BACKEND_CRON: "0 0 * * *"
      SUB_STORE_FRONTEND_PATH: "/app/frontend"
      SUB_STORE_FRONTEND_HOST: "0.0.0.0"
      SUB_STORE_FRONTEND_PORT: "3001"
      SUB_STORE_DATA_BASE_PATH: "/app"
      SUB_STORE_BACKEND_API_HOST: "127.0.0.1"
      SUB_STORE_BACKEND_API_PORT: "3000"
    volumes:
      - ./sub-store.bundle.js:/app/sub-store.bundle.js
      - ./frontend:/app/frontend
      - ./data:/app/data
EOF

echo "🚀 启动 Sub-Store Docker 容器..."
docker compose up -d

IP=$(curl -s https://ipinfo.io/ip || echo "<你的IP>")

echo
echo "✅ Sub-Store 安装完成！"
echo "🔗 访问地址： http://$IP:3001/?api=http://$IP:3001/$API_PATH"
echo "🌐 建议绑定域名并使用 CDN 隐藏真实 IP。"
