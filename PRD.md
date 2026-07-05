# UpdateBar — Product Requirements Document

> Historical PRD snapshot. For current implementation decisions, see
> [`current-plan.md`](current-plan.md) and
> [`current-architecture.md`](current-architecture.md). For upcoming work, see
> [`next-plan.md`](next-plan.md).
> Do not use this file as the source of truth for new implementation work.
> Several OpenRouter/provider/sync assumptions below were superseded by the
> CLI-first reset.

| 항목 | 값 |
|------|-----|
| 문서 상태 | Draft v1.1 (2차 다관점 리뷰 반영: 보안 신뢰모델 §22, 상태 갱신모델 §9.1, 메뉴바 계약 정합, exit-code·크로스플랫폼 등) |
| 작성일 | 2026-06-08 (개정 2026-06-09) |
| 한 줄 정의 | 카테고리에 구애받지 않고 무엇이든 등록해 버전 추적·업데이트·싱크를 한 곳에서 해주는 CLI 도구. macOS 메뉴바에서도 상태 확인·작업 실행 가능. |
| 핵심 원칙 | LLM은 등록·진단에서만, 런타임은 결정론적. CLI 우선, 메뉴바는 얇은 클라이언트. |

## 목차

1. [개요 / 한 줄 정의](#1-개요--한-줄-정의)
2. [문제 정의](#2-문제-정의)
3. [타깃 사용자 & 페르소나](#3-타깃-사용자--페르소나)
4. [핵심 사용 시나리오](#4-핵심-사용-시나리오-유저-스토리)
5. [목표 / 비목표](#5-목표--비목표)
6. [성공 지표](#6-성공-지표)
7. [기존 솔루션 분석](#7-기존-솔루션-분석)
8. [핵심 설계 원칙](#8-핵심-설계-원칙)
9. [시스템 아키텍처](#9-시스템-아키텍처)
10. [파일 레이아웃](#10-파일-레이아웃)
11. [데이터 모델](#11-데이터-모델)
12. [CLI 명령 표면](#12-cli-명령-표면)
13. [등록 플로우 (2-path)](#13-등록-플로우-2-path)
14. [LLM Provider 레이어](#14-llm-provider-레이어)
15. [배포 & 패키징](#15-배포--패키징)
16. [비용](#16-비용)
17. [macOS 실행 / 권한 제약](#17-macos-실행--권한-제약)
18. [레퍼런스 매핑 (RepoBar → UpdateBar)](#18-레퍼런스-매핑-repobar--updatebar)
19. [제약 & 리스크](#19-제약--리스크)
20. [오픈 퀘스천](#20-오픈-퀘스천-prd에서-답해야-할-결정-사항)
21. [빌드 마일스톤 (로드맵)](#21-빌드-마일스톤-로드맵)
22. [보안 모델 — 레시피 신뢰 경계](#22-보안-모델--레시피-신뢰-경계)

---

## 1. 개요 / 한 줄 정의

**한 줄 정의**: UpdateBar는 카테고리에 구애받지 않고 무엇이든 등록해 버전 추적·업데이트·싱크를 한 곳에서 해주는 CLI 도구입니다. macOS 메뉴바에서도 상태 확인과 작업 실행이 가능합니다.

**엘리베이터 피치**: 스킬, 앱, 플러그인, MCP 서버까지 — 우리는 점점 더 많은 종류의 도구를 손으로 설치하고, 제각각의 방식으로 업데이트하며 살고 있습니다. UpdateBar는 이 모든 이종(異種) 항목을 단일 레지스트리에 등록하고, 항목별 업데이트 방식을 선언적 레시피로 정의해, "무엇이 오래됐고 어떻게 최신화하는가"를 하나의 도구로 통합합니다. 핵심은 결정론적이고 스크립트 친화적인 CLI이며, macOS 메뉴바 앱은 그 위에 얹힌 얇은 클라이언트로서 "업데이트 N개" 배지와 원클릭 실행을 제공합니다.

## 2. 문제 정의

도구 생태계가 폭발적으로 다양해지면서, 사용자가 다루는 "업데이트 대상"의 종류와 출처가 통제 불가능할 만큼 늘어났습니다. 그 결과 다음과 같은 페인포인트가 반복됩니다.

- **도구 종류가 너무 많아 버전 관리가 힘듦** — 스킬/하니스(skill/harness), openclaw, hermes, opendesign, ouroboros, superpowers처럼 출처도 형태도 제각각인 도구들이 동시에 쌓입니다.
- **무엇을 업데이트해야 할지 잊어버림** — 어떤 항목이 최신인지, 새 버전이 나왔는지 추적할 단일 화면이 없습니다.
- **결국 옛 버전을 계속 씀** — 확인·업데이트가 번거로워 미루다가, 오래된 버전을 그대로 사용하게 됩니다.
- **도구마다 업데이트 방식이 제각각** — 어떤 것은 `git pull`, 어떤 것은 `npm`/`brew`, 또 어떤 것은 재클론(re-clone)이 필요해, 매번 "이건 어떻게 올리더라?"를 떠올려야 합니다.

**대상 항목의 다양성(예시)**

| 구분 | 예시 |
|------|------|
| 예시 도구 | skill/harness, openclaw, hermes, opendesign, ouroboros, superpowers |
| 형태(form factor) | 스킬(Skill), 앱(App), 플러그인(Plugin), MCP 서버 |
| 업데이트 방식 | `git pull`, `npm`, `brew`, 재클론 등 |

문제의 본질은 "버전을 모른다"가 아니라, **이종 항목을 일관된 방식으로 추적·업데이트할 공통 레이어가 없다**는 데 있습니다.

## 3. 타깃 사용자 & 페르소나

**주 사용자**: AI 에이전트·개발도구 생태계의 헤비 유저, 그리고 일반 개발자. 특히 스킬·플러그인·MCP·CLI 도구를 수시로 설치하고 직접 관리하는 사람들입니다.

**페르소나 1 — 지호 (AI 워크플로우 빌더)**
- 여러 에이전트 하니스와 스킬을 조합해 자신만의 워크플로우를 만드는 파워 유저.
- 깃 레포에서 클론한 스킬, npm으로 설치한 CLI, brew로 깐 앱이 한데 섞여 있음.
- 새 버전이 나와도 알아채지 못하거나, 업데이트 방법이 기억나지 않아 방치함.
- 니즈: "내가 쓰는 모든 도구의 최신 여부를 한눈에 보고, 클릭 한 번/명령 한 줄로 올리고 싶다."

**페르소나 2 — 민준 (개발자, CLI 우선)**
- 터미널 중심으로 일하며, 자동화와 스크립트화 가능한 도구를 선호.
- 업데이트 작업을 CI나 셸 스크립트에 엮고 싶어 하고, GUI는 보조 수단으로만 활용.
- 니즈: "결정론적이고 스크립트로 호출 가능한 인터페이스가 우선, 상태 확인용 메뉴바는 곁들임으로 충분하다."

## 4. 핵심 사용 시나리오 (유저 스토리)

**시나리오 A — 새 스킬 CLI 등록 및 자동 추적 설정**
> AI 워크플로우 빌더로서, 새로 설치한 스킬 CLI를 UpdateBar에 등록하면, 버전 확인 방법과 업데이트 방법이 자동으로 구성되어, 이후 별도 수고 없이 최신 여부를 추적하고 싶다.

**시나리오 B — 메뉴바 배지로 일괄/개별 업데이트**
> 사용자로서, macOS 메뉴바에 "업데이트 N개" 배지가 떠 있는 것을 보고, 클릭해서 항목별로 개별 업데이트하거나 한 번에 일괄 업데이트하고 싶다.

**시나리오 C — 여러 폴더에 흩어진 동일 스킬 sync 정합**
> 헤비 유저로서, 같은 스킬이 여러 툴 폴더에 흩어져 설치돼 있을 때, sync 기능으로 버전을 정합(整合)시켜 일관된 상태로 맞추고 싶다.

**시나리오 D — 깨진 업데이트 진단/복구**
> 사용자로서, 업데이트가 실패하거나 깨졌을 때, 무엇이 잘못됐는지 진단하고 복구할 수 있는 수단을 제공받아, 도구를 다시 정상 상태로 되돌리고 싶다.

## 5. 목표 / 비목표

**목표**

- **이종 항목의 단일 레지스트리 통합** — 스킬/앱/플러그인/MCP 등 형태가 다른 항목을 하나의 레지스트리에서 등록·추적.
- **항목별 업데이트 레시피의 선언적·공유 가능화** — 버전 확인과 업데이트 절차를 선언적 레시피로 정의하고, 이를 공유·재사용할 수 있게 함.
- **결정론적 버전 체크/업데이트 + 선택적 LLM 보조** — 기본 동작은 결정론적이고 재현 가능하게 하되, 레시피 작성·진단 등에서 LLM을 선택적으로 보조 수단으로 활용.
- **CLI 우선, 메뉴바는 얇은 클라이언트** — 핵심 기능과 진실의 원천(source of truth)은 CLI에 두고, macOS 메뉴바 앱은 상태 표시·작업 트리거를 담당하는 얇은 클라이언트로 설계.

**비목표 (v1)**

- **언어 런타임 버전 매니징 대체 아님** — asdf/mise 등의 런타임 버전 관리자를 대체하지 않음.
- **패키지 레지스트리 호스팅 아님** — 패키지를 호스팅·배포하는 레지스트리 서비스가 아님.
- **Windows/Linux 메뉴바 미지원** — 코어 CLI는 크로스플랫폼이 가능하나, 메뉴바 클라이언트는 macOS를 우선으로 함.

## 6. 성공 지표

아래 지표를 통해 "등록 → 추적 → 최신화"의 핵심 루프가 작동하는지를 측정합니다. (단, "메뉴바 일/주 활성"은 메뉴바가 출시 범위에 포함될 때만 유효합니다 — §20 Q1의 v1 스코프 결정에 종속됩니다. CLI-only로 먼저 출시할 경우 나머지 4개 지표로 측정합니다.)

| 지표 | 정의 | 의미 |
|------|------|------|
| 등록 항목 수 | 사용자/디바이스당 UpdateBar에 등록된 항목 수 | 통합 레지스트리로서의 채택도 |
| outdated → up-to-date 전환율 | 오래된 것으로 감지된 항목 중 실제 최신화된 비율 | "결국 옛 버전을 계속 쓴다"는 핵심 문제 해소 정도 |
| AI 등록 성공률 | 자동/AI 보조로 생성된 레시피가 라이브 테스트(버전 확인·업데이트 실행)를 통과하는 비율 | 등록 경험의 신뢰성 |
| 메뉴바 일/주 활성 | 메뉴바 클라이언트의 DAU/WAU | 상시 노출 채널로서의 지속 사용 |
| 업데이트 실행 횟수 | 기간당 CLI·메뉴바를 통한 업데이트 실행 건수 | 도구가 만들어내는 실질적 행동 빈도 |

## 7. 기존 솔루션 분석

UpdateBar가 풀려는 문제 — "이종(異種) 항목을 단일 레지스트리에 등록하고, 항목별로 무엇이 outdated인지 추적하며, 선언적 레시피로 최신화한다" — 에 정확히 들어맞는 단일 제품은 현재 존재하지 않습니다. 인접 영역에 강력한 도구들이 흩어져 있을 뿐이며, 이들의 장점을 조합해야 비로소 UpdateBar의 형태가 됩니다.

| 제품 / 부류 | 강점 | 한계 (UpdateBar 관점) |
|------------|------|----------------------|
| **topgrade** | 50개 이상의 도구를 자동 감지해 업데이트, TOML `[commands]`로 임의 커스텀 업데이트 스텝 등록, 크로스플랫폼 지원 | 항목별 버전 추적·레지스트리 개념이 없고, "무엇이 outdated인지"를 표시하지 않음. 메뉴바 없음. 상태 구분 없이 그냥 전부 실행 |
| **universal-skills-manager** | Claude/Codex/Gemini/openclaw/hermes에 걸쳐 스킬을 발견·설치하고 툴 간 싱크, 어느 쪽이 최신인지 표시 | 스킬에 특화됨. 임의 카테고리를 자유롭게 등록하는 범용 레이어가 아님 |
| **McPick** | MCP 서버 + Claude Code 플러그인의 install/update/enable을 한 곳에서, 레지스트리 동기화, TUI 제공 | MCP·플러그인 영역에 한정됨 |
| **Claude Code 네이티브 마켓플레이스** | 플러그인/스킬/MCP의 공식 경로, last updated 표시 | Claude Code 내부에 갇혀 있어 범용적이지 않음 |
| **CodexBar** | 메뉴바 + 번들 CLI 구조, 40개 이상의 프로바이더, provider guide 확장, OAuth/API key 멀티 인증 | 버전 관리가 아니라 사용량 한도 추적이 목적. 단, 구조적 템플릿으로는 최적의 참조 모델 |
| **asdf / mise / proto / vfox** | 플러그인 기반의 확장형 버전 매니저 | 언어 런타임·개발 툴이 대상이며, 일반 스킬/앱은 다루지 않음 |

**결론**: 정확히 들어맞는 단일 제품은 없으며, 명확한 빈자리가 존재합니다. **topgrade의 커스텀 명령 모델 + 항목별 버전 추적 레이어 + CodexBar식 메뉴바/플러그인 구조**를 합치면 그것이 바로 UpdateBar입니다.

## 8. 핵심 설계 원칙

UpdateBar의 아키텍처는 단 하나의 명제 위에 세워집니다. **LLM은 등록과 진단에서만 쓰이고, 런타임은 철저히 결정론적이다.**

버전 체크, 버전 비교, 업데이트 실행은 매번 동일한 셸 명령으로만 수행되며 LLM을 호출하지 않습니다. 한 번 등록된 항목은 이후 수백 번의 주기적 점검을 거치더라도 추론이 개입할 여지가 없습니다. 이는 비용·지연·재현성 세 가지를 동시에 해결합니다. 메뉴바가 1분마다 상태를 갱신하더라도 토큰 소모는 0이며, 같은 입력에 대해 항상 같은 출력이 보장되어 디버깅이 단순해집니다.

LLM은 본질적으로 "사람이 하기 번거로운 자연어·반정형 작업"에만 국한됩니다. 구체적으로는 다음 세 지점입니다.

1. **등록 시 레시피 추론** — 임의의 도구·앱·스킬을 어떻게 점검하고 업데이트할지를 선언적 레시피로 변환합니다.
2. **체인지로그 요약** — 최신 버전과 현재 버전 사이의 변경점을 요약하고 호환성 파괴(breaking) 여부를 가립니다.
3. **업데이트 실패 복구 제안** — 실행 중 발생한 오류를 진단하고 수정안을 제시합니다.

이 경계가 시스템 전반의 책임 분리를 규정합니다. 추론은 "한 번, 사람의 확인을 거쳐" 일어나고, 실행은 "반복적으로, 무인으로" 일어납니다.

## 9. 시스템 아키텍처

UpdateBar는 세 개의 계층으로 구성됩니다.

- **메뉴바 (Swift, 얇은 클라이언트)** — UI 표시와 사용자 상호작용만 담당합니다. 비즈니스 로직을 일절 포함하지 않으며, 오직 자기 자신의 CLI(`updatebar`)만 실행하고 그 `--json` 출력을 파싱해 렌더링합니다. 메뉴바는 상태를 계산하지 않고 *표시*만 합니다.
- **`updatebar` CLI (핵심 엔진)** — 모든 로직의 단일 진실 공급원입니다. 명령은 두 부류로 명확히 나뉩니다. 결정론적 명령(`list` / `check` / `status` / `update` / `sync`, 그리고 `pin`·`unpin`·`enable`·`disable`·`remove`·`edit`·`export`·`import` 등 레시피 조작 명령 — §12 전체)은 LLM을 호출하지 않으며, LLM 사용 명령(`add` / `diff` / `doctor`)만이 Provider 계층을 경유합니다.
- **Provider 인터페이스** — LLM 호출을 추상화합니다. 기본값은 로컬 실행되는 `ollama`이며, 가속기로 `codex`(`codex exec`)와 `claude`(`claude -p`)를 선택할 수 있습니다.

상태는 두 개의 파일로 영속됩니다. `manifest.json`은 항목 레시피(선언적 정의)를, `state.json`은 현재 버전과 최신 버전(계산된 값)을 담습니다.

```
            macOS 메뉴바 (Swift, 얇은 클라이언트)
                       │  자기 CLI만 실행, --json 파싱
                       ▼
   ┌─────────────────  updatebar (CLI)  ─────────────────┐
   │  결정론적 (LLM X)            LLM 사용                 │
   │  list / check / status      add / diff / doctor      │
   │  update / sync                  │                    │
   │       │                  Provider 인터페이스          │
   │       │                  ├ ollama (기본, 로컬)        │
   │       │                  ├ codex  (codex exec)        │
   │       │                  └ claude (claude -p)         │
   │       ▼                                              │
   │  manifest.json (레시피)   state.json (현재/최신)      │
   └──────────────────────────────────────────────────────┘
```

### 9.1 상태 갱신 모델 (status / check 분리)

메뉴바가 자주 폴링하는 `status`가 셸·네트워크를 직접 돌면 수 초간 블로킹되고 rate-limit에 걸립니다. 따라서 **읽기(`status`)와 갱신(`check`)을 엄격히 분리**합니다.

- **`status`** = `state.json`의 **순수 읽기**입니다. 셸을 실행하지 않고, 네트워크를 호출하지 않으며, 절대 블로킹하지 않습니다. 항상 마지막으로 계산된 스냅샷을 즉시 반환합니다.
- **`check`** = 실제 점검을 수행하는 갱신 경로입니다. 백그라운드(메뉴바의 타이머 또는 cron/launchd, CLI 수동 호출)에서 돌며 `state.json`을 채웁니다. 항목별 `check`/`latest` 조회를 **동시성 캡(예: 8)** 으로 병렬 실행합니다.
- **TTL & 신선도**: 각 항목의 `last_checked`와 `config.toml`의 `refresh_interval`을 비교해 만료된 항목만 재점검합니다. `status --refresh`는 만료를 무시하고 강제 재점검을 트리거하되, 트리거만 하고 완료를 기다리지 않습니다(해당 항목은 `checking` 상태로 표시).
- **Rate-limit 회피**: `github_release`/`git_tags` 등 네트워크 전략은 per-strategy TTL 캐시 + 조건부 요청(ETag/`304`)을 사용하고, GitHub 비인증 한도(60 req/hr)를 넘지 않도록 선택적 토큰을 지원합니다(§22 참조). 실패는 지수 백오프.

> 요약: 메뉴바는 캐시를 *본다*, 백그라운드 `check`가 캐시를 *채운다*. 네트워크·셸은 절대 hot path에 두지 않습니다.

## 10. 파일 레이아웃

모든 영속 상태는 `~/.updatebar/` 아래 세 파일로 관리됩니다. 핵심은 **레시피(선언적 정의)와 상태(계산된 값)의 엄격한 분리**입니다.

| 파일 | 역할 | 생성 주체 | 공유성 |
|------|------|-----------|--------|
| `~/.updatebar/manifest.json` | 항목별 레시피 — *무엇을 어떻게* 점검·업데이트할지 선언 | LLM 등록 시 생성(또는 수동 입력) | 선언적, 머신 간 공유 가능 |
| `~/.updatebar/state.json` | id별 현재 버전 / 최신 버전 / 마지막 체크 시각 | 런타임이 계산해 기록 | 머신 로컬, gitignore 대상 |
| `~/.updatebar/config.toml` | provider 선택, refresh 주기 등 사용자 설정 | 사용자 | 머신 로컬 |

이 분리 덕분에 레시피는 팀·기기 간에 그대로 복제·공유할 수 있고(`export`/`import`), 상태는 각 기기에서 독립적으로 다시 계산됩니다. 레시피를 옮긴다고 해서 남의 설치 상태를 끌고 오는 일이 없습니다.

**`config.toml` 키 (초안)**

```toml
[provider]
default = "ollama"            # ollama | codex | claude
github_token = ""             # 선택: latest 네트워크 전략의 rate-limit 완화

[refresh]
interval = "6h"               # 백그라운드 check TTL (예: 30m, 6h, 1d)
concurrency = 8               # 동시 점검 항목 수 캡

[security]
allow_import_exec = false     # import한 레시피 cmd의 무인 실행 허용 여부 (기본 차단, §22)
require_https_source = true   # http(s) 소스에서 평문 http 거부

[notify]
enabled = true                # notify:true 항목의 알림 전역 on/off
```

키 형식·기본값은 마일스톤 진행 중 확정합니다.

## 11. 데이터 모델

### 11.1 항목 레시피 스키마

레시피는 "이 항목을 어떻게 다룰지"를 선언적으로 기술합니다. 한 항목당 하나의 객체이며 `manifest.json`의 배열 원소로 저장됩니다.

```json
{
  "id": "claude-code",
  "name": "Claude Code",
  "category": "cli",
  "path": "~/.local/bin/claude",
  "source": {
    "kind": "npm",
    "ref": "@anthropic-ai/claude-code",
    "branch": null
  },
  "version_scheme": "semver",
  "check": { "cmd": "claude --version" },
  "latest": {
    "strategy": "npm_registry",
    "cmd": null,
    "pattern": null
  },
  "version_parse": { "regex": "([0-9]+\\.[0-9]+\\.[0-9]+)" },
  "update": {
    "cmd": "npm i -g @anthropic-ai/claude-code@latest",
    "requires_write": true,
    "cwd": null
  },
  "sync": null,
  "pin": null,
  "enabled": true,
  "notify": true
}
```

| 필드 | 의미 |
|------|------|
| `id` | 항목 고유 식별자(머신 친화적 키). 모든 명령·상태가 이 키로 항목을 지목한다. |
| `name` | 사람이 읽는 표시 이름. |
| `category` | 자유 형식 분류. `skill`/`app`/`plugin`/`mcp`/`cli`/`dotfile` 등. 그룹핑·필터 용도이며 동작에 영향 없음. |
| `path` | 항목이 설치된 로컬 경로(있을 때). |
| `source.kind` | 출처 종류: `git`·`npm`·`github_release`·`brew`·`http`·`custom` 중 하나. |
| `source.ref` | 출처 식별자(저장소 URL, 패키지명, formula명 등). |
| `source.branch` | git 계열에서 추적할 브랜치(해당 없으면 `null`). |
| `version_scheme` | 버전 해석 방식: `semver`·`commit`·`calver`·`opaque`. 비교 로직을 결정한다. |
| `check` | 현재 버전 산출 방식. `{cmd}`(명령 실행) **또는** `{file, query}`(파일 읽고 질의) 중 하나(oneOf). `query`는 파일 형식에 따른 추출식: JSON/YAML이면 `jq` 표현식, 일반 텍스트면 캡처 그룹 1개짜리 정규식. |
| `latest` | 최신 버전 조회 전략: `git_tags`·`git_head`·`npm_registry`·`github_release`·`brew`·`http_regex`·`cmd`. 전략별로 `cmd`(전략=`cmd`일 때 필수)·`pattern`(전략=`http_regex`일 때 필수) 보조 필드 사용. **source.kind ↔ 기본 strategy 매핑**: `git`→`git_tags`/`git_head`, `npm`→`npm_registry`, `github_release`→`github_release`, `brew`→`brew`, `http`→`http_regex`, `custom`→`cmd`(레시피가 직접 명령 지정). |
| `version_parse` | 원시 출력에서 버전 문자열을 추출. **oneOf**: `{ "regex": "<캡처 그룹 1개 정규식>" }` **또는** `{ "jq": "<jq 표현식>" }`. 둘 중 하나만 지정. (예: `{"jq": ".version"}`) |
| `update` | 업데이트 실행 명령(`cmd`), 쓰기 권한 필요 여부(`requires_write`, 기본 `true`), 실행 디렉터리(`cwd`). |
| `sync` | 동일 항목을 여러 위치에 전파할 때의 설정. `targets[]`, `strategy`(`copy_newest`·`symlink`·`cmd`), `cmd`. |
| `pin` | 특정 버전에 고정. 설정 시 업데이트 대상에서 제외(상태=`pinned`). |
| `enabled` | 항목 활성화 여부(기본 `true`). `false`면 점검·업데이트 모두 건너뜀(상태=`disabled`). |
| `notify` | 업데이트 가능 시 알림 여부(기본 `true`). **전달 수단**: 메뉴바 실행 중이면 배지/드롭다운, 메뉴바 미사용(CLI-only) 환경에서는 macOS `UserNotifications`(선택) 또는 `check` 출력의 요약 라인. `config.toml`의 `[notify].enabled`로 전역 차단 가능. |

**version_scheme 메모.** 스킬·플러그인은 semver를 따르지 않는 경우가 흔합니다. 비교 규칙은 scheme별로 다릅니다.

- `semver` — 표준 semver 정렬로 대소 비교. 가장 정확.
- `commit` — 로컬 sha vs 리모트 sha. **리모트 조회에 네트워크가 필요**하므로 §9.1의 TTL·rate-limit 대상입니다. 다르면 "업데이트 있음".
- `calver` — 날짜 기반(예: `2026.06`, `24.1.0`). 토큰을 숫자로 좌→우 비교하되, 형식이 불규칙하면 `opaque`로 강등합니다.
- `opaque` — 두 문자열의 **단순 불일치만** 감지합니다. 방향(신/구)을 알 수 없으므로 상태를 "outdated"가 아니라 "**differs(다름)**"로 표기하고, 다운그레이드·사이드그레이드를 outdated로 오판하지 않습니다.

즉 모든 항목에 의미 있는 버전 번호가 있다고 가정하지 않으며, 불확실성은 상태에 그대로 노출합니다.

> **정식 JSON Schema (draft 2020-12)** 는 별도 산출물로 유지합니다(`$id: updatebar/item.schema.json`, `additionalProperties: false`, `required: [id, name, category, version_scheme, check, latest, update]`). 위 예시는 그 스키마를 만족하는 한 인스턴스입니다.

### 11.2 status 출력 스키마

`status` 명령은 메뉴바가 직접 소비하는 결정론적 산출물입니다. 이는 `state.json`의 캐시된 스냅샷을 그대로 직렬화한 것으로, 네트워크·셸 실행 없이 즉시 반환됩니다(§9.1).

```json
{
  "generated_at": "2026-06-08T09:00:00Z",
  "summary": { "total": 12, "outdated": 3, "errors": 1 },
  "items": [
    {
      "id": "claude-code",
      "name": "Claude Code",
      "category": "cli",
      "current": "1.4.2",
      "latest": "1.5.0",
      "status": "outdated",
      "pinned": false,
      "last_checked": "2026-06-08T08:59:40Z",
      "error": null
    }
  ]
}
```

| 필드 | 의미 |
|------|------|
| `generated_at` | 이 스냅샷 생성 시각(ISO 8601). |
| `summary.total` | 전체 항목 수. |
| `summary.outdated` | 업데이트 가능 항목 수. **`pinned`·`disabled` 항목은 제외**(아래 우선순위 규칙 참조). |
| `summary.errors` | 점검 중 오류가 난 항목 수. |
| `items[].id` / `name` / `category` | 항목 식별·표시·분류 정보(레시피에서 옴). |
| `items[].current` | 현재 설치된 버전. |
| `items[].latest` | 조회된 최신 버전. |
| `items[].status` | `ok`·`outdated`·`differs`·`error`·`pinned`·`disabled`·`checking` 중 하나. 메뉴바 아이콘·색상을 결정. |
| `items[].pinned` | 버전 고정 여부(불리언). `status:"pinned"`와 중복 표기되지만, `pinned`는 *고정 사실*을, `status`는 *표시 상태*를 나타냄(우선순위 규칙 참조). |
| `items[].last_checked` | 마지막 점검 시각. |
| `items[].error` | 오류 시 메시지(정상이면 `null`). |

**status 값의 생산자·우선순위.** 한 항목이 여러 조건에 해당할 수 있으므로(예: 고정됐는데 신버전 존재), 단일 `status` 값을 다음 우선순위로 결정합니다 — **상태 오버라이드 > 버전 상태**:

1. `disabled` — `enabled:false`이면 무조건 이 값(점검 자체를 안 함).
2. `pinned` — `pin`이 설정됐으면 이 값(신버전이 있어도 `outdated`보다 우선). 고정 사실은 `pinned:true`로도 병기.
3. `error` — 마지막 점검이 실패했으면 이 값. `error` 필드에 메시지.
4. `checking` — **백그라운드 `check`가 해당 항목을 갱신 중일 때**의 일시 상태. `status --refresh`(§9.1)가 항목을 큐에 넣는 순간 세팅되고, 점검 완료 시 아래 버전 상태로 교체됨.
5. 버전 상태 — 위에 해당하지 않으면 비교 결과: 최신이면 `ok`, semver/calver상 더 신버전이 있으면 `outdated`, `opaque`로 단지 다르면 `differs`.

`summary.outdated`는 위 1~2(`disabled`/`pinned`)에 걸린 항목을 세지 않습니다. 메뉴바 배지 숫자 = `summary.outdated`. (`pinned`/`disabled`/`checking` 버킷 카운트는 `summary`에 두지 않고 메뉴바가 `items[]`를 스캔해 집계합니다 — 의도된 최소 계약.)

이 스키마가 **CLI ↔ 메뉴바 계약**입니다. 메뉴바는 이 형식만 알면 되고, 내부 구현 변경에 영향받지 않습니다.

## 12. CLI 명령 표면

`updatebar`의 모든 기능은 단일 CLI로 노출됩니다. 메뉴바를 포함한 모든 소비자는 이 표면만 사용합니다.

| 명령 | LLM | 주요 옵션 | 설명 |
|------|:---:|-----------|------|
| `add` | 선택적 | `--from <path\|url>` `--manual` `--ai`(기본) `--provider` `--dry-run` | 새 항목 등록. **기본은 `--ai`**(LLM이 레시피 추론), `--manual`은 사람이 직접 입력하는 fallback. |
| `list` | X | `--json` | 등록된 항목 나열. |
| `check` | X | `[id...]` `--json` | 지정 항목(또는 전체)의 현재/최신 버전 점검. |
| `status` | X | `--json` `--refresh` | 메뉴바용 종합 상태 출력. `--refresh`로 강제 재점검. |
| `update` | X | `[id...\|--all]` `--yes` | 업데이트 실행. `pin`·`enabled`·`requires_write`를 존중. |
| `sync` | X | `[id...]` | 레시피의 `sync` 설정에 따라 여러 위치에 전파. |
| `diff` | O | `[id]` | 현재↔최신 체인지로그 요약, breaking 여부 판정. |
| `doctor` | O | `[id]` | 점검·업데이트 실패 진단 및 수정안 제시. |
| `pin` / `unpin` | X | `<id> [version]` | 버전 고정/해제. |
| `enable` / `disable` | X | `<id>` | 항목 활성/비활성. |
| `remove` / `edit` | X | `<id>` | 레시피 삭제/편집. |
| `export` / `import` | X | `[file]` | manifest 공유용 내보내기/가져오기. |

메뉴바는 LLM을 쓰지 않는 빠른 결정론적 명령(`status` 등)만 호출합니다.

**Exit-code 계약 (스크립트/CI용).** 페르소나 민준의 자동화 시나리오를 위해 종료 코드를 고정합니다.

| 코드 | 의미 |
|---|---|
| `0` | 성공. (`check`/`status`에서는 "모든 항목 최신"도 0.) |
| `1` | 일반 실행 오류(잘못된 인자, 레시피 없음 등). |
| `2` | 부분 실패 — 일부 항목이 오류. `--json` 출력의 `items[].error`로 항목별 원인 식별. |
| `10` | `check`/`status`에서 **업데이트 가능 항목 존재**(CI가 "outdated면 실패" 게이트로 활용). `--exit-zero-on-outdated`로 무효화 가능. |

`update`/`sync`는 본 실행이 모두 성공하면 `0`, 일부 실패면 `2`. 모든 명령은 `--json` 시 사람용 메시지를 stderr, 데이터는 stdout으로 분리합니다.

## 13. 등록 플로우 (2-path)

신규 항목 등록은 두 경로(`manual`, `ai`)로 갈라지지만, **동일한 파이프라인을 공유합니다.**

```
제안(사람 또는 LLM)
  → 스키마 검증
  → cmd 검토·승인 (사람이 check/latest/update 명령 문자열을 보고 확인)
  → 샌드박스 라이브 테스트 (네트워크·FS·시간 제한)
  → (실패 시 수정)
  → 저장
```

- **manual** — 사람이 레시피 필드를 직접 입력해 "제안"을 만듭니다.
- **ai** — LLM이 `--from`으로 주어진 경로·URL을 분석해 레시피를 추론하고 "제안"을 만듭니다.

이후 단계는 두 경로가 완전히 같습니다. 제안된 레시피는 먼저 스키마로 검증됩니다.

**중요 — 실행 전 사람 확인이 선행합니다.** 라이브 테스트는 셸 명령을 실제로 돌리므로, AI가 추론한 cmd든 사람이 입력한 cmd든 **실행에 앞서 전체 명령 문자열을 사람에게 보여주고 승인을 받습니다.** 특히 AI 경로에서는 신뢰할 수 없는 입력(레포 README·웹페이지)이 프롬프트에 섞여 악성 명령을 유도할 수 있으므로(프롬프트 인젝션), "LLM이 만든 명령을 무인 실행"하지 않습니다. 자세한 위협 모델과 격리 방식은 §22를 참조하십시오.

승인된 명령만 **샌드박스 라이브 테스트**에 들어갑니다. 시스템은 (1) `check` 명령을 실행해 버전 문자열이 나오는지, (2) `latest` 전략을 찔러 최신 버전이 조회되는지, (3) `update`를 dry-run으로 돌려 명령이 성립하는지를 확인합니다. 단, **dry-run은 보안 경계가 아니라 best-effort 점검입니다**(§19·§22) — 도구가 dry-run을 존중하지 않을 수 있으므로, 테스트 자체를 선언된 소스 외 네트워크 차단·쓰기 금지·시간/리소스 제한 샌드박스에서 돌립니다. 테스트가 실패하면 그 오류 메시지를 LLM에 재투입해 레시피를 자가 수정하게 하고, **수정된 명령도 다시 사람 확인을 거칩니다** — 이는 `doctor` 루프와 동일한 메커니즘의 재사용입니다.

AI 등록이 "쉬운" 이유는 *생성* 능력이 아니라 **자동 테스트 + 승인 게이트** 덕분입니다. 모델이 끝내 수렴하지 못하면 manual을 fallback으로 제공합니다. "LLM이 그럴듯한 레시피를 뱉는 것"이 아니라 "사람이 승인한 명령의 실제 동작을 기계가 보증하는 것"이 신뢰의 근거입니다.

## 14. LLM Provider 레이어

모든 LLM 작업은 단일한 형태로 환원됩니다 — **"이 스키마를 채워라."** 레시피 추론도, 체인지로그 요약도, 실패 진단도 결국 정해진 JSON 스키마를 만족하는 객체를 받아내는 문제로 귀결됩니다. 덕분에 Provider 인터페이스는 극도로 좁습니다. (아래 시그니처는 계약을 보여주기 위한 **언어 중립 의사코드**입니다. 실제 구현은 UpdateBarCore의 Swift `protocol`이며, TypeScript 표기는 가독성을 위한 것일 뿐 런타임에 JS가 쓰인다는 뜻이 아닙니다.)

```ts
interface CompletionRequest { prompt: string; schema: object; context?: string; maxRetries?: number; }
interface Provider {
  readonly name: string;
  complete(req: CompletionRequest): Promise<unknown>; // schema 통과 객체, 실패 시 재시도 후 throw
}
```

신뢰성은 **생성 → 스키마 검증 → 실패 시 오류를 붙여 재프롬프트**(기본 3회)의 루프에서 나옵니다. 모델이 스키마를 위반하면 그 위반 사실 자체를 다음 프롬프트의 컨텍스트로 되먹여, 통과할 때까지(또는 재시도 한도까지) 조입니다.

구현별 특성은 다음과 같습니다.

- **codex** (`codex exec`) — 저장된 CLI 로그인을 재사용합니다. `--output-schema`로 네이티브 스키마 강제를 지원하고, `--json` 출력과 `--skip-git-repo-check` 플래그를 사용합니다. 스키마 준수가 엔진 레벨에서 보장되어 재시도 빈도가 낮습니다.
- **claude** (`claude -p`) — `--output-format json`을 지원하나 네이티브 스키마 플래그는 없으므로, 프롬프트에 스키마를 싣고 사후 검증으로 보강합니다. 다만 구독 기반 헤드리스 사용의 과금·약관은 변동 가능성이 있습니다(예: 헤드리스 호출이 별도 크레딧으로 차감되는 방향의 정책 변경이 보고된 바 있어, 확정 사실로 간주하지 말고 출시 시점에 재확인 필요). 소비자 약관상 자동화 접근의 회색지대도 존재합니다. (단, `add`는 사용자가 직접 치는 인터랙티브 명령이라 부담은 작습니다.)
- **ollama** — 로컬 JSON 모드로 실행되어 쿼터·약관 이슈를 우회합니다. 외부 의존이 없어 기본값으로 적합합니다.

인증 옵션은 로컬 CLI OAuth(`codex login` / `claude login` 재사용), OpenRouter API key, 로컬 ollama로 나뉘며, 모두 동일한 Provider 인터페이스를 통과합니다.

**권장 기본값**: `ollama` 우선. `codex`·`claude`는 더 높은 추론 품질이 필요할 때 선택적으로 켜는 가속기로 둡니다. LLM은 저빈도(등록·진단)에만 쓰이므로 로컬로 충분합니다.

## 15. 배포 & 패키징

UpdateBar는 steipete의 **RepoBar**, **CodexBar** 계열을 직접적인 레퍼런스로 삼습니다. 두 제품 모두 *메뉴바 앱 + 번들 CLI*를 단일 산출물로 묶어 MIT 라이선스로 무료 공개하는 네이티브 macOS 앱이며, UpdateBar는 동일한 배포 구조를 그대로 채택합니다.

### 15.1 패키지 구성

- **SwiftPM 패키지**(Xcode 프로젝트가 아님)를 단일 진실 공급원으로 둡니다. 빌드/의존성/타깃 정의를 모두 `Package.swift`에서 선언적으로 관리합니다.
- 하나의 패키지 안에서 **메뉴바 앱**과 **CLI**를 각각 별도의 `product`로 분리합니다. 단, SwiftPM의 executable product는 서명 가능한 `.app` 번들(Info.plist·리소스·아이콘 포함)을 그 자체로 생성하지 못하므로, 메뉴바 앱은 **SwiftPM 빌드 산출물을 패키징 스크립트(또는 `xcodebuild`)로 `.app` 번들로 조립**한 뒤 서명·노터라이즈합니다. CLI는 단일 실행 파일이라 추가 조립이 필요 없습니다.
- 공유 로직은 **UpdateBarCore** 라이브러리로 추출합니다. 도메인 모델, 버전 추적 로직, 인증을 앱과 CLI가 공통으로 사용합니다. 단, 자격증명 저장은 플랫폼 의존이므로 **`CredentialStore` 프로토콜로 추상화**합니다 — macOS(`canImport(Security)`)는 Keychain 구현, Linux는 파일/환경변수 fallback. Keychain·Sparkle 등 macOS 전용 의존을 Core에 하드코딩하면 §5에서 약속한 코어 CLI의 크로스플랫폼(Linux formula 배포)이 깨지므로, 이들은 `#if os(macOS)`로 격리하고 Sparkle은 앱 타깃에만 둡니다.

RepoBar의 언어 비율(Swift 95% / Shell 3% / TypeScript 1.5%)이 보여주듯, 이것은 **순수 네이티브 Swift 앱**입니다. Node/pnpm은 어디까지나 **태스크 러너**로만 쓰입니다. 즉 `package.json`의 scripts가 `swiftformat`, `swiftlint`, `build`, `test`, `codesign` 등의 워크플로를 감싸는 진입점일 뿐이며, **JavaScript는 앱 번들에 일절 포함되지 않습니다.**

### 15.2 Homebrew 배포

커스텀 탭 `youruser/homebrew-tap`을 운영합니다.

- **앱(macOS)**: cask로 배포 — `brew install --cask youruser/tap/updatebar`
- **CLI(Linux 등)**: formula로 배포

cask 설치 시 **앱과 CLI가 동시에 설치**됩니다. cask의 `binary` 스탠자가 `.app` 번들 내부에 동봉된 CLI 실행 파일을 `/opt/homebrew/bin`에 심볼릭 링크로 노출시키기 때문입니다. (실측: CodexBar는 번들 내 `CodexBarCLI`를 `/opt/homebrew/bin/codexbar`로 링크합니다.) UpdateBar도 동일하게 `updatebar` 명령을 PATH에 노출합니다.

### 15.3 자동 업데이트 & 서명

- **Sparkle** 프레임워크로 인앱 자동 업데이트를 제공합니다. `appcast.xml` 피드를 통해 신규 버전을 게시합니다.
- 버전은 `version.env`를 **단일 출처(single source of truth)**로 두고, 앱/CLI/appcast가 이를 공유합니다.
- 빌드 산출물은 **GitHub Releases**가 호스팅하며, appcast가 해당 릴리스 자산을 가리킵니다.
- **코드 서명 + 노터라이즈는 필수**입니다. `codesign` 스크립트 + entitlements 파일 + GitHub Actions 파이프라인으로 서명·노터라이즈·스테이플링을 자동화합니다. 서명되지 않은 빌드는 Gatekeeper에 막혀 배포가 불가능합니다.

### 15.4 랜딩

제품 소개 및 다운로드 안내는 `updatebar.app` 정적 사이트로 제공합니다.

## 16. 비용

- **Apple Developer Program 연 $99.** 이 비용은 **계정 단위**이므로, 동일 계정으로 서명·배포할 수 있는 앱 개수에는 제한이 없습니다.
- 매년 갱신이 필요합니다.
- **해지 시에도 이미 서명·노터라이즈된 빌드는 계속 동작합니다.** Developer ID 인증서는 생성일로부터 5년간 유효하고, 서명 시점에 secure timestamp가 함께 기록되기 때문에 인증서 만료·계정 해지 이후에도 기존 산출물의 신뢰는 유지됩니다.
- 단, **해지 후에는 새 빌드나 업데이트를 서명·노터라이즈할 수 없습니다.** 즉 배포를 지속하려면 멤버십 유지가 사실상 필수입니다.

## 17. macOS 실행 / 권한 제약

메뉴바 앱이 CLI를 **서브프로세스로 실행**하려면, 앱이 **비샌드박스(non-sandboxed)**여야 합니다. 이는 곧 **Developer ID 직접 배포(= Homebrew 경로)**를 의미하며, **Mac App Store 경로는 불가**합니다. 샌드박스 환경에서는 `git`, `codex`, `claude`, `ollama` 같은 임의 외부 바이너리 실행이 원천적으로 차단되기 때문입니다.

### 17.1 현실의 함정 세 가지

1. **GUI PATH 문제** — Finder/Dock에서 띄운 앱은 셸 PATH를 상속받지 않습니다. 외부 도구를 호출할 때는 **절대 경로**를 쓰거나, 로그인 셸(`/bin/zsh -lc`)을 통해 호출해야 사용자의 PATH가 반영됩니다.
2. **파일 접근 TCC 프롬프트** — 보호된 위치(문서, 데스크톱 등)를 읽으려 하면 macOS가 "파일 및 폴더" 접근 허용을 사용자에게 요구합니다. 권한 요청 시점과 UX를 설계에 반영해야 합니다.
3. **Gatekeeper / XProtect 충돌** — 남이 설치한 CLI를 건드리면 멀웨어 보호 메커니즘에 걸릴 수 있습니다. (실측: CodexBar가 사용자의 `codex` CLI를 관리하려다 macOS가 이를 *Malware Blocked* 처리하여 휴지통으로 이동시킨 사례가 있습니다.)

### 17.2 설계 권고

메뉴바 앱은 **`git`/`codex` 등 외부 도구를 직접 호출하지 않습니다.** 오직 **자기가 함께 배포한, 서명된 `updatebar` CLI 하나만** 실행합니다. PATH 해결, 외부 도구 호출, 임의 바이너리 실행 같은 "지저분한" 책임은 전부 CLI 안으로 격리합니다. 이렇게 하면 신뢰 경계가 깔끔해집니다 — 앱은 서명된 자기 자식 프로세스 하나만 신뢰하면 되고, Gatekeeper/XProtect와의 충돌 표면도 최소화됩니다.

## 18. 레퍼런스 매핑 (RepoBar → UpdateBar)

| RepoBar | UpdateBar |
|---|---|
| GitHub repo 상태 모니터링 | 등록 항목의 **버전 상태** 모니터링 |
| GraphQL/Apollo 데이터 레이어 | **latest 전략 + LLM provider** 레이어 |
| RepoBarCore | **UpdateBarCore** |
| `repobar` CLI (`--json` / `--plain`) | `updatebar` CLI (`--json`) |
| Local projects & sync (폴더 스캔 / 브랜치·싱크 상태 / fast-forward 자동 pull) | **항목 스캔 + 버전 추적 + sync 전략** |
| OAuth → Keychain | **OAuth/Key → Keychain** (provider 인증) |
| brew cask + Sparkle + `version.env` | 동일 |
| AGENTS.md | 동일 |

**결론:** RepoBar 대비 거의 *갈아끼우기(drop-in)* 수준으로 구조를 재사용할 수 있습니다. 데이터 소스(GitHub repo → 버전/패키지 소스)와 데이터 레이어(GraphQL → latest 전략 + LLM provider)만 교체하면, 패키징·배포·인증·업데이트 인프라는 그대로 가져옵니다.

## 19. 제약 & 리스크

아래는 v1 설계·운영 단계에서 직면하는 주요 제약과 리스크, 그리고 각각에 대한 완화책입니다.

| 리스크 / 제약 | 내용 | 완화책 |
|--------------|------|--------|
| **샌드박스 불가 → App Store 경로 포기** | 임의 셸 명령 실행과 사용자 도구 관리는 App Sandbox와 양립 불가하여 Mac App Store 배포가 불가능함 | 직접 배포(direct distribution)로 일원화. Developer ID 서명 + 노터라이즈 + Sparkle 자동 업데이트로 신뢰·갱신 경험 확보 |
| **LLM 등록의 자동 테스트가 임의 셸 실행** | AI가 생성한 레시피의 버전 확인·업데이트 절차를 라이브 테스트하려면 임의 명령을 실행하게 되어 안전 위험 존재 | 라이브 테스트는 **read-only 단계(`check`·`latest` 조회 + `update` dry-run)만 무인 실행**하고, 실제 쓰기를 일으키는 `update` 본 실행은 항상 사용자 확인을 거침. 레시피의 `requires_write`(기본 `true`)는 "이 업데이트가 쓰기를 수반함"을 표시하는 플래그이며, 표시된 항목일수록 실행 전 확인을 더 엄격히 적용 |
| **사용자 LLM CLI 관리 시 Gatekeeper 충돌** | UpdateBar가 관리·갱신하는 LLM CLI 바이너리가 서명/격리 속성 문제로 Gatekeeper에 막힐 수 있음 | 격리 속성(quarantine) 처리 가이드 제공, 신뢰된 출처 검증, 실패 시 명확한 진단 메시지로 안내 |
| **구독 헤드리스(claude -p) 의존 리스크** | 헤드리스 LLM 호출의 크레딧 소모·약관 변경에 따라 보조 기능이 끊길 수 있음 | 로컬(ollama) 및 OpenRouter를 헤지로 두어 프로바이더 추상화. 특정 구독에 종속되지 않게 설계 |
| **semver 없는 항목의 "최신" 판정 정확도** | commit 해시·opaque 식별자만 있는 항목은 "최신 여부" 판정이 부정확할 수 있음 | 전략별 latest 판정기를 분리(semver / commit / opaque), 불확실성은 상태에 명시. 오탐 시 사용자 재정의 허용 |
| **서명·노터라이즈 운영 비용** | Apple Developer Program 연 $99 + 빌드/노터라이즈 파이프라인 유지 비용이 상시 발생 | CI 파이프라인 자동화로 운영 부담 최소화, 릴리스 절차 문서화로 속도 보장 |
| **공유 레시피 = 임의 셸 실행(공급망)** | `import`/커뮤니티 레지스트리로 받은 manifest의 `check`/`latest.cmd`/`update.cmd`가 임의 셸. `check`는 메뉴바 폴링마다 무인 실행되어, import만으로 RCE 성립 | 가져온 레시피는 **untrusted로 격리**, 첫 실행(첫 `check` 포함) 전 cmd 단위 승인·diff. provenance/서명 도입. 상세 §22 |
| **업데이트 무결성 미검증** | `update`가 git/npm/http에서 코드를 끌어올 때 서명·해시·pin 검증이 없으면 MITM·업스트림 오염·typosquatting에 노출 | 평문 `http` 거부(`require_https_source`), 레시피별 선택적 해시/서명 pin, 실행 전 검증. §22 |
| **레시피 cmd의 시크릿 접근** | 레시피 명령이 사용자 권한으로 돌아 Keychain·env의 provider OAuth/OpenRouter 토큰을 읽거나 유출 가능 | 자식 프로세스 env에서 provider 시크릿 스크럽, 선언된 소스 외 네트워크 차단, 토큰 포함 가능 cmd/출력 로깅 금지. §22 |

## 20. 오픈 퀘스천 (PRD에서 답해야 할 결정 사항)

본 PRD가 확정해야 할 미결 질문은 다음과 같습니다.

1. **v1 스코프**: CLI만 우선 출시할 것인가, 메뉴바를 동시에 낼 것인가? (제안: CLI 코어 마일스톤 1~3을 먼저 완성하고, 메뉴바는 그 뒤에 얹는다.)
=> 우선 CLI만 구현, 하지만 바로 이후에 메뉴바도 구현할거기때문에 고려해서 구현해야함. 
2. **기본 LLM provider**: ollama를 기본값으로 강제할 것인가, 첫 실행 시 사용자가 선택하게 할 것인가?
=> 우선 OpenRouter API키 쓰는걸로 우선 출시, 하지만 OAuth로 Codex나 Claude쓰는것도 고려. 이는 OpenClaw/Hermes/OpenCode 참고해서 Oauth쓰도록. 하지만 처음버전은 OpenRouter사용함녀 좋을듯 그래도 나중에 쉽게 프로바이더 바꾸게 구조를 짜야함.
3. **레시피 공유**: export/import를 넘어 커뮤니티 레지스트리(공유 마켓플레이스)까지 로드맵에 둘 것인가? *(전제: §22의 레시피 신뢰/서명 모델이 선행되어야 함 — 신뢰 모델 없이 공유 레시피를 늘리면 공급망 공격 표면만 커짐.)*
=> OpenSource임 github을 통해서 공유할듯 landing page와 
4. **자동 업데이트 정책**: 알림만 줄 것인가, 자동 적용까지 할 것인가? (예: fast-forward류 안전한 갱신만 자동.)
=> 메뉴바에서 Update 가능하면 Update ready 띄워주면 될듯. 누르면 업데이트 후 restart 
5. **지원 카테고리 프리셋**: skill/mcp/plugin/brew/npm/git 등의 내장 템플릿을 기본 제공할 것인가?
=> 나중에 LandingPage나 Guide page에서 템플릿 제공할 예정 지금은 안함. 
6. **멀티머신 동기화**: manifest를 git/클라우드로 동기화하는 기능을 v1에 포함할 것인가?
=> 멀티머신 동기화 없음. import/export로 우선 사용
7. **텔레메트리/프라이버시**: 아무것도 전송하지 않는 것을 기본값으로 할 것인가?
=> 텔레메트리 없음. 

## 21. 빌드 마일스톤 (로드맵)

핵심 원칙: **마일스톤 1~3만으로도 LLM 없이 동작하는, 쓸모 있는 버전 추적기가 완성**됩니다. 코어가 LLM에 독립적이라는 점이 본 로드맵의 핵심이며, LLM은 어디까지나 등록·진단을 돕는 부가 레이어입니다.

1. **manifest/state 스키마 + 검증** — 산출물: 레지스트리/상태 스키마(JSON Schema draft 2020-12)와 **Swift로 구현된 검증기**(UpdateBarCore 내). 완료 기준: 유효/무효 manifest를 스키마로 정확히 판별. (주의: `ajv` 같은 JS 검증기는 §15.1의 "앱 번들에 JS 미포함" 원칙과 충돌하므로 채택하지 않음. 프로토타이핑 단계에서만 임시로 쓸 수 있음.)
2. **결정론적 코어** — 산출물: latest 판정 전략들(semver/commit/opaque) + `check`·`list`·`status --json`. 완료 기준: LLM 없이 outdated 여부를 결정론적으로 산출, JSON 출력 안정화.
3. **update / pin / sync** — 산출물: 항목 업데이트, 버전 고정, 여러 위치 정합 명령. 완료 기준: 등록 → 추적 → 최신화 루프가 CLI만으로 완결.
4. **Provider 인터페이스 + ollama → `add`** — 산출물: LLM 프로바이더 추상화와 ollama 연동, 스키마를 강제하는 등록 루프. 완료 기준: AI 보조로 생성된 레시피가 스키마 검증을 통과.
5. **codex / claude provider** — 산출물: 추가 프로바이더 연동. 완료 기준: 동일 인터페이스로 멀티 프로바이더 전환 가능.
6. **Swift 메뉴바 ↔ status 스키마 연결** — 산출물: SwiftPM 2-product 구조로 core를 공유하는 메뉴바 앱. 완료 기준: "업데이트 N개" 배지와 원클릭 실행이 status 스키마에 연동.
7. **diff / doctor (LLM 부가)** — 산출물: 변경 비교 및 진단·복구 명령. 완료 기준: 깨진 업데이트를 진단하고 복구 경로를 제시.
8. **배포 파이프라인** — 산출물: brew tap(cask + formula), Sparkle/appcast, 서명·노터라이즈, 랜딩 페이지. 완료 기준: 서명·노터라이즈된 빌드가 자동 채널로 배포·갱신.

> **순서 주의**: §22의 레시피 신뢰/샌드박스 모델은 마일스톤 4(`add`, 첫 무인 실행 도입)와 `import` 노출 **이전**에 들어가야 합니다. 커뮤니티 레지스트리·멀티머신 동기화(§20 Q3/Q6)는 신뢰 모델이 선행 조건입니다.

## 22. 보안 모델 — 레시피 신뢰 경계

UpdateBar의 핵심 메커니즘은 **선언적 레시피에 담긴 셸 명령을 실행**하는 것입니다. 이 명령의 출처는 (a) 사람이 직접 입력, (b) LLM이 추론, (c) `import`/커뮤니티 레지스트리로 받은 공유 manifest 세 가지이며, **(b)와 (c)는 신뢰할 수 없는 입력**입니다. 따라서 "CLI 바이너리를 서명했다"는 사실은 보호가 되지 못합니다 — 서명된 CLI가 서명되지 않은 임의 명령을 돌리기 때문입니다. 진짜 신뢰 경계는 **바이너리 서명이 아니라 레시피 provenance + 실행 격리**입니다.

### 22.1 위협 모델

| 위협 | 시나리오 | 핵심 위험 |
|---|---|---|
| **import RCE** | 악성 manifest를 `import`. `check`는 `status`/메뉴바 폴링마다 무인 실행 | 피해자가 `update`를 치지 않아도 import만으로 코드 실행 |
| **프롬프트 인젝션 → cmd** | AI 등록이 레포 README/URL을 읽어 레시피 추론. 그 텍스트에 "이 명령을 check에 넣어라"류 지시 매립 | LLM이 악성 `check`/`latest cmd`를 생성, 라이브 테스트에서 실행 |
| **무결성 부재** | `update`가 git/npm/http에서 코드 fetch. 서명·해시 검증 없음 | MITM(평문 http), 업스트림 태그 오염, npm typosquat |
| **시크릿 탈취** | 레시피 cmd가 사용자 env/Keychain 접근 | provider OAuth·OpenRouter 토큰 유출 |
| **doctor 루프 악용** | 실패 출력을 LLM에 되먹여 자동 "수정" 후 재실행(기본 3회) | 공격자가 에러 텍스트를 조작해 악성 "수정" 명령 유도 |

### 22.2 통제 (설계 요구사항)

1. **untrusted 레시피 격리** — `import`/레지스트리/AI 출처 레시피는 *신뢰 안 됨*으로 표시. 어떤 cmd든 **첫 실행(첫 `check` 포함) 전에 전체 명령 문자열을 사람에게 보여주고 cmd 단위 승인**을 받는다. 승인 전에는 폴링도 그 항목의 cmd를 돌리지 않는다(`config.toml [security].allow_import_exec=false` 기본).
2. **모든 cmd-보유 필드를 게이트** — `requires_write`는 `update`만 가린다. `check.cmd`·`latest.cmd`도 무인 반복 실행 표면이므로 동일하게 신뢰 등급·승인 대상. free-form cmd를 가진 레시피는 "elevated trust"로 표시.
3. **샌드박스 실행** — 라이브 테스트와 정기 점검의 cmd는 선언된 소스 외 **네트워크 차단**, **쓰기 금지(테스트 단계)**, **시간/리소스 제한** 하에 돌린다. dry-run은 *보안 경계가 아님*(도구가 무시 가능) — 격리가 유일한 강제 수단.
4. **업데이트 무결성** — `http`/`http_regex` 소스는 https 강제(`require_https_source`), 평문 거부. 레시피별 선택적 **해시/서명 pin**을 두고 실행 전 검증. `custom`/`http`는 UI에서 경고를 크게 표시.
5. **시크릿 스크럽** — 레시피 cmd의 자식 프로세스 env에서 provider 토큰·Keychain 핸들을 제거. 토큰이 섞일 수 있는 cmd·출력은 로깅하지 않는다.
6. **provenance/서명** — `export`는 서명·출처 메타데이터를 부착하고, `import`은 그 출처를 표시. 커뮤니티 레지스트리는 게시자 신원·서명을 전제로 한다(미충족 시 레지스트리 기능 보류).
7. **LLM 출력 = 제안일 뿐** — codex/claude/ollama 출력은 절대 자동 실행하지 않는다. 오염된 로컬 모델(임의 ollama pull 포함)·인젝션된 호스티드 모델 모두 동일하게 통제 2~3을 적용. "auto-test가 신뢰를 증명한다"는 순환 논리임을 명시(테스트 자체가 곧 실행).

### 22.3 비통제(현 단계 한계)

완전한 셸 샌드박싱은 macOS에서 비자명합니다(샌드박스 불가 앱이라 OS 샌드박스 활용도 제한적). v1은 **승인 게이트 + env 스크럽 + 네트워크/쓰기 제한 + 무결성 검증**으로 위험을 낮추되, 이를 "신뢰할 수 없는 레시피를 안전하게 자동 실행"이 아니라 "사람의 승인을 받은 명령을 통제된 환경에서 실행"으로 정직하게 한정합니다.
