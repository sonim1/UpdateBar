# UpdateBar — 실서비스 배포 전 남은 작업

작성일: 2026-07-08. 기준 커밋: `4642649` (main).
7개 영역 병렬 감사(릴리스 엔지니어링 / 서명·배포 / 제품 완성도 / 테스트·품질 / 보안 / 문서·UX / 앱·TUI 폴리시) 결과를 종합한 문서.

## 현재 상태 요약

v0.2.0은 이미 공개 배포됨 (GitHub Release + Homebrew formula `sonim1/tap/updatebar` + unsigned app cask). 제품 자체는 next-plan.md 기준 M0–M4 전부 구현·검증 완료. 코드 품질, 테스트 커버리지, 보안 문서의 정직성은 모두 양호.

**그러나 지금 상태로는 다음 릴리스(v0.3.0)를 태그해도 릴리스 파이프라인이 통과할 수 없고**, 배포된 Linux 바이너리는 Swift 툴체인 없는 머신에서 실행이 안 되며, unsigned 앱의 첫 실행 안내(Control-click Open)는 macOS 15+에서 더 이상 동작하지 않음. 실서비스 관점의 남은 일은 기능 개발이 아니라 **배포 파이프라인 수리 → 서명/공증 → 배포 운영 자동화 → 신뢰 체계** 순서의 작업임.

| 영역 | 상태 | 핵심 이슈 |
|---|---|---|
| 제품 기능 (CLI/코어) | ✅ 완료 | 문서-코드 일치, 팬텀 커맨드 없음 |
| 테스트/CI | ✅ 강함 | 릴리스 워크플로만 테스트 미연동 |
| 보안 모델 | ✅ 정직함 | 공급망 증명(provenance)·제보 채널만 부재 |
| 릴리스 파이프라인 | 🔴 막힘 | 다음 태그가 통과 불가능한 구조 (P0 ×2) |
| 앱 배포 (서명) | 🔴 미해결 | unsigned + macOS 15+ 실행 불가 안내 |
| 문서/UX 마무리 | 🟡 보통 | 업그레이드/언인스톨 문서, 스크린샷, 루트 정리 |

---

## 0. 먼저 결정할 것 (작업 아님, 의사결정)

| ID | 결정 | 영향 |
|---|---|---|
| **Q-APPLE-1** | Apple Developer Program ($99/yr) 결제 여부 | 서명/공증 앱 배포 전체가 이 결정에 걸려 있음. **실서비스 앱을 표방하면 사실상 필수** — macOS 15+에서 unsigned 앱은 Control-click 우회가 제거되어 System Settings 딥다이브 없이는 실행 불가 |
| **Q-ARCH-1** | Intel Mac(x86_64) 지원 여부 | 현재 formula/cask 모두 arm64 하드게이트, 문서에 명시 없음. universal binary를 빌드하거나 "Apple Silicon 전용"을 공식 결정으로 기록하고 문서화 |

---

## 1. P0 — 릴리스 블로커 (이거 안 하면 다음 배포 자체가 불가능)

### 1.1 릴리스 파이프라인 교착 해제 — 노력 M
`release.yml:53-55`의 strict Homebrew 메타데이터 검증이 태그 시점에 cask SHA 일치를 요구하는데, 앱 아카이브는 빌드할 때마다 SHA가 달라짐(`build-app-archive.sh:27`이 mtime/owner 정규화 없는 plain tar — 동일 번들로 2회 빌드 시 SHA 상이함을 실증 확인). 태그 전에 커밋해야 하는 SHA를 알 방법이 없어 **어떤 SHA를 넣어도 v0.3.0 태그가 실패하는 구조**. 이 검증은 v0.2.0 이후(커밋 `4642649`)에 추가되어 실제 릴리스를 한 번도 통과해 본 적 없음.

해결 방향(택1):
- `build-app-archive.sh`/`package-app.sh`에 `build-release.sh:48-56`과 동일한 mtime/owner 정규화 적용해 바이트 재현 가능하게 만들기
- 또는 SHA 동등성 검사를 태그 시점 strict 검증에서 빼고 배포 후(post-publish) 단계로 이동, 태그 시점엔 version/URL 검사만 유지

