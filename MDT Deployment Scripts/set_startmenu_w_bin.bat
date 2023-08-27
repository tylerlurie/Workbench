rem The first argument needs to be the path to the bin file to copy.
set binFile=%1
rem Windows has different names for the start bin file depending on the version, so we must account for this:
if exist "%LOCALAPPDATA%\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start.bin" set STARTFILE="start.bin"
if exist "%LOCALAPPDATA%\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start1.bin" set STARTFILE="start1.bin"
if exist "%LOCALAPPDATA%\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2.bin" set STARTFILE="start2.bin"
REM Copy start bin file to default user profile:
xcopy "%binFile%" "%startFile%" /Q /H /I /Y