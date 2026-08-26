<#
.SYNOPSIS
    Builds a complete player spell packet: 3x3 Spell Card Sheets, full Spell Descriptions,
    and a Book Index — all filtered to a single player's class and level selection.

.DESCRIPTION
    Reads pre-downloaded spell data from master-spells.json (produced by DownloadRepo-Spells.ps1)
    and generates two print-ready PDF outputs per spell level:

      1. Spell Card Sheets  — 3x3 grid of poker-sized cards (62mm x 87mm), one per spell.
                              Cards include title, level badge, range/duration/casting time stats,
                              body text (truncated if needed), school and source footer.
                              Laid out on 8.5x11 sheets with crop marks for cutting.
                              Cards are sized to fit standard 9-pocket trading card binder pages.

      2. Spell Descriptions — Full-text reference sheet in a two-column letter-page layout,
                              grouped by spell level. Mirrors the PHB style so players can look
                              up complete spell rules without thumbing through the book.

    A Book Index PDF is also rendered from Book-Index.html as part of the packet.
    All outputs are rendered to PDF via Chrome headless and saved to Print_Sheets_PDF\.
    HTML intermediates are preserved in Print_Sheets_HTML\ for inspection or re-rendering.

.PARAMETER ClassName
    Required. The character's class (e.g. "Wizard"). Filters spells by class.
    Must be a valid class name from the ValidateSet.

.PARAMETER Levels
    Optional. One or more spell levels to include (e.g. -Levels 0,1,2).
    If omitted, all levels are included.

.PARAMETER PlayerName
    Optional. Used to name output files (e.g. WillowLeaf_Spell-Card-Sheet_Level-1.pdf).
    Defaults to ClassName if not provided.

.EXAMPLE
    .\BuildSpellPacket.ps1 -ClassName Wizard -Levels 0,1 -PlayerName WillowLeaf
    .\BuildSpellPacket.ps1 -ClassName Druid -Levels 0,1,2 -PlayerName Aria

.NOTES
    Requires: Google Chrome (for headless PDF rendering)
    Data:     Run DownloadRepo-Spells.ps1 first to populate the Repo\ folder.
    Ruleset:  Supports multiple editions — see Book-Index.html for source abbreviations.
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        'Artificer', 'Barbarian', 'Bard', 'Cleric', 'Druid',
        'Fighter', 'Monk', 'Paladin', 'Ranger', 'Rogue',
        'Sorcerer', 'Warlock', 'Wizard'
    )]
    [string]$ClassName,

    [string[]]$Levels,

    [string]$PlayerName,

    [string]$HtmlOutputDir      = (Join-Path $PSScriptRoot "Print_Sheets_HTML"),
    [string]$PdfOutputDir       = (Join-Path $PSScriptRoot "Print_Sheets_PDF"),
    [string]$SheetTemplatePath  = (Join-Path $PSScriptRoot "Shared\Sheet-3x3-Template.html"),
    [string]$CardTemplatePath   = (Join-Path $PSScriptRoot "Spells\Spellcard-Template.html"),
    [string]$DescTemplatePath   = (Join-Path $PSScriptRoot "Spells\Spell-Descriptions-Template.html"),
    [string]$BookIndexPath      = (Join-Path $PSScriptRoot "Shared\Book-Index.html"),
    [string]$MasterSpellsPath   = (Join-Path $PSScriptRoot "Repo\master-spells.json"),
    [string]$ChromeExe          = "C:\Program Files\Google\Chrome\Application\chrome.exe"
)

# Normalize input casing
$ClassName = (Get-Culture).TextInfo.ToTitleCase($ClassName.ToLower())
if (-not $PlayerName) { $PlayerName = $ClassName }
$SafePlayerName = $PlayerName -replace '[\\/:*?"<>|]', ''

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Building Player Spell Packet" -ForegroundColor Cyan
Write-Host "  Player : $PlayerName" -ForegroundColor Cyan
Write-Host "  Class  : $ClassName" -ForegroundColor Cyan
Write-Host "  Levels : $(if ($Levels) { $Levels -join ', ' } else { 'All' })" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Ensure output directories exist
if (-not (Test-Path $HtmlOutputDir)) { New-Item -ItemType Directory -Path $HtmlOutputDir | Out-Null }
if (-not (Test-Path $PdfOutputDir))  { New-Item -ItemType Directory -Path $PdfOutputDir  | Out-Null }

