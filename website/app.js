const scenes = {
  create: {
    image: "assets/create.jpg",
    alt: "画笔与颜料组成的创作工作台",
    caption: "每一次投入，都是好素材。",
    number: "01",
  },
  home: {
    image: "assets/cat.jpg",
    alt: "家中一只望向镜头的猫咪",
    caption: "你没看见的，它都替你记着。",
    number: "02",
  },
  life: {
    image: "assets/forest.jpg",
    alt: "阳光穿过绿色森林的日常风景",
    caption: "再平常的一天，也有闪光的瞬间。",
    number: "03",
  },
};
const scenePhoto = document.querySelector("#scene-photo");
for (const button of document.querySelectorAll("[data-scene]")) {
  button.addEventListener("click", () => {
    const scene = scenes[button.dataset.scene];
    for (const option of document.querySelectorAll("[data-scene]")) {
      const selected = option === button;
      option.classList.toggle("active", selected);
      option.setAttribute("aria-pressed", String(selected));
    }
    scenePhoto.src = scene.image;
    scenePhoto.alt = scene.alt;
    document.querySelector("#scene-caption").textContent = scene.caption;
    document.querySelector("#scene-number").textContent = scene.number;
  });
}
if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries)
        if (entry.isIntersecting) {
          entry.target.classList.add("visible");
          observer.unobserve(entry.target);
        }
    },
    { threshold: 0.08 },
  );
  document.documentElement.classList.add("motion-ready");
  document
    .querySelectorAll(".reveal")
    .forEach((element) => observer.observe(element));
}
for (const link of document.querySelectorAll("[data-download]")) {
  link.addEventListener("click", () => {
    document.querySelector("#download-feedback").textContent =
      "正在前往 APK 下载；若下载未开始，可在 GitCode Releases 中获取安装包。";
  });
}
