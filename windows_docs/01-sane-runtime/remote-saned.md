# 원격 saned 경로

기준일: 2026-08-04
상태: 지원 대상 밖 — 그러나 깨뜨리지 않는다
목적: `net` 백엔드 경로의 실체와, 우리가 무엇을 하지 않기로 했는지 기록

관련 문서:

- [availability](availability.md)
- [runtime-route-decision](runtime-route-decision.md)
- [device-identity](../02-frontend-contract/device-identity.md)

## 1. 구조

```text
[Windows]
  negaflow-scanner-sane.exe
    scanimage.exe (net 백엔드 포함)
      net.conf → 서버 호스트 목록
      TCP 6566 (제어) + 임의 포트 (이미지 데이터)
[Linux 서버]
  saned
    libsane → libusb → 스캐너
```

장치명은 `net:<host>:<backend>:<device>` 형태가 된다.

## 2. 왜 매력적인가

Windows 쪽 USB 드라이버 문제가 **완전히 사라진다.** Zadig도, WinUSB
동시성 제약도, 벤더 소프트웨어 손실도 없다. Windows는 순수한 TCP 클라이언트다.
스캐너 쪽은 검증된 Linux 스택이고, `pieusb`를 포함한 모든 백엔드를 쓸 수 있다.

## 3. 왜 채택하지 않는가

### 3.1 MSYS2 빌드에 `net` 백엔드가 없다

**확인** — MSYS2 PKGBUILD의 명시적 `BACKENDS=` 허용 목록에 `net`이 없고,
배포되는 58개 백엔드 DLL 중 `libsane-net-1.dll`이 없다.

즉 현재 배포되는 `scanimage.exe`로는 **원격 서버에 연결할 수 없다.**
[building-sane](building-sane.md)의 재빌드가 선행돼야 한다.

### 3.2 `saned.exe`도 없다

**확인** — MSYS2 패키지에 `saned.conf`와 `saned.8`만 있고 실행 파일이 없다.
Windows를 스캐너 서버로 쓸 수 없다.

### 3.3 사용자가 Linux 머신을 운영해야 한다

라즈베리파이 한 대와 udev 규칙, 방화벽 설정, `saned` 서비스 관리.
필름 스캔 사용자에게 일반 제품 요구로 제시할 수 없다.

### 3.4 데이터 포트

`saned`는 6566에서 제어 연결을 받지만 **이미지 데이터는 별도의 임의 포트**로
전송된다. `saned.conf`에 `data_portrange`를 고정하지 않으면 방화벽에서
막힌다. 이것이 SANE 네트워크 배포의 고전적 함정이다.

### 3.5 진행률 watchdog과의 상호작용

이 플러그인의 watchdog은 stderr의 `Progress: N%`가 일정 시간 내에 갱신되는지
본다([timeouts-and-watchdog](../03-process-and-io/timeouts-and-watchdog.md)).
네트워크 경로에서는:

- 첫 진행률까지의 지연이 길어질 수 있다(서버가 장치를 여는 시간 + 네트워크)
- 데이터 전송이 끊겨도 `scanimage`가 즉시 알아채지 못할 수 있다
- 180초 기본값이 적절한지 재측정이 필요하다

### 3.6 인증

`saned`의 사용자 인증은 `saned.users`의 평문 자격 증명에 기반한다.
네트워크 구간이 암호화되지 않는다. 신뢰된 로컬 네트워크 전제다.

## 4. 결정

```text
D-03  원격 saned 경로는 지원 대상이 아니다.
      설치 프로그램도, 문서의 설치 절차도 이 경로를 안내하지 않는다.

      그러나 어댑터 코드는 이 경로를 특별히 막지 않는다.
      사용자가 스스로 net 백엔드가 포함된 scanimage를 배치하고
      net.conf를 구성하면 동작해야 한다.
```

## 5. "깨뜨리지 않는다"의 구체적 의미

어댑터 코드가 다음을 만족해야 한다.

### 5.1 `connectionType` 판정

```text
connectionType(deviceString):
    ":net:" 포함     → .network
    ":scsi:" 또는 "/dev/sg" → .scsi
    ":firewire:" | ":ieee1394:" | ":ieee-1394:" → .fireWire
    ":usb:" 또는 ":libusb:" → .usb
    그 외            → .internalBus
```

`net` 장치가 `.network`로 정확히 보고돼야 한다. 이미 구현돼 있으므로
이식 시 유지만 하면 된다.

### 5.2 `isVolatileUSBSelector`

```text
isVolatileUSBSelector(v) = v.contains(":libusb:")
```

`net:` 장치는 false다. 따라서 주소 만료 로직이 개입하지 않고,
`media.acquisitionDevice`가 그대로 재사용된다. 올바른 동작이다.

