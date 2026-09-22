<#
.SYNOPSIS
    Builds a printable D&D 5.5e (2024) Feature Packet for a specific player character.

.DESCRIPTION
    Reads pre-downloaded feature data from master-features.json, master-backgrounds.json,
    and master-feats.json (produced by DownloadRepo-Features.ps1) and generates two
    print-ready PDF outputs:

      1. Feature Card Sheet  — 3x3 grid of poker-sized cards (62mm x 87mm), one per feature.
                               Cards include a title banner, hex badge, action/uses stats,
                               body text (truncated if needed), and a source footer.
                               Laid out on 8.5x11 sheets with crop marks for cutting.

      2. Feature Descriptions — Full-text reference sheet in a two-column letter-page layout.
                                Mirrors the PHB style so players can look up complete feature
                                rules without thumbing through the book.

    The background's granted Origin Feat is automatically looked up in master-feats.json
    and included in both outputs.

    Both outputs are rendered to PDF via Chrome headless and saved to Print_Sheets_PDF\.
    HTML intermediates are preserved in Print_Sheets_HTML\ for inspection or re-rendering.

.PARAMETER ClassName
    The character's class. Must be a valid 2024 PHB class name.

.PARAMETER Species
    The character's species. Must be a valid 2024 PHB species name.

.PARAMETER Background
    The character's background. Must be a valid 2024 PHB background name.

.PARAMETER PlayerName
    Used to name the output files (e.g. WillowLeaf_Feature-Card-Sheet.pdf).
    Defaults to ClassName if not provided.

.PARAMETER MaxLevel
    Filters features to only those available at or below this character level.
    Species and background features are always included (they are level 0).
    Defaults to 20 (all levels).

.EXAMPLE
    .\BuildFeaturePacket.ps1 -ClassName Wizard -Species Elf -Background Noble -PlayerName WillowLeaf -MaxLevel 1

.NOTES
    Requires: Google Chrome (for headless PDF rendering)
    Data:     Run DownloadRepo-Features.ps1 first to populate the Repo\ folder.
    Ruleset:  2024 PHB only (XPHB source). Features from earlier editions are not included.
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        'Barbarian', 'Bard', 'Cleric', 'Druid', 'Fighter',
        'Monk', 'Paladin', 'Ranger', 'Rogue', 'Sorcerer',
        'Warlock', 'Wizard'
    )]
    [string]$ClassName,

    [Parameter(Mandatory = $true)]
    [ValidateSet(
        'Aasimar', 'Dragonborn', 'Dwarf', 'Elf', 'Gnome',
        'Goliath', 'Halfling', 'Human', 'Orc', 'Tiefling'
    )]
    [string]$Species,

    [Parameter(Mandatory = $true)]
    [ValidateSet(
        'Acolyte', 'Artisan', 'Charlatan', 'Criminal', 'Entertainer',
        'Farmer', 'Guard', 'Guide', 'Hermit', 'Merchant', 'Noble',
        'Sage', 'Sailor', 'Scribe', 'Soldier', 'Wayfarer'
    )]
    [string]$Background,

    [string]$PlayerName,
    [int]$MaxLevel = 20,

    [string]$HtmlOutputDir         = (Join-Path $PSScriptRoot "Print_Sheets_HTML"),
    [string]$PdfOutputDir          = (Join-Path $PSScriptRoot "Print_Sheets_PDF"),
    [string]$SheetTemplatePath     = (Join-Path $PSScriptRoot "Shared\Sheet-3x3-Template.html"),
    [string]$CardTemplatePath      = (Join-Path $PSScriptRoot "Features\Feature-Card-Template.html"),
    [string]$DescTemplatePath      = (Join-Path $PSScriptRoot "Shared\Description-Template.html"),
    [string]$MasterFeaturesPath    = (Join-Path $PSScriptRoot "Repo\master-features.json"),
    [string]$ChromeExe             = "C:\Program Files\Google\Chrome\Application\chrome.exe"
)

# Normalize input casing
$ClassName = (Get-Culture).TextInfo.ToTitleCase($ClassName.ToLower())
if (-not $PlayerName) { $PlayerName = $ClassName }
$SafePlayerName = $PlayerName -replace '[\\/:*?"<>|]', ''

# Ensure output directories exist
if (-not (Test-Path $HtmlOutputDir)) { New-Item -ItemType Directory -Path $HtmlOutputDir | Out-Null }
if (-not (Test-Path $PdfOutputDir))  { New-Item -ItemType Directory -Path $PdfOutputDir  | Out-Null }

