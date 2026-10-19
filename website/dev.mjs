import { execFileSync, spawn } from "node:child_process";
const port = Number(process.env.PORT || 3000);
if (!Number.isInteger(port) || port < 1 || port > 65535)
  throw new Error("端口无效");
let pids = "";
try {
  pids = execFileSync("lsof", ["-tiTCP:" + port, "-sTCP:LISTEN"], {
    encoding: "utf8",
  });
} catch (error) {
  if (error.status !== 1) throw error;
}
for (const pid of pids.trim().split(/\s+/).filter(Boolean)) {
  try {
    process.kill(Number(pid), "SIGTERM");
  } catch (error) {
    if (error.code !== "ESRCH") throw error;
  }
}
for (let attempt = 0; attempt < 30 && pids; attempt++) {
  await new Promise((done) => setTimeout(done, 100));
  try {
    pids = execFileSync("lsof", ["-tiTCP:" + port, "-sTCP:LISTEN"], {
      encoding: "utf8",
    }).trim();
  } catch (error) {
    if (error.status !== 1) throw error;
    pids = "";
  }
}
if (pids) throw new Error(`端口 ${port} 尚未释放，请检查占用进程`);
const child = spawn(process.execPath, ["server.mjs"], {
  cwd: new URL(".", import.meta.url),
  stdio: "inherit",
});
for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => child.kill(signal));
child.on("exit", (code) => process.exit(code ?? 0));
