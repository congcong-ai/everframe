import { mkdtempSync, mkdirSync, copyFileSync, readdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join, resolve, basename } from "node:path";
import { tmpdir } from "node:os";
import { createHash, randomBytes } from "node:crypto";
const output = resolve(process.argv[2] || mkdtempSync(join(tmpdir(), "everframe-release-")));
mkdirSync(output, { recursive: true });
const stage = mkdtempSync(join(tmpdir(), "everframe-stage-"));
const run = (cmd, args) => execFileSync(cmd, args, { stdio: "inherit", env: { ...process.env, COPYFILE_DISABLE: "1" } });
try {
  run("pnpm", ["install", "--frozen-lockfile"]);
  run("node", ["--test", ...readdirSync("website/tests").filter(x => x.endsWith(".test.mjs")).map(x => "website/tests/" + x)]);
  const scripts = ["server-install.sh", "server-deploy.sh", "server-common.sh", "native-service.sh"];
  for (const file of scripts) run("bash", ["-n", "scripts/" + file]);
  const website = ["package.json", "index.html", "faq.html", "privacy.html", "style.css", "app.js", "server.mjs", "download.mjs", "robots.txt", "llms.txt", "sitemap.xml", ...readdirSync("website/assets").map(x => "assets/" + x)];
  for (const file of website) {
    if (/\.m?js$/.test(file)) run("node", ["--check", "website/" + file]);
  }
  const files = [...website.map(x => "website/" + x), ...scripts.map(x => "scripts/" + x), "scripts/server-port-audit.py", "deploy/ecosystem.config.cjs", "deploy/nginx.conf.template"];
  for (const file of files) {
    const target = join(stage, "release", file);
    mkdirSync(resolve(target, ".."), { recursive: true });
    copyFileSync(file, target);
  }
  const id = new Date().toISOString().replace(/[-:.]/g, "") + "-" + randomBytes(4).toString("hex");
  writeFileSync(join(stage, "release/RELEASE_ID"), id + "\n");
  const archive = join(output, "everframe-" + id + ".tar.gz");
  run("tar", ["-czf", archive, "-C", stage, "release"]);
  const entries = execFileSync("tar", ["-tzf", archive], { encoding: "utf8" });
  if (/\.env|node_modules|__MACOSX|\/\._|\.git\//m.test(entries)) throw Error("发布包包含禁止文件");
  const digest = createHash("sha256").update(readFileSync(archive)).digest("hex");
  writeFileSync(archive + ".sha256", digest + "  " + basename(archive) + "\n");
  writeFileSync(join(output, "latest-release.txt"), archive + "\n");
  console.log("发布包已测试并生成：" + archive);
} finally { rmSync(stage, { recursive: true, force: true }); }
