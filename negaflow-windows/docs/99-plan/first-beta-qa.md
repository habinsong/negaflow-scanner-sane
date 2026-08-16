# Windows 최초 QA·프리뷰 데모·베타 추적

기준일: 2026-08-16

이 문서는 최초 QA·프리뷰 데모·베타 테스트의 SANE 어댑터 추적 문서다. 아래 사용자 목표의 기능·품질·성능·검증 범위는 축약하거나 재해석하지 않는다. 스캐너 어댑터 단독 검사와 Negaflow 호스트 통합 검사를 구분하며, 실제 장치 증거 없이 완료로 표시하지 않는다.

## 사용자 목표

1. GrainMend 기능이 동작하지 않고 "고칠 것을 찾지 못했습니다"만 표시된다. 자동·가이드·브러시·복제 도구·IR을 모두 macOS와 동일하게 동작하게 한다. 복제 도구가 잘려 보이는 문제도 수정한다.
2. 창작한 UI/UX를 제거하고 각종 뷰의 크기·모양·모서리 라운딩·위치·정렬을 macOS와 동일하게 한다. 누락된 현상 버튼, 아예 만들지 않은 UI/UX, 백엔드에 연결되지 않은 UI를 모두 구현·연결한다. `C:\Users\habin\negaflow\negaflow_mac_screenshot`의 기준 화면을 그대로 대조한다.
3. Library에서 사진을 불러온 뒤 Develop에서 이미지와 썸네일이 보여야 하며 하단 탭 전체가 동작해야 한다. Library와 Develop을 분리된 데이터 흐름으로 두지 않는다.
4. 창작한 Develop 좌측 탭을 제거하고 macOS Develop 좌측 탭의 모든 기능과 여러 사진을 다루는 흐름을 동일하게 구현한다. Library 좌측 탭에만 있는 기능으로 축소하지 않는다.
5. 창작한 UI/UX 때문에 글자가 잘리거나 가려지는 문제를 모든 화면·상태·지원 언어에서 수정한다.
6. Develop 우측 탭의 모든 슬라이더가 실시간으로 반응하게 한다. 수초 지연을 허용하지 않으며 슬라이더 하나가 아니라 모든 실시간 편집 경로를 포함한다.
7. 자동 톤·자동 색상·자동 레벨이 모두 동작하고 실시간 사용에 적합한 속도를 내게 한다.
8. 이미지 crop·rotate·flip을 포함한 모든 이미지 편집 기능의 속도와 반응성을 개선한다.
9. Print에서 선택한 이미지가 표시되게 하고 UI/UX와 전체 기능을 macOS와 동일하게 구현한다.
10. macOS 스크린샷과 동일한 UI/UX 위치·크기·모양 및 기능을 모두 구현한다. `computer-use`로 연결된 8100과 V700 스캐너를 사용해 스캔·보정·인화·내보내기 전체 흐름을 검증한다. `C:\Users\habin\OneDrive\바탕 화면\negaflow_test`로 일반 이미지 경로를 테스트하고 `C:\Users\habin\Downloads\golden\golden`으로 IR을 테스트한다. `C:\Users\habin\negaflow\negaflow-windows`와 `C:\Users\habin\negaflow-scanner-sane` 양쪽을 모두 수정·검증한다. 스크린샷 기준은 `C:\Users\habin\negaflow\negaflow_mac_screenshot`, macOS 코드 기준은 `C:\Users\habin\negaflow\negaflow-mac`과 `C:\Users\habin\negaflow-scanner-sane\negaflow-mac`이다. 검증되지 않은 상태에서 "다했습니다" 또는 "완성했습니다"라고 주장하지 않는다.

## 추가 운영 요구

