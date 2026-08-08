# 백엔드별 특수 처리

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 이식 정본 — 항목별 근거와 Windows 재검증 필요 여부
코드 근거: `SANEBackend+Discovery.swift`, `SANEBackend+Capabilities.swift`,
`SANEBackend+ScanExecution.swift`, `SANEBackend+Process.swift`,
`Formula/sane-backends-negaflow.rb`

관련 문서:

- [option-dump-parser](option-dump-parser.md)
- [exact-option-contract](exact-option-contract.md)
- [building-sane](../01-sane-runtime/building-sane.md)
- [validation-matrix](../09-hardware/validation-matrix.md)
- [driver-option-reference](../10-lessons/driver-option-reference.md) — 옵션별 근거와 upstream 소스
- [field-lessons](../10-lessons/field-lessons.md) — 이 분기들이 생긴 사건들

## 0. 원칙

백엔드 이름으로 분기하는 코드는 전부 **여기에 문서화된 것뿐**이어야 한다.
새 분기를 추가하려면 (a) upstream 백엔드 소스의 해당 줄, 또는 (b) 실기
관측 기록이 있어야 한다. 모델명으로는 절대 분기하지 않는다.

백엔드 동작은 OS가 아니라 SANE 구현이 결정한다. 따라서 **이 장의 모든 처리는
Windows에서도 그대로 유지된다.** 다만 각 항목이 Windows에서 실제로 재현되는지는
[validation-matrix](../09-hardware/validation-matrix.md)의 실기 항목이다.

현재 이름으로 분기하는 지점 목록:

| 위치 | 분기 대상 |
|---|---|
| `supportsStableBackendSelector` | genesys, epson2 |
| `isDedicatedFilmBackend` | coolscan, coolscan2, coolscan3, pie, pieusb |
| `canReuseSinglePassOptionsDump` | genesys |
| `capabilityOptionsDump` (기본 `--mode Color`) | genesys |
| `capabilityRedumpArguments` (color/gamma correction) | epson2 |
| `resolveMedia` (color/gamma correction) | epson2 |
| `resolveMedia` (높이 정렬) | epson2 |
| `resolveMedia` (필름 타입 극성) | coolscan, coolscan2, coolscan3 |
| `resolveMedia` (톤 조정 억제) | genesys + 16-bit |
| `fixedDepth` | epson2, pie |
| `parseCapabilities` (IR disabled reason) | coolscan3 |
| `validateExactOptions` | pieusb, epson2 |
| `makeScanimageArgs` | pieusb, epson2 |
| `runSingleAcquisition` (재시도 횟수) | pieusb |
| `runSingleAcquisition` (첫 진행률 재시도) | genesys |
| `usesAutomaticAcquisitionWatchdog` | pieusb |

## 1. genesys (Plustek OpticFilm 계열)

### 1.1 capability를 Color로 읽는다

```text
capabilityOptionsDump: backend == "genesys" → baseArgs += ["--mode", "Color"]
```

근거: 주 사용 모드가 Color이고, 다른 모드에서 읽은 활성 상태를 Color 스캔에
쓰면 안 된다.

### 1.2 단일 투과 소스면 덤프를 재사용한다

```text
canReuseSinglePassOptionsDump(dump, backend):
    backend == "genesys"
    소스 중 IR이 아닌 값이 정확히 1개
    그 하나가 투과 소스
    → true
```

근거(코드 주석): 단일 투과 소스만 가진 genesys 필름 스캐너는 장치를 연속해서
여러 번 열면 실제 OpticFilm에서 다음 acquisition이 실패할 수 있다.
Flatbed와 Transparency를 함께 가진 genesys 장치는 소스별 재검증을 그대로 수행한다.

**Windows 영향**: 이 최적화는 "USB 장치를 연속으로 여는 것이 위험하다"는
하드웨어/펌웨어 사실에 기반한다. 전송 계층이 바뀌어도(WinUSB, usbip)
장치 쪽 사실이므로 유지한다.

### 1.3 16-bit에서 톤 조정을 억제한다

