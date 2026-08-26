; negaflow-scanner-sane — Windows 설치 프로그램 (단일 실행 파일)
;
; 사용자는 이 exe 하나만 받아 실행한다. 플러그인과 SANE 런타임이 함께 들어가고
; 따로 받을 것이 없다. **설치 자체는 사용자 영역에만 쓰고 관리자를 요구하지 않는다.**
;
; 다만 스캐너를 여는 통로는 다르다. 플러그인은 Windows 자신의 usbscan.sys 로 장치를
; 열고(runtime-route-decision §4.4b), 그 드라이버가 스캐너에 묶여 있어야 한다. §4.4b 의
; 실측은 "Plustek 드라이버 그대로" 인 기계에서 잰 것이고, 8100 이 열렸던 것도 SilverFast 가
; 깔아 둔 INF 덕이었다 — **벤더 소프트웨어가 없는 깨끗한 PC 에는 묶어 주는 것이 없다.**
; 그래서 설치 마지막에 그 통로를 여는 단계를 두고, 그 한 단계만 권한을 올린다. 거절해도
; 설치는 그대로 남고, 벤더 드라이버로 이미 열리는 기계는 이 단계 없이도 동작한다.
;
; 빌드:
;   makensis -DPAYLOAD=<payload 경로> -DVERSION=<x.y.z> negaflow-scanner-sane.nsi
;
; 서명하지 않는다. 인증서가 없으므로 SmartScreen 경고가 뜬다 (D-1).
;
; SPDX-License-Identifier: GPL-2.0-or-later

Unicode true
ManifestDPIAware true
SetCompressor /SOLID lzma

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"

!ifndef PAYLOAD
  !error "PAYLOAD 를 달라: makensis -DPAYLOAD=<경로>"
!endif
!ifndef VERSION
  !define VERSION "0.0.0"
!endif

!define APPNAME  "negaflow SANE Scanner"
!define PLUGINID "sane"
!define EXENAME  "negaflow-scanner-sane.exe"
!define REGKEY   "Software\Microsoft\Windows\CurrentVersion\Uninstall\negaflow-scanner-sane"
!define LOGNAME  "negaflow-scanner-sane-install.log"
!define APP_ICON "${__FILEDIR__}\..\..\..\negaflow-windows\src\app\Negaflow.ico"

Name        "${APPNAME}"
OutFile     "negaflow-scanner-sane-${VERSION}-x64-setup.exe"
Icon        "${APP_ICON}"
UninstallIcon "${APP_ICON}"
; Negaflow Windows discovers user plug-ins below `Plugins`, matching the
; macOS product contract.  Keep this separate from the Apache-2.0 app payload.
InstallDir  "$LOCALAPPDATA\Negaflow\Plugins\${PLUGINID}"

; 사용자 영역에만 쓴다. 상승을 요구하면 드라이버를 바꾸지 않는다는 약속이
; 무색해지고, 관리자가 아닌 사용자는 설치 자체를 못 한다.
RequestExecutionLevel user

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName"     "${APPNAME}"
VIAddVersionKey "FileDescription" "negaflow scanner plugin (SANE)"
VIAddVersionKey "FileVersion"     "${VERSION}"
VIAddVersionKey "ProductVersion"  "${VERSION}"
VIAddVersionKey "LegalCopyright"  "GPL-2.0-or-later"

; --- 화면 -------------------------------------------------------------------

!define MUI_ABORTWARNING
; GPL 바이너리를 배포하므로 전문을 보여준다.
!define MUI_LICENSEPAGE_TEXT_BOTTOM "이 소프트웨어는 GPL-2.0-or-later 로 배포됩니다. 대응 소스는 설치 폴더의 source\ 에 함께 들어갑니다."

!insertmacro MUI_PAGE_LICENSE "${PAYLOAD}\LICENSES\COPYING"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Korean"
!insertmacro MUI_LANGUAGE "English"

; --- 기록 -------------------------------------------------------------------
;
; 설치가 실패했다는 신고를 받았을 때 물어볼 것이 없으면 아무것도 못 한다.
; 실패해도 남도록 $TEMP 에 쓰고, 성공하면 설치 폴더로 옮긴다.

Var LogFile

!macro LOG text
  FileWrite $LogFile "${text}$\r$\n"
!macroend
!define LOG "!insertmacro LOG"

; 무인 모드에서는 절대 창을 띄우지 않는다. `/S` 로 돌린 설치가 사람을
; 기다리며 멈추면 배포 스크립트가 통째로 멎는다. 무인 모드의 결과는 종료
; 코드와 로그로만 말한다.
!macro SAY icon text
  ${If} ${Silent}
  ${Else}
    MessageBox ${icon} "${text}"
  ${EndIf}
!macroend
!define SAY "!insertmacro SAY"

; --- 설치 -------------------------------------------------------------------

Var Staging
Var Backup
Var MovedAside

