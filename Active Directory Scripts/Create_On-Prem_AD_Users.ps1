<#PSScriptInfo
.VERSION 1.0
.AUTHOR Tyler Lurie
.DESCRIPTION
Bulk adds Active Directory users from a CSV file. CSV file Parameters take precedence over script parameters, but script parameters can be used as fallback when no CSV Parameter is defined for a user.

.RELEASENOTES
Version 1.0: Original version
#>
<#
.SYNOPSIS
Script synopsis
.PARAMETER CsvFilePath
The absolute or relative path to the CSV file to retrieve users and attributes from.
.PARAMETER OU
The OU to add users to. If not defined, this will add users to the default OU for users. This value will be overridden for users that have this parameter defined in the CSV file.
.PARAMETER UPNSuffix
The UPN suffix to use for users by default. The suffix used must be defined in AD Domains and Trusts. If not specified, this value will use the default DNS root. This will be overridden for users that have this parameter defined in the CSV file.
.PARAMETER Groups
The groups to add the users to by default. These will be included in addition to the groups defined in the CSV file.
.PARAMETER ChangePasswordAtLogon
Requires the users to change their passwords at logon by default. This value will be overridden for users that have this Parameter defined in the CSV file.
.PARAMETER PasswordNeverExpires
Sets the users' passwords to never expire by default. This value will be overridden for users that have this Parameter defined in the CSV file.

.EXAMPLE
.\Create_On-Prem_AD_Users.ps1 -CsvFilePath "C:\Path\To\Your\CSV\File.csv" -OU "OU=Users,DC=yourdomain,DC=com" -Groups "Group1", "Group2", "Group3" -UPNSuffix "yourdomain.com"
#>

[CmdletBinding(DefaultParameterSetName = 'Default')]
param (
    [Parameter(Mandatory = $true, Position = 1)][String]$CsvFilePath,
    [Parameter(Mandatory = $false)][String]$OU = (Get-ADRootDSE).defaultNamingContext,
    [Parameter(Mandatory = $false)][String]$UPNSuffix = (Get-ADRootDSE).dnsroot,
    [Parameter(Mandatory = $false)][String[]]$Groups = @(),
    [Parameter(Mandatory = $false)][Switch]$ChangePasswordAtLogon,
    [Parameter(Mandatory = $false)][Switch]$PasswordNeverExpires
)

## Define our variables: ##
$minPasswordLength = (Get-ADDefaultDomainPasswordPolicy).MinPasswordLength
$generatedPasswordsCSV = @()
$generatedPasswordsCSVPath = "user_generated_passwords.csv"
## End of variable declarations ##

