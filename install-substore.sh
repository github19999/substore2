#!/bin/bash

# Sub-Store 完整部署脚本
# 包含 Docker + Nginx 反代 + SSL 证书

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
    local chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local path=""
    for i in {1..32}; do
        path+="${chars:RANDOM%${#chars}:1}"
    done
    echo "/api-$path"
}

# 检测系统环境
detect_system() {
    if [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/redhat-release ]]; then
        echo "centos"
    else
        echo "unknown"
    fi
}

echo "=================================================="
echo "       Sub-Store 完整部署脚本"
echo "     Docker + Nginx + SSL 一键配置"
echo "=================================================="
echo

# 检查权限
if [[ $EUID -ne 0 ]]; then
   print_error "请使用 root 用户运行此脚本"
   exit 1
fi

# 获取系统信息
SYSTEM=$(detect_system)
print_info "检测到系统: $SYSTEM"

# 获取配置
while true; do
    read -p "请输入您的域名: " DOMAIN
    if [[ -n "$DOMAIN" && "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
        break
    else
        print_error "请输入有效的域名"
    fi
done

read -p "请输入服务端口 (默认: 3001): " PORT
PORT=${PORT:-3001}

read -p "请输入 API 路径 (留空自动生成): " API_PATH
if [[ -z "$API_PATH" ]]; then
    API_PATH=$(generate_api_path)
    print_info "自动生成 API 路径: $API_PATH"
fi

[[ ! "$API_PATH" =~ ^/ ]] && API_PATH="/$API_PATH"

# 配置变量
API_URL="https://$DOMAIN$API_PATH"
DATA_DIR="/opt/sub-store-data"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
NGINX_LINK="/etc/nginx/sites-enabled/$DOMAIN"

echo
print_info "部署配置:"
echo "域名: $DOMAIN"
echo "端口: $PORT"
echo "API路径: $API_PATH"
echo "API地址: $API_URL"
echo "数据目录: $DATA_DIR"
echo

read -p "确认配置无误？(y/N): " confirm
[[ ! "$confirm" =~ ^[Yy]$ ]] && exit 0

echo
print_info "开始完整部署..."

# 1. 更新系统并安装软件
print_info "1. 更新系统并安装必要软件..."
if [[ "$SYSTEM" == "debian" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt update && apt upgrade -y
    apt install -y nginx certbot python3-certbot-nginx docker.io curl wget ufw
elif [[ "$SYSTEM" == "centos" ]]; then
    yum update -y
    yum install -y nginx certbot python3-certbot-nginx docker curl wget firewalld
    systemctl enable firewalld
    systemctl start firewalld
else
    print_error "不支持的系统类型"
    exit 1
fi

# 2. 启动服务
print_info "2. 启动基础服务..."
systemctl enable docker nginx
systemctl start docker nginx

# 3. 配置防火墙
print_info "3. 配置防火墙..."
if [[ "$SYSTEM" == "debian" ]]; then
    ufw --force enable
    ufw allow ssh
    ufw allow 80
    ufw allow 443
    ufw allow $PORT
elif [[ "$SYSTEM" == "centos" ]]; then
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --permanent --add-port=$PORT/tcp
    firewall-cmd --reload
fi

# 4. 创建数据目录
print_info "4. 创建数据目录..."
mkdir -p "$DATA_DIR"

# 5. 启动 Docker 容器
print_info "5. 启动 Sub-Store 容器..."
docker stop sub-store 2>/dev/null || true
docker rm sub-store 2>/dev/null || true
docker pull xream/sub-store

docker run -d --restart=always \
  --name sub-store \
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

# 6. 配置 Nginx 反向代理
print_info "6. 配置 Nginx 反向代理..."

# 删除默认配置
[[ -f "/etc/nginx/sites-enabled/default" ]] && rm -f /etc/nginx/sites-enabled/default

# 创建初始 HTTP 配置
cat > "$NGINX_CONF" << NGINX_HTTP
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # 健康检查
    location /health {
        access_log off;
        return 200 "healthy\\n";
        add_header Content-Type text/plain;
    }
}
NGINX_HTTP

# 创建软链接
[[ ! -f "$NGINX_LINK" ]] && ln -s "$NGINX_CONF" "$NGINX_LINK"

# 测试并重载配置
if nginx -t; then
    systemctl reload nginx
    print_success "Nginx HTTP 配置已生效"
else
    print_error "Nginx 配置测试失败"
    exit 1
fi

# 7. 申请 SSL 证书
print_info "7. 申请 SSL 证书..."
print_warning "请确保域名 $DOMAIN 已正确解析到此服务器"

read -p "现在申请 SSL 证书吗？(y/N): " ssl_confirm
if [[ "$ssl_confirm" =~ ^[Yy]$ ]]; then
    read -p "邮箱地址 (用于证书通知，留空跳过): " EMAIL
    
    if [[ -n "$EMAIL" ]]; then
        certbot --nginx --agree-tos --email "$EMAIL" -d "$DOMAIN" --non-interactive
    else
        certbot --nginx --agree-tos --register-unsafely-without-email -d "$DOMAIN" --non-interactive
    fi
    
    if [[ $? -eq 0 ]]; then
        print_success "SSL 证书申请成功"
        
        # 8. 更新 HTTPS 配置
        print_info "8. 更新 HTTPS 配置..."
        cat > "$NGINX_CONF" << NGINX_HTTPS
server {
    listen 8080;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 8443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/ssl/private/fullchain.cer;
    ssl_certificate_key /etc/ssl/private/private.key;

    # SSL 优化配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # 健康检查
    location /health {
        access_log off;
        return 200 "healthy\\n";
        add_header Content-Type text/plain;
    }
}
NGINX_HTTPS
        
        nginx -t && systemctl reload nginx
        print_success "HTTPS 配置已生效"
    else
        print_error "SSL 证书申请失败，继续使用 HTTP"
    fi
else
    print_warning "跳过 SSL 证书申请"
fi

# 9. 设置自动续期
if [[ -f "/etc/ssl/private/fullchain.cer" ]]; then
    print_info "9. 设置 SSL 证书自动续期..."
    cat > /etc/cron.daily/cert_renew << CRON_RENEW
#!/bin/bash
certbot renew --quiet --deploy-hook "systemctl reload nginx"
CRON_RENEW
    chmod +x /etc/cron.daily/cert_renew
fi

# 10. 设置容器自动更新
print_info "10. 设置容器自动更新..."
cat > /etc/cron.d/substore_update << CRON_UPDATE
# Sub-Store 每3天自动更新
0 3 */3 * * root /usr/bin/docker pull xream/sub-store && \\
/usr/bin/docker stop sub-store && \\
/usr/bin/docker rm sub-store && \\
/usr/bin/docker run -d --restart=always \\
--name sub-store \\
-e "SUB_STORE_FRONTEND_BACKEND_PATH=$API_PATH" \\
-e "API_URL=$API_URL" \\
-p "127.0.0.1:$PORT:$PORT" \\
-v "$DATA_DIR:/opt/app/data" \\
xream/sub-store > /var/log/substore_update.log 2>&1
CRON_UPDATE

systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null

# 11. 创建管理脚本
print_info "11. 创建管理脚本..."
cat > /opt/substore_manage.sh << 'MANAGE_SCRIPT'
#!/bin/bash
case "$1" in
    start)
        docker start sub-store
        echo "Sub-Store 已启动"
        ;;
    stop)
        docker stop sub-store
        echo "Sub-Store 已停止"
        ;;
    restart)
        docker restart sub-store
        echo "Sub-Store 已重启"
        ;;
    status)
        echo "=== 容器状态 ==="
        docker ps | grep sub-store || echo "容器未运行"
        echo "=== 服务状态 ==="
        systemctl status nginx --no-pager -l
        ;;
    logs)
        docker logs -f sub-store
        ;;
    update)
        echo "更新 Sub-Store..."
        docker pull xream/sub-store
        docker stop sub-store
        docker rm sub-store
        echo "请重新运行部署脚本完成更新"
        ;;
    info)
        echo "=== Sub-Store 信息 ==="
        echo "容器状态: $(docker ps | grep sub-store > /dev/null && echo '运行中' || echo '未运行')"
        echo "Nginx状态: $(systemctl is-active nginx)"
        echo "数据目录: $DATA_DIR"
        ;;
    *)
        echo "Sub-Store 管理脚本"
        echo "用法: $0 {start|stop|restart|status|logs|update|info}"
        echo ""
        echo "命令说明:"
        echo "  start   - 启动服务"
        echo "  stop    - 停止服务"
        echo "  restart - 重启服务"
        echo "  status  - 查看状态"
        echo "  logs    - 查看日志"
        echo "  update  - 更新镜像"
        echo "  info    - 显示信息"
        ;;
