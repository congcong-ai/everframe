#!/usr/bin/env bash
set -euo pipefail
release="${1:?缺少发布目录}"
source "$release/scripts/server-common.sh"
[[ "$EUID" == 0 ]] || exit 1
[[ ! -f "$base/shared/installed" ]] || { verify_target; echo '首次安装已完成'; exit 0; }
mkdir -p "$base/shared"
exec 9>"$base/shared/deploy.lock"; flock -n 9 || { echo '已有安装或部署正在执行'; exit 1; }
apt-get check
packages=()
for pair in nginx:nginx certbot:certbot curl:curl lsof:lsof ss:iproute2 python3:python3; do command -v "${pair%%:*}" >/dev/null || packages+=("${pair#*:}"); done
if ! dpkg-query -W -f='${Status}' python3-certbot-nginx 2>/dev/null | grep -q 'install ok installed'; then packages+=(python3-certbot-nginx); fi
if ((${#packages[@]})); then
 plan="$(apt-get -s install --no-upgrade "${packages[@]}")"
 if grep -Eq '^Remv|^Inst [^ ]+ \[' <<< "$plan"; then printf '%s\n' "$plan"; echo '安装涉及升级或删除已有软件，已停止'; exit 1; fi
 apt-get install -y --no-upgrade "${packages[@]}"
fi
/usr/bin/node -e 'if(+process.versions.node.split(".")[0]<22)process.exit(1)' || { echo '需要 Node.js 22 或更新版本，不替换共享服务器运行时'; exit 1; }
command -v pm2 >/dev/null || { echo '需要服务器已有 PM2，请先安装兼容版本'; exit 1; }
if [[ ! -f "$base/shared/.env" ]]; then
 [[ "${DEPLOY_WEB_PORT:-}" =~ ^[0-9]+$ ]] && (( DEPLOY_WEB_PORT > 1024 && DEPLOY_WEB_PORT < 32768 )) || { echo '先执行 server:ports，确认后填写 DEPLOY_WEB_PORT'; exit 1; }
 python3 "$release/scripts/server-port-audit.py" --choose
 python3 "$release/scripts/server-port-audit.py" --check "$DEPLOY_WEB_PORT" "$DEPLOY_WEB_PORT"
 if id everframe >/dev/null 2>&1; then echo '专用用户已存在但本站配置缺失，请先核对归属'; exit 1; fi
 useradd --system --create-home --home-dir "$runtime_home" --shell /usr/sbin/nologin everframe
 install -d -o everframe -g everframe "$base/releases" "$base/shared/logs"
 cat > "$base/shared/.env" <<EOF
NODE_ENV=production
APP_ORIGIN=https://$DEPLOY_DOMAIN
HOST=127.0.0.1
PORT=$DEPLOY_WEB_PORT
EOF
 chmod 600 "$base/shared/.env"; chown everframe:everframe "$base/shared/.env"
 cat > "$base/shared/install.env" <<EOF
DEPLOY_DOMAIN=$DEPLOY_DOMAIN
DEPLOY_WEB_PORT=$DEPLOY_WEB_PORT
DEPLOY_TLS_EMAIL=$DEPLOY_TLS_EMAIL
DEPLOY_USE_PROXY=${DEPLOY_USE_PROXY:-false}
DEPLOY_PROXY_HOST=${DEPLOY_PROXY_HOST:-127.0.0.1}
DEPLOY_PROXY_PORT=${DEPLOY_PROXY_PORT:-1080}
DEPLOY_HTTP_PROXY_PORT=${DEPLOY_HTTP_PROXY_PORT:-1087}
EOF
fi
verify_target
config=/etc/nginx/sites-available/everframe
if [[ -e "$config" ]]; then
 head -1 "$config" | grep -qx '# 由 EverFrame 安装器管理' || { echo '同名 Nginx 配置不属于本站，停止覆盖'; exit 1; }
 export EVERFRAME_NGINX_CHECK=1
else
 if nginx -T 2>/dev/null | grep -E "server_name .*${DEPLOY_DOMAIN//./\.}([ ;]|$)"; then echo '域名已被其它 Nginx 配置使用'; exit 1; fi
fi
EVERFRAME_LOCK_HELD=1 bash "$release/scripts/server-deploy.sh" "$release"
if [[ ! -e "$config" ]]; then
 sed -e "s/__DOMAIN__/$DEPLOY_DOMAIN/g" -e "s/__WEB_PORT__/$PORT/g" "$release/deploy/nginx.conf.template" > "$config"
 ln -s "$config" /etc/nginx/sites-enabled/everframe
 if ! nginx -t; then rm -f /etc/nginx/sites-enabled/everframe "$config"; exit 1; fi
 systemctl reload nginx
fi
pm2 startup systemd -u everframe --hp "$runtime_home"
as_app pm2 save --force
systemctl stop pm2-everframe
if [[ -S "$runtime_home/.pm2/rpc.sock" ]]; then as_app pm2 kill; fi
systemctl enable pm2-everframe
systemctl start pm2-everframe
systemctl is-active --quiet pm2-everframe
systemctl is-enabled --quiet pm2-everframe
health
# DNS 未就绪时保留已启动的 HTTP 服务，重跑首次安装可继续签发证书。
python3 - "$DEPLOY_DOMAIN" "$DEPLOY_SSH_HOST" <<'DNS'
import socket,sys
addresses={x[4][0] for x in socket.getaddrinfo(sys.argv[1],80)}
if sys.argv[2] not in addresses: raise SystemExit('域名未指向目标服务器，请设置 A 记录后重跑首次安装')
DNS
certbot_log="$(mktemp /tmp/everframe-certbot.XXXXXX)"
trap 'rm -f "$certbot_log"' EXIT
certified=false
for attempt in {1..60}; do
 if certbot --nginx --non-interactive --agree-tos --redirect --keep-until-expiring -d "$DEPLOY_DOMAIN" -m "$DEPLOY_TLS_EMAIL" >"$certbot_log" 2>&1; then
  cat "$certbot_log"; certified=true; break
 fi
 if grep -q 'Another instance of Certbot is already running' "$certbot_log"; then
  echo "已有 Certbot 任务运行，等待释放锁（$attempt/60）"; sleep 10
 else cat "$certbot_log"; exit 1; fi
done
[[ "$certified" == true ]] || { cat "$certbot_log"; echo '等待证书任务超时，请稍后重跑首次安装'; exit 1; }
nginx -t
curl --noproxy '*' --resolve "$DEPLOY_DOMAIN:443:127.0.0.1" -fsS "https://$DEPLOY_DOMAIN/healthz"
touch "$base/shared/installed"
echo "首次安装及首次发布完成：https://$DEPLOY_DOMAIN"
echo "生产配置：$base/shared/.env；后续使用 pnpm server:deploy"
