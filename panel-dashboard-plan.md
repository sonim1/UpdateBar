# Manage Panel + Dashboard Plan (v0.4.0)

메뉴바 앱에 GUI 관리 패널과 대시보드를 추가한다. 두 기능 요구:

1. **스캔/항목 관리 패널** — 메뉴에서 바로 스캔하지 않고, 패널을 열어
   등록된 항목(manifest)과 스캔 후보를 카테고리별 리스트로 보고
   enable/disable 및 등록을 관리한다.
2. **대시보드** — 업데이트 시점 이력과 대기중 개수를 차트/타일로 요약.
   상세는 1의 리스트에서 확인한다.

## 현황 (이미 있는 것)

- `manifest.json` 항목에 `enabled: Bool`, `category: String` 필드 존재
  (docs/manifest.md).
- CLI `updatebar enable <id>` / `disable <id>` 구현됨 (docs/cli.md).
- `updatebar scan --json`이 카테고리/confidence/capability 포함 후보 출력.
- 메뉴바 앱은 core 직접 어댑터 + CLI 서브프로세스 폴백(`MenuBarServicing`)
  구조. 뷰모델은 `UpdateBarMenuBar`(pure), 셸은 `UpdateBarMenuBarApp`.

## 없는 것 (만들어야 하는 것)

- **업데이트 이력 저장소** — `state.json`은 `last_checked`만 기록.
  "언제 업데이트했는지" 시계열 데이터가 없어 차트 불가.
- GUI 창 자체 (현재 앱은 NSMenu만 있음).

## 아키텍처 결정

- **SwiftUI 창**을 AppKit delegate에서 `NSHostingView`로 호스팅.
  macOS 13+(LSMinimumSystemVersion) 타겟이므로 **Swift Charts** 사용,
  외부 의존성 없음.
- accessory 앱(LSUIElement)에서 창 표시 시 `NSApp.activate` 처리 필요.
- 뷰모델/상태 타입은 `UpdateBarMenuBar` 타겟에 순수 타입으로 두고
  유닛 테스트. SwiftUI 뷰는 얇게.
- 데이터 접근은 `MenuBarServicing` 프로토콜 확장으로 통일
  (core/CLI 어댑터 모두 구현).
- CLI가 원천(오픈소스/에이전트 철학): 이력도 `updatebar history --json`
  으로 먼저 노출하고 GUI는 소비자로.

## M1 — 패널 셸 + 등록 항목 관리

- 메뉴에 `Manage Items...` 추가. 기존 `Scan & Add` 메뉴 항목은 패널로 흡수.
- 창 구성: 사이드/탭 = Overview | Items | Scan. M1에서는 Items만.
- Items 탭: 카테고리 그룹 리스트. 행 = 이름, 현재/최신 버전, 상태 뱃지
  (outdated/ok/untrusted/error), enable/disable 토글.
- `MenuBarServicing` 확장: `listItems()`(manifest+status 조인),
  `setEnabled(id:enabled:)`. core 어댑터는 `RegistryService` 직접,
  CLI 어댑터는 `enable`/`disable` 서브커맨드 호출.
- 토글 후 상태 리프레시 + 메뉴 뱃지 갱신.
- 테스트: 뷰모델(그룹핑/정렬/토글 상태 전이) 유닛, 어댑터 계약 테스트.

## M2 — Scan 탭

- 패널 안에서만 스캔 실행 (버튼) — 메뉴에서 즉시 실행하지 않음.
- 후보 리스트: 카테고리 그룹, confidence/capability 표시,
  이미 등록된 항목은 구분 표시.
- 체크박스 선택 → 등록. 기존 scan-init 선택/등록 로직 재사용.
- 신규 등록은 기존 보안 경계 유지: trust는 기본 미승인
  (`trust.approved_commands` 비움), 승인은 기존 approvals 플로우.
- 테스트: 후보 뷰모델 매핑, 등록 시 manifest 반영 e2e.

## M3 — 히스토리 저장소

- `~/.updatebar/history.jsonl` 신설. 이벤트 스키마(v1):
  `{"schema_version":1,"event":"update_finished","id":...,"from":...,
  "to":...,"outcome":"updated|failed","at":ISO8601}` +
  `check_finished` 요약 이벤트(outdated 수).
- 기록 지점: core `UpdateRunner` 완료 훅, check 요약 지점.
- 회전: 파일 크기 캡(예: 512KB) 초과 시 앞부분 절단 (로그 회전과 동일 패턴).
- CLI `updatebar history [--json] [--since <date>]` 추가.
- 테스트: HistoryStore append/회전/파싱, CLI 출력 계약,
  update 실행 시 이벤트 적재 e2e.

## M4 — Overview 탭 (대시보드)

- 통계 타일: 대기중 업데이트 수, 승인 대기 수, 마지막 체크/업데이트 시각.
- Swift Charts 바 차트: 최근 4주 일별(또는 주별) 업데이트 횟수
  (history.jsonl 집계).
- 타일 클릭 → Items 탭 해당 필터로 이동.
- 테스트: 집계 로직(버킷팅) 유닛 테스트. 차트 뷰는 스냅샷 없이 얇게 유지.

## M5 — 마무리 / 릴리스

- menubar smoke 테스트에 패널 오픈 경로 추가.
- docs/menu-bar.md, docs/cli.md(history), CHANGELOG 갱신.
- v0.4.0 릴리스 (CLI에 history 추가되므로 minor bump).
  릴리스 후 tap SHA 갱신은 기존 절차.

## 리스크 / 주의

- accessory 앱 창 활성화(포커스) 처리 — `NSApp.activate(ignoringOtherApps:)`.
- history 스키마는 v1부터 `schema_version` 포함해 마이그레이션 여지 확보.
- 패널과 TUI 기능 중복은 의도: TUI는 터미널 사용자용, 패널은 GUI 사용자용.
- 스캔/등록은 패널에서도 절대 자동 승인하지 않는다 (보안 경계 불변).
