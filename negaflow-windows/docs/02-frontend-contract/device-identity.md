# 장치 식별과 재연결

기준일: 2026-08-04
기준 커밋: c554aaf
상태: 이식 정본 + Windows 재검증 필요 항목
코드 근거: `SANEBackend+Discovery.swift`(`currentDeviceAddress`,
`liveCachedSelector`, `noteDeviceOpened`, `resolveIdentity`, `sameIdentity`,
`supportsStableBackendSelector`), `SANEBackend+ScanExecution.swift`(`resolveDeviceAddress`)

관련 문서:

- [scanimage-invocation](scanimage-invocation.md)
- [usb-transport](../01-sane-runtime/usb-transport.md)
- [wire-contract](../05-protocol/wire-contract.md)

## 1. 문제

SANE 장치명은 `<backend>:<transport>:<address>` 형태다.

```text
genesys:libusb:001:002
epson2:libusb:001:005
coolscan3:usb:libusb:001:002
epson2:net:192.168.0.10
```

macOS 실측(Plustek OpticFilm 8100 + sane-backends 1.4.0, 코드 주석에 기록):

1. 장치를 **열 때마다** libusb 주소가 바뀐다. `002:001 → 002:002 → 002:001`로
   번갈아 관측됐다.
2. 목록 조회(`-L`/`-f`)만으로는 주소가 바뀌지 않는다. 목록은 장치를 열지 않는다.
3. 죽은 주소로 여는 시도는 하드웨어에 닿기 전에 즉시 실패한다(약 11 ms).
4. 호스트 USB 컨트롤러가 같은 device number를 재사용하면 이 문제가 드러나지
   않는다. 어떤 Mac에서는 재사용한다.

따라서 `detect`가 준 장치명은 **한 번 쓰면 만료될 수 있는 자원**이다.
스캔은 여러 번 장치를 열므로(옵션 덤프, RGB 패스, IR 패스, 노출 브래킷 3~12회)
주소를 그때그때 다시 얻지 못하면 두 번째 패스부터 전부 실패한다.

### 1.1 Windows에서 재확인해야 할 것

이 실측은 macOS의 IOKit/libusb 조합에서 얻었다. Windows에서는:

- libusb-1.0의 Windows 백엔드가 device address를 어떻게 부여하는지
- WinUSB 핸들을 닫고 다시 여는 사이 주소가 유지되는지
- WSL2/usbip 경로에서 재부착 시 주소가 어떻게 바뀌는지
- 네트워크(`net` 백엔드) 경로에는 이 문제가 아예 없는지

가 모두 미검증이다. **주소가 안정적이더라도 이 로직을 제거하지 않는다.**
비용은 목록 조회 한 번이고, 제거했다가 특정 컨트롤러에서 실패하면
"가끔 두 번째 패스가 실패하는" 재현 어려운 버그가 된다.
[usb-transport](../01-sane-runtime/usb-transport.md)의 spike U-3이 이 항목을 소유한다.

## 2. 선택자의 세 종류

| 종류 | 예 | 만료 | 조건 |
|---|---|---|---|
| 전체 주소 | `genesys:libusb:001:002` | open 1회 후 | 기본 |
| backend 선택자 | `genesys` | 만료 없음 | `supportsStableBackendSelector` && 그 backend 장치가 정확히 1대 && `:libusb:` 포함 |
| 캐시된 것 | 위 둘 중 하나 | 5초 TTL 또는 open | `liveCachedSelector` |

`supportsStableBackendSelector(backend)`:

```text
backend == "genesys" || backend == "epson2"
```

SANE의 dll 계층은 `-d genesys`를 backend의 **빈 장치명**으로 전달한다.
genesys와 epson2는 빈 장치명을 "첫 장치"로 처리하지만 coolscan2/3처럼
거부하는 구현이 있으므로 USB 백엔드 전체로 일반화하면 안 된다.

**Windows 이식 규칙**: 이 두 이름 목록을 확장하려면 해당 backend 소스에서
빈 장치명 처리를 확인하고 실기로 증명해야 한다. 추측으로 추가하지 않는다.

## 3. `currentDeviceAddress` 판정 알고리즘

입력: `targetDevice`(전체 장치명), `targetBackend`, `expectedIdentity`,
`allowSingleBackendSelector`, `ownedByScanSession`.

```text
0. liveCachedSelector가 있으면 즉시 반환 (목록 조회 없음)

1. listed = listDevices()

2. backendMatches  = targetBackend와 backend 이름이 같은 항목들
   exactMatch      = devname == targetDevice 인 항목
   identityMatches = backendMatches 중 expectedIdentity와 같은 identity

3. 선택:
   a) exactMatch가 있고 (identity 힌트가 없거나 identity가 일치)  → exactMatch
   b) identity 힌트가 있고 identityMatches가 정확히 1개           → 그것
   c) targetBackend가 nil이고 listed가 정확히 1개                 → 그것
   d) identity 힌트가 없고 targetBackend가 있고 backendMatches가 1개 → 그것
   e) 그 외                                                       → 실패

4. 선택 성공 시 해석:
   allowSingleBackendSelector && targetBackend가 안정 선택자 지원
   && backendMatches가 1개 && chosen.devname에 ":libusb:" 포함
       → resolvedAddress = targetBackend        (주소 없는 선택자)
   아니면
       → resolvedAddress = chosen.devname

5. 캐시 갱신 후 반환

6. 실패 시 캐시 무효화 + 오류:
   identity 힌트 있고 identityMatches > 1  → "같은 제조사·모델의 장치가 여러 대라…"
   identity 힌트 있고 backendMatches 비지 않음 → "…선택한 vendor model과 일치하지 않습니다."
   그 외                                    → "…제조사·모델 정보가 없어 안전하게 재연결할 수 없습니다."
```

