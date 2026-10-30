#!/bin/bash
# ego lite 브라우저 작업을 영상으로 남기는 러너.
# start → (act 를 여러 번) → stop. 에이전트(호출자)가 act 라운드마다 고정 페이지 p1 에서 일하는 동안
# 백그라운드 관찰자가 p1 의 프레임을 받아 두고, stop 이 mp4 와 타임라인 초안을 만든다.
# 화면·창·키보드 포커스를 건드리지 않는다 — 화면을 찍지 않고 탭에서 프레임을 직접 받는다.
#
# 사용법:
#   ego-record.sh check
#   ego-record.sh start --name "<케이스 이름>" [--size 1440x900] [--mobile] [--cursor | --no-cursor] "<대상 URL>"
#   ego-record.sh act <실행 폴더> [--say "<이 라운드에서 하려는 일>"] [-e '<js>' | < script.js]
#   ego-record.sh stop <실행 폴더>
#   ego-record.sh abort <실행 폴더>      (영상을 만들지 않고 관찰자·TaskSpace 만 정리)
set -u
SDIR="$(cd "$(dirname "$0")" && pwd -P)"
# 산출물 위치는 인자로 받지 않는다 — 세션 임시 폴더로 들어가면 세션이 정리될 때 영상이 같이 사라진다.
OUTDIR="$HOME/Movies/ego-record"
FPS="${EGO_RECORD_FPS:-5}"
MAX_SECONDS="${EGO_RECORD_MAX_SECONDS:-1800}"  # 관찰자 안전 상한. stop 을 잊어도 이 뒤엔 멈춘다

die() { echo "$*" >&2; exit 1; }
strip() { sed $'s/\x1b\\[[0-9;]*m//g'; }

# --- 테스트 진행 기록 ---------------------------------------------------------
# 녹화 실측도 테스트로 친다 — agent dashboard 의 atest 진행 파일에 녹화 하나를 실행 하나로 남긴다.
# 케이스는 준비·act 라운드(R1, R2 …, 제목은 --say)·인코딩·고정 페이지 판정. 실행 키는 실행 폴더에서 나온다.
# atest 는 $ATEST·PATH, 없으면 이 스킬이 든 볼트의 agent-dashboard 에서 찾는다. 없거나 실패해도 녹화는 계속한다.
ATEST="${ATEST:-$(command -v atest 2>/dev/null)}"
[ -x "$ATEST" ] || ATEST="$SDIR/../../../../40_Tools/agent-dashboard/bin/atest"
at() {  # <실행 폴더> <atest 명령 …>
  local key="ego-$(basename "$1" | tr '.' '-')"; shift
  [ -x "$ATEST" ] && "$ATEST" "$@" --key "$key" >/dev/null 2>&1; return 0
}

# --- check ------------------------------------------------------------------
cmd_check() {
  local fail=0
  echo "사전 점검"
  for c in ego-browser ffmpeg ffprobe python3; do
    if command -v "$c" >/dev/null 2>&1; then continue; fi
    fail=$((fail + 1))
    case "$c" in
      ego-browser) echo "   [실패] ego-browser 없음 — ego lite 설치·첫 실행 설정을 마치고 ~/.local/bin 을 PATH 에 넣는다 (https://lite.ego.app/)" ;;
      ffmpeg|ffprobe) echo "   [실패] $c 없음 — brew install ffmpeg" ;;
      python3) echo "   [실패] python3 없음 — xcode-select --install" ;;
    esac
  done
  [ "$fail" = 0 ] && echo "   [OK]   명령: ego-browser ffmpeg ffprobe python3"
  if command -v ffmpeg >/dev/null 2>&1; then
    if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q h264_videotoolbox; then echo "   [OK]   ffmpeg h264_videotoolbox"
    else echo "   [실패] ffmpeg 에 h264_videotoolbox 가 없다 — brew 의 ffmpeg 로 바꾼다"; fail=$((fail + 1)); fi
  fi
  if command -v ego-browser >/dev/null 2>&1; then
    if ego-browser nodejs -e 'console.log("EGO_OK")' 2>&1 | grep -q EGO_OK; then echo "   [OK]   ego-browser 런타임"
    else echo "   [실패] ego-browser nodejs 가 돌지 않는다 — ego lite 앱이 실행 중인지 본다"; fail=$((fail + 1)); fi
  fi
  [ "$fail" = 0 ] && { echo "점검 통과"; return 0; }
  echo "점검 실패 $fail 건"; return 1
}

