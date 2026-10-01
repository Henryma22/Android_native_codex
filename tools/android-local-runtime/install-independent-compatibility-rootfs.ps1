[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ArchivePath,

    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [string]$AdbPath = 'C:\Users\Henry\AppData\Local\Android\Sdk\platform-tools\adb.exe',

    [string]$Serial = '',

    [string]$ExpectedSha256 = '',

    [ValidateRange(1, 600)]
    [int]$DeviceWaitSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PackageName = 'io.henry.codex'
$RuntimeBaseName = 'codex-compatibility-v1'

function Invoke-Adb {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $AdbPath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($exitCode -ne 0) {
        throw "adb failed ($exitCode): $($output -join "`n")"
    }
    return $output
}

function Wait-ForAdbDevice {
    param(
        [string[]]$Arguments = @()
    )

    $state = ''
    for ($attempt = 1; $attempt -le $DeviceWaitSeconds; $attempt++) {
        $stateOutput = @(& $AdbPath @($Arguments + @('get-state')) 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $state = ($stateOutput -join "`n").Trim()
            if ($state -eq 'device') {
                return
            }
        }
        Start-Sleep -Seconds 1
    }
    throw "ADB target did not become ready within ${DeviceWaitSeconds}s: serial=$Serial state=$state"
}

function Quote-DeviceShell {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    return "'$( $Value.Replace("'", "'\''") )'"
}

function Require-ManifestText {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "Rootfs manifest field is required: $Name"
    }
    return $text.Trim()
}

function Require-SafeToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Value -notmatch '^[A-Za-z0-9._+\-]+$') {
        throw "Rootfs manifest field contains an unsafe token: $Name"
    }
    return $Value
}

if (-not (Test-Path -LiteralPath $AdbPath -PathType Leaf)) {
    throw "adb was not found: $AdbPath"
}
if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
    throw "ArchivePath is not a regular file: $ArchivePath"
}
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "ManifestPath is not a regular file: $ManifestPath"
}
$finalizerPath = Join-Path $PSScriptRoot 'device/proot-finalize-rootfs.sh'
if (-not (Test-Path -LiteralPath $finalizerPath -PathType Leaf)) {
    throw "The checked-in ARM64 finalizer is missing: $finalizerPath"
}
$finalizer = (Resolve-Path -LiteralPath $finalizerPath).Path

$archive = (Resolve-Path -LiteralPath $ArchivePath).Path
$manifestFile = (Resolve-Path -LiteralPath $ManifestPath).Path
try {
    $manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
    throw "ManifestPath is not valid JSON: $ManifestPath"
}

