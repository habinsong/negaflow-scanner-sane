# OpticFilm Gray. 무엇이 문제였고 macOS 에서 무엇이 남았는가

기준일: 2026-08-25
소유 코드: `negaflow-mac/Formula/sane-backends-negaflow.rb`
관련 Windows 정본: `../sane-runtime/patches/011-opticfilm-host-side-gray.patch`, `../sane-runtime/SOURCES.md`

이 문서는 **macOS 에서 실기 검증이 남아 있기 때문에** 존재한다. 코드 수정은 이미 formula 에
들어갔다. 남은 것은 맥에서 실제 스캐너로 돌려 보는 일뿐이고, 그 절차와 합격 기준을 여기에
적어 둔다. 이 문서를 읽지 않고 formula 의 genesys hunk 를 지우거나 다른 모델 행에 확대
적용하지 말 것.

## 1. 증상

Plustek OpticFilm 8100 을 **Gray 모드**로 스캔하면:

- 스캐너 헤드는 움직이고 dark/white calibration 도 끝난다.
- `begin_scan` 이 성공으로 돌아온다.
- 그 뒤 `wait_until_buffer_non_empty()` 가 보는 장치 버퍼가 **영원히 0** 이다.
- 프런트엔드는 멈춘 채 남고 결과 파일은 **0 바이트**다.

같은 장치의 **Color 16-bit 는 정상**이다. 그래서 "이 장치는 Gray 미지원" 이라는 추측으로
닫으면 안 된다. capability 목록은 Gray 를 지원한다고 보고하고, 실제로 아래 방식으로
동작한다.

## 2. 확정한 원인 세 가지

### 2.1 장치가 단일 채널 Gray 획득을 완주하지 못한다

genesys 백엔드는 `params.channels == 1` 이면 센서에게 단일 채널 획득을 요청한다.
7400-v2/8100 하드웨어는 이 경로에서 데이터를 내보내지 않는다.

SANE 1.4.0 에는 이미 해결책이 있다: `ModelFlag::HOST_SIDE_GRAY`. 이 플래그가 켜지면
`compute_session()` 이 Gray 요청을 **장치 RGB single-pass** 로 바꾸고
`ImagePipelineNodeMergeColorToGray` 가 행 단위 임시 버퍼에서 RGB→Gray 를 합친다.
전체 RGB 프레임을 따로 보관하지 않으므로 메모리는 늘지 않는다.

upstream 은 GL841 계열 3개 모델에만 이 플래그를 켰다.

### 2.2 색 필터 목록이 `None` 을 노출하지 않았다

`genesys.cpp` 의 `OPT_COLOR_FILTER` 초기화는 **CIS 가 아닌 스캐너**에게
`Red|Green|Blue` 만 주고 기본값을 `Green` 으로 잡는다. OpticFilm 은 CCD(=`is_cis == false`)라서
이 분기로 들어간다.

그런데 `compute_session()` 의 host-side Gray 조건은
`color_filter == ColorFilter::NONE` 이다. 즉 **`None` 을 고를 수 없으면 플래그를 켜도 절대
발동하지 않는다.** 그래서 이 분기를 `HOST_SIDE_GRAY` 플래그 기준으로 넓혀야 한다.
모델명이 아니라 플래그로 걸리므로 이 hunk 는 완전히 범용이다.

### 2.3 GL845/GL846 의 종료 길이 계산이 빠져 있다 (upstream 버그)

`use_host_side_gray` 가 켜지면 파이프라인은 Gray 를 내지만
`session.output_line_bytes_requested` 는 **센서가 실제로 획득하는 3채널** 기준이다.
`sane_get_parameters()` 는 이미 1채널 크기를 예고하므로, 읽기 루프가 3배를 다 읽을 때까지
멈추지 않는다.

```
scanimage: WARNING: read more data than announced by backend (3030240/1010080)
```

`gl841.cpp` 는 이 자리에서 `dev->total_bytes_to_read /= 3;` 을 한다. **GL845/GL846 에는
그 줄이 없다.** upstream 이 host-side Gray 를 GL841 에서만 돌려 봤기 때문이다.