# --- start ------------------------------------------------------------------
cmd_start() {
  local name="" size="1440x900" mobile=false cursor=true url=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) name="${2:?--name 뒤에 케이스 이름이 필요합니다}"; shift 2 ;;
      --size) size="${2:?--size 뒤에 WxH 가 필요합니다}"; shift 2 ;;
      --mobile) mobile=true; shift ;;
      --cursor) cursor=true; shift ;;      # 기본값 — 명시용
      --no-cursor) cursor=false; shift ;;  # 페이지 DOM 에 오버레이를 넣지 않아야 할 때
      -*) die "모르는 옵션: $1" ;;
      *) url="$1"; shift ;;
    esac
  done
  [ -n "$url" ] || die "대상 URL 이 필요합니다"
  [[ "$size" =~ ^([0-9]+)x([0-9]+)$ ]] || die "--size 는 1440x900 형식이다"
  local w="${BASH_REMATCH[1]}" h="${BASH_REMATCH[2]}"
  cmd_check >/dev/null || { cmd_check; exit 1; }

  # 이름이 없으면 대상 URL 의 호스트. 경로를 깨는 문자(/ :)와 연속 공백만 정리한다.
  [ -z "$name" ] && name=$(printf '%s' "$url" | sed -E 's#^[a-zA-Z]+://##; s#[/?\#].*$##')
  name=$(printf '%s' "$name" | tr '/:\n\t' '----' | tr -s ' ' | sed -E 's/^[ .-]+//; s/[ .]+$//' | cut -c1-80)
  [ -z "$name" ] && name="ego"
  local stamp; stamp=$(date +%Y%m%d-%H%M%S)
  mkdir -p "$OUTDIR/.runs"
  local run; run=$(mktemp -d "$OUTDIR/.runs/$stamp.XXXX") || die "실행 폴더를 만들지 못했다"
  mkdir -p "$run/frames"
  at "$run" start --kind ego --label "녹화 실측 · $name" "준비=TaskSpace·고정 페이지 p1·관찰자 ($url)"
  at "$run" case "준비" running

  # 0) TaskSpace 와 고정 페이지 p1. 케이스마다 space 가 따로라 동시에 여러 건을 돌려도 섞이지 않는다.
  ego-browser nodejs > "$run/start.log" 2>&1 <<EOF
