; ExplorerTerminal.ahk
; Originally found from here: https://www.autohotkey.com/boards/viewtopic.php?t=29026
; This script was designed to be used during my daily experiments with OS deployment.
; I often find myself pressing Alt+D to highlight the Explorer address bar and typing in "wt" to quickly open the terminal at the current Explorer location.
; The problem I run into with OSD is that many of the DISM commands require elevated privileges to work. Although Microsoft have conveniently added
; an option to the right-click menu to quickly open a terminal from the current explorer location, I generally always have my fingers on the keyboard and try to use
; the mouse as little as possible. Not to mention, this option currently does not seem to have support for opening an administrative terminal window yet. I really
; like the Linux approach to this problem (included in several, but not all, distros) of pressing Ctrl+Alt+T to open the terminal, but this feature sadly is not
; available in Windows as of now. With this problem in mind, this script allows the user to press Ctrl+Alt+T, and opens a terminal window at the current Explorer
; location if Explorer is the active window. Otherwise, it opens a terminal to whatever location is set as the default.
; Place a shortcut to this script in your user's startup folder (%AppData%\Microsoft\Windows\Start Menu\Programs\Startup) if you'd like it to run when you sign in.
; Or place one in the system's startup folder (%ProgramData%\Microsoft\Windows\Start Menu\Programs\Startup) if you'd like it to run when the computer boots
; (this affects all users).

; If you'd like to make any changes to this script, you can do so and recompile it with AutoHotkey if you choose. Credit for the icon file for this script
; goes to Microsoft and can be downloaded from this link: https://github.com/microsoft/terminal/raw/main/res/terminal.ico

; One final note, in my testing I've found that the only way to ensure this script runs as intended with Windows Terminal is to ensure that for each terminal
; profile (or just in the "Defaults" settings if you haven't made any changes to any of them), the starting directory is set to "Use parent process directory".

#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.
#SingleInstance Force
#NoTrayIcon

; I prefer to use the Windows Termianl app as my default terminal. It is included with Windows 11 by default and can be downloaded on Windows 10 from the Microsoft
; Store. If you prefer to use something else, you'll need to modify the below variable to be the name of/path to the executable of your choice of terminal
; (i.e., "powershell.exe", or "cmd.exe"):
global TERMINAL := "wt.exe"

ExplorerTerminal(admin := false) {
    if WinActive("ahk_class CabinetWClass") || WinActive("ahk_class ExploreWClass") {
        WinHWND := WinActive()
        for win in ComObjCreate("Shell.Application").Windows {
			if (win.HWND = WinHWND) {
				currdir := SubStr(win.LocationURL, 9)
				currdir := RegExReplace(currdir, "%20", " ")
				break
			}
		}
    }
	if admin
		try
			Run *RunAs %TERMINAL%, %currdir%
	else
		Run, %TERMINAL%, %currdir%
	return
}

; Below is the mapping of the hotkeys to the openTerminalHere function. If you want to map these to different keyboard shortcuts, you can do so here:
; Note: The Ctrl key is "^", the Alt key is "!", the Shift key is "+", and the Windows key is "#"
^!t::ExplorerTerminal()
^!+t::ExplorerTerminal(admin:=true)