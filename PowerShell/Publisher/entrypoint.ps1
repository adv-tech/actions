$ErrorActionPreference = "Stop"
## Disable Certificate Features For Now
# function Set-SignatureHelper {
#   Param (
#     $FilePath,
#     $Certificate
#   )
#   $sign = Set-AuthenticodeSignature -FilePath $FilePath -Certificate $Certificate
#   if (($sign).Status -ne "Valid") {
#     throw ($sign).StatusMessage
#   }
#   else {
#     $msg = "Signed: " + $sign.Path
#     Write-Host $msg
#   }
# }

# function Get-CodeSigningCert {
#   Param(
#     $certificate,
#     [SecureString]$certificatePassword
#   )
#   $collection = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new();
#   $collection.Import($certificate, ($certificatePassword | ConvertFrom-SecureString -AsPlainText),  [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet);
#   try {
#       $store = [System.Security.Cryptography.X509Certificates.X509Store]::new('My');
#       $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite);
#       foreach ($cert in $collection) {
#           if ($cert.Thumbprint -in @($store.Certificates | ForEach-Object { $_.Thumbprint } )) {
#               $store.Remove($cert)
#           }
#           $store.Add($cert);
#       }
#   } finally {
#       if($store) {
#           $store.Dispose()
#       }
#   }
#   Get-ChildItem Cert:\CurrentUser\My\ -CodeSigningCert
# }

Write-Host "Import PowerShellGet"
Import-Module PowerShellGet

Write-Host "Register repository"
$repo = @{
  Name                  =  'TargetRepo'
  SourceLocation        =  ${env:TargetRepoUri}
  PublishLocation       =  ${env:TargetRepoUri}
  ScriptSourceLocation  =  ${env:TargetRepoUri}
  ScriptPublishlocation =  ${env:TargetRepoUri}
  InstallationPolicy    =  'Trusted'
}
$tag = ${env:GITHUB_REF}
Register-PSRepository @repo 
if ($tag -match "refs/tags/") {
  $tag = $tag.Substring($tag.lastIndexOf('/')+1)
}
Write-Host "Release version: $tag"

Write-Host "Get release notes"
$uriRelease = "https://api.github.com/repos/${env:GITHUB_REPOSITORY}/releases/tags/$tag"
Write-Host $uriRelease
$headers = @{
  Accept = "application/vnd.github.v2+json"
  'Authorization' = "token ${env:GitHub_Token}"
}
$release = Invoke-RestMethod -Uri $uriRelease -Headers $headers | ConvertTo-Json | ConvertFrom-Json

$release

if (${env:Package} -match ".ps1$") {
  Write-Host "Update script info"
  if ($release.prerelease) {
    Update-ScriptFileInfo ${env:Package} -Version $tag -ReleaseNotes $release.body
  }
  else {
    Update-ScriptFileInfo ${env:Package} -Version $tag -ReleaseNotes $release.body
  }
  # if (${env:certificate}) {
  #   Write-Host "Sign script"
  #   $cert = Get-CodeSigningCert -certificate ${env:certificate} -certificatePassword (ConvertTo-SecureString ${env:certificatePassword} -AsPlainText -Force)
  #   Set-SignatureHelper -FilePath ${env:Package} -Certificate $cert
  # }
  Write-Host "Publish script"
  Publish-Script -Path ${env:Package} -Repository TargetRepo -NuGetApiKey $NuGetApiKey
}
else {
  Write-Host "Get required dependencies"
  (Test-ModuleManifest ${env:Package} -ErrorAction Ignore).RequiredModules | % {Install-Module -Name $_.Name -Repository TargetRepo}
  Write-Host "Update module manifest"
  if ($release.prerelease) {
    $tag = $tag.Split("-")
    Update-ModuleManifest ${env:Package} -ModuleVersion $tag[0] -ReleaseNotes $release.body -Prerelease $tag[1].Replace(".","")
  }
  else {
    Update-ModuleManifest ${env:Package} -ModuleVersion $tag -ReleaseNotes $release.body -ErrorAction Ignore
  }
  # if ($certificate) {
  #   Write-Host "Sign module"
  #   $cert = Get-CodeSigningCert -certificate $certificate -certificatePassword ${env:certificatePassword}
  #   Set-SignatureHelper -FilePath ${env:Package} -Certificate $cert
  #   $RootModule = (${env:Package}.SubString(0, ${env:Package}.lastIndexOf('\')+1) + ((Test-ModuleManifest ${env:Package}).RootModule).SubString(((Test-ModuleManifest ${env:Package}).RootModule).IndexOf('\')+1))
  #   Set-SignatureHelper -FilePath $RootModule -Certificate $cert
  #   ForEach ($ModuleFile in (Get-ChildItem (${env:Package}.SubString(0, ${env:Package}.lastIndexOf('\')+1) + "Resources\"))) {
  #     Set-SignatureHelper -FilePath $ModuleFile -Certificate $cert
  #   }
  # }
  Write-Host "Publish module"
  Write-Host "Path: ${env:Package}.SubString(0, ${env:Package}.lastIndexOf('\')+1)"
  $Path = ${env:Package}
  Write-Host $Path.SubString(0, ${env:Package}.lastIndexOf('\')+1)
  Publish-Module -Path ${env:Package}.SubString(0, ${env:Package}.lastIndexOf('\')+1) -Repository TargetRepo -NuGetApiKey $NuGetApiKey
}
