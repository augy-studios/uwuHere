; uwuHere's Windows installer (docs/desktop-features-spec.md §16, docs/flutter-desktop-app-spec.md
; §10): per user, no admin, asking where to install (by default %LOCALAPPDATA%\Programs\uwuHere,
; or wherever an earlier install went), with the x64 and Arm64 apps in one file, installing the
; one this PC runs. It closes a running copy first, clears the folder, installs, writes
; "Uninstall uwuHere.exe" (which the app's updater looks for), Start menu and desktop shortcuts,
; and registers uwu:// links.
;
; Each version installs over the last in place: the same file name, folder, uninstaller name,
; install-location key and uninstall entry (both under uwuHere's own GUID, below, which never
; changes), and clearing the folder first takes the old version's files away.
;
; Honours /S (silent), --updated (an update: no shortcuts made again on the desktop) and
; --force-run (open the app when done), as the app's updater passes them (lib/desktop/updater.dart).
;
; Built by .github/workflows/build-desktop.yml:
;   makensis -DVERSION=2.0.0 -DX64=<x64 Release folder> [-DARM64=<arm64 Release folder>] -DOUT=<file> uwuhere.nsi

Unicode true
!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"

!ifndef VERSION
  !error "Pass /DVERSION=x.y.z"
!endif
!ifndef X64
  !error "Pass /DX64=<the x64 build's Release folder>"
!endif
!ifndef OUT
  !define OUT "uwuhere-${VERSION}-setup.exe"
!endif

!define APP "uwuHere"
!define EXE "uwuHere.exe"
!define AUMID "org.uwuapps.here"
; uwuHere's own, made for 2.0.0 and never changed: the uninstall entry and install location hang on it.
!define APP_GUID "7ef91d96-2604-4e9a-ad76-b2e80459dea6"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_GUID}"
!define INSTALL_KEY "Software\${APP_GUID}"

Name "${APP}"
OutFile "${OUT}"
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\Programs\${APP}"
InstallDirRegKey HKCU "${INSTALL_KEY}" "InstallLocation"
SetCompressor /SOLID lzma
BrandingText "${APP} ${VERSION}"
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "CompanyName" "Augy Studios"
VIAddVersionKey "FileDescription" "${APP} installer"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "MIT licence"

!define MUI_ICON "${X64}\data\flutter_assets\assets\images\tray.ico"
!define MUI_UNICON "${X64}\data\flutter_assets\assets\images\tray.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Open ${APP}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Var Updated
Var ForceRun

Function .onInit
  ${GetParameters} $0
  ClearErrors
  ${GetOptions} $0 "--updated" $1
  ${IfNot} ${Errors}
    StrCpy $Updated 1
  ${EndIf}
  ClearErrors
  ${GetOptions} $0 "--force-run" $1
  ${IfNot} ${Errors}
    StrCpy $ForceRun 1
  ${EndIf}
FunctionEnd

Section "Install"
  ; A running copy lets go of its files first.
  nsExec::Exec 'taskkill /IM "${EXE}" /F'
  Sleep 800

  ; The folder emptied, so files from an earlier build don't linger.
  RMDir /r "$INSTDIR"
  SetOutPath "$INSTDIR"

!ifdef ARM64
  ${If} ${IsNativeARM64}
    File /r "${ARM64}\*.*"
  ${Else}
    File /r "${X64}\*.*"
  ${EndIf}
!else
  File /r "${X64}\*.*"
!endif

  WriteUninstaller "$INSTDIR\Uninstall ${APP}.exe"
  WriteRegStr HKCU "${INSTALL_KEY}" "InstallLocation" "$INSTDIR"

  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "Augy Studios"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${EXE}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall ${APP}.exe"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall ${APP}.exe" /S'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "URLInfoAbout" "https://here.uwuapps.org"
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "EstimatedSize" $0

  ; uwu:// links (the app takes the scheme over at every start too, noting a sibling app's).
  WriteRegStr HKCU "Software\Classes\uwu" "" "URL:UwU Apps link"
  WriteRegStr HKCU "Software\Classes\uwu" "URL Protocol" ""
  WriteRegStr HKCU "Software\Classes\uwu\shell\open\command" "" '"$INSTDIR\${EXE}" "%1"'

  CreateShortCut "$SMPROGRAMS\${APP}.lnk" "$INSTDIR\${EXE}"
  ${If} $Updated != 1
    CreateShortCut "$DESKTOP\${APP}.lnk" "$INSTDIR\${EXE}"
  ${EndIf}

  ${If} $ForceRun == 1
    Exec '"$INSTDIR\${EXE}"'
  ${EndIf}
SectionEnd

Section "Uninstall"
  nsExec::Exec 'taskkill /IM "${EXE}" /F'
  Sleep 500
  Delete "$SMPROGRAMS\${APP}.lnk"
  Delete "$DESKTOP\${APP}.lnk"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  DeleteRegKey HKCU "${INSTALL_KEY}"
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "${APP}"
  ; The scheme only if it's still this app's.
  ReadRegStr $0 HKCU "Software\Classes\uwu\shell\open\command" ""
  ${If} $0 == '"$INSTDIR\${EXE}" "%1"'
    DeleteRegKey HKCU "Software\Classes\uwu"
  ${EndIf}
  RMDir /r "$INSTDIR"
SectionEnd