# Verify Chrome
if (-not (Test-Path $ChromeExe)) {
    $ChromeExe = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
    if (-not (Test-Path $ChromeExe)) {
        Write-Error "Chrome not found. Please verify the ChromeExe path."
        exit 1
    }
}

# Clean old output files
Remove-Item "$HtmlOutputDir\${SafePlayerName}_Feature-Card-Sheet.html"   -ErrorAction SilentlyContinue
Remove-Item "$PdfOutputDir\${SafePlayerName}_Feature-Card-Sheet.pdf"     -ErrorAction SilentlyContinue
Remove-Item "$HtmlOutputDir\${SafePlayerName}_Feature-Descriptions.html" -ErrorAction SilentlyContinue
Remove-Item "$PdfOutputDir\${SafePlayerName}_Feature-Descriptions.pdf"   -ErrorAction SilentlyContinue

# ==========================================
# HELPER: Render PDF via Chrome Headless
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
# LOAD DATA
# ==========================================
$featuresOnly = Get-Content -Path $MasterFeaturesPath -Raw | ConvertFrom-Json

$MasterBackgroundsPath = Join-Path (Split-Path $MasterFeaturesPath) "master-backgrounds.json"
$backgroundsOnly = @()
if (Test-Path $MasterBackgroundsPath) {
    $backgroundsOnly = Get-Content -Path $MasterBackgroundsPath -Raw | ConvertFrom-Json
}

# Load feats table
$MasterFeatsPath = Join-Path (Split-Path $MasterFeaturesPath) "master-feats.json"
$allFeats = @()
if (Test-Path $MasterFeatsPath) {
    $allFeats = Get-Content -Path $MasterFeatsPath -Raw | ConvertFrom-Json
}

$allFeatures = @() + $featuresOnly + $backgroundsOnly

# Filter features for player selection
$filteredFeatures = $allFeatures | Where-Object {
    $f = $_
    $keep = $false

    if ($f.className -eq $ClassName -and $f.level -le $MaxLevel) { $keep = $true }
    if ($Species    -and $f.className -eq $Species    -and $f.level -le $MaxLevel) { $keep = $true }
    if ($Background -and $f.className -eq $Background -and $f.level -le $MaxLevel) { $keep = $true }

    return $keep
}

# Join: find the background's Origin Feat in master-feats.json
# The background body already contains "Origin Feat: <FeatName>" — parse it out
$bgEntry    = $backgroundsOnly | Where-Object { $_.className -eq $Background }
$bgFeatName = ""
if ($bgEntry -and $bgEntry.body -match '<b>Feat::</b>\s*<p>([^<]+)</li>') {
    $bgFeatName = $Matches[1].Trim()
}

$filteredFeats = @()
if ($bgFeatName) {
    $filteredFeats = @($allFeats | Where-Object { $_.name -eq $bgFeatName })
    Write-Host "  Background feat: $bgFeatName" -ForegroundColor Green
} else {
    Write-Host "  No background feat found for: $Background" -ForegroundColor Yellow
}

# Combine features + background feat into one alphabetically sorted content list
$allFilteredContent = @() + $filteredFeatures + $filteredFeats | Sort-Object name

# ==========================================
# PART 1 — FEATURE CARD SHEETS (3x3 Grid)
# ==========================================
Write-Host "`n[1/2] Building Feature Card Sheets..." -ForegroundColor Cyan

$cardTemplate  = Get-Content -Raw -Path $CardTemplatePath  -Encoding UTF8
$sheetTemplate = Get-Content -Raw -Path $SheetTemplatePath -Encoding UTF8

# Extract CSS from card template — injected once into the sheet <head>
$cardStyle = ""
if ($cardTemplate -match '(?s)<style>(.*?)</style>') {
    $cardStyle = $Matches[1]
}

# Extract card markup only — no <html>/<head>/<body> wrapper
$cardMarkup = ""
if ($cardTemplate -match '(?s)<body>\s*(.*?)\s*</body>') {
    $cardMarkup = $Matches[1]
}

$allSheetsHtml = [System.Collections.Generic.List[string]]::new()

