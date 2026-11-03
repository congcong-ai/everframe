#!/usr/bin/env bash
set -euo pipefail
release="${1:?缺少发布目录}"
source "$release/scripts/server-common.sh"
[[ "$EUID" == 0 ]] || exit 1
if [[ "${EVERFRAME_LOCK_HELD:-0}" != 1 ]]; then
 exec 9>"$base/shared/deploy.lock"; flock -n 9 || { echo '已有安装或部署正在执行'; exit 1; }
fi
verify_target
id="$(cat "$release/RELEASE_ID")"
[[ "$id" =~ ^[A-Za-z0-9-]+$ ]] || exit 1
next="$base/releases/$id"
required_kb="$(du -sk "$release" | awk '{print $1 * 3 + 10240}')"
available_kb="$(df -Pk "$base" | awk 'NR==2 {print $4}')"
(( available_kb > required_kb )) || { echo '磁盘可用空间不足，停止部署'; exit 1; }
[[ ! -e "$next" ]] || { echo '发布版本已存在'; exit 1; }
mkdir "$next"
cp -a "$release/." "$next/"
# 跳过各级共享依赖和软链目标，避免影响其他项目。
find "$next" -name node_modules -type d -prune -o -exec chown -h everframe:everframe {} +
ln -s "$base/shared/.env" "$next/.env"
old="$(readlink -f "$base/current" || true)"
rollback() {
 result=$?
 trap - ERR
 echo '新版本未通过验收，恢复上一版本'
 as_app pm2 stop everframe-web || true
 if [[ -n "$old" && -d "$old" ]]; then
  ln -sfn "$old" "$base/current.rollback"; mv -Tf "$base/current.rollback" "$base/current"
  as_app pm2 startOrRestart "$old/deploy/ecosystem.config.cjs" --update-env
  health && as_app pm2 save --force
 else
  as_app pm2 delete everframe-web || true
  rm -f "$base/current"
 fi
 exit "$result"
}
trap rollback ERR
stop_own_service
# 停止本站服务后，重新审计监听者及其它站点的端口预留。
python3 "$next/scripts/server-port-audit.py" --check "$PORT" "$PORT" ${EVERFRAME_NGINX_CHECK:+--project-nginx} ${EVERFRAME_NGINX_CHECK:+/etc/nginx/sites-available/everframe}
ln -sfn "$next" "$base/current.next"; mv -Tf "$base/current.next" "$base/current"
as_app pm2 startOrRestart "$next/deploy/ecosystem.config.cjs" --update-env
health
for path in / /faq /privacy /robots.txt /llms.txt /sitemap.xml /assets/favicon.svg; do
 curl --noproxy '*' -fsS --max-time 5 "http://127.0.0.1:$PORT$path" >/dev/null
done
as_app pm2 save --force
trap - ERR
# 只保留当前健康版本与最近一个健康版本。
for item in "$base"/releases/*; do
 [[ "$item" == "$next" || "$item" == "$old" ]] || rm -rf -- "$item"
done
echo "日常部署完成：$id"
