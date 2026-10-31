$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /warnaserror+ /reference:System.Web.Extensions.dll "/out:$PSScriptRoot\DesktopIconCleaner.exe" "$PSScriptRoot\DesktopIconCleaner.cs" "$PSScriptRoot\Recycle.cs"
if ($LASTEXITCODE -ne 0) { throw "Build failed: $LASTEXITCODE" }
