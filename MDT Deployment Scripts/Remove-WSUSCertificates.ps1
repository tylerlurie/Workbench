<#
.SYNOPSIS
This script removes certificates based on subject name from the Trusted Root and Intermediate Certification Authorities stores.

.DESCRIPTION
This PowerShell script is designed to automate the removal of specific certificates from the Trusted Root Certification Authorities (Root) and Intermediate Certification Authorities (CA) stores on a local machine. It requires the subject name of the root certificate as a mandatory parameter, and the subject name of the issuing certificate as an optional parameter. While this could be used for a variety of tasks, it was intended to remove SSL certificates that are added to connect to WSUS for workgroup-joined machines (i.e., for build sequences and delayed domain-joined task sequences)

.AUTHOR
Tyler Lurie

.VERSION
1.0

.EXAMPLE
To remove a root certificate only:
.\Remove-WSUSCertificates.ps1 -RootSubjectName "CN=My Company Root Certification Authority, DC=ad, DC=mycompany, DC=com"

.EXAMPLE
To remove both a root and an issuing certificate:
.\Remove-WSUSCertificates.ps1 -RootSubjectName "CN=My Company Root Certification Authority, DC=ad, DC=mycompany, DC=com" -IssSubjectName "CN=My Company Issuing Certification Authority 01, DC=ad, DC=mycompany, DC=com"

.NOTES
To find the subject name of the root cerificate, run the following command from a machine that already has the certificate installed (i.e., a domain-joined machine):
Get-ChildItem -Path Cert:\LocalMachine\Root | Select-Object -ExpandProperty Subject

To find the subject name of the issuing certificate, run the following command from a machine that already has the certificate installed (i.e., a domain-joined machine):
Get-ChildItem -Path Cert:\LocalMachine\CA | Select-Object -ExpandProperty Subject

To run this script in MDT, use a Run Command Line and run the following command:
Powershell.exe -ExecutionPolicy Bypass -File "%SCRIPTROOT%\Remove-WSUSCertificates.ps1" -RootSubjectName "CN=My Company Root Certification Authority, DC=ad, DC=mycompany, DC=com"
Powershell.exe -ExecutionPolicy Bypass -File "%SCRIPTROOT%\Remove-WSUSCertificates.ps1" -RootSubjectName "CN=My Company Root Certification Authority, DC=ad, DC=mycompany, DC=com" -IssSubjectName "CN=My Company Issuing Certification Authority 01, DC=ad, DC=mycompany, DC=com"
#>

param (
    [Parameter(Mandatory=$true)][string]$RootSubjectName,
    [Parameter(Mandatory=$false)][string]$IssSubjectName
)
# Handling Root Certificate
$rootCert = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { $_.Subject -eq $RootSubjectName }
$rootIssCert = Get-ChildItem -Path Cert:\LocalMachine\CA | Where-Object { $_.Subject -eq $RootSubjectName }
if ($rootCert) {
    foreach ($cert in $rootCert) {
        $rootSerialNumber = $cert.SerialNumber
        $cmd = "certutil -delstore Root `"$rootSerialNumber`""
        Invoke-Expression $cmd
        Write-Output "Root certificate with serial $rootSerialNumber removed successfully."
    }
} else {
    Write-Output "Root certificate not found."
}
# Handling the Same Certificate in the Issuing CA Folder
$rootIssCert = Get-ChildItem -Path Cert:\LocalMachine\CA | Where-Object { $_.Subject -eq $RootSubjectName }
if ($rootIssCert) {
    foreach ($cert in $rootIssCert) {
        $rootIssSerialNumber = $cert.SerialNumber
        $cmd = "certutil -delstore CA `"$rootIssSerialNumber`""
        Invoke-Expression $cmd
        Write-Output "Root issuing certificate with serial $rootSerialNumber removed successfully."
    }
} else {
    Write-Output "Root issuing certificate not found."
}
# Handling Issuing Certificate if issSubjectName is provided
if ($issSubjectName) {
    $issCert = Get-ChildItem -Path Cert:\LocalMachine\CA | Where-Object { $_.Subject -eq $issSubjectName }
    if ($issCert) {
        foreach ($cert in $issCert) {
            $issSerialNumber = $cert.SerialNumber
            $cmd = "certutil -delstore CA `"$issSerialNumber`""
            Invoke-Expression $cmd
            Write-Output "Issuing certificate with serial $issSerialNumber removed successfully."
        }
    } else {
        Write-Output "Issuing certificate not found."
    }
}