<#PSScriptInfo
.VERSION 1.0
.AUTHOR Tyler Lurie
.DESCRIPTION
Downloads Windows ISO files from Microsoft.
.RELEASENOTES
Version 1.0: Original version
#>
<#
.PARAMETER Type
The type of OS ISO to download (client, server)
.PARAMETER Version
The version of Windows to be downloaded (8.1, 10, 11)
.PARAMETER Release
The release of the Windows OS to download (i.e., 1909, 2004, 21H1, 21H2, etc.)
.PARAMETER Edition
The edition of Windows to download (i..e, Home, Professional, Enterprise)
.PARAMETER Locale
The locale of the ISO to download (i.e., en-US, fr-FR). Defaults to the locale of the OS the script runs on
.PARAMETER GetUrl
Only retrieve the URL of the file to download
.PARAMETER OutputDir
The directory to download the ISO file to. Defaults to the script directory
#>

param (
    [Parameter(Mandatory = $true)][String]$Type,
    [Parameter(Mandatory = $true)][String]$Version,
    [Parameter(Mandatory = $false)][String]$Release,
    [Parameter(Mandatory = $true)][String[]]$Edition,
    [Parameter(Mandatory = $false)][String]$Locale = (Get-Culture).Name,
    [Parameter(Mandatory = $false)][Switch]$GetUrl,
    [Parameter(Mandatory = $false)][String]$OutputDir = $PSScriptRoot
)

