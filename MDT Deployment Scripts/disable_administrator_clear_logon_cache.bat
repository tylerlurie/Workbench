for /f "tokens=2" %%i in ('systeminfo ^| find "Domain"') do (set "DOMAIN=%%i")
if NOT "%DOMAIN%" == "WORKGROUP" (
	reg delete HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI /v LastLoggedOnDisplayName /f
	reg delete HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI /v LastLoggedOnSAMUser /f
	reg delete HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI /v LastLoggedOnUser /f
	reg delete HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI /v LastLoggedOnUserSID /f
	reg delete HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI /v SelectedUserSID /f
	reg add HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI /v LastLoggedOnDisplayName
	reg add HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI /v LastLoggedOnSAMUser
	reg add HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI /v LastLoggedOnUser
	reg add HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI /v LastLoggedOnUserSID
	reg add HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI /v SelectedUserSID
	net user Administrator /active:no
)