- `computer-use`를 사용한다. 각 프로젝트마다 Markdown 문서를 만들고 한 것·안 한 것·수정할 것·수정한 것·검증한 것을 모두 기록하고 계속 최신화하며, 작업을 재개할 때 먼저 읽는다. 컨텍스트 압축 뒤에도 잊지 않도록 메모리 업데이트 노트를 남긴다. 이 작업은 최초 QA이자 프리뷰 데모 베타 테스트다.
- 체크포인트 마다 커밋/푸시 하고, 그거랑 별개로 문서는 계속 작성하고 최신화해라
- 1번부터 끝까지 목표 사항 축약없이, 생략없이 목표 단위로 기록해놔라. 말 토씨하나 빼지 말고
- UI/UX를 창작하지 않는다. 아예 존재하지 않거나 동작하지 않는 요소를 모두 찾아 구현·연결하고, 각종 뷰의 크기·모양·모서리 라운딩·위치·높이·너비가 macOS와 완전히 동일하게 한다.
- 이미지 현상·보정·인화·내보내기의 품질·속도·성능을 모두 최적화한다. 특히 속도를 우선하며 슬라이더는 한 가지 예일 뿐이고 전체 이미지 처리 경로를 포함한다.
- 속도·품질·성능 최적화는 로그를 남겨 추측이나 확인되지 않은 가설 없이 검증하면서 해결한다.
- UI/UX는 `computer-use`를 사용해 Windows 실제 화면을 캡처하고 macOS 스크린샷과 비교하며, 양쪽 코드와 고정 metric도 함께 비교한다.
- 다국어 텍스트 길이 확장을 고려해 UI/UX를 구현한다. 지원 언어별 문자열이 길어져도 뒤쪽 글자가 잘리거나 가려지지 않게 하고, macOS 계약을 벗어나지 않는 범위에서 줄바꿈·가변 너비·최소 높이와 접근성 이름이 자연스럽게 동작하도록 한다. 여섯 언어(`de`, `en`, `fr`, `ja`, `ko`, `zh-Hans`)의 실제 렌더링을 각각 검증한다.
- Library·Develop·Print는 분리된 기능이 아니라 하나의 연속된 워크플로다. 현재 끊긴 이미지·썸네일·선택·filmstrip·Print 대상 전달을 모두 수정한다.
- Negaflow 본체와 `negaflow-scanner-sane` 모두 저장소에 이미 있는 setup/build-installer 경로로 최신 소스를 빌드·설치한 뒤 `computer-use` 검증을 수행한다. 설치된 오래된 실행 파일이나 임의 실행 경로를 기준으로 삼지 않는다.
- 체크포인트 커밋·푸시는 별도 작업 브랜치를 만들지 않고 각 저장소의 `main`에 직접 수행한다. 저장소에는 `main`만 유지한다.
- macOS `negaflow-mac/scripts/ci-gate.sh`처럼 각 Windows 프로젝트에 단일 로컬 CI 진입점을 둔다. 이후 수동으로 빌드 단계를 반복하지 않고 본체는 `scripts/local-ci.ps1`의 core gate→setup build→설치→package identity→실제 창 생성→제거를, SANE은 Release build→CTest→setup build→설치 payload→`detect`→제거를 각각 한 번에 통과한 산출물만 QA에 사용한다. 각 실행 로그 경로를 문서 증거에 남긴다.

## 상태 표

상태 값은 `미재현`, `재현`, `수정 중`, `수정`, `부분 검증`, `검증 완료`만 사용한다. SANE 저장소의 `검증 완료`는 어댑터와 실제 장치 범위만 뜻하며, Negaflow UI·현상·인화 완료를 대신하지 않는다.

