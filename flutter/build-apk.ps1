# Builds the signed Android app into release/<version>/ at the project root:
#
#     powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1          the APK, for GitHub
#     powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1 -Aab     the App Bundle, for Play
#
# The APK is for ARM phones, 32 and 64 bit, in one file (the app's updater fetches the one file):
# uwuhere-<version>.apk. The App Bundle is
# uwuhere-<version>.aab, Play's own build: no updater of its own (src/play/AndroidManifest.xml
# and UWUHERE_PLAY take it out, and that's checked here).
#
# Both are shrunk and obfuscated as Google Play asks: R8 on the Java and its libraries, with unused
# resources removed (android/app/build.gradle.kts), and the Dart code obfuscated with its symbols
# split off (--obfuscate --split-debug-info). What reads a crash report back is kept beside them in
# release/<version>/ and never shared: uwuhere-<version>-mapping.txt (R8) and
# uwuhere-<version>-symbols.zip (Dart, for `flutter symbolize`). The App Bundle carries both kinds
# for Play too (R8's mapping, and the native libraries' symbol tables), which is checked here.
#
# Each is signed with android.keystore using the passwords in keystore.properties (both kept out of
# git, README.md), and the signature is checked against the app's own key before it's copied out.
#
# Needs Flutter on the PATH (or FLUTTER_ROOT), a JDK 17 or later and the Android SDK. It finds the
# JDK and SDK in JAVA_HOME and ANDROID_HOME if they're set, or else the newest JDK under Program
# Files and the SDK in %LOCALAPPDATA%\Android\Sdk.

param([switch]$Aab)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
# The app's key: an APK signed with any other can't update one already installed.
# The same key as the Capacitor app (1.0.x), so 2.0.0 installs over it
# (main-site/.well-known/assetlinks.json).
$keySha256 = 'EE0DA7D3D53080EADD08413D304E35E01128D0685519698E6FF3ED318D54857A'

if (-not (Test-Path "$here\keystore.properties") -or -not (Test-Path "$here\android.keystore")) {
    throw "android.keystore and keystore.properties are missing from $here. They're not in git: restore them from your backup."
}