if ([int]$manifest.schema.version -ne 1 -or
    (Require-ManifestText $manifest.schema.name 'schema.name') -ne 'codex-android-local-rootfs') {
    throw 'Rootfs manifest schema is unsupported'
}
$abi = Require-ManifestText $manifest.target.android_abi 'target.android_abi'
if ($abi -ne 'arm64-v8a') {
    throw "This independent compatibility installer accepts only arm64-v8a inputs: $abi"
}
$manifestFileName = Require-ManifestText $manifest.artifact.filename 'artifact.filename'
if (-not ([IO.Path]::GetFileName($archive)).Equals($manifestFileName, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Archive filename does not match the rootfs manifest: $manifestFileName"
}
$manifestSha256 = (Require-ManifestText $manifest.artifact.sha256 'artifact.sha256').ToLowerInvariant()
if ($manifestSha256 -notmatch '^[0-9a-f]{64}$') {
    throw 'Rootfs manifest artifact.sha256 must be 64 lowercase hexadecimal characters'
}
$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($archiveHash -ne $manifestSha256) {
    throw "SHA-256 mismatch. manifest=$manifestSha256 actual=$archiveHash"
}
if ($ExpectedSha256 -and $archiveHash -ne $ExpectedSha256.ToLowerInvariant()) {
    throw "SHA-256 mismatch. expected=$ExpectedSha256 actual=$archiveHash"
}

$nodeVersion = Require-SafeToken (Require-ManifestText $manifest.components.node.version 'components.node.version') 'components.node.version'
$codexVersion = Require-SafeToken (Require-ManifestText $manifest.components.codex.resolved_version 'components.codex.resolved_version') 'components.codex.resolved_version'
$debianSuite = Require-SafeToken (Require-ManifestText $manifest.debian.suite 'debian.suite') 'debian.suite'
$runtimeVersion = "debian-$debianSuite-node-$nodeVersion-codex-$codexVersion"

$deviceArguments = @()
if ($Serial) {
    $deviceArguments += @('-s', $Serial)
}
Wait-ForAdbDevice $deviceArguments
$deviceAbi = ((Invoke-Adb ($deviceArguments + @('shell', 'getprop', 'ro.product.cpu.abilist'))) -join "`n").Trim()
if (-not (($deviceAbi -split ',') -contains $abi)) {
    throw "Device ABI list does not include ${abi}: $deviceAbi"
}

$packageInfo = (Invoke-Adb ($deviceArguments + @('shell', 'dumpsys', 'package', $PackageName))) -join "`n"
$dataMatch = [regex]::Match($packageInfo, 'dataDir=(/data/user/[0-9]+/io\.henry\.codex)(?:\s|$)')
$uidMatch = [regex]::Match($packageInfo, 'uid=([0-9]+)\s')
$nativeMatch = [regex]::Match($packageInfo, 'legacyNativeLibraryDir=([^\s]+)')
if (-not $dataMatch.Success -or -not $uidMatch.Success -or -not $nativeMatch.Success) {
    throw "Could not resolve the installed $PackageName data directory, UID, and native library directory"
}
$dataDir = $dataMatch.Groups[1].Value
$appUid = $uidMatch.Groups[1].Value
$nativeDir = $nativeMatch.Groups[1].Value
if ($dataDir -notmatch '^/data/user/[0-9]+/io\.henry\.codex$') {
    throw "Package data directory is outside the independent compatibility contract: $dataDir"
}
if ($appUid -notmatch '^[1-9][0-9]{2,7}$') {
    throw "Package UID is invalid: $appUid"
}
if ($nativeDir -notmatch '^/data/app/[^\s]+/lib$') {
    throw "Package native library directory is outside the expected APK layout: $nativeDir"
}

$installId = [guid]::NewGuid().ToString('N')
$deviceStage = "/data/local/tmp/io.henry.codex-compat-install-$installId"
$deviceArchive = "$deviceStage/rootfs.tar.gz"
$deviceMarker = "$deviceStage/runtime.manifest.json"
$deviceFinalizer = "$deviceStage/proot-finalize-rootfs.sh"
$markerJson = [ordered]@{
    schemaVersion = 1
    state = 'verified'
    verificationMode = 'finalized-proot'
    rootfsDigest = $manifestSha256
    runtimeVersion = $runtimeVersion
    nodeVersion = $nodeVersion
    codexVersion = $codexVersion
} | ConvertTo-Json -Compress
$markerTemp = Join-Path $env:TEMP "io.henry.codex-compatibility-marker-$installId.json"
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[System.IO.File]::WriteAllText($markerTemp, $markerJson, $utf8NoBom)

try {
    Invoke-Adb ($deviceArguments + @('shell', 'mkdir', '-p', $deviceStage)) | Out-Null
    Invoke-Adb ($deviceArguments + @('push', $archive, $deviceArchive)) | Out-Null
    Invoke-Adb ($deviceArguments + @('push', $markerTemp, $deviceMarker)) | Out-Null
    Invoke-Adb ($deviceArguments + @('push', $finalizer, $deviceFinalizer)) | Out-Null

    $deviceInstall = @'
set -eu
   stage=__STAGE__
   data=__DATA__
   uid=__UID__
   native_dir=__NATIVE__
   finalizer=__FINALIZER__
digest=__DIGEST__
runtime_version=__RUNTIME_VERSION__
expected_node=__NODE_VERSION__
expected_codex=__CODEX_VERSION__
base="$data/no_backup/codex-compatibility-v1"
new="$data/no_backup/.codex-compatibility-v1.install-__INSTALL_ID__"
backup="$data/no_backup/.codex-compatibility-v1.backup-__INSTALL_ID__"
   rootfs="$new/rootfs"
   home="$new/home"
   temp="$new/proot-tmp"
   finalizer_bin="$temp/finalizer-bin"
   finalizer_lib="$temp/finalizer-lib"
   finalizer_sbin="$temp/finalizer-sbin"

# Keep interrupted or failed installs from leaving an opaque hidden slot
# behind. If activation has already moved the previous slot aside, restore it
# before removing the incomplete new tree.
cleanup_install() {
  status=$?
  trap - 0 1 2 3 15
  if test "$status" -ne 0; then
    if test -e "$backup" && ! test -e "$base"; then
      mv -f "$backup" "$base" || :
    fi
    if test -d "$new" && ! test -L "$new"; then
      rm -rf "$new" || :
    fi
  fi
  exit "$status"
}
trap cleanup_install 0 1 2 3 15

# PackageManager reports the APK's native library root on some Android
# releases, while ApplicationInfo.nativeLibraryDir resolves the ABI child.
# Accept only that fixed child; never search arbitrary app files.
if test -d "$native_dir/arm64"; then native_dir="$native_dir/arm64"; fi
proot="$native_dir/libcodex_proot.so"
loader="$native_dir/libcodex_proot_loader.so"
trampoline="$native_dir/libcodex_host_trampoline.so"

test -d "$stage" || exit 10
   test -f "$stage/rootfs.tar.gz" || exit 11
   test -f "$stage/runtime.manifest.json" || exit 12
   test ! -L "$stage/runtime.manifest.json" || exit 13
   test -f "$finalizer" || exit 14
   test ! -L "$finalizer" || exit 15
   test ! -L "$data" || exit 16
   test ! -L "$data/no_backup" || exit 17
   test ! -L "$base" || exit 18
   test -f "$proot" || exit 19
   test -f "$loader" || exit 20
   test -f "$trampoline" || exit 21

label=$(ls -Zd "$data/no_backup" | awk '{print $1}')
case "$label" in
  u:object_r:app_data_file:s0*) : ;;
  *) printf '%s\n' 'app-private SELinux file label is not app_data_file' >&2; exit 20 ;;