```text
supportsHardwareToneAdjustments = !(backend == "genesys" && bitDepth == .sixteen)
거짓이면 hasBrightnessOption / hasContrastOption / brightnessRange / contrastRange를
모두 없는 것으로 취급
```

근거: 코드에 이유가 명시돼 있지 않다. genesys가 16-bit 경로에서 밝기/대비를
적용하지 못하거나 잘못 적용한다는 관측으로 추정된다.

**이식 시 조치**: 이 분기의 근거를 upstream `backend/genesys/` 소스에서 찾아
주석으로 남긴다. 찾지 못하면 "실기 관측 기반, 근거 미문서화"로 명시한다.
근거 없이 제거하지 않는다.

능력 응답과의 불일치는 [capability-model](capability-model.md) §3.10 참조.

### 1.4 첫 진행률 타임아웃 시 1회 재시도

```text
attempt == 0 && backend == "genesys" && code == .timeout
&& 첫 진행률 타임아웃 && 취소 아님
    → 출력 파일 삭제, 주소 캐시 무효화, 재시도
```

### 1.5 IR

genesys "i" 필름 스캐너는 별도 IR 소스(`Transparency Adapter Infrared`)를
노출한다. `.separateSource` 전략으로 두 번째 패스를 돈다.

IR 패스는 `--source`를 IR 소스로 바꾸고 `--mode`를 gray로 바꾼다.
해상도·심도·지오메트리는 본 스캔과 동일하다.

### 1.6 모델마다 해상도 목록이 다르다

**8100 한 대로는 안 드러난다.** `backend/genesys/tables_model.cpp` 의
`model.resolutions` 다.

| 모델 | ASIC | 해상도 | 투과 영역 | IR |
|---|---|---|---|---|
| OpticFilm 7200 | GL842 | 7200 3600 1800 900 | 36 × 25 | 없음 |
| OpticFilm 7200i | GL843 | 7200 3600 1800 900 | 36 × 24 | **있음** |
| OpticFilm 7200 v2 | GL842 | 7200 3600 1800 900 | 36 × 25 | 없음 |
| OpticFilm 7300 | GL843 | 7200 3600 1800 900 | 36 × 24 | 없음 |
| OpticFilm 7400 (v1/v2) | GL845 | 7200 3600 2400 1200 600 | 36.33 × 25 | 없음 |
| OpticFilm 8100 | GL845 | 7200 3600 2400 1200 600 | 36.33 × 25 | 없음 |
| OpticFilm 7500i | GL843 | 7200 3600 1800 900 | 36 × 24 | **있음** |
| OpticFilm 7600i (v1) | GL843 | 7200 3600 1800 900 | 36 × 24 | **있음** |
| OpticFilm 7600i (v2) | GL845 | 7200 3600 1800 900 | 36.33 × 25 | **있음** |
| OpticFilm 8200i | GL845 | 7200 3600 1800 900 | 36.33 × 25 | **있음** |

**8100 에서 되는 600 dpi 가 7500i 에는 아예 없다.** 목록을 보지 않고 보내면
그 기기에서만 스캔이 실패한다. 스냅하지 않는다(I-1) — 없는 값이면 거절한다.

심도는 전 모델 16 하나뿐이다(`bpp_color_values = { 16 }`). 실기 8100 도
`--depth 16 [16]` 을 낸다. 8-bit 요청은 거절해야 한다.

`opticfilm-matrix` 시험이 다섯 모델을 돌린다.

### 1.6a OpticFilm 120 / 135 는 SANE 이 지원하지 않는다

genesys 의 모델표에는 OpticFilm 항목이 **11개뿐**이고 위 표가 전부다.
1.4.0 도 upstream master(f498f59)도 같다. 120 / 120 Pro / 135 / 135i 는
칩셋이 달라 genesys 가 다루지 않는다. 우리가 할 수 있는 것이 없다.

### 1.7 프리뷰: `--preview` 는 genesys 에서 아무 일도 하지 않는다