### 5.3 `noteDeviceOpened`

`net` 장치도 `cachedAddressIsStableSelector`가 false이므로(문자열에 `:`가
있으므로) 캐시가 무효화된다. 약간 비효율적이지만 정확하다.
**최적화하지 않는다** — `net` 경로는 지원 대상이 아니므로 위험을 감수할
이유가 없다.

### 5.4 `supportsStableBackendSelector`

```text
allowSingleBackendSelector && supportsStableBackendSelector(backend)
&& backendMatches.count == 1
&& chosen.devname.contains(":libusb:")   ← net 장치는 여기서 걸러진다
```

`net:...:genesys:...`의 backend 이름은 `net`이므로 애초에
`supportsStableBackendSelector`를 통과하지 않는다. 이중으로 안전하다.

### 5.5 백엔드 이름 추출

```text
backendName("net:192.168.0.10:genesys:libusb:001:002") = "net"
```

즉 **백엔드별 특수 처리가 전부 비활성화된다.** epson2 감마 보정도,
pieusb `--advance=no`도, genesys 재시도도 적용되지 않는다.

이것은 알려진 한계다. 원격 경로에서는 백엔드별 처리를 받지 못하고,
그 결과 epson2 원격 스캐너는 2단계 검증에서 색 보정 관련 조건에 걸리지
않아 **내부 감마가 켜진 채 스캔될 수 있다.**

**이 한계를 문서화하고 코드로 막지 않는다.** 막으려면 중첩 장치명을
파싱해야 하고, 그 파싱이 틀리면 로컬 경로까지 영향을 준다.
지원 대상 밖 경로 때문에 지원 대상 경로를 위험에 빠뜨리지 않는다.

원격 경로를 정식 지원하기로 한다면 그때 다음을 결정한다.

```text
effectiveBackendName(deviceString):
    "net:"로 시작하면 → 호스트 부분을 건너뛴 다음 토큰
    아니면            → 첫 ":" 앞
```

그리고 이 변경은 [decision-register](../00-overview/decision-register.md)의
새 항목이 되어야 한다.

## 6. SANEWinDS는 이 경로가 아니다

SANEWinDS(GPLv3, 1.6.9221, 2025-04-02)는 SANE 네트워크 프로토콜을 직접 구현한
네이티브 Windows 클라이언트다. TWAIN 2.x 데이터 소스와 단독 실행 파일,
그리고 .NET DLL로 제공된다.

**`scanimage`를 제공하지 않는다.** 따라서:

- 이 플러그인이 SANEWinDS를 호출할 방법이 없다(CLI가 없다).
- SANEWinDS를 쓰려면 TWAIN 클라이언트나 .NET 상호운용을 새로 작성해야 하고,
  그것은 SANE 어댑터가 아니라 TWAIN 어댑터다.
- 문서화된 프로그래밍 API의 존재 여부는 **미확인**이다(spike S-6).

NAPS2가 Windows에서 SANE 서버에 접근하는 방법으로 SANEWinDS 설치를
안내하는 것도 같은 이유다 — SANEWinDS는 TWAIN 장치로 보인다.

정리: **SANEWinDS는 우리 플러그인의 대안이 아니라 우리 플러그인의 경쟁자다.**
Windows에서 원격 SANE가 필요한 사용자는 SANEWinDS를 직접 쓰고 negaflow의
TWAIN 경로로 들어오는 편이 낫다. 그 경로는 본체 windows_docs의
`10-scanner/twain-wia.md`가 소유한다.

## 7. 문서에 남길 사용자 안내

지원하지 않지만 사용자가 물을 수 있다. FAQ 수준의 답:

> **Q. 리눅스 서버에 연결된 스캐너를 Windows에서 쓸 수 있나요?**
>
> 이 플러그인은 그 구성을 지원하지 않습니다. `net` 백엔드가 포함된
> `scanimage`를 직접 준비하고 `net.conf`를 구성하면 동작할 수 있지만,
> 백엔드별 보정(Epson 감마 끄기, Reflecta 자동 이동 끄기 등)이 적용되지
> 않아 결과가 달라질 수 있습니다.
>
> 원격 스캐너를 쓰려면 SANEWinDS를 설치해 TWAIN 장치로 만든 뒤
> negaflow의 TWAIN 경로를 사용하는 편을 권합니다.

## 8. 열린 질문

- SANEWinDS에 문서화된 프로그래밍 API가 있는가 (S-6)
- `net` 백엔드를 재빌드로 추가할 경우, 중첩 장치명 처리를 도입할 가치가 있는가
- 네트워크 경로에서 watchdog 기본값(180초)이 적절한가
