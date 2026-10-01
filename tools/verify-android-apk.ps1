param(
    [string] $ApkPath,
    [string] $AndroidSdkRoot,
    [switch] $RequireReleaseSigning,
    [switch] $RequireCodexNativeAssets
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $ApkPath = Join-Path $repoRoot 'apps\codex\build\app\outputs\flutter-apk\app-release.apk'
}
$apk = (Resolve-Path -LiteralPath $ApkPath).Path
if (-not [System.IO.File]::Exists($apk)) {
    throw "APK does not exist: $apk"
}

function Test-PathWithin {
    param(
        [Parameter(Mandatory = $true)][string] $Candidate,
        [Parameter(Mandatory = $true)][string] $Parent
    )

    $candidateFull = [System.IO.Path]::GetFullPath($Candidate).TrimEnd('\', '/')
    $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
    if ([System.String]::Equals($candidateFull, $parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $prefix = $parentFull + [System.IO.Path]::DirectorySeparatorChar
    return $candidateFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

if ([string]::IsNullOrWhiteSpace($AndroidSdkRoot)) {
    foreach ($variable in @('ANDROID_HOME', 'ANDROID_SDK_ROOT')) {
        $candidate = [Environment]::GetEnvironmentVariable($variable)
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            [System.IO.Directory]::Exists($candidate)) {
            $AndroidSdkRoot = $candidate
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($AndroidSdkRoot)) {
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
        $AndroidSdkRoot = Join-Path $localAppData 'Android\Sdk'
    }
}
if (-not [System.IO.Directory]::Exists($AndroidSdkRoot)) {
    throw "Android SDK root was not found: $AndroidSdkRoot"
}

$buildToolsRoot = Join-Path $AndroidSdkRoot 'build-tools'
$buildTools = Get-ChildItem -LiteralPath $buildToolsRoot -Directory |
    Sort-Object Name -Descending
$aapt = $null
$apkSigner = $null
$buildToolsVersion = $null
foreach ($directory in $buildTools) {
    $aaptCandidate = Join-Path $directory.FullName 'aapt.exe'
    $signerCandidate = Join-Path $directory.FullName 'apksigner.bat'
    if ([System.IO.File]::Exists($aaptCandidate) -and
        [System.IO.File]::Exists($signerCandidate)) {
        $aapt = $aaptCandidate
        $apkSigner = $signerCandidate
        $buildToolsVersion = $directory.Name
        break
    }
}
if ($null -eq $aapt -or $null -eq $apkSigner) {
    throw "No Android build-tools directory with aapt.exe and apksigner.bat was found under $buildToolsRoot"
}

$signingOutput = (& $apkSigner verify --verbose --print-certs $apk 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "APK signature verification failed: $signingOutput"
}
$certificateDnMatch = [System.Text.RegularExpressions.Regex]::Match(
    $signingOutput,
    'certificate DN:\s*(.+)'
)
$certificateDigestMatch = [System.Text.RegularExpressions.Regex]::Match(
    $signingOutput,
    'certificate SHA-256 digest:\s*([0-9a-fA-F]{64})'
)
$certificateDn = $certificateDnMatch.Groups[1].Value.Trim()
$certificateSha256 = $certificateDigestMatch.Groups[1].Value.ToLowerInvariant()
$debugSigned = $certificateDn -match 'CN=Android Debug'
if ($RequireReleaseSigning -and $debugSigned) {
    throw 'The APK is signed with the Android debug certificate; a release certificate is required.'
}

$driveLetter = $null
$mappedApk = $apk
$mappedRoot = $null
try {
    # aapt in the installed Windows SDK can fail on a non-ASCII checkout path.
    # Use a temporary drive alias without copying or changing the artifact.
    if (Test-PathWithin -Candidate $apk -Parent $repoRoot) {
        foreach ($candidate in @('X', 'Y', 'Z', 'W', 'V')) {
            if (-not (Get-PSDrive -Name $candidate -ErrorAction SilentlyContinue)) {
                $driveLetter = $candidate
                break
            }
        }
        if ($null -eq $driveLetter) {
            throw 'No temporary drive letter is available for aapt verification.'
        }
        $mappedRoot = "${driveLetter}:"
        subst $mappedRoot $repoRoot
        $relativeApk = $apk.Substring($repoRoot.Length).TrimStart('\', '/')
        $mappedApk = Join-Path $mappedRoot $relativeApk
    }

    $badgingOutput = (& $aapt dump badging $mappedApk 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "aapt badging failed: $badgingOutput"
    }
} finally {
    if ($null -ne $mappedRoot) {
        subst $mappedRoot /d | Out-Null
    }
}

$packageMatch = [System.Text.RegularExpressions.Regex]::Match(
    $badgingOutput,
    "package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'"
)
if (-not $packageMatch.Success) {
    throw 'Could not parse package identity from aapt badging output.'
}
$labelMatch = [System.Text.RegularExpressions.Regex]::Match(
    $badgingOutput,
    "application-label:'([^']*)'"
)
$label = $labelMatch.Groups[1].Value

$requiredCodexNativeAssets = @(
    'lib/arm64-v8a/libcodex_proot.so',
    'lib/arm64-v8a/libcodex_proot_loader.so',
    'lib/arm64-v8a/libcodex_host_trampoline.so',
    'lib/arm64-v8a/libcodex_worker_guard.so'
)
$presentCodexNativeAssets = [System.Collections.Generic.List[string]]::new()
$nativeAssetSizes = [ordered]@{}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$apkZip = [System.IO.Compression.ZipFile]::OpenRead($apk)
try {
    foreach ($entry in $apkZip.Entries) {
        $isCodexNativeAsset =
            $entry.FullName.StartsWith('lib/arm64-v8a/libcodex_', [System.StringComparison]::Ordinal) -or
            $entry.FullName -eq 'lib/arm64-v8a/libcodex.so'
        if ($isCodexNativeAsset -and
            $entry.FullName.EndsWith('.so', [System.StringComparison]::OrdinalIgnoreCase)) {
            $presentCodexNativeAssets.Add($entry.FullName)
            $nativeAssetSizes[$entry.FullName] = $entry.Length
        }
    }
}
finally {
    $apkZip.Dispose()
}
$missingCodexNativeAssets = @(
    $requiredCodexNativeAssets | Where-Object { $presentCodexNativeAssets -notcontains $_ }
)
$forbiddenCodexNativeAssets = @(
    'lib/arm64-v8a/libcodex_root_read_broker.so',
    'lib/arm64-v8a/libcodex.so'
)
$presentForbiddenCodexNativeAssets = @(
    $forbiddenCodexNativeAssets | Where-Object { $presentCodexNativeAssets -contains $_ }
)
if ($presentForbiddenCodexNativeAssets.Count -gt 0) {
    throw "APK contains retired Bridge/Bionic Codex assets: $($presentForbiddenCodexNativeAssets -join ', ')"
}
if ($RequireCodexNativeAssets -and $missingCodexNativeAssets.Count -gt 0) {
    throw "APK is missing required independent Codex ARM64 native assets: $($missingCodexNativeAssets -join ', ')"
}

$artifactHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
$signingKind = 'release-certificate'
if ($debugSigned) {
    $signingKind = 'debug-certificate'
}

[ordered]@{
    schemaVersion = 1
    mode = 'read-only-apk-verification'
    artifact = $apk
    sizeBytes = (Get-Item -LiteralPath $apk).Length
    sha256 = $artifactHash
    packageName = $packageMatch.Groups[1].Value
    versionCode = $packageMatch.Groups[2].Value
    versionName = $packageMatch.Groups[3].Value
    applicationLabel = $label
    signingKind = $signingKind
    certificateDn = $certificateDn
    certificateSha256 = $certificateSha256
    signatureVerified = $true
    codexNativeAssets = [ordered]@{
        required = $requiredCodexNativeAssets
        present = @($presentCodexNativeAssets | Sort-Object)
        missing = $missingCodexNativeAssets
        forbiddenPresent = $presentForbiddenCodexNativeAssets
        sizes = $nativeAssetSizes
        contractSatisfied = ($missingCodexNativeAssets.Count -eq 0)
    }
    androidBuildTools = $buildToolsVersion
} | ConvertTo-Json -Depth 8