`genesys.cpp` 는 `OPT_PREVIEW` 를 옵션으로 만들어 두고 **값을 어디서도 읽지
않는다**(`val[OPT_PREVIEW]` 참조 0건, 1.4.0). 그러니 프리뷰가 싼 이유는
플래그가 아니라 **`--resolution` 을 보내지 않는 것**이다. 그러면 백엔드가
자기 기본값으로 훑고, 그 기본값이 목록의 최솟값이다(실기 8100: `[600]`).

프리뷰에 해상도를 함께 보내도록 "개선" 하면 프리뷰가 본스캔 해상도로 돈다.
7200 dpi 프리뷰는 몇 분이 걸린다. `opticfilm-matrix` 가 모델마다
`--resolution` 이 **안 나가는지** 확인한다.

## 2. epson2 (Epson Perfection / GT 계열)

### 2.1 내부 색 보정을 끈다

```text
colorCorrection: constraintEnumValues("color-correction")에서
                 트림 후 "None"과 대소문자 무시 일치하는 첫 값
gammaCorrection: constraintEnumValues("gamma-correction")에서
                 소문자·공백 제거 후 "gamma=1.0"을 포함하는 첫 값
                 없으면 트림 후 "User defined"와 일치하는 첫 값
```

`resolveMedia`에서는 활성일 때만(`isActive`), 재덤프 인자 생성에서는
활성 여부와 무관하게(`constraintEnumValues`) 읽는다. 이 비대칭은 의도된
것이다 — 재덤프는 앞선 옵션 적용으로 활성화될 옵션을 같은 호출 뒤쪽에 배치하기
때문이다.

`color-correction`은 선택 모드에 "color"가 포함될 때만 적용한다.

negaflow가 원본 밀도를 현상하므로 장치 내부 색 보정과 감마는 전부 꺼야 한다.
끄지 못하면 2단계에서 스캔을 거부한다.

### 2.2 `--gamma-correction` 리버트 이력

