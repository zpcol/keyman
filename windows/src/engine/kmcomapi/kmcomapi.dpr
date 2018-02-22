library kmcomapi;

{ Important note about DLL memory management: ShareMem must be the
  first unit in your library's USES clause AND your project's (select
  Project-View Source) USES clause if your DLL exports any procedures or
  functions that pass strings as parameters or function results. This
  applies to all strings passed to and from your DLL--even those that
  are nested in records and classes. ShareMem is the interface unit to
  the BORLNDMM.DLL shared memory manager, which must be deployed along
  with your DLL. To avoid using BORLNDMM.DLL, pass string information
  using PChar or ShortString parameters. }

uses
  Imagehlp in '..\..\global\delphi\vcl\Imagehlp.pas',
  SysUtils,
  ComServ,
  keymanautoobject in 'util\keymanautoobject.pas',
  keyman_implementation in 'com\keyman_implementation.pas' {Keyman: CoClass},
  keymancontrol in 'com\system\keymancontrol.pas',
  keymanerror in 'com\errors\keymanerror.pas',
  keymanerrors in 'com\errors\keymanerrors.pas',
  keymanhotkey in 'com\hotkeys\keymanhotkey.pas',
  keymanhotkeys in 'com\hotkeys\keymanhotkeys.pas',
  keymankeyboard in 'com\keyboards\keymankeyboard.pas',
  keymankeyboardfile in 'com\keyboards\keymankeyboardfile.pas',
  keymankeyboardinstalled in 'com\keyboards\keymankeyboardinstalled.pas',
  keymankeyboardlanguageinstalled in 'com\keyboardlanguages\keymankeyboardlanguageinstalled.pas',
  keymankeyboardlanguagesinstalled in 'com\keyboardlanguages\keymankeyboardlanguagesinstalled.pas',
  keymankeyboardoption in 'com\keyboardoptions\keymankeyboardoption.pas',
  keymankeyboardoptions in 'com\keyboardoptions\keymankeyboardoptions.pas',
  keymankeyboardsinstalled in 'com\keyboards\keymankeyboardsinstalled.pas',
  keymanlanguage in 'com\languages\keymanlanguage.pas',
  keymanlanguages in 'com\languages\keymanlanguages.pas',
  keymanoption in 'com\options\keymanoption.pas',
  keymanoptions in 'com\options\keymanoptions.pas',
  keymanpackagecontentfile in 'com\packages\keymanpackagecontentfile.pas',
  keymanpackagecontentfiles in 'com\packages\keymanpackagecontentfiles.pas',
  keymanpackagecontentfont in 'com\packages\keymanpackagecontentfont.pas',
  keymanpackagecontentfonts in 'com\packages\keymanpackagecontentfonts.pas',
  keymanpackagecontentkeyboards in 'com\keyboards\keymanpackagecontentkeyboards.pas',
  keymanpackagefile in 'com\packages\keymanpackagefile.pas',
  keymanpackageinstalled in 'com\packages\keymanpackageinstalled.pas' {KeymanPackage: CoClass},
  keymanpackagesinstalled in 'com\packages\keymanpackagesinstalled.pas' {KeymanPackages: CoClass},
  keymansysteminfo in 'com\system\keymansysteminfo.pas' {KeymanSystemInfo: CoClass},
  keymanvisualkeyboard in 'com\keyboards\keymanvisualkeyboard.pas' {KeymanVisualKeyboard: CoClass},
  exception_keyman in 'util\exception_keyman.pas',
  isadmin in 'util\isadmin.pas',
  baseerror in 'util\baseerror.pas',
  utilkeyman in 'util\utilkeyman.pas',
  CRC32 in '..\..\global\delphi\general\CRC32.pas',
  KeyNames in '..\..\global\delphi\general\KeyNames.pas',
  RegistryKeys in '..\..\global\delphi\general\RegistryKeys.pas',
  GetOsVersion in '..\..\global\delphi\general\GetOsVersion.pas',
  RegKeyboards in '..\..\global\delphi\general\RegKeyboards.pas',
  HotkeyUtils in '..\..\global\delphi\general\HotkeyUtils.pas',
  Glossary in '..\..\global\delphi\general\Glossary.pas',
  kpbase in 'processes\kpbase.pas',
  kpinstallkeyboard in 'processes\keyboard\kpinstallkeyboard.pas',
  utilunicode in 'util\utilunicode.pas',
  kpuninstallkeyboard in 'processes\keyboard\kpuninstallkeyboard.pas',
  keymancontext in 'keymancontext.pas',
  utilvararray in 'util\utilvararray.pas',
  kpinstallpackage in 'processes\package\kpinstallpackage.pas',
  kmpinffile in '..\..\global\delphi\general\kmpinffile.pas',
  PackageInfo in '..\..\global\delphi\general\PackageInfo.pas',
  PackageFileFormats in '..\..\global\delphi\general\PackageFileFormats.pas',
  exceptionw in '..\..\global\delphi\general\exceptionw.pas',
  ttinfo in '..\..\global\delphi\general\ttinfo.pas',
  keymanerrorcodes in 'util\keymanerrorcodes.pas',
  kpuninstallpackage in 'processes\package\kpuninstallpackage.pas',
  kpinstallfont in 'processes\font\kpinstallfont.pas',
  kpuninstallfont in 'processes\font\kpuninstallfont.pas',
  utilkeymanoption in 'util\utilkeymanoption.pas',
  BitmapIPicture in '..\..\global\delphi\general\BitmapIPicture.pas',
  KPUninstallVisualKeyboard in 'processes\visualkeyboard\KPUninstallVisualKeyboard.pas',
  KPInstallVisualKeyboard in 'processes\visualkeyboard\KPInstallVisualKeyboard.pas',
  VisualKeyboard in '..\..\global\delphi\visualkeyboard\VisualKeyboard.pas',
  keymancustomisation in 'com\customisation\keymancustomisation.pas',
  CustomisationMessages in '..\..\global\delphi\cust\CustomisationMessages.pas',
  CustomisationStorage in '..\..\global\delphi\cust\CustomisationStorage.pas',
  custinterfaces in '..\..\global\delphi\cust\custinterfaces.pas',
  utilkeymancontrol in 'util\utilkeymancontrol.pas',
  klog in '..\..\global\delphi\general\klog.pas',
  DCPcrypt2 in '..\..\ext\dcpcrypt\DCPcrypt2.pas',
  DCPbase64 in '..\..\ext\dcpcrypt\DCPbase64.pas',
  DCPconst in '..\..\ext\dcpcrypt\DCPconst.pas',
  DCPsha256 in '..\..\ext\dcpcrypt\Hashes\DCPsha256.pas',
  DCPrc4 in '..\..\ext\dcpcrypt\Ciphers\DCPrc4.pas',
  utilfiletypes in '..\..\global\delphi\general\utilfiletypes.pas',
  keymanapi_TLB in 'keymanapi_TLB.pas',
  kmxfile in '..\..\global\delphi\general\kmxfile.pas',
  utilhandleexception in 'util\utilhandleexception.pas',
  StockFileNames in '..\..\global\delphi\cust\StockFileNames.pas',
  CustomisationMenu in '..\..\global\delphi\cust\CustomisationMenu.pas',
  utilolepicture in 'util\utilolepicture.pas',
  utilxml in '..\..\global\delphi\general\utilxml.pas',
  VersionInfo in '..\..\global\delphi\general\VersionInfo.pas',
  extshiftstate in '..\..\global\delphi\comp\extshiftstate.pas',
  utilsystem in '..\..\global\delphi\general\utilsystem.pas',
  utilstr in '..\..\global\delphi\general\utilstr.pas',
  utildir in '..\..\global\delphi\general\utildir.pas',
  utiltsf in '..\..\global\delphi\general\utiltsf.pas',
  OnlineConstants in '..\..\global\delphi\productactivation\OnlineConstants.pas',
  SystemDebugPath in '..\..\global\delphi\general\SystemDebugPath.pas',
  MessageDefaults in '..\..\global\delphi\cust\MessageDefaults.pas',
  MessageIdentifierConsts in '..\..\global\delphi\cust\MessageIdentifierConsts.pas',
  KeymanEngineControl in '..\..\global\delphi\general\KeymanEngineControl.pas',
  ErrorControlledRegistry in '..\..\global\delphi\vcl\ErrorControlledRegistry.pas',
  kmxfileutils in '..\..\global\delphi\general\kmxfileutils.pas',
  kmxfileconsts in '..\..\global\delphi\general\kmxfileconsts.pas',
  kmxfileusedchars in '..\..\global\delphi\general\kmxfileusedchars.pas',
  kmxfileusedscripts in '..\..\global\delphi\general\kmxfileusedscripts.pas',
  UnicodeBlocks in '..\..\global\delphi\general\UnicodeBlocks.pas' { UnicodeBlock: CoClass},
  IntegerArray in '..\..\global\delphi\general\IntegerArray.pas',
  KeymanControlMessages in '..\..\global\delphi\general\KeymanControlMessages.pas',
  ErrLogPath in '..\..\global\delphi\general\ErrLogPath.pas',
  internalinterfaces in 'util\internalinterfaces.pas',
  VKeyChars in '..\..\global\delphi\general\VKeyChars.pas',
  UserMessages in '..\..\global\delphi\general\UserMessages.pas',
  DebugPaths in '..\..\global\delphi\general\DebugPaths.pas',
  utilrun in 'util\utilrun.pas',
  keyman_msctf in '..\..\global\delphi\winapi\keyman_msctf.pas',
  Unicode in '..\..\global\delphi\general\Unicode.pas',
  utilexecute in '..\..\global\delphi\general\utilexecute.pas',
  KeymanVersion in '..\..\global\delphi\general\KeymanVersion.pas',
  StockMessages in '..\..\global\delphi\cust\StockMessages.pas',
  kpinstallkeyboardlanguageprofiles in 'processes\keyboard\kpinstallkeyboardlanguageprofiles.pas',
  kpuninstallkeyboardlanguageprofiles in 'processes\keyboard\kpuninstallkeyboardlanguageprofiles.pas',
  kprecompilemnemonickeyboard in 'processes\keyboard\kprecompilemnemonickeyboard.pas',
  TempFileManager in '..\..\global\delphi\general\TempFileManager.pas',
  input_installlayoutortip in '..\..\global\delphi\winapi\input_installlayoutortip.pas',
  utilicon in '..\..\global\delphi\general\utilicon.pas',
  KPInstallPackageStartMenu in '..\..\global\delphi\general\KPInstallPackageStartMenu.pas',
  KPUninstallPackageStartMenu in '..\..\global\delphi\general\KPUninstallPackageStartMenu.pas',
  utilwow64 in '..\..\global\delphi\general\utilwow64.pas',
  KeymanDesktopShell in '..\keyman\KeymanDesktopShell.pas',
  KeymanPaths in '..\..\global\delphi\general\KeymanPaths.pas',
  KeymanMutex in '..\..\global\delphi\general\KeymanMutex.pas',
  KeymanOptionNames in '..\..\global\delphi\general\KeymanOptionNames.pas',
  VisualKeyboardLoaderBinary in '..\..\global\delphi\visualkeyboard\VisualKeyboardLoaderBinary.pas',
  VisualKeyboardLoaderXML in '..\..\global\delphi\visualkeyboard\VisualKeyboardLoaderXML.pas',
  VisualKeyboardSaverBinary in '..\..\global\delphi\visualkeyboard\VisualKeyboardSaverBinary.pas',
  VisualKeyboardSaverXML in '..\..\global\delphi\visualkeyboard\VisualKeyboardSaverXML.pas',
  VKeys in '..\..\global\delphi\general\VKeys.pas',
  Windows8LanguageList in '..\..\global\delphi\general\Windows8LanguageList.pas',
  BCP47Tag in '..\..\global\delphi\general\BCP47Tag.pas',
  JsonUtil in '..\..\global\delphi\general\JsonUtil.pas',
  Keyman.System.Standards.BCP47SuppressScriptRegistry in '..\..\global\delphi\standards\Keyman.System.Standards.BCP47SuppressScriptRegistry.pas',
  Keyman.System.LanguageCodeUtils in '..\..\global\delphi\general\Keyman.System.LanguageCodeUtils.pas',
  Keyman.System.Standards.ISO6393ToBCP47Registry in '..\..\global\delphi\standards\Keyman.System.Standards.ISO6393ToBCP47Registry.pas',
  Keyman.System.Standards.LCIDToBCP47Registry in '..\..\global\delphi\standards\Keyman.System.Standards.LCIDToBCP47Registry.pas',
  keymankeyboardlanguage in 'com\keyboardlanguages\keymankeyboardlanguage.pas',
  keymankeyboardlanguagesfile in 'com\keyboardlanguages\keymankeyboardlanguagesfile.pas',
  keymankeyboardlanguagefile in 'com\keyboardlanguages\keymankeyboardlanguagefile.pas';

{$R *.TLB}

{$R *.RES}
{$R VERSION.RES}
{$R MANIFEST.RES}

exports
  DllGetClassObject,
  DllCanUnloadNow,
  DllRegisterServer,
  DllUnregisterServer;

begin
    // I1642 move GetErrLogPath out of DllMain - causes memory issues later due to COM calls.  Now in TavultesoftKeyman:Initialize
end.
