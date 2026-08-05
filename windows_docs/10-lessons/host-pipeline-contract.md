# 본체가 이 플러그인 출력에 거는 계약

기준일: 2026-08-04
상태: 이식 정본 — 이 계약을 깨면 색이 무너진다
목적: 플러그인이 내는 TIFF가 negaflow 현상 파이프라인에서 **무엇으로 취급되는지**
확정한다

관련 문서:

- [driver-option-reference](driver-option-reference.md) — 이 계약의 하드웨어 쪽 절반
- [field-lessons](field-lessons.md) §6 — 이 계약이 명문화된 계기
- [tiff-validation](../04-imaging/tiff-validation.md) — 산출물 검증
- [numerical-parity](../04-imaging/numerical-parity.md) — 픽셀 동등성

## 0. 왜 이 문서가 필요한가

이 저장소만 보면 플러그인의 일은 "스캔해서 TIFF를 쓴다"로 끝난다.
그러나 **그 TIFF가 어떻게 해석될지는 이 저장소 밖에 있다.**

negaflow 본체(Apache-2.0, 별도 저장소)는 이 플러그인이 내는 파일을
**태그 없는 16-bit 선형 raw**로 읽는다. 그 전제가 깨지면 스캔은 성공하고,
검증도 통과하고, **색만 무너진다.** 가장 찾기 어려운 종류의 실패다.

이식 중에 "TIFF를 좀 더 친절하게 만들자"는 생각이 드는 순간이 반드시 온다.
이 문서가 그 순간을 위한 것이다.

## 1. 아키텍처 위치

```text
negaflow (Apache-2.0)                  이 저장소 (GPL-2.0-or-later)
┌──────────────────────────┐          ┌───────────────────────────┐
│ ScannerPluginHost        │          │ negaflow-scanner-sane     │
│ ExternalScannerBackend   │◄────────►│                           │
│ ScannerPluginManifest    │ Process  │  detect                   │
│ ScanTempFile             │ + Pipe   │  capabilities <id>        │
│                          │ NDJSON   │  scan                     │
│ SANE 코드 0줄            │          │                           │
│ libsane 링크 0           │          │  scanimage를 자식으로 실행  │
└──────────────────────────┘          └───────────────────────────┘
         ▲                                        │
         │  16-bit linear TIFF (태그 없음)          │
         └────────────────────────────────────────┘
```

핵심 사실:

- **negaflow에는 SANE 코드가 0줄이다.** 스캐너 인식·제어는 전부 이 플러그인.
- 통신은 `Process` + `Pipe`로만. **링크가 아니라 별도 프로그램 취합
  (aggregation)** 이며, 이것이 Apache-2.0 / GPL 경계를 성립시킨다.
- 장치 id는 `plugin:<pluginId>:<내부id>`. 이 플러그인의 `pluginId`는 `sane`.
- 플러그인 발견 경로(macOS): `~/Library/Application Support/negaflow/Plugins/<id>/manifest.json`
  (재정의 env: `NEGAFLOW_PLUGINS_DIR`)