> **여기서 한 번 헛짚었다.** 처음에는 이 수정을 `gl843.cpp` 에 넣었다. OpticFilm 8100 의
> `model.asic_type` 은 **`AsicType::GL845`** 이고, `low.cpp` 의 command-set 팩토리는
> `case AsicType::GL845:` 를 `GL846` 으로 흘려보내 `CommandSetGl846` 을 만든다. 즉 8100 은
> `gl843.cpp` 를 한 줄도 타지 않는다. 그리고 현재 `HOST_SIDE_GRAY` 를 켠 모델 중 GL843 은
> 하나도 없어서, gl843 쪽 수정은 **컴파일은 되고 절대 실행되지 않는 죽은 코드**였다.
> 빌드 로그로는 알 수 없고 실기 스캔의 바이트 수로만 드러난다.

## 3. formula 에 들어간 수정

`Formula/sane-backends-negaflow.rb` 의 `__END__` payload 에 genesys hunk 3개를 추가했고
`version` 을 `1.4.0-negaflow.4` 로 올렸다. Homebrew 는 version 이 바뀌어야 다시 빌드한다.

| hunk | 파일 | 분기 조건 | 범용성 |
|---|---|---|---|
| 1 | `backend/genesys/genesys.cpp` | `ModelFlag::HOST_SIDE_GRAY` | 플래그 기반. 모델명 없음 → **범용** |
| 2 | `backend/genesys/tables_model.cpp` | 7400-v2 행 (8100 이 상속) | **모델 행, 증거 범위 한정** |
| 3 | `backend/genesys/gl846.cpp` | `session.use_host_side_gray` | 세션 속성. 모델명 없음 → **범용**, upstream 버그 수정 |

### 3.1 hunk 2 의 범위를 왜 넓히지 않았는가

`tables_model.cpp` 는 SANE 이 **모델별 하드웨어 사실**을 적는 표다. upstream 도 GL841
3개 행에 같은 방식으로 이 플래그를 켠다. 그러니 "하드코딩 우회" 가 아니라 "사실 등록" 이다.

그렇더라도 실기 증거는 **OpticFilm 8100 한 대뿐**이다. OpticFilm 계열은 한 행이 아니다:

| 모델 | ASIC | 이 수정의 대상인가 |
|---|---|---|
| 7200 | GL842 | 아니오, 미검증 |
| 7200i / 7200-v2 / 7300 / 7400-v1 / 7500i / 7600i-v1 | GL843 | 아니오, 미검증 |
| **7400-v2** | **GL845** | **예**, 8100 이 이 행을 상속 |
| **8100** | **GL845** | **예**, 실기 증거 있음 |
| 8200i / 7600i-v2 | GL845 | 아니오, 미검증 |

host-side Gray 는 **3채널을 획득**한다. native Gray 가 멀쩡히 되는 장치에 이 플래그를 켜면
스캔이 느려지는 **회귀**다. 그래서 증거 없는 행은 켜지 않는다. 어떤 행을 켜려면 **그
장치의 실제 스캔 결과**가 있어야 한다.

## 4. Windows 에서 통과한 증거 (macOS 증거가 아니다)

같은 3개 hunk 로 빌드한 UCRT64 런타임을 OpticFilm 8100 실기에 걸어 확인한 값이다.

| 항목 | 수정 전 | 수정 후 |
|---|---|---|
| Gray 16-bit 600 dpi | 무한 정지, 0 B | **exit 0, 16,726 / 16,792 ms** |
| 예고/실제 바이트 | `3030240 / 1010080` 경고 | **경고 없음, 정확히 일치** |
| 결과 파일 | 3,030,462 B (2 MB 쓰레기 포함) | **1,010,302 B** |
| TIFF 헤더 | 856×590, 16-bit, SPP 1 | 동일 |
| Color 16-bit 회귀 | 정상 | **정상 (856×590, SPP 3, exit 0)** |

macOS formula 의 8개 hunk 전체는 **실제 macOS upstream tarball**
(`sane-backends-1.4.0.tar.gz`, sha256 `f99205c9…`) 에 `patch -p1 --dry-run` 으로
**오프셋 0, fuzz 0** 으로 적용됨을 확인했다. genesys hunk 의 C++ 자체는 Windows 빌드에서
경고 없이 컴파일된 같은 코드다.

**그러나 macOS 에서 빌드하고 실기로 돌린 적은 없다.** 아래 §5 를 통과하기 전에는
macOS 통과로 기록하지 않는다.

## 5. macOS 에서 해야 할 일. 정확한 절차와 합격 기준

### 5.1 빌드

```bash
brew uninstall --force sane-backends-negaflow
brew install --build-from-source ./negaflow-mac/Formula/sane-backends-negaflow.rb
```

`keg_only` 이므로 PATH 에 올라오지 않는다. 실행 파일 절대 경로를 먼저 잡는다.

