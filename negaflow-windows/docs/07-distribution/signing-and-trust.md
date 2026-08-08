# 서명과 신뢰

기준일: 2026-08-04
상태: 설계
관련 문서:

- [packaging-and-install](packaging-and-install.md)
- [gpl-compliance](gpl-compliance.md)
- [wire-contract](../05-protocol/wire-contract.md)

## 1. 현재 macOS

```text
codesign --force --options runtime --timestamp
         --sign "Developer ID Application: ..."
         --entitlements Config/Plugin.entitlements
codesign --verify --strict --verbose=2
codesign -dv --verbose=4 | grep runtime         hardened runtime 확인
xcrun notarytool submit --wait                  공증
spctl --assess --type execute --verbose=4       Gatekeeper 평가
```

`Config/Plugin.entitlements`는 **빈 dict**다. 어떤 권한도 요구하지 않는다.

단독 실행 파일에는 티켓을 staple할 수 없으므로 온라인 티켓을 Gatekeeper가
조회한다.

PKG는 `Developer ID Installer` 인증서로 별도 서명한다.

## 2. Windows 대응

| macOS | Windows |
|---|---|
| Developer ID Application | Authenticode 코드 서명 인증서 |
| Developer ID Installer | 같은 인증서 (MSI도 Authenticode) |
| notarization | **대응 없음** |
| Gatekeeper | SmartScreen |
| entitlements | **대응 없음** (매니페스트는 별개) |
| hardened runtime | **대응 없음** (완화 정책은 별개) |
| `--timestamp` | RFC 3161 타임스탬프 |
| `spctl --assess` | `WinVerifyTrust` |

## 3. 인증서

### 3.1 종류

| 종류 | SmartScreen | 비용 | 요건 |
|---|---|---|---|
| OV (Organization Validation) | 평판 축적 필요 | 낮음 | 조직 검증 |
| EV (Extended Validation) | **즉시 신뢰** | 높음 | 조직 검증 + 하드웨어 토큰 |

**2023년 6월부터 OV/EV 모두 하드웨어 보안 모듈(HSM) 또는 하드웨어 토큰에
키를 보관해야 한다**(CA/Browser Forum 요건). 즉 CI에서 자동 서명하려면
클라우드 HSM 기반 서명 서비스가 필요하다.

옵션:

- Azure Trusted Signing (구 Azure Code Signing)
- DigiCert KeyLocker / ONE
- SSL.com eSigner
- 자체 HSM + 서명 서버

**Azure Trusted Signing이 CI 통합이 가장 쉽다.** GitHub Actions 액션이 있다.

### 3.2 개인 개발자

이 프로젝트는 개인 개발자(`habin song`)의 것으로 보인다.
Azure Trusted Signing은 개인 개발자 계정을 지원하지만
"3년 이상 활동한 법적 실체" 요건이 있을 수 있다(정책 변동).

**확인 필요** → spike D-1.

서명하지 못하면:

- SmartScreen이 "알 수 없는 게시자" 경고를 낸다
- 사용자가 "추가 정보 → 실행"을 눌러야 한다
- **negaflow 호스트가 서명을 요구할 수 있다**

마지막이 결정적이다. negaflow 본체 windows_docs
`10-scanner/plugin-security-and-lifecycle.md`가 Authenticode signer
thumbprint를 신뢰 identity에 포함할 수 있다고 적는다.

**호스트가 서명을 필수로 요구하는지 확인해야 한다.** 필수면 서명 없이는
Windows 지원이 불가능하다.

## 4. 서명 대상

```text
negaflow-scanner-sane.exe          필수
bind-scanner-driver.exe            필수 (권한 상승 요구)
negaflow-scanner-sane-<ver>.msi    필수
```

### 4.1 SANE 런타임 DLL은?

```text
scanimage.exe
libsane-1.dll
libsane-*.dll
libusb-1.0.dll
MinGW 런타임 DLL
```

**서명할 것인가?**

| 안 | 내용 |
|---|---|
| A | 전부 서명한다 |
| B | 서명하지 않는다 |
| C | `scanimage.exe`만 서명한다 |

**고려사항**:

- 이것들은 GPL 소프트웨어이며 우리가 빌드했다. 서명하는 것은
  "우리가 이 바이너리를 만들었다"는 진술이며 정확하다.
- 서명하면 SmartScreen 경고가 줄고 사용자가 파일을 신뢰할 근거가 생긴다.
- 서명하면 우리가 그 코드의 보증을 하는 것처럼 보일 수 있다.
  GPL의 무보증 조항과 충돌하지는 않지만 오해를 부를 수 있다.
- 서명 비용은 파일당이 아니라 시간당이므로 개수는 문제가 아니다.

```text
D-23  SANE 런타임 바이너리 전체를 서명한다.
      릴리스 노트와 THIRD_PARTY_NOTICES.md에
      "우리가 빌드했고 서명했다. 무보증이다"를 명시한다.
```

