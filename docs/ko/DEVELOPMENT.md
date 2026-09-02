# 개발

[문서 홈](README.md)

## negaflow 스캐너 프로토콜

실행 파일은 서브커맨드로 호출되며 표준 출력에 JSON을 기록합니다.

| 명령 | 입력 | 출력 |
|---|---|---|
| `detect` | 없음 | 장치 목록 JSON |
| `capabilities <deviceId>` | 선택적 탐지 장치 식별 JSON | 해상도, 모드, 비트 심도, 영역, 노출과 IR 기능 JSON |
| `scan` | stdin의 protocol v2 요청 JSON | NDJSON 진행 상황과 최종 결과 또는 오류 이벤트 |
| `repair-sane-config` | 없음 | 구버전 negaflow 플러그인이 꺼 둔 백엔드만 다시 활성화 |
| `tune-sane` | 없음 | `repair-sane-config` 호환 별칭 |
| `restore-sane` | 없음 | 최후 수단으로 구버전 전체 백업 복구 |

protocol v2의 모든 이벤트에는 `protocolVersion`, `requestID`와 계속 증가하는 `sequence`가
들어갑니다. 성공 결과의 `appliedOptions`는 출력 TIFF와 실제 적용값을 확인한 뒤에만 기록합니다.
negaflow는 `capabilities`가 돌려준 불투명 `capabilityToken`을 다음 스캔 요청에 자동으로
되돌려줍니다. CLI를 직접 호출할 때도 같은 값을 넣어야 하며, 생략하면 호환용 사전 검사가 더
실행됩니다.

capability는 실제로 스캔할 상태에서 읽습니다. SANE 옵션은 서로의 활성 여부를 바꾸기 때문입니다.
`epson2`는 Lineart에서 심도를, 선형 감마를 고르면 밝기를 비활성으로 내립니다. 그래서 장치 기본
상태의 덤프는 스캔 상태를 설명하지 못합니다. 투과 소스와 스캔 모드, 중립 색·감마를 적용한 상태에서
옵션을 읽고 그 상태를 토큰에 담으며, 다른 모드를 요청하면 그 모드에서 옵션을 다시 읽습니다.

본 스캔 요청 예시:

```json
{
  "protocolVersion": 2,
  "requestID": "7A91B43D-90F8-41E2-B71D-04D17CD9E03B",
  "deviceID": "sane-genesys:libusb:001:002",
  "capabilityToken": "<capabilities가 반환한 불투명 토큰>",
  "resolutionDPI": 3600,
  "bitDepth": 16,
  "colorMode": "color",
  "filmType": "colorNegative",
  "preview": false,
  "multiExposure": false,
  "infrared": false,
  "scanArea": {
    "originXMM": 0,
    "originYMM": 0,
    "widthMM": 36,
    "heightMM": 24
  },
  "outputRawTIFF": true,
  "outputPath": "/tmp/scan.tiff"
}
```

## 요청값과 실패 처리

- 요청한 DPI가 장치의 목록이나 범위에 정확히 있어야 합니다. 가까운 해상도로 바꾸지 않습니다.
- 16-bit 요청은 SANE depth가 8보다 크고 결과 파일도 실제 16-bit TIFF일 때만 성공합니다.
- mm 단위 `-x/-y` 범위가 있어야 물리 스캔 영역을 표시합니다. 위치 지정에는 `-l/-t`도 필요합니다.
- source, mode, depth, resolution, preview와 geometry를 적용한 뒤 의존 옵션을 다시 확인합니다.
- 프리뷰에 IR이나 다중 노출을 몰래 덧붙이지 않습니다.
- 밝기, 대비나 gamma를 하드웨어 다중 노출처럼 사용하지 않습니다.
- 결과가 요청과 다르거나 검증에 실패하면 해당 파일을 버리고 오류를 반환합니다.

## 저장소 구성

| 경로 | 역할 |
|---|---|
| `Sources/SANEPluginCore` | SANE 장치 찾기, 기능 해석, 스캔, TIFF 검증, IR과 노출 병합 |
| `Sources/negaflow-scanner-sane` | negaflow 스캐너 프로토콜 v2용 JSON/CLI 어댑터 |
| `Tests/SANEPluginCoreTests` | 프로토콜, 프로세스, 옵션 파서, TIFF와 가상 스캐너 회귀 테스트 |
| `Installer` | 원샷 PKG 배포 구성, 설치 스크립트와 Installer.app 화면 자료 |
| `scripts` | 유니버설 빌드, 서명, 패키징, 설치, 공증과 릴리스 확인 |

## 개발 확인

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

모델별 가상 스캐너 테스트는 실제 subprocess와 TIFF 계약으로 프리뷰, 본 스캔, 스캔 영역과 IR 경로를
확인합니다. 스캐너 모터, 광학계, USB 전송이나 최종 화질은 재현하지 않으므로 실기기 검증이 아닙니다.

## 릴리스 빌드

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
```

스크립트는 `arm64`와 `x86_64`를 빌드해 유니버설 실행 파일로 합치고, dSYM 생성, 서명, 패키징,
SHA-256 기록과 압축 파일 검증까지 수행합니다. 산출물은 `.build/release-artifacts/`에 저장됩니다.

배포 서명과 공증에는 `NEGAFLOW_CODESIGN_IDENTITY`, `NEGAFLOW_NOTARY_KEYCHAIN_PROFILE`,
`NEGAFLOW_RELEASE_MODE=distribution`이 추가로 필요합니다.

원샷 PKG와 DMG는 아래 명령으로 만듭니다.

```bash
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

이 빌드는 고정된 공식 Homebrew 패키지를 검증한 뒤 설치 구성 요소를 포함하고, Apple Silicon 전용과
유니버설 두 가지를 만든 다음 실제 설치 없이 각 PKG와 DMG 구조를 확인합니다.
`NEGAFLOW_INSTALLER_ARCHITECTURE`를 `arm64` 또는 `universal`로 지정하면 한 가지만 만들고, 기본값
`all`은 둘 다 만듭니다. `NEGAFLOW_INSTALLER_VARIANT=all`을 지정하면 일반판과 Coolscan판을 모두
만들며 기본값은 일반판입니다. 배포용 서명·공증에는 `NEGAFLOW_INSTALLER_MODE=distribution`, PKG용
`NEGAFLOW_INSTALLER_IDENTITY`, 기존 앱 서명 신원과 공증 프로필이 추가로 필요합니다.
