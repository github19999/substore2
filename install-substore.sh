#!/bin/bash

# Sub-Store 部署脚本 - 适配现有反代环境
# 支持宝塔、1Panel、Nginx Proxy Manager 等面板

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 生成随机 API 路径
generate_api_path() {
    local chars="ABCGEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local path=""
    for i in {1..32}; do
        path+="${chars:RANDOM%${#chars}:1}"
    done
    echo "/api-$path"
}

# 检测现有反代环境
detect_proxy_env() {
    local proxy_type=""
    
    # 检测宝塔面板
    if [[ -d "/www/server/panel" ]]; then
        proxy_type="bt"
    # 检测1Panel
    elif [[ -d "/opt/1panel" ]]; then
        proxy_type="1panel"
    # 检测Nginx Proxy Manager
    elif docker ps | grep -q "nginxproxymanager"; then
        proxy_type="npm"
    # 检测原生Nginx
    elif systemctl is-active --quiet nginx && [[ ! -d "/www/server/panel" ]]; then
        proxy_type="nginx"
    # 检测其他Docker反代
    elif docker ps | grep -E "(traefik|caddy|proxy)" > /dev/null; then
        proxy_type="docker"
    else
        proxy_type="none"
    fi
    
    echo "$proxy_type"
}

echo "=================================================="
echo "       Sub-Store 智能部署脚本"
echo "       适配各种反代环境"
echo "=================================================="
echo

# 检查权限
if [[ $EUID -ne 0 ]]; then
   print_error "请使用 root 用户运行此脚本"
   exit 1
fi

# 检测环境
print_info "检测服务器环境..."
PROXY_ENV=$(detect_proxy_env)

case $PROXY_ENV in
    "bt")
        print_warning "检测到宝塔面板环境"
        print_info "将使用宝塔友好模式部署"
        ;;
    "1panel")
        print_warning "检测到 1Panel 面板环境"
        print_info "将使用 1Panel 友好模式部署"
        ;;
    "npm")
        print_warning "检测到 Nginx Proxy Manager 环境"
        print_info "将使用 NPM 友好模式部署"
        ;;
    "nginx")
        print_warning "检测到原生 Nginx 环境"
        print_info "将谨慎处理 Nginx 配置"
        ;;
    "docker")
        print_warning "检测到其他 Docker 反代环境"
        print_info "将使用纯 Docker 模式部署"
        ;;
    "none")
        print_info "未检测到反代环境，使用标准模式"
        ;;
esac

echo

# 获取配置
while true; do
    read -p "请输入您的域名: " DOMAIN
    if [[ -n "$DOMAIN" && "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
        break
    else
        print_error "请输入有效的域名"
    fi
done

# 根据环境选择端口
case $PROXY_ENV in
    "bt"|"1panel"|"npm"|"nginx")
        print_info "检测到面板环境，建议使用非标准端口"
        read -p "请输入服务端口 (建议: 13001): " PORT
        PORT=${PORT:-13001}
        ;;
    *)
        read -p "请输入服务端口 (默认: 3001): " PORT
        PORT=${PORT:-3001}
        ;;
esac

# 检查端口占用
if netstat -tlnp | grep -q ":$PORT "; then
    print_error "端口 $PORT 已被占用，请选择其他端口"
    exit 1
fi

# API 路径配置
read -p "请输入 API 路径 (留空自动生成): " API_PATH
if [[ -z "$API_PATH" ]]; then
    API_PATH=$(generate_api_path)
    print_info "自动生成 API 路径: $API_PATH"
fi

[[ ! "$API_PATH" =~ ^/ ]] && API_PATH="/$API_PATH"

# 配置变量
API_URL="https://$DOMAIN$API_PATH"
DATA_DIR="/opt/sub-store-data"  # 使用 /opt 避免与面板冲突

echo
print_info "部署配置:"
echo "域名: $DOMAIN"
echo "端口: $PORT"
echo "API路径: $API_PATH"
echo "数据目录: $DATA_DIR"
echo "反代环境: $PROXY_ENV"
echo

read -p "确认配置无误？(y/N): " confirm
[[ ! "$confirm" =~ ^[Yy]$ ]] && exit 0

echo
print_info "开始部署..."

# 1. 安装 Docker（如果需要）
if ! command -v docker &> /dev/null; then
    print_info "安装 Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