### 3.1 (d) 분기가 존재하는 이유

코드 주석: 이 갈래가 없으면 open 한 번으로 주소가 바뀐 뒤 재연결이 **항상**
실패했다. 제조사·모델 힌트가 없어도 해당 backend 장치가 정확히 하나면
모호하지 않다. 장치가 둘 이상이면 계속 거부한다 — 엉뚱한 스캐너를 열지 않는다.

### 3.2 identity 비교 (`normalizedIdentityComponent`)

```text
folding(options: [caseInsensitive, diacriticInsensitive, widthInsensitive],
        locale: en_US_POSIX)
공백류로 분리 후 단일 공백으로 재결합
```

Windows 대응:

- 대소문자: 인바리언트 컬처 대문자 접기(`ToUpperInvariant`) 또는
  `CompareStringOrdinal(..., ignoreCase: true)`.
- 발음구별 기호: NFD 정규화 후 결합 문자 제거, 또는
  `LCMapStringEx(LCMAP_LINGUISTIC_CASING | NORM_IGNORENONSPACE)`.
- 전각/반각: `LCMAP_HALFWIDTH`. 일본어 Windows에서 `ＧＴ－Ｘ９８０` 같은
  전각 표기가 실제로 나올 수 있는지는 미검증이지만, macOS가 접고 있으므로
  Windows도 접는다.
- 공백 정규화: 연속 공백을 하나로.

세 접기를 다 구현하기 어렵다면 최소한 대소문자와 공백은 반드시 접고,
발음구별/전각을 접지 않는다는 사실을 문서화한다. 접기 범위가 다르면
같은 스캐너가 한쪽에서는 재연결되고 한쪽에서는 안 된다.

## 4. 캐시

```text
cachedAddress                  마지막으로 확정한 선택자
cachedAddressBackend           그때의 targetBackend
cachedAddressTarget            그때의 targetDevice
cachedAddressIdentity          그때의 expectedIdentity
cachedAddressAt                확정 시각
cachedAddressIsStableSelector  선택자에 ":"가 없으면 true
addressCacheTTL                5.0초
```

`liveCachedSelector`가 반환하는 조건:

```text
cachedAddress != nil
&& cachedAddressBackend  == targetBackend
&& cachedAddressTarget   == targetDevice
&& cachedAddressIdentity == expectedIdentity
&& (cachedAddressIsStableSelector || now - cachedAddressAt < 5.0)
```

즉 **네 키가 전부 일치해야** 한다. `nil` 대 `nil`도 일치로 본다.
Windows 구현에서 옵셔널 비교를 값 비교로 바꾸면(예: `nil`을 빈 문자열로)
서로 다른 조회가 같은 캐시를 공유하게 된다.

### 4.1 `noteDeviceOpened`

```text
cachedAddressIsStableSelector이면 아무것도 하지 않는다
아니면 캐시 전체 무효화
```

호출 시점:

- `runScanimage`의 `defer`에서, 인자에 `-d`가 있을 때(`opensDevice`).
- `runScanimageTo`의 `terminationHandler`에서 **무조건**(스캔은 언제나 장치를 연다).

이 두 곳이 전부다. Windows 구현이 호출 지점을 늘리거나 줄이면 open 횟수가
달라지고, 그것이 전용 필름 스캐너에서 실패로 나타난다.

### 4.2 `SANE_DEFAULT_DEVICE`

```text
makeSaneEnvironmentWithDefaultDevice():
    기본 환경 + (캐시가 유효하면) SANE_DEFAULT_DEVICE = 캐시된 선택자
```

목적: `scanimage -L`이 probe 없이 그 장치를 바로 열게 한다.
`noteDeviceOpened`가 만료된 주소를 이미 지우므로 죽은 주소가 주입되지 않는다.

Windows에서 이 환경 변수가 동일하게 동작하는지는 SANE 런타임 경로에 달렸다.
`net` 백엔드 경유면 의미가 다르다.
[environment-and-paths](../03-process-and-io/environment-and-paths.md) §5 참조.

## 5. `capabilityToken` 안의 identity

```text
SANECapabilitySnapshot.deviceIdentity: { vendor, model }
```

토큰에 제조사·모델을 반드시 싣는다. 이후 스캔은 주소가 바뀌어도 이 정보로
"같은 모델"임을 확인하고 재연결한다. 식별자가 비면 스캔 시점에 같은 backend의
다른 스캐너로 갈아끼워도 알아챌 수 없다.

