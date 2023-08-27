rem Sets the default desktop wallpaper during deployment with MDT.
rem Run with the first argument being the path to the wallpaper image file.
rem For example: set_desktop_wallpaper.bat "Z:\Customizations\Wallpaper.jpg"
rem Run in Task Sequence with command line: "cmd.exe /c %DEPLOYROOT%\Customizations\Set-DesktopWallpaper.bat"
set filePath=%1
xcopy %filePath% "%OSDisk%\Windows\Web\Wallpaper" /Q /H /I /Y
reg load HKLM\NewUsers "%OSDisk%\Users\Default\NTUSER.DAT"
reg add HKLM\NewUsers\Software\Microsoft\Windows\CurrentVersion\Policies\System /v Wallpaper /t REG_SZ /d "C:\Windows\Web\Wallpaper\Wallpaper.jpg" /f
reg add HKLM\NewUsers\Software\Microsoft\Windows\CurrentVersion\Policies\System /v WallpaperStyle /t REG_SZ /d 4 /f
reg unload HKLM\NewUsers