esac

rm -rf "$new" "$backup"
mkdir -p "$rootfs" "$home" "$temp"
tar -xzf "$stage/rootfs.tar.gz" -C "$rootfs"
test ! -L "$rootfs" || exit 21
test -f "$rootfs/usr/bin/dash" || exit 22
test -f "$rootfs/usr/bin/true" || exit 23
test -f "$rootfs/usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1" || exit 24
test -f "$rootfs/opt/node/bin/node" || exit 25
test -d "$rootfs/opt/codex/lib/node_modules/@openai/codex" || exit 26
   test -f "$rootfs/usr/local/bin/codex" || exit 27

# A rootfs update replaces the immutable guest tree, but /home/codex is the
# user's writable package/data area. Carry it forward before activation so
# user-prefix package data (for example /home/codex/.local/codex-pkgs) and
# files survive the version switch.
if test -e "$base/home" || test -L "$base/home"; then
  if test ! -d "$base/home" || test -L "$base/home"; then
    printf '%s\n' 'existing guest home is not a real directory; refusing to replace it' >&2
    exit 28
  fi
  cp -a "$base/home/." "$home/"
fi

   cp "$finalizer" "$rootfs/.codex-proot-finalize-v1"
   chmod 700 "$rootfs/.codex-proot-finalize-v1"