# Verify required files exist
foreach ($req in @(
    @{ Path = $SheetTemplatePath; Name = "Sheet-3x3-Template.html" },
    @{ Path = $CardTemplatePath;  Name = "Spellcard-Template.html" },
    @{ Path = $DescTemplatePath;  Name = "Spell-Descriptions-Template.html" },
    @{ Path = $BookIndexPath;     Name = "Book-Index.html" },
    @{ Path = $MasterSpellsPath;  Name = "master-spells.json" }
)) {
    if (-not (Test-Path $req.Path)) {
        Write-Error "Required file not found: $($req.Name) at $($req.Path)"
        exit 1
    }
}

# Verify Chrome
if (-not (Test-Path $ChromeExe)) {
    $ChromeExe = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
    if (-not (Test-Path $ChromeExe)) {
        Write-Error "Chrome not found. Please verify the ChromeExe path."
        exit 1
    }
}

# Clean old output files for this player
if ($Levels) {
    foreach ($lvl in $Levels) {
        $label = if ([int]$lvl -eq 0) { "Cantrip" } else { "Level-$lvl" }
        Remove-Item "$HtmlOutputDir\${SafePlayerName}_Spell-Card-Sheet_${label}.html" -ErrorAction SilentlyContinue
        Remove-Item "$PdfOutputDir\${SafePlayerName}_Spell-Card-Sheet_${label}.pdf"   -ErrorAction SilentlyContinue
    }
} else {
    Remove-Item "$HtmlOutputDir\${SafePlayerName}_Spell-Card-Sheet_*.html" -ErrorAction SilentlyContinue
    Remove-Item "$PdfOutputDir\${SafePlayerName}_Spell-Card-Sheet_*.pdf"   -ErrorAction SilentlyContinue
}
Remove-Item "$HtmlOutputDir\${SafePlayerName}_Spell-Descriptions.html" -ErrorAction SilentlyContinue
Remove-Item "$PdfOutputDir\${SafePlayerName}_Spell-Descriptions.pdf"   -ErrorAction SilentlyContinue

# ==========================================
# HELPER: Render PDF via Chrome headless
# ==========================================
function Invoke-ChromePdf {
    param([string]$HtmlPath, [string]$PdfPath, [string]$Label)

    Write-Host "  Rendering $Label..." -ForegroundColor Yellow
    $htmlUri = ([System.Uri]([System.IO.Path]::GetFullPath($HtmlPath))).AbsoluteUri
    $pdfFull = [System.IO.Path]::GetFullPath($PdfPath)

    $args = @(
        "--headless=new",
        "--disable-gpu",
        "--no-pdf-header-footer",
        "--print-to-pdf=`"$pdfFull`"",
        "`"$htmlUri`""
    )
    Start-Process -FilePath $ChromeExe -ArgumentList $args -Wait -NoNewWindow
    Write-Host "    Saved: $PdfPath" -ForegroundColor Green
}

# ==========================================
# HELPER: School code to full name
# ==========================================
function Get-SchoolName ($code) {
    switch ($code) {
        "A" { "Abjuration" }    "C" { "Conjuration" }
        "D" { "Divination" }    "E" { "Enchantment" }
        "V" { "Evocation" }     "I" { "Illusion" }
        "N" { "Necromancy" }    "T" { "Transmutation" }
        default { $code }
    }
}

# ==========================================
# HELPER: Format casting time
# ==========================================
function Get-CastingTime ($timeArray) {
    if (-not $timeArray) { return "" }
    $t    = $timeArray[0]
    $unit = $t.unit
    if ($t.number -gt 1) { $unit += "s" }
    return "$($t.number) $unit"
}

# ==========================================
# HELPER: Format range
# ==========================================
function Get-Range ($rangeObj) {
    if (-not $rangeObj) { return "" }
    if ($rangeObj.distance) {
        if ($rangeObj.distance.amount) {
            return "$($rangeObj.distance.amount) $($rangeObj.distance.type)"
        }
        return "$($rangeObj.distance.type)"
    }
    $t = $rangeObj.type
    if ($t) { return ([string]$t).Substring(0,1).ToUpper() + ([string]$t).Substring(1).ToLower() }
    return ""
}

