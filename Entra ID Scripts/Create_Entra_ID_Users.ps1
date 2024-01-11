<#PSScriptInfo
.VERSION 1.0
.AUTHOR Tyler Lurie
.DESCRIPTION
Bulk adds Microsoft Entra ID users from a CSV file. CSV file Parameters take precedence over script parameters, but script parameters can be used as fallback when no CSV Parameter is defined for a user.

.RELEASENOTES
Version 1.0: Original version
#>
<#
.SYNOPSIS
Script synopsis
.PARAMETER CsvFilePath
The absolute or relative path to the CSV file to retrieve users and attributes from.
.PARAMETER Licenses
Licenses you wish to assign users to. These will be included in addition to the licenses defined in the CSV file.
.PARAMETER Groups
The groups to add the users to by default. These will be included in addition to the groups defined in the CSV file.
.PARAMETER Roles
The administrator roles you wish to assign a user. These will be included in addition to the roles defined in the CSV file.
.PARAMETER ChangePasswordAtLogon
Requires the users to change their passwords at sign-in by default. This value will be overridden for users that have this Parameter defined in the CSV file.
.PARAMETER PasswordNeverExpires
Sets the users' passwords to never expire by default. This value will be overridden for users that have this Parameter defined in the CSV file.

.EXAMPLE
.\Create_Entra_ID_Users.ps1 -CsvFilePath "C:\Path\To\Your\CSV\File.csv" -Licenses "Office 365 E5", "Microsoft Power Automate Free" -Groups "Group1", "Group2", "Group3" -Roles "Billing Administrator", "Intune Administrator"
#>

[CmdletBinding(DefaultParameterSetName = 'Default')]
param (
    [Parameter(Mandatory = $true, Position = 1)][String]$CsvFilePath,
    [Parameter(Mandatory = $false)][String[]]$Groups = @(),
    [Parameter(Mandatory = $false)][String[]]$Licenses = @(),
    [Parameter(Mandatory = $false)][String[]]$Roles = @(),
    [Parameter(Mandatory = $false)][Boolean]$ChangePasswordAtLogon = $true,
    [Parameter(Mandatory = $false)][Boolean]$PasswordNeverExpires = $false
)

## Define our variables: ##
$userList = $null
$licenseTable = @{}
$generatedPasswordsCSV = @()
$minPasswordLength = 8 # Office 365 has set this, and it cannot be changed
$generatedPasswordsCSVPath = "user_generated_passwords.csv"

## Define our functions: ##
function Get-LicenseSKUs {
    $licenseFileLink = Invoke-WebRequest -UseBasicParsing -Uri "https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference" | Select-Object -ExpandProperty Links | Where-Object { ($_.href -like "*.csv") } | Select-Object -ExpandProperty href
    $licenseInformation = (New-Object System.Net.WebClient).DownloadString($licenseFileLink) | ConvertFrom-Csv | Group-Object GUID | ForEach-Object { $_.Group | Select-Object -First 1 } | Select-Object Product_Display_Name, GUID
    $licenseHashtable = @{}
    foreach ($entry in $licenseInformation) {
        $licenseHashtable[$entry.Product_Display_Name] = $entry.GUID
    }
    return $licenseHashtable
}

function Generate-RandomPassword {
    param (
        [int]$Length
    )
    
    $specialCharacters = "!@#$%^&*()-_=+[]{}|;:'<>,.?/"
    $charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz' + $specialCharacters
    $password = ""
    do {
        $password = ""
        1..$Length | ForEach-Object {
            $randomChar = $charset[(Get-Random -Minimum 0 -Maximum $charset.Length)]
            $password += $randomChar
        }
    } while (!(Test-PasswordComplexity -Password $password.ToString()))
    return $password
}
function Test-PasswordQuality {
    param (
        [string]$Password
    )
    $result = @{
        "QualityResult" = "Pass"
        "Feedback"      = @()
    }

    if ($Password.Length -lt $minPasswordLength) {
        $result["QualityResult"] = "Fail"
        $result["Feedback"] += "Password length is less than the minimum required length."
    }
    if ($Password -cnotmatch "[A-Z]") {
        $result["QualityResult"] = "Fail"
        $result["Feedback"] += "Password does not contain an uppercase letter."
    }

    if ($Password -cnotmatch "[a-z]") {
        $result["QualityResult"] = "Fail"
        $result["Feedback"] += "Password does not contain a lowercase letter."
    }

    if ($Password -notmatch "[0-9]") {
        $result["QualityResult"] = "Fail"
        $result["Feedback"] += "Password does not contain a digit."
    }
    if ($Password -notmatch "[!@#\$%^&*\(\)\-_=+\[\]{}|;:'<>,.?/]") {
        $result["QualityResult"] = "Fail"
        $result["Feedback"] += "Password does not contain a special character."
    }
    return $result
}
# Test password complexity
function Test-PasswordComplexity {
    param (
        [string]$Password
    )
    $complexityResult = Test-PasswordQuality -Password $Password
    return $complexityResult.QualityResult -eq 'Pass'
}