# Process cards in batches of 9 (one page per batch)
for ($i = 0; $i -lt $allFilteredContent.Count; $i += 9) {
    $batch     = @($allFilteredContent[$i..[Math]::Min($i + 8, $allFilteredContent.Count - 1)])
    $cellHtmls = [System.Collections.Generic.List[string]]::new()

    foreach ($feature in $batch) {
        $cardHtml = $cardMarkup
        $cardHtml = $cardHtml -replace '\{\{FeatureName\}\}',   $feature.name
        $cardHtml = $cardHtml -replace '\{\{ActionType\}\}',    $feature.actionType
        $cardHtml = $cardHtml -replace '\{\{Usage\}\}',         $feature.usage
        $cardHtml = $cardHtml -replace '\{\{BodyText\}\}',      $feature.cardBody
        $cardHtml = $cardHtml -replace '\{\{Category\}\}',      $feature.category
        $cardHtml = $cardHtml -replace '\{\{ClassName\}\}',     $feature.className
        $cardHtml = $cardHtml -replace '\{\{BadgeCode\}\}',     $feature.badge
        $cardHtml = $cardHtml -replace '\{\{Source\}\}',        $feature.source
        $cardHtml = $cardHtml -replace '\{\{SourceEdition\}\}', $feature.sourceEdition

        $cellHtmls.Add("<div class=`"grid-cell`">$cardHtml</div>")
    }

    # Pad page to exactly 9 grid cells
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

# Inject card styles once into sheet <head>, then insert all page blocks
$styledSheet    = $sheetTemplate -replace '</head>', "<style>`n$cardStyle`n</style>`n</head>"
$finalSheetHtml = $styledSheet -replace '<!-- CARDS_PLACEHOLDER -->', ($allSheetsHtml -join "`n")

$sheetHtmlPath = Join-Path $HtmlOutputDir "${SafePlayerName}_Feature-Card-Sheet.html"
$sheetPdfPath  = Join-Path $PdfOutputDir  "${SafePlayerName}_Feature-Card-Sheet.pdf"

$finalSheetHtml | Out-File -FilePath $sheetHtmlPath -Encoding UTF8
Invoke-ChromePdf -HtmlPath $sheetHtmlPath -PdfPath $sheetPdfPath -Label "Feature Card Sheet"


# ==========================================
# PART 2 — FEATURE DESCRIPTIONS
# ==========================================
Write-Host "`n[2/2] Building Feature Descriptions..." -ForegroundColor Cyan

$descTemplate       = Get-Content -Raw -Path $DescTemplatePath -Encoding UTF8
$featureEntriesHtml = [System.Collections.Generic.List[string]]::new()

foreach ($f in $allFilteredContent) {
    $title    = $f.name
    $badge    = if ($f.badge)    { $f.badge }    else { "TRAIT" }
    $category = if ($f.category) { $f.category } else { "Feature" }
    $bodyHtml = $f.body
    $source   = "$($f.sourceEdition) · $($f.source)"

    # Add prerequisite line for feats that have one
    $prereqLine = ""
    if ($f.prerequisite) {
        $prereqLine = "<div class=`"content-property`"><span class=`"prop-label`">Prerequisite:</span> $($f.prerequisite)</div>"
    }

    $featureEntriesHtml.Add(@"
<div class="content-entry">
  <div class="content-name">$title</div>
  <div class="content-subtitle">$category ($badge)</div>
  $prereqLine
  <div class="content-body">$bodyHtml</div>
  <div class="content-source">$source</div>
</div>
"@)
}

$pageTitle = "$PlayerName – Features & Traits"
$finalDescPageHtml = @"
<div class="level-page">
  <div class="page-header">
    <div class="title-banner">
      <div class="title-text">$pageTitle</div>
    </div>
  </div>
  <hr class="header-rule">
  <div class="columns">
    $($featureEntriesHtml -join "`n")
  </div>
</div>
"@

$finalDescHtml = $descTemplate -replace '<!-- LEVEL_PAGES_PLACEHOLDER -->', $finalDescPageHtml

$descHtmlPath = Join-Path $HtmlOutputDir "${SafePlayerName}_Feature-Descriptions.html"
$descPdfPath  = Join-Path $PdfOutputDir  "${SafePlayerName}_Feature-Descriptions.pdf"

$finalDescHtml | Out-File -FilePath $descHtmlPath -Encoding UTF8
Invoke-ChromePdf -HtmlPath $descHtmlPath -PdfPath $descPdfPath -Label "Feature Descriptions"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " SUCCESS! Feature packet complete." -ForegroundColor Green
Write-Host "  Player     : $PlayerName" -ForegroundColor Green
Write-Host "  Class      : $ClassName" -ForegroundColor Green
Write-Host "  Species    : $Species" -ForegroundColor Green
Write-Host "  Background : $Background (Feat: $(if ($bgFeatName) { $bgFeatName } else { 'none found' }))" -ForegroundColor Green
Write-Host "  Max Level  : $MaxLevel" -ForegroundColor Green
Write-Host "  Output     : $PdfOutputDir" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
