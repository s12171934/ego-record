// 관찰자 — 고정 페이지 p1 의 프레임을 받아 쌓고, 화면 크기·커서·이동 기록을 붙든다.
// ego-record.sh start 가 첫 줄에 `const RUN = "<실행 폴더>";` 를 붙여 백그라운드로 띄운다.
// 화면 크기 지정과 주입 스크립트는 이 프로세스가 살아 있는 동안만 유지된다 — 그래서 끝까지 붙든다.
const fs = await import("node:fs/promises");
const cfg = JSON.parse(await fs.readFile(RUN + "/config.json", "utf8"));
const task = await taskSpace(cfg.space);
const page = task.page("p1");
const note = (o) => fs.appendFile(RUN + "/nav.jsonl", JSON.stringify(o) + "\n");

await page.cdp("Emulation.setDeviceMetricsOverride", { width: cfg.width, height: cfg.height, deviceScaleFactor: 2, mobile: cfg.mobile });
if (cfg.mobile) await page.cdp("Emulation.setTouchEmulationEnabled", { enabled: true });
// ego 의 에이전트 커서는 브라우저 UI 에 그려져 캡처에 안 찍힌다 — 녹화용 커서를 페이지에 그린다
if (cfg.cursor) {
  const src = await fs.readFile(cfg.scripts + "/cursor.js", "utf8");
  await page.cdp("Page.addScriptToEvaluateOnNewDocument", { source: src });
  await page.cdp("Runtime.evaluate", { expression: src });
}
// 영상 크기는 지정한 화면 크기다. innerWidth 는 페이지의 meta viewport 를 따른 레이아웃 폭이라 다를 수 있다
const vp = [cfg.width, cfg.height, 2, await page.evaluate(() => innerWidth)];
await fs.writeFile(RUN + "/ready", JSON.stringify({ t: Date.now(), viewport: vp }));

const period = Math.round(1000 / cfg.fps);
const end = Date.now() + cfg.maxSeconds * 1000;
let n = 0, err = 0, lastUrl = "", lastNav = 0;
while (Date.now() < end) {
  try { await fs.stat(RUN + "/STOP"); break; } catch {}
  const t = Date.now();
  // URL 이 바뀌면 이동으로 남긴다 (타임라인의 「이동」 줄)
  if (t - lastNav > 1000) {
    lastNav = t;
    try {
      const u = await page.url();
      if (u !== lastUrl) { lastUrl = u; await note({ t, url: u, title: await page.title().catch(() => "") }); }
    } catch {}
  }
  try {
    const shot = page.cdp("Page.captureScreenshot", { format: "jpeg", quality: 70 }).then((r) => Buffer.from(r.data, "base64"));
    const b = await Promise.race([shot, new Promise((r) => setTimeout(() => r(null), 3000))]);
    if (b) { await fs.writeFile(`${RUN}/frames/${t}.jpg`, b); n++; } else err++;
  } catch (e) { err++; if (err < 4) console.log("capture error", String(e.message).slice(0, 200)); }
  const w = period - (Date.now() - t);
  if (w > 0) await new Promise((r) => setTimeout(r, w));
}
await fs.writeFile(RUN + "/observer.json", JSON.stringify({ frames: n, errors: err, viewport: vp, timedOut: Date.now() >= end }));
