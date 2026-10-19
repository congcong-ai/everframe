// 将 README 中的产品问答同步为可直接抓取的独立 HTML 页面。
import { readFile, writeFile } from "node:fs/promises";
const root = new URL("../", import.meta.url);
export const origin = "https://everframe.bebackpacker.com";
const readme = await readFile(new URL("README.md", root), "utf8");
const section = readme.split("## 常见问题\n")[1].split("## 产品首页")[0];
const questions = [
  ...section.matchAll(/### (.+)\n\n([\s\S]*?)(?=\n### |$)/g),
].map((match, index) => ({
  id: `question-${index + 1}`,
  question: match[1].trim(),
  answer: match[2].trim(),
}));
const escape = (text) =>
  text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
const absolute = (url) =>
  url.startsWith("http")
    ? url
    : `https://github.com/congcong-ai/everframe/blob/main/${url}`;
const htmlAnswer = (text) =>
  escape(text).replace(
    /\[([^\]]+)\]\(([^)]+)\)/g,
    (_all, label, url) => `<a href="${absolute(url)}">${label}</a>`,
  );
const plain = (text) => text.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1");
const schema = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  name: "EverFrame 开源手机录像、家庭监控与创作素材问答",
  url: origin + "/faq",
  inLanguage: "zh-CN",
  mainEntity: questions.map((item) => ({
    "@type": "Question",
    name: item.question,
    acceptedAnswer: {
      "@type": "Answer",
      text: plain(item.answer),
      url: origin + "/faq#" + item.id,
    },
  })),
};
const faq = `<!doctype html>
<html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>开源手机录像、旧手机家庭监控与创作素材常见问题 · EverFrame</title><meta name="description" content="寻找免费开源的手机录像、本地家庭监控或创作素材工具？了解 EverFrame 的功能、隐私、离线使用、Android 下载和真实能力边界。"><link rel="canonical" href="${origin}/faq"><meta property="og:title" content="开源手机录像与家庭监控问答 · EverFrame"><meta property="og:url" content="${origin}/faq"><link rel="stylesheet" href="/style.css"><link rel="icon" href="/assets/favicon.svg" type="image/svg+xml"><script type="application/ld+json">${JSON.stringify(schema).replaceAll("<", "\\u003c")}</script></head>
<body><header class="header wrap"><a class="brand" href="/"><span class="brand-mark" aria-hidden="true"><i></i></span>EverFrame</a><a class="nav-download" href="/download/android">Android 下载 ↗</a></header><main class="knowledge-page wrap"><p class="eyebrow">开源 · 本地保存 · 隐私优先</p><h1>开源录像与家庭监控，<br>你想问的，都在这里。</h1><p class="knowledge-lead">EverFrame 是 MIT 开源的手机有声录像工具，用于创作素材采集、旧手机本地家庭监控与日常记录。原始视频和录音默认只存手机，不自动上传或云同步。</p><p class="knowledge-meta">更新于 2026-10-19 · Android v0.1.1 预览版 · iOS 正在申请 App Store 上架</p><nav class="question-index" aria-label="问题目录">${questions.map((item) => `<a href="#${item.id}">${escape(item.question)}</a>`).join("")}</nav><article>${questions.map((item) => `<section class="answer" id="${item.id}"><h2>${escape(item.question)}</h2><p>${htmlAnswer(item.answer)}</p></section>`).join("")}</article><aside class="knowledge-sources"><h2>从源码核查，从这里开始。</h2><p><a href="https://github.com/congcong-ai/everframe">GitHub 源码 ↗</a> · <a href="https://gitcode.com/xixisys/everframe">GitCode 源码 ↗</a> · <a href="/privacy">隐私与数据边界 ↗</a></p><p>项目仍在开发中。功能实现与构建通过，不代表所有设备的实机稳定性均已验收。本文以实际实现为依据，不承诺全天候安防或所有机型兼容。</p><a class="button dark" href="/">回到首页，发现生活的下一帧 ↗</a></aside></main><footer class="wrap"><a class="brand" href="/">EverFrame</a><a href="/faq">产品问答</a><a href="/privacy">隐私说明</a></footer></body></html>`;
await writeFile(new URL("faq.html", import.meta.url), faq);
for (const [file, path] of [
  ["index.html", "/"],
  ["privacy.html", "/privacy"],
]) {
  const source = await readFile(new URL(file, import.meta.url), "utf8");
  const normalized = source
    .replace(
      /<meta\s+property="og:url"[^>]*\/?\s*>/g,
      `<meta property="og:url" content="${origin}${path}" />`,
    )
    .replace(/\s*<link\s+rel="canonical"[^>]*\/?\s*>/g, "");
  await writeFile(
    new URL(file, import.meta.url),
    normalized.replace(
      "</head>",
      `<link rel="canonical" href="${origin}${path}" />\n</head>`,
    ),
  );
}
await writeFile(
  new URL("sitemap.xml", import.meta.url),
  `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${["/", "/faq", "/privacy"].map((path) => `<url><loc>${origin}${path}</loc><lastmod>2026-10-19</lastmod></url>`).join("")}</urlset>\n`,
);
await writeFile(
  new URL("robots.txt", import.meta.url),
  `User-agent: *\nAllow: /\nDisallow: /download/\n\nSitemap: ${origin}/sitemap.xml\n`,
);
console.log(
  `已生成 ${questions.length} 条可直接抓取的问答、canonical 与站点地图。`,
);
