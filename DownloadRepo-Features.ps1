<#
.SYNOPSIS
    Downloads 5etools data for Classes, Subclasses, Species, and Backgrounds,
    strictly filtering input to pull ONLY 2024 ruleset content,
    and builds a clean master-features.json in the Repo folder.
#>

$RepoDir = Join-Path $PSScriptRoot "Repo"
if (-not (Test-Path $RepoDir)) { New-Item -ItemType Directory -Path $RepoDir | Out-Null }

$MasterFeaturesPath = Join-Path $RepoDir "master-features.json"
$Base2024Url        = "https://raw.githubusercontent.com/5etools-mirror-3/5etools-src/main/data"

# Whitelist for 2024 Rulebook Sources (XPHB = 2024 Player's Handbook)
$Allowed2024Sources = @("XPHB", "DMG24", "MM24", "2024")

# ==========================================
# CARD BODY CALIBRATION
# Based on Feature-Card-Template.html at 7.2pt Arial.
# If you change card size or font, adjust these values.
#   CardBodyMaxChars  : plain-text character count above which truncation triggers
#   CardBodyCutChars  : plain-text characters to keep before appending the suffix
# ==========================================
$CardBodyMaxChars = 800
$CardBodyCutChars = 560

# Convert 5etools inline tags to display text using 5etools rendering semantics.
function ConvertFrom-5eToolsInlineTags {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    return [regex]::Replace(
        $Text,
        '\{@(?<tag>\w+)\s+(?<content>[^{}]+)\}',
        {
            param($match)

            $tag = $match.Groups['tag'].Value
            $parts = $match.Groups['content'].Value -split '\|'

            switch ($tag) {
                # 5etools: NAME | SOURCE | DISPLAY
                { $_ -in @(
                    'action',
                    'condition',
                    'creature',
                    'feat',
                    'item',
                    'itemMastery',
                    'itemProperty',
                    'sense',
                    'skill',
                    'spell',
                    'status',
                    'table',
                    'variantrule'
                ) } {
                    if ($parts.Count -ge 3 -and $parts[2]) { return $parts[2] }
                    return $parts[0]
                }

                # 5etools dice/damage: ROLL | DISPLAY
                { $_ -in @('damage', 'dice') } {
                    if ($parts.Count -ge 2 -and $parts[1]) { return $parts[1] }
                    return ($parts[0] -replace ';', '/')
                }

                # 5etools DC tags include the "DC" label in displayed text.
                'dc' {
                    if ($parts.Count -ge 2 -and $parts[1]) { return "DC $($parts[1])" }
                    return "DC $($parts[0])"
                }

                # Tags whose first field is their human-readable text.
                { $_ -in @('filter', '5etools', 'book', 'i') } {
                    return $parts[0]
                }

                # Preserve readable text if a new/unknown 5etools tag appears.
                default {
                    return $parts[0]
                }
            }
        }
    )
}

# Helper to flatten 5etools entry trees into clean HTML
function Get-EntryHtml ($entry) {
    if (-not $entry) { return "" }

    # If it's a simple string, convert internal 5etools inline tags
    if ($entry -is [string]) {
        $clean = ConvertFrom-5eToolsInlineTags $entry
        return "<p>$clean</p>"
    }

    # If it's a complex object/hashtable
    if ($entry.psobject) {
        $html = ""

        # Header/Name of sub-entry if present
        if ($entry.name) {
            $html += "<b>$($entry.name):</b> "
        }

        # If entry is a list type
        if ($entry.type -eq "list" -and $entry.items) {
            $html += "<ul>"
            foreach ($item in $entry.items) {
                $itemText = Get-EntryHtml $item
                # Strip wrapping <p> tags for inline list items
                $itemText = $itemText -replace '^<p>|<\/p>$', ''
                $html += "<li>$itemText</li>"
            }
            $html += "</ul>"
            return $html
        }

        # Recursive parsing for nested entries
        if ($entry.entries) {
            $html += ($entry.entries | ForEach-Object { Get-EntryHtml $_ }) -join ""
        }

        # Handles entries structured as item/entry pairs
        if ($entry.entry) {
            $html += Get-EntryHtml $entry.entry
        }

        return $html
    }

    return ""
}