커밋 `7f950dc`는 `82b7b32`("set the Epson linear gamma even when the option
reports inactive")를 되돌렸다. 즉 **비활성 상태의 gamma-correction을 강제로
설정하려던 시도는 철회됐다.**

현재 동작:
- `resolveMedia`: 활성일 때만 값을 정한다.
- `capabilityRedumpArguments`: 활성 여부와 무관하게 값을 실어 재덤프한다.
- `validateExactOptions`: 옵션이 활성인데 값을 못 정했으면 거부한다.

Windows 이식에서 이 이력을 모른 채 "비활성이어도 보내면 되지 않나"라고
되돌리지 않도록 여기 기록한다. 되돌리려면 실기 증거가 필요하다.

**왜 그것이 스캔을 실패시키는지**(SANE 원본 근거)와 감마 선택 규칙의
전체 유도는 [driver-option-reference](../10-lessons/driver-option-reference.md) §8에
있다. 요약: `OPT_GAMMA_CORRECTION`의 비활성은 "지금 꺼져 있다"가 아니라
**"이 하드웨어에 감마 명령이 없다"** 는 뜻이고, 그 상태에서 옵션을 보내면
`attempted to set inactive option`으로 스캔 전체가 실패한다.

### 2.3 정수 mm 절삭 보정 (`epson2AlignedHeightMM`)

`backend/epson2-ops.c`의 `e2_init_parameters`. `params.lines`를 **두 번**
대입하는데, 문제는 두 번째다.

```c
/* ① 일반 경로 — 여기는 멀쩡하다 */
s->params.lines =
    ((SANE_UNFIX(s->val[OPT_BR_Y].w - s->val[OPT_TL_Y].w) / MM_PER_INCH) * dpi) + 0.5;

/* ② 아래 가장자리를 넘치면 다시 계산한다 */
if (SANE_UNFIX(s->val[OPT_BR_Y].w) / MM_PER_INCH * dpi < (s->params.lines + s->top)) {
    s->params.lines =
        ((int) SANE_UNFIX(s->val[OPT_BR_Y].w) / MM_PER_INCH * dpi + 0.5) - s->top;
}
```

②의 `(int)` 캐스트가 나눗셈보다 먼저 걸려 **`br_y`를 밀리미터 단위로
버린다**(1.4.0의 1421행, master도 같다). `lines`와 `top`이 둘 다 올림되면
조건이 참이 되므로 이 경로는 드물지 않다. `br_y`가 소수 mm면 결과 이미지의
세로만 최대 1 mm어치 짧아진다. 요청한 종횡비와 어긋나고 필름 컷이 조용히
잘린다. 아래를 정수 mm로 맞춰 보내면 `(int) br_y == br_y`가 되어 아무것도
잃지 않는다 — 그것이 아래 알고리즘이다.

보정 알고리즘:

```text
bottom = originY + height
bottom이 이미 정수(1e-9 이내)면 → 그대로

grownBottom = ceil(bottom)
grown = grownBottom - originY
range.containsExactly(grown) 이고 grownBottom <= surfaceBottom + 1e-9
    → grown 채택 (스캔 범위가 최대 1 mm 넓어질 뿐 잘리지 않는다)

shrunk = floor(bottom) - originY
shrunk > 0 이고 range.containsExactly(shrunk)
    → shrunk 채택

둘 다 불가능하면 → 요청값 그대로
```

`heightAlignmentMM = 채택값 - 요청 높이`이며, 2단계 검증은
`abs(heightAlignmentMM) < 1`을 요구한다. 프로토콜의
`appliedOptions.scanArea.heightMM`에 채택값이 실린다. 호스트는
`abs(요청 높이 - 적용 높이) < 1 mm`를 허용한다.

**이 tolerance는 높이에만 있다.** 폭·원점에는 없다.

폭에도 절삭이 있지만 성격이 다르므로 보정하지 않는다.

```c
/* pixels_per_line is rounded to the next 8bit boundary */
s->params.pixels_per_line = s->params.pixels_per_line & ~7;
```

폭은 **픽셀 단위로 8의 배수까지 내림**한다(1.4.0과 master 모두). 최대 7픽셀
손실이라 2400 dpi 에서 0.074 mm, 600 dpi 에서 0.30 mm 다. 높이 쪽 1 mm 와
자릿수가 다르고, mm 를 조정해서 없앨 수 있는 종류가 아니다(요청 폭과
무관하게 8 경계로 떨어진다). 맥도 같으므로 **동작을 맞춘다.** 앱은 결과의
실제 픽셀 폭을 result 이벤트로 받는다.

이 패치는 `Formula/sane-backends-negaflow.rb`에도 들어 있어 Coolscan 설치
경로에서는 백엔드 자체가 고쳐진다. 하지만 stock SANE 사용자를 위해
플러그인 쪽 보정을 함께 유지한다. Windows에서 stock 빌드를 쓴다면 플러그인
보정이 유일한 방어선이다.

### 2.4 심도가 Lineart에서 비활성

기본 모드가 Lineart이고 그 상태에서 `--depth`가 비활성이다(실측: GT-X980 = V850).
모드를 적용하지 않은 덤프만 읽으면 지원 심도가 통째로 빈다.
→ [capability-model](capability-model.md) §2.

### 2.5 `fixedDepth` 후보

`--depth` 옵션 자체가 없으면 8-bit 고정으로 판정한다(구형 기기).

### 2.5b 적외선은 소스가 아니라 **모드**다

genesys 와 갈리는 지점이다.

```text
genesys   별도 소스   --source Transparency Adapter Infrared   (SeparateSource)
epson2    모드        --mode Infrared                          (SeparateMode)
```

epson2 의 `mode_list` 에 `Infrared` 가 들어 있고(`SANE_FRAME_IR` 이 정의돼
있으므로 항상), 별도 IR 소스는 없다. 그래서 IR 패스는 **소스를 그대로 두고
모드만 바꾼다.** 소스를 바꾸려 들면 그런 소스가 없어 실패한다.

IR 패스에는 `--film-type` / `--color-correction` / `--gamma-correction` 을
보내지 않는다. 색 처리 옵션이라 적외선 채널에 의미가 없다.

실측한 인자(`epson-smoke` ⑤a):

```text
-d epson2:usbscan:001 -p --source TPU8x10 --mode Color --color-correction None
   --gamma-correction User defined --film-type Negative Film --brightness=0
   --resolution 2400 --depth 16 -l 10 -t 20 -x 36 -y 24 --format=tiff
-d epson2:usbscan:001 -p --source TPU8x10 --mode Infrared
   --resolution 2400 --depth 16 -l 10 -t 20 -x 36 -y 24 --format=tiff
```

### 2.6 소스

`Flatbed` / `Transparency Unit` / `TPU8x10`. 8x10을 우선한다.
`--film-type`으로 극성을 지정한다.

**`TPU8x10`은 세 모델에만 붙는다.** `backend/epson2-ops.c`의 TPU2 분기가
모델명을 `GT-X800` / `GT-X900` / `GT-X980` 으로 검사한다(= 4990 /
V700·V750 / V800·V850). 그 밖의 투과 장비 — 예를 들어 일본 모델 `GT-X970` —
는 `Transparency Unit` 하나만 낸다. 8x10을 전제로 만든 코드는 그런 기기에서
투과 스캔을 아예 못 하게 된다. 두 경우 모두 `epson-smoke` 가 돌린다.

### 2.4a 사용자는 자기가 산 이름을 못 본다

`detect` 가 내는 이름은 **기기가 스스로 말하는 것**이고, 그것이 일본 내수
모델명이다.

```text
Perfection V800 / V850  →  GT-X980
Perfection V700 / V750  →  GT-X900
Perfection 4870         →  GT-X700
```

epson2 는 `esci_request_extended_identity` 가 준 buf[46..61] 을 그대로
모델명으로 쓴다(`e2_set_model`). 추정이 아니다 — epson2-ops.c 의 TPU2 분기가
바로 그 문자열로 검사하므로(`e2_model(s, "GT-X980")`), 그렇지 않으면 그
분기가 영영 안 돈다.

`displayName` 은 `capitalized(vendor) + " " + model` 이므로 사용자는
**"Epson GT-X980"** 을 본다. 자기가 산 V800 이 아니다.

**여기서 고치지 않는다.** 맥도 같은 문자열을 낸다. 별칭 표를 넣으려면 양쪽을
같이 고쳐야 하고, 그것은 제품 결정이지 이식 작업이 아니다. `epson-smoke` 는
이 사실을 고정만 한다 — 누가 픽스처를 "Perfection V800 Photo" 로 되돌려
문제를 감추지 못하게.

### 2.5a 프리뷰: epson2 는 고속 모드를 켠다

genesys 와 달리 epson2 는 `--preview` 를 실제로 쓴다.

```c
if (s->val[OPT_PREVIEW].w)
        status = esci_set_speed(s, 1);   /* 고속 */
else
        status = esci_set_speed(s, 0);
```

해상도는 건드리지 않는다. 그러니 여기서도 싼 이유는 **`--resolution` 을
보내지 않아** 기기 기본값(목록 최솟값)으로 훑기 때문이다. 프리뷰라도
`--source` 는 투과여야 한다 — 평판으로 훑으면 필름이 안 보인다.

`epson-smoke` ④a 가 확인한다.

### 2.6a 초점은 우리가 건드리지 않는다 — `--source`가 이미 옮긴다

`--focus`를 보내고 싶어질 수 있다. V700/V750/V800/V850은 필름을 유리에서
띄워 스캔하니까 초점을 필름면으로 옮겨야 할 것 같다. **이미 옮겨져 있다.**

`epson2.c`의 `--source` 처리(`sane_control_option`)가 하는 일이다.

```c
} else if (strcmp(TPU_STR, value) == 0 || strcmp(TPU_STR2, value) == 0) {
        ...
        if (s->hw->focusSupport)
                s->val[OPT_FOCUS_POS].w = FOCUS_ABOVE_25MM;   /* 64 + 25 */
```

`FOCUS_ON_GLASS`가 64, `FOCUS_ABOVE_25MM`가 64+25 다. 투과 소스를 고르면
백엔드가 초점을 **유리 위 2.5 mm**, 즉 필름 홀더 면으로 옮기고, Flatbed 나
ADF 를 고르면 유리로 되돌린다. 우리가 `--focus`를 따로 보내면 그 기본값을
덮어쓴다.

`focusSupport`는 기기에 물어서 정한다(`esci_request_focus_position`이
성공하면 참). 지원하지 않는 기기에서는 `--focus`가 `[inactive]`로 나오므로
보내면 스캔 전체가 실패한다.

같은 분기가 `--film-type`도 그때 활성화한다. 소스를 적용해 덤프를 다시
읽어야 하는 이유가 지오메트리만은 아니다.

### 2.7 Windows: 필요한 sanei_usb API가 genesys의 부분집합이다

epson2와 epsonds가 부르는 것은 `init` `open` `close` `read_bulk` `write_bulk`
`set_timeout` `get_vendor_product` `find_devices`
`attach_matching_devices` 아홉이고, **전부 genesys 도 부른다.** genesys 는
OpticFilm 8100 실기에서 usbscan 경로로 돈다 — 그러니 usbscan 백엔드 쪽에
Epson 전용으로 남은 구멍은 없다. genesys 는 그 위에 `control_msg`
`clear_halt` `reset` `get_descriptor` 까지 쓴다.

실측(2026-08-06): 두 백엔드 모두 Windows 에서 로드·초기화되고, 설정을 읽고,
USB 와 네트워크를 훑고 정상 종료한다. `scsi EPSON` 줄과 `net autodiscovery`
줄도 걸리지 않는다.

### 2.8 V800/V850 은 PID 목록에 있다 — 확인함

한 번 잘못 짚었으니 적어 둔다. `backend/epson_usb.c` 는 항목이 36개뿐이고
`0x0151`(GT-X980 = V800/V850)이 없다. 그러나 **그 파일은 폐기된 `epson`
백엔드의 것이다.** epson2 는 `backend/epson2_usb.c` 를 쓰고, 그쪽은
`epson2.desc` 에서 생성돼 182개이며 `0x012c`(V700/V750)와 `0x0151` 이 모두
들어 있다.

실측: 재고 `epson2.conf` 로 `sanei_usb_find_devices` 가 183회 불리고
(182개 + 종료용 0) 그 안에 `0x0151` 이 있다. 설정을 손댈 이유가 없다.

### 2.9 epsonds 와 겹치지 않는다

둘 다 `dll.conf` 에 있으니 한 기기가 두 번 나올 수 있다. 안 그런다.

실측: epsonds 는 PID 73개를 찾고 그 안에 `0x012c`(V700/V750)도
`0x0151`(V800/V850)도 없다. epsonds 는 ESC/I-2 를 쓰는 DS 계열 문서
스캐너를 맡고, Perfection 필름 평판은 epson2 가 맡는다. 목록이 겹치지
않으므로 `detect` 에 중복이 생기지 않는다.

## 3. coolscan3 (Nikon Coolscan LS 계열)

### 3.1 `--mode`가 없다

전용 필름 스캐너로 판정돼 Color 요청만 통과한다.
`--mode`를 보내면 `scanimage`가 즉시 실패하므로 절대 보내지 않는다.

### 3.2 pel 단위 지오메트리

`-x`/`-y`가 `pel` 단위이거나 `tl-x`/`tl-y`/`br-x`/`br-y` 모서리 좌표를
쓴다. mm 값을 넘기면 N픽셀 폭으로 오해된다.

pel 변환은 `mm * dpi / 25.4`이며 반올림 후 범위의 `containsExactly`를
만족해야 한다. 만족하지 못하면 2단계에서 거부된다.

### 3.3 `--depth 8|14`

14-bit는 16-bit 컨테이너로 전달된다. `depthArgument`는 16이 없으면
8 초과 값의 최대(=14)를 고른다.

### 3.4 `--infrared`를 IR 능력으로 보고하지 않는다

coolscan3의 `--infrared`는 `SANE_FRAME_RGBI` **한 프레임**이며,
stock `scanimage` 1.4는 이를 RGB와 IR 두 개의 TIFF로 분리하지 못한다.
따라서 별도 IR 채널 기능으로 보고하지 않고, `disabledReasons["infrared"]`에
그 이유를 적는다.

**Windows에서도 동일하다.** `scanimage`의 한계이지 OS의 한계가 아니다.
이것을 해결하려면 `scanimage`를 고치거나 SANE API를 직접 쓰는 어댑터를
만들어야 하는데, 후자는 이 플러그인의 GPL 경계 설계를 근본적으로 바꾼다
([gpl-compliance](../07-distribution/gpl-compliance.md) §5).

### 3.5 `--negative` 는 장치 반전 스위치다

coolscan2/coolscan3의 `--negative`는 필름 메타데이터가 아니라 **스캐너 자체
색 반전**이다. negaflow가 원본 네거티브 밀도를 현상하므로 **항상 `no`로
보낸다.** 요청 filmType과 무관하다.

### 3.6 word-list 할당 버그

`Formula/sane-backends-negaflow.rb`가 적용하는 패치:

```diff
-  word_list = (SANE_Word *) cs2_xmalloc (2 * sizeof (SANE_Word));   coolscan2.c:546
+  word_list = (SANE_Word *) cs2_xmalloc (3 * sizeof (SANE_Word));
-  (SANE_Word *) cs3_xmalloc(2 *                                     coolscan3.c:506
+  (SANE_Word *) cs3_xmalloc(3 *
```

upstream 커밋 `9bea1ee256c744098576acee98053e094b4a14a2`. 힙 오버플로우이며
macOS 26의 강화된 할당자에서 즉시 크래시한다. 그래서 별도 keg를 빌드한다.

**Windows 영향**: 이 버그는 OS 무관하다. 다만 Windows 힙(특히 디버그 힙이나
page heap)이 이를 크래시로 드러낼지, 조용히 넘어갈지는 할당자 구현에 달렸다.
어느 쪽이든 **패치된 SANE를 쓰는 것이 맞다.** Windows에서 SANE를 어떻게
전달하든 이 패치 적용 여부를 명시해야 한다
([building-sane](../01-sane-runtime/building-sane.md), 
[gpl-compliance](../07-distribution/gpl-compliance.md)).

### 3.7 LS-5000 미해결

upstream의 후속 변경이 Coolscan3 load/eject/reset 파라미터 블록을 초기화하는데
(LS-5000 펌웨어 1.03에 필요), 현재 최소 패치 세트에는 의도적으로 포함하지
않았다. 따라서 LS-5000 load/eject/reset은 패치된 설치에서도 미검증이며
실패할 수 있다.

## 4. coolscan (구형 SCSI)

`--type` 옵션을 쓰며, `preserveRawCoolscan` 플래그로 **극성 변환을 하지 않고**
항상 positive 계열 값을 고른다. SCSI 전용이다.

**Windows 영향**: SCSI 경로는 현대 Windows에서 사실상 불가능하다.
ASPI 계층이 없고, 레거시 SCSI HBA 드라이버가 Windows 11에 존재하지 않는다.
이 백엔드는 Windows 지원 범위에서 제외하는 것이 현실적이다
([validation-matrix](../09-hardware/validation-matrix.md) §6).

## 5. pieusb / pie (Reflecta, PIE PowerSlide)

### 5.1 `--advance=no`가 필수다

`pieusb`는 full scan 뒤 다음 슬라이드로 이동하는 `--advance`의 기본값이
`yes`다. 앱이 배치 이동을 요청하지 않았으므로 옵션이 확인되면 **항상 `no`**를
보낸다.

옵션이 활성이 아니면 2단계에서 **스캔을 거부한다.** 자동 이동을 끌 수 없는데
스캔하면 사용자의 필름 배치가 예상 없이 움직인다.

### 5.2 재시도 금지

```text
attemptCount = backend == "pieusb" ? 1 : 2
```

full scan 자체가 슬라이드 이동을 수반할 수 있으므로 같은 요청을 자동
재시도하면 다른 프레임을 덮어쓴다.

### 5.3 watchdog 끔

```text
usesAutomaticAcquisitionWatchdog(backend) = backend != "pieusb"
```

`pieusb`는 shading/calibration과 실제 acquisition을 `sane_start` 안에서 동기
실행해 첫 progress가 장시간 없을 수 있다. 중간 종료는 transport 상태를
불명확하게 만들므로 **사용자 취소만 허용한다.**

이것이 뜻하는 바: pieusb 스캔은 무한정 매달릴 수 있다. 호스트의 scan
타임아웃(7,200초)만이 상한이다. Windows 구현도 같다.

### 5.4 `--clean-image`는 IR 채널이 아니다

백엔드가 IR로 먼지를 제거한 RGB를 반환하는 단일 패스 기능이다. 별도 IR
파일이 없으므로 `supportsInfrared = false`이고 `disabledReasons`에 이유를 적는다.

코드에 `IRStrategy.cleanImage`가 정의돼 있고 `makeScanimageArgs`와
`startFullScan`에 처리 분기가 있지만, `resolveMedia`가 이 값을 **만들지
않는다.** 즉 현재 도달 불가능한 코드다. 이식 시 이 상태를 그대로 유지하고
임의로 활성화하지 않는다.

### 5.5 모델 번호 매칭

`pieusb`는 USB ID **와** 모델 번호를 함께 본다. Reflecta와 PIE 유닛이
`05e3:0145` 같은 ID를 공유하므로, 유닛이 `pieusb.conf`에 모델 번호로
등재돼 있어야 사용 가능하다.

**Windows 영향**: `pieusb.conf`가 SANE 설정 디렉터리에 있어야 하고, 그
디렉터리를 찾는 방법이 Windows 런타임 경로에 따라 다르다
([environment-and-paths](../03-process-and-io/environment-and-paths.md)).

### 5.6 `pie` (구형 SCSI)

`--depth` 옵션이 없고 항상 8-bit다. `fixedDepth`가 `.eight`를 돌려준다.
coolscan과 같은 이유로 Windows에서 사실상 불가능하다.

## 6. 모델명이 하드웨어를 식별하지 못한다

README에 정리된 사실이며 Windows에서도 동일하다.

| 함정 | 내용 |
|---|---|
| OpticFilm 8100 | `07b3:130c`는 genesys가 구동, `07b3:1824`는 다른 Genesys 칩이라 어느 백엔드도 구동하지 못함 |
| OpticFilm 8200i | `07b3:130d`는 구동, `07b3:1825`(GL128)는 미지원 |
| pieusb | USB ID + 모델 번호 둘 다 일치해야 함 |
| epson2 | Perfection V800/V850을 `GT-X980`으로, V700/V750을 `GT-X900`으로 보고. 같은 스캐너다 |

Windows에서는 여기에 하나가 더 붙는다.

| 함정 | 내용 |
|---|---|
| 드라이버 점유 | 같은 USB 장치를 벤더 드라이버/WIA/TWAIN이 이미 잡고 있으면 libusb가 열 수 없다. 반대로 WinUSB로 바꾸면 벤더 소프트웨어가 못 쓴다 |

→ [driver-conflicts](../09-hardware/driver-conflicts.md)

## 7. 이식 체크리스트

- [ ] §0의 분기 목록 16개가 전부 이식됐고 새 분기가 추가되지 않았다
- [ ] genesys 16-bit 톤 억제의 근거를 조사하고 결과를 기록했다
- [x] epson2 gamma 리버트 이력을 코드 주석에 남겼다
- [x] `epson2AlignedHeightMM` 4갈래 전부 fixture — `test_main.cpp`
      `testEpson2AlignedHeight()` 가 단위로, `epson-smoke` ⑤ 가 요청부터
      `-y` 인자와 `appliedOptions` 까지 통째로 돌린다
- [ ] coolscan `--negative=no` 강제
- [ ] pieusb 3종 처리(advance/재시도/watchdog)
- [ ] `IRStrategy.cleanImage` 도달 불가 상태 유지
- [ ] coolscan/pie SCSI를 Windows 지원 범위에서 제외한다는 결정 반영
- [ ] Coolscan word-list 패치 적용 여부를 배포물마다 명시