- Windows 대응: `%LOCALAPPDATA%\Negaflow\ScannerPlugins\<id>\`

**negaflow의 기본 워크플로우는 "이미지 가져오기 → 현상"이고, 스캐너는
선택적 외부 플러그인이다.** 이 플러그인이 없어도 본체는 완전히 동작한다.
그래서 플러그인 실패는 본체를 죽이지 않아야 한다.

## 2. 프레임 소스 구분 — 로더가 갈린다

본체는 프레임마다 출처를 구분하고 **다른 로더**를 태운다.

| 구분 | 로더 | 색 해석 |
|---|---|---|
| 스캐너 출력 | `loadScannerTIFF` | **16-bit linear로 재해석** |
| 가져온 파일 | `loadImported` | ICC 프로파일 존중 |

`loadImported`의 규칙:

```text
RAW(제조사 전 포맷)      → CIRAWFilter
임베디드 ICC가 있으면     → 존중 (SilverFast HDRi의 SFprofT/SFprofN 포함)
프로파일 없는 16-bit      → linear로 간주 (VueScan raw TIFF)
```

**우리 출력은 "프로파일 없는 16-bit"에 해당한다.** 그리고 그것이 의도다.

### 2.1 여기서 나오는 절대 규칙

```text
출력 TIFF에 ICC 프로파일을 넣지 않는다.
sRGB 태그도, linear sRGB 태그도, 아무것도 넣지 않는다.
```

libtiff로 쓸 때 "표준을 지키자"며 `TIFFTAG_ICCPROFILE`이나
`TIFFTAG_TRANSFERFUNCTION`을 추가하면 본체가 감마 도메인으로 읽는다.
실측된 오염 규모([field-lessons](field-lessons.md) §6의 본체 사건):
**linear 0.3 → 0.58, 0.1 → 0.35.**

색이 "하얗고 파랗게" 나온다. 그리고 스캔은 성공으로 보고된다.

**macOS 동작 확인됨(2026-08-05, spike I-2).** `writeRGB16TIFF`가
`CGColorSpaceCreateDeviceRGB()`로 만든 `CGImage`를 ImageIO에 넘겨도
**프로파일이 박히지 않는다.** 산출물 태그 14개를 전수 확인한 결과:

```text
ICCProfile(34675)      없음 ✓
TransferFunction(301)  없음 ✓
Photometric            RGB (MINISWHITE 아님)
SampleFormat           unsigned integer
바이트 순서            MM (big-endian)
```

즉 macOS 는 이 계약을 **실제로 지키고 있다.** Windows 구현도 같은 태그
집합을 내면 된다 — libtiff 에서 `TIFFTAG_ICCPROFILE` 을 설정하지 않는 것으로
충분하다.

**이 계약이 걸리는 것은 병합 산출물뿐이다.** 단일 패스 스캔의 TIFF는
`scanimage`가 직접 쓰므로 우리 손을 거치지 않는다 — 그쪽에 프로파일이
박히는지는 백엔드와 `scanimage`의 문제이며, 지금까지 문제가 보고된 적은 없다.

## 3. 선형성은 두 겹으로 만들어진다

| 층 | 담당 | 수단 |
|---|---|---|
| 하드웨어 | 플러그인 | epson2 `--gamma-correction` = 항등 램프 / `--color-correction None` |
| 파일 | 플러그인 | 태그 없는 16-bit TIFF |
| 해석 | 본체 | `loadScannerTIFF` = linear 재해석 |

**세 개가 한 세트다.** 하나만 바꾸면 나머지 둘과 어긋난다.

`--gamma-correction`을 "안 보내도 되지 않나"라고 생각하는 순간
[field-lessons](field-lessons.md) §1로 돌아간다. epson2의 `Default`(index 0)는
중립이 아니라 **표시용 감마 0x02**를 보낸다. 감마를 안 건드리는 것이
선형이 아니다.

## 4. 네거티브 base 측정 — 왜 플러그인이 손대면 안 되는가

본체의 색 정확도는 **필름 base(Dmin)의 실측**에 걸려 있다.

우선순위:

```text
manual(사용자 스포이드)  >  실측  >  preset × 광원 프로파일
```

실측이 스캐너·광원·필름 퇴색을 **전부 흡수**하기 때문에, 이것이 예측 가능한
색의 유일한 정직한 경로다. 필름 데이터시트에는 D-min 수치 테이블이 존재하지
않는다(Portra 400 E-4050 실확인) — 프리셋은 근사치일 뿐이다.

### 4.1 플러그인에 대한 함의

```text
장치 내부의 어떤 톤·색 처리도 켜지 않는다.
```

스캐너가 자동 노출이든 자동 톤이든 무엇을 하든, 그것은 base 실측에
**측정 불가능한 왜곡**을 넣는다. 실측이 "스캐너를 흡수한다"는 말은
**스캐너가 매번 같은 짓을 할 때만** 성립한다.

이것이 다음 결정들의 진짜 이유다:

- epson2 `--color-correction None`
- epson2 `--gamma-correction` 선형
- coolscan2/3 `--negative=no` (장치 반전 끄기)
- coolscan `preserveRawCoolscan` (극성 변환 안 함)
- genesys 16-bit 톤 조정 억제

**전부 "장치야, 아무것도 하지 마"의 다른 표현이다.**

### 4.2 포지티브(슬라이드)도 마찬가지다

포지티브 파이프라인이 무보정 패스스루인 것은 **설계다**(flat master 계약).
슬라이드가 어둡게 나오는 것은 소프트웨어 Auto Tone으로 해결한다 —
16-bit라 +1.4 스탑을 소프트웨어에서 올려도 계조 손실이 무시할 수준이다.

**스캔 시점에 밝게 만들려는 시도는 하지 않는다**
([field-lessons](field-lessons.md) §2).

단, 본체의 포지티브 파이프라인에는 예외가 하나 있다: **SANE raw 범위 복원용
AutoLevels는 무조건 유지된다.** 이건 룩 보정이 아니라 raw 범위를 되살리는
기술적 단계다.

## 5. IR 채널 계약

### 5.1 파일과 필드

```text
RGB 결과      <outputPath>
IR 결과       <outputPath>.ir.tiff
result JSON   irPath, hasInfrared, warnings
```

옵셔널 추가 필드이므로 **하위 호환**이다. 구 호스트는 무시한다.

### 5.2 본체가 IR로 무엇을 하는가

본체의 IR 결함 제거는 순서가 고정돼 있다:

```text
정렬(NCC, 누설 텍스처 가드)
  → 다크 마진 flood-fill 제외      ← 스펙트럴 클린보다 먼저여야 한다
  → 스펙트럴 클린 (ired ≈ c + a·ln(red) 회귀)
  → 적응 임계 (이중 기준)
  → PCA 분류 → 클러스터 타일 마스크
  → 기존 복원 경로 재사용
