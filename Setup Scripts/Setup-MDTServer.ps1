## If the script was not ran with administrative rights, elevate
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process Powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -NoNewWindow" -Verb RunAs
	Exit
}
## TOOD: Finish prompting for initial questions
$sharesDir = Read-Host "Type the path where the MDT shares should be created"
$LCU_OS = Read-Host "What version of Windows is the latest WinPE based on? (i.e., `"Microsoft Server Operating System version 23H2 x64`", `"Windows 11 version 23H2 x64`")"
$delayDomainJoin = Read-Host "Do you want to domain join after or during an image deployment (A = after; D = during)"
$wantHighPerformance = Read-Host "Do you want to configure the task sequences to run at high performance mode? (Y/N)"
# TODO: Make these arrays and loop to grab as many ISOs as needed
# TODO: Modify prompts to allow for deploying server OS's
$windowsVersion = Read-Host "What version of Windows do you want to deploy? (10/11)"
$windowsRelease = Read-Host "What release of Windows do you want to deploy? (21H2, 22H2, etc.)"
$windowsEdition = Read-Host "What edition of Windows do you want to deploy? (Pro, Enterprise, etc.)"
$mdtUsers = "Enter the name of the AD group of users who can read from the MDT shares"
$mdtAdmins = "Enter the name of the AD group of users who can modify the MDT shares"
$buildSA = Read-Host "Enter the username of the service account used to build MDT images"
$domainJoinSA = Read-Host "Enter the username of the service account used to join the domain during deployments"
$wsusServer = Read-Host "Enter a WSUS server to deploy updates from (blank for none)"
## Global variables
$ProgressPreference = 'SilentlyContinue'
$locale = Get-Culture | Select-Object -ExpandProperty Name
## Functions
function Test-DownloadLink {
    param($Url)
    try { return (Invoke-WebRequest -Uri $Url -Method Head).StatusCode -eq 200 }
    catch { return $false }
}
## TODO: Potentially create service accounts and MDT groups
## TODO: Disable NetBIOS/TCP
## TODO: Install and configure WDS
## Install the necessary prerequisite software
 # Windows ADK (Latest)
Write-Host "Downloading the Windows ADK..."
$ProgressPreference = 'SilentlyContinue'
$redirectLink = Invoke-WebRequest -UseBasicParsing -Uri "https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install" | Select-Object -ExpandProperty Links | Where-Object {$_.outerHTML -like "*Download the Windows ADK*"} | Select-Object -First 1 | Select-Object -ExpandProperty href
$request = [System.Net.WebRequest]::Create($redirectLink)
$request.AllowAutoRedirect=$false
$response=$request.GetResponse()
$dlLink = $response.GetResponseHeader("Location")
$file = [System.IO.Path]::GetFileName($dlLink)
$InstallerPath = Join-Path $env:TEMP $file
(New-Object System.Net.WebClient).DownloadFile($dlLink, $InstallerPath)
Write-Host "Windows ADK Download Complete."
Write-Host "Installing the Windows ADK..."
Start-Process $InstallerPath -Wait -ArgumentList "/features OptionId.DeploymentTools OptionId.UserStateMigrationTool /q" -Verb RunAs
Write-Host "ADK Installed."
 # Windows PE Add-on for the Windows ADK
Write-Host "Downloading the Windows PE Add-on..."
$redirectLink = Invoke-WebRequest -UseBasicParsing -Uri "https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install" | Select-Object -ExpandProperty Links | Where-Object {$_.outerHTML -like "*Download the Windows PE add-on for the Windows ADK*"} | Select-Object -First 1 | Select-Object -ExpandProperty href
$request = [System.Net.WebRequest]::Create($redirectLink)
$request.AllowAutoRedirect=$false
$response=$request.GetResponse()
$dlLink = $response.GetResponseHeader("Location")
$file = [System.IO.Path]::GetFileName($dlLink)
$InstallerPath = Join-Path $env:TEMP $file
(New-Object System.Net.WebClient).DownloadFile($dlLink, $InstallerPath)
Write-Host "Windows PE Add-on Download Complete"
Write-Host "Installing the Windows PE Add-on..."
Start-Process $InstallerPath -Wait -ArgumentList "/features + /q" -Verb RunAs
Write-Host "Windows PE Add-on Installed"
## WinPE Modifications to work with MDT
 # Add x86 support for the WinPE