## Define the necessary functions: ##
# Generate a strong random password if not specified in the CSV
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
        [string]$Password,
        [Microsoft.ActiveDirectory.Management.ADDefaultDomainPasswordPolicy]$Policy
    )

    $complexity = [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain().DomainControllers[0].PasswordComplexity
    $passwordInfo = New-Object DirectoryServices.DirectorySearcher([ADSI]"")
    $passwordInfo.Filter = "(&(objectCategory=person)(objectClass=user)(samAccountName=$env:username))"
    $user = $passwordInfo.FindOne()
    $userPassword = $user.Properties.Item("Password")

    $result = @{
        "QualityResult" = "Pass"
        "Feedback" = @()
    }

    if ($Password.Length -lt $Policy.MinPasswordLength) {
        $result["QualityResult"] = "Fail"
        $result["Feedback"] += "Password length is less than the minimum required length."
    }

    if ($Policy.PasswordHistoryCount -gt 0 -and $userPassword -contains $Password) {
        $result["QualityResult"] = "Fail"
        $result["Feedback"] += "Password has been used before and is in the password history."
    }

    if ($complexity -eq 0) {
        # Password complexity is not required
        return $result
    }

    if ($Password -notmatch "[A-Z]") {
        $result["QualityResult"] = "Fail"
        $result["Feedback"] += "Password does not contain an uppercase letter."
    }

    if ($Password -notmatch "[a-z]") {
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
    $policy = Get-ADDefaultDomainPasswordPolicy
    $complexityResult = Test-PasswordQuality -Password $Password -Policy $policy
    return $complexityResult.QualityResult -eq 'Pass'
}
# Define a function to determine the OU path with existence check
function Get-UserOUPath($userOU, $scriptOU) {
    if (-not [string]::IsNullOrEmpty($userOU) -and (Test-OUExist -OUToCheck $userOU)) {
        return $userOU
    }
    elseif (-not [string]::IsNullOrEmpty($scriptOU) -and (Test-OUExist -OUToCheck $scriptOU)) {
        return $scriptOU
    }
    else {
        Write-Host "Error: Specified OU '$($userOU)' or script OU '$($scriptOU)' does not exist for user: $($user.Username). Skipping this user..."
        return $null
    }
}
# Function to determine the UPN suffix with existence check
function Get-UserUPNSuffix($userUPNSuffix, $scriptUPNSuffix, $user) {
    if (-not [string]::IsNullOrEmpty($userUPNSuffix)) {
        $forestUPNSuffixes = (Get-ADForest).UPNSuffixes
        if ($userUPNSuffix -notin $forestUPNSuffixes) {
            Write-Host "Error: Specified UPN Suffix '$userUPNSuffix' for user $user is not defined in AD Domains and Trusts."
            return $null
        }
        return $userUPNSuffix
    }
    elseif (-not [string]::IsNullOrEmpty($scriptUPNSuffix)) {
        return $scriptUPNSuffix
    }
    else {
        Write-Host "Error: No valid UPN Suffix specified for user $user"
        return $null
    }
}
# Function to check if an OU exists
function Test-OUExist {
    param (
        [string]$OUToCheck
    )
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$OUToCheck'")) {
        return $false
    }
    return $true
}
## End of function definitions ##

## Perform necessary prerequisite checks:
# Check if the ActiveDirectory module is available
if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
    Write-Host "Error: The ActiveDirectory module is not available on this system. This script requires Active Directory module to run."
    exit 1
}

# Check if the provided CSVFilePath is a valid CSV file
if (-not (Test-Path -Path $CsvFilePath -PathType Leaf)) {
    Write-Host "Error: Specified CSV file '$CsvFilePath' could not be found."
    exit 1
}
# Check if the file has a .csv extension
if ($CsvFilePath -notmatch '\.csv$') {
    Write-Host "Error: Specified file '$CsvFilePath' is not a valid CSV file (missing .csv extension)."
    exit 1
}

# Check if both ChangePasswordAtLogon and PasswordNeverExpires are used simultaneously
if ($ChangePasswordAtLogon.IsPresent -and $PasswordNeverExpires.IsPresent) {
    Write-Host "Error: You cannot use both ChangePasswordAtLogon and PasswordNeverExpires simultaneously."
    exit 1
}
## End of prerequisite checks ##