### 1.2 Linux 바이너리 정적 링크 — 노력 S
공개된 `updatebar-0.2.0-linux-x86_64.tar.gz`의 ELF를 확인한 결과 `libswiftCore.so`, `libFoundation.so` 등을 동적 링크 — **Swift 툴체인 없는 일반 Linux에서 실행 불가**. 스모크 테스트는 툴체인 있는 빌드 머신에서 돌아서 통과했을 뿐. `Scripts/build-release.sh:26-28` Linux 레인에 `--static-swift-stdlib` 추가.

### 1.3 macOS 15+ 첫 실행 안내 수정 — 노력 S
README.md:20-21, docs/install.md, cask caveats 모두 "Control-click → Open" 안내인데 macOS Sequoia(15)부터 이 우회가 제거됨. 서명 전까지의 임시 조치로 System Settings → Privacy & Security → Open Anyway 절차로 교체하고, 필요시 `--no-quarantine` 옵션 언급. (근본 해결은 1.4)

### 1.4 서명/공증 파이프라인 완성 (Q-APPLE-1 = go 시) — 노력 L
`Scripts/package-app.sh`의 서명 경로는 구현되어 있으나 **mock codesign/xcrun 스텁으로만 테스트됨** — 실제 Developer ID 인증서로 end-to-end 실행 이력 없음. release.yml에는 서명 배선이 전무(secrets 참조 0건). 남은 일:
- 인증서 발급 → .p12를 CI secrets로, temp keychain import 단계 추가
- `xcrun notarytool store-credentials`용 App Store Connect API key secrets 구성
- macOS 릴리스 잡에 `UPDATEBAR_SIGN_APP=1` / `UPDATEBAR_NOTARIZE_APP=1` + identity/profile env 배선
- 서명 후 실검증 추가: `codesign --verify --strict`, `spctl --assess`, `xcrun stapler validate` (현재 grep 결과 0건 — 첫 실전 실행이 릴리스 당일이 되는 구조)
- cask를 서명 아티팩트로 갱신, Gatekeeper 안내문 제거
- docs/release.md에 secrets 이름/인증서 갱신 등 운영 절차 문서화

---

## 2. P1 — 실서비스 배포 전 강력 권장

### 릴리스 운영
| 작업 | 노력 | 근거 |
|---|---|---|
| v0.3.0 릴리스 컷: version.env 범프, CHANGELOG Unreleased → 0.3.0 롤오버, 태그, tap SHA 갱신 | M | main에 배포 안 된 수정들 + 동작 변경(hidden add 위저드 제거)이 쌓여 있음. P0 1.1/1.2 해결 후 진행 |
| Homebrew tap 동기화 자동화 (release.yml에서 tap repo로 PR/push, 업로드된 `.sha256` 기반) | M | 현재 두 파일 수동 복사 + SHA 손타이핑. 오타 하나로 모든 사용자의 `brew install` 파손 |
| GitHub 릴리스 노트 자동 첨부 (CHANGELOG 섹션 → `body_path` 또는 `generate_release_notes`) | S | `gh release view v0.2.0` body가 빈 문자열. 공개 서비스에서 릴리스 설명 공란은 방치된 프로젝트로 보임 |
| CHANGELOG 롤오버 강제: 태그 빌드 시 `## <버전>` 섹션 없으면 실패 | S | 지금 상태 그대로 태그하면 "변경사항 없음" 릴리스가 나감 |
| 릴리스 전 테스트 게이트: release.yml에서 `swift test`(또는 CI 성공 요구) 후 publish | S | 현재 태그 push는 테스트 실패 커밋도 그대로 공개 배포함 |
| 배포 후 검증: 라이브 릴리스 대상 `install-release.sh` + `brew install` 실행 잡 | M | 현재 모든 검사가 업로드 전 로컬 아티팩트 대상. 사용자가 실제 받는 자산은 아무도 검증 안 함 |
| 롤백/yank 절차 문서화 (릴리스 삭제, tap 되돌리기, fix-forward 기준) | S | `install-release.sh`가 latest 기본값이라 불량 릴리스가 즉시 전체 사용자에게 노출. rollback/yank 문서 0건 |
| release.yml에 `workflow_dispatch` 드라이런 모드 (publish 없이 전체 빌드/검증 + SHA 출력) | S | 최근 릴리스 런 5회 중 4회 실패 — 태그 삭제/재푸시 반복 중. 리허설 수단 필요 |