fi

# 2. 创建数据目录
print_info "创建数据目录..."
mkdir -p "$DATA_DIR"

# 3. 启动容器
print_info "启动 Sub-Store 容器..."
docker stop sub-store 2>/dev/null || true
docker rm sub-store 2>/dev/null || true
docker pull xream/sub-store

docker run -d --restart=always \
  --name sub-store \
  -e "SUB_STORE_CRON=0 0 * * *" \
  -e "SUB_STORE_FRONTEND_BACKEND_PATH=$API_PATH" \
  -e "API_URL=$API_URL" \
  -p "127.0.0.1:$PORT:$PORT" \
  -v "$DATA_DIR:/opt/app/data" \
  xream/sub-store

# 检查容器状态
sleep 3
if ! docker ps | grep -q sub-store; then
    print_error "容器启动失败"
    docker logs sub-store
    exit 1
fi

print_success "Sub-Store 容器启动成功"

# 4. 根据环境提供配置指导
echo
echo "=================================================="
print_success "🎉 Sub-Store 部署完成！"
echo "=================================================="
echo
print_info "容器信息:"
echo "端口: 127.0.0.1:$PORT"
echo "API路径: $API_PATH"
echo

case $PROXY_ENV in
    "bt")
        print_info "宝塔面板配置指导:"
        echo "1. 打开宝塔面板 -> 网站"
        echo "2. 添加站点，域名: $DOMAIN"
        echo "3. 设置 -> 反向代理"
        echo "4. 目标URL: http://127.0.0.1:$PORT"
        echo "5. 发送域名: \$host"
        echo "6. SSL 在宝塔面板中申请"
        ;;
    "1panel")
        print_info "1Panel 配置指导:"
        echo "1. 打开 1Panel -> 网站"
        echo "2. 创建网站，域名: $DOMAIN"
        echo "3. 配置反向代理"
        echo "4. 代理地址: http://127.0.0.1:$PORT"
        echo "5. 在 1Panel 中申请 SSL 证书"
        ;;
    "npm")
        print_info "Nginx Proxy Manager 配置指导:"
        echo "1. 打开 NPM 管理界面"
        echo "2. Proxy Hosts -> Add Proxy Host"
        echo "3. Domain: $DOMAIN"
        echo "4. Forward Hostname/IP: 127.0.0.1"
        echo "5. Forward Port: $PORT"
        echo "6. 启用 SSL 和 Force SSL"
        ;;
    "nginx")
        print_warning "检测到原生 Nginx，请手动配置:"
        echo "在 Nginx 配置中添加:"
        echo "location / {"
        echo "    proxy_pass http://127.0.0.1:$PORT;"
        echo "    proxy_set_header Host \$host;"
        echo "    proxy_set_header X-Real-IP \$remote_addr;"
        echo "}"
        ;;
    *)
        print_info "请在您的反代中配置:"
        echo "目标地址: http://127.0.0.1:$PORT"
        echo "域名: $DOMAIN"
        ;;
esac

echo
print_info "访问地址 (配置反代后):"
echo "🌐 管理面板: https://$DOMAIN"
echo "📱 订阅地址: https://$DOMAIN/subs?api=$API_URL"
echo
print_warning "重要提醒:"
echo "1. 请在面板中为域名配置 SSL 证书"
echo "2. 确保域名已解析到服务器 IP"
echo "3. 妥善保管 API 路径: $API_PATH"

# 5. 创建管理脚本
cat > /opt/substore_manage.sh << 'MANAGE'
#!/bin/bash
case "$1" in
    start) docker start sub-store && echo "Sub-Store 已启动" ;;
    stop) docker stop sub-store && echo "Sub-Store 已停止" ;;
    restart) docker restart sub-store && echo "Sub-Store 已重启" ;;
    status) docker ps | grep sub-store ;;
    logs) docker logs -f sub-store ;;
    update) 
        docker pull xream/sub-store
        docker stop sub-store && docker rm sub-store
        echo "请重新运行部署脚本完成更新"
        ;;
    *) echo "用法: $0 {start|stop|restart|status|logs|update}" ;;
esac
MANAGE

chmod +x /opt/substore_manage.sh

echo
print_info "管理命令:"
echo "/opt/substore_manage.sh {start|stop|restart|status|logs|update}"
echo "=================================================="