| 목표 | 상태 | SANE 책임과 현재 확인 사실 | 수정할 것 | 수정한 것 | 검증한 것 |
| --- | --- | --- | --- | --- | --- |
| 1 | 미재현 | IR TIFF 제공과 호스트 전달이 직접 책임이며 GrainMend 적용은 본체 책임 | V700 IR 스캔→RGB/IR 격자·경로→호스트 import→결함 적용 전 구간 대조 | 없음 | 없음 |
| 2 | 미재현 | 스캐너 UI는 본체 책임, 장치·capability·진행·오류 계약은 어댑터 책임 | macOS wire 결과와 Windows 호스트 표시의 연결 검증 | 없음 | 없음 |
| 3 | 미재현 | 스캔 결과 publish 후 Library/Develop 전달은 호스트 통합 경계 | scan result·infraredPath·artifact commit 영수증을 실제 앱에서 확인 | 없음 | 없음 |
| 4 | 미재현 | Develop 좌측 탭은 본체 책임 | 스캔한 여러 프레임이 host interaction scope에 유지되는지 통합 검증 | 없음 | 없음 |
| 5 | 미재현 | UI 문자열 클리핑은 본체 책임, 장치명·오류 문자열 데이터는 어댑터 책임. 다국어 확장 시 뒤쪽 글자 잘림·가림도 금지 | 여섯 지원 언어에서 긴 장치명·오류·진행 텍스트의 전체 표시·줄바꿈·접근성 이름 확인 | 없음 | 없음 |
| 6 | 미재현 | Develop 슬라이더는 본체 책임 | 스캐너 자식 프로세스·배경 작업이 현상 preview를 방해하지 않는지 통합 계측 | 없음 | 없음 |
| 7 | 미재현 | 자동 톤·색상·레벨은 본체 책임 | 스캔 publish 후 host 자동 보정 입력이 올바른지 확인 | 없음 | 없음 |
| 8 | 미재현 | crop·rotate·flip은 본체 책임 | 스캔 원본과 recipe 분리·원본 불변성 통합 확인 | 없음 | 없음 |
| 9 | 미재현 | Print는 본체 책임 | 스캔 결과가 host Print 대상 집합까지 전달되는지 통합 확인 | 없음 | 없음 |
| 10 | 미재현 | 8100/V700 실제 스캔과 IR 산출이 직접 책임 | 두 장치 detect→capabilities→preview→full→IR→cancel/retry와 본체 전 구간 검증 | 없음 | 없음 |

호스트 UI와 연결되는 항목은 macOS에 해당 요소가 존재하는지, 같은 동작인지, 같은 위치인지, 같은 높이·너비인지, 같은 모양인지, 같은 모서리 반경인지, 문자열이 잘리거나 가리지 않는지, 장치·capability·진행·오류 백엔드가 실제로 연결됐는지, 같은 입력 상태에서 렌더한 Windows 캡처가 기준과 일치하는지를 모두 확인한다. 하나라도 없으면 완료가 아니다.

성능 검증은 scan detect·capabilities·preview·full·IR·cancel·retry의 첫 응답 지연, 전체 시간, CPU·메모리, 반복 편차를 기록한다. SANE 백그라운드 작업이 Negaflow의 이미지 표시·현상·보정·인화·내보내기 반응성을 방해하는지도 호스트 통합에서 확인한다.

성능 작업은 다음 순서를 지킨다: 고정 장치·입력·옵션과 재현 절차 확정 → 자식 프로세스 시작·첫 출력·진행·완료·취소·종료 로그와 wall time·CPU·메모리·출력 바이트 수집 → 측정으로 병목 확정 → 한 번에 한 원인만 수정 → 같은 조건으로 재측정 → TIFF 계약과 반복성 회귀 확인. 추측이나 측정되지 않은 가설만으로 코드를 바꾸지 않는다.

호스트 UI 통합은 같은 창 크기·DPI·입력·장치·탭 상태에서 `computer-use`로 Windows 실제 화면을 캡처하고 macOS 스크린샷, 양쪽 코드, 고정 metric, 클릭·키보드·오류·진행 상태를 함께 대조한다. Library·Develop·Print는 하나의 catalog, interaction scope, active frame, selected set, frame identity가 이어지는 단일 워크플로이며, 스캔 결과가 어느 단계에서든 끊기면 완료가 아니다.

## 읽은 기준

- `docs/00-overview/handoff.md`
- `docs/99-plan/roadmap.md`
- `docs/99-plan/test-plan.md`
- `docs/09-hardware/validation-matrix.md`
- `docs/10-lessons/host-pipeline-contract.md`
- `C:\Users\habin\negaflow-scanner-sane\negaflow-mac`

