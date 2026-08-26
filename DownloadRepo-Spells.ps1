<#
.SYNOPSIS
    Downloads all official D&D 5e/5.5e spell data from 5etools and merges into a single master JSON.

.DESCRIPTION
    Pulls spell data from both the 2024 (XPHB) and 2014 (PHB, XGE, TCE, etc.) 5etools repositories.
    When a spell exists in both editions, the 2024 (XPHB) version always wins.
    Each spell is tagged with a 'sourceEdition' field ("2024" or "2014") and retains its original
    'source' field (e.g. XPHB, XGE, TCE, PHB).

.NOTES
    Run from the folder where you want the Repo\ subfolder to be created, or adjust $OutputFile below.
#>

# ==========================================
# CONFIGURATION
# ==========================================
$OutputFile      = Join-Path $PSScriptRoot "Repo\master-spells.json"
$Base2024Url     = "https://raw.githubusercontent.com/5etools-mirror-3/5etools-src/main/data"
$Base2014Url     = "https://raw.githubusercontent.com/5etools-mirror-3/5etools-2014-src/main/data"

# All known official spell source files in the 2024 repo.
# XPHB is the 2024 core book; all others are 2014-era supplements hosted alongside it.
# Source: https://5e.tools/data/spells/index.json
$Sources2024 = @{
    "XPHB"      = "spells-xphb.json"      # 2024 Player's Handbook          — 2024 core
    "EFA"        = "spells-efa.json"       # Eberron: Forge of the Artificer — 2024 supplement
}

$Sources2014 = @{
    "PHB"        = "spells-phb.json"       # Player's Handbook (2014)
    "XGE"        = "spells-xge.json"       # Xanathar's Guide to Everything
    "TCE"        = "spells-tce.json"       # Tasha's Cauldron of Everything
    "EGW"        = "spells-egw.json"       # Explorer's Guide to Wildemount
    "GGR"        = "spells-ggr.json"       # Guildmasters' Guide to Ravnica
    "SCC"        = "spells-scc.json"       # Strixhaven: Curriculum of Chaos
    "AAG"        = "spells-aag.json"       # Astral Adventurer's Guide
    "AI"         = "spells-ai.json"        # Acquisitions Incorporated
    "BMT"        = "spells-bmt.json"       # Book of Many Things
    "FTD"        = "spells-ftd.json"       # Fizban's Treasury of Dragons
    "FRHoF"      = "spells-frhof.json"     # Forgotten Realms: Heroes of the Forgotten Kingdoms
    "IDRotF"     = "spells-idrotf.json"    # Icewind Dale: Rime of the Frostmaiden
    "LLK"        = "spells-llk.json"       # Lost Laboratory of Kwalish
    "SatO"       = "spells-sato.json"      # Spelljammer: Adventures in Space
    "AitFR-AVT"  = "spells-aitfr-avt.json" # Adventures in the Forgotten Realms
}

# ==========================================
# HELPER: Download and parse a spell JSON file
# ==========================================
function Get-SpellsFromUrl {
    param(
        [string]$BaseUrl,
        [string]$SourceCode,
        [string]$FileName,
        [string]$Edition
    )

    $url = "$BaseUrl/spells/$FileName"
    Write-Host "  Downloading $SourceCode ($Edition)..." -ForegroundColor Gray

    try {
        $data = Invoke-RestMethod -Uri $url -ErrorAction Stop
    }
    catch {
        Write-Warning "  SKIPPED $SourceCode — could not download from $url`n  Error: $_"
        return @()
    }

    # 5etools spell files use either .spell or .spells as the array key
    $spellArray = if ($data.spell)   { $data.spell }
                  elseif ($data.spells) { $data.spells }
                  else {
                      Write-Warning "  SKIPPED $SourceCode — no 'spell' or 'spells' array found in response."
                      return @()
                  }

    # Tag each spell with edition and normalise the source field
    foreach ($s in $spellArray) {
        # Map internal year labels to display edition labels
    $displayEdition = switch ($Edition) {
        "2024" { "5.5" }
        "2014" { "5.0" }
        default { $Edition }
    }
    $s | Add-Member -NotePropertyName "sourceEdition" -NotePropertyValue $displayEdition -Force
        # Ensure source field is set (some supplemental files omit it on individual entries)
        if (-not $s.source) {
            $s | Add-Member -NotePropertyName "source" -NotePropertyValue $SourceCode -Force
        }
    }

    return $spellArray
}

# ==========================================
# HELPER: Resolve class list from lookup map
# ==========================================
function Get-ClassList {
    param($LookupMap, [string]$SpellSource, [string]$SpellName)

    $srcKey  = $SpellSource.ToLower()
    $nameKey = $SpellName.ToLower()

    $classList = [System.Collections.Generic.List[string]]::new()

    if (-not ($LookupMap.$srcKey -and $LookupMap.$srcKey.$nameKey)) { return $classList.ToArray() }

    $entry = $LookupMap.$srcKey.$nameKey

    # 2024 spells use 'class'; 2014 PHB spells use 'class'; 2014 supplement spells
    # (XGE, TCE, etc.) use 'classVariant'. Some PHB spells have both. Check all.
    foreach ($groupKey in @('class', 'classVariant')) {
        if (-not $entry.$groupKey) { continue }
        foreach ($srcProp in $entry.$groupKey.PSObject.Properties) {
            foreach ($cProp in $srcProp.Value.PSObject.Properties) {
                if (-not $classList.Contains($cProp.Name)) {
                    $classList.Add($cProp.Name)
                }
            }
        }
    }

    return $classList.ToArray()
}