const task = await taskSpace($(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "ego-record $name $stamp ${run##*.}"));
const page = task.page("p1");
try { await page.goto($(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$url"), { timeout: 20000 }); }
catch (e) { console.log("GOTO_WARN " + String(e.message).slice(0, 160)); }
console.log("SPACE:" + task.spaceId);
EOF
  local space; space=$(strip < "$run/start.log" | sed -n 's/^SPACE://p' | head -1)
  [ -n "$space" ] || { cat "$run/start.log" >&2; at "$run" case "준비" failed "TaskSpace 를 열지 못했다"; at "$run" end failed; rm -rf "$run"; die "TaskSpace 를 열지 못했다"; }
  python3 - "$run/config.json" "$name" "$url" "$space" "$w" "$h" "$mobile" "$cursor" "$FPS" "$MAX_SECONDS" "$SDIR" <<'PY'
import json, sys
out, name, url, space, w, h, mobile, cursor, fps, mx, sdir = sys.argv[1:]
json.dump({"name": name, "url": url, "space": int(space), "width": int(w), "height": int(h),
           "mobile": mobile == "true", "cursor": cursor == "true", "fps": int(fps), "maxSeconds": int(mx),
           "scripts": sdir}, open(out, "w"), ensure_ascii=False)
PY

  # 1) 관찰자를 백그라운드로 띄운다. 이 셸이 끝나도 살아 있어야 한다.
  { printf 'const RUN = %s;\n' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$run")"; cat "$SDIR/observer.js"; } > "$run/observer.gen.js"
  nohup ego-browser nodejs < "$run/observer.gen.js" > "$run/observer.log" 2>&1 &
  echo $! > "$run/observer.pid"
  disown 2>/dev/null || true
  for _ in $(seq 1 60); do [ -s "$run/ready" ] && break; kill -0 "$(cat "$run/observer.pid")" 2>/dev/null || break; sleep 0.5; done
  if [ ! -s "$run/ready" ]; then
    tail -5 "$run/observer.log" >&2
    at "$run" case "준비" failed "관찰자가 준비되지 않았다"
    cmd_abort "$run" >/dev/null 2>&1
    die "관찰자가 준비되지 않았다"
  fi
  grep -h GOTO_WARN "$run/start.log" | strip
  at "$run" case "준비" passed "space $space · ${w}×${h}"
  echo "녹화 시작: $name"
  echo "   화면 $(python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))["viewport"]; print("%d×%d (페이지 레이아웃 폭 %d)" % (v[0], v[1], v[3]))' "$run/ready") · space $space · 고정 페이지 p1"
  echo "RUN=$run"
}

# --- act --------------------------------------------------------------------
cmd_act() {
  local run="${1:?실행 폴더가 필요합니다}"; shift
  [ -f "$run/config.json" ] || die "실행 폴더가 아니다: $run"
  [ -f "$run/STOP" ] && die "이미 stop 한 녹화다"
  local code="" say=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --say) say="${2:?--say 뒤에 설명이 필요합니다}"; shift 2 ;;
      -e) code="${2:?-e 뒤에 코드가 필요합니다}"; shift 2 ;;
      *) die "모르는 인자: $1" ;;
    esac
  done
  [ -z "$code" ] && code=$(cat)
  [ -n "$say" ] && python3 -c 'import json,sys,time; open(sys.argv[1],"a").write(json.dumps({"t": int(time.time()*1000), "kind": "say", "text": sys.argv[2]}, ensure_ascii=False) + "\n")' "$run/actions.jsonl" "$say"
  local n=$(( $(cat "$run/acts" 2>/dev/null || echo 0) + 1 )) rc
  echo "$n" > "$run/acts"
  at "$run" case "R$n" running --title "${say:-act 라운드 $n}"
  { printf 'const RUN = %s;\n' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$run")"; cat "$SDIR/act-prelude.js"; printf '\n%s\n' "$code"; } | ego-browser nodejs
  rc=$?
  if [ "$rc" -eq 0 ]; then at "$run" case "R$n" passed; else at "$run" case "R$n" failed "종료 코드 $rc"; fi
  return "$rc"
}