```

가드:

- 흑백 은염 필름은 **skip**(은이 IR을 차단한다)
- 커버리지 > 5%면 **abort**(코다크롬 / 정렬 실패 — 사진 파괴 방지)

### 5.3 플러그인이 지켜야 하는 것

```text
IR 패스의 픽셀 격자가 RGB 패스와 정확히 같아야 한다.
```

`makeScanimageArgs`가 IR 패스에서 **소스/모드만 바꾸고 해상도·심도·
지오메트리를 유지**하는 이유가 이것이다. 격자가 어긋나면 본체의 정렬 단계가
누설 텍스처 가드에 걸리거나, 더 나쁘게는 어긋난 마스크로 멀쩡한 픽셀을
복원한다.

**최적화로 보이는 것이 정확성 요건이다.** IR 패스만 저해상도로 찍어 시간을
줄이려는 발상은 이 계약을 깬다.

### 5.4 IR 실패의 의미

```text
IR 패스 실패 → 경고를 남기고 RGB 결과를 반환 (예외 안 던짐)
그러나 요청했는데 IR 파일이 없으면 → 3단계 검증이 실패시킨다
```

모순처럼 보이지만 아니다. **최종적으로는 실패한다.** 중간 단계에서 예외를
던지지 않을 뿐이다(I-10).

## 6. 플러그인이 **모르는** 것 — 알려고 하지 말 것

본체가 하는 일 중 플러그인이 관여하지 않는 것을 명시한다. 이식 중에
"여기서 해주면 편한데"가 나오는 지점들이다.

| 본체의 일 | 플러그인이 하면 안 되는 이유 |
|---|---|
| 네거티브 반전 | 장치 반전(`--negative`)을 끄는 이유와 같다. 두 번 반전된다 |
| 필름 base 측정 | 실측이 전체 파이프라인의 앵커다. 미리 정규화하면 앵커가 사라진다 |
| 자동 톤 / 자동 화이트밸런스 | 사용자 opt-in 기능이다 |
| 결함 검출·복원 | IR 원본만 주면 된다 |
| 색 공간 변환 | linear raw가 계약이다 |
| 방향 보정 / 크롭 | 요청한 영역을 요청한 대로 |
| 스캐너 에뮬레이션 룩 | 완전히 본체 영역 |

**플러그인의 일은 "장치가 본 것을 왜곡 없이 파일로 옮기는 것" 하나다.**

## 7. wire 안정성이 왜 중요한가

**같은 호스트가 두 플랫폼의 플러그인을 상대한다.** 응답 형태가 다르면
호스트가 플랫폼별 분기를 갖게 되고, 그 순간 "계약"이라는 개념이 사라진다(I-5).

플랫폼 무관하게 고정되는 것:

```text
id                = "sane"
verifiedStatus    = 항상 "compatibleTarget"
driverVersion     = "<backend> (SANE)"
usbVendorID / usbProductID / serialNumber = 항상 null
모든 옵셔널 필드   = null로 명시
appliedOptions     = 12키 전부
sequence           = 0부터 1씩
```

`verifiedStatus`가 **항상** `compatibleTarget`인 것은 게으름이 아니라 규율이다
(I-19). 백엔드 이름이나 모델명으로 `verified`를 만들지 않는다.
**"장치가 보인다"와 "지원한다"는 다르다.**

### 7.1 `appliedOptions`는 요청 복사가 아니다

`appliedOptions.scanArea`에는 **실제로 `scanimage`에 보낸 영역**이 실린다.
epson2 정수 mm 정렬 때문에 높이가 1 mm 미만 달라질 수 있고, 호스트는
`abs(요청 높이 - 적용 높이) < 1 mm`를 허용한다.

**이 tolerance는 높이에만 있다.** 폭·원점이 달라지면 호스트가 거부한다.

## 8. 이식 체크리스트

- [ ] 출력 TIFF에 ICC 프로파일 / transfer function 태그가 **없다**
- [ ] 16-bit, 무압축, RGB(또는 IR은 gray)
- [ ] 장치 내부 색·감마·톤 처리를 전부 끈다
- [ ] `--negative=no` 무조건
- [ ] IR 패스의 해상도·심도·지오메트리가 RGB 패스와 동일
- [ ] IR 파일 경로가 `<outputPath>.ir.tiff`
- [ ] `irPath` / `hasInfrared` / `warnings` 필드가 옵셔널로 나간다
- [ ] IR 요청 + IR 부재 = 최종 실패
- [ ] `verifiedStatus`가 항상 `compatibleTarget`
- [ ] `appliedOptions`에 요청이 아니라 실제 적용값이 실린다
- [ ] 플러그인 실패가 본체를 죽이지 않는다(별도 프로세스 유지)
- [ ] `dumpbin /imports`에 sane이 없다
