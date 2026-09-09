# UpdateBar 메뉴바 UX 검토 화면 디자인

범위: 이번 폴더의 로컬 HTML 계획/프로토타입. 운영 앱의 전역 디자인 시스템을 변경하지 않는다. 기존 AppKit/SwiftUI의 system font, 시스템 라벨 계층, 4/8/12/20 간격, 8/10 모서리, native controls를 출발점으로 한 개선 제안이다. 독립적인 브랜드/랜딩 페이지를 새로 만드는 작업이 아니다.

## 1. Atmosphere & Identity

‘열고, 확인하고, 다시 하던 일로.’ 차분한 macOS 유틸리티. 계획 문서는 여백과 선으로 구조를 드러내고, 실제 팝오버는 작은 공간의 정보 밀도를 우선한다. 시각적 중심은 살아 있는 메뉴바 미리보기 하나다. 장식용 이미지·차트·움직임은 쓰지 않는다. 사용자는 자주 도구를 업데이트하는 개발자, 가끔 승인 요청을 만나는 사용자, 키보드로 조작하는 사용자로 가정한다.

## 2. Color

| 역할 | CSS 토큰 | 값 |
| --- | --- | --- |
| 문서 배경 | --paper | #f8f9fb |
| 기본 표면 | --surface | #ffffff |
| 부드러운 표면 | --surface-soft | #f0f2f5 |
| 주요 텍스트 | --ink | #202731 |
| 보조 텍스트 | --muted | #626d7b |
| 약한 텍스트 | --faint | #63707e |
| 구분선 | --line | #dfe4ea |
| 동작 | --accent | #2864d9 |
| 동작 hover | --accent-hover | #1e51b7 |
| 동작 배경 | --accent-soft | #eaf1ff |
| 성공 | --success / --success-soft | #28734f / #eaf4ee |
| 검토 필요 | --warning / --warning-soft | #906013 / #fff5e2 |
| 오류 | --danger / --danger-soft | #b63b3b / #fff0ee |
| 데스크톱 재료 | --desk / --desk-deep | #e1e8ef / #cbd7e4 |
| 어두운 모드(미리보기만) | --surface / --surface-soft / --ink / --muted / --faint / --line | #252a32 / #303741 / #f4f6fa / #b5becc / #a2adbd / #424b59 |
| 어두운 모드 상태 | --accent / --accent-hover / --accent-soft / --success / --success-soft / --warning / --warning-soft / --danger / --danger-soft | #8db5ff / #b5ceff / #263c60 / #91d3aa / #263d32 / #e8c77e / #433a27 / #ffaaa0 / #482f31 |

샘플 도구 아이콘은 문자와 동일한 의미색으로 표현한다. 브랜드 로고를 임의로 재현하지 않는다. 색은 상태 라벨과 아이콘을 보조한다.

## 3. Typography

- 본문: `-apple-system, BlinkMacSystemFont, 'Apple SD Gothic Neo', 'Noto Sans KR', sans-serif`. macOS 앱을 검토하는 표면이므로 시스템 글꼴이 의도된 선택이다.
- 코드·버전: `ui-monospace, SFMono-Regular, Menlo, monospace`.
- 크기: --text-xs 11px(짧은 메타), --text-sm 12px(버전/보조), --text-md 14px(행/버튼), --text-body 15px(문서), --text-lg 18px, --text-xl 24px, --text-title 38px(좁은 화면 30px), --text-display 48px(짧은 숫자).
- 본문 행간 1.65, UI 1.4, 제목 1.3. 한국어 `word-break: keep-all`; 코드와 긴 토큰만 `overflow-wrap:anywhere`. 제목은 어절을 지킨다.

## 4. Spacing & Layout