# ==========================================
# HELPER: Format duration
# ==========================================
function Get-Duration ($durationArray) {
    if (-not $durationArray -or $durationArray.Count -eq 0) { return "" }

    $d = $durationArray[0]

    if ($d.type -eq "instant")   { return "Instantaneous" }
    if ($d.type -eq "permanent") { return "Permanent" }
    if ($d.type -eq "special")   { return "Special" }

    $parts = [System.Collections.Generic.List[string]]::new()

    if ($d.concentration -eq $true) { $parts.Add("Concentration") }

    if ($d.duration) {
        $amount = $d.duration.amount
        $type   = $d.duration.type
        if ($amount -gt 1) { $type += "s" }

        if ($d.ends -contains "dispel" -or $d.concentration -eq $true) {
            $parts.Add("up to $amount $type")
        } else {
            $parts.Add("$amount $type")
        }
    }

    if ($parts.Count -gt 0) { return ($parts -join ", ") }
    return $d.type
}

# ==========================================
# HELPER: Recursively extract entry text as HTML
# ==========================================
function Get-EntryHtml ($entry) {
    if ($entry -is [string]) {
        $text = $entry
        $text = $text -replace '\{@(bold|b) ([^}]+)\}',        '<b>$2</b>'
        $text = $text -replace '\{@(italic|i) ([^}]+)\}',      '<i>$2</i>'
        $text = $text -replace '\{@(dice|damage) ([^}]+)\}',   '$2'
        $text = $text -replace '\{@\w+ ([^}|]+)(\|[^}]+)?\}', '$1'
        return "<p>$text</p>"
    }
    elseif ($entry.PSObject.Properties['name'] -and $entry.PSObject.Properties['entries']) {
        $name    = $entry.name
        $subHtml = ($entry.entries | ForEach-Object { Get-EntryHtml $_ }) -join ""
        $subHtml = $subHtml -replace '^<p>', "<p><b><i>$name.</i></b> "
        return $subHtml
    }
    elseif ($entry.PSObject.Properties['entries']) {
        return ($entry.entries | ForEach-Object { Get-EntryHtml $_ }) -join ""
    }
    elseif ($entry.PSObject.Properties['items']) {
        return ($entry.items | ForEach-Object { Get-EntryHtml $_ }) -join ""
    }
    return ""
}

# ==========================================
# LOAD DATA & TEMPLATES
# ==========================================
$masterSpells  = Get-Content -Raw -Path $MasterSpellsPath -Encoding UTF8 | ConvertFrom-Json
$sheetTemplate = Get-Content -Raw -Path $SheetTemplatePath -Encoding UTF8
$cardTemplate  = Get-Content -Raw -Path $CardTemplatePath  -Encoding UTF8
$descTemplate  = Get-Content -Raw -Path $DescTemplatePath  -Encoding UTF8

# Extract CSS and markup from card template — same pattern as feature pipeline
$cardStyle  = ""
$cardMarkup = ""
if ($cardTemplate -match '(?s)<style>(.*?)</style>')      { $cardStyle  = $Matches[1] }
if ($cardTemplate -match '(?s)<body>\s*(.*?)\s*</body>') { $cardMarkup = $Matches[1] }

# Filter spells by class and level
$filteredSpells = $masterSpells | Where-Object {
    $s    = $_
    $keep = $true
    if ($s.classes -notcontains $ClassName) { $keep = $false }
    if ($keep -and $Levels -and $Levels.Count -gt 0) {
        if ($s.level -notin ($Levels | ForEach-Object { [int]$_ })) { $keep = $false }
    }
    return $keep
}

Write-Host "  Found $($filteredSpells.Count) matching spells." -ForegroundColor Green

# Group by level, sort by name within each level
$byLevel = $filteredSpells | Group-Object level | Sort-Object { [int]$_.Name }

# ==========================================
# PART 1 — SPELL CARD SHEETS (3x3 grid)
# ==========================================
Write-Host ""
Write-Host "[1/3] Building Spell Card Sheets..." -ForegroundColor Cyan