### 신뢰/보안 체계
| 작업 | 노력 | 근거 |
|---|---|---|
| 빌드 증명 추가 (`actions/attest-build-provenance` 또는 cosign) | M | 현재 `.sha256`이 아티팩트와 같은 릴리스에서 서빙됨 — 전송 무결성만 보장, 출처 진위는 보장 못 함. 명령 실행 도구라 공급망 신뢰가 특히 중요 |
| `.github/SECURITY.md` 취약점 제보 채널 개설 (GitHub private reporting 활성화) | S | 위협 모델 문서는 있는데 제보 경로가 없음 → 취약점이 공개 이슈로 올라오는 구조 |
| 의존성 취약점 상시 감시: `.github/dependabot.yml` (npm/tui, github-actions, swift) | S | CI가 `npm ci --no-audit`. 오늘은 0건이지만 이후 ink/react 어드바이저리를 아무도 못 봄 |

### 사용자 대면 마무리
| 작업 | 노력 | 근거 |
|---|---|---|
| 업그레이드 문서: `brew upgrade`, cask 업그레이드, curl 재실행 + "앱 자체 업데이트 없음(cask 경유가 설계)" 명시 | S | 업데이트 추적 도구인데 자기 자신의 업데이트 방법이 문서에 없음 |
| Apple Silicon 전용 범위 명시 (install.md의 `ARCH=arm64` 하드코딩 구간 포함) | S | Intel 사용자가 404로 한계를 발견하는 구조 |
| 제품 언인스톨 문서 (formula/cask 제거 + `UPDATEBAR_HOME` 데이터 위치/정리) | S | `background uninstall`만 있고 제품 제거 문서 없음 |
| README에 스크린샷/데모 GIF (메뉴바 앱 + TUI) | S | 시각 자료 0개. 메뉴바 앱 제품의 얼굴이 텍스트뿐 |
| 앱 아이콘 제작·번들 포함 | M | `.icns` 없음, `package-app.sh`에 아이콘 배선 없음 — 기본 아이콘으로 실서비스 불가 |
| `.github` 커뮤니티 파일: 이슈 템플릿, CONTRIBUTING.md | S | `.github/`에 workflows만 존재 |

---

## 3. P2 — 배포 후 진행해도 되는 것

**릴리스 파이프라인 개선**
- macOS x86_64/universal + Linux arm64 아티팩트 추가 여부 결정 (Q-ARCH-1 후속)
- Linux 릴리스 빌드를 CI와 동일한 `swift:6.0` 컨테이너에서 (현재 테스트 환경과 배포 빌드 환경 불일치, glibc 하한도 불필요하게 높음)
- `action-gh-release`에 `fail_on_unmatched_files: true` (+ draft 후 수동 promote 검토)
- CI에서 `brew style`/`brew audit` 실행 (현재 grep 기반 자체 검사뿐)
- shellcheck CI 필수화 (현재 없으면 조용히 스킵 — Linux 컨테이너에 미설치)

**품질**
- TUI↔CLI JSONL 계약 E2E (실제 바이너리 spawn 검증 — 현재 양쪽 다 픽스처만)
- 메뉴바 인터랙션 레벨 테스트 (현재 launch 스모크까지만)
- 커버리지 측정 (`--enable-code-coverage`, vitest coverage)
- DocumentationSnapshotTests의 XCTSkip 폴백 → 지원 셸에 대해 XCTFail

