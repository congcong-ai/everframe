// 将已有 Android APK 发布到 GitCode；不重新构建、不删除历史附件。
import { openAsBlob } from "node:fs";
import { readFile as read, stat as fileStat } from "node:fs/promises";
import { createHash } from "node:crypto";
import { basename, resolve } from "node:path";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../", import.meta.url));
try {
  process.loadEnvFile(resolve(root, ".env"));
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}
const [tag, input] = process.argv.slice(2);
const {
  GITCODE_TOKEN: token,
  GITCODE_OWNER: owner = "xixisys",
  GITCODE_REPO: repo = "everframe",
} = process.env;
if (!/^v\d+\.\d+\.\d+$/.test(tag || "") || !input || !token) {
  console.error(
    "用法：node scripts/publish-android.mjs v0.1.1 /绝对路径/everframe-android-v0.1.1-debug.apk；请先配置 .env 中的 GITCODE_TOKEN。",
  );
  process.exit(1);
}
const path = resolve(input),
  name = basename(path);
if (name !== `everframe-android-${tag}-debug.apk`)
  throw new Error("APK 文件名必须与发布版本一致");
const size = (await fileStat(path)).size;
const digest = createHash("sha256")
  .update(await read(path))
  .digest("hex");
const base = `https://api.gitcode.com/api/v5/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/releases`;
async function api(suffix, init = {}, params = {}) {
  const url = new URL(base + suffix);
  url.searchParams.set("access_token", token);
  for (const [key, value] of Object.entries(params))
    url.searchParams.set(key, value);
  const response = await fetch(url, {
    ...init,
    signal: AbortSignal.timeout(30000),
  });
  if (!response.ok)
    throw new Error(`GitCode API 失败（HTTP ${response.status}）`);
  return response.json();
}
async function verify(asset, expected) {
  const url = new URL(asset.browser_download_url);
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.searchParams.has("access_token")
  )
    throw new Error("附件下载地址无效");
  const response = await fetch(url, { signal: AbortSignal.timeout(120000) });
  if (
    !response.ok ||
    response.headers.get("content-type")?.includes("text/html")
  )
    throw new Error("附件无法直接下载");
  const hash = createHash("sha256");
  for await (const chunk of response.body) hash.update(chunk);
  if (hash.digest("hex") !== expected)
    throw new Error(
      "远端 SHA-256 与本地不一致；保留本地文件，请使用新版本重新发布",
    );
}
try {
  let release;
  const checkURL = new URL(base + "/tags/" + tag);
  checkURL.searchParams.set("access_token", token);
  const check = await fetch(checkURL, { signal: AbortSignal.timeout(30000) });
  if (check.ok) release = await check.json();
  else if (check.status === 404)
    release = await api("", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        tag_name: tag,
        target_commitish: "main",
        name: `EverFrame ${tag} · Android 预览版`,
        release_status: "pre",
        body: `免费开源的本机录像工具。Android 8.0 及以上，开发签名预览版。\n\n原始音视频默认保存在手机，无自动云同步。\n源码：https://github.com/congcong-ai/everframe\n\nSHA-256：${digest}`,
      }),
    });
  else throw new Error(`查询 Release 失败（HTTP ${check.status}）`);
  const checksum = Buffer.from(`${digest}  ${name}\n`);
  for (const item of [
    { name, body: await openAsBlob(path), digest },
    {
      name: name + ".sha256",
      body: new Blob([checksum]),
      digest: createHash("sha256").update(checksum).digest("hex"),
    },
  ]) {
    release = await api("/tags/" + tag);
    let assets = (release.assets || []).filter(
      (asset) => asset.name === item.name,
    );
    if (assets.length > 1) throw new Error("存在重复附件，请人工检查");
    if (!assets.length) {
      const signed = await api(
        "/" + tag + "/upload_url",
        {},
        { file_name: item.name },
      );
      if (new URL(signed.url).protocol !== "https:")
        throw new Error("上传地址无效");
      const result = await fetch(signed.url, {
        method: "PUT",
        headers: signed.headers,
        body: item.body,
        signal: AbortSignal.timeout(180000),
        redirect: "error",
      });
      if (!result.ok)
        throw new Error(`上传失败（HTTP ${result.status}），本地文件已保留`);
      for (let attempt = 0; attempt < 5; attempt++) {
        release = await api("/tags/" + tag);
        assets = (release.assets || []).filter(
          (asset) => asset.name === item.name,
        );
        if (assets.length) break;
        await new Promise((done) => setTimeout(done, 1000));
      }
    }
    if (assets.length !== 1) throw new Error("上传后未找到唯一附件");
    await verify(assets[0], item.digest);
    console.log(`${item.name}：远端 SHA-256 校验通过`);
  }
  console.log(
    `发布完成：https://gitcode.com/${owner}/${repo}/releases/${tag}（APK ${(size / 1024 / 1024).toFixed(2)} MB）`,
  );
} catch (error) {
  console.error(
    String(error.message)
      .split(token)
      .join("[已脱敏]")
      .replace(/([?&]access_token=)[^&\s]+/g, "$1[已脱敏]"),
  );
  process.exitCode = 1;
}
