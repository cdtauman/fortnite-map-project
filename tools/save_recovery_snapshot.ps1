param(
    [string]$NativeProjectRoot = 'C:/Users/cdtauman/Documents/Fortnite Projects/ProCoachLab',
    [string]$SnapshotName = ('ProCoachLab_saved_194_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
)
$ErrorActionPreference = 'Stop'
$taskWorkspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$taskNativeRoot = [IO.Path]::GetFullPath($NativeProjectRoot)
$taskBackupRoot = [IO.Path]::GetFullPath((Join-Path $taskWorkspace '.local/backups'))
if ($SnapshotName -notmatch '^ProCoachLab_saved_194_[0-9]{8}_[0-9]{6}$') { throw 'Unexpected snapshot name' }
$taskOutput = [IO.Path]::GetFullPath((Join-Path $taskBackupRoot $SnapshotName))
if (-not $taskOutput.StartsWith($taskBackupRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Snapshot must stay in the workspace backup directory' }
if (Test-Path -LiteralPath $taskOutput) { throw 'Snapshot exists; inspect it instead of overwriting' }
if (-not (Test-Path -LiteralPath (Join-Path $taskNativeRoot 'ProCoachLab.uefnproject'))) { throw 'Expected ProCoachLab project is missing' }

function Get-TextDigest([string]$Path) {
    $taskText = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($taskText))).ToLowerInvariant()
}

$taskRepoVerse = @(Get-ChildItem -LiteralPath (Join-Path $taskWorkspace 'uefn/Verse') -Filter '*.verse' -File)
$taskNativeVerse = @(Get-ChildItem -LiteralPath (Join-Path $taskNativeRoot 'Content') -Filter '*.verse' -File -Recurse)
if ($taskRepoVerse.Count -ne 28 -or $taskNativeVerse.Count -ne 28) { throw 'Inspect the current source set before packaging' }
$taskSourcePairs = @(
    foreach ($taskFile in $taskRepoVerse) {
        $taskMatches = @($taskNativeVerse | Where-Object Name -EQ $taskFile.Name)
        if ($taskMatches.Count -ne 1) { throw ('Ambiguous native source: ' + $taskFile.Name) }
        $taskRepoHash = Get-TextDigest $taskFile.FullName
        $taskNativeHash = Get-TextDigest $taskMatches[0].FullName
        if ($taskRepoHash -ne $taskNativeHash) { throw ('Source differs; do not replace either copy: ' + $taskFile.Name) }
        [pscustomobject]@{ name = $taskFile.Name; normalized_sha256 = $taskRepoHash }
    }
)

$taskNativeFiles = @(
    Get-ChildItem -LiteralPath $taskNativeRoot -File
    foreach ($taskFolder in @('Content', 'Resources')) {
        Get-ChildItem -LiteralPath (Join-Path $taskNativeRoot $taskFolder) -File -Recurse
    }
)
$taskRepoFiles = @(
    foreach ($taskName in @('AGENTS.md', 'README.md', '.gitignore')) { Get-Item -LiteralPath (Join-Path $taskWorkspace $taskName) }
    Get-ChildItem -LiteralPath (Join-Path $taskWorkspace 'docs') -File -Filter '*.md'
    foreach ($taskFolder in @('uefn', 'tools')) {
        Get-ChildItem -LiteralPath (Join-Path $taskWorkspace $taskFolder) -File -Recurse | Where-Object { $_.Extension -notin @('.pyc', '.pyo') -and $_.FullName -notmatch '[\\/]__pycache__[\\/]' }
    }
)
$taskEvidence = @(
    Get-Item -LiteralPath (Join-Path $taskWorkspace '.local/academy-actors.json')
    Get-ChildItem -LiteralPath (Join-Path $taskWorkspace '.local') -File -Filter '*.json' | Where-Object { $_.Name -match '^(native-pool18[68]-|entry187-|legacy187-|combat-damage189-|structure-pose190-|round-attribution191-|review-selection192-|core193-)' }
)
$taskFiles = [Collections.Generic.List[object]]::new()
foreach ($taskGroup in @(
    @{ archive = 'ProCoachLab-native.zip'; root = $taskNativeRoot; files = $taskNativeFiles; prefix = '' },
    @{ archive = 'ProCoachLab-sources.zip'; root = $taskWorkspace; files = $taskRepoFiles; prefix = '' },
    @{ archive = 'ProCoachLab-sources.zip'; root = (Join-Path $taskWorkspace '.local'); files = $taskEvidence; prefix = 'evidence/' }
)) {
    foreach ($taskFile in $taskGroup.files) {
        if ($taskFile.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Inspect reparse-point files before packaging' }
        $taskRelative = [IO.Path]::GetRelativePath($taskGroup.root, $taskFile.FullName).Replace('\', '/')
        if ($taskRelative.StartsWith('../') -or [IO.Path]::IsPathRooted($taskRelative)) { throw 'File escaped its source root' }
        $taskFiles.Add([pscustomobject]@{ archive = $taskGroup.archive; entry = $taskGroup.prefix + $taskRelative; path = $taskFile.FullName; bytes = $taskFile.Length; sha256 = (Get-FileHash -LiteralPath $taskFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant() })
    }
}
New-Item -ItemType Directory -Path $taskOutput | Out-Null
$taskManifest = [ordered]@{
    scope = 'Saved local project recovery point; not gameplay, release, publication or product acceptance'
    created_at_utc = [DateTime]::UtcNow.ToString('o')
    native_project_root = $taskNativeRoot
    workspace_root = $taskWorkspace
    product_sources = $taskSourcePairs
    excluded = @('Native .lore database', 'Workspace .git and environments', 'Caches and browser/computer captures', 'Unrelated legacy package', 'Full operation logs')
    files = @($taskFiles | Select-Object archive, entry, bytes, sha256)
}
$taskManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $taskOutput 'manifest.json') -Encoding utf8
foreach ($taskArchive in @('ProCoachLab-native.zip', 'ProCoachLab-sources.zip')) {
    $taskPartial = Join-Path $taskOutput ($taskArchive + '.partial')
    $taskStream = [IO.File]::Open($taskPartial, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $taskZip = [IO.Compression.ZipArchive]::new($taskStream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($taskRow in $taskFiles | Where-Object archive -EQ $taskArchive) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($taskZip, $taskRow.path, $taskRow.entry, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally { $taskZip.Dispose(); $taskStream.Dispose() }
    Move-Item -LiteralPath $taskPartial -Destination (Join-Path $taskOutput $taskArchive)
}
$taskChecked = 0
foreach ($taskArchive in @('ProCoachLab-native.zip', 'ProCoachLab-sources.zip')) {
    $taskZip = [IO.Compression.ZipFile]::OpenRead((Join-Path $taskOutput $taskArchive))
    try {
        $taskRows = @($taskFiles | Where-Object archive -EQ $taskArchive)
        if ($taskZip.Entries.Count -ne $taskRows.Count) { throw 'Archive entry count differs' }
        foreach ($taskRow in $taskRows) {
            $taskEntry = $taskZip.GetEntry($taskRow.entry)
            if ($null -eq $taskEntry -or $taskEntry.Length -ne $taskRow.bytes) { throw 'Archive size differs' }
            $taskRead = $taskEntry.Open()
            try { $taskArchivedHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($taskRead)).ToLowerInvariant() } finally { $taskRead.Dispose() }
            $taskCurrentHash = (Get-FileHash -LiteralPath $taskRow.path -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($taskArchivedHash -ne $taskRow.sha256 -or $taskCurrentHash -ne $taskRow.sha256) { throw ('File changed during recovery capture: ' + $taskRow.entry) }
            $taskChecked++
        }
    } finally { $taskZip.Dispose() }
}
$taskVerification = [ordered]@{ complete = $true; verified_files = $taskChecked; matching_product_sources = $taskSourcePairs.Count; verification = 'SHA256 of archived bytes and unchanged source files'; restore_executed = $false; gameplay_executed = $false }
$taskVerification | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskOutput 'verification.json') -Encoding utf8
@'
# נקודת שחזור מקומית

זהו צילום של הקבצים השמורים, לא מסירת מוצר גמור או בדיקת משחק.

`ProCoachLab-native.zip` כולל את Content המלא, כולל מפת האי, Actors חיצוניים ונכסים, וכן Resources, קובץ הפרויקט וה־uplugin. `ProCoachLab-sources.zip` כולל את מקור העבודה, פריסות, הוראות ותיעוד טקסטואלי. הרשומות שב־evidence הן ראיות מתוארכות, לא אישורי הרצה.

לפני שחזור יש לסגור את UEFN ולשמור עותק נפרד של המצב הקיים. אין כלי שמשחזר או מוחק אוטומטית. יש לחלץ תחילה לתיקייה חדשה ולבדוק את manifest.json ו־verification.json. שחזור לתיקייה המקורית ייעשה רק לפי בקשה מפורשת, בלי לדרוס עבודה מאוחרת. הפרויקט שומר מזהים מקוריים; אין לפתוח במקביל שתי העתקות כאילו היו איים שונים.

הארכיון אינו כולל את מסד Lore, סביבות Python, מאגר Git או תלויות Epic המותקנות במחשב. הוא אינו גיבוי לכשל של הדיסק עצמו. 28 מקורות Verse הושוו לטקסט המקביל בפרויקט; אין בכך אימות משחק או תאימות לפרסום.
'@ | Set-Content -LiteralPath (Join-Path $taskOutput 'RESTORE_HE.md') -Encoding utf8
[pscustomobject]@{ directory = $taskOutput; verified_files = $taskChecked; matching_product_sources = $taskSourcePairs.Count; archive_bytes = ((Get-ChildItem -LiteralPath $taskOutput -Filter '*.zip' -File | Measure-Object Length -Sum).Sum) } | ConvertTo-Json -Compress
