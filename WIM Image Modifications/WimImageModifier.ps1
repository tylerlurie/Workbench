if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process Powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -NoNewWindow" -Verb RunAs
	Exit
}
Clear-Host
do {
    Write-Host "1) Mount WIM File"
    Write-Host "2) Extract ISO File"
    Write-Host "3) Repackage ISO File"
	Write-Host "4) Convert ESD File to WIM File"
    Write-Host "5) Remove Image from WIM File"
    Write-Host "6) Set Default Locale for Image"
    Write-Host "7) Import Custom Start Menu to Image"
    Write-Host "8) Import Custom App Associations to Image"
    Write-Host "9) Import Drivers to Image"
    Write-Host "10) Add Windows Updates to Image"
    Write-Host "11) Remove Windows Store Apps from Image"
    Write-Host "12) Apply Unattend Answer File to Image"
    Write-Host "13) Unmount WIM File"
    Write-Host "14) Exit"
    Write-Host ""
    $userChoice = Read-Host "Choice"
	Write-Host ""
	switch ($userChoice) {
		1 {
			$pathToWim = Read-Host -Prompt "Path to WIM or ESD file"
			$mountedWIMs = Get-WindowsImage -Mounted | Select-Object -ExpandProperty ImagePath
			if ($pathToWim -in $mountedWIMs) {
				$mountDir = Get-WindowsImage -Mounted | Select-Object ImagePath, Path | Where-Object {$_.ImagePath -eq $pathToWim} | Select-Object -ExpandProperty Path
			}
			else {
				$mountDir = Read-Host -Prompt "Directory to mount WIM image"
				Write-Host ""
				Write-Host $(Get-WindowsImage -ImagePath $pathToWim | Select-Object ImageName, ImageIndex | Out-String)
				$index = Read-Host -Prompt "Which index would you like to mount?"
			}
			if ([IO.Path]::GetExtension($pathToWim) -eq ".esd") {
				$ans = Read-Host -Prompt "ESD file detected. Would you like to convert it to a WIM? (y/n)"
				if ($ans -eq "y") {
					$pathToEsd = $pathToWim
					$pathToWim = $($pathToWim.Replace("`"", "").TrimEnd(".esd") + ".wim")
					Dism.exe /Export-Image /SourceImageFile:$pathToWim /SourceIndex:$index /DestinationImageFile:$pathToWim
					$ans = Read-Host -Prompt "$pathToEsd converted to $pathToWim. Would you like to delete the ESD file? (y/n)"
					if ($ans -eq "y") {
						Remove-Item -Path $pathToEsd
					}
				}
			}
			if ($pathToWim -notin $mountedWIMs) {
				if (-not (Test-Path $mountDir)) {
					New-Item -ItemType Directory -Path $mountDir | Out-Null
				}
				Dism.exe /Mount-Image /ImageFile:$pathToWim /Index:$index /MountDir:$mountDir /Optimize
			}
			Clear-Host
			Write-Host "Done.`n"
		}
		2 { 
			$isoFile = Read-Host -Prompt "Path to ISO File"
			$outDir = Read-Host -Prompt "Path to Output Files"
			if (-not (Test-Path $outDir)) {
				New-Item -ItemType Directory -Path $outDir
			}
			# Use 7-Zip if it is installed. Otherwise, mount the ISO and copy the files:
			if ((Test-Path "${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {
				Start-Process "${env:ProgramFiles(x86)}\7-Zip\7z.exe" -ArgumentList "x -y -o$outDir $isoFile" -Wait -NoNewWindow
			} elseif ((Test-Path "${env:ProgramFiles}\7-Zip\7z.exe")) {
				Start-Process "${env:ProgramFiles}\7-Zip\7z.exe" -ArgumentList "x -y -o$outDir $isoFile" -Wait -NoNewWindow
			} else {
				Mount-DiskImage -ImagePath $isoFile -NoDriveLetter
				Copy-Item -Path \\.\CDROM1\ -Destination $outDir -Recurse
				Dismount-DiskImage -ImagePath $isoFile
			}
			Clear-Host
			Write-Host "Done.`n"
		}
		3 {
			$windowsVersion = ((Get-ComputerInfo).OsName).Split(" ")[2]
			$oscdimg = "C:\Program Files (x86)\Windows Kits\$windowsVersion\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
			if (-not (Test-Path "$oscdimg")) {
				$ans = Read-Host -Prompt "You are missing dependencies to repackage ISO files. Would you like to download them now? (y/n)"
				if ($ans -eq "y") {
					if ($windowsVersion -eq "10") {
						$dlLink = "https://go.microsoft.com/fwlink/?linkid=2196127"
					} elseif ($windowsVersion -eq "11") {
						$dlLink = "http://go.microsoft.com/fwlink/p/?LinkId=526740"
					}
					$installer = "$($env:TEMP)\adksetup.exe"
					Invoke-WebRequest -Uri $dlLink -OutFile $installer
					Start-Process $installer -ArgumentList "/features OptionId.DeploymentTools /q" -Wait
					Remove-Item $installer
				}
			}
			Start-Process "C:\Program Files (x86)\Windows Kits\$windowsVersion\Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat" -Wait
			$srcPath = Read-Host -Prompt "Enter the path to the source files of your ISO file"
			$outFile = Read-Host -Prompt "Enter the path to the new ISO to be created"
			Start-Process "`"$oscdimg`"" -ArgumentList "-m -o -u2 -udfver102 -bootdata:2`#p0,e,b$srcPath\boot\etfsboot.com`#pEF,e,b$srcPath\efi\microsoft\boot\efisys.bin $srcPath $outFile" -Wait -NoNewWindow
			Clear-Host
			Write-Host "Done.`n"
		}
		4 {
			if ($pathToWim -ne $null) {
				$newPathToWim = Read-Host -Prompt "Path to dismounted WIM File (Default: $pathToWim)"
				if ($newPathToWim -ne "") {
					$pathToWim = $newPathToWim
				}
			} else {
				$pathToWim = Read-Host -Prompt "Path to dismounted ESD File"
				Write-Host $(Get-WindowsImage -ImagePath $pathToWim | Select-Object ImageName, ImageIndex | Out-String)
				$index = Read-Host -Prompt "Enter the index of the image you'd like to convert"
				$pathToEsd = $pathToWim
				$pathToWim = $($pathToWim.Replace("`"", "").TrimEnd(".esd") + ".wim")
				Dism.exe /Export-Image /SourceImageFile:$pathToEsd /SourceIndex:$index /DestinationImageFile:$pathToWim
				$ans = Read-Host -Prompt "$pathToEsd converted to $pathToWim`nWould you like to delete the ESD file? (y/n)"
				if ($ans -eq "y") {
					Remove-Item -Path $pathToEsd
				}
			}
		}
		5 {
			if ($pathToWim -ne $null) {
				$newPathToWim = Read-Host -Prompt "Path to dismounted WIM File (Default: $pathToWim)"
				if ($newPathToWim -ne "") {
					$pathToWim = $newPathToWim
				}
			} else {
				$pathToWim = Read-Host -Prompt "Path to dismounted WIM File"
			}
			Write-Host $(Get-WindowsImage -ImagePath $pathToWim | Select-Object ImageName, ImageIndex | Out-String)
			$indexes = Read-Host -Prompt "Enter the range of indexes to remove separated by hyphens and commas"
			$indexes = $indexes -replace " ", ""
			# Make removing indexes easier by allowing ranges:
			$indexes = $indexes.Replace("-", "..")
			$indexes = $indexes.Split(",")
			# Indexes get re-ordered when deleted from an image, so we cannot rely on the index number to be consistent. So we will store indexes by name before we begin deleting them:
			$indexNames = @()
			foreach ($index in $indexes) {
				if ($index.Contains("..")) {
					$min = [int]$index.Split("..")[0]
					$max = [int]$index.Split("..")[2]
					for($i = $min; $i -le $max; $i++) {
						$indexNames += Get-WindowsImage -ImagePath $pathToWim | Select-Object ImageName, ImageIndex | Where-Object {$_.ImageIndex -eq $i} | Select-Object -ExpandProperty ImageName
					}
				} else {
					$indexNames += Get-WindowsImage -ImagePath $pathToWim | Select-Object ImageName, ImageIndex | Where-Object {$_.ImageIndex -eq $index} | Select-Object -ExpandProperty ImageName
				}
			}
			foreach ($name in $indexNames) {
				Dism.exe /Delete-Image /ImageFile:$pathToWim /Name:$name
			}
			Clear-Host
			Write-Host "Done.`n"
		}
		6 {
			if ($pathToWim -ne $null) {
				$newPathToWim = Read-Host -Prompt "Path to mounted WIM File (Default: $pathToWim)"
				if ($newPathToWim -ne "") {
					$pathToWim = $newPathToWim
				}
			} else {
				$pathToWim = Read-Host -Prompt "Path to mounted WIM File"
			}
			$mountDir = Get-WindowsImage -Mounted | Select-Object ImagePath, Path | Where-Object {$_.ImagePath -eq $pathToWim} | Select-Object -ExpandProperty Path
			do {
				$locale = Read-Host -Prompt "Enter the locale code for the default language of the image (? for help)"
				if ($locale -eq "?") {
					Start-Process "https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/default-input-locales-for-windows-language-packs?view=windows-11"
				}
			} while ($locale -eq "?")
			Dism.exe /Image:$mountDir /Set-AllIntl:$locale
			$ans = Read-Host -Prompt "Would you like to add a fallback language? (y/n)"
			if ($ans -eq "y") {
				do {
					$fallbackLocale = Read-Host -Prompt "Enter the input locale code for the fallback language of the image (? for help)"
					if ($fallbackLocale -eq "?") {
						Start-Process "https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/default-input-locales-for-windows-language-packs?view=windows-11"
					}
				} while ($fallbackLocale -eq "?")
			}	
			Dism.exe /Image:$mountDir /Set-UILangFallBack:$fallbackLocale
			$ans = Read-Host "Would you like to set the default timezone for the image? (y/n)"
			if ($ans -eq "y") {
				do {
					$timeZone = Read-Host -Prompt "Enter the timezone name (e.g., 'W. Europe Standard Time') you would like to set for the image (? for help)"
					if ($timeZone -eq "?") {
						Start-Process "https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/default-time-zones?view=windows-11"
					}
				} while ($timeZone -eq "?")
				Dism.exe /Image:$mountDir /Set-TimeZone:"$timeZone"
			}
			Clear-Host
			Write-Host "Done.`n"
		}
		7 {
			if ($pathToWim -ne $null) {
				$newPathToWim = Read-Host -Prompt "Path to mounted WIM File (Default: $pathToWim)"
				if ($newPathToWim -ne "") {
					$pathToWim = $newPathToWim
				}
			} else {
				$pathToWim = Read-Host -Prompt "Path to mounted WIM File"
			}
			$mountDir = Get-WindowsImage -Mounted | Select-Object ImagePath, Path | Where-Object {$_.ImagePath -eq $pathToWim} | Select-Object -ExpandProperty Path
			$pathToStartFile = Read-Host -Prompt "Path to Start Menu Layout File"
			if ([IO.Path]::GetExtension($pathToStartFile) -eq ".xml") {
				$startFile = "LayoutModification.xml"
			} elseif ([IO.Path]::GetExtension($pathToStartFile) -eq ".json") {
				$startFile = "LayoutModification.json"
			}
			Copy-Item -Path $pathToStartFile -Destination "$mountDir\Users\Default\AppData\Local\Microsoft\Windows\Shell\$startFile" -Force
			Clear-Host
			Write-Host "Done.`n"
		}
		8 {
			if ($pathToWim -ne $null) {
				$newPathToWim = Read-Host -Prompt "Path to mounted WIM File (Default: $pathToWim)"
				if ($newPathToWim -ne "") {
					$pathToWim = $newPathToWim
				}
			} else {
				$pathToWim = Read-Host -Prompt "Path to mounted WIM File"
			}
			$mountDir = Get-WindowsImage -Mounted | Select-Object ImagePath, Path | Where-Object {$_.ImagePath -eq $pathToWim} | Select-Object -ExpandProperty Path
			$pathToAppAssoc = Read-Host -Prompt "Path to App Associations File"
			Dism.exe /Image:$mountDir /Import-DefaultAppAssociations:$pathToAppAssoc
			Clear-Host
			Write-Host "Done.`n"
		}
		9 {
			if ($pathToWim -ne $null) {
				$newPathToWim = Read-Host -Prompt "Path to mounted WIM File (Default: $pathToWim)"
				if ($newPathToWim -ne "") {
					$pathToWim = $newPathToWim
				}
			} else {
				$pathToWim = Read-Host -Prompt "Path to mounted WIM File"
			}
			$mountDir = Get-WindowsImage -Mounted | Select-Object ImagePath, Path | Where-Object {$_.ImagePath -eq $pathToWim} | Select-Object -ExpandProperty Path
			$pathToDrivers = Read-Host -Prompt "Path to driver or folder containing drivers"
			if ($pathToDrivers.Replace("`"").EndsWith(".inf")) {
				Dism.exe /Image:$mountDir /Add-Driver /Driver:$pathToDriver
			} else {
				Dism.exe /Image:$mountDir /Add-Driver /Driver:$pathToDriver /recurse
			}
			Clear-Host
			Write-Host "Done.`n"
		}
		10 {
			if ($pathToWim -ne $null) {
				$newPathToWim = Read-Host -Prompt "Path to mounted WIM File (Default: $pathToWim)"
				if ($newPathToWim -ne "") {
					$pathToWim = $newPathToWim
				}
			} else {
				$pathToWim = Read-Host -Prompt "Path to mounted WIM File"
			}
			$mountDir = Get-WindowsImage -Mounted | Select-Object ImagePath, Path | Where-Object {$_.ImagePath -eq $pathToWim} | Select-Object -ExpandProperty Path
			$pathToUpdates = Read-Host -Prompt "Path to update file(s)"
			Dism.exe /Image:$mountDir /Add-Package /PackagePath:$pathToUpdates
			Clear-Host
			Write-Host "Done.`n"
		}
		11 {
			if ($pathToWim -ne $null) {
				$newPathToWim = Read-Host -Prompt "Path to mounted WIM File (Default: $pathToWim)"
				if ($newPathToWim -ne "") {
					$pathToWim = $newPathToWim
				}
			} else {
				$pathToWim = Read-Host -Prompt "Path to mounted WIM File"
			}
			$mountDir = Get-WindowsImage -Mounted | Select-Object ImagePath, Path | Where-Object {$_.ImagePath -eq $pathToWim} | Select-Object -ExpandProperty Path
			$appsToRemove = ""
			$packages = @()
			do {
				$appsToRemove = Read-Host -Prompt "Enter the package name of the app you want to remove, or specify a path to a .txt file to remove multiple apps (? to view package names)"
				if ($appsToRemove.Replace("`"", "").EndsWith(".txt")) {
					foreach ($line in $(Get-Content $appsToRemove)) {
						$packages += " /PackageName:$line"
					}
				} elseif ($appsToRemove -eq "?") {
					Get-AppxProvisionedPackage -Path $mountDir | Format-Table DisplayName, PackageName
				} else {
					$packages = $appsToRemove
				}
			} while ($appsToRemove -eq "?")
			foreach ($package in $packages) {
				Invoke-Expression ("Dism.exe /Image:$mountDir /Remove-ProvisionedAppxPackage" + $package)
			}
			Clear-Host
			Write-Host "Done.`n"
		}
		12 {
			if ($pathToWim -ne $null) {
				$newPathToWim = Read-Host -Prompt "Path to mounted WIM File (Default: $pathToWim)"
				if ($newPathToWim -ne "") {
					$pathToWim = $newPathToWim
				}
			} else {
				$pathToWim = Read-Host -Prompt "Path to mounted WIM File"
			}
			$mountDir = Get-WindowsImage -Mounted | Select-Object ImagePath, Path | Where-Object {$_.ImagePath -eq $pathToWim} | Select-Object -ExpandProperty Path
			$pathToAnswerFile = Read-Host -Prompt "Path to Answer File"
			Dism.exe /Image:$mountDir /Apply-Unattend:$pathToAnswerFile
			Clear-Host
			Write-Host "Done.`n"
		}
		13 {
			if ($pathToWim -ne $null) {
				$newPathToWim = Read-Host -Prompt "Path to mounted WIM File (Default: $pathToWim)"
				if ($newPathToWim -ne "") {
					$pathToWim = $newPathToWim
				}
			} else {
				$pathToWim = Read-Host -Prompt "Path to mounted WIM File"
			}
			$mountDir = Get-WindowsImage -Mounted | Select-Object ImagePath, Path | Where-Object {$_.ImagePath -eq $pathToWim} | Select-Object -ExpandProperty Path
			$mountDir = Get-WindowsImage -Mounted | Select-Object ImagePath, Path | Where-Object {$_.ImagePath -eq $pathToWim} | Select-Object -ExpandProperty Path
			$ans = Read-Host -Prompt "Do you want to save the changes you made to the WIM image? (y/n)"
			if ($ans -eq "y") {
				$save = "/Commit"
			} else {
				$save = "/Discard"
			}
			if ($save -eq "/Commit") {
				Invoke-Expression "Dism.exe /Image:$mountDir /Cleanup-Image /StartComponentCleanup /ResetBase"
			}
			Invoke-Expression "Dism.exe /Unmount-Image /MountDir:$mountDir $save"
			Clear-Host
			Write-Host "Done.`n"
		}
		14 {
			Exit
		}
	}
} while ($userChoice -ne 14)