**제품 폴리시**
- TUI 배포 채널 결정: npm 퍼블리시/formula 리소스/번들 중 택1, 아니면 "소스 체크아웃 전용"으로 문구 다운그레이드 (현재 `private: true` 미발행인데 README·메뉴바가 광고 중)
- 메뉴바 launch-at-login (SMAppService — 현재 없음. 업데이트 추적기가 재부팅 후 안 뜸)
- 백그라운드 체크가 outdated 발견 시 사용자 알림 (현재 UNUserNotification 사용 0건 — 메뉴바 안 보면 모름)
- `StoreError.corruptFile` 에러 메시지에 `updatebar doctor`/troubleshooting 포인터 추가
- `status --refresh`, `--exit-zero-on-outdated` docs/cli.md 문서화 (hidden인데 계약상 표면)
- 에이전트 JSON 계약에 버전 명시 (next-plan M1이 "frozen and versioned" 약속했으나 버전 표기 없음)
- llms.txt를 릴리스 아카이브/자산에 실제 포함 (next-plan은 Done 표기지만 실제로는 미포함)
- schema_version 호환성 계약 1문단 문서화 (구 바이너리가 신 스키마 만났을 때 동작; state.json은 현재 schemaVersion 미검증)

**저장소 위생**
- PRD.md에 supersede 표기 (add --ai, sync, Sparkle 필수 등 제거된 설계가 그대로 남아 신규 기여자/에이전트 오도)
- 루트 플래닝 문서 정리 (PRD.md, plan.md, current-plan.md, next-plan.md, plan-required.md, current-architecture.md → docs/ 이동 또는 아카이브)
- 스테일 브랜치 삭제 (codex/* 3개는 main과 patch-equivalent, work/updatebar-cli는 224파일 뒤처짐) + 빈 `Sources/UpdateBarCore/Auth`, `Providers` 디렉터리 제거

---

## 4. 권장 실행 순서

```text
R1  파이프라인 수리 (P0 1.1 + 1.2 + 1.3)                     ~수일
     └─ release.yml 드라이런으로 리허설
R2  v0.3.0 릴리스 컷 (쌓인 Unreleased 배포)
     └─ 릴리스 노트/CHANGELOG 게이트/테스트 게이트 이때 같이
R3  Q-APPLE-1 결정 → go면 서명/공증 파이프라인 (P0 1.4)        ~1-2주
     └─ v0.4.0 = 서명·공증·스테이플 앱 릴리스 (실서비스 선언 시점)
R4  운영 자동화 + 신뢰 체계 (tap 자동화, 배포 후 검증, 롤백 문서,
     provenance, SECURITY.md, dependabot)
R5  사용자 대면 마무리 (아이콘, 스크린샷, 업그레이드/언인스톨 문서)
이후 P2 백로그 소화
```

실서비스 배포의 정의를 "일반 사용자가 brew로 설치하고, 앱이 경고 없이 실행되고, 문제 생기면 제보 경로가 있고, 불량 릴리스를 되돌릴 수 있는 상태"로 잡으면 **R1–R4 완료가 그 라인**임.

---

## 부록: 감사 방법과 한계

- 감사 5개 영역(릴리스 엔지니어링, 서명·배포, 제품 완성도, 테스트, 보안)은 에이전트가 코드/워크플로/라이브 릴리스 자산까지 직접 확인 (Linux 바이너리 ELF 파싱, 앱 아카이브 2회 빌드 SHA 비교, `gh release view` 실측 포함).
- 문서·UX / 앱·TUI 영역은 세션 한도로 에이전트 감사가 중단되어 메인 스레드에서 직접 점검한 결과로 대체 (아이콘/알림/launch-at-login/커뮤니티 파일/스크린샷/언인스톨 문서 부재는 grep·find로 확인).
- 교차 검증(adversarial verify) 단계도 같은 이유로 대부분 미실행 — 각 항목은 감사자가 제시한 file:line 증거 기반이며, 착수 전 해당 증거 위치를 한 번 확인하고 진행할 것.
