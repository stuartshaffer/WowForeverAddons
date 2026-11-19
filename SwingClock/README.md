# SwingClock

Circular clock / pie-chart weapon swing timer for **World of Warcraft: Forever** styled to match the default WoW UI antique-brass & bronze frames.

## Visual Behavior
- **WoW UI Antique-Brass Ring**: Sculpted dual-bevel antique-brass bezel sampled from Blizzard's Portrait, Level badge, and Minimap frames, with top-left catchlights, dark ink outlines, sharp cardinal chisel notches, and a Minimap-style **12 o'clock** arrowhead crest.
- **12 o'clock = Swing Ready**: When your swing reaches 12 o'clock (or while idle), the entire circle turns emerald green and stays green until your next attack fires.
- **Filling (Recovering)**: While a weapon swing is recovering, a slightly opaque yellow pie slice sweeps clockwise from **12 o'clock** all the way around to **12 o'clock** over a warm dark umber dial.
- **Attack Pulse**: Passing **12 o'clock** when an attack fires triggers a subtle emerald-green pulse/glow around the clock face and 12 o'clock crest.
- **Dual-Wield & Ranged Support**:
  - Automatically displays a concentric brass-bordered **inner ring** for Off-Hand swings when dual-wielding.
  - Tracks **Auto Shot** and **Wand** swings on the clock face.
  - Adjusts mid-swing for haste buffs (`Flurry`, `Slice and Dice`, `Bloodlust`, etc.) and player **Parry Haste**.
- **Paladin Active Seal & Unsealed Wrath Echo Tracking (Class-Specific)**:
  - **Active Seal Box (Paladin Only)**: Appears to the **left** of the swing circle (half the diameter of the circle) with a matching antique-brass box border, displaying your currently active Seal icon and remaining seconds underneath.
  - **Unsealed Wrath Echo Box & Side Pips (Paladin + Unsealed Wrath Talent Only)**: Appears to the **right** of the swing circle (same size and antique-brass box border as the Seal box) **only** when you are a Paladin and have the **Unsealed Wrath** (`1310735`) talent taken. Displays the Seal currently storing Echo stacks (`Echo of Righteousness`, `Echo of Command`, `Echo of Fury`, `Echo of Justice`, `Echo of Light`, `Echo of Wisdom`) with **3 circular Minimap-style pips** along its right edge that fill green for each Echo stack (`1..3`) and clear when expended.
- **Hides Default Swing Bar**: Automatically sets `showSwingTimer=0` while enabled (and restores your previous CVar value if turned off).

## Repositioning (Grid & Screen Center Snapping)
Unlocking the clock displays a full-screen alignment grid centered on `(0, 0)` with highlighted horizontal and vertical center axes (`X=0`, `Y=0`). While dragging, the clock magnetically snaps to the screen center axes and the `20px` grid lines (lighting up the snapped center axis in green):
- Type `/sc unlock` (or `/sc move`), **Left-Drag** to move (hold **Shift** for free pixel movement), **Middle-Click** to snap `X = 0` (`Shift+Middle-Click` for `(0, 0)`), then **Right-Click** (or `/sc lock`) to lock.
- Open `/sc` to use **Unlock & Drag**, toggle/cycle **Grid Snap**, or click **Center X=0**.
- Open **Esc -> Edit Mode** (automatically displays the grid and snaps while dragging in Edit Mode).
- Open **Esc -> Options -> AddOns -> SwingClock** for **Unlock & Drag Clock** and **Center Horizontally (X=0)**.

## Install
Put (or copy) the `SwingClock` folder into `_forever_\Interface\AddOns`. Note: when updating `.tga` textures while WoW is open, restart the client so the new textures load cleanly.

## Commands
- `/sc` (or `/swingclock`) — Open/close the SwingClock settings window
- `/sc unlock` — Unlock the clock, show the grid, and drag to reposition
- `/sc lock` — Toggle lock / click-through state
- `/sc center [all]` — Snap horizontally to `X = 0` (`all` centers at `(0, 0)`)
- `/sc snap [off|<8-64>]` — Toggle grid snap or adjust grid spacing in px (default `20`)
- `/sc test` — Simulate single-weapon swings in town
- `/sc test dual` — Simulate dual-wield swings (Main Hand pie + Off-Hand inner ring)
- `/sc size <24-320>` — Set clock diameter in pixels (default `136`)
- `/sc alpha <15-100>` — Set yellow pie opacity % (default `74`)
- `/sc pulse <0-200>` — Set 12 o'clock green pulse strength % (default `100`)
- `/sc show <always|target|combat>` — Change when the clock is visible (default `always`)
- `/sc offhand` — Toggle inner Off-Hand ring
- `/sc ranged` — Toggle Ranged (Auto Shot / Wand) tracking
- `/sc blizzard` — Toggle hiding Blizzard's built-in swing bar (`showSwingTimer`)
- `/sc text` — Toggle optional countdown seconds in the center
- `/sc reset` — Reset position and settings to defaults