New-Item -ItemType Directory -Path "$env:ProgramFiles (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\x86\WinPE_OCs" | Out-Null
Write-Host "Added x86 folder structure to the WinPE."
 # Add support for HTA applications
 $fileContents =
 '<?xml version="1.0" encoding="utf-8"?>
 <unattend xmlns="urn:schemas-microsoft-com:unattend">
     <settings pass="windowsPE">
         <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
             <Display>
                 <ColorDepth>32</ColorDepth>
                 <HorizontalResolution>1024</HorizontalResolution>
                 <RefreshRate>60</RefreshRate>
                 <VerticalResolution>768</VerticalResolution>
             </Display>
             <RunSynchronous>
                 <RunSynchronousCommand wcm:action="add">
                     <Description>Lite Touch PE</Description>
                     <Order>1</Order>
                     <Path>reg.exe add "HKLM\Software\Microsoft\Internet Explorer\Main" /t REG_DWORD /v JscriptReplacement /d 0 /f</Path>
                 </RunSynchronousCommand>
                 <RunSynchronousCommand wcm:action="add">
                     <Description>Lite Touch PE</Description>
                     <Order>2</Order>
                     <Path>wscript.exe X:\Deploy\Scripts\LiteTouch.wsf</Path>
                 </RunSynchronousCommand>
             </RunSynchronous>
         </component>
     </settings>
 </unattend>'
 Set-Content -Path "$env:ProgramFiles\Microsoft Deployment Toolkit\Templates\Unattend_PE_x64.xml" -Value $fileContents 
Write-Host "Added support for HTA applications to the WinPE."
## Patch the WinPE Media with the LCU for the appropriate Windows version
 # Mount the WinPE media
$peWimFilePath = $"{env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\$locale\winpe.wim"
$mountDir = "$env:SystemDrive\Mount"
if (-not (Test-Path "$mountDir")) {
    Write-Host "Creating mount directory: $mountDir"
    New-Item -Path $mountDir -ItemType Directory | Out-Null
    Write-Host "Mount directory created."
}
Write-Host "Mounting the WinPE WIM file..."
Mount-WindowsImage -ImagePath $peWimFilePath -Path $mountDir -Optimize
Write-Host "WinPE mounted successfully."
 # Determine the needed update. Since the download page for Windows ADK only recently started to show this, prompt for input since this might not work in the future.
 # Get the download link for the latest update
