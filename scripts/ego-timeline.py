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


def describe(a):
    args = a.get("args") or []
    label = next((x.get("label") for x in args if isinstance(x, dict) and x.get("label")), None)
    plain = [x for x in args if not isinstance(x, dict)]
    head = a["name"] if a["kind"] == "page" else "%s.%s" % (a["kind"], a["name"])
    body = " ".join(x if isinstance(x, str) else json.dumps(x, ensure_ascii=False) for x in plain)
    s = head + (" " + body if body else "")
    if label:
        s = "%s — %s" % (label, s)
    return squeeze("%s (%.1fs)" % (s, (a["end"] - a["t"]) / 1000))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", required=True)
    ap.add_argument("--video")
    a = ap.parse_args()

    frames_dir = os.path.join(a.run, "frames")
    frames = sorted(int(f[:-4]) for f in os.listdir(frames_dir) if f.endswith(".jpg")) if os.path.isdir(frames_dir) else []
    meta = {}
    if os.path.exists(os.path.join(a.run, "run.json")):
        meta = json.load(open(os.path.join(a.run, "run.json")))
    start = frames[0] if frames else meta.get("firstFrame")
    if not start:
        sys.exit("녹화 시작을 알 수 없습니다 — 프레임도 run.json 도 없습니다")

    rows = []
    for x in read(os.path.join(a.run, "actions.jsonl")):
        if x["kind"] == "say":
            rows.append((x["t"], "말", squeeze(x["text"])))
        elif x["kind"] == "space":
            rows.append((x["t"], "위반", describe(x) + " — 고정 페이지 p1 밖"))
        elif x.get("error"):
            rows.append((x["t"], "오류", describe(x) + " ✗ " + squeeze(x["error"], 120)))
        else:
            rows.append((x["t"], "도구", describe(x)))
    for x in read(os.path.join(a.run, "nav.jsonl")):
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
