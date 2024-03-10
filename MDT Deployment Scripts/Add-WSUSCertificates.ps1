<#
.SYNOPSIS
This script adds certificates based on file path to the Trusted Root and Intermediate Certification Authorities stores.

.DESCRIPTION
This PowerShell script is designed to automate the importing of specific certificates to the Trusted Root Certification Authorities (Root) and Intermediate Certification Authorities (CA) stores on a local machine. It requires the file path of the root certificate as a mandatory parameter, and the file path of the issuing certificate as an optional parameter. While this could be used for a variety of tasks, it was intended to add SSL certificates to connect to WSUS for workgroup-joined machines (i.e., for build sequences and delayed domain-joined task sequences)

.AUTHOR
Tyler Lurie

.VERSION
1.0

.EXAMPLE
To add a root certificate only:
.\Add-WSUSCertificates.ps1 -RootCertPath "%DEPLOYROOT%\Certificates\RootCert.cer"

.EXAMPLE
To add both a root and an issuing certificate:
.\Add-WSUSCertificates.ps1 -RootCertPath "%DEPLOYROOT%\Certificates\RootCert.cer" -IssCertPath "%DEPLOYROOT%\Certificates\IssuingCert.cer"

.NOTES
To run this script in MDT, use a Run Command Line and run the following command:
Powershell.exe -ExecutionPolicy Bypass -File "%SCRIPTROOT%\Add-WSUSCertificates.ps1" -RootCertPath "%DEPLOYROOT%\Certificates\RootCert.cer"
Powershell.exe -ExecutionPolicy Bypass -File "%SCRIPTROOT%\Add-WSUSCertificates.ps1" -RootCertPath "%DEPLOYROOT%\Certificates\RootCert.cer" -IssCertPath "%DEPLOYROOT%\Certificates\IssuingCert.cer"
#>

param (
    [Parameter(Mandatory=$true)][string]$RootCertPath,
    [Parameter(Mandatory=$true)][string]$IssCertPath
)
Write-Host "Adding the Root CA certificate..."
$rootResult = Import-Certificate -FilePath $RootCertPath -CertStoreLocation Cert:\LocalMachine\Root
Write-Host "Root CA certificate added: $($rootResult.Thumbprint)"
Write-Host "Adding the Issuing Root CA certificate..."
$rootResult2 = Import-Certificate -FilePath $RootCertPath -CertStoreLocation Cert:\LocalMachine\CA
Write-Host "Issuing Root CA certificate added: $($rootResult.Thumbprint)"
if ($IssCertPath) {
	Write-Host "Adding the Issuing CA certificate..."
	$issResult = Import-Certificate -FilePath $IssCertPath -CertStoreLocation Cert:\LocalMachine\CA
	Write-Host "Issuing CA certificate added: $($issResult.Thumbprint)"
}