**MinGW 런타임 DLL은 우리가 만들지 않았다.** MSYS2에서 가져온 것이면
재서명이 부적절할 수 있다. 재빌드에서 정적 링크하거나, 서명하지 않고
그대로 둔다.

### 4.2 서명하지 않는 것

```text
PDB 파일          (서명 대상 아님)
소스 아카이브     (해시로 검증)
설정 파일         (.conf)
문서
```

## 5. 서명 절차

```powershell
signtool sign `
    /fd SHA256 `
    /tr http://timestamp.digicert.com `
    /td SHA256 `
    /a `
    negaflow-scanner-sane.exe

signtool verify /pa /v negaflow-scanner-sane.exe
```

**타임스탬프가 필수다.** 인증서가 만료돼도 서명이 유효하게 유지된다.

### 5.1 macOS 스크립트 대응

`scripts/sign-plugin.sh`가 하는 검증을 대응시킨다.

| macOS 검사 | Windows 대응 |
|---|---|
| 실행 파일 존재 | 동일 |
| `Developer ID Application:` 접두사 확인 | 인증서 subject 확인 |
| Keychain에 인증서 존재 | 인증서 저장소 또는 HSM 접근 확인 |
| `--verify --strict` | `signtool verify /pa` |
| hardened runtime 플래그 확인 | **대응 없음** |
| — | 타임스탬프 존재 확인 (신규) |
| — | 체인 검증 (신규) |

```powershell
# 타임스탬프 확인
$sig = Get-AuthenticodeSignature "negaflow-scanner-sane.exe"
if (-not $sig.TimeStamperCertificate) { throw "타임스탬프가 없습니다" }
if ($sig.Status -ne "Valid") { throw "서명이 유효하지 않습니다: $($sig.Status)" }
```

## 6. SmartScreen

Authenticode 서명이 있어도 **평판이 축적되기 전에는 경고가 나온다**
(OV 인증서). EV는 즉시 신뢰된다.

평판은 다음으로 쌓인다:

- 같은 인증서로 서명된 파일의 다운로드 수
- Microsoft에 보고된 악성 판정 없음
- 시간

**초기 릴리스에서 경고가 나오는 것을 문서에 미리 적는다.**

```text
설치 프로그램을 실행하면 Windows가 "PC 보호" 경고를 표시할 수 있습니다.
"추가 정보"를 누르고 게시자가 <이름>인지 확인한 뒤 "실행"을 누르십시오.

파일의 SHA-256:
  negaflow-scanner-sane-1.0.3-win-x64.msi
  <해시>
```

**해시를 공개하는 것이 중요하다.** 사용자가 검증할 수 있다.

## 7. 호스트의 신뢰 모델

negaflow 본체 windows_docs가 정의하는 identity:

```text
plugin ID
plugin version
manifest SHA-256
executable SHA-256
+ Authenticode signer thumbprint (Windows 추가 후보)
+ executable file ID + volume serial
+ architecture
+ approval timestamp
```

**어댑터가 할 일**:

1. 매니페스트와 실행 파일이 설치 후 변경되지 않게 한다.
2. 서명이 유효하게 유지되게 한다.
3. 업데이트 시 해시가 바뀌므로 재승인이 필요함을 안내한다.

**어댑터가 하지 않을 일**:

- 자기 서명을 검증하지 않는다(호스트의 일).
- 승인 상태를 저장하지 않는다.

### 7.1 SANE 런타임의 무결성

호스트는 `negaflow-scanner-sane.exe`의 해시만 본다.
`scanimage.exe`와 백엔드 DLL은 **검증 범위 밖**이다.

즉 공격자가 `sane\bin\scanimage.exe`를 바꿔치기하면 승인된 플러그인이
공격자 코드를 실행한다.

**완화**:

```text
1. 설치 디렉터리 ACL을 좁게 유지한다 (사용자만 쓰기)
2. 어댑터가 실행 전에 scanimage.exe의 서명을 검증한다  ← 신규
3. 어댑터가 예상 해시를 내장하고 확인한다              ← 대안
```

2번을 권장한다.

```text
CreateProcessW 전에:
    WinVerifyTrust로 scanimage.exe 서명 확인
    signer가 우리 인증서인지 확인
    실패하면 진단에 기록하고 계속할지 결정
```

**"실패하면 계속할지"가 결정 사항이다.**

- 거부하면: 사용자가 자기 SANE를 쓸 수 없다
  (`NEGAFLOW_SCANIMAGE_PATH`가 무력화된다)
- 허용하면: 검증의 의미가 약해진다

```text
D-24  번들된 scanimage.exe(설치 디렉터리 안)는 서명을 검증하고
      실패하면 거부한다.
      NEGAFLOW_SCANIMAGE_PATH나 사용자 지정 경로의 scanimage는
      검증하지 않되, 진단과 결과 warnings에 그 사실을 남긴다.
```

warnings 예:

```text
"Using an unverified SANE runtime at <경로>. This build was not
 provided by the plug-in installer."
