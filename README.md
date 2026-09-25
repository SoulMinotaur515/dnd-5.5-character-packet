# D&D 5.5e Character Packet

Printable **D&D 5.5e (2024)** feature cards, spell cards, and reference sheets for player character binders.

Designed for **new players** who want all their character information in one place without thumbing through the Player's Handbook mid-session. Cards are sized to fit standard **9-pocket trading card binder pages**.

---

## What It Produces

### Feature Packet
- **Feature Card Sheet** — 3×3 grid of poker-sized cards (one per feature), printed on letter paper with crop marks for cutting. Each card shows the feature name, a class/species badge, action type, usage, and body text.
- **Feature Descriptions** — Two-column reference sheet with full feature text, mirroring the PHB layout. Includes class features, species traits, background entry, and the background's granted Origin Feat.

### Spell Packet
- **Spell Card Sheets** — One 3×3 sheet per spell level (Cantrips, Level 1, etc.), with range, duration, casting time, and description on each card.
- **Spell Descriptions** — Full spell text grouped by level in a two-column reference layout.
- **Book Index** — Source book abbreviation reference sheet.

---

## Prerequisites

- **Windows** with PowerShell
- **Google Chrome** (used for headless PDF rendering)
- Internet access (scripts download data from the [5etools mirror](https://github.com/5etools-mirror-3/5etools-src) on first run)

---

## Setup

Clone the repo:
```powershell
git clone https://github.com/SoulMinotaur515/dnd-5.5-character-packet.git
cd dnd-5.5-character-packet
```

Download the rules data (run once, or whenever you want to refresh):
```powershell
.\DownloadRepo-Features.ps1
.\DownloadRepo-Spells.ps1
```

This populates the `Repo\` folder with:
- `master-features.json` — class and subclass features, species traits
- `master-backgrounds.json` — background definitions
- `master-feats.json` — all 2024 feats (Origin, General, Epic Boon, Fighting Style)
- `master-spells.json` — merged 5.5e/5e spell list, preferring 5.5e versions when duplicates exist

---

## Usage

### Feature Packet
```powershell
.\BuildFeaturePacket.ps1 -ClassName Wizard -Species Elf -Background Noble -PlayerName Slingblade -MaxLevel 1
```

**Parameters:**
| Parameter | Required | Description |
|---|---|---|
| `-ClassName` | Yes | Character class (validated against 2024 PHB classes) |
| `-Species` | Yes | Character species (validated against 2024 PHB species) |
| `-Background` | Yes | Character background (validated against 2024 PHB backgrounds) |
| `-PlayerName` | No | Used to name output files. Defaults to ClassName. |
| `-MaxLevel` | No | Filters features to this level and below. Defaults to 20. |

### Spell Packet
```powershell
.\BuildSpellPacket.ps1 -ClassName Wizard -Levels 0,1 -PlayerName Slingblade
```

**Parameters:**
| Parameter | Required | Description |
|---|---|---|
| `-ClassName` | Yes | Character class |
| `-Levels` | No | Spell levels to include (e.g. `0,1,2`). Defaults to all levels. |
| `-PlayerName` | No | Used to name output files. Defaults to ClassName. |

---

## Output

All files are saved to:
- `Print_Sheets_HTML\` — HTML intermediates (useful for browser preview)
- `Print_Sheets_PDF\` — Final print-ready PDFs

These folders are excluded from the repo and recreated at runtime.

---

## Valid Parameter Values

**Classes:** Barbarian, Bard, Cleric, Druid, Fighter, Monk, Paladin, Ranger, Rogue, Sorcerer, Warlock, Wizard

**Species:** Aasimar, Dragonborn, Dwarf, Elf, Gnome, Goliath, Halfling, Human, Orc, Tiefling

**Backgrounds:** Acolyte, Artisan, Charlatan, Criminal, Entertainer, Farmer, Guard, Guide, Hermit, Merchant, Noble, Sage, Sailor, Scribe, Soldier, Wayfarer

---

## Ruleset

Feature data — classes, subclasses, species traits, backgrounds, and feats — is limited to the **2024 / D&D 5.5e ruleset**.

Spell data is broader. `DownloadRepo-Spells.ps1` pulls supported spells from both **5.5e/2024** and **5e/2014** sources. When a spell exists in both editions, the 5.5e/2024 version takes precedence and the older version is omitted.

Spell cards retain their source and edition information. See `Shared\Book-Index.html` for source abbreviations.

---

## License

MIT — see [LICENSE](LICENSE) for details.

Data is sourced from the [5etools mirror](https://github.com/5etools-mirror-3/5etools-src) and is subject to its own licensing terms.