#!/bin/bash

# 设置在命令失败时立即退出脚本
set -e

echo "🔄 更新系统并安装必要组件..."
# 更新软件包列表
apt update -y
# 安装 curl, wget, unzip, git, docker.io 和 docker-compose
# docker.io 是 Docker 守护进程，docker-compose 用于多容器应用管理
apt install -y curl wget unzip git docker.io docker-compose

echo "🚀 检查 Docker 安装状态..."
# 检查 Docker 是否安装成功
if docker --version &> /dev/null; then
    echo "✅ Docker 已成功安装。"
else
    echo "❌ Docker 安装失败，请检查错误信息。"
    exit 1
fi

echo "🕒 设置时区为 Asia/Shanghai..."
# 设置系统时区为上海
timedatectl set-timezone Asia/Shanghai
echo "✅ 时区已设置为 Asia/Shanghai。"

echo "---"
echo "🛠️ 开始安装 Sub-Store..."
# 创建 Sub-Store 的安装目录并进入
mkdir -p /root/docker/substore
cd /root/docker/substore

echo "🔐 生成随机 API 请求路径..."
# 生成一个24字符的十六进制字符串作为随机API路径
API_PATH=$(openssl rand -hex 12)

echo "⬇️ 下载 Sub-Store 后端文件..."
# 从GitHub最新发布版下载 Sub-Store 后端JS文件
curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js

echo "⬇️ 下载 Sub-Store 前端文件..."
# 从GitHub最新发布版下载 Sub-Store 前端ZIP文件，解压并重命名目录
curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
unzip -o dist.zip && mv dist frontend && rm dist.zip

echo "📋 写入 Sub-Store 的 docker-compose.yml 文件..."
# 将docker-compose配置写入文件
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
# 启动 Sub-Store 容器，-d 表示在后台运行
docker compose up -d
echo "✅ Sub-Store 部署完成。"

echo "---"
echo "🛠️ 开始安装 Nginx Proxy Manager (NPM)..."
# 创建 NPM 的安装目录并进入
mkdir -p /root/docker/npm
cd /root/docker/npm

echo "📋 写入 NPM 的 docker-compose.yml 文件..."
# 将NPM的docker-compose配置写入文件
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF

echo "🚀 启动 NPM Docker 容器..."
# 启动 NPM 容器
docker compose up -d
echo "✅ NPM 部署完成。"

echo "---"
echo "🛠️ 开始安装 Wallos..."
# 创建 Wallos 的安装目录并进入
mkdir -p /root/docker/wallos
cd /root/docker/wallos

echo "📋 写入 Wallos 的 docker-compose.yml 文件..."
# 将Wallos的docker-compose配置写入文件
cat > docker-compose.yml <<EOF
version: '3.0'

services:
  wallos:
    container_name: wallos
    image: bellamy/wallos:2.39.0
    ports:
      - "8282:80/tcp"
    environment:
      TZ: 'Asia/Shanghai'
    volumes:
      - './db:/var/www/html/db'
      - './logos:/var/www/html/images/uploads/logos'
    restart: unless-stopped
EOF

echo "🚀 启动 Wallos Docker 容器..."
# 启动 Wallos 容器
docker compose up -d
echo "✅ Wallos 部署完成。"

echo "---"
echo "🎉 所有应用安装完成！"
echo "请将 '<你的IP>' 替换为你的服务器公网IP地址。"
echo ""
echo "🔗 Sub-Store 访问地址: "
echo "   http://<你的IP>:3001/?api=http://<你的IP>:3001/$API_PATH"
echo "🔗 Nginx Proxy Manager 访问地址: "
echo "   http://<你的IP>:81"
echo "   默认登录邮箱: admin@example.com"
echo "   默认登录密码: changeme"
echo "🔗 Wallos 访问地址: "
echo "   http://<你的IP>:8282/"
echo ""
echo "⚠️ 首次登录 NPM 后，请务必更改默认的邮箱和密码！"
echo "🌐 建议为 Sub-Store 和 NPM 绑定域名并使用 CDN 隐藏真实 IP。"
