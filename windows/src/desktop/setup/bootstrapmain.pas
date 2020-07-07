(*
  Name:             bootstrapmain
  Copyright:        Copyright (C) SIL International.
  Documentation:    
  Description:      
  Create Date:      4 Jun 2007

  Modified Date:    23 Oct 2014
  Authors:          mcdurdin
  Related Files:    
  Dependencies:     

  Bugs:             
  Todo:             
  Notes:            
  History:          04 Jun 2007 - mcdurdin - Initial version
                    05 Jun 2007 - mcdurdin - I817 - Fix -x option
                    19 Jun 2007 - mcdurdin - I817 - Translate to Unicode and remove Forms dependence
                    14 Sep 2007 - mcdurdin - I1065 - -s silent option in setup.exe stills asks about updated version
                    14 Sep 2007 - mcdurdin - I1066 - -s option does not do a fully silent install in setup.exe
                    14 Sep 2007 - mcdurdin - I1063 - setup.exe crashing when an update is found online rather than installing it
                    27 Mar 2008 - mcdurdin - I1306 - Fix -s option not doing fully silent extract
                    14 Jun 2008 - mcdurdin - Close handles after starting app
                    28 Jul 2008 - mcdurdin - I1158 - Report error codes
                    30 Dec 2010 - mcdurdin - I2562 - EULA in bootstrapper
                    31 Dec 2010 - mcdurdin - I2615 - Fix hidden controls when Alt pressed in Vista
                    31 Dec 2010 - mcdurdin - I2611 - Incorrect icon for setup form
                    21 Feb 2011 - mcdurdin - I2738 - Auto update does not start automatically when triggered
                    31 Mar 2011 - mcdurdin - I2847 - Version 8.0 silent upgrade runs keyboard import from version 7.0 and shouldn't
                    03 Oct 2011 - mcdurdin - I3081 - Create target folder when -x specified
                    04 Nov 2011 - mcdurdin - I3126 - Add flag to control msi UI level
                    18 May 2012 - mcdurdin - I3306 - V9.0 - Remove TntControls + Win9x support
                    17 Aug 2012 - mcdurdin - I3377 - KM9 - Update code references from 8.0 to 9.0
                    19 Oct 2012 - mcdurdin - I3476 - V9.0 - Fixup additional hints and warnings around string conversion
                    02 Feb 2012 - mcdurdin - I2975 - VistaAltFixUnit can crash on shutdown
                    15 Jun 2012 - mcdurdin - I3355 - Keyman Developer (and Desktop) sometimes reboot automatically with auto upgrade
                    03 Nov 2012 - mcdurdin - I3500 - V9.0 - Merge of I3355 - Keyman Developer (and Desktop) sometimes reboot automatically with auto upgrade
                    28 Feb 2014 - mcdurdin - I4099 - V9.0 - Keyman Desktop Setup dialog is still 8.0 style
                    24 Jun 2014 - mcdurdin - I4293 - V9.0 - Setup bootstrapper does not check for V8 upgrade
                    12 Aug 2014 - mcdurdin - I4365 - V9.0 - Installer still doesn't enforce Win7 or later
                    16 Oct 2014 - mcdurdin - I4460 - V9.0 - Setup bootstrapper should handle upgrade scenarios with a prompt
                    23 Oct 2014 - mcdurdin - I4470 - Internet Explorer 9.0 of later required [CrashID:kmshell.exe_9.0.472.0_script_TfrmMain_0]
*)
unit bootstrapmain;  // I3306

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils,

  Keyman.Setup.System.InstallInfo,
  SetupStrings;

var
  FInstallInfo: TInstallInfo = nil;

procedure Run;

function FormatFileSize(Size: Integer): string;

implementation

uses
  System.StrUtils,
  System.TypInfo,
  Vcl.Forms,
  Winapi.ActiveX,
  Winapi.Windows,

  CommonControls,
  ErrorControlledRegistry,
  GetOsVersion,
  Keyman.Setup.System.OnlineResourceCheck,
  Keyman.System.UpgradeRegistryKeys,
  KeymanPaths,
  KeymanVersion,
  OnlineConstants,
  RegistryHelpers,
  RegistryKeys,
  RunTools,
  SetupForm,
  SFX,
  TntDialogHelp,
  UfrmRunDesktop,
  Upload_Settings,
  utilexecute;

function CheckForOldVersionScenario: Boolean; forward;
procedure InstallKeyboardsInOldVersion(const ShellPath: string); forward;
procedure DoExtractOnly(FSilent: Boolean; const FExtractOnly_Path: string); forward;
function CreateTempDir: string; forward;
procedure RemoveTempDir(const path: string); forward;
procedure ProcessCommandLine(var FPromptForReboot, FSilent, FForceOffline, FExtractOnly, FContinueSetup, FStartAfterInstall, FDisableUpgradeFrom6Or7Or8: Boolean; var FPackages, FExtractPath: string); forward;
procedure LogError(const s: WideString); forward;
procedure SetExitVal(c: Integer); forward;
function IsKeymanDesktop7Installed: string; forward;
function IsKeymanDesktop8Installed: string; forward;