## Perform necessary prerequisite checks: ##
# Check if the provided CSVFilePath is a valid CSV file
if (-not (Test-Path -Path $CsvFilePath -PathType Leaf)) {
    Write-Host "Error: Specified CSV file '$CsvFilePath' could not be found."
    exit 1
}
# Check if the file has a .csv extension:
if ($CsvFilePath -notmatch '\.csv$') {
    Write-Host "Error: Specified file '$CsvFilePath' is not a valid CSV file (missing .csv extension)."
    exit 1
}
# Check if both ChangePasswordAtLogon and PasswordNeverExpires are used simultaneously
if ($ChangePasswordAtLogon -and $PasswordNeverExpires) {
    Write-Host "Error: You cannot use both ChangePasswordAtLogon and PasswordNeverExpires simultaneously."
    exit 1
}
# Prevent Invoke-WebRequest from hanging in case it is called later:
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# Get the list of users:
$userList = Import-Csv -Path $CsvFilePath
# See if we are assigning any licenses from this CSV:
$needLicenses = $null -ne $userList.Licenses -and $userList.Licenses -ne ''
# Check the result
if ($needLicenses) {
	$requiredModules = ("Microsoft.Graph.Users.Actions", "Microsoft.Graph.Identity.DirectoryManagement")
	foreach ($module in $requiredModules) {
		if (-not (Get-Module $module -ListAvailable)) {
			Install-Module -Name $module -Scope CurrentUser -Force
		}
		Import-Module -Name $module -Force
	}
    $licenseTable = Get-LicenseSKUs
}
# Install/Import the according MS-Graph Extensions and connect with the according needs
# Handle installing NuGet if the user has never done it before:
if (-not (Get-PackageProvider "NuGet" -ListAvailable)) {
	Install-PackageProvider -Name NuGet -Scope CurrentUser -Force | Out-Null
}
$requiredModules = ("Microsoft.Graph.Identity.Governance", "Microsoft.Graph.Users", "Microsoft.Graph.Groups", "Microsoft.Graph.Users.Actions")
foreach ($module in $requiredModules) {
    if (-not (Get-Module $module -ListAvailable)) {
        Install-Module -Name $module -Scope CurrentUser -Force
    }
    Import-Module -Name $module -Force
}
Connect-MgGraph -Scopes "User.ReadWrite.All,UserAuthenticationMethod.ReadWrite.All,RoleManagement.ReadWrite.Directory, GroupMember.ReadWrite.All, Group.ReadWrite.All, Directory.ReadWrite.All, Organization.Read.All" -NoWelcome

