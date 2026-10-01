[CmdletBinding()]
param(
    [string] $ApkPath,
    [string] $AdbPath = 'C:\Users\Henry\AppData\Local\Android\Sdk\platform-tools\adb.exe',
    [string] $Serial = 'emulator-5554',
    [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $ApkPath = Join-Path $repoRoot 'apps\codex\build\app\outputs\flutter-apk\app-release.apk'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot 'tmp\codex-vm-smoke'
}
$apk = (Resolve-Path -LiteralPath $ApkPath).Path
if (-not [System.IO.File]::Exists($apk)) {
    throw "APK does not exist: $apk"
}
if (-not [System.IO.File]::Exists($AdbPath)) {
    throw "adb was not found: $AdbPath"
}

$output = [System.IO.DirectoryInfo](New-Item -ItemType Directory -Force -Path $OutputDirectory)
$uiTreePath = Join-Path $output.FullName 'home.xml'
$screenshotPath = Join-Path $output.FullName 'home.png'
$sessionUiTreePath = Join-Path $output.FullName 'session.xml'
$sessionScreenshotPath = Join-Path $output.FullName 'session.png'
$resultPath = Join-Path $output.FullName 'result.json'
# /sdcard is backed by a FUSE path on recent Android builds and can make an
# immediately-following adb pull observe a stale or missing uiautomator file.
# Keep the probe in the device-local temporary area instead.
$remoteTreePath = '/data/local/tmp/io.henry.codex.vm-smoke.xml'
$sessionRemoteTreePath = '/data/local/tmp/io.henry.codex.vm-smoke-session.xml'
$deviceArguments = @('-s', $Serial)
$deviceWaitSeconds = 30
$bootWaitSeconds = 60

function Invoke-Adb {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $result = @(& $AdbPath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "adb failed ($exitCode): $($result -join "`n")"
    }
    return $result
}

$state = ''
$deviceReady = $false
for ($attempt = 1; $attempt -le $deviceWaitSeconds; $attempt++) {
    $stateOutput = @(& $AdbPath @($deviceArguments + @('get-state')) 2>$null)
    if ($LASTEXITCODE -eq 0) {
        $state = ($stateOutput -join "`n").Trim()
        if ($state -eq 'device') {
            $deviceReady = $true
            break
        }
    }
    Start-Sleep -Seconds 1
}
if (-not $deviceReady) {
    throw "ADB target did not become ready within ${deviceWaitSeconds}s: serial=$Serial state=$state"
}
$bootCompleted = ''
$bootReady = $false
for ($attempt = 1; $attempt -le $bootWaitSeconds; $attempt++) {
    $bootOutput = @(& $AdbPath @($deviceArguments + @('shell', 'getprop', 'sys.boot_completed')) 2>$null)
    if ($LASTEXITCODE -eq 0) {
        $bootCompleted = ($bootOutput -join "`n").Trim()
        if ($bootCompleted -eq '1') {
            $bootReady = $true
            break
        }
    }
    Start-Sleep -Seconds 1
}
if (-not $bootReady) {
    throw "Android target did not complete boot within ${bootWaitSeconds}s: serial=$Serial sys.boot_completed=$bootCompleted"
}

Invoke-Adb ($deviceArguments + @('install', '-r', '-d', $apk)) | Out-Null
Invoke-Adb ($deviceArguments + @('shell', 'am', 'force-stop', 'io.henry.codex')) | Out-Null
Invoke-Adb ($deviceArguments + @('shell', 'input', 'keyevent', 'KEYCODE_HOME')) | Out-Null
Invoke-Adb ($deviceArguments + @('shell', 'am', 'start', '-W', '-n', 'io.henry.codex/.MainActivity')) | Out-Null

$activityDump = ''
$activityReady = $false
for ($attempt = 1; $attempt -le 12; $attempt++) {
    $activityDump = (Invoke-Adb ($deviceArguments + @('shell', 'dumpsys', 'activity', 'activities'))) -join "`n"
    if ($activityDump.Contains('io.henry.codex/.MainActivity') -and
        ($activityDump -match 'ResumedActivity|topResumedActivity')) {
        $activityReady = $true
        break
    }
    Start-Sleep -Seconds 1
}
if (-not $activityReady) {
    throw 'io.henry.codex/.MainActivity did not become resumed.'
}

Invoke-Adb ($deviceArguments + @('shell', 'uiautomator', 'dump', $remoteTreePath)) | Out-Null
Invoke-Adb ($deviceArguments + @('pull', $remoteTreePath, $uiTreePath)) | Out-Null
$screenshotArguments = $deviceArguments + @('exec-out', 'screencap', '-p')
& $AdbPath @screenshotArguments > $screenshotPath
if ($LASTEXITCODE -ne 0) {
    throw "adb screenshot failed ($LASTEXITCODE)"
}

$uiTree = [System.IO.File]::ReadAllText($uiTreePath)
$expectedLabelGroups = @(
    [pscustomobject]@{ Name = 'Codex title'; Variants = @('Codex', 'CC Pocket') },
    [pscustomobject]@{ Name = 'workspace access status'; Variants = @('Folder access granted', '已使用文件夹授权', '文件夹授权') },
    [pscustomobject]@{ Name = 'workspaces section'; Variants = @('Workspaces', '工作区') },
    [pscustomobject]@{ Name = 'recent sessions section'; Variants = @('Recent Sessions', '最近会话') },
    [pscustomobject]@{ Name = 'grouped filter'; Variants = @('Grouped', '已分组') },
    [pscustomobject]@{ Name = 'all projects filter'; Variants = @('All projects', 'All workspaces', '全部项目') }
)
$expectedLabels = @($expectedLabelGroups | ForEach-Object { $_.Name })
$missingLabels = @()
foreach ($group in $expectedLabelGroups) {
    $matched = $false
    foreach ($variant in $group.Variants) {
        if ($uiTree.Contains($variant)) {
            $matched = $true
            break
        }
    }
    if (-not $matched) {
        $missingLabels += $group.Name
    }
}
if ($missingLabels.Count -gt 0) {
    throw "CC Pocket Home UI contract failed; missing labels: $($missingLabels -join ', ')"
}
if ($uiTree -match '(?i)primary%3ACodex%2FWorkspaces%2F') {
    throw 'Home UI exposed an encoded SAF document ID instead of its readable workspace name.'
}
# The Home page is backend-aware. Local Android exposes creation/import actions,
# while a selected Linux Compatibility backend intentionally shows only its
# already-known workspace cards. The common CC Pocket contract above is the
# stable assertion; workspace probing must not require a Local Android action.
$compatibilityHome = $uiTree.Contains('Linux Compatibility (PRoot)')
if (-not $compatibilityHome) {
    $localActionGroups = @(
        [pscustomobject]@{ Name = 'add workspace action'; Variants = @('Add', '添加') },
        [pscustomobject]@{ Name = 'new session action'; Variants = @('New session', '新会话') }
    )
    $missingLocalActionLabels = @()
    foreach ($group in $localActionGroups) {
        $matched = $false
        foreach ($variant in $group.Variants) {
            if ($uiTree.Contains($variant)) {
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            $missingLocalActionLabels += $group.Name
        }
    }
    if ($missingLocalActionLabels.Count -gt 0) {
        throw "Local Android Home contract failed; missing labels: $($missingLocalActionLabels -join ', ')"
    }
}
$workspaceDataPresent = $uiTree.Contains('Local workspace') -or
    $uiTree.Contains('/Codex/Workspaces/')
$sessionExpectedLabelGroups = @(
    [pscustomobject]@{ Name = 'return to session list'; Variants = @('Back', '返回会话列表') },
    [pscustomobject]@{ Name = 'plan mode control'; Variants = @('Plan off', '计划关闭') },
    [pscustomobject]@{ Name = 'execution identity control'; Variants = @('Root', 'App UID', '应用 UID') },
    [pscustomobject]@{ Name = 'send message control'; Variants = @('Send message', '发送消息') }
)
$sessionExpectedLabels = @($sessionExpectedLabelGroups | ForEach-Object { $_.Name })
$sessionMissingLabels = @()
$sessionOpened = $false

if ($workspaceDataPresent) {
    [xml]$homeDocument = $uiTree
    $newSessionNode = @(
        $homeDocument.SelectNodes('//node') |
            Where-Object {
                $_.GetAttribute('clickable') -eq 'true' -and
                (
                    $_.GetAttribute('text') -in @('New session', '新会话') -or
                    $_.GetAttribute('content-desc') -in @('New session', '新会话')
                )
            }
    ) | Select-Object -First 1
    if ($null -eq $newSessionNode) {
        throw 'A workspace was present but its New session action was not found.'
    }

    $boundsMatch = [regex]::Match(
        $newSessionNode.GetAttribute('bounds'),
        '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$'
    )
    if (-not $boundsMatch.Success) {
        throw "New session action bounds are invalid: $($newSessionNode.GetAttribute('bounds'))"
    }
    $left = [int]$boundsMatch.Groups[1].Value
    $top = [int]$boundsMatch.Groups[2].Value
    $right = [int]$boundsMatch.Groups[3].Value
    $bottom = [int]$boundsMatch.Groups[4].Value
    $centerX = [int](($left + $right) / 2)
    $centerY = [int](($top + $bottom) / 2)
    Invoke-Adb ($deviceArguments + @(
            'shell', 'input', 'tap', $centerX.ToString(), $centerY.ToString()
        )) | Out-Null

    for ($attempt = 1; $attempt -le 12; $attempt++) {
        try {
            Invoke-Adb ($deviceArguments + @('shell', 'uiautomator', 'dump', $sessionRemoteTreePath)) | Out-Null
            Invoke-Adb ($deviceArguments + @('pull', $sessionRemoteTreePath, $sessionUiTreePath)) | Out-Null
            $sessionUiTree = [System.IO.File]::ReadAllText($sessionUiTreePath)
            $sessionMissingLabels = @()
            foreach ($group in $sessionExpectedLabelGroups) {
                $matched = $false
                foreach ($variant in $group.Variants) {
                    if ($sessionUiTree.Contains($variant)) {
                        $matched = $true
                        break
                    }
                }
                if (-not $matched) {
                    $sessionMissingLabels += $group.Name
                }
            }
            if ($sessionMissingLabels.Count -eq 0) {
                $sessionOpened = $true
                break
            }
        }
        catch {
            # The UI hierarchy may be unavailable during the route transition.
        }
        Start-Sleep -Seconds 1
    }
    if (-not $sessionOpened) {
        throw "Session UI contract failed; missing labels: $($sessionMissingLabels -join ', ')"
    }

    $sessionScreenshotArguments = $deviceArguments + @('exec-out', 'screencap', '-p')
    & $AdbPath @sessionScreenshotArguments > $sessionScreenshotPath
    if ($LASTEXITCODE -ne 0) {
        throw "adb session screenshot failed ($LASTEXITCODE)"
    }
}

$result = [ordered]@{
    schemaVersion = 2
    serial = $Serial
    packageName = 'io.henry.codex'
    activity = 'io.henry.codex/.MainActivity'
    sysBootCompleted = $bootCompleted
    activityResumed = $activityReady
    apk = $apk
    apkSha256 = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    expectedLabels = $expectedLabels
    missingLabels = $missingLabels
    workspaceDataPresent = $workspaceDataPresent
    sessionExpectedLabels = $sessionExpectedLabels
    sessionMissingLabels = $sessionMissingLabels
    sessionOpened = $sessionOpened
    uiTree = $uiTreePath
    screenshot = $screenshotPath
    sessionUiTree = if ($sessionOpened) { $sessionUiTreePath } else { $null }
    sessionScreenshot = if ($sessionOpened) { $sessionScreenshotPath } else { $null }
}
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[System.IO.File]::WriteAllText(
    $resultPath,
    ($result | ConvertTo-Json -Depth 6),
    $utf8NoBom
)
$result | ConvertTo-Json -Depth 6