```

호스트가 이것을 사용자에게 보여준다.

## 8. DLL 하이재킹 방어

`scanimage.exe`가 `libsane-1.dll`을 로드한다. 검색 경로에 공격자가
쓸 수 있는 디렉터리가 있으면 위험하다.

**방어**:

1. 설치 디렉터리 ACL (§7.1)
2. **현재 작업 디렉터리를 제어한다.** `CreateProcessW`의
   `lpCurrentDirectory`를 설치 디렉터리로 명시한다.
   기본값(부모의 CWD)을 상속하면 공격자가 제어하는 디렉터리일 수 있다.
3. 자식의 `PATH`에 신뢰할 수 없는 디렉터리를 앞에 넣지 않는다
4. 가능하면 백엔드 DLL을 `scanimage.exe`와 같은 디렉터리에 둔다
   (검색 순서 3번, 가장 이른 시점)

```text
CreateProcessW(..., lpCurrentDirectory: <플러그인>\sane\bin, ...)
```

## 9. 권한 상승

`bind-scanner-driver.exe`는 관리자 권한이 필요하다.

```xml
<!-- 매니페스트 -->
<requestedExecutionLevel level="requireAdministrator" uiAccess="false" />
```

`negaflow-scanner-sane.exe`는 **절대 권한 상승을 요구하지 않는다.**

```xml
<requestedExecutionLevel level="asInvoker" uiAccess="false" />
```

호스트가 사용자 권한으로 실행하고, 그것으로 충분해야 한다.
macOS에서 `sudo`가 필요 없다는 것이 README에 명시돼 있는 것과 같은 원칙이다.

## 10. 실행 파일 매니페스트

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity type="win32" name="negaflow-scanner-sane"
                    version="1.0.3.0" processorArchitecture="*"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <!-- 지원하는 Windows 버전 GUID -->
    </application>
  </compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <activeCodePage xmlns="http://schemas.microsoft.com/SMI/2019/WindowsSettings">UTF-8</activeCodePage>
      <longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>
    </windowsSettings>
  </application>
</assembly>
```

**`activeCodePage: UTF-8`이 유용하다.** ANSI API가 UTF-8을 쓰게 해
인코딩 문제가 줄어든다. 단 Windows 10 1903 이상이 필요하다.

**`longPathAware`**: 호스트 staging 경로가 260자를 넘을 수 있다.
켜두는 것이 안전하다. 단 이것만으로는 부족하고 레지스트리 정책도
필요하다는 점을 문서화한다.

## 11. 릴리스 검증

```powershell
# 서명
signtool verify /pa /v negaflow-scanner-sane.exe
signtool verify /pa /v sane\bin\scanimage.exe
signtool verify /pa /v negaflow-scanner-sane-1.0.3-win-x64.msi

# 타임스탬프
Get-AuthenticodeSignature ... | ForEach { $_.TimeStamperCertificate }

# 아키텍처
(Get-Item negaflow-scanner-sane.exe).VersionInfo   # 참고용
# PE 헤더 machine type 직접 확인

# import table
dumpbin /imports negaflow-scanner-sane.exe | findstr /i sane   # 비어야 함

# 권한 상승 요구 없음
mt.exe -inputresource:negaflow-scanner-sane.exe;#1 -out:manifest.xml
# requestedExecutionLevel이 asInvoker인지 확인
```

## 12. spike

### D-1 — 서명 인증서 확보 가능성

```text
1. Azure Trusted Signing의 개인 개발자 자격 요건 확인
2. 대안 CA의 요건과 비용
3. HSM/토큰 없이 CI에서 서명할 수 있는 경로
4. negaflow 호스트가 서명을 필수로 요구하는지 확인
```

**4번이 가장 중요하다.** 필수면 D-1이 gate가 된다.

### D-2 — SmartScreen 동작

```text
서명된 MSI를 새 Windows 설치에서 실행
경고가 나오는가? 어떤 문구인가?
```

### D-3 — `activeCodePage: UTF-8`의 영향

```text
UTF-8 활성 코드 페이지에서:
- 자식 프로세스의 환경 변수 인코딩
- 파일 경로 처리
- 콘솔 출력
가 예상대로 동작하는가
```

## 13. 체크리스트

- [ ] 어댑터 exe 서명 + 타임스탬프
- [ ] MSI 서명
- [ ] SANE 런타임 서명 (D-23)
- [ ] `asInvoker` 권한 수준
- [ ] `activeCodePage: UTF-8`
- [ ] `longPathAware`
- [ ] `lpCurrentDirectory` 명시
- [ ] 번들 scanimage 서명 검증 (D-24)
- [ ] 사용자 지정 scanimage에 warning
- [ ] 설치 디렉터리 ACL
- [ ] import table에 sane 없음
- [ ] 릴리스 해시 공개
- [ ] SmartScreen 경고를 문서에 미리 안내

## 14. 열린 질문

- 서명 인증서를 확보할 수 있는가 (D-1)
- 호스트가 서명을 필수로 요구하는가
- MinGW 런타임 DLL을 재서명하는 것이 적절한가
- 서명 실패 시 Windows 지원을 어떻게 할 것인가