Write-Host "Downloading the latest cumulative update for $LCU_OS..."
$queryResponse = Invoke-WebRequest -UseBasicParsing -Uri "https://www.catalog.update.microsoft.com/Search.aspx?q=$LCU_OS" | Select-Object -ExpandProperty Links | Where-Object {$_.outerHTML -like "*20*-* Cumulative Update for * x64*" } | Select-Object -First 1 -ExpandProperty outerHTML
If ($queryResponse -match '\(KB(\d+)\)') { $ArticleId = 'KB' + $matches[1] }
$DownloadLink = @()
$UpdateIdResponse = Invoke-WebRequest -Uri "https://www.catalog.update.microsoft.com/Search.aspx?q=$ArticleId" -Method GET -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:104.0) Gecko/20100101 Firefox/104.0' -ContentType 'text/html; charset=utf-8' -UseBasicParsing
$DownloadOptions = ($UpdateIdResponse.Links | Where-Object -Property ID -like "*_link")
$Architecture = "x64"
$DownloadOptions = $DownloadOptions | Where-Object -FilterScript { $_.OuterHTML -like "*$($OperatingSystem)*" -and $_.OuterHTML -notlike "*Dynamic*" }
$DownloadOptions = $DownloadOptions | Where-Object -FilterScript { $_.OuterHTML -like "*$($Architecture)*" }
$Guid = $DownloadOptions.id.Replace("_link","")
Write-Verbose -Message "Downloading information for $($ArticleID) $($Guid)"
$Body = @{ UpdateIDs = "[$(@{ Size = 0; UpdateID = $Guid; UidInfo = $Guid } | ConvertTo-Json -Compress)]" }
$LinksResponse = (Invoke-WebRequest -Uri 'https://catalog.update.microsoft.com/DownloadDialog.aspx' -Method POST -Body $Body -UseBasicParsing -SessionVariable WebSession).Content 
$DownloadLink += ($LinksResponse.Split("$([Environment]::NewLine)") | Select-String -Pattern 'downloadInformation' | Select-String -Pattern 'url' | Out-String).Trim()
$DownloadLink = ($LinksResponse.Split("$([Environment]::NewLine)") | Select-String -Pattern 'downloadInformation' | Select-String -Pattern 'url' | Out-String).Trim().Split("'")[-2]
$msuFile = $DownloadLink -split "/" | Select-Object -Last 1
 # Download the LCU
