param([switch]$Install, [switch]$Launch, [switch]$Signed, [string]$DeviceTarget = '127.0.0.1:5555', [switch]$Unsigned)
$ErrorActionPreference = 'Stop'
if ($Signed -and $Unsigned) { throw 'Choose either Signed or Unsigned, not both.' }
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskIde = if ($env:DEVECO_STUDIO_HOME) { $env:DEVECO_STUDIO_HOME } else { 'C:\Program Files\Huawei\DevEco Studio' }
$env:DEVECO_SDK_HOME = Join-Path $taskIde 'sdk'
$env:JAVA_HOME = Join-Path $taskIde 'jbr'
$env:NODE_HOME = Join-Path $taskIde 'tools\node'
$taskNode = Join-Path $env:NODE_HOME 'node.exe'
$taskHvigor = Join-Path $taskIde 'tools\hvigor\bin\hvigorw.js'
$taskHdc = Join-Path $taskIde 'sdk\default\openharmony\toolchains\hdc.exe'
Push-Location $taskRoot
try {
  & $taskNode $taskHvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
  if ($LASTEXITCODE -ne 0) { throw 'HarmonyOS build failed.' }
  if ($Install -or $Launch) {
    $taskSignedHap = Join-Path $taskRoot 'entry\build\default\outputs\default\entry-default-signed.hap'
    $taskUnsignedHap = Join-Path $taskRoot 'entry\build\default\outputs\default\entry-default-unsigned.hap'
    $taskUseSigned = !$Unsigned -and ($Signed -or (Test-Path -LiteralPath $taskSignedHap))
    if ($taskUseSigned -and (Test-Path -LiteralPath $taskSignedHap) -and (Test-Path -LiteralPath $taskUnsignedHap) -and
        (Get-Item -LiteralPath $taskSignedHap).LastWriteTimeUtc -lt (Get-Item -LiteralPath $taskUnsignedHap).LastWriteTimeUtc) {
      throw 'Signed HAP is older than the current build. Regenerate the local signing output before installing.'
    }
    $taskArtifact = if ($taskUseSigned) { 'entry-default-signed.hap' } else { 'entry-default-unsigned.hap' }
    $taskHap = Join-Path $taskRoot ('entry\build\default\outputs\default\' + $taskArtifact)
    if (!(Test-Path -LiteralPath $taskHap)) { throw 'HAP missing. For physical devices, configure a local DevEco signing profile first.' }
    $taskInstallOutput = & $taskHdc -t $DeviceTarget install -r $taskHap 2>&1
    $taskInstallExit = $LASTEXITCODE
    $taskInstallOutput | ForEach-Object { Write-Output $_ }
    if ($taskInstallExit -ne 0 -or ($taskInstallOutput -join "`n") -notmatch 'install bundle successfully') {
      throw 'HAP installation failed. If signatures differ, do not clear app data without approval; use the same signing identity as the IDE.'
    }
  }
  if ($Launch) {
    & $taskHdc -t $DeviceTarget shell aa start -b com.example.opencode_harmony -m entry -a EntryAbility
    if ($LASTEXITCODE -ne 0) { throw 'Application launch failed.' }
  }
} finally { Pop-Location }