function Find-Jdk {
    if ($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\java.exe")) {
        # Through cmd: Windows PowerShell 5.1 turns a native program's stderr into an error under 'Stop'.
        $v = cmd /c "`"$env:JAVA_HOME\bin\java.exe`" -version 2>&1" | Out-String
        if ($v -match 'version "(\d+)' -and [int]$Matches[1] -ge 17) { return $env:JAVA_HOME }
    }
    $candidates = @('C:\Program Files\Eclipse Adoptium', 'C:\Program Files\Java', 'C:\Program Files\Microsoft', 'C:\Program Files\Android\Android Studio\jbr') |
        Where-Object { Test-Path $_ } |
        ForEach-Object { if (Test-Path "$_\bin\java.exe") { Get-Item $_ } else { Get-ChildItem $_ -Directory -Filter 'jdk*' } } |
        Where-Object { Test-Path "$($_.FullName)\bin\java.exe" } |
        Sort-Object { $m = [regex]::Match($_.Name, 'jdk-?(\d+)'); if ($m.Success) { [int]$m.Groups[1].Value } else { 0 } }
    if ($candidates) { return ($candidates | Select-Object -Last 1).FullName }
    throw 'No JDK 17 or later found. Install one (https://adoptium.net) or set JAVA_HOME to it.'
}

$env:JAVA_HOME = Find-Jdk
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
if (-not $env:ANDROID_HOME) {
    if (Test-Path "$env:LOCALAPPDATA\Android\Sdk") { $env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk" }
    else { throw 'No Android SDK found. Set ANDROID_HOME to it.' }
}
$buildTools = Get-ChildItem "$env:ANDROID_HOME\build-tools" -Directory | Sort-Object { [version]$_.Name } | Select-Object -Last 1

$pubspec = Get-Content "$here\pubspec.yaml" -Raw
$version = [regex]::Match($pubspec, '(?m)^version:\s*([0-9.]+)').Groups[1].Value
# A new version code for every build, APK or bundle: Play refuses a code it has ever seen, and a phone
# only takes a higher one as an update. The version name stays as it is. Commit pubspec.yaml with it.
$codeMatch = [regex]::Match($pubspec, '(?m)^version:\s*[0-9.]+\+(\d+)')
if (-not $codeMatch.Success) { throw 'pubspec.yaml''s version needs a build number, as in 1.0.0+1.' }
$versionCode = [int]$codeMatch.Groups[1].Value + 1
$pubspec = [regex]::Replace($pubspec, '(?m)^(version:\s*[0-9.]+)\+\d+', "`${1}+$versionCode")
[IO.File]::WriteAllText("$here\pubspec.yaml", $pubspec, (New-Object Text.UTF8Encoding $false))
Write-Host "Version code raised to $versionCode."
$flutter = if ($env:FLUTTER_ROOT) { "$env:FLUTTER_ROOT\bin\flutter.bat" } else { 'flutter' }
$out = "$root\release\$version"
New-Item -ItemType Directory -Force $out | Out-Null
Write-Host "Building uwuHere $version ($versionCode) for Android (JDK: $env:JAVA_HOME)..."

# The Dart side's symbols, split off the obfuscated code, one folder per kind of build. Never
# emptied here: when nothing's changed, Gradle skips compiling the Dart again and doesn't write
# them again either.
$kind = if ($Aab) { 'play' } else { 'github' }
$symbols = "$here\symbols\$version-$kind"

function Save-CrashReaders($suffix) {
    $mapping = "$here\build\app\outputs\mapping\release\mapping.txt"
    if (-not (Test-Path $mapping)) { throw "R8 made no mapping: is isMinifyEnabled still on in android/app/build.gradle.kts?" }
    Copy-Item $mapping "$out\uwuhere-$version$suffix-mapping.txt" -Force
    if (-not (Get-ChildItem $symbols -Filter '*.symbols' -ErrorAction SilentlyContinue)) {
        throw "No Dart symbols in $symbols. Run 'flutter clean' in flutter\ and build again."
    }
    Compress-Archive -Path "$symbols\*" -DestinationPath "$out\uwuhere-$version$suffix-symbols.zip" -Force
}

Push-Location $here
try {
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
    if ($Aab) {
        $bundle = "$here\build\app\outputs\bundle\release\app-release.aab"
        # Never an old one: with nothing changed, Gradle wouldn't write it again.
        Remove-Item $bundle -Force -ErrorAction SilentlyContinue
        & $flutter build appbundle --release --obfuscate --split-debug-info=$symbols --dart-define=UWUHERE_PLAY=true --android-project-arg=uwuherePlay=true
        $failed = $LASTEXITCODE -ne 0
    } else {
        & $flutter build apk --release --target-platform android-arm,android-arm64 --obfuscate --split-debug-info=$symbols
        if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed. Its messages are above.' }
    }
} finally {
    Pop-Location
}

if ($Aab) {
    # Flutter's last step looks for debug symbols with apkanalyzer, from the SDK's cmdline-tools,
    # and says it failed if that isn't installed. So a failure counts only if no bundle was made,
    # or if the same look, done here, finds them missing.
    if (-not (Test-Path $bundle)) {
        if ($failed) { throw 'flutter build appbundle failed. Its messages are above.' }
        throw 'Gradle made no bundle.'
    }
    $ErrorActionPreference = 'Continue'
    $certs = & "$env:JAVA_HOME\bin\keytool.exe" -printcert -jarfile $bundle 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
    if (($certs -replace ':', '') -notmatch "SHA256\s*$keySha256") { throw "The bundle isn't signed with the app's key: is keystore.properties right?" }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($bundle)
    try {
        $stream = $zip.GetEntry('base/manifest/AndroidManifest.xml').Open()
        $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::GetEncoding(28591))
        $manifest = $reader.ReadToEnd()
        $reader.Dispose()
        $entries = @($zip.Entries | ForEach-Object { $_.FullName })
    } finally {
        $zip.Dispose()
    }
    # Nothing of the updater left in what Play reads.
    if ($manifest -match 'REQUEST_INSTALL_PACKAGES') { throw 'The bundle still has REQUEST_INSTALL_PACKAGES in its manifest.' }
    # No ads, no analytics: Play's Advertising ID declaration is "No", so the permission mustn't be there.
    if ($manifest -match 'permission\.AD_ID') { throw 'The bundle asks for the advertising ID (AD_ID), which the app never uses.' }
    # The native libraries' symbols stripped into the bundle's metadata, for Play's crash reports.
    foreach ($lib in 'libflutter', 'libapp') {
        if (-not ($entries -match "^BUNDLE-METADATA/com\.android\.tools\.build\.debugsymbols/.*/$lib\.so\.(sym|dbg)$")) {
            throw "The bundle's $lib.so hasn't had its debug symbols stripped into its metadata."
        }
    }
    # R8 ran, and Play gets its mapping, to read crashes and measure the code's optimisation.
    if (-not ($entries -contains 'BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map')) {
        throw 'The bundle has no R8 mapping: is isMinifyEnabled still on in android/app/build.gradle.kts?'
    }
    Copy-Item $bundle "$out\uwuhere-$version.aab" -Force
    Save-CrashReaders '-play'
    Write-Host "Done: $out\uwuhere-$version.aab (version code $versionCode)"
    return
}

$signed = "$here\build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $signed)) { throw "Gradle made no signed APK: is keystore.properties's storeFile right?" }
# Its warnings (META-INF/*.version "not protected by signature") come with every Android build and
# mean nothing here; only a failure matters. Windows PowerShell turns anything a program writes to
# stderr into an error, so only its exit code is looked at.
$ErrorActionPreference = 'Continue'
$check = & "$($buildTools.FullName)\apksigner.bat" verify --print-certs $signed 2>&1
$verified = $LASTEXITCODE -eq 0
$ErrorActionPreference = 'Stop'
if (-not $verified) { $check | Write-Host; throw 'The signed app failed its signature check.' }
$sha = [regex]::Match(($check | Out-String), 'SHA-256 digest: ([0-9a-f]{64})').Groups[1].Value
if ($sha -and $sha.ToUpper() -ne $keySha256) {
    throw "The APK is signed with a different key ($sha), so it can't update the app already installed."
}
Copy-Item $signed "$out\uwuhere-$version.apk" -Force
Save-CrashReaders ''

# The version code really is the new one.
$badging = & "$($buildTools.FullName)\aapt2.exe" dump badging $signed 2>$null | Select-Object -First 1
if ($badging -notmatch "versionCode='$versionCode'") { throw "The APK's version code isn't $versionCode ($badging)." }
Write-Host "Done: $out\uwuhere-$version.apk (version code $versionCode)"