## Attempt to create users: ##
try {
    $userList = Import-Csv -Path $CsvFilePath
    foreach ($user in $userList) {

        $userParams = @{
            SamAccountName    = $user.Username
            UserPrincipalName = "$($user.Username)@$(Get-UserUPNSuffix -userUPNSuffix $user.UPNSuffix -scriptUPNSuffix $UPNSuffix -user $user.Username)"
            Name              = "$($user.FirstName) $($user.LastName)"
            GivenName         = $user.FirstName
            Surname           = $user.LastName
            DisplayName       = if ($user.DisplayName) { $user.DisplayName } else { "$($user.FirstName) $($user.LastName)" }
            EmailAddress      = $user.EmailAddress
            Organization      = $user.Organization
            Company           = $user.Company
            Country           = $user.Country
            Department        = $user.Department
            Description       = $user.Description
            Title             = $user.JobTitle
            Office            = $user.Office
            OfficePhone       = $user.OfficePhone
            MobilePhone       = $user.MobilePhone
            StreetAddress     = $user.StreetAddress
            City              = $user.City
            State             = $user.State
            PostalCode        = $user.PostalCode
            POBox             = $user.POBox
            Path              = Get-UserOUPath -userOU $user.OU -scriptOU $OU
        }
		# If the OU specified OU does not exist, don't try to add the user
		if ($null -eq $userParams["Path"]) { continue }
		# Manager cannot be a blank attribute, so only add it if it's included:
		if ($user.Manager) { $userParams.Add("Manager", $user.Manager) }
        # Generate a random password if not specified in the CSV
        if ([string]::IsNullOrEmpty($user.Password)) {
            $plainTextPassword = (Generate-RandomPassword -Length $minPasswordLength)
            $passwordSecure = ConvertTo-SecureString -String $plainTextPassword -AsPlainText -Force
            $user.Password = $passwordSecure
            $userParams.Add("AccountPassword", $passwordSecure)
            $generatedPasswordsCSV += [PSCustomObject]@{
                Username = $user.Username
                Password = $($plainTextPassword.ToString())
            }
        }
        else {
            $password = ConvertTo-SecureString $user.Password -AsPlainText -Force
            $user.Password = $password
            $userParams.Add("AccountPassword", $password)
        }
        $ChangePasswordAtLogonValue = if ($user.ChangePasswordAtLogon) { $user.ChangePasswordAtLogon } else { $ChangePasswordAtLogon }
        $userParams.Add("ChangePasswordAtLogon", $ChangePasswordAtLogonValue)
        $userParams.Add("Enabled", $true)
        # Check if both ChangePasswordAtLogon and PasswordNeverExpires are defined in the CSV
        if ($user.ChangePasswordAtLogon -eq $true -and $user.PasswordNeverExpires -eq $true) {
            Write-Host "Error: Both ChangePasswordAtLogon and PasswordNeverExpires are defined in the CSV for user: $($user.Username). Skipping this user."
            continue
        }

        # Set ChangePasswordAtLogon and PasswordNeverExpires based on CSV values
        elseif ($user.ChangePasswordAtLogon -eq $true) {
            $userParams.ChangePasswordAtLogon = $true
            $userParams.PasswordNeverExpires = $false
        }
        elseif ($user.PasswordNeverExpires -eq $true) {
            $userParams.PasswordNeverExpires = $true
            $userParams.ChangePasswordAtLogon = $false
        }
        # Otherwise, base it on script parameters
        elseif ($ChangePasswordAtLogon.IsPresent) {
            $userParams.ChangePasswordAtLogon = $true
            $userParams.PasswordNeverExpires = $false
        }
        elseif ($PasswordNeverExpires.IsPresent) {
            $userParams.PasswordNeverExpires = $true
            $userParams.ChangePasswordAtLogon = $false
        }
        else {
            # Set defaults if neither parameter is defined in CSV
            $userParams.ChangePasswordAtLogon = $true
            $userParams.PasswordNeverExpires = $false
        }
        New-ADUser @userParams
        Write-Host "Created user: $($user.Username)"
        $allGroups = $Groups + ($user.Groups -split ',\s*' | Where-Object { $_ -ne '' })
        foreach ($group in $allGroups) {
            # Check if the group exists
            if (Get-ADGroup -Filter { Name -eq $group }) {
                Add-ADGroupMember -Identity $group -Members $user.Username
                Write-Host "Added user $($user.Username) to group: $group"
            }
            else {
                Write-Host "Error: Group '$group' does not exist for user $($user.Username)"
            }
        }
    }
    # Export the generated usernames and passwords to a CSV
    if ($generatedPasswordsCSV.Count -gt 0) {
        $generatedPasswordsCSV | Export-Csv -Path $generatedPasswordsCSVPath -NoTypeInformation
        Write-Host "Successfully created $generatedPasswordsCSVPath for users with no specified password."
    }
}
catch { Write-Host "Error: $_" }
## End of creating users ##