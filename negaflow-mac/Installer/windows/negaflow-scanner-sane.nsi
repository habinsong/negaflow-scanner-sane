; negaflow-scanner-sane — Windows 설치 프로그램 (단일 실행 파일)
;
; 사용자는 이 exe 하나만 받아 실행한다. 플러그인과 SANE 런타임이 함께 들어가고
; 따로 받을 것이 없다. **관리자 권한을 요구하지 않는다** — 드라이버를 바꾸지
; 않기 때문이다. 그것이 이 제품의 전제다(runtime-route-decision §4.4b).
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

  FileClose $LogFile
  CopyFiles /SILENT "$TEMP\${LOGNAME}" "$INSTDIR\install.log"
SectionEnd

; --- 제거 -------------------------------------------------------------------
;
; NSIS 는 제거 프로그램을 $TEMP 로 복사해 거기서 돌린다. 그래서 설치 폴더를
; 통째로 옮기고 지울 수 있다.

Section "Uninstall"
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
