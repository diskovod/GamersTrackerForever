$ErrorActionPreference = "Stop"

$addonRoot = Split-Path -Parent $PSScriptRoot
$tocPath = Join-Path $addonRoot "GamersTrackerForever.toc"
$tocEntries = Get-Content -LiteralPath $tocPath |
    Where-Object { $_ -and -not $_.StartsWith("##") }

$tocHeader = Get-Content -LiteralPath $tocPath | Where-Object { $_ -like "## Interface:*" } | Select-Object -First 1
if ($tocHeader -notmatch '^## Interface:\s*11509\s*,\s*16001\s*$') {
    throw "TOC must declare both the proven Classic Era and Forever beta interfaces"
}

if ($tocEntries -contains "Bindings.xml") {
    throw "Bindings.xml is loaded as ordinary UI XML and produces SoD XML warnings"
}

$bindingsPath = Join-Path $addonRoot "Bindings.xml"
$bindings = Get-Content -LiteralPath $bindingsPath -Raw
if ($bindings -notmatch '<Binding\s+category="[^"]+"\s+name="GAMERSTRACKERFOREVER_TOGGLE"') {
    throw "Bindings.xml must use the SoD-supported category/name binding form"
}
if ($bindings -match '\bheader\s*=') {
    throw "Bindings.xml must not use the unsupported header attribute"
}

Write-Output "SoD static regression checks: PASS"
