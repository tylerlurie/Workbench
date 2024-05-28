Import-Module ActiveDirectory
Import-Module Microsoft.Graph.Users
Select-MgProfile -Name "beta"
Connect-MgGraph -Scopes "RoleManagement.Read.Directory"
$roleId = (Get-MgDirectoryRole -Filter "DisplayName eq 'Global Administrator'").Id
$idList = Get-MgDirectoryRoleMember -DirectoryRoleId $roleId
$syncableList = @()
# Only collect users that exist in both the Office 365 tenant and Active Directory:
foreach ($id in $idList) {
    $cloudUser = Get-MgUser -UserId $id
    if ($(Get-AdUser -Filter "UserPrincipalName eq $($cloudUser.UserPrincipalName)") -ne '') {
        $syncableList.Add($cloudUser)
    }
}
Write-Host "The following users have the 'Global Administrator' role in your tenant:`n"
foreach ($user in $syncableList) { Write-Host "$($user.DisplayName) <$($user.Mail)>`n" }
$syncUserMail = Read-Host -Prompt "`nPlease enter the email address of the user you would like to sync"
if ($syncUserMail -in $($syncableList | Select-Object -ExpandProperty UserPrincipalName)) {
    $onPremGUID = Get-ADUser -Filter "UserPrincipalName eq $syncUserMail" | Select-Object -ExpandProperty Objectguid
    $cloudUserId = Get-MgUser -Filter "UserPrincipalName eq $syncUserMail" | Select-Object -ExpandProperty Id
    $immutableID = [System.Convert]::ToBase64String($onPremGUID.tobytearray())
    Update-MgUser -UserId $cloudUserId -OnPremisesImmutableId $immutableID
    Write-Host "Global Administrator $syncUserMail synced successfully!"
}
else { Write-Error "Error: UserPrincipalName $syncUserMail could not be matched to an existing Global Administrator." }