param(
    [ValidateSet('backend','web','android','check','data','serve')]
    [string]$Task = 'backend'
)
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $workspace
$bundledJava = Get-ChildItem -LiteralPath (Join-Path $workspace '.tools/jdk21') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($bundledJava) { $env:JAVA_HOME = $bundledJava.FullName }
$flutter = Join-Path $workspace '.tools/flutter/bin/flutter.bat'
if (-not (Test-Path -LiteralPath $flutter)) { $flutter = 'flutter' }
$python = Join-Path $workspace '.tools/venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $python)) { $python = 'python' }
$env:GRADLE_USER_HOME = Join-Path $workspace '.tools/gradle'
$env:TEMP = Join-Path $workspace '.tools/tmp'
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
if ($Task -in @('backend', 'check') -and -not $env:JWT_SECRET) {
    $jwtSecretFile = Join-Path $workspace '.tools/jwt-secret.txt'
    if (-not (Test-Path -LiteralPath $jwtSecretFile)) {
        $jwtBytes = New-Object byte[] 48
        $jwtRandom = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $jwtRandom.GetBytes($jwtBytes) } finally { $jwtRandom.Dispose() }
        [System.IO.File]::WriteAllText($jwtSecretFile, [Convert]::ToBase64String($jwtBytes))
    }
    $env:JWT_SECRET = [System.IO.File]::ReadAllText($jwtSecretFile).Trim()
}

switch ($Task) {
  'backend' {
    $env:MAVEN_OPTS = '-Xmx256m'
    & mvn -f backend/pom.xml spring-boot:run '-Dspring-boot.run.profiles=dev' '-Dspring-boot.run.jvmArguments=-Xmx384m'
  }
  'data' {
    & $python tools/import-bible/import_bible.py .tools/downloads/cmn-cu89s_usfm.zip
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Copy-Item -LiteralPath data/bible.bin,data/bible_index.json -Destination apps/logos/assets
  }
  'check' {
    & mvn -f backend/pom.xml test
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Set-Location -LiteralPath apps/logos
    & $flutter analyze --no-pub
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $flutter test --no-pub --concurrency=1
  }
  'web' {
    Set-Location -LiteralPath apps/logos
    & $flutter build web --no-wasm-dry-run
  }
  'serve' { & $python -m http.server 7357 --bind 127.0.0.1 --directory apps/logos/build/web }
  'android' {
    Set-Location -LiteralPath apps/logos
    & $flutter build apk --debug --target-platform android-arm64,android-x64
  }
}
exit $LASTEXITCODE
