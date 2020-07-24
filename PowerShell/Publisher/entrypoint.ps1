$ErrorActionPreference = "Stop"
#Path
#NuGetApiKey
#Token
function Set-SignatureHelper {
  Param (
    $FilePath,
    $Certificate
  )
  $sign = Set-AuthenticodeSignature -FilePath $FilePath -Certificate $Certificate
  if (($sign).Status -ne "Valid") {
    throw ($sign).StatusMessage
  }
  else {
    $msg = "Signed: " + $sign.Path
    Write-Host $msg
  }
}

function Get-CodeSigningCert {
  Param(
    $PfxBase64,
    [SecureString]$PfxPassword
  )
  $CertPath = "$PSScriptRoot\Codesigning.pfx"
  $bytes = [Convert]::FromBase64String($PfxBase64)
  [IO.File]::WriteAllBytes($CertPath, $bytes)
  $collection = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new();
  $collection.Import($certPath, ($PfxPassword | ConvertFrom-SecureString -AsPlainText),  [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet);
  try {
      $store = [System.Security.Cryptography.X509Certificates.X509Store]::new('My');
      $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite);
      foreach ($cert in $collection) {
          if ($cert.Thumbprint -in @($store.Certificates | ForEach-Object { $_.Thumbprint } )) {
              $store.Remove($cert)
          }
          $store.Add($cert);
      }
  } finally {
      if($store) {
          $store.Dispose()
      }
  }
  Get-ChildItem Cert:\CurrentUser\My\ -CodeSigningCert
}

Write-Host "Import PowerShellGet"
Import-Module PowerShellGet

Write-Host "Register repository"
$repo = @{
  Name                  =  'TargetRepo'
  SourceLocation        =  ${env:TargetRepoUri}
  PublishLocation       =  ${env:TargetRepoUri}
  InstallationPolicy    =  'Trusted'
}
$tag = ${env:ReleaseTag}
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
  'Authorization' = "token $GitHub_Token"
}
$release = Invoke-RestMethod -Uri $uriRelease -Headers $headers | ConvertTo-Json | ConvertFrom-Json

if ($Path -match ".ps1$") {
  Write-Host "Update script info"
  if ($release.prerelease) {
    Update-ScriptFileInfo $Path -Version $tag -ReleaseNotes $release.body
  }
  else {
    Update-ScriptFileInfo $Path -Version $tag -ReleaseNotes $release.body
  }
  if (${env:PfxBase64}) {
    Write-Host "Sign script"
    $cert = Get-CodeSigningCert -PfxBase64 ${env:PfxBase64} -PfxPassword (ConvertTo-SecureString ${env:PfxPassword} -AsPlainText -Force)
    Set-SignatureHelper -FilePath $Path -Certificate $cert
  }
  Write-Host "Publish script"
  Publish-Script -Path $Path -Repository TargetRepo -NuGetApiKey $NuGetApiKey
}
else {
  Write-Host "Update module manifest"
  if ($release.prerelease) {
    $tag = $tag.Split("-")
    Update-ModuleManifest $Path -ModuleVersion $tag[0] -ReleaseNotes $release.body -Prerelease $tag[1].Replace(".","")
  }
  else {
    Update-ModuleManifest $Path -ModuleVersion $tag -ReleaseNotes $release.body
  }
  if ($PfxBase64) {
    Write-Host "Sign module"
    $cert = Get-CodeSigningCert -PfxBase64 $PfxBase64 -PfxPassword ${env:PfxPassword}
    Set-SignatureHelper -FilePath $Path -Certificate $cert
    $RootModule = ($Path.SubString(0, $Path.lastIndexOf('\')+1) + ((Test-ModuleManifest $Path).RootModule).SubString(((Test-ModuleManifest $Path).RootModule).IndexOf('\')+1))
    Set-SignatureHelper -FilePath $RootModule -Certificate $cert
    ForEach ($ModuleFile in (Get-ChildItem ($Path.SubString(0, $Path.lastIndexOf('\')+1) + "Resources\"))) {
      Set-SignatureHelper -FilePath $ModuleFile -Certificate $cert
    }
  }
  Write-Host "Publish module"
  Publish-Module -Path $Path.SubString(0, $Path.lastIndexOf('\')+1) -Repository TargetRepo -NuGetApiKey $NuGetApiKey
}