$msuFilePath = Join-Path $env:TEMP $msuFile
(New-Object System.Net.WebClient).DownloadFile($DownloadLink, $msuFilePath)
Write-Host "Finished downloading the latest cumulative update for $LCU_OS."
Write-Host "Applying the latest cumulative update to the Windows PE media. This will take some time..."
Add-WindowsPackage -PackagePath $msuFilePath -Path $mountDir
Write-Host "Package added successfully."
Remove-Item $msuFilePath -Force
Write-Host "Cleaning up the image..."
Repair-WindowsImage -Path $mountDir -StartComponentCleanup -ResetBase
Write-Host "Dismounting the WinPE WIM file..."
Dismount-WindowsImage -Path $mountDir -Save
## Download and install Microsoft Deployment Toolkit (MDT)
Write-Host "Downloading Microsoft Deployment Toolkit (MDT)..."
$dlLink = "https://download.microsoft.com/download/3/3/9/339BE62D-B4B8-4956-B58D-73C4685FC492/MicrosoftDeploymentToolkit_x64.msi" # Likely safe to hardcode as this will probably never be updated again
$file = $dlLink -split "/" | Select-Object -Last 1
$InstallerPath = Join-Path $env:TEMP $file
(New-Object System.Net.WebClient).DownloadFile($dlLink, $InstallerPath)
Write-Host "Installing Microsoft Deployment Toolkit (MDT)..."
Start-Process msiexec.exe -Wait -ArgumentList "/i $InstallerPath /qn" -Verb RunAs
Write-Host "MDT Installed successfully."
## Apply patch for MDT BIOS detection
Write-Host "Downloading MDT firmware detection patch..."
$dlLink = "https://download.microsoft.com/download/3/0/6/306AC1B2-59BE-43B8-8C65-E141EF287A5E/KB4564442/MDT_KB4564442.exe"
$file = $dlLink -split "/" | Select-Object -Last 1
$InstallerPath = Join-Path $env:TEMP $file
(New-Object System.Net.WebClient).DownloadFile($dlLink, $InstallerPath)
Write-Host "Applying MDT firmware patch..."
$dumpFolder = Join-Path $env:TEMP "MDT_Patch"
Start-Process $InstallerPath -Wait -ArgumentList "-q -extract:$dumpFolder"
Move-Item -Path "$dumpFolder\x64\*" -Destination "$env:ProgramFiles\Microsoft Deployment Toolkit\Templates\Distribution\Tools\x64"
Move-Item -Path "$dumpFolder\x86\*" -Destination "$env:ProgramFiles\Microsoft Deployment Toolkit\Templates\Distribution\Tools\x86"
Remove-Item $dumpFolder -Force
Remove-Item $InstallerPath -Force
Write-Host "Successfully applied MDT firmware patch."
## MDT Modifications
Write-Host "Applying MDT Modifications..."
$mdtScriptDir = "$env:ProgramFiles\Microsoft Deployment Toolkit\Templates\Distribution\Scripts"
# Custom rules per task sequence
$dlLink = "https://raw.githubusercontent.com/tylerlurie/Workbench/main/MDT%20Modifications/DeployWiz_SelectTS.vbs"
$file = $dlLink -split "/" | Select-Object -Last 1
$outputPath = Join-Path $mdtScriptDir $file
(New-Object System.Net.WebClient).DownloadFile($dlLink, $outputPath)
Write-Host "Modified $file to allow rule customization per task sequence."
$dlLink = "https://raw.githubusercontent.com/tylerlurie/Workbench/main/MDT%20Modifications/ZTIBde.wsf"
$file = $dlLink -split "/" | Select-Object -Last 1
$outputPath = Join-Path $mdtScriptDir $file
(New-Object System.Net.WebClient).DownloadFile($dlLink, $outputPath)
Write-Host "Modified $file and applied fix for BitLocker for Windows Server 2022"
# Adjust the default unattend.xml files for HideShell
$xmlFiles = "Unattend_Core_x64.xml.10.0.xml", "Unattend_Core_x86.xml.10.0.xml", "Unattend_x64.xml.10.0.xml", "Unattend_x86.xml.10.0.xml"
foreach ($xml in $xmlFiles) {
    $dlLink = "https://raw.githubusercontent.com/tylerlurie/Workbench/main/MDT%20Modifications/$xml"
    $file = $dlLink -split "/" | Select-Object -Last 1
    $outputPath = Join-Path "$env:ProgramFiles\Microsoft Deployment Toolkit\Templates\" $file
    (New-Object System.Net.WebClient).DownloadFile($dlLink, $outputPath)
}
# Add the fix for LTICleanup.wsf
$dlLink = "https://raw.githubusercontent.com/tylerlurie/Workbench/main/MDT%20Modifications/LTICleanup.wsf"
$file = $dlLink -split "/" | Select-Object -Last 1
$outputPath = Join-Path $mdtScriptDir $file
(New-Object System.Net.WebClient).DownloadFile($dlLink, $outputPath)
Write-Host "Fixed support for the HideShell command"
# Delay domain joining until the end of the task sequence if the user chose to
If ($delayDomainJoin -eq "A") {
    Write-Host "Delaying domain join to the end of new task sequences by default..."
    $dlLink = "https://raw.githubusercontent.com/tylerlurie/Workbench/main/MDT%20Modifications/ZTIDomainJoinDelayed.wsf"
    $file = $dlLink -split "/" | Select-Object -Last 1
    $outputPath = Join-Path $mdtScriptDir $file
    (New-Object System.Net.WebClient).DownloadFile($dlLink, $outputPath)
    Write-Host "Added ZTIDomainJoinDelayed.wsf to the MDT Scripts path."
    $xmlFiles = "Unattend_Core_x64.xml.10.0.xml", "Unattend_Core_x86.xml.10.0.xml", "Unattend_x64.xml.10.0.xml", "Unattend_x86.xml.10.0.xml"
    foreach ($xml in $xmlFiles) {
    [xml]$xml = Get-Content "$env:ProgramFiles\Microsoft Deployment Toolkit\Templates\$xml"
    $components = $xml.unattend.settings | Where-Object { $_.pass -eq "specialize" } | Select-Object -ExpandProperty component
    $componentToRemove = $components | Where-Object { $_.name -eq "Microsoft-Windows-UnattendedJoin" }
    if ($null -ne $componentToRemove) { $componentToRemove.ParentNode.RemoveChild($componentToRemove) | Out-Null }
    $xml.Save("$env:ProgramFiles\Microsoft Deployment Toolkit\Templates\$xml")
    }
    Write-Host "Modified the default unattend.xml files to delay domain joining until the end of the task sequence."
    $xmlFiles = @("Client.xml", "Server.xml")
    $templatePath = "$env:ProgramFiles\Microsoft Deployment Toolkit\Templates"

    foreach ($xmlFileName in $xmlFiles) {
        $xmlFilePath = Join-Path -Path $templatePath -ChildPath $xmlFileName
        [xml]$xml = Get-Content -Path $xmlFilePath
        $steps = $xml.sequence.group.step
        $stepToRemove = $steps | Where-Object { $_.type -eq "BDD_RecoverDomainJoin" -and $_.name -eq "Recover From Domain " }
        if ($null -ne $stepToRemove) { $stepToRemove.ParentNode.RemoveChild($stepToRemove) | Out-Null }
        $newStep = $xml.CreateElement("step")
        $newStep.SetAttribute("type", "SMS_TaskSequence_RunCommandLineAction")
        $newStep.SetAttribute("name", "Join Domain")
        $newStep.SetAttribute("disable", "false")
        $newStep.SetAttribute("continueOnError", "false")
        $newStep.SetAttribute("startIn", "")
        $newStep.SetAttribute("successCodeList", "0 3010")
        $newStep.SetAttribute("runIn", "WinPEandFullOS")
        $newStep.InnerXml = @"
<defaultVarList>
  <variable name="PackageID" property="PackageID"></variable>
  <variable name="RunAsUser" property="RunAsUser">false</variable>
  <variable name="SMSTSRunCommandLineUserName" property="SMSTSRunCommandLineUserName"></variable>
  <variable name="SMSTSRunCommandLineUserPassword" property="SMSTSRunCommandLineUserPassword"></variable>
  <variable name="LoadProfile" property="LoadProfile">false</variable>
</defaultVarList>
<action>cscript.exe %SCRIPTROOT%\ZTIDomainJoinDelayed.wsf</action>
"@
        $targetStepName = "Restore User State"
        $targetStep = $steps | Where-Object { $_.name -eq $targetStepName }
        if ($null -ne $targetStep) { $targetStep.ParentNode.InsertBefore($newStep, $targetStep) | Out-Null }
        $xml.Save($xmlFilePath)
    }
    Write-Host "Domain join step adjusted and recover step removed from task sequences."
}
If ($wantHighPerformance -eq "Y") {
    Write-Host "Adding High Performance Power Plan steps into default task sequences..."
    $xmlFiles = @("Client.xml", "Server.xml")
    $templatePath = "$env:ProgramFiles\Microsoft Deployment Toolkit\Templates"
    foreach ($xmlFileName in $xmlFiles) {
        $xmlFilePath = Join-Path -Path $templatePath -ChildPath $xmlFileName
        $xml = [xml](Get-Content $xmlFile)
        $highPerformanceCommand = "cmd /c powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
        $balancedPlanCommand = "cmd /c powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e"
        function InsertStep($groupName, $stepName, $newStepName, $actionCommand) {
            $targetStep = $xml.SelectNodes("//group[@name='$groupName']/step[@name='$stepName']")
            $newNode = $xml.CreateElement("step")
            $newNode.SetAttribute("type", "SMS_TaskSequence_RunCommandLineAction")
            $newNode.SetAttribute("name", $newStepName)
            $newNode.SetAttribute("description", "")
            $newNode.SetAttribute("disable", "false")
            $newNode.SetAttribute("continueOnError", "true")
            $newNode.SetAttribute("startIn", "")
            $newNode.SetAttribute("successCodeList", "0 3010")
            $newNode.SetAttribute("runIn", "WinPEandFullOS")
            $actionNode = $xml.CreateElement("action")
            $actionNode.InnerText = $actionCommand
            $newNode.AppendChild($actionNode)
            $targetStep.ParentNode.InsertAfter($newNode, $targetStep)
        }
        InsertStep "Preinstall" "Gather local only" "Set High Performance Plan" $highPerformanceCommand
        InsertStep "State Restore" "Gather local only" "Set High Performance Plan" $highPerformanceCommand
        InsertStep "Capture Image" "Gather local only" "Set High Performance Plan" $highPerformanceCommand
        InsertStep "State Restore" "Enable BitLocker" "Set Balanced Plan" $balancedPlanCommand
        $xml.Save($xmlFile)
    }
    Write-Host "Successfully added High Performance Power Plan steps into default task sequences."
}
# Fix the generating of Windows Catalog files:
Write-Host "Applying fix for generating Windows Catalog files..."
# Define the path to the DeploymentTools.xml file
$xmlFile = "$env:ProgramFiles\Microsoft Deployment Toolkit\Bin\DeploymentTools.xml"
$xml = [xml](Get-Content $xmlFile)
$toolNode = $xml.SelectSingleNode("//tool[@name='imgmgr.exe']")
$toolNode.InnerText = "%ADKPath%\Deployment Tools\WSIM\%RealPlatform%"
$xml.Save($xmlFile)
Write-Host "Catalog file fix applied successfully."
# Download Windows ISOs
$scriptLink = "https://raw.githubusercontent.com/tylerlurie/Workbench/main/WIM%20Image%20Modifications/WindowsISODownloader.ps1"
$scriptFile = $scriptLink -split "/" | Select-Object -Last 1
$scriptPath = Join-Path ($env:TEMP, $scriptFile)
Write-Host "Downloading ISO file..."
(New-Object System.Net.WebClient).DownloadFile($scriptLink, $scriptPath)
Set-ExecutionPolicy -Scope CurrentUser Bypass
& $scriptPath -Type "Client" -Version $windowsVersion -Release $windowsRelease -Edition $windowsEdition -Locale $locale -OutputDir $env:TEMP
$isoFile = Get-ChildItem -Path $env:TEMP -Filter *.iso | Select-Object -ExpandProperty Name
Write-Host "$isoFile downloaded successfully to $env:TEMP\$isoFile"
Write-Host "Removing additional indexes..."
Mount-DiskImage -ImagePath "$env:TEMP\$isoFile" -NoDriveLetter | Out-Null
$ISOPath = Get-DiskImage "$env:TEMP\$isoFile" | Select-Object DevicePath -ExpandProperty DevicePath
$isoExtractDir = $isoFile.Substring(0, $isoFile.LastIndexOf("."))
Copy-Item -Path "$ISOPath\" -Destination "$env:TEMP\$isoExtractDir" -Recurse
Dismount-DiskImage -ImagePath "$env:TEMP\$isoFile" | Out-Null
$images = Get-WindowsImage -ImagePath "$env:TEMP\$isoExtractDir\sources\install.wim" | Select-Object -ExpandProperty ImageName
ForEach ($image in $images) {
    If ($windowsEdition -ne $image) { Remove-WindowsImage -ImagePath "$env:TEMP\$isoExtractDir\sources\install.wim" -Name $image }
}
Write-Host "Removed all unnecessary editions of Windows."
Import-Module "$env:ProgramFiles\Microsoft Deployment Toolkit\bin\MicrosoftDeploymentToolkit.psd1"
## Create the shares
# Define variables
$netBIOSDomainName = $env:USERDOMAIN
$buildSharePath = "$sharesDir\BuildShare"
$deploySharePath = "$sharesDir\DeployShare"
# Create the main directories if they do not already exist
If (-not (Test-Path -Path $buildSharePath)) {
New-Item -ItemType Directory -Path $buildSharePath
}
If (-not (Test-Path -Path $deploySharePath)) {
New-Item -ItemType Directory -Path $deploySharePath
}
# Share the directories with hidden shares and set full access permissions
New-SmbShare -Name "BuildShare$" -Path $buildSharePath -FullAccess "$netBIOSDomainName\$mdtAdmins", "$netBIOSDomainName\$buildSA"
New-SmbShare -Name "DeployShare$" -Path $deploySharePath -FullAccess "$netBIOSDomainName\$mdtAdmins", "$netBIOSDomainName\$mdtUsers"
New-PSDrive -Name "DS001" -PSProvider "MDTProvider" -Root "$MdtBuildShare" -Description "MDT Build Share" -NetworkPath "\\$env:ComputerName\BuildShare`$" | Add-MDTPersistentDrive | Out-Null
New-Item -Path "DS001:\Operating Systems\Windows $windowsVersion $windowsRelease" -ItemType Directory | Out-Null
Write-Host "Creating WinPE Selection Profile..."
New-Item -Path "DS001:\Packages\WinPE" -ItemType Directory | Out-Null
New-Item -Path "DS001:\Selection Profiles" -enable "True" -Name "WinPE" -Comments "" -Definition "<SelectionProfile><Include path=`"Packages\WinPE`" /></SelectionProfile>" -ReadOnly "False" | Out-Null
Write-Host "Creating the Build Task Sequence..."
Import-MDTOperatingSystem -Path "DS001:\Operating Systems\Windows $windowsVersion $windowsRelease" -SourcePath "$env:TEMP\$isoExtractDir" -DestinationFolder "$windowsVersion $windowsRelease $windowsEdition" | Out-Null
Import-MdtTaskSequence -Path "DS001:\Task Sequences" -Name "Build a Windows $windowsVersion $windowsRelease Reference Image" -Template "$env:ProgramFiles\Microsoft Deployment Toolkit\Templates\Client.xml"
Write-Host "Build Task Sequence created successfully."
Write-Host "Adjusting CustomSettings.ini..."
$customSettingsContent =
'[Settings]
Priority=Default, TaskSequenceID
Properties=MyCustomProperty

[Default]
_SMSTSORGNAME=Organization
_SMSTSPackageName=%TaskSequenceName%
; Comment this in with valid TSID to skip the Task Sequence selection screen
;TaskSequenceID=OS-XXXX-B
OSInstall=Y
DriverSelectionProfile=Nothing
DriverInjectionMode=All
SkipCapture=YES
SkipAdminPassword=YES
SkipProductKey=YES
SkipComputerBackup=YES
SkipBitLocker=YES
; Comment this in to skip the Task Sequence selection screen
;SkipTaskSequence=YES
SkipApplications=YES
SkipComputerName=YES
TimeZoneName=' + $(Get-Timezone).Id + '
KeyboardLocale=en-US
UILanguage=en-US
UserLocale=en-US
BitsPerPel=32
VRefresh=60
XResolution=1
YResolution=1
SkipUserData=YES
SkipDomainMembership=YES
SkipLocaleSelection=YES
SkipTimeZone=YES
SkipSummary=YES
SkipFinalSummary=YES
FinishAction=SHUTDOWN
WSUSServer=http://' + $wsusServer + ':8530
SLShare=\\' + $env:COMPUTERNAME + '\BuildShare$\Logs
EventService=http://' + $env:COMPUTERNAME + ':9800
DoCapture=YES
ComputerBackupLocation=\\' + $env:COMPUTERNAME + '\BuildShare$\Captures
BackupFile=install-#year(date) & "-" & month(date) & "-" & day(date) & "-" & hour(time) & "-" & minute(time)#.wim
HideShell=NO'
# Remove the line for WSUS server if one wasn't supplied:
If ($wsusServer -eq '') { $customSettingsContent = $customSettingsContent.Replace('WSUSServer=http://' + $wsusServer + ':8530' + "`n", "") }
Out-File -FilePath "$buildSharePath\Control\Settings.xml" -Encoding utf8 -InputObject $customSettingsContent -Force
## Change MDT config to disable x86 support for boot media
Write-Host "Removing support for x86..."
$XMLContent = Get-Content "$buildSharePath\Control\Settings.xml"
$XMLContent = $XMLContent -Replace '<SupportX86>True</SupportX86>','<SupportX86>False</SupportX86>'
$XMLContent | Out-File "$buildSharePath\Control\Settings.xml"
Write-Host "Done creating build share."
## Deploy Share:
New-PSDrive -Name "DS002" -PSProvider "MDTProvider" -Root "$MdtBuildShare" -Description "MDT Deploy Share" -NetworkPath "\\$env:ComputerName\DeployShare`$" | Add-MDTPersistentDrive | Out-Null
New-Item -Path "DS002:\Operating Systems\Windows $windowsVersion $windowsRelease" -ItemType Directory | Out-Null
Write-Host "Creating WinPE Selection Profile..."
New-Item -Path "DS002:\Packages\WinPE" -ItemType Directory | Out-Null
New-Item -Path "DS002:\Selection Profiles" -enable "True" -Name "WinPE" -Comments "" -Definition "<SelectionProfile><Include path=`"Packages\WinPE`" /></SelectionProfile>" -ReadOnly "False" | Out-Null
Write-Host "Creating the Build Task Sequence..."
Import-MdtTaskSequence -Path "DS002:\Task Sequences" -Name "Build a Windows $windowsVersion $windowsRelease Reference Image" -Template "$env:ProgramFiles\Microsoft Deployment Toolkit\Templates\Client.xml" -Comments "" -ID "W$windowsVersion-$windowsRelease-B" -Version "1.0" -OperatingSystemPath "DS001\Operating Systems\Windows $windowsVersion $windowsRelease"
Write-Host "Build Task Sequence created successfully."
Write-Host "Adjusting CustomSettings.ini..."
$customSettingsContent =
'[Settings]
Priority=Default, TaskSequenceID
Properties=MyCustomProperty

[Default]
_SMSTSORGNAME=Organization
_SMSTSPackageName=%TaskSequenceName%
; Comment this in with valid TSID to skip the Task Sequence selection screen
;TaskSequenceID=OS-XXXX-B
OSInstall=Y
DriverSelectionProfile=Nothing
DriverInjectionMode=All
SkipCapture=YES
SkipAdminPassword=YES
SkipProductKey=YES
SkipComputerBackup=YES
SkipBitLocker=YES
; Comment this in to skip the Task Sequence selection screen
;SkipTaskSequence=YES
SkipApplications=YES
SkipComputerName=YES
TimeZoneName=' + $(Get-Timezone).Id + '
KeyboardLocale=en-US
UILanguage=en-US
UserLocale=en-US
BitsPerPel=32
VRefresh=60
XResolution=1
YResolution=1
SkipUserData=YES
SkipDomainMembership=YES
SkipLocaleSelection=YES
SkipTimeZone=YES
SkipSummary=YES
SkipFinalSummary=YES
FinishAction=SHUTDOWN
WSUSServer=http://' + $wsusServer + ':8530
SLShare=\\' + $env:COMPUTERNAME + '\BuildShare$\Logs
EventService=http://' + $env:COMPUTERNAME + ':9800
DoCapture=YES
ComputerBackupLocation=\\' + $env:COMPUTERNAME + '\BuildShare$\Captures
BackupFile=install-#year(date) & "-" & month(date) & "-" & day(date) & "-" & hour(time) & "-" & minute(time)#.wim
HideShell=NO'
# Remove the line for WSUS server if one wasn't supplied:
If ($wsusServer -eq '') { $customSettingsContent = $customSettingsContent.Replace('WSUSServer=http://' + $wsusServer + ':8530' + "`n", "") }
Out-File -FilePath "$buildSharePath\Control\Settings.xml" -Encoding utf8 -InputObject $customSettingsContent -Force
## Change MDT config to disable x86 support for boot media
Write-Host "Removing support for x86..."
$XMLContent = Get-Content "$buildSharePath\Control\Settings.xml"
$XMLContent = $XMLContent -Replace '<SupportX86>True</SupportX86>','<SupportX86>False</SupportX86>'
$XMLContent | Out-File "$buildSharePath\Control\Settings.xml"
Write-Host "Done creating build share."
