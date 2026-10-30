// 녹화용 커서 — 마우스·포인터·터치 이벤트를 따라 화살표를 그리고, 누르면 빨간 원을 퍼뜨린다.
// 관찰자가 Page.addScriptToEvaluateOnNewDocument 로 넣어 이동 뒤에도 다시 들어간다. 클릭은 가로채지 않는다.
(() => {
  if (window.__egoRecordCursor) return;
  window.__egoRecordCursor = true;
  const mount = () => {
    const root = document.documentElement;
    if (!root) return setTimeout(mount, 50);
    const c = document.createElement("div");
    c.setAttribute("data-ego-record-cursor", "");
    c.style.cssText = "position:fixed;left:0;top:0;width:22px;height:22px;z-index:2147483647;pointer-events:none;transform:translate(-100px,-100px)";
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("width", "22"); svg.setAttribute("height", "22"); svg.setAttribute("viewBox", "0 0 22 22");
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", "M2 2 L2 18 L6.5 13.5 L9.5 20 L12.5 18.7 L9.6 12.3 L16 12.3 Z");
    path.setAttribute("fill", "#111"); path.setAttribute("stroke", "#fff"); path.setAttribute("stroke-width", "1.5");
    svg.appendChild(path); c.appendChild(svg); root.appendChild(c);
    const ring = (x, y) => {
      const r = document.createElement("div");
      r.setAttribute("data-ego-record-cursor", "");
      r.style.cssText = `position:fixed;left:${x - 18}px;top:${y - 18}px;width:36px;height:36px;border-radius:50%;border:3px solid #ff3b30;box-sizing:border-box;z-index:2147483646;pointer-events:none;opacity:1;transition:opacity 600ms,transform 600ms`;
      root.appendChild(r);
      requestAnimationFrame(() => { r.style.opacity = "0"; r.style.transform = "scale(1.6)"; });
      setTimeout(() => r.remove(), 700);
    };
    // 새 문서에서는 다음 마우스 이벤트까지 위치를 모른다 — 같은 출처 이동이면 마지막 위치를 이어받는다
    const KEY = "__egoRecordCursorPos";
    const at = (x, y) => {
      c.style.transform = `translate(${x}px,${y}px)`;
      try { sessionStorage.setItem(KEY, JSON.stringify([x, y])); } catch {}
    };
    try { const p = JSON.parse(sessionStorage.getItem(KEY) || "null"); if (p) c.style.transform = `translate(${p[0]}px,${p[1]}px)`; } catch {}
    const xy = (e) => (e.touches && e.touches[0]) || (e.changedTouches && e.changedTouches[0]) || e;
    for (const t of ["mousemove", "pointermove", "touchmove", "wheel"]) addEventListener(t, (e) => { const p = xy(e); at(p.clientX, p.clientY); }, { capture: true, passive: true });
    let lastDown = 0;
    for (const t of ["pointerdown", "mousedown", "touchstart"]) addEventListener(t, (e) => {
      const p = xy(e); at(p.clientX, p.clientY);
      // 한 번의 누름이 pointerdown·mousedown·touchstart 를 모두 내므로 원은 한 번만
      if (Date.now() - lastDown > 150) { lastDown = Date.now(); ring(p.clientX, p.clientY); }
    }, true);
  };
  mount();
})();
