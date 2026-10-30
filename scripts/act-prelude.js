// 작업 라운드 머리말 — ego-record.sh act 가 첫 줄에 `const RUN = "<실행 폴더>";` 를 붙이고 이 파일과 작업 스크립트를 이어 실행한다.
// `task`·`page`(고정 페이지 p1)를 만들어 두고, Page·mouse·keyboard·TaskSpace 호출을 시각과 함께 actions.jsonl 에 남긴다.
// 작업 스크립트는 이 둘을 그대로 쓰고 다시 선언하지 않는다.
const task = await taskSpace(JSON.parse(await (await import("node:fs/promises")).readFile(RUN + "/config.json", "utf8")).space);
const page = task.page("p1");
{
  const fs = await import("node:fs/promises");
  const LOG = RUN + "/actions.jsonl";
  let depth = 0; // keyboard.type 안의 press 같은 내부 호출은 한 줄로 친다
  const pack = (a) => a.map((x) => typeof x === "string" ? x.slice(0, 200)
    : typeof x === "function" ? "fn"
    : x && typeof x === "object" ? JSON.parse(JSON.stringify(x, (k, v) => typeof v === "string" ? v.slice(0, 200) : v))
    : x);
  const wrap = (proto, kind, names) => {
    for (const n of names) {
      const f = proto[n];
      if (typeof f !== "function" || f.__egoRecord) continue;
      const w = async function (...a) {
        if (depth > 0) return f.apply(this, a);
        depth++; const t = Date.now(); let err;
        try { return await f.apply(this, a); }
        catch (e) { err = e; throw e; }
        finally {
          depth--;
          await fs.appendFile(LOG, JSON.stringify({ t, end: Date.now(), kind, name: n, page: this.label, args: pack(a), error: err ? String(err.message).slice(0, 200) : undefined }) + "\n");
        }
      };
      w.__egoRecord = true; proto[n] = w;
    }
  };
  wrap(Object.getPrototypeOf(page), "page", ["goto", "reload", "click", "dblclick", "hover", "fill", "press", "selectOption", "focus", "dragAndDrop", "setInputFiles", "evaluate", "waitForURL", "waitForSelector", "waitForLoadState", "waitForFunction", "acceptDialog", "dismissDialog", "close"]);
  wrap(Object.getPrototypeOf(page.mouse), "mouse", ["click", "move", "down", "up", "wheel"]);
  wrap(Object.getPrototypeOf(page.keyboard), "keyboard", ["down", "up", "press", "type", "insertText", "paste"]);
  // ego 의 page.screenshot() 은 자체 화면 크기를 걸어, 그 뒤로 관찰자가 건 크기와 캡처마다 번갈아 페이지가 흔들린다
  // (창 반짝임·클릭 좌표 어긋남·깨진 프레임) — 같은 모양의 CDP 캡처로 바꿔 낀다
  {
    const proto = Object.getPrototypeOf(page);
    if (!proto.screenshot.__egoRecord) {
      const os = await import("node:os");
      const shot = async function (opts = {}) {
        const r = await this.cdp("Page.captureScreenshot", { format: "png" });
        const path = opts.path || `${os.tmpdir()}/ego-record-${Date.now()}.png`;
        await fs.writeFile(path, Buffer.from(r.data, "base64"));
        return path;
      };
      shot.__egoRecord = true; proto.screenshot = shot;
    }
  }
  // 고정 페이지 밖으로 나가는 호출 — 관찰자는 p1 만 찍으므로 stop 이 이 녹화를 [폐기] 로 판정한다
  wrap(Object.getPrototypeOf(task), "space", ["newPage", "adopt", "finish", "handOff"]);
}