- 4px 단위: --s1 4 / --s2 8 / --s3 12 / --s4 16 / --s5 20 / --s6 24 / --s8 32 / --s10 40 / --s12 48 / --s16 64.
- 문서 최대 폭 1200px, 좌우 여백 clamp(20px, 4vw, 56px), 2열 약 0.8:1.2. 960px 아래는 단일 열.
- 문서가 전체 세로 스크롤을 소유한다. 미리보기 팝오버는 폭 --popover-width 392px, 최대 높이 --popover-height 560px. 자체 콘텐츠 본문만 overflow:auto, 헤더와 footer는 고정.
- 미리보기 문서의 작은 뷰포트에서는 팝오버 폭 min(392px,100%)로 축소한다. macOS 네이티브 폭 pt와 HTML px는 지각 비교를 위한 설계값이며 시스템 렌더링 등가가 아니다.

## 5. Components

- `Button`: primary, secondary, text, icon. hover, pressed, focus-visible, disabled, busy. native button + 설명형 접근성 이름. 터치 최소 36px, 좁은 화면 40px.
- `ItemRow`: native checkbox + 도구 문자 아이콘 + 이름/버전 + 상세 버튼. selected, queued, running, done, failed. 기본 행 높이 64px. 실패/긴 이름에서는 높이가 늘어난다. 본문 목록에서 재사용한다.
- `StatusNote`: icon + 주요 문구 + 선택적 행동. info/warning/error/success. 상태 변경은 별도 polite live region에서 요약한다.
- `PopoverShell`: 헤더/스크롤 본문/고정 실행부/보조부. 닫기와 재열기는 상태를 유지하며 Escape는 안쪽 상세에서 뒤로, 최상위에서 닫기로 동작한다.
- `ScenarioButton`: 6가지 상태 탐색. aria-pressed, 선택 강조. 시나리오 변경은 예시 데이터를 초기화한다. 실제 UI 밖의 검토 도구다.
- `CommandReview`: 정확한 명령·작업 폴더·필드 라벨, 승인 체크박스, 명시적 승인 버튼. 승인 직후 업데이트를 자동 실행하지 않는다.
- `HandoffDialog`: 기존 Dashboard로 이동할 계획인 화면을 설명하는 프로토타입 전용 dialog. native HTML dialog로 focus trap/닫기 제공. 실제 Dashboard를 구현한 것처럼 보이지 않도록 ‘연결 설계’ 표기.
- 6개 시나리오, 상세·명령 검토·dialog가 동일한 primitive의 상태 harness 역할을 한다.

## 6. Motion

--fast 140ms / --normal 220ms, easing cubic-bezier(.2,.7,.2,1). hover 색 변화, focus, 상세 진입 opacity에만 사용. 확인/실행 spinner 1s linear는 작업 중에만 표시한다. 완료 개수 진행 막대는 즉시 갱신해 실제 비율 의미를 유지한다. `prefers-reduced-motion: reduce`에서는 회전과 transition을 없애고 상태 텍스트를 유지한다. 애니메이션을 위해 콘텐츠를 숨기지 않는다.

## 7. Depth & Surface

문서는 평면, 선과 여백으로 구획한다. 미리보기 팝오버만 실제 떠 있는 UI를 표현하는 다층 그림자 `0 24px 60px rgba(36,53,76,.16), 0 4px 12px rgba(36,53,76,.08)`와 얇은 가장자리, 16px corner를 사용한다. 버튼 8px, 행 8px, desktop frame 20px. 투명도는 읽기 쉬운 fallback surface 위에 제한적으로 사용한다.

## 8. Accessibility, Verification & Limits

- native button/input/dialog, 키보드 Tab/Space/Enter/Escape. 선택/진행/결과는 색 외에 문구로 표현. focus-visible 3px accent ring, 2px offset.
- 한글 줄바꿈, 375/768/1280px, light/dark, reduced motion, empty/error/approval/progress, 긴 문자열 검증.
- 문서와 팝오버의 한국어 본문은 잘리지 않게 하고 코드만 필요시 줄바꿈한다.
- HTML 시뮬레이션은 네이티브 메뉴바 위치, VoiceOver/AppKit 접근성, 활성화 정책, 실제 코어 실행을 검증하지 않는다. 이는 네이티브 구현 단계의 명시적 검증 항목이다.
- 실제 프로젝트 자료를 네트워크에 올리지 않는다. 외부 asset/font/runtime 없이 로컬에서 열린다.
