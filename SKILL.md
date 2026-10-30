---
name: "ego-record"
description: "ego lite(`ego-browser`)로 브라우저 작업을 하면서 그 화면을 영상으로 남기는 실측 스킬. 「ego lite 로 실측하면서 녹화해줘」, 「브라우저 작업 영상으로 남겨」, 「egolite 녹화」, 「여러 케이스 동시에 돌려 녹화」, 「모바일 크기로 찍어줘」, 「커서 보이게 녹화」 같은 요청에서 로드한다. 화면을 찍지 않는다 — 케이스마다 TaskSpace 의 고정 페이지 p1 에서 백그라운드 관찰자가 프레임을 직접 받아 mp4 로 묶으므로, 사용자의 화면·창·키보드 포커스를 건드리지 않고 여러 녹화를 동시에 돌릴 수 있다. 화면 크기 지정·녹화용 커서·동작 기록 기반 타임라인 초안을 지원하고, 끝나면 Media Extended 타임라인 노트를 사용자의 노트에 남기는 것까지가 산출물이다. Aside 에이전트(`aside exec`) 녹화는 `aside-record` 를 쓴다."
---

# ego lite 실측 녹화

ego lite 에는 `aside exec` 같은 자체 에이전트가 없다. **브라우저를 모는 것은 이 스킬을 쓰는 에이전트 자신이다.**
그래서 러너는 한 번에 돌지 않고 `start → act(여러 번) → stop` 으로 나뉜다. 에이전트는 act 라운드마다
화면을 보고 다음 동작을 정하고, 그동안 백그라운드 관찰자가 고정 페이지를 계속 찍는다.

- 화면을 찍지 않는다 — 관찰자가 고정 페이지 p1 에서 `Page.captureScreenshot` 으로 프레임을 받는다.
- 메뉴 클릭·`activate`·창 이동이 없어 사용자의 전면 앱이 바뀌지 않는다(실측: 0.5초 간격 측정 내내 불변).
- ego-browser 의 일반 사용법(API·TaskSpace 규칙)은 `ego-browser skill` 출력이 원본이다. 이 문서는 녹화에 필요한 것만 적는다.

## 0. 준비

