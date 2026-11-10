<#
Run locally in PowerShell:
    pwsh -NoProfile -File .\Tests\Test-FeatureAction.ps1
No network access is required.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Features/FeatureAction.ps1')

$cases = @(
    @{ name='Cunning Action'; owner='Rogue'; expected='Bonus Action'; body='On your turn, you can take Dash, Disengage, or Hide as a {@variantrule Bonus Action|XPHB}.' }
    @{ name='Uncanny Dodge'; owner='Rogue'; expected='Reaction'; body='When you are hit, you can take a {@variantrule Reaction|XPHB} to halve damage.' }
    @{ name='Sneak Attack'; owner='Rogue'; expected='No Action'; body='Once per turn, you can deal extra damage to a creature you hit.' }
    @{ name='Action Surge'; owner='Fighter'; expected='No Action'; body='On your turn, you can take one additional action.' }
    @{ name='Weapon Mastery'; owner='Rogue'; expected='Passive'; body='Your training with weapons allows you to use their mastery properties.' }
    @{ name='Breath Weapon'; owner='Dragonborn'; expected='Action'; body='When you take the {@action Attack|XPHB} action on your turn, you can replace one of your attacks with a breath weapon.' }
    @{ name='Draconic Flight'; owner='Dragonborn'; expected='Bonus Action'; body='As a {@variantrule Bonus Action|XPHB}, you manifest wings. You can retract them (no action required).' }
    @{ name='Abjure Foes'; owner='Paladin'; expected='Action'; body='As a {@action Magic|XPHB} action, you affect enemies. Those enemies can move, take an action, or take a {@variantrule Bonus Action|XPHB}.' }
    @{ name='Mantle of Inspiration'; owner='Bard'; expected='Bonus Action'; body='As a {@variantrule Bonus Action|XPHB}, you empower allies. Each ally can use its {@variantrule Reaction|XPHB} to move.' }
    @{ name="Nature's Sanctuary"; owner='Druid'; expected='Varies'; body='As a {@action Magic|XPHB} action, you create a sanctuary. As a {@variantrule Bonus Action|XPHB}, you move it.' }
    @{ name='Giant Ancestry'; owner='Goliath'; expected='Varies'; body='Choose an ancestral boon.' }
    @{ name='Channel Divinity'; owner='Cleric'; expected='Varies'; body='Choose a Channel Divinity effect.' }
    @{ name='Extra Attack'; owner='Fighter'; expected=''; body='You can attack twice whenever you take the {@action Attack|XPHB} action.' }
    @{ name='Unknown New Feature'; owner='Unknown'; expected=''; body='Ancient magic gives you unusual powers.' }
    @{ name='Fear Effect'; owner='Unknown'; expected=''; body='Affected enemies may take a {@variantrule Bonus Action|XPHB} while afraid.' }
    @{ name='Cunning Action'; owner='Rogue'; expected=''; body='A different edition has no recognized activation.'; source='DIFFERENT' }
    @{ name='Noble'; owner='Noble'; expected=''; kind='Background'; body='A character-creation background.' }
)
$failed = 0
foreach ($c in $cases) {
    $source = if ($c.source) { $c.source } else { 'XPHB' }
    $kind = if ($c.kind) { $c.kind } else { 'Class Feature' }
    $actual = Get-FeatureActionType -Entries @($c.body) -Name $c.name -Owner $c.owner -Source $source -Kind $kind
    if ($actual -cne $c.expected) {
        Write-Host "FAIL $($c.owner)/$($c.name): expected '$($c.expected)', got '$actual'" -ForegroundColor Red
        $failed++
    }
}
if ($failed -gt 0) { throw "$failed Action metadata test(s) failed." }
Write-Host "PASS $($cases.Count) Action metadata cases." -ForegroundColor Green
