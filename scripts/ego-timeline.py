#!/usr/bin/env python3
"""ego-record 실행 폴더의 기록(actions.jsonl·nav.jsonl)을 녹화 시작 기준 오프셋으로 펴는 타임라인 초안 도구.

사용:
  ego-timeline.py --run <실행 폴더> [--video <mp4>]

녹화 시작은 첫 프레임 파일명(epoch ms)이고, 프레임이 지워졌으면 run.json 의 firstFrame 을 쓴다.
출력은 노트에 그대로 붙일 완성본이 아니다 — 구간을 묶고 무엇이 증거인지 판단하는 일은 에이전트 몫이다.
"""
import argparse, json, os, re, sys
from datetime import datetime
from urllib.parse import quote


def read(path):
    out = []
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return out


def offset(ms, start):
    s = int(round((ms - start) / 1000))
    sign = "-" if s < 0 else ""
    s = abs(s)
    if s >= 3600:
        return "%s%d:%02d:%02d" % (sign, s // 3600, s % 3600 // 60, s % 60)
    return "%s%02d:%02d" % (sign, s // 60, s % 60)


def squeeze(text, limit=160):
    text = re.sub(r"\s+", " ", str(text or "")).strip()
    return text if len(text) <= limit else text[: limit - 1] + "…"


# 화면을 바꾸지 않는 관찰·대기 호출 — 실패했거나 label 을 준 경우만 남긴다
QUIET = {"evaluate", "waitForURL", "waitForSelector", "waitForLoadState", "waitForFunction", "focus"}
# 이 간격 안에 이어진 동작은 한 줄로 합친다(초) — 영상에서 1초 단위로 찾으므로 그보다 잘게 나눌 이유가 없다
MERGE_GAP = 2.0
# 마우스 이동·누름·뗌이 이 간격 안에 이어지면 한 동작(드래그·이동)으로 본다(초)
GESTURE_GAP = 1.0


def label_of(a):
    return next((x.get("label") for x in a.get("args") or [] if isinstance(x, dict) and x.get("label")), None)


def num(v):
    return ("%d" % round(v)) if isinstance(v, (int, float)) else str(v)


def describe(a, full=False):
    args = a.get("args") or []
    label = label_of(a)
    plain = [x for x in args if not isinstance(x, dict)]
    head = a["name"] if a["kind"] == "page" else "%s.%s" % (a["kind"], a["name"])
    body = " ".join(x if isinstance(x, str) else num(x) if isinstance(x, (int, float)) else json.dumps(x, ensure_ascii=False) for x in plain)
    # label 이 있으면 그것이 사람이 읽을 이름이다 — 선택자는 --raw 에서만 본다
    s = label if label and not full else head + (" " + body if body else "")
    if label and full:
        s = "%s — %s" % (label, s)
    took = (a["end"] - a["t"]) / 1000
    return squeeze(s + (" (%.1fs)" % took if took >= 1 else ""))


def point(a):
    xs = [x for x in a.get("args") or [] if isinstance(x, (int, float))]
    return "(%s,%s)" % (num(xs[0]), num(xs[1])) if len(xs) >= 2 else None


def gesture(group):
    """이어진 mouse.move/down/up/wheel 묶음 → 한 줄. 누름이 있으면 드래그, 없으면 이동, wheel 은 스크롤."""
    label = next((label_of(a) for a in group if label_of(a)), None)
    names = [a["name"] for a in group]
    pts = [p for p in (point(a) for a in group if a["name"] == "move") if p]
    if "wheel" in names:
        what = "스크롤 %d회" % names.count("wheel")
    elif "down" in names:
        strokes = names.count("down")
        what = "드래그" + (" %d번" % strokes if strokes > 1 else "")
        if pts:
            what += " %s→%s" % (pts[0], pts[-1]) if strokes == 1 else ""
    else:
        what = "마우스 이동" + (" → %s" % pts[-1] if pts else "")
    return squeeze("%s — %s" % (label, what) if label else what)


def collapse(acts):
    """한 라운드의 동작 목록에서 관찰 호출을 빼고 마우스 묶음을 한 동작으로 접는다 → [(t, kind, text)]"""
    out, group = [], []

    def flush():
        if group:
            out.append((group[0]["t"], "도구", gesture(group)))
            group.clear()

    for a in acts:
        if a.get("error"):
            flush()
            out.append((a["t"], "오류", describe(a, full=True) + " ✗ " + squeeze(a["error"], 120)))
        elif a["kind"] == "mouse" and a["name"] != "click":
            if group and (a["t"] - group[-1]["end"]) / 1000 > GESTURE_GAP:
                flush()
            group.append(a)
        else:
            flush()
            if a["kind"] == "page" and a["name"] in QUIET and not label_of(a):
                continue
            out.append((a["t"], "도구", describe(a)))
    flush()
    return out


def compact(raw):
    """라운드(말) 단위로 묶어 줄을 줄인다.
    - 같은 문장을 연달아 다시 말한 라운드(사이에 남길 동작이 없을 때)는 첫 줄 하나로 합치고 횟수를 붙인다.
    - 라운드 안에서 직전 줄과 MERGE_GAP 안에 일어난 동작은 그 줄에 « · » 로 붙인다(말 줄에는 « ▸ »).
    - 오류·위반은 언제나 제 줄을 갖는다.
    """
    rounds, cur = [], None
    for x in raw:
        if x["kind"] == "say":
            cur = {"t": x["t"], "text": squeeze(x["text"]), "n": 1, "acts": []}
            rounds.append(cur)
        elif x["kind"] == "space":
            rounds.append({"t": x["t"], "violation": describe(x)})
            cur = None
        else:
            if cur is None:
                cur = {"t": x["t"], "text": None, "n": 1, "acts": []}
                rounds.append(cur)
            cur["acts"].append(x)

    rows = []  # [t, kind, text, end_t]
    prev = None
    for r in rounds:
        if "violation" in r:
            rows.append([r["t"], "위반", r["violation"] + " — 고정 페이지 p1 밖", r["t"]])
            prev = None
            continue
        acts = collapse(r["acts"])
        if prev and r["text"] and r["text"] == prev["text"] and not prev["acts_kept"]:
            prev["n"] += 1
            prev["row"][2] = "%s (%d회)" % (prev["text"], prev["n"])
            prev["acts_kept"] = bool(acts)
            head = prev["row"]
        else:
            head = None
            if r["text"]:
                head = [r["t"], "말", r["text"], r["t"]]
                rows.append(head)
            prev = {"text": r["text"], "n": 1, "row": head, "acts_kept": bool(acts)}
        tail = head
        for t, kind, text in acts:
            if kind == "도구" and tail and tail[1] in ("말", "도구") and (t - tail[3]) / 1000 <= MERGE_GAP:
                tail[2] += (" ▸ " if tail[1] == "말" and " ▸ " not in tail[2] else " · ") + text
                tail[3] = t
            else:
                tail = [t, kind, text, t]
                rows.append(tail)
    return [(t, k, s) for t, k, s, _ in rows]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", required=True)
    ap.add_argument("--video")
    ap.add_argument("--raw", action="store_true", help="합치지 않고 기록 한 건을 한 줄로 (디버깅용)")
    a = ap.parse_args()

    frames_dir = os.path.join(a.run, "frames")
    frames = sorted(int(f[:-4]) for f in os.listdir(frames_dir) if f.endswith(".jpg")) if os.path.isdir(frames_dir) else []
    meta = {}
    if os.path.exists(os.path.join(a.run, "run.json")):
        meta = json.load(open(os.path.join(a.run, "run.json")))
    start = frames[0] if frames else meta.get("firstFrame")
    if not start:
        sys.exit("녹화 시작을 알 수 없습니다 — 프레임도 run.json 도 없습니다")

    raw = sorted(read(os.path.join(a.run, "actions.jsonl")), key=lambda x: x["t"])
    if a.raw:
        rows = []
        for x in raw:
            kind = "말" if x["kind"] == "say" else "위반" if x["kind"] == "space" else "오류" if x.get("error") else "도구"
            rows.append((x["t"], kind, squeeze(x["text"]) if x["kind"] == "say" else describe(x, full=True)))
    else:
        rows = compact(raw)
    last = None
    for x in read(os.path.join(a.run, "nav.jsonl")):
        if x["url"] == last:
            continue
        last = x["url"]
        rows.append((x["t"], "이동", squeeze("%s — %s" % (x.get("title") or "", x["url"]))))

    video = a.video or meta.get("video")
    print("# 영상: %s" % (video or "(미지정)"))
    if video:
        print("# 영상 URL: file://%s" % quote(os.path.abspath(video)))
    print("# 녹화 시작: %s (첫 프레임, epoch ms %d)" % (datetime.fromtimestamp(start / 1000).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3], start))
    if meta.get("frames"):
        print("# 프레임: %d장, 화면 %s" % (meta["frames"], "×".join(str(v) for v in meta.get("viewport", [])[:2])))
    print("#")
    for t, kind, text in sorted(rows, key=lambda r: r[0]):
        print("%s\t%s\t%s" % (offset(t, start), kind, text))


if __name__ == "__main__":
    main()