## 체크포인트 기록

### CP0 — 목표 고정

- 한 것: 사용자 목표의 기능·품질·성능·검증 범위와 운영 요구를 이 문서에 고정했다.
- 안 한 것: 실제 앱 재현, 코드 수정, 장치 스캔, 호스트 통합, 결과 TIFF 검증.
- 수정할 것: 장치 탐지와 현재 앱 통합 상태를 먼저 재현한다.
- 수정한 것: 이 추적 문서만 생성했다.
- 검증한 것: 목표 1~10과 추가 운영 요구가 빠짐없이 포함됐는지 문서 diff로 확인한다.

### CP1 — 최신 setup 기준 실행 준비

- 한 것: `scripts/build-installer.ps1`, `scripts/verify-installer.ps1`, NSIS setup의 설치 경로·교체 방식·설치 후 `detect` 검사를 읽었다.
- 안 한 것: 현재 작업 트리 Release build·CTest, setup 생성·설치, 8100/V700 실제 탐지·스캔.
- 수정할 것: 현재 소스로 SANE setup을 빌드·설치하고 본체 최신 setup과 함께 실제 장치·호스트 통합을 확인한다.
- 수정한 것: 최신 setup만 실제 QA 기준으로 사용한다는 운영 규칙을 이 문서에 추가했다.
- 검증한 것: setup은 `%LOCALAPPDATA%\Negaflow\Plugins\sane`을 소유하고 본체 setup과 라이선스 경계를 유지하며 설치 후 adapter `detect`를 실행하도록 작성돼 있음을 확인했다. 실제 장치 검증은 아직 하지 않았다.

### CP2 — SANE 로컬 CI

- 한 것: macOS `ci-gate.sh`와 같은 단일 Windows 진입점 `scripts/local-ci.ps1`을 만들고 Release build, CTest, setup build, 임시 설치 payload, 설치본 `detect`, 제거를 한 번에 실행했다.
- 안 한 것: 로컬 CI의 `detect` 성공은 8100/V700 실제 스캔·IR 프레임·취소·재연결·반복 스캔 성공을 의미하지 않는다.
- 수정할 것: 로컬 CI를 통과한 setup을 실제 플러그인 경로에 설치하고 두 실제 장치의 preview·scan·IR·취소·재연결을 앱 통합 상태에서 검증한다.
- 수정한 것: 개별 빌드·설치 명령 대신 실패 즉시 중단하고 전체 로그를 남기는 단일 로컬 CI를 추가했다.
- 검증한 것: `scripts/local-ci.ps1` 통과. CTest 5/5, setup 설치 payload·설치본 `detect` 종료 코드 0·제거 통과. 설치 파일 SHA-256은 `85b1928ec01a8729af4de27d09805ed2bf336deaf41680b55f9ad39f2066fe09`, 로그는 `out\logs\local-ci-20260817-000901.log`이다.

### CP3 — 실제 플러그인 경로 설치와 장치 탐지

- 한 것: 로컬 CI를 통과한 1.0.4 setup을 `%LOCALAPPDATA%\Negaflow\Plugins\sane`에 설치하고 설치된 adapter로 `detect`를 실행했다.
- 안 한 것: 실제 preview·scan·IR·취소·재연결·반복 스캔은 아직 실행하지 않았다.
- 수정할 것: 본체 최신 설치본에서 두 장치 capability와 실제 scan 전체 흐름을 검증한다.
- 수정한 것: 이전 플러그인 설치를 로컬 CI 통과 setup으로 교체했다.
- 검증한 것: 설치 adapter SHA-256 `e2a49ed244e8571e842a3efee19f9141dca28db7e056c0ec0ab01aa7aa2e0453`; `detect`가 `sane-epson2:usbscan:001` Epson GT-X900과 `sane-genesys:usbscan:000` Plustek OpticFilm 8100을 반환했다.