- ego lite 설치와 첫 실행 설정(온보딩)은 사람이 한다 — 설치 안내는 [ego lite (공식 사이트)](https://lite.ego.app/). 끝나면 `ego-browser` 가 `~/.local/bin` 에 생긴다.
- `brew install ffmpeg` (`h264_videotoolbox` 인코더 필요).
- 판정은 명령으로 한다: `scripts/ego-record.sh check`. 빠진 것마다 조치 한 줄을 찍는다.

스크립트는 이 스킬의 `scripts/` 에 있다. 이 `SKILL.md` 가 로드된 경로에서 역추적한다.

```bash
skill_dir="$(cd "$(dirname "$(readlink -f "<이 SKILL.md 가 로드된 경로>")")" && pwd -P)"
R="$skill_dir/scripts/ego-record.sh"
```

## 1. 실행

```bash
"$R" start --name "<케이스 이름>" [--size 1440x900] [--mobile] [--cursor | --no-cursor] "<대상 URL>"
# → 마지막 줄 RUN=<실행 폴더>. 이 값을 끝까지 들고 다닌다.

"$R" act "$RUN" --say "<이 라운드에서 하려는 일>" <<'EOF'
await page.click("#searchInput", { label: "click search box" });
await page.keyboard.type("Zettelkasten");
console.log(await page.title());
EOF
# 필요한 만큼 act 를 반복한다. 짧은 코드는 -e '<js>' 로 줘도 된다.

"$R" stop "$RUN"
```

- **`start` 옵션**
    - `--name` — 영상 목록에서 알아볼 짧은 이름(티켓 키 + 확인할 것). 빼면 대상 URL 의 호스트. `/`·`:` 는 `-` 로 바뀐다.
    - `--size WxH` — 페이지 화면 크기. 기본 `1440x900`. ego 창 크기는 바꾸지 않는다. 영상 크기 = 이 값.
    - `--mobile` — 모바일 흉내(`mobile: true` + 터치). 화면 폭과 터치만 바꾸고 User-Agent 는 그대로다 — UA 로 모바일 페이지를 따로 내는 사이트는 데스크톱 화면이 나올 수 있다.
    - `--cursor` (기본) / `--no-cursor` — 녹화용 커서를 그릴지. ego 의 에이전트 커서는 캡처에 찍히지 않아서(§2) 페이지 안에 커서를 직접 그린다. 커서는 마우스 이동·클릭·스크롤을 따라가고, 누르면 빨간 원이 퍼진다. DOM 검사나 화면 비교가 검증 대상이면 `--no-cursor` 로 끈다.
- **`act` 라운드**
    - 머리말이 `task`(케이스의 TaskSpace)와 `page`(고정 페이지 p1)를 만들어 둔다. **다시 선언하지 말고 그대로 쓴다** (`const page = …` 는 SyntaxError).
    - `--say` 는 타임라인의 「말」 줄이 된다. 라운드마다 무엇을 하려는지 한 줄로 준다.
    - 클릭·hover·`mouse.*` 에는 `{ label: "…" }` 를 준다 — 타임라인 줄에 그대로 남는다.
    - **p1 하나에서만 일한다.** `task.newPage()`·`adopt()`·`finish()`·`handOff()` 를 부르면 기록되고 stop 이 `[폐기]` 를 찍는다. 다른 페이지가 필요하면 p1 안에서 `goto` 한다.
    - 관찰용 `page.snapshot()`·`page.screenshot()` 은 자유롭게 쓴다(타임라인에 남기지 않는다).
- **`stop`** — 관찰자를 멈추고 TaskSpace 를 닫은 뒤 mp4 와 타임라인 초안을 만들고 프레임을 지운다. 영상 경로·영상 URL(퍼센트 인코딩 `file://`)·녹화 시작 시각·타임라인 초안 경로·고정 페이지 판정을 찍는다. §4 의 노트가 이 값을 쓰므로 출력을 흘리지 말 것.
- **`abort`** — 영상 없이 관찰자·TaskSpace·실행 폴더를 정리한다. 실패한 시작이나 버릴 녹화에 쓴다.

출력은 `~/Movies/ego-record/<케이스 이름> <YYYYmmdd-HHMMSS>.mp4` 와 같은 이름의 `.timeline.txt` 다. 기본 5fps(`EGO_RECORD_FPS`).
**저장 위치는 인자로 바꿀 수 없다** — 세션 스크래치패드로 빼면 세션이 정리될 때 영상이 같이 사라진다.
동작 기록은 `~/Movies/ego-record/.runs/<실행 폴더>/` 에 남는다(`actions.jsonl`·`nav.jsonl`·`config.json`).

### 여러 케이스를 동시에

케이스마다 `start` 를 따로 하고 각자의 `RUN` 으로 act·stop 한다. 케이스마다 TaskSpace 가 따로라 섞이지 않는다
(실측: 데스크톱·모바일 두 케이스를 동시에 98초 녹화 — 각 영상에 자기 페이지만, 캡처 오류 0건).

```bash
"$R" start --name "<케이스 A>" "<URL A>" > a.txt &
"$R" start --name "<케이스 B>" --size 390x844 --mobile "<URL B>" > b.txt &
wait
```

동시에 몇 건까지 버티는지는 재지 않았다. 늘릴 때는 stop 이 찍는 프레임 수가 fps × 길이에 못 미치는지부터 본다.

## 2. 깨뜨리면 안 되는 것 (전부 실측)

- **`ego-browser nodejs` 호출 하나는 Node 프로세스 하나다.** TaskSpace·탭·페이지 label 은 호출 사이에 남고 JS 변수는 남지 않는다. 그래서 관찰자는 `nohup` 으로 띄운 별도 프로세스이고, act 는 매번 머리말로 `task`·`page` 를 다시 잡는다. 관찰자는 도구 호출 세 번에 걸친 98초 녹화 내내 살아 있었다.
- **화면 크기와 주입 스크립트는 그것을 건 프로세스가 살아 있는 동안만 유지된다.** 별도 프로세스로 걸고 끝내면 원래 창 크기로 돌아간다. 그래서 끝까지 사는 관찰자가 건다. 관찰자가 사는 동안에는 다른 프로세스·다른 사이트로의 이동에도 유지된다.
- **`page.screenshot()` 은 PNG 만 내고 `type` 옵션을 거부한다.** JPEG 는 `page.cdp("Page.captureScreenshot", {format: "jpeg"})` 로 받는다.
- **ego 의 에이전트 커서는 캡처에 찍히지 않는다** — CDP 캡처·`screenshot()` 어느 쪽에도 없고 DOM 에도 없다. 녹화용 커서(`scripts/cursor.js`)는 `Page.addScriptToEvaluateOnNewDocument` 로 이동 뒤에도 다시 들어간다. 새 문서에서는 다음 마우스 이벤트(이동·클릭·스크롤)가 올 때까지 위치를 모른다 — 같은 출처 이동은 마지막 위치를 이어받고, 다른 사이트로 이동하면 다음 이벤트까지 숨는다.
- **페이지가 스스로 넓은 `meta viewport` 를 주면 화면 크기보다 넓게 그려 축소해 보인다**(예: 데스크톱 UA 로 연 위키백과는 `width=1120` → 390 폭 화면에서 0.35배). 영상 크기는 지정한 값 그대로이고 커서도 같이 작아진다. start 출력의 「페이지 레이아웃 폭」이 화면 폭과 다르면 이 경우다.
- **ego 의 `click` 은 요소 중앙에서 `isTrusted` 이벤트를 낸다.** 모바일 흉내에서도 pointer·mouse·click 이 같은 좌표로 온다.
- **같은 TaskSpace 의 같은 페이지를 두 프로세스(관찰자·act)가 동시에 써도 충돌하지 않는다.**
- **ego 에는 Aside 의 세션 로그 같은 동작 기록이 없다.** 타임라인은 act 머리말이 Page·mouse·keyboard 프로토타입을 감싸 남긴 `actions.jsonl` 과 관찰자의 1초 간격 URL 기록 `nav.jsonl` 로 만든다. `page.cdp()` 직접 호출과 act 를 거치지 않은 `ego-browser nodejs` 호출은 남지 않는다.
- **프레임 파일명(epoch ms)이 시각의 정본이다.** 고정 fps 로 잇지 않고 파일명 간격을 `concat` 길이로 쓴다. mp4 이름의 시각은 첫 프레임이고 타임라인 오프셋의 기준점이라 빼지 않는다.
- **`goto` 가 load 를 못 기다려 시간 초과로 끝날 수 있다**(무거운 사이트). start 는 이를 경고로만 찍고 계속한다.

## 3. 끝난 뒤 확인

- `[폐기]` 가 찍히면 그 녹화는 버린다 — p1 밖에서 일한 구간은 영상에 없다. act 에서 새 페이지를 쓰게 만든 코드를 빼고 다시 돌린다.
- 영상을 만들었다고 끝이 아니다. 첫 장면·끝 장면을 직접 본다:

```bash
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,nb_frames:format=duration -of csv=p=0 "<mp4>"
ffmpeg -v error -ss 1 -i "<mp4>" -frames:v 1 -y /tmp/head.png
ffmpeg -v error -sseof -1 -i "<mp4>" -frames:v 1 -y /tmp/tail.png
```

- 관찰자 상한(`EGO_RECORD_MAX_SECONDS`, 기본 1800초)에 걸리면 stop 이 경고한다 — 영상 뒷부분이 없다.

## 4. 타임라인 노트

녹화만 남기고 끝내지 않는다 — 영상은 훑을 수가 없다. 타임라인 초안(`.timeline.txt`)을 펴서 Media Extended
타임스탬프 링크로 구간 색인을 만들고 **사용자의 노트에 저장하는 것까지가 이 스킬의 산출물이다.**

초안 한 줄은 `MM:SS <종류> <내용>` 이다. 종류는 `말`(act 의 `--say`)·`도구`(Page·mouse·keyboard 호출)·`이동`(URL 변경)·`오류`(실패한 호출)·`위반`(p1 밖). 다시 뽑으려면 `scripts/ego-timeline.py --run <실행 폴더>`.

**초안을 그대로 옮기지 않는다.** 의미 있는 구간으로 묶고(챕터), 판정이 갈린 순간·오류·증거 장면을 굵게 세운다.
장면은 영상에서 프레임을 뽑아 직접 확인하고 쓴다 — 동작 기록만 보고 화면을 추측하지 않는다.

- 시각 링크는 `[MM:SS](<영상 URL>#t=MM:SS)`. 1시간이 넘으면 `hh:mm:ss`.
- **구간도 시작 시각 하나만 링크한다** — `[01:01–01:04](<영상 URL>#t=01:01)`. `#t=시작,끝` 범위 링크는 Media Extended 가 영상 자르기(clip)로 처리해, 누를 때마다 재생 길이가 바뀌고 이후 단일 링크도 잘린 구간 안에서만 움직인다.
- 영상 URL 은 stop 이 찍은 퍼센트 인코딩 `file://` 을 쓴다(파일명에 공백·한글).
- 첫 인용 블록에 무엇을 확인한 녹화인지, 오프셋 기준(첫 프레임 시각)과 오차(±1초 안팎), 영상이 노트 저장소 밖 `~/Movies/ego-record` 에 있다는 것을 적는다.
- 여러 케이스를 동시에 돌렸으면 케이스마다 절을 둔다.
- 저장 위치는 사용자의 노트다. Obsidian 볼트를 쓰면 그 볼트의 규칙을 따른다(`vault-entry` 스킬) — 작업의 소속을 따르고, 애매하면 사용자에게 묻는다. 만든 뒤 그 저장소의 규칙대로 인덱스를 갱신한다.

파일명 예: `<작업> 브라우저 실측 녹화 타임라인 YYYY-MM-DD.md`
