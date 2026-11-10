<#
.SYNOPSIS
    Classifies feature Action metadata from raw 5etools entries (2024 rules).
.DESCRIPTION
    Returns Action, Bonus Action, Reaction, No Action, Passive, Varies, or "".
    A blank is intentional: uncertain action economy must never become a
    misleading default. This does not interpret usage/recharge restrictions.

    The entry text is examined BEFORE converting 5etools markup to HTML.
    References to actions do not by themselves mean that the feature uses one.
#>

function Get-FeatureActionStrings {
    param([object]$Entry)

    if ($null -eq $Entry) { return }
    if ($Entry -is [string]) {
        Write-Output $Entry
        return
    }

    if ($Entry -is [System.Collections.IEnumerable]) {
        foreach ($item in $Entry) { Get-FeatureActionStrings -Entry $item }
        return
    }

    # Ignore names, captions, tables and refClassFeature/refSubclassFeature
    # references. Those are not activation instructions for this feature.
    foreach ($field in @('entries', 'entry', 'items')) {
        $property = $Entry.PSObject.Properties[$field]
        if ($null -ne $property) {
            Get-FeatureActionStrings -Entry $property.Value
        }
    }
}

function Get-FeatureActionType {
    param(
        [object]$Entries,
        [string]$Name,
        [string]$Owner = "",
        [string]$Source = "",
        [string]$Kind = ""
    )

    # A background record is a bundle of character-creation benefits; its
    # Origin Feat receives an independently classified feature card.
    if ($Kind -eq 'Background') { return "" }

    # Reviewed XPHB exceptions. Key includes source and owner so an unrelated
    # feature with the same name in another source is not silently relabelled.
    $overrides = @{
        'XPHB|Rogue|Sneak Attack'         = 'No Action'
        'XPHB|Fighter|Action Surge'       = 'No Action'
        'XPHB|Cleric|Channel Divinity'   = 'Varies'
        'XPHB|Paladin|Channel Divinity'  = 'Varies'
        'XPHB|Monk|Martial Arts'         = 'Varies'
        'XPHB|Bard|Agile Strikes'        = 'Varies'
        'XPHB|Goliath|Giant Ancestry'    = 'Varies'
        'XPHB|Ranger|Primal Companion'   = 'Varies'
    }
    $overrideKey = "$Source|$Owner|$Name"
    if ($overrides.ContainsKey($overrideKey)) {
        return $overrides[$overrideKey]
    }

    # A spellcasting-granting feature has no single casting time. The spell
    # cards, not this feature's action cell, carry each spell's precise time.
    if ($Name -in @('Spellcasting', 'Pact Magic')) { return 'Varies' }

    $parts = @(Get-FeatureActionStrings -Entry $Entries)
    $raw = $parts -join ' '
    if ([string]::IsNullOrWhiteSpace($raw)) { return "" }

    # Match what the character DOES, not bare mentions of those terms.
    # "The target can take a Bonus Action" and "the ally uses its Reaction"
    # must not describe the feature owner's action economy.
    $bonusAction = [regex]::IsMatch($raw,
        '(?i)\bas\s+(?:an?\s+|your\s+)\{@variantrule Bonus Action\|[^}]+\}|\byou\s+(?:can\s+)?(?:take|use|spend|expend)\s+(?:an?\s+|your\s+)\{@variantrule Bonus Action\|[^}]+\}')
    $reaction = [regex]::IsMatch($raw,
        '(?i)\bas\s+(?:an?\s+|your\s+)\{@variantrule Reaction\|[^}]+\}|\byou\s+(?:can\s+)?(?:take|use|spend|expend)\s+(?:an?\s+|your\s+)\{@variantrule Reaction\|[^}]+\}')
    $action = [regex]::IsMatch($raw,
        '(?i)\bas\s+(?:an?\s+|your\s+)\{@action (?:Magic|Utilize|Search|Study|Influence|Help)\|[^}]+\}\s+action\b|\byou\s+(?:can\s+)?take\s+(?:an?\s+|the\s+)\{@action (?:Magic|Utilize|Search|Study|Influence|Help)\|[^}]+\}\s+action\b|\bas an? action\b')

    # Attack replacements are part of the Attack action, not another action.
    # "Action" is the available card value; the body explains replacement.
    $attackReplacement = [regex]::IsMatch($raw,
        '(?i)\{@action Attack\|[^}]+\}\s+action[^.]{0,160}\breplace\s+(?:(?:one|two|any)\s+of\s+|an?\s+)?(?:your\s+)?attacks?\b')
    if ($attackReplacement) { $action = $true }

    $explicit = @()
    if ($action)      { $explicit += 'Action' }
    if ($bonusAction) { $explicit += 'Bonus Action' }
    if ($reaction)    { $explicit += 'Reaction' }
    if ($explicit.Count -gt 1) { return 'Varies' }
    if ($explicit.Count -eq 1) { return $explicit[0] }

    # Clear optional riders triggered by an existing event do not consume
    # another action. Never infer this from a bare "you can" statement.
    # Spellcasting references and unspecified actions remain unclassified.
    if ($raw -notmatch '(?i)\byou can cast\b') {
        foreach ($part in $parts) {
            $plainPart = [regex]::Replace($part, '\{@[^}]+\}', 'RULE')
            $sentences = $plainPart -split '(?<=[.!?])\s+(?=[A-Z])'
            foreach ($sentence in $sentences) {
                if ($sentence.Length -gt 300) { continue }
                $hasTrigger = $sentence -match '(?i)^\s*(?:when(?:ever)?\b|once\s+(?:per|on|each)\b|immediately after\b|at the start of\b|if you\s+(?:fail|succeed|hit|miss|drop|roll|take|deal|start)\b|on your turn\b)'
                $hasOptionalEffect = $sentence -match '(?i)\byou can\s+(?:reroll|replace|expend|spend|deal|impose|regain|give|turn|reduce|move|roll|add|make|cause|force|drop|end|swap|teleport|treat|forgo|remove|apply|restore|decide)\b'
                $isLevelOrRest = $sentence -match '(?i)^\s*when(?:ever)? you (?:reach|gain|finish)\b'
                if ($hasTrigger -and $hasOptionalEffect -and -not $isLevelOrRest) {
                    return 'No Action'
                }
            }
        }
    }

    # Passive is a positive classification for standing benefits, not a
    # catch-all for entries with no recognized activation tag.
    $plain = [regex]::Replace($raw, '\{@[^}]+\}', 'RULE')
    $standingBenefit = $plain -match '(?i)^\s*(?:you (?:have|gain|know|learn|are|don.t|do not|no longer|also have|can see|can move|can speak|become)\b|your\b|while\b|your training\b)'
    $possibleActivation = $plain -match '(?i)\byou can\s+(?:take|use|cast|spend|expend|activate|choose to|invoke|attempt|make|turn|cause|force|restore|regain|give|deal|impose)\b|\byou (?:may|can)\s+(?:choose|decide)\b'
    if ($standingBenefit -and -not $possibleActivation) {
        return 'Passive'
    }

    # The remaining records need manual review, not a made-up action cost.
    return ""
}
