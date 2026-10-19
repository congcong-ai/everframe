import test from "node:test";
import assert from "node:assert/strict";
import {
  selectAPK,
  resolveAPK,
  fallbackAPK,
  directURL,
  safeURL,
} from "../download.mjs";
import { createWebsiteServer } from "../server.mjs";
const release = (version, options = {}) => ({
  tag_name: version,
  release_status: "pre",
  assets: [
    {
      name: `everframe-android-${version}-debug.apk`,
      type: "attach",
      browser_download_url: `https://gitcode.com/xixisys/everframe/releases/download/${version}/everframe-android-${version}-debug.apk`,
    },
  ],
  ...options,
});
const headOK = () =>
  new Response(null, {
    headers: { "content-type": "application/vnd.android.package-archive" },
  });
test("GitCode 按版本号选取 APK，允许预览版且不依赖缺失的 size/state 字段", () => {
  const selected = release("v0.1.10");
  assert.equal(
    selectAPK([
      release("v0.1.2"),
      release("v2.0.0", { draft: true }),
      release("v3.0.0", { assets: [] }),
      selected,
    ]),
    selected.assets[0].browser_download_url,
  );
});
test("拒绝源码附件、外站地址、版本不符及带认证信息地址", () => {
  const invalid = release("v3.0.0");
  invalid.assets[0].browser_download_url = "https://example.com/fake.apk";
  const source = release("v4.0.0");
  source.assets[0].type = "source";
  const mismatch = release("v5.0.0");
  mismatch.assets[0].name = "everframe-android-v1.0.0-debug.apk";
  assert.equal(selectAPK([invalid, source, mismatch]), undefined);
  for (const url of [
    "http://example.com/file",
    "https://user:pass@example.com/file",
    "https://example.com/file?ACCESS_TOKEN=secret",
    "not-a-url",
  ])
    assert.equal(safeURL(url), undefined);
});
test("GitCode HEAD 401 时通过 GET 302 和 CDN HEAD 验证，不读取 APK 内容", async () => {
  let cancelled = false;
  const calls = [];
  const result = await directURL(fallbackAPK, async (url, options) => {
    calls.push([url, options.method || "GET"]);
    if (url === "https://cdn.example.com/file.apk") return headOK();
    if (options.method === "HEAD") return new Response(null, { status: 401 });
    return {
      status: 302,
      headers: new Headers({ location: "https://cdn.example.com/file.apk" }),
      body: {
        cancel: async () => {
          cancelled = true;
        },
      },
    };
  });
  assert.equal(result, "https://cdn.example.com/file.apk");
  assert.equal(cancelled, true);
  assert.equal(calls.length, 3);
});
test("下载探针拒绝 HTML 和非 HTTPS 跳转", async () => {
  assert.equal(
    await directURL(
      fallbackAPK,
      async () =>
        new Response(null, { headers: { "content-type": "text/html" } }),
    ),
    undefined,
  );
  assert.equal(
    await directURL(fallbackAPK, async (_url, options) =>
      options.method === "HEAD"
        ? new Response(null, { status: 401 })
        : new Response(null, {
            status: 302,
            headers: { location: "http://example.com/file.apk" },
          }),
    ),
    undefined,
  );
});
test("API 故障与空列表回退 GitCode 固定下载，不回退 GitHub", async () => {
  for (const fetcher of [
    async () => ({ ok: false }),
    async () => ({ ok: true, json: async () => [] }),
    async () => {
      throw Error("网络错误");
    },
  ])
    assert.equal(await resolveAPK(fetcher), fallbackAPK);
  assert.ok(fallbackAPK.startsWith("https://gitcode.com/"));
});
test("多页发布记录中选最高版本并探测真实下载", async () => {
  const latest = release("v1.0.0");
  const target = await resolveAPK(async (url, options) =>
    options.method === "HEAD"
      ? headOK()
      : {
          ok: true,
          json: async () =>
            url.endsWith("page=1")
              ? Array.from({ length: 100 }, () => release("v0.1.1"))
              : [latest],
        },
  );
  assert.equal(target, latest.assets[0].browser_download_url);
});
test("官网资源、隐私页、机器可读内容、302、HEAD 与私有文件隔离", async (t) => {
  const server = createWebsiteServer({
    resolveDownload: async () => fallbackAPK,
  });
  await new Promise((done) => server.listen(0, "127.0.0.1", done));
  t.after(() => new Promise((done) => server.close(done)));
  const base = `http://127.0.0.1:${server.address().port}`;
  for (const path of [
    "/",
    "/privacy",
    "/faq",
    "/sitemap.xml",
    "/robots.txt",
    "/llms.txt",
    "/style.css",
    "/app.js",
    "/assets/forest.jpg",
    "/assets/create.jpg",
    "/assets/cat.jpg",
    "/assets/favicon.svg",
  ]) {
    const response = await fetch(base + path);
    assert.equal(response.status, 200, path);
    assert.ok((await response.arrayBuffer()).byteLength > 0);
  }
  const html = await (await fetch(base)).text();
  const faqHTML = await (await fetch(base + "/faq")).text();
  const schema = JSON.parse(
    faqHTML.match(
      /<script type="application\/ld\+json">([\s\S]*?)<\/script>/,
    )[1],
  );
  assert.equal(schema["@type"], "FAQPage");
  assert.equal(schema.mainEntity.length, 10);
  for (const item of schema.mainEntity) assert.ok(faqHTML.includes(item.name));
  assert.ok(html.includes('href="/faq"'));
  assert.ok(html.includes("https://github.com/congcong-ai/everframe"));
  assert.ok(html.includes("https://gitcode.com/xixisys/everframe"));
  const download = await fetch(base + "/download/android", {
    redirect: "manual",
  });
  assert.equal(download.status, 302);
  assert.equal(download.headers.get("location"), fallbackAPK);
  assert.equal(download.headers.get("cache-control"), "no-store");
  assert.equal(await download.text(), "");
  const head = await fetch(base, { method: "HEAD" });
  assert.equal(head.status, 200);
  assert.equal(await head.text(), "");
  for (const path of [
    "/server.mjs",
    "/package.json",
    "/.env",
    "/assets/../server.mjs",
  ])
    assert.equal((await fetch(base + path)).status, 404);
});
