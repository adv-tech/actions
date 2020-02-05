Import-Module PowerShellGet
$repo = @{
  Name = 'TargetRepo'
  SourceLocation = ${env:repository}
  PublishLocation = ${env:repository}
  InstallationPolicy = 'Trusted'
}
Register-PSRepository @repo
$version = ${env:GITHUB_REF} -replace 'refs\/tags\/', ''
if (${env:entrypoint} -match ".ps1$") {
  Update-ScriptFileInfo ${env:entrypoint} -Version $version
}
else {
  if (${env:entrypoint} -match ".psd1$") {
    Update-ModuleManifest ${env:entrypoint} -ModuleVersion $version
  }
  Publish-Module ${env:entrypoint} -repository TargetRepo -ApiKey ${env:apikey}
}
