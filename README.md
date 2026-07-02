# negaflow-scanner-sane

**negaflow용 SANE 필름 스캐너 플러그인 (외부 프로세스, 설치형).**

<a href="README_en.md">Read in English</a>

negaflow(Apache-2.0)에서 분리된 **독립 프로그램**입니다. SANE(`scanimage`, GPL)로 필름
스캐너를 인식·제어하고, 결과를 negaflow의 JSON/CLI 계약으로 전달합니다. negaflow 본체에는
SANE 코드가 전혀 없으며, 이 플러그인과는 **별도 OS 프로세스 · CLI 인자 · 파이프 · JSON**으로만
통신합니다.

- 플러그인 저장소: <https://github.com/habinsong/negaflow-scanner-sane>
- 본체 저장소: <https://github.com/habinsong/negaflow>

## 왜 별도 프로젝트인가 (라이선스)

- Plustek OpticFilm 계열이 쓰는 SANE `genesys` 백엔드는 **링크 예외 없는 GPL-2.0-or-later**입니다.
- negaflow는 **Apache-2.0**입니다.
- 두 라이선스를 한 프로세스/한 바이너리에 결합하면 GPL 의무가 negaflow로 전파될 수 있습니다.
- 따라서 SANE 관련 코드는 전부 이 GPL 프로젝트에 두고, negaflow와는 프로세스 경계로만 통신합니다.
- 근거: FSF GPL FAQ(“mere aggregation”), SANE 라이센스 문서. 자세한 내용은 `LICENSE` 참고.

## 요구사항

- macOS 13+, Swift(SwiftPM)
- 런타임에 SANE `scanimage`:
  ```sh
  brew install sane-backends
  ```

## 빌드 & 설치

```sh
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane
./install.sh
```

이 스크립트는 릴리스 빌드 후 다음 위치에 실행파일과 `manifest.json`을 복사합니다:

```
~/Library/Application Support/negaflow/Plugins/sane/
  ├── negaflow-scanner-sane
  └── manifest.json
```

negaflow를 재시작하면 좌측 **Library → 스캐너 불러오기**에서 스캐너가 인식됩니다.

## 플러그인 프로토콜 (negaflow ↔ 플러그인)

실행파일은 서브커맨드로 호출되고 stdout에 JSON을 냅니다.

| 커맨드 | 입력 | 출력(stdout) |
| --- | --- | --- |
| `detect` | — | `{"devices":[{ id, displayName, vendor, model, connectionType, verifiedStatus, … }]}` |
| `capabilities <deviceId>` | — | `{ "resolutionsDPI":[…], "modes":[…], "bitDepths":[…], "supportsInfrared":… }` |
| `scan` | 옵션 JSON(stdin) | 진행률 NDJSON `{"type":"progress","phase":…,"fraction":…}` … 그리고 `{"type":"result","width":…,"height":…,"path":…}` |

`scan` 옵션 JSON:

```json
{ "deviceID": "sane-genesys:libusb:001:002", "resolutionDPI": 3600, "bitDepth": 16,
  "colorMode": "color", "filmType": "colorNegative", "preview": false,
  "multiExposure": false, "outputPath": "/tmp/scan.tiff" }
```

수동 확인:

```sh
swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

## 구조

```
Sources/
  SANEPluginCore/          # SANE 백엔드 + 모델 + TIFF 로더 (라이브러리, 테스트 가능)
    SANEBackend*.swift      #   scanimage 래퍼(장치 감지·capability·스캔·멀티샘플/HDR)
    SaneConfigTuner.swift
    ScannerModel.swift      #   자체 모델 타입(negaflow 미의존)
    TIFFLoader.swift
  negaflow-scanner-sane/   # JSON/CLI 프로토콜 어댑터 (얇은 실행파일)
    main.swift
    WireProtocol.swift
Tests/SANEPluginCoreTests/ # SANE 알고리즘 단위 테스트
```

## 라이선스

GPL-2.0-or-later. 배포 파일에는 `LICENSE`와 GNU GPL v2 전문인 `COPYING`을 함께 포함합니다.