# ==========================================
# ENSURE OUTPUT DIRECTORY EXISTS
# ==========================================
$outputDir = Split-Path $OutputFile -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# ==========================================
# STEP 1: Download class lookup maps
# ==========================================
Write-Host "`n[1/4] Downloading class lookup maps..." -ForegroundColor Cyan

try {
    $lookup2024 = Invoke-RestMethod -Uri "$Base2024Url/generated/gendata-spell-source-lookup.json" -ErrorAction Stop
    Write-Host "  2024 lookup map: OK" -ForegroundColor Gray
}
catch {
    Write-Error "Failed to download 2024 class lookup map: $_"
    exit 1
}

try {
    $lookup2014 = Invoke-RestMethod -Uri "$Base2014Url/generated/gendata-spell-source-lookup.json" -ErrorAction Stop
    Write-Host "  2014 lookup map: OK" -ForegroundColor Gray
}
catch {
    Write-Warning "2014 lookup map unavailable — class lists for 2014 spells may be incomplete."
    $lookup2014 = $null
}

# ==========================================
# STEP 2: Download all 2024 spells (these always win on name conflicts)
# ==========================================
Write-Host "`n[2/4] Downloading 2024 spells..." -ForegroundColor Cyan

# Track 2024 spell names (lowercase) for deduplication
$spellsBy2024Name = @{}
$masterSpells = [System.Collections.Generic.List[PSObject]]::new()

foreach ($entry in $Sources2024.GetEnumerator()) {
    $sourceCode = $entry.Key
    $fileName   = $entry.Value
    $spells     = Get-SpellsFromUrl -BaseUrl $Base2024Url -SourceCode $sourceCode -FileName $fileName -Edition "2024"  # → "5.5"

    foreach ($s in $spells) {
        $classes = Get-ClassList -LookupMap $lookup2024 -SpellSource $s.source -SpellName $s.name
        $s | Add-Member -NotePropertyName "classes" -NotePropertyValue $classes -Force

        $nameKey = $s.name.ToLower()
        $spellsBy2024Name[$nameKey] = $true
        $masterSpells.Add($s)
    }
}

Write-Host "  2024 spells loaded: $($masterSpells.Count)" -ForegroundColor Green

# ==========================================
# STEP 3: Download all 2014 spells, skip any superseded by 2024
# ==========================================
Write-Host "`n[3/4] Downloading 2014 spells..." -ForegroundColor Cyan

$added2014   = 0
$skipped2014 = 0

foreach ($entry in $Sources2014.GetEnumerator()) {
    $sourceCode = $entry.Key
    $fileName   = $entry.Value
    $spells     = Get-SpellsFromUrl -BaseUrl $Base2014Url -SourceCode $sourceCode -FileName $fileName -Edition "2014"  # → "5.0"

    foreach ($s in $spells) {
        $nameKey = $s.name.ToLower()

        # Skip if a 2024 version already exists for this spell name
        if ($spellsBy2024Name.ContainsKey($nameKey)) {
            $skipped2014++
            continue
        }

        # Resolve class list from 2014 lookup (fall back to empty if unavailable)
        $classes = if ($lookup2014) {
            Get-ClassList -LookupMap $lookup2014 -SpellSource $s.source -SpellName $s.name
        } else { @() }

        $s | Add-Member -NotePropertyName "classes" -NotePropertyValue $classes -Force

        # Register this name so duplicates within 2014 sources are also deduplicated
        $spellsBy2024Name[$nameKey] = $true
        $masterSpells.Add($s)
        $added2014++
    }
}

Write-Host "  2014 spells added:   $added2014" -ForegroundColor Green
Write-Host "  2014 spells skipped (superseded by 5.5 version): $skipped2014" -ForegroundColor Yellow

# ==========================================
# STEP 4: Sort and save
# ==========================================
Write-Host "`n[4/5] Saving master spell list..." -ForegroundColor Cyan

$sorted = $masterSpells | Sort-Object { $_.level }, { $_.name }
$sorted | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputFile -Encoding UTF8

Write-Host "`n===========================================" -ForegroundColor Green
Write-Host " SUCCESS! Master spell list saved." -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Green
Write-Host " Total spells : $($sorted.Count)"
Write-Host " Output file  : $OutputFile"
Write-Host ""

# ==========================================
# VERIFICATION SUMMARY
# ==========================================
Write-Host "--- BREAKDOWN BY EDITION ---" -ForegroundColor Yellow
$sorted | Group-Object sourceEdition | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,-4} : {1} spells" -f $_.Name, $_.Count)
}