esac
MANAGE_SCRIPT

chmod +x /opt/substore_manage.sh

# 完成部署
echo
echo "=================================================="
print_success "🎉 Sub-Store 完整部署成功！"
echo "=================================================="
echo

# 检查最终状态
CONTAINER_STATUS=$(docker ps | grep sub-store > /dev/null && echo "✅ 运行中" || echo "❌ 未运行")
NGINX_STATUS=$(systemctl is-active nginx)
SSL_STATUS=$([[ -f "/etc/ssl/private/fullchain.cer" ]] && echo "✅ 已配置" || echo "❌ 未配置")

print_info "部署状态:"
echo "Docker容器: $CONTAINER_STATUS"
echo "Nginx服务: $NGINX_STATUS"
echo "SSL证书: $SSL_STATUS"
echo

print_info "访问地址:"
if [[ -f "/etc/ssl/private/fullchain.cer" ]]; then
    echo "🌐 管理面板: https://$DOMAIN"
    echo "📱 订阅地址: https://$DOMAIN/subs?api=$API_URL"
else
    echo "🌐 管理面板: http://$DOMAIN"
    echo "📱 订阅地址: http://$DOMAIN/subs?api=$API_URL"
fi

echo
print_info "管理命令:"
echo "服务管理: /opt/substore_manage.sh {start|stop|restart|status|logs|update|info}"
echo "查看状态: /opt/substore_manage.sh status"
echo "查看日志: /opt/substore_manage.sh logs"

echo
print_info "重要文件:"
echo "数据目录: $DATA_DIR"
echo "Nginx配置: $NGINX_CONF"
echo "管理脚本: /opt/substore_manage.sh"

echo
print_warning "重要提醒:"
echo "1. 妥善保管 API 路径: $API_PATH"
echo "2. 定期备份数据目录: $DATA_DIR"
echo "3. 确保域名解析正确指向服务器IP"

if [[ ! -f "/etc/ssl/private/fullchain.cer" ]]; then
    echo "4. 如需SSL，请确保域名解析后重新运行脚本"
fi

echo "=================================================="