# Global Variables
$ProgressPreference = 'SilentlyContinue'
$LocaleLanguageMap = @{
    "ar-SA" = "Arabic"
    "bg-BG" = "Bulgarian"
    "pt-BR" = "BrazilianPortuguese"
    "zh-CN" = "Chinese_Simplified"
    "zh-TW" = "Chinese_Traditional"
    "hr-HR" = "Croatian"
    "cs-CZ" = "Czech"
    "da-DK" = "Danish"
    "nl-NL" = "Dutch"
    "en-US" = "English"
    "en-GB" = "EnglishInternational"; "en-AU" = "EnglishInternational"; "en-CA" = "EnglishInternational"; "en-NZ" = "EnglishInternational"
    "et-EE" = "Estonian"
    "fi-FI" = "Finnish"
    "fr-FR" = "French"
    "fr-CA" = "FrenchCanadian"
    "de-DE" = "German"
    "el-GR" = "Greek"
    "he-IL" = "Hebrew"
    "hu-HU" = "Hungarian"
    "it-IT" = "Italian"
    "ja-JP" = "Japanese"
    "ko-KR" = "Korean"
    "lv-LV" = "Latvian"
    "lt-LT" = "Lithuanian"
    "no-NO" = "Norwegian"
    "pl-PL" = "Polish"
    "pt-PT" = "Portuguese"
    "ro-RO" = "Romanian"
    "ru-RU" = "Russian"
    "sr-Latn-RS" = "SerbianLatin"
    "sk-SK" = "Slovak"
    "sl-SI" = "Slovenian"
    "es-ES" = "Spanish"
    "es-MX" = "Spanish_Mexico"
    "sv-SE" = "Swedish"
    "th-TH" = "Thai"
    "tr-TR" = "Turkish"
    "uk-UA" = "Ukrainian"
}
$validClientVersions = @("8.1", "10", "11")
$validServerVersions = @("2012-R2", "2016", "2019", "2022")
# Provide flexibility on the editions to prevent having to update this script every 6-12 months...
# Hopefully the user inputs that correctly.
$validClientEditions = @("Home", "Professional", "Enterprise", "Education", "ProfessionalWorkstation")
$validServerEditions = @("ServerStandard", "ServerDatacenter")
$validLocales = $LocaleLanguageMap.keys
$firstOSReleases = @{
	"10" = "1507"
	"11" = "21H2"
}
# Functions
# Check if the download link is valid
function Test-DownloadLink {
    param($Url)
    try { return (Invoke-WebRequest -Uri $Url -Method Head).StatusCode -eq 200 }
    catch { return $false }
}
if ($Locale -notin $validLocales) { Write-Host "Invalid locale specified." -ForegroundColor Red; return }
if ($Type -eq "Server") {
	if ($Version -notin $validServerVersions) { Write-Host "Invalid server OS version specified." -ForegroundColor Red; return }
	if ($Edition -notin $validServerEditions) { Write-Host "Invalid server OS edition specified." -ForegroundColor Red; return }
	if ("" -ne $Release) { Write-Host "Release specified but not necessary for server OS. Release will be ignored." }
	$baseServerLink = "https://www.microsoft.com/$($locale.ToLower())/evalcenter/download-windows-server-$Version"
	$possibleISOLinks = Invoke-WebRequest -UseBasicParsing -Uri $baseServerLink | Select-Object -ExpandProperty Links | Where-Object { $_.href -like "*culture=$locale*" -and $_.OuterHtml -like "*64-bit edition*" } | Select-Object -ExpandProperty href
	# Since we cannot determine which FWD link is the ISO (as opposed to the VHD or Azure VMs)
	$isoDlLink = ""
	foreach ($link in $possibleISOLinks) {
		$request = [System.Net.WebRequest]::Create($link)
		$request.AllowAutoRedirect=$false
		$response=$request.GetResponse()
		if ($response.GetResponseHeader("Location").ToLower().EndsWith(".iso")) { $isoDlLink = $response.GetResponseHeader("Location") }        
	}
	if ("" -eq $isoDlLink) { Write-Host "Could not obtain download link for Windows Server $Version" -ForegroundColor Red; return }
	if ($GetUrl.IsPresent) { Write-Host $isoDlLink -ForegroundColor Green; return }
	$isoFile = $isoDlLink -split "/" | Select-Object -Last 1
	(New-Object System.Net.WebClient).DownloadFile($isoDlLink, $(Join-Path $OutputDir $isoFile))
	$isoFile = $isoDlLink -split "/" | Select-Object -Last 1
	Write-Host "Windows Server $Version ISO downloaded to $(Join-Path $OutputDir $isoFile)" -ForegroundColor Green
	# TODO: Convert from Eval to Full
}
elseif ($Type -eq "Client") {
	if ($Version -notin $validClientVersions) { Write-Host "Invalid client OS version specified." -ForegroundColor Red; return }
	if ($Edition -notin $validClientEditions) { Write-Host "Invalid client OS edition specified." -ForegroundColor Red; return }
    if ($Release -eq "") { Write-Host "No release specified." -ForegroundColor Red; return }
	if ($Release -eq $firstOSReleases[$Version]) { $baseClientLink = "https://software.download.prss.microsoft.com/dbazure/Win$($Version)_$($LocaleLanguageMap[$locale])_x64.iso" }
	else { $baseClientLink = "https://software.download.prss.microsoft.com/dbazure/Win$($Version)_$($Release)_$($LocaleLanguageMap[$locale])_x64.iso?t" }
	$isoDlLink = $baseClientLink
	$isValidISOLink = Test-DownloadLink -Url $isoDlLink
	$i = 1
    $failCount = 0
	do {
		$isoLink = $baseClientLink -replace ".iso", "v$i.iso"
		$isValidISOLink = Test-DownloadLink -Url $isoLink
		if ($isValidISOLink) { $isoDlLink = $isoLink }
        else { $failCount++ }
		$i++
	} while (($isValidISOLink -eq $true) -or ($failCount -lt 2)) # Microsoft have sometimes skipped appending v1 to ISO's and instead began with v2 at the end of the file name. Set the failure count threshold to 2 to account for this.
	if ("" -eq $isoDlLink) { Write-Host "Could not obtain download link for Windows $Version version $Release" -ForegroundColor Red; return }
	if ($GetUrl.IsPresent) { Write-Host $isoDlLink -ForegroundColor Green; return }
	$isoFile = ($isoDlLink -split "/" | Select-Object -Last 1) -split "\?" | Select-Object -First 1
	(New-Object System.Net.WebClient).DownloadFile($isoDlLink, $(Join-Path $OutputDir $isoFile))
	Write-Host "Windows $Version version $Release ISO downloaded to $(Join-Path $OutputDir $isoFile)" -ForegroundColor Green
	# TODO: Remove other editions + conversion for enterprise ISO
}