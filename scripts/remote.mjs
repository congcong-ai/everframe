import { existsSync, readFileSync, mkdtempSync, rmSync } from "node:fs";
import { parseEnv } from "node:util";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, basename } from "node:path";
import { createHash } from "node:crypto";
process.chdir(new URL("..", import.meta.url).pathname);
const [mode, ...args] = process.argv.slice(2);
try {
  if (!["install", "deploy", "ports"].includes(mode) || args.some(x => !["--check", "--help"].includes(x))) throw Error("用法：pnpm server:install|server:deploy [--check]，或 pnpm server:ports");
  if (args.includes("--help")) { console.log("配置读取根目录 .env，再以 .deploy.env 覆盖；--check 只校验配置，不连接服务器。首次安装需要审计并确认 DEPLOY_WEB_PORT。日常部署从服务器复用端口。"); process.exit(0); }
  const config = {};
  for (const file of [".env", ".deploy.env"]) if (existsSync(file)) Object.assign(config, parseEnv(readFileSync(file, "utf8")));
  const get = (key, fallback = "") => config["DEPLOY_" + key] || fallback;
  const host = get("SSH_HOST"), user = get("SSH_USER", "deployer"), port = get("SSH_PORT", "22");
  const domain = get("DOMAIN", "everframe.bebackpacker.com"), email = get("TLS_EMAIL", "revival.wgj@gmail.com"), web = get("WEB_PORT");
  const root = get("ROOT", "/var/www/everframe");
  const validPort = x => /^\d+$/.test(x) && +x > 0 && +x < 65536;
  const hostname = /^[a-zA-Z0-9][a-zA-Z0-9.-]*$/;
  if (!hostname.test(host) || !/^[a-z_][a-z0-9_-]*$/.test(user) || !validPort(port) || !hostname.test(domain) || !/^[-a-zA-Z0-9._+]+@[-a-zA-Z0-9.]+$/.test(email) || root !== "/var/www/everframe") throw Error("SSH、域名、邮箱或部署目录配置无效");
  const proxy = get("USE_PROXY", "false"), proxyHost = get("PROXY_HOST", "127.0.0.1"), socksPort = get("PROXY_PORT", "1080"), httpPort = get("HTTP_PROXY_PORT", "1087");
  if (!["true", "false"].includes(proxy) || !hostname.test(proxyHost) || !validPort(socksPort) || !validPort(httpPort)) throw Error("代理配置无效");
  if (web && (!validPort(web) || +web <= 1024 || +web >= 32768)) throw Error("网站端口应位于 1025 至 32767");
  if (args.includes("--check")) { console.log(`配置通过：${user}@${host}:${port} → https://${domain}，目录 ${root}，端口 ${web || "读取既有安装配置"}`); process.exit(0); }
  const env = { ...process.env, COPYFILE_DISABLE: "1" };
  for (const key of ["all_proxy", "ALL_PROXY", "http_proxy", "HTTP_PROXY", "https_proxy", "HTTPS_PROXY", "no_proxy", "NO_PROXY"]) delete env[key];
  const run = (cmd, argv, capture = false) => execFileSync(cmd, argv, { env, stdio: capture ? ["ignore", "pipe", "inherit"] : "inherit", encoding: "utf8" });
  const quote = s => "'" + s.replaceAll("'", "'\\''") + "'";
  const options = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=4"];
  const ssh = (command, capture = false) => run("ssh", ["-T", ...options, "-p", port, `${user}@${host}`, command], capture);
  if (mode === "ports") {
    run("scp", [...options, "-P", port, "scripts/server-port-audit.py", `${user}@${host}:/tmp/everframe-port-audit.py`]);
    ssh("sudo -n env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin python3 /tmp/everframe-port-audit.py");
    process.exit(0);
  }
  // 先验证目标身份和安装标记；已安装时首次入口不再构建或上传。
  const check = `set -e; if [ -f ${root}/shared/.env ]; then . ${root}/shared/.env; test "$APP_ORIGIN" = ${quote("https://" + domain)}; fi; if [ -f ${root}/shared/installed ]; then test -f ${root}/shared/.env; printf installed; else printf pending; fi`;
  const status = ssh("sudo -n bash -c " + quote(check), true).trim();
  if (!["installed", "pending"].includes(status)) throw Error("无法确认安装状态");
  if (mode === "install" && status === "installed") { console.log("首次安装已完成；后续请执行 pnpm server:deploy"); process.exit(0); }
  if (mode === "deploy" && status !== "installed") throw Error("请先执行 pnpm server:install 完成首次安装");
  if (mode === "install" && !web) throw Error("先执行 pnpm server:ports，确认空闲端口后填写 .deploy.env 的 DEPLOY_WEB_PORT");
  const work = mkdtempSync(join(tmpdir(), "everframe-publish-"));
  try {
    run("bash", ["scripts/build-release.sh", work]);
    const archive = readFileSync(join(work, "latest-release.txt"), "utf8").trim();
    const name = basename(archive);
    if (!/^everframe-[A-Za-z0-9-]+\.tar\.gz$/.test(name)) throw Error("发布包名称无效");
    const digest = createHash("sha256").update(readFileSync(archive)).digest("hex");
    run("scp", [...options, "-P", port, archive, archive + ".sha256", `${user}@${host}:/tmp/`]);
    const variables = { DEPLOY_DOMAIN: domain, DEPLOY_TLS_EMAIL: email, DEPLOY_SSH_HOST: host, DEPLOY_WEB_PORT: web, DEPLOY_USE_PROXY: proxy, DEPLOY_PROXY_HOST: proxyHost, DEPLOY_PROXY_PORT: socksPort, DEPLOY_HTTP_PROXY_PORT: httpPort };
    const assignments = Object.entries(variables).map(([k,v]) => k + "=" + quote(v)).join(" ");
    const script = `set -euo pipefail
cd /tmp
printf '%s  %s\\n' '${digest}' '${name}' | sha256sum -c -
stage=$(mktemp -d /tmp/everframe-upload.XXXXXX)
trap 'rm -rf "$stage"; rm -f /tmp/${name} /tmp/${name}.sha256' EXIT
tar --no-same-owner --no-same-permissions -xzf '${name}' -C "$stage"
${mode === "deploy" ? "export EVERFRAME_NGINX_CHECK=1" : ""}
env ${assignments} bash "$stage/release/scripts/server-${mode}.sh" "$stage/release"`;
    ssh("sudo -n bash -c " + quote(script));
    console.log(`完成：https://${domain}`);
  } finally { rmSync(work, { recursive: true, force: true }); }
} catch (error) { console.error("执行失败：" + (error.status ? `子命令退出码 ${error.status}，详见上方输出` : error.message)); process.exitCode = 1; }
