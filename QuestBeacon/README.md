# QuestBeacon

Shows quest `!` (available) and `?` (turn-in) icons on NPC nameplates. Nameplates can be drawn even when the unit is behind a wall, so the icons show up through walls and terrain.

## How it works
- Sets these CVars (`/qb cvars` restores your old values): `nameplateShowAll=1`, `nameplateShowFriendlyNPCs=1`, `nameplateOccludedAlphaMult=1`, and `nameplateMaxDistance` raised to at least 41.
- Hides the regular friendly-NPC nameplate (name and health bar) so only the icon shows. Turn this off with `/qb plates`.
- Quest data comes from:
  - **Questie** (if installed): full database of quest starters and enders.
  - **Learned cache**: every NPC you talk to is recorded, saved account-wide in `QuestBeaconLearned`.

Without Questie, an NPC only gets an icon after you've talked to it once.

## Install
Put (or junction) the `QuestBeacon` folder into `_classic_beta_\Interface\AddOns`.

## Commands
`/qb` lists all commands. `/qb target` prints debug info for your current target.

## Limitations
- Friendly nameplates are restricted inside instances, so expect no icons in dungeons.
- Quest objects (chests, wanted posters) don't have nameplates, so they get no icon.