foreach ($levelGroup in $byLevel) {
    $levelNum   = [int]$levelGroup.Name
    $levelLabel = if ($levelNum -eq 0) { "Cantrip" } else { "Level-$levelNum" }
    $hexLabel   = if ($levelNum -eq 0) { "C" } else { "$levelNum" }
    $levelSpells = $levelGroup.Group | Sort-Object name

    Write-Host "  Processing $levelLabel ($($levelSpells.Count) spells)..." -ForegroundColor Yellow

    $allSheetsHtml = [System.Collections.Generic.List[string]]::new()

    for ($i = 0; $i -lt $levelSpells.Count; $i += 9) {
        $batch     = @($levelSpells[$i..[Math]::Min($i + 8, $levelSpells.Count - 1)])
        $cellHtmls = [System.Collections.Generic.List[string]]::new()

        foreach ($spell in $batch) {
            $school      = Get-SchoolName $spell.school
            $castTime    = Get-CastingTime $spell.time
            $range       = Get-Range       $spell.range
            $duration    = Get-Duration    $spell.duration
            $classes     = ($spell.classes -join ", ")
            $description = if ($spell.cardDescription) { $spell.cardDescription } else {
                ($spell.entries | ForEach-Object { Get-EntryHtml $_ }) -join ""
            }

            $cardHtml = $cardMarkup
            $cardHtml = $cardHtml -replace '\{\{Title\}\}',       $spell.name
            $cardHtml = $cardHtml -replace '\{\{Level\}\}',       $hexLabel
            $cardHtml = $cardHtml -replace '\{\{Range\}\}',       $range
            $cardHtml = $cardHtml -replace '\{\{Duration\}\}',    $duration
            $cardHtml = $cardHtml -replace '\{\{CastingTime\}\}', ($castTime -replace 'Casting Time', 'Cast Time')
            $cardHtml = $cardHtml -replace '\{\{Description\}\}', $description
            $cardHtml = $cardHtml -replace '\{\{School\}\}',      $school
            $cardHtml = $cardHtml -replace '\{\{Edition\}\}',     $spell.sourceEdition
            $cardHtml = $cardHtml -replace '\{\{Source\}\}',      $spell.source
            $cardHtml = $cardHtml -replace '\{\{Classes\}\}',     $classes

            $cellHtmls.Add("<div class=`"grid-cell`">$cardHtml</div>")
        }

        # Pad to exactly 9 cells
        while ($cellHtmls.Count -lt 9) {
            $cellHtmls.Add("<div class=`"grid-cell`"></div>")
        }

        $sheetBlock = @"
<div class="sheet-container">
    <div class="crop-marks-layer">
        <div class="crop-line v-line v-top" style="left: 14.95mm;"></div>
        <div class="crop-line v-line v-top" style="left: 76.95mm;"></div>
        <div class="crop-line v-line v-top" style="left: 138.95mm;"></div>
        <div class="crop-line v-line v-top" style="left: 200.95mm;"></div>
        <div class="crop-line v-line v-bottom" style="left: 14.95mm;"></div>
        <div class="crop-line v-line v-bottom" style="left: 76.95mm;"></div>
        <div class="crop-line v-line v-bottom" style="left: 138.95mm;"></div>
        <div class="crop-line v-line v-bottom" style="left: 200.95mm;"></div>
        <div class="crop-line h-line h-left" style="top: 9.2mm;"></div>
        <div class="crop-line h-line h-left" style="top: 96.2mm;"></div>
        <div class="crop-line h-line h-left" style="top: 183.2mm;"></div>
        <div class="crop-line h-line h-left" style="top: 270.2mm;"></div>
        <div class="crop-line h-line h-right" style="top: 9.2mm;"></div>
        <div class="crop-line h-line h-right" style="top: 96.2mm;"></div>
        <div class="crop-line h-line h-right" style="top: 183.2mm;"></div>
        <div class="crop-line h-line h-right" style="top: 270.2mm;"></div>
    </div>
    <div class="page-grid">
$($cellHtmls -join "`n")
    </div>
</div>
"@
        $allSheetsHtml.Add($sheetBlock)
    }

    $styledSheet   = $sheetTemplate -replace '</head>', "<style>`n$cardStyle`n</style>`n</head>"
    $finalCardHtml = $styledSheet -replace '<!-- CARDS_PLACEHOLDER -->', ($allSheetsHtml -join "`n")

    $cardHtmlPath = Join-Path $HtmlOutputDir "${SafePlayerName}_Spell-Card-Sheet_${levelLabel}.html"
    $finalCardHtml | Out-File -FilePath $cardHtmlPath -Encoding UTF8

    Invoke-ChromePdf -HtmlPath $cardHtmlPath `
                     -PdfPath  (Join-Path $PdfOutputDir "${SafePlayerName}_Spell-Card-Sheet_${levelLabel}.pdf") `
                     -Label    "Spell Card Sheet — $levelLabel"
}

# ==========================================
# PART 2 — SPELL DESCRIPTIONS
# ==========================================
Write-Host ""
Write-Host "[2/3] Building Spell Descriptions..." -ForegroundColor Cyan

$levelPagesHtml = [System.Collections.Generic.List[string]]::new()

foreach ($levelGroup in $byLevel) {
    $levelNum    = [int]$levelGroup.Name
    $levelSpells = $levelGroup.Group | Sort-Object name
    $headerLabel = if ($levelNum -eq 0) { "Cantrips" } else { "Level $levelNum" }
    $pageTitle   = "$PlayerName `u{2013} $headerLabel ($ClassName)"
    $hexLabel    = if ($levelNum -eq 0) { "C" } else { "$levelNum" }

    $spellEntriesHtml = [System.Collections.Generic.List[string]]::new()

    foreach ($s in $levelSpells) {
        $school    = Get-SchoolName $s.school
        $classes   = ($s.classes -join ", ")
        $levelWord = if ($levelNum -eq 0) { "Cantrip" } else { "Level $levelNum" }
        $subtitle  = "$levelWord $school ($classes)"
        $castTime  = Get-CastingTime $s.time
        $range     = Get-Range       $s.range
        $duration  = Get-Duration    $s.duration
        $bodyHtml  = if ($s.entries) {
            ($s.entries | ForEach-Object { Get-EntryHtml $_ }) -join ""
        } else { "" }

        $spellEntriesHtml.Add(@"
<div class="spell-entry">
  <div class="spell-name">$($s.name)</div>
  <div class="spell-subtitle">$subtitle</div>
  <div class="spell-properties">
    <p class="spell-property"><span class="prop-label">Casting Time:</span> $castTime</p>
    <p class="spell-property"><span class="prop-label">Range:</span> $range</p>
    <p class="spell-property"><span class="prop-label">Duration:</span> $duration</p>
  </div>
  <div class="spell-body">$bodyHtml</div>
  <div class="spell-source">$($s.sourceEdition) &middot; $($s.source)</div>
</div>
"@)
    }

    $spellCount = $levelSpells.Count
    $levelPagesHtml.Add(@"
<div class="level-page">
  <div class="page-header">
    <div class="title-banner">
      <div class="title-text">$pageTitle</div>
    </div>
    <svg class="hex-badge" viewBox="0 0 100 115">
      <polygon points="50,2 98,28 98,87 50,113 2,87 2,28" fill="#ffffff" stroke="#000000" stroke-width="7" />
      <text x="50" y="72" font-size="28" font-weight="bold" font-family="Arial" text-anchor="middle" fill="#000000">$hexLabel</text>
    </svg>
  </div>
  <hr class="header-rule">
  <div class="columns">
    $($spellEntriesHtml -join "`n")
  </div>
  <div class="page-footer">
    <div>$ClassName</div>
    <div class="footer-right">$headerLabel &middot; $spellCount spell$(if ($spellCount -ne 1) { "s" })</div>
  </div>
</div>
"@)
}

$finalDescHtml = $descTemplate -replace '<!-- LEVEL_PAGES_PLACEHOLDER -->', ($levelPagesHtml -join "`n")
$descHtmlPath  = Join-Path $HtmlOutputDir "${SafePlayerName}_Spell-Descriptions.html"
$finalDescHtml | Out-File -FilePath $descHtmlPath -Encoding UTF8

Invoke-ChromePdf -HtmlPath $descHtmlPath `
                 -PdfPath  (Join-Path $PdfOutputDir "${SafePlayerName}_Spell-Descriptions.pdf") `
                 -Label    "Spell Descriptions"

# ==========================================
# PART 3 — BOOK INDEX
# ==========================================
Write-Host ""
Write-Host "[3/3] Building Book Index..." -ForegroundColor Cyan

Invoke-ChromePdf -HtmlPath $BookIndexPath `
                 -PdfPath  (Join-Path $PdfOutputDir "Book-Index.pdf") `
                 -Label    "Book Index"

# ==========================================
# SUMMARY
# ==========================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " SUCCESS! Player spell packet complete." -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host " Player : $PlayerName"
Write-Host " Class  : $ClassName"
Write-Host " Output : $PdfOutputDir"
Write-Host ""
Write-Host " Files generated:" -ForegroundColor Yellow
Write-Host "   ${SafePlayerName}_Spell-Card-Sheet_Cantrip.pdf"
Write-Host "   ${SafePlayerName}_Spell-Card-Sheet_Level-1.pdf  (one file per level)"
Write-Host "   ${SafePlayerName}_Spell-Descriptions.pdf"
Write-Host "   Book-Index.pdf"
Write-Host ""