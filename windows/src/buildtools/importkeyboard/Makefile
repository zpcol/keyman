#
# importkeyboard Makefile
#

!include ..\..\Defines.mak

build: version.res dirs
    $(MSBUILD) importkeyboard.csproj $(MSBUILD_BUILD)
    $(COPY) bin\debug\importkeyboard.exe $(PROGRAM)\buildtools
    $(COPY) bin\debug\importkeyboard.pdb $(DEBUGPATH)\buildtools

clean: def-clean
    $(MSBUILD) importkeyboard.csproj $(MSBUILD_CLEAN)

signcode:
    $(SIGNCODE) /d "Keyman Developer Tools" $(PROGRAM)\buildtools\importkeyboard.exe

backup:
    $(WZZIP) $(BUILD)\buildtools\importkeyboard.zip  $(BACKUPDEFAULTS) importkeyboard.exe

!include ..\..\Target.mak