var
  FNiceExitCodes: Boolean = True; // always, now

const
  ICC_PROGRESS_CLASS     = $00000020; // progress


var
  ProgramPath: string = '';

procedure Run;
var
  FTempPath: string;
  FExtractOnly: Boolean;
  FContinueSetup: Boolean;
  FStartAfterInstall: Boolean;  // I2738
  FDisableUpgradeFrom6Or7Or8: Boolean; // I2847   // I4293
  FPromptForReboot: Boolean;  // I3355   // I3500
  FSilent: Boolean;
  FForceOffline: Boolean;
  FPackages, FExtractOnly_Path: string;
BEGIN
  CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  try
    try
      Vcl.Forms.Application.Icon.LoadFromResourceID(hInstance, 1);  // I2611

      try
        FTempPath := CreateTempDir;
        try
          InitCommonControl(ICC_PROGRESS_CLASS);

          FInstallInfo := TInstallInfo.Create(FTempPath);

          { Display the dialog }

          ProcessCommandLine(FPromptForReboot, FSilent, FForceOffline, FExtractOnly, FContinueSetup, FStartAfterInstall, FDisableUpgradeFrom6Or7Or8, FPackages, FExtractOnly_Path);  // I2738, I2847  // I3355   // I3500   // I4293

          if FExtractOnly then
          begin
            DoExtractOnly(FSilent, FExtractOnly_Path);
            Exit;
          end;

          // We will now work with a missing setup.inf: if it is not present,
          // we assume that we are in Keyman Desktop mode

          // There are two possible paths for files: ProgramPath and TempPath,
          // and also files that can be downloaded during the installation into TempPath.

          // TODO: deprecate ExtPath usage for one of TempPath or ProgramPath

          ProgramPath := ExtractFilePath(ParamStr(0));

          if not ProcessArchive then
          begin
            { The files must be in the current directory.  Use them instead }
            ExtPath := ExtractFilePath(ParamStr(0));  // I3476
          end;

          ExtPath := IncludeTrailingPathDelimiter(ExtPath);  // I3476

          // Get the list of anticipated packages from the filename


          // The filename of this executable can be changed to tell it which
          // packages to download, e.g. keyman-setup.khmer_angkor.km.exe tells
          // it to download khmer_angkor from the Keyman cloud and install it
          // for bcp47 tag km. See the setup documentation for more
          // examples.
          FInstallInfo.LocatePackagesFromFilename(ParamStr(0));

          // Additionally, packages can be specified on the command line, with
          // the -p parameter, e.g. -p khmer_angkor=km,sil_euro_latin=fr
          FInstallInfo.LocatePackagesFromParameter(FPackages);

          // Packages that have been extracted from the SFX archive are in
          // the TempPath
          FInstallInfo.LocatePackagesInPath(FInstallInfo.TempPath);

          // Finally, look also for any .kmp packages in the same folder as
          // this executable
          FInstallInfo.LocatePackagesInPath(ProgramPath);

          GetRunTools.CheckInternetConnectedState;

          if not FForceOffline and GetRunTools.Online then
            // TODO: retry strategies (and prompt around firewall etc)
            TOnlineResourceCheck.QueryServer(FSilent, FInstallInfo);

          // This loads setup.inf, if present, for various additional strings and settings
          // The bundled installer usually contains a setup.inf.
          if FileExists(FInstallInfo.TempPath + 'setup.inf') then
            FInstallInfo.LoadSetupInf(FInstallInfo.TempPath)
          else if FileExists(ProgramPath + 'setup.inf') then
            FInstallInfo.LoadSetupInf(ProgramPath);

          // If the user is trying to install on downlevel version of Windows (Vista or earlier),
          // we can simplify their life by installing the packages into an existing Keyman
          // install, or point them to the old version of Keyman otherwise.
          if CheckForOldVersionScenario then   // I4460
            Exit;

          TRunTools.CheckInstalledVersion(FInstallInfo.BestMsi);

          // Looks for installation state for Keyman, and determines best packages for installation.
          // If no .msi can be found, and Keyman is not installed, this will show/log an error and
          // abort installation.
          if not FInstallInfo.CheckMsiAndPackageUpgradeScenarios then
          begin
            // TODO: this should be refactored together with the retry strategy for online check above
            // TODO: Delineate between log messages and dialogs.
            // TODO: Consider Sentry?
            LogError('A valid Keyman install could not be found offline. Please connect to the Internet or allow this installer through your firewall in order to install Keyman.');
            SetExitVal(ERROR_NO_MORE_FILES);
            Exit;
          end;

          // Default scenario is that if any newer installer is available, then
          // Setup should install it.
          FInstallInfo.ShouldInstallKeyman := FInstallInfo.IsNewerAvailable;

          with TfrmRunDesktop.Create(nil) do    // I2562
          try
            ContinueSetup := FContinueSetup;
            StartAfterInstall := FStartAfterInstall; // I2738
            DisableUpgradeFrom6Or7Or8 := FDisableUpgradeFrom6Or7Or8;  // I2847   // I4293
            if FSilent
              then DoInstall(False, True, FPromptForReboot)  // I3355   // I3500
              else ShowModal;
          finally
            Free;
          end;
        finally
          RemoveTempDir(FTempPath);
        end;

        SetExitVal(ERROR_SUCCESS);

      finally
        FInstallInfo.Free;
      end;
    except
      on e:Exception do
      begin
        //TODO: handle exceptions with JCL
        ShowMessageW(e.message);
      end;
    end;
  finally
    CoUninitialize;
  end;