```bash
SANEBIN="$(brew --prefix sane-backends-negaflow)/bin"
"$SANEBIN/scanimage" --version   # 1.4.0 이어야 한다
"$SANEBIN/scanimage" -L          # genesys:... OpticFilm 이 보여야 한다
```

### 5.2 합격 기준 1. 색 필터에 `None` 이 노출된다

```bash
"$SANEBIN/scanimage" -d <device> -A --mode Gray | grep color-filter
```

**합격**: `--color-filter Red|Green|Blue|None [None]`
**불합격**: `Red|Green|Blue [Green]`. hunk 1 이 안 먹은 것이다. 이 상태에서는 hunk 2 를
켜도 host-side Gray 가 발동하지 않는다.

### 5.3 합격 기준 2. Gray 16-bit 가 **연속 2회** 정상 종료한다

```bash
for i in 1 2; do
  "$SANEBIN/scanimage" -d <device> --mode Gray --depth 16 --resolution 600 \
    -l 0 -t 0 -x 36.33 -y 25 --format=tiff -o "gray_$i.tiff"
  echo "exit=$? size=$(stat -f%z gray_$i.tiff)"
done
```

**합격 조건 전부**:

1. 두 번 다 `exit=0` 이고 정지하지 않는다.
2. `read more data than announced by backend` 경고가 **한 번도** 나오지 않는다.
3. 파일 크기가 `폭 × 높이 × 2 + TIFF 헤더` 다. 600 dpi 전면이면 **1,010,302 B** 부근.
   3배(약 3,030,462 B)가 나오면 hunk 3 이 안 먹은 것이다.
4. `tiffinfo gray_1.tiff` 가 **Samples/Pixel 1**, **Bits/Sample 16** 이다.

### 5.4 합격 기준 3. Color 16-bit 회귀

```bash
"$SANEBIN/scanimage" -d <device> --mode Color --depth 16 --resolution 600 \
  -l 0 -t 0 -x 36.33 -y 25 --format=tiff -o color.tiff
```

**합격**: `exit=0`, 경고 없음, `Samples/Pixel 3`, 크기가 Gray 의 약 3배.

### 5.5 합격 기준 4. Coolscan / epson2 회귀

genesys hunk 는 다른 백엔드를 건드리지 않지만, formula 를 다시 빌드했으므로 기존 3개
수정이 살아 있는지 같이 본다. Coolscan 의 depth 목록과 epson2 의 스캔 높이·IR 프레임을
기존 실기 절차로 한 번씩 확인한다.

### 5.6 실패했을 때

`HOST_SIDE_GRAY` 를 켜고도 Gray 가 여전히 멈추면, **플래그를 억지로 유지하지 말고**
formula 의 hunk 2 를 되돌린 뒤 Negaflow 앱 쪽에서 Color RGB 로 획득하고 macOS 흑백
네거/포지티브 현상 경로로 넘기는 계약으로 바꾼다. 그 경우 이 문서에 실패한 실기 로그
(`SANE_DEBUG_GENESYS=255`) 를 그대로 붙이고 §3 표를 갱신한다.

## 6. macOS 앱 쪽에서 함께 고친 것

`negaflow` 저장소의 `negaflow-mac/Sources/Chromabase/Imaging/ImageLoader/ImageLoader+ImageIO.swift`
가 프로필 없는 16bit TIFF 를 linear raw 로 읽을 때 **항상 `linearSRGB`** 를 지정하고 있었다.
Gray 스캔은 monochrome 모델 `CGImage` 로 오므로 채널 수가 맞지 않는 색공간을 지정하는 셈이다.
`linearRawColorSpaceName(_:)` 을 추가해 monochrome 이면 `linearGray` 를 고르도록 고쳤다.
자세한 내용은 그 저장소의 `negaflow-mac/docs/gray-scan-ingest.md` 에 있다. 이 변경도
**macOS 실기 검증 전**이다.

## 7. 라이선스 경계

genesys hunk 3개는 GPL-2.0-or-later SANE 파생물이다. macOS 는 바이너리를 배포하지 않고
formula 와 patch payload(=대응 소스)만 배포하므로 기존 Coolscan/epson2 패치와 같은 경계에
있다. Apache-2.0 Negaflow 본체에 링크하거나 합치지 않는다. Windows 쪽 경계는
`../../negaflow-windows/docs/07-distribution/gpl-compliance.md` 가 소유한다.
