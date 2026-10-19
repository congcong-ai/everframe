#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
base=/var/www/everframe
runtime_home=/var/lib/everframe
for key in all_proxy ALL_PROXY http_proxy HTTP_PROXY https_proxy HTTPS_PROXY no_proxy NO_PROXY; do unset "$key"; done
case "${DEPLOY_USE_PROXY:-false}" in
 true)
  [[ "${DEPLOY_PROXY_HOST:-127.0.0.1}" =~ ^[a-zA-Z0-9.-]+$ ]] || exit 1
  for value in "${DEPLOY_PROXY_PORT:-1080}" "${DEPLOY_HTTP_PROXY_PORT:-1087}"; do [[ "$value" =~ ^[0-9]+$ ]] && ((value > 0 && value < 65536)) || exit 1; done
  export all_proxy="socks5://${DEPLOY_PROXY_HOST:-127.0.0.1}:${DEPLOY_PROXY_PORT:-1080}"; export ALL_PROXY="$all_proxy"
  export http_proxy="http://${DEPLOY_PROXY_HOST:-127.0.0.1}:${DEPLOY_HTTP_PROXY_PORT:-1087}"; export https_proxy="$http_proxy" HTTP_PROXY="$http_proxy" HTTPS_PROXY="$http_proxy"
  export no_proxy=127.0.0.1,localhost NO_PROXY=127.0.0.1,localhost;;
 false) ;;
 *) echo '代理开关无效'; exit 1;;
esac
as_app() {
 runuser -u everframe -- env -u all_proxy -u ALL_PROXY -u http_proxy -u HTTP_PROXY -u https_proxy -u HTTPS_PROXY -u no_proxy -u NO_PROXY HOME="$runtime_home" PM2_HOME="$runtime_home/.pm2" "$@"
}
verify_target() {
 [[ -f "$base/shared/.env" ]] || { echo '缺少生产配置'; exit 1; }
 set -a; source "$base/shared/.env"; set +a
 [[ "$APP_ORIGIN" == "https://$DEPLOY_DOMAIN" && "$HOST" == 127.0.0.1 && "$PORT" =~ ^[0-9]+$ ]] || { echo '服务器域名或监听配置不匹配'; exit 1; }
}
health() {
 for attempt in {1..20}; do
  if curl --noproxy '*' -fsS --max-time 3 "http://127.0.0.1:$PORT/healthz" | /usr/bin/node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{try{const j=JSON.parse(s);process.exit(j.status==="ok"&&j.service==="everframe-website"?0:1)}catch{process.exit(1)}})'; then return 0; fi
  sleep 1
 done
 return 1
}
stop_own_service() {
 # 仅停止本站进程，再检查端口；绝不杀死其它项目的监听者。
 if [[ -S "$runtime_home/.pm2/rpc.sock" ]]; then as_app pm2 stop everframe-web || true; fi
 local pids
 pids="$(lsof -t -iTCP:"$PORT" -sTCP:LISTEN || true)"
 if [[ -n "$pids" ]]; then
  for pid in $pids; do
   [[ "$(ps -o user= -p "$pid" | tr -d ' ')" == everframe ]] || { echo "端口 $PORT 被其它服务占用，停止部署"; return 1; }
  done
  kill $pids
  for attempt in {1..10}; do [[ -z "$(lsof -t -iTCP:"$PORT" -sTCP:LISTEN || true)" ]] && return 0; sleep 1; done
  echo '本站端口未释放'; return 1
 fi
}