end;

function CheckForOldVersionScenario: Boolean;   // I4460
var
  OldKMShellPath: string;
begin
  if not (GetOS in [osLegacy, osVista]) then   // I4365
    Exit(False);

  if FInstallInfo.Packages.Count = 0 then
  begin
    // No keyboards installed, so we determine install based on Windows version
    if MessageDlgW(FInstallInfo.Text(ssOldOsVersionDownload), mtConfirmation, mbOkCancel, 0) = mrOk then
      TUtilExecute.URL(MakeKeymanURL(URLPath_ArchivedDownloads));
    SetExitVal(ERROR_OLD_WIN_VERSION);
    Exit(True);
  end;

  OldKMShellPath := IsKeymanDesktop8Installed;
  if OldKMShellPath = '' then OldKMShellPath := IsKeymanDesktop7Installed;

  if OldKMShellPath <> '' then
  begin
    if MessageDlgW(FInstallInfo.Text(ssOldOsVersionInstallKeyboards), mtConfirmation, mbYesNoCancel, 0) = mrYes then
      InstallKeyboardsInOldVersion(OldKMShellPath);
  end
  else
  begin
    if MessageDlgW(FInstallInfo.Text(ssOldOsVersionDownload), mtConfirmation, mbOkCancel, 0) = mrOk then
      TUtilExecute.URL(MakeKeymanURL(URLPath_ArchivedDownloads));
  end;
  SetExitVal(ERROR_OLD_WIN_VERSION);
  Exit(True);
end;

// TODO: move this into a separate unit: it deals with installing keyboards into
// an existing Keyman install on downlevel versions of Windows (e.g. Vista). So
// we are constrained in how we do this -- no ability to do language associations
// etc.
procedure InstallKeyboardsInOldVersion(const ShellPath: string);   // I4460
  procedure DoInstall(pack: TInstallInfoPackage; const silentFlag: string);
  var
    location: TInstallInfoPackageFileLocation;
  begin
    location := pack.GetBestLocation;
    if Assigned(location) and pack.ShouldInstall then
    begin
      if location.LocationType = iilOnline then
        Assert(FALSE, 'TODO: implement download of this resource');
        //TODO:
      TUtilExecute.WaitForProcess('"' + ShellPath + '" '+silentFlag+' -i "'+location.Path+'"', ExtPath);
    end;
  end;
var
  pack: TInstallInfoPackage;
begin
  if FInstallInfo.Packages.Count = 1 then
  begin
    DoInstall(FInstallInfo.Packages[0], '');
  end
  else
  begin
    for pack in FInstallInfo.Packages do
      DoInstall(pack, '-s');
    ShowMessageW('All packages have been installed');
  end;
end;

