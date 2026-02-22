#ifndef RepoRoot
  #define RepoRoot "..\..\.."
#endif

#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif

#define MyAppName "Rex Language"
#define MyAppPublisher "Rex Team"
#ifdef LuaExe
  #define LuaDir ExtractFilePath(LuaExe)
#endif

[Setup]
AppId={{0D9DDA9A-9F6E-48AF-9D6D-78674F5515E4}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\RexLang
DefaultGroupName=Rex Language
OutputDir={#RepoRoot}\dist\windows
OutputBaseFilename=rex-{#MyAppVersion}-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
WizardImageFile={#RepoRoot}\rex.png
WizardSmallImageFile={#RepoRoot}\rex.png
WizardImageStretch=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesInstallIn64BitMode=x64compatible
ChangesEnvironment=yes
SetupLogging=yes
UninstallDisplayIcon={app}\rex.png
UsePreviousLanguage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "chinese"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "portuguese"; MessagesFile: "compiler:Languages\Portuguese.isl"

[Tasks]
Name: "addtopath"; Description: "Add Rex command to PATH"; GroupDescription: "Environment:"; Flags: checkedonce
Name: "desktopicon"; Description: "Create desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#RepoRoot}\rex\compiler\*"; DestDir: "{app}\rex\compiler"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RepoRoot}\rex\runtime_c\*"; DestDir: "{app}\rex\runtime_c"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RepoRoot}\rex\examples\*"; DestDir: "{app}\rex\examples"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RepoRoot}\rex.png"; DestDir: "{app}"; Flags: ignoreversion
#ifdef LuaExe
Source: "{#LuaExe}"; DestDir: "{app}\lua"; DestName: "lua.exe"; Flags: ignoreversion
Source: "{#LuaDir}lua*.dll"; DestDir: "{app}\lua"; Flags: ignoreversion skipifsourcedoesntexist
#endif

[Icons]
Name: "{group}\Rex Console"; Filename: "{app}\bin\rex.cmd"
Name: "{group}\Uninstall Rex"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Rex Console"; Filename: "{app}\bin\rex.cmd"; Tasks: desktopicon

[Code]
const
  EnvSubKey = 'Environment';
  PathValueName = 'Path';
  REX_HWND_BROADCAST = $FFFF;
  REX_WM_SETTINGCHANGE = $001A;
  REX_SMTO_ABORTIFHUNG = $0002;

function SendMessageTimeout(
  hWnd: Integer;
  Msg: Integer;
  wParam: Integer;
  lParam: string;
  fuFlags: Integer;
  uTimeout: Integer;
  var lpdwResult: Integer
): Integer;
  external 'SendMessageTimeoutW@user32.dll stdcall';

var
  RuntimePage: TWizardPage;
  RuntimeLabel: TNewStaticText;

function SplitPathContains(const AllPaths, Entry: string): Boolean;
var
  S, Item, Target: string;
  P: Integer;
begin
  Result := False;
  S := LowerCase(AllPaths);
  Target := LowerCase(Entry);
  while (Length(Target) > 0) and (Target[Length(Target)] = '\') do
    Delete(Target, Length(Target), 1);
  while S <> '' do
  begin
    P := Pos(';', S);
    if P > 0 then
    begin
      Item := Copy(S, 1, P - 1);
      Delete(S, 1, P);
    end
    else
    begin
      Item := S;
      S := '';
    end;
    while (Length(Item) > 0) and (Item[Length(Item)] = '\') do
      Delete(Item, Length(Item), 1);
    if Item = Target then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function ReadPathValue(RootKey: Integer; var Value: string): Boolean;
begin
  Result := RegQueryStringValue(RootKey, EnvSubKey, PathValueName, Value);
  if not Result then
    Value := '';
end;

function AddPathEntry(RootKey: Integer; const Entry: string): Boolean;
var
  CurrentPath: string;
begin
  ReadPathValue(RootKey, CurrentPath);
  if SplitPathContains(CurrentPath, Entry) then
  begin
    Result := True;
    Exit;
  end;
  if CurrentPath = '' then
    CurrentPath := Entry
  else
    CurrentPath := CurrentPath + ';' + Entry;
  Result := RegWriteExpandStringValue(RootKey, EnvSubKey, PathValueName, CurrentPath);
end;

function RemovePathEntry(RootKey: Integer; const Entry: string): Boolean;
var
  CurrentPath, OutPath, S, Item, Target: string;
  P: Integer;
begin
  Result := True;
  if not ReadPathValue(RootKey, CurrentPath) then
    Exit;

  S := CurrentPath;
  OutPath := '';
  Target := LowerCase(Entry);
  while (Length(Target) > 0) and (Target[Length(Target)] = '\') do
    Delete(Target, Length(Target), 1);

  while S <> '' do
  begin
    P := Pos(';', S);
    if P > 0 then
    begin
      Item := Copy(S, 1, P - 1);
      Delete(S, 1, P);
    end
    else
    begin
      Item := S;
      S := '';
    end;

    while (Length(Item) > 0) and (Item[Length(Item)] = '\') do
      Delete(Item, Length(Item), 1);
    if LowerCase(Item) = Target then
      continue;

    if OutPath = '' then
      OutPath := Item
    else
      OutPath := OutPath + ';' + Item;
  end;

  Result := RegWriteExpandStringValue(RootKey, EnvSubKey, PathValueName, OutPath);
end;

procedure WriteLauncherFile;
var
  LauncherPath, Content: string;
begin
  ForceDirectories(ExpandConstant('{app}\bin'));
  LauncherPath := ExpandConstant('{app}\bin\rex.cmd');

  Content :=
    '@echo off' + #13#10 +
    'setlocal' + #13#10 +
    'set "REX_ROOT=%~dp0.."' + #13#10 +
    'set "REX_LUA=%REX_ROOT%\lua\lua.exe"' + #13#10 +
    'if exist "%REX_LUA%" goto run' + #13#10 +
    'where lua.exe >nul 2>nul && set "REX_LUA=lua.exe"' + #13#10 +
    'if defined REX_LUA goto run' + #13#10 +
    'echo Rex error: lua.exe not found. Reinstall Rex with bundled Lua or add Lua to PATH.' + #13#10 +
    'exit /b 1' + #13#10 +
    ':run' + #13#10 +
    '"%REX_LUA%" "%REX_ROOT%\rex\compiler\cli\rex.lua" %*' + #13#10;

  SaveStringToFile(LauncherPath, Content, False);
end;

procedure InitializeWizard;
begin
  RuntimePage := CreateCustomPage(wpSelectTasks, 'Runtime', 'Lua runtime configuration');
  RuntimeLabel := TNewStaticText.Create(RuntimePage);
  RuntimeLabel.Parent := RuntimePage.Surface;
  RuntimeLabel.Left := ScaleX(0);
  RuntimeLabel.Top := ScaleY(6);
  RuntimeLabel.Width := RuntimePage.SurfaceWidth;
  RuntimeLabel.Height := ScaleY(80);
#ifdef LuaExe
  RuntimeLabel.Caption := 'Bundled Lua: yes' + #13#10 +
    'Installer was built with Lua embedded.' + #13#10 +
    'rex.cmd will use bundled lua.exe by default.';
#else
  RuntimeLabel.Caption := 'Bundled Lua: no' + #13#10 +
    'Installer does not include lua.exe.' + #13#10 +
    'Install Lua 5.4+ and keep it in PATH so rex works.';
#endif
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  RootKey: Integer;
  BinPath: string;
  ResultCode: Integer;
begin
  if CurStep <> ssPostInstall then
    Exit;

  WriteLauncherFile;

  if WizardIsTaskSelected('addtopath') then
  begin
    BinPath := ExpandConstant('{app}\bin');
    if IsAdminInstallMode then
      RootKey := HKLM
    else
      RootKey := HKCU;
    AddPathEntry(RootKey, BinPath);
    SendMessageTimeout(REX_HWND_BROADCAST, REX_WM_SETTINGCHANGE, 0, 'Environment', REX_SMTO_ABORTIFHUNG, 5000, ResultCode);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  BinPath: string;
  ResultCode: Integer;
begin
  if CurUninstallStep <> usUninstall then
    Exit;

  BinPath := ExpandConstant('{app}\bin');
  RemovePathEntry(HKCU, BinPath);
  RemovePathEntry(HKLM, BinPath);
  SendMessageTimeout(REX_HWND_BROADCAST, REX_WM_SETTINGCHANGE, 0, 'Environment', REX_SMTO_ABORTIFHUNG, 5000, ResultCode);
end;