## Begin creating users: ##
try {
    foreach ($user in $userList) {
        $userParams = @{
            UserPrincipalName = $user.EmailAddress
            DisplayName       = if ($user.DisplayName) { $user.DisplayName } else { "$($user.FirstName) $($user.LastName)" }
            MailNickName      = ($user.EmailAddress).Split("@")[0]
            City              = $user.City
            CompanyName       = $user.Company
            Country           = $user.Country
            Department        = $user.Department
            JobTitle          = $user.JobTitle
            BusinessPhones    = $user.OfficePhone
            MobilePhone       = $user.MobilePhone
            State             = $user.State
            StreetAddress     = $user.StreetAddress
            Surname           = $user.LastName
            GivenName         = $user.FirstName
            UsageLocation     = $user.Country
            OfficeLocation    = $user.StreetAddress
			AccountEnabled    = $true
        } # TODO: Investigate StreetAddress and Country needing to be used twice for some reason
    # Create the user's password:
    # Generate a random password if not specified in the CSV
    if ([string]::IsNullOrEmpty($user.Password)) {
        $plainTextPassword = (Generate-RandomPassword -Length $minPasswordLength)
        $passwordSecure = ConvertTo-SecureString -String $plainTextPassword -AsPlainText -Force
        $user.Password = $passwordSecure
        $generatedPasswordsCSV += [PSCustomObject]@{
            Username = $user.EmailAddress
            Password = $($plainTextPassword.ToString())
        }
    }
    else {
        $password = ConvertTo-SecureString $user.Password -AsPlainText -Force
        $user.Password = $password
    }
    $NewPassword = @{}
    $NewPassword["Password"] = $user.Password
    $NewPassword["ForceChangePasswordNextSignIn"] = if ($user.ChangePasswordAtLogon -ne '') { $user.ChangePasswordAtLogon } else { $ChangePasswordAtLogon }
	if ($user.MFA) { $NewPassword["ForceChangePasswordNextSignInWithMfa"] = if ($user.ChangePasswordAtLogon -ne '') { $user.ChangePasswordAtLogon } else { $ChangePasswordAtLogon } }
    $userParams.Add("PasswordProfile", $NewPassword)
    # Create the user:
    New-MgUser @userParams | Out-Null
    Write-Host "Created user: $($user.EmailAddress)"
    # Set password to never expire if needed:
    if (($user.PasswordNeverExpires -and (-not $PasswordNeverExpires)) -or ((-not $user.PasswordNeverExpires) -and $PasswordNeverExpires)) {
        Update-MgUser -UserId $user.EmailAddress -PasswordPolicies DisablePasswordExpiration
    }
	# Assign Manager if needed:
	if ($user.Manager) {
		$managerObjectId = Get-MgUser -Filter "mail eq '$($user.Manager)'" | Select-Object -ExpandProperty Id
		$NewManager = @{
		  "@odata.id"="https://graph.microsoft.com/v1.0/users/$managerObjectId"
		}
		Set-MgUserManagerByRef -UserId $user.EmailAddress -BodyParameter $NewManager
	}
    # Assign licenses:
    $allLicenses = ($Licenses + ($user.Licenses -split ',\s*' | Where-Object { $_ -ne '' })) | Select-Object -Unique
    $addLicenses = @()
    foreach ($license in $allLicenses) {
        $licenseInfo = Get-MgSubscribedSKU | Select-Object SkuPartNumber, SkuId, @{Name = "ActiveUnits"; Expression = { ($_.PrepaidUnits).Enabled } }, ConsumedUnits | Where-Object { ($_.SkuId -eq $licenseTable[$license]) }
        $canAssign = ($licenseInfo.ActiveUnits - - $numLicenses.ConsumedUnits) -ge 1
        if ($canAssign) { $addLicenses += @{SkuId = $licenseTable[$license] } }
        else { Write-Host "Failed to assign $license license to $($user.Email). Insufficient licenses remaining." }
    }
    Set-MgUserLicense -UserId $user.EmailAddress -AddLicenses $addLicenses -RemoveLicenses @() | Out-Null
    foreach ($license in $user.Licenses) { Write-Host "Successfully assigned $license for $($user.EmailAddress)" }
    $userId = Get-MgUser -Filter "userPrincipalName eq '$($user.EmailAddress)'" | Select-Object -ExpandProperty Id
    # Add user to groups:
    $allGroups = ($Groups + ($user.Groups -split ',\s*' | Where-Object { $_ -ne '' })) | Select-Object -Unique
    foreach ($group in $allGroups) {
        $groupExists = Get-MgGroup -Filter "DisplayName eq '$group'"
        if ($groupExists) {
			New-MgGroupMember -GroupId $groupExists.Id -DirectoryObjectId $userId
			Write-Host "Successfully added user $($user.EmailAddress) to group $($groupExists.DisplayName)"
			}
    }
    # Assign user's roles:
    $allRoles = ($Roles + ($user.Roles -split ',\s*' | Where-Object { $_ -ne '' })) | Select-Object -Unique
    foreach ($role in $allRoles) {
        $roledefinition = Get-MgRoleManagementDirectoryRoleDefinition -Filter "DisplayName eq '$role'" | Select-Object -ExpandProperty Id
        if ($roledefinition) {
			New-MgRoleManagementDirectoryRoleAssignment -DirectoryScopeId '/' -RoleDefinitionId $roledefinition -PrincipalId $userId | Out-Null
			Write-Host "Successfully assigned user $($user.EmailAddress) role $role"
			}
        else { Write-Host "Error: Could not assign role $role to $($user.EmailAddress). Role not found." }
    }
    # Export the generated usernames and passwords to a CSV
    if ($generatedPasswordsCSV.Count -gt 0) {
        $generatedPasswordsCSV | Export-Csv -Path $generatedPasswordsCSVPath -NoTypeInformation
        Write-Host "Successfully created $generatedPasswordsCSVPath for users with no specified password."
    }
} }
catch { return }
## End of creating users ##