param(
    [ValidateSet('debug', 'profile', 'release')]
    [string]$Mode = 'release',
    [string]$Flutter = 'C:\toolchains\flutter-3.47.0\bin\flutter.bat',
    [string[]]$DartDefines = @(),
    [switch]$RequireReleaseSigning
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$appRoot = Join-Path $repoRoot 'apps\codex'

if (-not (Test-Path -LiteralPath $Flutter -PathType Leaf)) {
    throw "Flutter executable was not found: $Flutter"
}
if (-not (Test-Path -LiteralPath (Join-Path $appRoot 'pubspec.yaml') -PathType Leaf)) {
    throw "Codex app was not found: $appRoot"
}
if ($RequireReleaseSigning -and $Mode -ne 'release') {
    throw '-RequireReleaseSigning is only valid with -Mode release.'
}
if ($RequireReleaseSigning) {
    $signingVariables = @(
        'CODEX_RELEASE_STORE_FILE',
        'CODEX_RELEASE_STORE_PASSWORD',
        'CODEX_RELEASE_KEY_ALIAS',
        'CODEX_RELEASE_KEY_PASSWORD'
    )
    foreach ($variable in $signingVariables) {
        $value = [Environment]::GetEnvironmentVariable($variable)
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "Release signing requires environment variable $variable; its value is not printed or stored by this script."
        }
    }
}

# Flutter's Windows AOT snapshotter in the pinned toolchain can fail to reopen
# app.dill when the checkout path contains non-ASCII characters. A temporary
# SUBST mapping keeps the same files in place while giving the toolchain an
# ASCII path. This is deliberately a build-only workaround; no source is
# copied and the mapping is always removed in the finally block.
$driveLetter = $null
foreach ($candidate in @('X', 'Y', 'Z', 'W', 'V')) {
    if (-not (Get-PSDrive -Name $candidate -ErrorAction SilentlyContinue)) {
        $driveLetter = $candidate
        break
    }
}
if ($null -eq $driveLetter) {
    throw 'No temporary drive letter is available for the Flutter build.'
}

$mappedRoot = "${driveLetter}:"

# Flutter's depfile lists Gradle output files as absolute paths. If the free
# SUBST letter changes between builds, the old depfile can point Gradle at an
# unmapped drive while it creates output parents. Discard only that generated
# depfile when its output targets reference a stale temporary mapping; Flutter
# will recreate it during this build.
$flutterBuildDepfile = Join-Path $appRoot "build\app\intermediates\flutter\$Mode\flutter_build.d"
if (Test-Path -LiteralPath $flutterBuildDepfile -PathType Leaf) {
    $depfileText = Get-Content -LiteralPath $flutterBuildDepfile -Raw
    $outputTargets = ($depfileText -split ': ', 2)[0]
    $checkoutDriveLetter = [IO.Path]::GetPathRoot($repoRoot).Substring(0, 1).ToUpperInvariant()
    $targetDriveLetters = @(
        [regex]::Matches($outputTargets, '(?m)(?:^|\s)([A-Za-z]):\\') |
            ForEach-Object { $_.Groups[1].Value.ToUpperInvariant() } |
            Sort-Object -Unique
    )
    $staleTargetDrive = $targetDriveLetters |
        Where-Object { $_ -ne $checkoutDriveLetter -and $_ -ne $driveLetter } |
        Select-Object -First 1
    if ($staleTargetDrive) {
        Remove-Item -LiteralPath $flutterBuildDepfile
    }
}

subst $mappedRoot $repoRoot
$exitCode = 1
try {
    Push-Location (Join-Path $mappedRoot 'apps\codex')
    # The extracted CC Pocket widgets keep several Material IconData values
    # behind package adapters; release tree-shaking drops those glyphs and
    # renders tofu boxes. Keep the complete Material icon font for UI parity.
    $buildArguments = @(
        'build',
        'apk',
        "--$Mode",
        '--no-pub',
        '--no-tree-shake-icons'
    )
    foreach ($dartDefine in $DartDefines) {
        if ([string]::IsNullOrWhiteSpace($dartDefine)) {
            throw 'Dart define values cannot be empty.'
        }
        $buildArguments += "--dart-define=$dartDefine"
    }
    & $Flutter @buildArguments
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
    subst $mappedRoot /d | Out-Null
}
exit $exitCode
