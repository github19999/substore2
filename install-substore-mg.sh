#!/bin/bash

# 极简版 Sub-Store 部署脚本（仅 HTTP 直连，已安装 Docker）

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

generate_api_path() {
    local chars="abcdefghijklmnopqrstuvwxyz0123456789"
    local path=""
    for i in {1..8}; do
        path+="${chars:RANDOM%${#chars}:1}"
    done
    echo "/api-$path"
}

[[ $EUID -ne 0 ]] && error "请使用 root 用户运行此脚本" && exit 1

read -p "请输入 Sub-Store 容器端口（默认 3001）: " PORT
PORT=${PORT:-3001}

read -p "自定义 API 路径（留空自动生成）: " API_PATH
[[ -z "$API_PATH" ]] && API_PATH=$(generate_api_path)
[[ "$API_PATH" != /* ]] && API_PATH="/$API_PATH"

DATA_DIR="/opt/sub-store-data"
API_URL="http://$(curl -s ifconfig.me):$PORT$API_PATH"

info "部署配置如下："
echo "端口: $PORT"
echo "API路径: $API_PATH"
echo "API链接: $API_URL"
echo
read -p "确认继续部署？(y/N): " confirm
[[ ! "$confirm" =~ ^[Yy]$ ]] && exit 0

mkdir -p "$DATA_DIR"
docker stop sub-store 2>/dev/null || true
docker rm sub-store 2>/dev/null || true

info "启动 Sub-Store 容器..."
docker run -d --restart=always \
  --name sub-store \
  -e "SUB_STORE_FRONTEND_BACKEND_PATH=$API_PATH" \
  -e "API_URL=$API_URL" \
  -v "$DATA_DIR:/opt/app/data" \
  -p "$PORT:$PORT" \
  xream/sub-store

sleep 2
if docker ps | grep -q sub-store; then
  success "Sub-Store 部署成功！"
  echo "访问地址：http://你的IP:$PORT"
  echo "订阅链接：http://你的IP:$PORT/subs?api=$API_URL"
else
  error "容器启动失败，请检查日志：docker logs sub-store"
fi
