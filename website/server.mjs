import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { resolve, extname, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { resolveAPK } from "./download.mjs";

const root = fileURLToPath(new URL(".", import.meta.url));
const publicFiles = new Set([
  "index.html",
  "style.css",
  "app.js",
  "privacy.html",
  "faq.html",
  "sitemap.xml",
  "robots.txt",
  "llms.txt",
]);
const types = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".jpg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".xml": "application/xml; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
};
export function createWebsiteServer({ resolveDownload = resolveAPK } = {}) {
  let pending;
  return createServer(async (request, response) => {
    try {
      if (!["GET", "HEAD"].includes(request.method)) {
        response.writeHead(405, { Allow: "GET, HEAD" }).end("请求方法不支持");
        return;
      }
      const pathname = decodeURIComponent(
        new URL(request.url, "http://localhost").pathname,
      );
      if (
        pathname === "/download/android" ||
        pathname === "/download/android/"
      ) {
        pending ||= resolveDownload();
        let target;
        try {
          target = await pending;
        } finally {
          pending = undefined;
        }
        response
          .writeHead(302, { Location: target, "Cache-Control": "no-store" })
          .end();
        return;
      }
      if (pathname === "/healthz") {
        response.writeHead(200, {
          "Content-Type": "application/json; charset=utf-8",
          "Cache-Control": "no-store",
        });
        response.end(
          request.method === "HEAD"
            ? undefined
            : JSON.stringify({ status: "ok", service: "everframe-website" }),
        );
        return;
      }
      const relative =
        pathname === "/"
          ? "index.html"
          : pathname === "/faq"
            ? "faq.html"
            : pathname === "/privacy"
              ? "privacy.html"
              : pathname.slice(1);
      const path = resolve(root, relative);
      if (
        !path.startsWith(root + (root.endsWith(sep) ? "" : sep)) ||
        !(
          publicFiles.has(relative) ||
          /^assets\/[a-zA-Z0-9_-]+\.(jpg|svg)$/.test(relative)
        )
      ) {
        response
          .writeHead(404, { "Content-Type": "text/plain; charset=utf-8" })
          .end("页面不存在");
        return;
      }
      const info = await stat(path);
      if (!info.isFile()) throw new Error("文件不存在");
      response.writeHead(200, {
        "Content-Type": types[extname(path)] || "application/octet-stream",
        "Content-Length": info.size,
        "Cache-Control": "no-cache",
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "strict-origin-when-cross-origin",
      });
      response.end(
        request.method === "HEAD" ? undefined : await readFile(path),
      );
    } catch {
      if (!response.headersSent)
        response.writeHead(404, {
          "Content-Type": "text/plain; charset=utf-8",
        });
      response.end("页面不存在");
    }
  });
}
if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const port = Number(process.env.PORT || 3000);
  createWebsiteServer().listen(port, process.env.HOST || "0.0.0.0", () =>
    console.log(`EverFrame 官网：http://localhost:${port}`),
  );
}