`getCapabilitiesReport`의 identity 결정 순서:

```text
1. cachedDeviceIdentity(for: devname)
2. 호출자가 준 expectedIdentity
3. resolveIdentity(devname:backend:) — 목록을 다시 읽어
     정확 일치가 있으면 그것
     아니면 같은 backend 장치가 정확히 1대일 때만 그 identity
     아니면 nil
```

3번이 필요한 이유: capability 조회 자체가 장치를 한 번 열어 주소를
바꿔놓았을 수 있어서 이름이 정확히 맞지 않을 수 있다.

## 6. 재시도 정책 (`currentDeviceAddressWithRetry`)

```text
for attempt in 0..<3:
    currentDeviceAddress(ownedByScanSession: true) 시도
    ScannerError이고 isRetryableAddressError == false → 즉시 전파
    그 외 실패 → attempt < 2면 800 ms 대기
```

`isRetryableAddressError`:

```text
cancelled, timeout, unsupportedOption, driverConflict → false
busy, ioFailure                                       → true
notConnected, unknown → 메시지에 "여러 대라" 또는 "일치하지 않습니다"가
                        없을 때만 true
```

코드 주석: 예전에는 이런 오류에도 5번을 재시도해 스캐너에 목록 조회 폭풍을
쏟아부었다.

**이식 시 개선**: 메시지 부분 문자열 대신 오류에 구조적 이유를 실어 보낸다.

```text
enum AddressResolutionFailure {
    ambiguousMultipleDevices   // 재시도 무의미
    identityMismatch           // 재시도 무의미
    notListedYet               // 재시도 가치 있음
}
```

한국어 문자열 비교를 Windows 구현에 옮기지 않는다.

## 7. 장치 ID의 wire 계약

```text
플러그인 내부 ID: "sane-" + <SANE 장치명 전체>
호스트 라우팅 ID: "plugin:sane:" + 플러그인 내부 ID
```

즉 호스트가 보는 최종 형태는:

```text
plugin:sane:sane-genesys:libusb:001:002
```

`:`가 여러 번 등장하지만 호스트는 **처음 두 개만** 구분자로 쓴다
(`plugin` / `<pluginID>` / 나머지 전부). 이 규칙이 깨지면 SANE 장치명이
잘린다. Windows 호스트 구현에서 `split(':')` 전체 분리를 쓰면 즉시 버그다.
`split with limit 3`이어야 한다.

### 7.1 안정성 선언

현재 detect는 다음을 **항상 null로** 보고한다.

```text
usbVendorID, usbProductID, serialNumber
```

`scanimage`가 그 값을 주지 않기 때문이다. 결과적으로:

- 재연결 후 장치 ID가 달라질 수 있다(주소가 바뀌므로).
- 호스트는 이 ID를 영구 identity로 취급하면 안 된다.
- 같은 모델 두 대를 구분할 방법이 프로토콜 상에 없다.

Windows에서 SANE 런타임이 USB VID/PID를 얻을 수 있는 경로가 생기면
(예: WinUSB 장치 인스턴스 경로에서 추출) 이 필드를 채울 수 있다.
채운다면 **detect 응답에만 추가**하고 장치 ID 형식은 바꾸지 않는다.
장치 ID 형식 변경은 호스트의 승인·캐시·카탈로그에 파급된다.

## 8. 같은 모델 여러 대

현재 동작:

| 상황 | 결과 |
|---|---|
| 같은 backend, 다른 모델 2대 | identity로 구분 가능 |
| 같은 backend, 같은 모델 2대 | **거부**. "안전하게 식별할 수 없습니다" |
| 다른 backend 여러 대 | backend 이름으로 구분 |

같은 모델 2대는 명시적으로 지원하지 않는다. 이것은 결함이 아니라 결정이다 —
잘못된 스캐너를 여는 것보다 실패가 낫다. Windows도 같은 결정을 유지한다.

serial number를 얻을 수 있게 되면 이 제약을 풀 수 있다. 그 경우:

1. `PluginDevice.serialNumber`를 채운다.
2. `SANECapabilitySnapshot`에 serial을 추가하고 `schemaVersion`을 올린다.
3. identity 비교에 serial을 최우선 키로 넣는다.
4. serial이 없는 장치는 현재 동작을 유지한다.

## 9. 이식 체크리스트

- [ ] 선택 알고리즘 5갈래(a~e)를 순서대로 재현
- [ ] `supportsStableBackendSelector` 목록을 확장하지 않음
- [ ] identity 접기 범위를 문서화하고 fixture로 고정
- [ ] 캐시 4키 일치 조건(옵셔널 nil 포함)
- [ ] `noteDeviceOpened` 호출 지점 2곳만
- [ ] 재시도 판정을 문자열이 아니라 구조적 이유로
- [ ] 호스트 라우팅 ID 분리가 limit 3
- [ ] 같은 모델 2대 거부 케이스 테스트
- [ ] Windows 실기에서 open 후 장치명 변동 여부 계측 (spike U-3)