# ==========================================
# HELPER: Compute and attach cardBody to a feature object
# Uses plain-text character count (same approach as the spell pipeline).
# HTML tags are stripped for measurement only — the HTML is preserved in the output.
# ==========================================
function Set-CardBody {
    param([PSObject]$Feature)

    $rawBody = $Feature.body
    if ($rawBody) {
        $plainText = $rawBody -replace '<[^>]+>', ''

        if ($plainText.Length -gt $CardBodyMaxChars) {
            # Strip newlines from a LOCAL copy only — purely for walk accuracy
            # $Feature.body and the JSON are never touched
            $walkable  = $rawBody -replace '`r`n|`n|`r', ''

            $charCount = 0
            $inTag     = $false
            $truncated = ""
            foreach ($char in $walkable.ToCharArray()) {
                if ($char -eq '<') { $inTag = $true }
                if (-not $inTag)   { $charCount++ }
                $truncated += $char
                if ($char -eq '>') { $inTag = $false }
                if ($charCount -ge $CardBodyCutChars) { break }
            }

            $lastSpace = $truncated.LastIndexOf(" ")
            if ($lastSpace -gt 0) { $truncated = $truncated.Substring(0, $lastSpace) }

            $Feature | Add-Member -NotePropertyName "cardBody" `
                -NotePropertyValue "$truncated... <i>(See Feature Descriptions sheet)</i>" -Force
        } else {
            $Feature | Add-Member -NotePropertyName "cardBody" -NotePropertyValue $rawBody -Force
        }
    } else {
        $Feature | Add-Member -NotePropertyName "cardBody" -NotePropertyValue "" -Force
    }
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Updating 2024 Features & Traits Data" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$featuresList = [System.Collections.Generic.List[PSObject]]::new()

# ==========================================
# [1/4] CLASS & SUBCLASS FEATURES (2024 ONLY)
# ==========================================

Write-Host "`n[1/4] Querying 2024 Classes & Subclasses..." -ForegroundColor Yellow

$classIndexUrl = "$Base2024Url/class/index.json"
try {
    $classIndex = Invoke-RestMethod -Uri $classIndexUrl -ErrorAction Stop

    $classFiles = @()
    foreach ($prop in $classIndex.psobject.Properties) {
        $val = $prop.Value
        if ($val -is [string] -and $val.EndsWith(".json") -and $val -notin $classFiles) {
            $classFiles += $val
        }
    }

    foreach ($cFile in $classFiles) {
        $cUrl = "$Base2024Url/class/$cFile"
        Write-Host " -> Downloading class file: $cFile ... " -NoNewline

        try {
            $cData = Invoke-RestMethod -Uri $cUrl -ErrorAction Stop
            Write-Host "OK" -ForegroundColor Green

            # Class Features
            if ($cData.classFeature) {
                foreach ($cf in $cData.classFeature) {
                    if (-not $cf.entries) { continue }
                    if (-not $cf.source -or $cf.source -notin $Allowed2024Sources) { continue }
                    if ($cf.isReprinted -eq $true) { continue }

                    $bodyHtml = ($cf.entries | ForEach-Object { Get-EntryHtml $_ }) -join ""
                    if ([string]::IsNullOrWhiteSpace($bodyHtml)) { continue }

                    $cName = $cf.className
                    $badge = if ($cName.Length -ge 3) { $cName.Substring(0,3).ToUpper() } else { "CLS" }

                    $featuresList.Add([PSCustomObject]@{
                        name          = $cf.name
                        badge         = $badge
                        category      = "Class Feature"
                        source        = "$cName Level $($cf.level)"
                        level         = $cf.level
                        actionType    = if ($cf.header) { "Action" } else { "Passive" }
                        usage         = "At Will"
                        body          = $bodyHtml
                        className     = $cName
                        sourceEdition = "2024 Edition"
                    })
                }
            }

            # Subclass Features
            if ($cData.subclassFeature) {
                foreach ($sf in $cData.subclassFeature) {
                    if (-not $sf.entries) { continue }
                    if (-not $sf.source -or $sf.source -notin $Allowed2024Sources) { continue }
                    if ($sf.isReprinted -eq $true) { continue }

                    $bodyHtml = ($sf.entries | ForEach-Object { Get-EntryHtml $_ }) -join ""
                    if ([string]::IsNullOrWhiteSpace($bodyHtml)) { continue }

                    $cName = $sf.className
                    $badge = if ($cName.Length -ge 3) { $cName.Substring(0,3).ToUpper() } else { "SUB" }

                    $featuresList.Add([PSCustomObject]@{
                        name          = $sf.name
                        badge         = $badge
                        category      = "Subclass ($($sf.subclassShortName))"
                        source        = "$($sf.subclassShortName) Level $($sf.level)"
                        level         = $sf.level
                        actionType    = "Feature"
                        usage         = "At Will"
                        body          = $bodyHtml
                        className     = $cName
                        sourceEdition = "2024 Edition"
                    })
                }
            }
        } catch {
            Write-Host "FAILED" -ForegroundColor Red
        }
    }
} catch {
    Write-Warning "Could not retrieve class index."
}

# ==========================================
# 2. SPECIES / RACIAL TRAITS (2024 ONLY)
# ==========================================

Write-Host "`n[2/4] Querying 2024 Species & Traits..." -ForegroundColor Yellow

$raceIndexUrl = "$Base2024Url/race/index.json"
$raceFiles = @()

try {
    $raceIndex = Invoke-RestMethod -Uri $raceIndexUrl -ErrorAction SilentlyContinue
    if ($raceIndex) {
        foreach ($prop in $raceIndex.psobject.Properties) {
            $val = $prop.Value
            if ($val -is [string] -and $val.EndsWith(".json") -and $val -notin $raceFiles) {
                $raceFiles += $val
            }
        }
    }
} catch { }

if ($raceFiles.Count -eq 0) { $raceFiles = @("races.json") }

foreach ($rFile in $raceFiles) {
    $rUrl = if ($rFile -eq "races.json") { "$Base2024Url/races.json" } else { "$Base2024Url/race/$rFile" }
    Write-Host " -> Downloading species file: $rFile ... " -NoNewline

    try {
        $rData = Invoke-RestMethod -Uri $rUrl -ErrorAction Stop
        Write-Host "OK" -ForegroundColor Green

        if ($rData.race) {
            foreach ($r in $rData.race) {
                if (-not $r.entries) { continue }
                if (-not $r.source -or $r.source -notin $Allowed2024Sources) { continue }

                foreach ($entry in $r.entries) {
                    if ($entry.name -and $entry.entries) {
                        $bodyHtml = ($entry.entries | ForEach-Object { Get-EntryHtml $_ }) -join ""
                        if ([string]::IsNullOrWhiteSpace($bodyHtml)) { continue }

                        $raceName = $r.name
                        $badge = if ($raceName.Length -ge 3) { $raceName.Substring(0,3).ToUpper() } else { "SPE" }

                        $featuresList.Add([PSCustomObject]@{
                            name          = $entry.name
                            badge         = $badge
                            category      = "Species Trait"
                            source        = $raceName
                            level         = 0
                            actionType    = "Trait"
                            usage         = "At Will"
                            body          = $bodyHtml
                            className     = $raceName
                            sourceEdition = "2024 Edition"
                        })
                    }
                }
            }
        }
    } catch {
        Write-Host "FAILED" -ForegroundColor Red
    }
}

# ==========================================
# [3/4] Querying 2024 Backgrounds
# ==========================================
Write-Host "`n[3/4] Querying 2024 Backgrounds..." -ForegroundColor Yellow
$bgUrl = "$Base2024Url/backgrounds.json"
Write-Host " -> Downloading backgrounds file: backgrounds.json ... " -NoNewline

$backgroundsList = [System.Collections.Generic.List[PSObject]]::new()

try {
    $bgData = Invoke-RestMethod -Uri $bgUrl -ErrorAction Stop
    Write-Host "OK" -ForegroundColor Green

    if ($bgData.background) {
        foreach ($bg in $bgData.background) {
            # Source validation against your expanded allowed sources
            if (-not $bg.source -or $bg.source -notin $Allowed2024Sources) { continue }

            $bgName   = $bg.name
            $bodyHtml = ""

            # Attempt parsing via Get-EntryHtml
            if ($bg.entries) {
                try {
                    $bodyHtml = ($bg.entries | ForEach-Object { Get-EntryHtml $_ }) -join ""
                } catch {
                    $bodyHtml = ""
                }

                # Fallback if Get-EntryHtml returns blank/whitespace
                if ([string]::IsNullOrWhiteSpace($bodyHtml)) {
                    $bodyHtml = ($bg.entries | Out-String).Trim()
                }
            }

            # Extract origin feats referenced in 5etools JSON array
            if ($bg.feats) {
                $featNames = @()
                foreach ($f in $bg.feats) {
                    if ($f -is [string]) {
                        $fClean = ConvertFrom-5eToolsInlineTags $f
                        $featNames += $fClean
                    } elseif ($f.psobject.Properties['feat']) {
                        $fClean = ConvertFrom-5eToolsInlineTags $f.feat
                        $featNames += $fClean
                    }
                }
                if ($featNames.Count -gt 0) {
                    $bodyHtml += "<p><b>Origin Feat:</b> $($featNames -join ', ')</p>"
                }
            }

            # Standard placeholder if no text content was found
            if ([string]::IsNullOrWhiteSpace($bodyHtml)) {
                $bodyHtml = "<p>Standard 2024 Background options and traits.</p>"
            }

            $backgroundsList.Add([PSCustomObject]@{
                name          = "$bgName"
                badge         = "BKG"
                category      = "Background"
                source        = "$bgName Background"
                level         = 0
                actionType    = "Background"
                usage         = "Passive"
                body          = $bodyHtml
                className     = $bgName
                sourceEdition = "2024 Edition"
            })
        }
    }

    # Attach cardBody to Backgrounds
    foreach ($bg in $backgroundsList) { Set-CardBody -Feature $bg }

    # Save directly to master-backgrounds.json
    $MasterBackgroundsPath = Join-Path (Split-Path $MasterFeaturesPath) "master-backgrounds.json"

    $backgroundsList | Group-Object name | ForEach-Object { $_.Group[0] } |
        ConvertTo-Json -Depth 10 | Set-Content -Path $MasterBackgroundsPath -Encoding UTF8

    Write-Host " Saved $($backgroundsList.Count) backgrounds to master-backgrounds.json" -ForegroundColor Green

} catch {
    Write-Host "FAILED ($($_.Exception.Message))" -ForegroundColor Red
}

# ==========================================
# [4/4] Querying 2024 Feats
# ==========================================
Write-Host "`n[4/4] Querying 2024 Feats..." -ForegroundColor Yellow
$featsUrl = "$Base2024Url/feats.json"
Write-Host " -> Downloading feats file: feats.json ... " -NoNewline

$featsList = [System.Collections.Generic.List[PSObject]]::new()

$featCategoryMap = @{
    "O"    = "Origin Feat"
    "G"    = "General Feat"
    "EB"   = "Epic Boon"
    "FS"   = "Fighting Style"
    "FS:P" = "Fighting Style"
    "FS:R" = "Fighting Style"
}

try {
    $featsData = Invoke-RestMethod -Uri $featsUrl -ErrorAction Stop
    Write-Host "OK" -ForegroundColor Green

    if ($featsData.feat) {
        foreach ($feat in $featsData.feat) {
            if (-not $feat.source -or $feat.source -notin $Allowed2024Sources) { continue }
            if ($feat.reprintedAs) { continue }
            if (-not $feat.entries) { continue }

            $bodyHtml = ($feat.entries | ForEach-Object { Get-EntryHtml $_ }) -join ""
            if ([string]::IsNullOrWhiteSpace($bodyHtml)) { continue }

            $catCode = if ($feat.category) { $feat.category } else { "G" }
            $catName = if ($featCategoryMap[$catCode]) { $featCategoryMap[$catCode] } else { "Feat" }

            # Prerequisite as a readable string
            $prereqText = ""
            if ($feat.prerequisite) {
                $parts = @()
                foreach ($p in $feat.prerequisite) {
                    if ($p.level)        { $parts += "Level $($p.level.level)" }
                    if ($p.ability)      { foreach ($a in $p.ability) { foreach ($k in $a.psobject.Properties) { $parts += "$($k.Name.ToUpper()) $($k.Value)+" } } }
                    if ($p.spellcasting) { $parts += "Spellcasting" }
                    if ($p.feat)         { $parts += "Feat: $($p.feat -join ', ')" }
                    if ($p.other)        { $parts += $p.other }
                }
                $prereqText = $parts -join "; "
            }

            $featsList.Add([PSCustomObject]@{
                name          = $feat.name
                badge         = "FET"
                category      = $catName
                featCategory  = $catCode
                source        = "XPHB p.$($feat.page)"
                level         = 0
                prerequisite  = $prereqText
                actionType    = "Feat"
                usage         = "Passive"
                body          = $bodyHtml
                className     = ""
                sourceEdition = "2024 Edition"
            })
        }
    }

    # Attach cardBody to feats
    foreach ($feat in $featsList) { Set-CardBody -Feature $feat }

    # Save to master-feats.json
    $MasterFeatsPath = Join-Path (Split-Path $MasterFeaturesPath) "master-feats.json"
    $featsList | ConvertTo-Json -Depth 10 | Set-Content -Path $MasterFeatsPath -Encoding UTF8

    Write-Host " Saved $($featsList.Count) feats to master-feats.json" -ForegroundColor Green
    Write-Host "  Origin: $(($featsList | Where-Object { $_.featCategory -eq 'O' }).Count)  General: $(($featsList | Where-Object { $_.featCategory -eq 'G' }).Count)  Epic Boon: $(($featsList | Where-Object { $_.featCategory -eq 'EB' }).Count)  Fighting Style: $(($featsList | Where-Object { $_.featCategory -in @('FS','FS:P','FS:R') }).Count)" -ForegroundColor Green

} catch {
    Write-Host "FAILED ($($_.Exception.Message))" -ForegroundColor Red
}

# Deduplicate Class Features by Name + Class/Species/Background
$uniqueFeatures = $featuresList | Group-Object { "$($_.name)_$($_.className)" } | ForEach-Object { $_.Group[0] }

# Attach cardBody to Class & Subclass Features
foreach ($feature in $uniqueFeatures) { Set-CardBody -Feature $feature }

# Save clean 2024 dataset
$uniqueFeatures | ConvertTo-Json -Depth 10 | Set-Content -Path $MasterFeaturesPath -Encoding UTF8

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " SUCCESS! Updated master-features.json (2024 Only)" -ForegroundColor Green
Write-Host " Total 2024 features/traits/backgrounds stored: $($uniqueFeatures.Count)" -ForegroundColor Green
Write-Host " Saved to: $MasterFeaturesPath"
Write-Host "==========================================" -ForegroundColor Green