Function .onInit
  ; scanimage.exe 와 백엔드는 x64 다. ARM64 에서는 에뮬레이션으로 돌지만
  ; USB 계층을 확인한 적이 없으므로 조용히 넘기지 않는다.
  ${If} ${RunningX64}
  ${Else}
    ${SAY} MB_ICONSTOP "이 패키지는 64비트 Windows 전용입니다."
    SetErrorLevel 1
    Abort
  ${EndIf}
FunctionEnd

Section "설치"
  FileOpen $LogFile "$TEMP\${LOGNAME}" w
  ${LOG} "negaflow-scanner-sane ${VERSION} x64"
  ${LOG} "대상: $INSTDIR"

  StrCpy $MovedAside "0"
  StrCpy $Staging "$INSTDIR.staging"
  StrCpy $Backup  "$INSTDIR.previous"

  DetailPrint "SANE 런타임을 함께 설치합니다. 관리자 권한은 필요하지 않습니다."

  RMDir /r "$Staging"
  RMDir /r "$Backup"

  ; ① 새것을 옆에 완성한다. 여기까지 실패해도 기존 설치는 그대로다.
  SetOutPath "$Staging"
  File /r "${PAYLOAD}\*.*"
  ; SetOutPath 는 프로세스의 현재 디렉터리도 거기로 옮긴다. 그대로 두면 ③ 의
  ; Rename 이 "현재 디렉터리는 이름을 못 바꾼다"로 조용히 실패한다 — 실측:
  ; staging 만 남고 설치가 0개 파일로 끝났다.
  SetOutPath "$TEMP"
  ${LOG} "① 새 파일을 $Staging 에 풀었다"

  ; ② 기존을 옆으로 치운다. 실행 중이면 파일이 잠겨 rename 이 실패하므로,
  ;    이 단계가 곧 "실행 중인가" 검사다. 따로 프로세스를 뒤지지 않는다.
  ${If} ${FileExists} "$INSTDIR\*.*"
    ClearErrors
    Rename "$INSTDIR" "$Backup"
    ${If} ${Errors}
      ${LOG} "② 기존 설치를 치우지 못했다 — 실행 중으로 본다"
      FileClose $LogFile
      RMDir /r "$Staging"
      ${SAY} MB_ICONSTOP "기존 설치를 교체할 수 없습니다. negaflow 를 닫고 다시 시도하십시오."
      Abort "설치를 중단했습니다."
    ${EndIf}
    StrCpy $MovedAside "1"
    ${LOG} "② 기존 설치를 $Backup 으로 치웠다"
  ${EndIf}

  ; ③ 새것을 제자리에.
  ClearErrors
  Rename "$Staging" "$INSTDIR"
  ${If} ${Errors}
    RMDir /r "$Staging"
    ${If} $MovedAside == "1"
      Rename "$Backup" "$INSTDIR"
      ${LOG} "③ 실패 — 이전 상태로 되돌렸다"
      DetailPrint "설치에 실패해 이전 상태로 되돌렸습니다."
    ${Else}
      ${LOG} "③ 실패"
    ${EndIf}
    FileClose $LogFile
    Abort "설치에 실패했습니다."
  ${EndIf}
  ${LOG} "③ 제자리로 옮겼다"

  RMDir /r "$Backup"

  ; --- 제거 정보 ---
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegStr   HKCU "${REGKEY}" "DisplayName"     "${APPNAME}"
  WriteRegStr   HKCU "${REGKEY}" "DisplayVersion"  "${VERSION}"
  WriteRegStr   HKCU "${REGKEY}" "Publisher"       "negaflow"
  WriteRegStr   HKCU "${REGKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr   HKCU "${REGKEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr   HKCU "${REGKEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegStr   HKCU "${REGKEY}" "DisplayIcon"     '"$INSTDIR\${EXENAME}"'
  WriteRegDWORD HKCU "${REGKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${REGKEY}" "NoRepair" 1
  WriteRegDWORD HKCU "${REGKEY}" "EstimatedSize" $0
  ${LOG} "제거 정보를 등록했다 ($0 KB)"

  ; --- 확인 ---
  ; 설치했다고 말하기 전에 실제로 도는지 본다. 스캐너가 없어도 플러그인은
  ; 빈 목록을 내고 정상 종료해야 한다. 여기서 걸리는 대표적인 실패가 의존
  ; DLL 누락이고, 그것은 개발 기계에서는 PATH 때문에 안 보인다.
  nsExec::ExecToStack '"$INSTDIR\${EXENAME}" detect'
  Pop $0
  Pop $1
  ${If} $0 != 0
    ${LOG} "확인 실패 (종료 코드 $0): $1"
    FileClose $LogFile
    CopyFiles /SILENT "$TEMP\${LOGNAME}" "$INSTDIR\install.log"
    DetailPrint "확인 실패: $1"
    ${SAY} MB_ICONSTOP "설치는 됐지만 플러그인이 동작하지 않습니다 (종료 코드 $0).$\n$\n$1"
    Abort "설치 후 확인에 실패했습니다."
  ${EndIf}
  ${LOG} "확인 완료: $1"
  DetailPrint "확인 완료: 플러그인이 동작합니다."

  ; --- 스캐너 통로 ---
  ;
  ; 플러그인은 Windows 자신의 usbscan.sys 를 통해 장치를 연다. 그 드라이버가 스캐너에
  ; 묶여 있어야 하는데, **깨끗한 PC 에는 묶어 주는 것이 없다.** §4.4b 의 실측은
  ; "Plustek 드라이버 그대로" 인 기계에서 잰 것이고, 8100 이 열렸던 것도 SilverFast 가
  ; 깔아 둔 INF 덕이었다. 벤더 소프트웨어가 없는 기계에서는 여기까지 와도 장치가 없다.
  ;
  ; 통로를 여는 일은 드라이버 설치라 관리자가 필요하다. **설치 자체는 사용자 영역
  ; 그대로 두고 이 한 단계만 올린다** - 관리자가 아닌 사용자도 설치는 할 수 있어야 하고,
  ; 벤더 드라이버로 이미 열리는 기계는 이 단계 없이도 동작한다. 거절해도 설치는 남는다.
  ${If} ${Silent}
    ${LOG} "무인 모드: 스캐너 통로 열기를 건너뛴다 (관리자 확인을 띄울 수 없다)"
    DetailPrint "무인 모드: 스캐너 통로 열기를 건너뜁니다."
  ${Else}
    MessageBox MB_YESNO|MB_ICONQUESTION "스캐너를 연결할 통로를 지금 엽니다.$\n$\n스캐너를 Windows 의 usbscan 드라이버에 묶는 단계이며 관리자 확인이 필요합니다. 건너뛰면 스캐너 제조사 소프트웨어가 이미 깔린 기계에서만 인식됩니다.$\n$\n지금 열까요?" /SD IDYES IDNO SkipUsbScanBind
    DetailPrint "스캐너 통로를 엽니다 (관리자 확인)."
    ClearErrors
    ExecShellWait "runas" "$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" '-NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\usbscan-bind\install.ps1"' SW_SHOWNORMAL
    ${If} ${Errors}
      ${LOG} "스캐너 통로 열기를 건너뛰었다 (관리자 확인 거절 또는 실행 실패)"
      DetailPrint "스캐너 통로를 열지 못했습니다. 나중에 usbscan-bind\install.ps1 을 관리자로 실행하십시오."
    ${Else}
      ${LOG} "스캐너 통로 열기를 실행했다"
      ; 열렸는지는 말이 아니라 목록으로 확인한다.
      nsExec::ExecToStack '"$INSTDIR\${EXENAME}" detect'
      Pop $0
      Pop $1
      ${LOG} "통로를 연 뒤 detect (종료 코드 $0): $1"
      DetailPrint "통로를 연 뒤 장치 목록: $1"
    ${EndIf}
    SkipUsbScanBind:
  ${EndIf}

  FileClose $LogFile
  CopyFiles /SILENT "$TEMP\${LOGNAME}" "$INSTDIR\install.log"
SectionEnd

; --- 제거 -------------------------------------------------------------------
;
; NSIS 는 제거 프로그램을 $TEMP 로 복사해 거기서 돌린다. 그래서 설치 폴더를
; 통째로 옮기고 지울 수 있다.

Section "Uninstall"
  ; 통로를 열었다면 되돌린다. 드라이버를 남기면 제거한 뒤에도 우리가 깔아 둔 것이
  ; 계속 스캐너를 잡고, 자체 서명 인증서가 신뢰 저장소에 영영 남는다. 지우면 Windows 가
  ; 남아 있는 최선의 드라이버(벤더 INF 등)로 되돌아간다.
  ${If} ${Silent}
  ${Else}
    ${If} ${FileExists} "$INSTDIR\usbscan-bind\install.ps1"
      MessageBox MB_YESNO|MB_ICONQUESTION "설치할 때 연 스캐너 통로도 함께 되돌립니다.$\n$\n관리자 확인이 필요합니다. 건너뛰면 통로는 그대로 남습니다.$\n$\n지금 되돌릴까요?" /SD IDNO IDNO SkipUsbScanUnbind
      ExecShellWait "runas" "$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" '-NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\usbscan-bind\install.ps1" -Uninstall -RemoveCertificate' SW_SHOWNORMAL
      SkipUsbScanUnbind:
    ${EndIf}
  ${EndIf}

  ; 제거도 실행 중이면 실패한다. 조용히 반쯤 지우지 않는다.
  ClearErrors
  Rename "$INSTDIR" "$INSTDIR.removing"
  ${If} ${Errors}
    ${SAY} MB_ICONSTOP "제거할 수 없습니다. negaflow 를 닫고 다시 시도하십시오."
    Abort "제거를 중단했습니다."
  ${EndIf}

  RMDir /r "$INSTDIR.removing"
  DeleteRegKey HKCU "${REGKEY}"

  ; 우리가 만든 상위 폴더는 비었을 때만 지운다.
  RMDir "$LOCALAPPDATA\Negaflow\Plugins"
  RMDir "$LOCALAPPDATA\Negaflow"
SectionEnd
