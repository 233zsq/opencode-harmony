param([switch]$Install, [switch]$Launch)
$ErrorActionPreference = 'Stop'
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
    $taskHap = Join-Path $taskRoot 'entry\build\default\outputs\default\entry-default-unsigned.hap'
    & $taskHdc -t 127.0.0.1:5555 install -r $taskHap
    if ($LASTEXITCODE -ne 0) { throw 'HAP installation failed.' }
  }
  if ($Launch) { & $taskHdc -t 127.0.0.1:5555 shell aa start -b com.example.opencode_harmony -m entry -a EntryAbility }
} finally { Pop-Location }
