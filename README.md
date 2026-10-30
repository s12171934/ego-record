---
title: ego-record
created: 2026-10-30
updated: 2026-10-30
tags: [domain/인공지능, area/브라우저에이전트, agent/claude-5eaeaae3-acc4-4aa2-8d18-47f6008fbf34]
source: ai
---

# ego-record

ego lite(`ego-browser`)로 브라우저 작업을 하면서 그 화면을 영상으로 남기고, 동작 기록으로 시각 색인(타임라인 노트)을 만드는 에이전트 스킬이다.

- 화면을 찍지 않는다. 케이스마다 TaskSpace 의 고정 페이지 p1 에서 백그라운드 관찰자가 프레임을 직접 받는다.
- 사용자의 화면·창·키보드 포커스를 건드리지 않고, 케이스마다 TaskSpace 가 따로라 여러 녹화를 동시에 돌릴 수 있다.
- 페이지 화면 크기 지정(모바일 흉내 포함)과 녹화용 커서 표시를 지원한다.
- 결과물은 `~/Movies/ego-record/<케이스 이름> <시각>.mp4` 와 타임라인 초안, 그리고 Obsidian Media Extended 타임스탬프 링크로 된 타임라인 노트다.
- ego lite 에는 자체 에이전트가 없어, 브라우저는 이 스킬을 쓰는 에이전트가 직접 몬다(`start → act → stop`).

## 요구 사항

- macOS
- ego lite 와 `ego-browser` 명령 ([ego lite (공식 사이트)](https://lite.ego.app/))
- `ffmpeg`(`ffprobe`, `h264_videotoolbox` 포함)
- 선택: Obsidian 과 Media Extended 플러그인 (타임라인 노트의 시각 링크 재생)

`scripts/ego-record.sh check` 가 전제를 확인한다.

## 설치

```bash
git clone https://github.com/s12171934/ego-record.git ~/.claude/skills/ego-record
```

다른 도구에서도 쓰려면 그 도구의 스킬 디렉터리(`~/.codex/skills/` 등)에 이 폴더로 가는 심볼릭 링크를 만든다.

## 구성

| 경로 | 내용 |
| --- | --- |
| [[20_Agents/skills/ego-record/SKILL\|SKILL.md]] | 스킬 본문 — 실행 절차, 깨뜨리면 안 되는 제약, 확인 방법, 타임라인 노트 규칙 |
| `scripts/ego-record.sh` | 러너 — `check`·`start`·`act`·`stop`·`abort` |
| `scripts/observer.js` | 관찰자 — 고정 페이지 캡처, 화면 크기·커서 유지, URL 이동 기록 |
| `scripts/act-prelude.js` | act 머리말 — `task`·`page` 준비, Page·mouse·keyboard 호출 기록, 고정 페이지 위반 기록 |
| `scripts/cursor.js` | 녹화용 커서 오버레이 |
| `scripts/ego-timeline.py` | 동작 기록을 녹화 시작 기준 오프셋으로 펴는 타임라인 초안 도구 |

환경 변수: `EGO_RECORD_FPS`(최대 fps, 기본 5), `EGO_RECORD_MAX_SECONDS`(관찰자 상한, 기본 1800).

## 공개 면

스킬 이름 `ego-record` 만 공개 면이다. `scripts/` 와 그 밖의 파일은 내부 전용이라 예고 없이 바뀔 수 있다.