# --- stop / abort -----------------------------------------------------------
stop_observer() {  # <run>
  local run="$1" pid
  touch "$run/STOP"
  pid=$(cat "$run/observer.pid" 2>/dev/null)
  for _ in $(seq 1 40); do [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 0; sleep 0.5; done
  kill "$pid" 2>/dev/null
}
finish_space() {  # <run>
  local space; space=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["space"])' "$1/config.json")
  ego-browser nodejs -e "await (await taskSpace($space)).finish({ keep: [] }); console.log('FINISHED');" 2>&1 | strip | grep -q FINISHED \
    || echo "[경고] TaskSpace $space 를 닫지 못했다 — ego lite 에서 직접 닫는다"
}
cmd_abort() {
  local run="${1:?실행 폴더가 필요합니다}"
  stop_observer "$run"; finish_space "$run"
  at "$run" end failed "중단 — 영상을 만들지 않았다"; rm -rf "$run"
  echo "중단: 영상을 만들지 않았다"
}
cmd_stop() {
  local run="${1:?실행 폴더가 필요합니다}"
  [ -f "$run/config.json" ] || die "실행 폴더가 아니다: $run"
  stop_observer "$run"
  finish_space "$run"
  local first count name
  first=$(ls "$run/frames" 2>/dev/null | sort -n | head -1)
  at "$run" case "인코딩" running --title "mp4 묶기"
  [ -n "$first" ] || { tail -5 "$run/observer.log"; at "$run" case "인코딩" failed "프레임 없음"; at "$run" end failed; die "프레임이 하나도 없다 — $run/observer.log 를 본다"; }
  count=$(ls "$run/frames" | wc -l | tr -d ' ')
  name=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$run/config.json")

  # mp4 이름은 「<케이스 이름> <첫 프레임 시각>」 — 시각이 타임라인 오프셋의 기준점이라 빼지 않는다.
  local epoch=$(( ${first%.jpg} / 1000 )) stamp mp4 i=2
  stamp=$(date -r "$epoch" +%Y%m%d-%H%M%S)
  mp4="$OUTDIR/$name $stamp.mp4"
  while [ -e "$mp4" ]; do mp4="$OUTDIR/$name $stamp-$i.mp4"; i=$((i + 1)); done

  # 프레임 파일명(epoch ms)을 그대로 시각으로 쓴다 — 늦게 온 프레임은 그만큼 길게 보인다.
  python3 - "$run/frames" "$run/concat.txt" <<'PY'
import os, sys
d, out = sys.argv[1], sys.argv[2]
ts = sorted(int(f[:-4]) for f in os.listdir(d) if f.endswith(".jpg"))
with open(out, "w") as f:
    for a, b in zip(ts, ts[1:] + [ts[-1] + 200]):
        f.write("file '%s/%d.jpg'\nduration %.3f\n" % (d, a, (b - a) / 1000))
    f.write("file '%s/%d.jpg'\n" % (d, ts[-1]))
PY
  # 프레임은 2배 해상도라 절반으로 줄이면 영상 크기 = 지정한 화면 크기
  ffmpeg -v error -f concat -safe 0 -i "$run/concat.txt" \
    -vf "fps=$FPS,scale=trunc(iw/4)*2:trunc(ih/4)*2,format=yuv420p" \
    -c:v h264_videotoolbox -b:v 2M -movflags +faststart -y "$mp4" \
    || { at "$run" case "인코딩" failed "인코딩 실패"; at "$run" end failed; false; } || die "인코딩 실패 — 프레임은 $run/frames 에 남겨 둔다"

  python3 - "$run" "$mp4" "${first%.jpg}" "$count" <<'PY'
import json, os, sys
run, mp4, first, count = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
obs = json.load(open(os.path.join(run, "observer.json"))) if os.path.exists(os.path.join(run, "observer.json")) else {}
json.dump({"video": mp4, "firstFrame": first, "frames": count, "viewport": obs.get("viewport"), "captureErrors": obs.get("errors"),
           "timedOut": obs.get("timedOut")}, open(os.path.join(run, "run.json"), "w"), ensure_ascii=False)
PY
  python3 "$SDIR/ego-timeline.py" --run "$run" --video "$mp4" > "${mp4%.mp4}.timeline.txt"
  rm -rf "$run/frames" "$run/concat.txt" "$run/STOP"

  at "$run" case "인코딩" passed "프레임 $count 장"
  echo "영상: $mp4"
  echo "영상 URL: $(python3 -c 'import sys,urllib.parse; print("file://" + urllib.parse.quote(sys.argv[1]))' "$mp4")"
  echo "녹화 시작: $(date -r "$epoch" '+%Y-%m-%d %H:%M:%S') (epoch $epoch)"
  echo "프레임: $count 장 · 캡처 오류 $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("captureErrors"))' "$run/run.json") 건"
  echo "타임라인 초안: ${mp4%.mp4}.timeline.txt"
  echo "기록: $run"
  # 고정 페이지 밖으로 나간 호출이 있으면 그 구간은 영상에 없다
  local viol
  viol=$(grep '"kind":"space"' "$run/actions.jsonl" 2>/dev/null | grep -o '"name":"[a-zA-Z]*"' | sort -u | tr '\n' ' ')
  if [ -n "$viol" ]; then
    echo "[폐기] 작업이 고정 페이지 p1 밖을 썼다: $viol— 그 구간은 영상에 없다"
    at "$run" case "고정 페이지 판정" failed --title "p1 밖 호출 확인" "[폐기] $viol"
  else
    echo "고정 페이지: 지켜짐"
    at "$run" case "고정 페이지 판정" passed --title "p1 밖 호출 확인"
  fi
  python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("timedOut") else 1)' "$run/run.json" \
    && echo "[경고] 관찰자가 상한(${MAX_SECONDS}초)에 걸려 먼저 멈췄다 — 영상 뒷부분이 없다"
  at "$run" end "$(basename "$mp4")"
  return 0
}

sub="${1:-}"; shift || true
case "$sub" in
  check) cmd_check ;;
  start) cmd_start "$@" ;;
  act)   cmd_act "$@" ;;
  stop)  cmd_stop "$@" ;;
  abort) cmd_abort "$@" ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
