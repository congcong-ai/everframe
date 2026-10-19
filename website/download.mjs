export const fallbackAPK =
  "https://gitcode.com/xixisys/everframe/releases/download/v0.1.1/everframe-android-v0.1.1-debug.apk";
export const releasePage = "https://gitcode.com/xixisys/everframe/releases";
const releasesAPI =
  "https://api.gitcode.com/api/v5/repos/xixisys/everframe/releases";
export function safeURL(value) {
  try {
    const url = new URL(value);
    if (
      url.protocol !== "https:" ||
      url.username ||
      url.password ||
      [...url.searchParams.keys()].some((key) =>
        /^(access_token|token)$/i.test(key),
      )
    )
      return;
    return url.href;
  } catch {
    return;
  }
}
export function selectAPK(releases) {
  return releases
    .filter(
      (release) => !release.draft && /^v?\d+\.\d+\.\d+$/.test(release.tag_name),
    )
    .sort((a, b) => {
      const av = a.tag_name.replace(/^v/, "").split(".").map(Number);
      const bv = b.tag_name.replace(/^v/, "").split(".").map(Number);
      return bv[0] - av[0] || bv[1] - av[1] || bv[2] - av[2];
    })
    .flatMap((release) =>
      (release.assets || []).filter(
        (asset) =>
          /^everframe-android-v\d+\.\d+\.\d+-debug\.apk$/.test(asset.name) &&
          asset.name ===
            `everframe-android-${release.tag_name.startsWith("v") ? release.tag_name : "v" + release.tag_name}-debug.apk` &&
          asset.type === "attach" &&
          (asset.size == null || asset.size > 0) &&
          safeURL(asset.browser_download_url)?.startsWith(
            "https://gitcode.com/xixisys/everframe/releases/download/",
          ),
      ),
    )[0]?.browser_download_url;
}
export async function directURL(url, fetcher = fetch) {
  const probe = async (target) => {
    const response = await fetcher(target, {
      method: "HEAD",
      signal: AbortSignal.timeout(8000),
      cache: "no-store",
    });
    return (
      response.ok &&
      !response.headers.get("content-type")?.includes("text/html")
    );
  };
  try {
    if (await probe(url)) return url;
    // GitCode 的 HEAD 可能返回 401，GET 则返回公开 CDN 的 302。
    const response = await fetcher(url, {
      redirect: "manual",
      signal: AbortSignal.timeout(8000),
      cache: "no-store",
    });
    try {
      const location = response.headers.get("location");
      const target = location && safeURL(new URL(location, url).href);
      if (
        [301, 302, 303, 307, 308].includes(response.status) &&
        target &&
        (await probe(target))
      )
        return target;
    } finally {
      await response.body?.cancel();
    }
  } catch {
    /* API/网络异常时使用已验证的固定 GitCode 入口。 */
  }
}
export async function resolveAPK(fetcher = fetch) {
  try {
    const releases = [];
    const signal = AbortSignal.timeout(10000);
    for (let page = 1; page <= 10; page++) {
      const response = await fetcher(
        `${releasesAPI}?per_page=100&page=${page}`,
        { signal, cache: "no-store" },
      );
      if (!response.ok) return fallbackAPK;
      const batch = await response.json();
      if (!Array.isArray(batch)) return fallbackAPK;
      releases.push(...batch);
      if (batch.length < 100) break;
    }
    const asset = selectAPK(releases);
    return asset
      ? (await directURL(asset, fetcher)) || fallbackAPK
      : fallbackAPK;
  } catch {
    return fallbackAPK;
  }
}