Write-Host "`n--- BREAKDOWN BY SOURCE ---" -ForegroundColor Yellow
$sorted | Group-Object source | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,-12} : {1} spells" -f $_.Name, $_.Count)
}

Write-Host "`n--- SAMPLE (first 5 spells) ---" -ForegroundColor Yellow
$sorted | Select-Object -First 5 | ForEach-Object {
    [PSCustomObject]@{
        Name    = $_.name
        Level   = $_.level
        Source  = $_.source
        Edition  = $_.sourceEdition
        Classes = ($_.classes -join ", ")
    }
} | Format-Table -AutoSize

# ==========================================
# STEP 5: Generate Book-Index.html
# ==========================================
Write-Host "`n[5/5] Generating Book-Index.html..." -ForegroundColor Cyan

# Full source metadata — all known official sources with title, edition, and type
$allSourceMeta = [ordered]@{
    "XPHB"      = @{ Title = "Player's Handbook (2024)";                          Edition = "5.5"; Type = "Core"       }
    "EFA"        = @{ Title = "Eberron: Forge of the Artificer";                  Edition = "5.5"; Type = "Supplement" }
    "PHB"        = @{ Title = "Player's Handbook (2014)";                         Edition = "5.0"; Type = "Core"       }
    "XGE"        = @{ Title = "Xanathar's Guide to Everything";                   Edition = "5.0"; Type = "Supplement" }
    "TCE"        = @{ Title = "Tasha's Cauldron of Everything";                   Edition = "5.0"; Type = "Supplement" }
    "EGW"        = @{ Title = "Explorer's Guide to Wildemount";                   Edition = "5.0"; Type = "Supplement" }
    "FTD"        = @{ Title = "Fizban's Treasury of Dragons";                     Edition = "5.0"; Type = "Supplement" }
    "GGR"        = @{ Title = "Guildmasters' Guide to Ravnica";                   Edition = "5.0"; Type = "Supplement" }
    "SCC"        = @{ Title = "Strixhaven: A Curriculum of Chaos";                Edition = "5.0"; Type = "Supplement" }
    "AAG"        = @{ Title = "Astral Adventurer's Guide (Spelljammer)";          Edition = "5.0"; Type = "Supplement" }
    "SatO"       = @{ Title = "Spelljammer: Adventures in Space";                 Edition = "5.0"; Type = "Supplement" }
    "BMT"        = @{ Title = "The Book of Many Things";                          Edition = "5.0"; Type = "Supplement" }
    "IDRotF"     = @{ Title = "Icewind Dale: Rime of the Frostmaiden";            Edition = "5.0"; Type = "Adventure"  }
    "AI"         = @{ Title = "Acquisitions Incorporated";                        Edition = "5.0"; Type = "Supplement" }
    "LLK"        = @{ Title = "Lost Laboratory of Kwalish";                       Edition = "5.0"; Type = "Adventure"  }
    "FRHoF"      = @{ Title = "Forgotten Realms: Heroes of the Forgotten Kingdoms"; Edition = "5.0"; Type = "Supplement" }
    "AitFR-AVT"  = @{ Title = "Adventures in the Forgotten Realms: A Verdant Tomb"; Edition = "5.0"; Type = "Adventure"  }
}

# Collect only the sources that actually appear in master-spells.json
$activeSources = $sorted | Group-Object source | Sort-Object Name | Select-Object -ExpandProperty Name

# Build table rows — only for sources present in the downloaded data, in canonical order
$tableRows = [System.Collections.Generic.List[string]]::new()
foreach ($code in $allSourceMeta.Keys) {
    if ($activeSources -notcontains $code) { continue }
    $meta = $allSourceMeta[$code]
    $tableRows.Add("<tr><td>$code</td><td>$($meta.Title)</td><td>$($meta.Edition)</td><td>$($meta.Type)</td></tr>")
}

# Spell count per source for the footer note
$totalSources = $tableRows.Count

# Load template and inject rows and footer values
$bookIndexTemplatePath = Join-Path $PSScriptRoot "Repo\Book-Index-Template.html"
if (-not (Test-Path $bookIndexTemplatePath)) {
    Write-Warning "Book-Index-Template.html not found at $bookIndexTemplatePath — skipping Book-Index generation."
} else {
    $bookIndexHtml = Get-Content -Raw -Path $bookIndexTemplatePath -Encoding UTF8
    $bookIndexHtml = $bookIndexHtml -replace '<!-- TABLE_ROWS_PLACEHOLDER -->', ($tableRows -join "`n        ")
    $bookIndexHtml = $bookIndexHtml -replace '\{\{SourceCount\}\}',   $totalSources
    $bookIndexHtml = $bookIndexHtml -replace '\{\{GeneratedDate\}\}', (Get-Date -Format 'yyyy-MM-dd')

    $bookIndexOutput = Join-Path $outputDir "Book-Index.html"
    $bookIndexHtml | Set-Content -Path $bookIndexOutput -Encoding UTF8
    Write-Host "  Saved: $bookIndexOutput" -ForegroundColor Green
    Write-Host "  Sources included: $totalSources" -ForegroundColor Green
}