# Debian extraction does not reliably inherit the Android app's category
# labels through symlinks. -h is required so /etc/localtime and similar
# internal links receive the same app_data_file label as their targets.
chcon "$label" "$new"
chcon -Rh "$label" "$rootfs" "$home" "$temp"
   chmod 700 "$home" "$temp"
   chown "$uid:$uid" "$new" "$home" "$temp"

   # Debian's foreign archive uses merged-/usr aliases. During the second
   # stage those aliases can become self-referential under PRoot's normal
   # link projection. Build private, temporary FHS projections for the
   # finalizer only; they are deleted before the slot is activated.
   rm -rf "$finalizer_bin" "$finalizer_lib" "$finalizer_sbin"
   mkdir -p "$finalizer_bin" "$finalizer_lib" "$finalizer_sbin"
   cp -a "$rootfs/usr/bin/." "$finalizer_bin/"
   rm -f "$finalizer_bin/sh"
   cp "$finalizer_bin/dash" "$finalizer_bin/sh"
   cp -a "$rootfs/usr/lib/." "$finalizer_lib/"
   cp -a "$rootfs/usr/sbin/." "$finalizer_sbin/"
   chcon -Rh "$label" "$finalizer_bin" "$finalizer_lib" "$finalizer_sbin"

export PATH=/opt/node/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/home/codex
export TMPDIR=/tmp
export PROOT_NO_SECCOMP=1
export PROOT_LOADER="$loader"
export PROOT_TMP_DIR="$temp"

   run_guest() {
    "$proot" \
    --link2symlink \
    --kill-on-exit \
    --rootfs="$rootfs" \
    --bind="$rootfs/usr/bin:/bin!" \
    --bind="$rootfs/usr/bin/dash:/bin/sh!" \
    --bind="$rootfs/usr/lib:/lib!" \
    --bind="$rootfs/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu!" \
    --bind="$rootfs/usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1:/lib/ld-linux-aarch64.so.1!" \
    --bind="$rootfs/usr/sbin:/sbin!" \
    --bind="$trampoline:/codex-host-trampoline" \
    --bind=/proc:/proc \
    --bind="$home:/home/codex!" \
    --bind="$temp:/tmp!" \
    --cwd=/home/codex \
    --root-id \
       /codex-host-trampoline "$@"
   }

   run_finalizer() {
       "$proot" \
       --kill-on-exit \
       --rootfs="$rootfs" \
       --bind="$finalizer_bin:/bin!" \
       --bind="$finalizer_sbin:/sbin!" \
       --bind="$finalizer_lib:/lib!" \
       --bind="$trampoline:/codex-host-trampoline" \
       --bind=/proc:/proc \
       --bind="$home:/home/codex!" \
       --bind="$temp:/tmp!" \
       --cwd=/home/codex \
       --root-id \
       /codex-host-trampoline \
       /.codex-proot-finalize-v1 \
       "$@"
   }

   if ! finalizer_output=$(run_finalizer "$expected_node" "$expected_codex" "$base" "$digest" 2>&1); then
     printf '%s\n' 'ARM64 PRoot rootfs finalization failed' >&2
     printf '%s\n' "$finalizer_output" >&2
     rm -rf "$new"
     exit 30
   fi
   test -f "$rootfs/var/lib/codex/rootfs-finalized-proot-v1" || {
     printf '%s\n' 'ARM64 PRoot finalizer did not write its success marker' >&2
     rm -rf "$new"
     exit 31
   }
   rm -f "$rootfs/.codex-proot-finalize-v1"
   rm -rf "$finalizer_bin" "$finalizer_lib" "$finalizer_sbin"

   # The Debian second stage can unpack or replace files after the initial
   # extraction relabel. Reapply the package-private app_data_file label to
   # the final tree, including symlinks, before the slot becomes active.
   # Otherwise an untouched shared object such as libpcre2 can retain the
   # default s0 label and Android's dynamic loader reports EPERM.
   if ! chcon -Rh "$label" "$rootfs" "$home" "$temp"; then
     printf '%s\n' 'post-finalization SELinux relabel failed' >&2
     rm -rf "$new"
     exit 30
   fi

   if ! true_output=$(run_guest /usr/bin/true 2>&1); then
     printf '%s\n' 'PRoot guest probe failed' >&2
     printf '%s\n' "$true_output" >&2
     rm -rf "$new"
     exit 32
   fi
