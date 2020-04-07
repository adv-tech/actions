Write-Host "Import PowerShellGet"
Import-Module PowerShellGet -ErrorAction Stop

Write-Host "Register repository"
$repo = @{
  Name                  =  'TargetRepo'
  SourceLocation        =  ${env:repoModule}
  PublishLocation       =  ${env:repoModule}
  ScriptSourceLocation  =  ${env:repoScript}
  ScriptPublishLocation =  ${env:repoScript}
  InstallationPolicy    =  'Trusted'
}
Register-PSRepository @repo -ErrorAction Stop

$version = ${env:GITHUB_REF} -replace 'refs\/tags\/', ''
Write-Host "Release version: $version"

if (${env:entrypoint} -match ".ps1$") {
  Write-Host "Update script info"
  Update-ScriptFileInfo ${env:entrypoint} -Version $version -ErrorAction Stop
  Write-Host "Publish script"
  Publish-Script -Path ${env:entrypoint} -Repository TargetRepo -NuGetApiKey ${env:apikey} -ErrorAction Stop
}
else {
  Write-Host "Update module manifest"
  Update-ModuleManifest ${env:entrypoint} -ModuleVersion $version -ErrorAction Stop
  Write-Host "Publish module"
  Publish-Module -Path ${env:entrypoint}.SubString(0, ${env:entrypoint}.lastIndexOf('/')+1) -Repository TargetRepo -NuGetApiKey ${env:apikey} -ErrorAction Stop
}
