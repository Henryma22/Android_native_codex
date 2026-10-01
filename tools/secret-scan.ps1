[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$patterns = @(
    'sk-[A-Za-z0-9]{20,}',
    'gh[pousr]_[A-Za-z0-9_]{20,}',
    'AIza[0-9A-Za-z_-]{20,}',
    '-----BEGIN (RSA|OPENSSH|EC|PRIVATE) KEY-----',
    '(?i)\\b(api[_-]?key|token|password|secret)\\s*[:=]\\s*[A-Za-z0-9_./+=-]{16,}'
)
$files = Get-ChildItem -LiteralPath $root -Recurse -File -Force |
    Where-Object { $_.FullName -notmatch '\\\\(\\.git|build|\\.dart_tool|tmp|artifacts|node_modules|\\.gradle)(\\\\|$)' }
$hits = @()
foreach ($file in $files) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($null -eq $text) { continue }
    foreach ($pattern in $patterns) {
        if ($text -match $pattern) {
            $hits += [pscustomobject]@{ File = $file.FullName.Substring($root.Length + 1); Pattern = $pattern }
        }
    }
}
if ($hits.Count -gt 0) {
    $hits | Format-Table -AutoSize
    throw "Potential secret patterns found: $($hits.Count). Review before publishing."
}
Write-Output 'Secret scan passed: no configured high-confidence credential patterns found.'