if ! node_output=$(run_guest /opt/node/bin/node --version 2>&1); then
     printf '%s\n' 'Node.js guest probe failed' >&2
     rm -rf "$new"
     exit 33
fi
case "$node_output" in
  *"$expected_node"*) : ;;
     *) printf '%s\n' 'Node.js guest version did not match the manifest' >&2; rm -rf "$new"; exit 34 ;;
esac
if ! codex_output=$(run_guest /usr/local/bin/codex --version 2>&1); then
     printf '%s\n' 'Codex guest probe failed' >&2
     rm -rf "$new"
     exit 35
fi
case "$codex_output" in
  *"${expected_codex%%-*}"*) : ;;
     *) printf '%s\n' 'Codex guest version did not match the manifest' >&2; rm -rf "$new"; exit 36 ;;
esac

marker="$new/runtime.manifest.json"
cp "$stage/runtime.manifest.json" "$marker"
chcon "$label" "$marker"
chown "$uid:$uid" "$marker"
chmod 644 "$marker"

had_previous=0
if test -e "$base"; then
  mv -f "$base" "$backup"
  had_previous=1
fi
   if ! mv -f "$new" "$base"; then
     rm -rf "$base"
     if test "$had_previous" -eq 1; then mv -f "$backup" "$base"; fi
     exit 37
   fi
rm -rf "$backup"
printf '%s\n' 'state=verified'
   printf '%s\n' 'verification=finalized-proot'
printf '%s\n' "node=$node_output"
printf '%s\n' "codex=$codex_output"
'@
    $deviceInstall = $deviceInstall.Replace('__STAGE__', (Quote-DeviceShell $deviceStage))
    $deviceInstall = $deviceInstall.Replace('__DATA__', (Quote-DeviceShell $dataDir))
    $deviceInstall = $deviceInstall.Replace('__UID__', (Quote-DeviceShell $appUid))
    $deviceInstall = $deviceInstall.Replace('__NATIVE__', (Quote-DeviceShell $nativeDir))
    $deviceInstall = $deviceInstall.Replace('__FINALIZER__', (Quote-DeviceShell $deviceFinalizer))
    $deviceInstall = $deviceInstall.Replace('__DIGEST__', (Quote-DeviceShell $manifestSha256))
    $deviceInstall = $deviceInstall.Replace('__RUNTIME_VERSION__', (Quote-DeviceShell $runtimeVersion))
    $deviceInstall = $deviceInstall.Replace('__NODE_VERSION__', (Quote-DeviceShell $nodeVersion))
    $deviceInstall = $deviceInstall.Replace('__CODEX_VERSION__', (Quote-DeviceShell $codexVersion))
    $deviceInstall = $deviceInstall.Replace('__INSTALL_ID__', $installId)

    $installOutput = Invoke-Adb ($deviceArguments + @('shell', 'su', '-c', $deviceInstall))
    Write-Output "Installed independent Android compatibility rootfs: $dataDir/no_backup/$RuntimeBaseName"
    Write-Output "Rootfs SHA-256: $manifestSha256"
    Write-Output "Runtime: $runtimeVersion"
    Write-Output "Node.js: $nodeVersion"
    Write-Output "Codex: $codexVersion"
    Write-Output "Finalizer: $finalizer"
    if ($installOutput) {
        Write-Output (($installOutput -join "`n").Trim())
    }
}
finally {
    Remove-Item -LiteralPath $markerTemp -Force -ErrorAction SilentlyContinue
    try {
        Invoke-Adb ($deviceArguments + @(
            'shell',
            'su',
            '-c',
            "rm -rf $(Quote-DeviceShell $deviceStage)"
        )) | Out-Null
    }
    catch {
        # Preserve the installation result; the temporary staging path is
        # exact and can be removed by the next invocation if the device went
        # offline during cleanup.
    }
}
