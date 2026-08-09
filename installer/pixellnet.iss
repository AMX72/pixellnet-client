; PIXELLNET Windows installer — Inno Setup script.
; Compiled in CI via ISCC.exe with /DAppVersion=X.Y.Z /DSourceDir=... /DOutputDir=...
;
; Result: pixellnet-setup-<AppVersion>.exe (~50MB, LZMA-compressed).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir ".."
#endif

#define AppName "PIXELLNET"
#define AppExecutable "pixellnet.exe"
#define AppPublisher "PIXELLNET"
#define AppPublisherURL "https://pixellnet.com"
#define AppId "{{A3F12B74-9C2E-4D81-B507-CF882E14A93D}"

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppPublisherURL}
AppSupportURL={#AppPublisherURL}
AppUpdatesURL={#AppPublisherURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableWelcomePage=no
OutputDir={#OutputDir}
OutputBaseFilename=pixellnet-setup-{#AppVersion}
Compression=lzma
SolidCompression=yes
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExecutable}
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=force
RestartApplications=no
UsedUserAreasWarning=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce
Name: "startupicon"; Description: "Запускать PIXELLNET при входе в Windows"; GroupDescription: "Автозапуск:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExecutable}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExecutable}"; Tasks: desktopicon
Name: "{userstartup}\{#AppName}"; Filename: "{app}\{#AppExecutable}"; WorkingDir: "{app}"; Tasks: startupicon
Name: "{app}\Удалить {#AppName}"; Filename: "{uninstallexe}"

[Registry]
; Deep-link scheme pixellnet:// (для реферальных ссылок и import-config)
Root: HKCR; Subkey: "pixellnet"; ValueType: string; ValueName: ""; ValueData: "URL:PIXELLNET Protocol"; Flags: uninsdeletekey
Root: HKCR; Subkey: "pixellnet"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCR; Subkey: "pixellnet\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExecutable},0"
Root: HKCR; Subkey: "pixellnet\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExecutable}"" ""%1"""

[UninstallDelete]
; Оставляем %APPDATA%\PixellNet — юзерские настройки/логи/подписка сохраняются.
; При полной чистке юзер удалит вручную.
Type: filesandordirs; Name: "{app}"

[Code]
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  // Убить запущенный pixellnet.exe перед установкой (иначе Windows Explorer lock файлы)
  Exec('taskkill.exe', '/F /IM pixellnet.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // Удалить stale WinTUN adapter от предыдущего instance (v0.1.37 fix)
  Exec('powershell.exe', '-NoProfile -NonInteractive -Command "Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object InterfaceDescription -like ''*sing-tun*'' | Where-Object Name -ne ''happ-tun'' | Remove-NetAdapter -Confirm:$false -ErrorAction SilentlyContinue"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := True;
end;

[Run]
Filename: "{app}\{#AppExecutable}"; Description: "Запустить {#AppName} сейчас"; Flags: nowait postinstall skipifsilent runascurrentuser