procedure DoExtractOnly(FSilent: Boolean; const FExtractOnly_Path: string);
begin
  ExtPath := FExtractOnly_Path;  // I3476

  if ExtPath = '' then
    ExtPath := '.';

  if (ExtPath <> '.') and (ExtPath <> '.\') and not DirectoryExists(ExtPath) then  // I3081  // I3476
  begin
    if not CreateDir(ExtPath) then  // I3476
    begin
      LogError('Setup could not create the target folder '+ExtPath);  // I3476
      SetExitVal(Integer(GetLastError));
      Exit;
    end;
  end;

  if not ProcessArchive then
  begin
    LogError('This file was not a valid self-extracting archive.  The files should already be in the same folder as the archive.');
    SetExitVal(ERROR_BAD_FORMAT);
    Exit;
  end;

  if not FSilent then
    LogError('All files extracted from the archive to '+ExtPath+'\.');  // I3476
  SetExitVal(ERROR_SUCCESS);
end;

function CreateTempDir: string;
var
  buf: array[0..260] of WideChar;
begin
  GetTempPath(MAX_PATH-1, buf);
  ExtPath := ExcludeTrailingPathDelimiter(buf);  // I3476
  GetTempFileName(PWideChar(ExtPath), 'kmt', 0, buf);  // I3476
  ExtPath := buf;  // I3476
  if FileExists(buf) then DeleteFile(buf);  // I3476
  // NOTE: race condition here...
  CreateDirectory(buf, nil);  // I3476
  Result := IncludeTrailingPathDelimiter(ExtPath);
end;

procedure DeletePath(const path: WideString);
var
  fd: TWin32FindDataW;
  n: DWord;
begin
  n := FindFirstFile(PWideChar(path + '\*.*'), fd);
  if n = INVALID_HANDLE_VALUE then Exit;
  repeat
    DeleteFile(PWideChar(path + '\' + fd.cFileName));
  until not FindNextFile(n, fd);
  FindClose(n);
  RemoveDirectory(PWideChar(path));
end;

procedure RemoveTempDir(const path: string);
begin
  if path <> '' then
    DeletePath(ExcludeTrailingPathDelimiter(path));  // I3476
end;

procedure ProcessCommandLine(var FPromptForReboot, FSilent, FForceOffline, FExtractOnly, FContinueSetup, FStartAfterInstall, FDisableUpgradeFrom6Or7Or8: Boolean; var FPackages, FExtractPath: string);  // I2847  // I3355   // I3500   // I4293
var
  i: Integer;
begin
  FPromptForReboot := True;  // I3355   // I3500
  FSilent := False;
  FForceOffline := False;
  FExtractOnly := False;
  FContinueSetup := False;
  FDisableUpgradeFrom6Or7Or8 := False; // I2847   // I4293
  FStartAfterInstall := True;  // I2738
  i := 1;
  while i <= ParamCount do
  begin
    if WideSameText(ParamStr(i), '-c') then
      FContinueSetup := True
    else if WideSameText(ParamStr(i), '-s') then
    begin
      FSilent := True;
      FStartAfterInstall := False;
      FPromptForReboot := False;  // I3355   // I3500
    end
    else if WideSameText(ParamStr(i), '-au') then  // I2738
    begin
      // auto update - options for more flexibility later...
      FSilent := True;
      FForceOffline := True;
      FStartAfterInstall := True;
      FDisableUpgradeFrom6Or7Or8 := True;  // I2847   // I4293
    end
    else if WideSameText(ParamStr(i), '-o') then
      FForceOffline := True
    else if WideSameText(ParamStr(i), '-r') then
      // previously, 'nice exit codes'
    else if WideSameText(ParamStr(i), '-x') then
    begin
      Inc(i);
      FExtractOnly := True;
      FExtractPath := ParamStr(i);
      if FExtractPath = '' then
        FExtractPath := ExtractFilePath(ParamStr(0));
    end
    else if SameText(ParamStr(i), '-p') then
    begin
      // e.g. -p khmer_angkor=km,sil_euro_latin=fr
      Inc(i);
      FPackages := ParamStr(i);
    end;
    Inc(i);
  end;
end;

procedure LogError(const s: WideString);
begin
  // TODO: refactor with RunTools.LogError
  // TODO: FSilent mode, log error to logfile instead;
  ShowMessageW(s);
end;

procedure SetExitVal(c: Integer);
begin
  // TODO: write the exit code to the logfile
  ExitCode := c;
end;

function IsKeymanDesktop7Installed: string;   // I4460
begin
  with CreateHKLMRegistry do
  try
    if OpenKeyReadOnly(SRegKey_Keyman70_LM) and ValueExists('root path')  //TODO -- test this
      then Result := IncludeTrailingPathDelimiter(ReadString('root path')) + TKeymanPaths.S_KMShell
      else Exit('');

    if not FileExists(Result) then
      Result := '';
  finally
    Free;
  end;
end;

function IsKeymanDesktop8Installed: string;   // I4460
begin
  with CreateHKLMRegistry do
  try
    if OpenKeyReadOnly(SRegKey_Keyman80_LM) and ValueExists('root path')  //TODO -- test this
      then Result := IncludeTrailingPathDelimiter(ReadString('root path')) + TKeymanPaths.S_KMShell
      else Exit('');

    if not FileExists(Result) then
      Result := '';
  finally
    Free;
  end;
end;

function FormatFileSize(Size: Integer): string;
begin
  if Size > 1024*1024 then
    Result := Format('%.1fMB', [Size/1024/1024])
  else if Size > 1024 then
    Result := Format('%dKB',[Size div 1024])
  else if Size = 1 then
    Result := '1 byte'
  else
    Result := Format('%d bytes', [Size]);
end;

end.
