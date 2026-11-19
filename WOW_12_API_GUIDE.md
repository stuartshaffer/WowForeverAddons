# WoW Forever (Interface `16001` / Patch 12.0+ *Midnight* Engine) Addon API Guide

This document summarizes the **Patch 12.0+ (*Midnight*)** / **WoW: Forever (`Interface: 16001`)** addon architecture, Secret Values restrictions, and the modern C++-delegated UI APIs verified in this workspace.

---

## 1. Core Architectural Shift: "Secret Values" & Taint Rules

In Patch 12.0+ / WoW Forever, Blizzard restricts Lua addons from reading, comparing, or branching on live combat telemetry so addons cannot automate combat decisions:

- **What is Secret in Combat:**
  - `C_UnitAuras` aura payloads (`GetPlayerAuraBySpellID`, `GetAuraDataBySpellName`, `GetAuraDataByIndex`, `GetAuraApplicationDisplayCount`) when `C_Secrets.ShouldAurasBeSecret()` is true or during combat (`DenyTaintedAccessWhenAurasAreSecret`).
  - Certain unit stats/combat values (`UnitHealth`, `UnitPower`, `UnitAttackSpeed`, `UnitRangedDamage`, etc. depending on context).
  - Secret values **cannot** be used in arithmetic (`+`, `-`, `*`, `/`), comparisons (`<`, `>`, `==`), or table indexing — doing so throws errors like `attempt to compare local '...' (a secret value)` or taints execution.
- **How to Guard:**
  ```lua
  local function IsSecret(v)
      return issecretvalue and issecretvalue(v) or false
  end
  ```
  Also check `issecrettable(t)` / `HasSecretValues()` before inspecting returned tables, and `C_Secrets.ShouldAurasBeSecret()` before calling `C_UnitAuras` lookups.
- **What Triggers UI Locks (`ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN`):**
  - Registering `COMBAT_LOG_EVENT_UNFILTERED` (`CombatLogGetCurrentEventInfo` is Blizzard-UI-only in 12.0+).
  - Hooking/writing into shared protected namespaces like `C_SpellBook` (`hooksecurefunc(C_SpellBook, "CastSpellBookItem", ...)`), `UseAction`, or `CastSpellByName`.
  - Calling `C_UnitAuras` lookup APIs during combat when auras are secret.
  - Modifying protected frames or CVars (`SetCVar`) while `InCombatLockdown()` is true.

---

## 2. Native Combat-Safe Aura Rendering: `AuraContainer`

Instead of reading buff state in Lua during combat or guessing from combat events, **delegate aura rendering to Blizzard's C++ UI** using `AuraContainer`.

### Availability Check
```lua
local function HasNativeAuraContainer()
    return CustomAuraContainerAuraProcessingPolicy ~= nil and C_AuraContainerUtil ~= nil
end
```

### Building an `AuraContainer` (Out of Combat Only)
> **Rule:** `AuraContainer` creation, `AddAuraSlot`, and rebuilding must happen **out of combat** (`not InCombatLockdown()`). Once built, Blizzard owns the generated slot buttons ("forbidden objects") — **do not** call `Show()`, `Hide()`, or restyle those buttons directly from Lua. To show/hide the display in combat, call `SetAlpha(0|1)` on your own plain wrapper `Frame` that parents the `AuraContainer`.

```lua
local wrap = CreateFrame("Frame", nil, parentFrame)
wrap:SetAllPoints(parentFrame)

local c = CreateFrame("AuraContainer", nil, wrap, "CustomAuraContainerTemplate")
c:SetEnabled(false)
c:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
c:SetPoint("TOPLEFT", parentFrame, "TOPLEFT")
c:SetUnit("player")

c:AddAuraSlot("MySlot", "HELPFUL", {
    candidateFilters = { includeSpellIDs = { [20918] = true, ... } },
    initializeFrame = function(button)
        button:EnableMouse(false)
        button:ClearAllPoints()
        button:SetAllPoints(parentFrame)

        -- 1. Icon Texture
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(parentFrame)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button:SetIcon(icon)

        -- 2. Cooldown Swipe (optional)
        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd:SetReverse(true)
        button:SetDurationCooldown(cd)

        -- 3. Duration Text (real-time countdown in combat)
        local timerFS = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        timerFS:SetPoint("TOP", parentFrame, "BOTTOM", 0, -3)
        button:SetDurationText(timerFS, { textFormatter = myTimerFormatter })

        -- 4. Stack Count / Pips (real-time stack display in combat)
        local stackFS = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        stackFS:SetPoint("CENTER", pipFrame, "CENTER", 0, 0)
        button:SetApplicationCount(stackFS, { formatter = myPipFormatter })
    end,
})

c:SetAuraSlotEnabled("MySlot", true)
c:SetEnabled(true)
```

### Supported `AuraContainer` Slot Bindings (Observed on Forever `16001`)
- `button:SetIcon(texture)` — Blizzard sets/clears the matching aura's icon texture automatically.
- `button:SetDurationCooldown(cooldown)` — Drives a `Cooldown` frame swipe automatically.
- `button:SetDurationText(fontString, options)` — Drives a countdown `FontString` with optional `textFormatter` and `textColor` curve.
- `button:SetApplicationCount(fontString, options)` — Drives stack count text or inline `|T...|t` pip textures via `formatter`.
- `button:SetApplicationBar(statusBar, { maxApplications = 3, minApplications = ... })` — Drives a `StatusBar` fill by stack count (check `pcall` as `minApplications` may vary by build).
- `button:SetDurationBar(statusBar, {})` — Drives a `StatusBar` by remaining aura duration (if supported by the build; wrap in `pcall`).

### Per-Element Tip (`|T...|t` Alignment)
- Consecutive `|T...|t` tokens on one line advance the text cursor slightly past the texture width, and multi-line `\n` strings depend on font line-height metrics.
- For pixel-exact discrete indicators (like 3 separate pip orbs), create **one `AuraContainer` per pip** anchored `CENTER` to each pip frame with a single `|T...|t` at `offsetX = 0, offsetY = 0` and a threshold formatter (`{ threshold = 0, format = "" }, { threshold = i, format = dot }`).

---

## 3. Formatting & Curve Utilities (`C_StringUtil`, `C_CurveUtil`)

Because Lua cannot format or color-branch on secret numbers directly, pass declarative formatters and curves to Blizzard's C++ widgets:

### `C_StringUtil.CreateNumericRuleFormatter()`
Creates a rule-based formatter evaluated in C++ against secret durations or application counts:
```lua
local up = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up
local fmt = C_StringUtil.CreateNumericRuleFormatter()
fmt:SetBreakpoints({
    { threshold = 0,  format = "%ds",      step = 1, rounding = up },
    { threshold = 60, format = "%d:%02d",  step = 1, rounding = up,
      components = { { div = 60 }, { mod = 60 } } },
})
```
For stack pips (`0..3`):
```lua
fmt:SetBreakpoints({
    { threshold = 0, format = "" },
    { threshold = 1, format = "|TInterface\\AddOns\\...\\CircleDisc:12:12:0:0:64:64:0:64:0:64:56:235:87|t" },
})
```

### `C_CurveUtil.CreateColorCurve()`
Maps a secret remaining duration (or value) to colors in C++ (e.g., turning countdown text orange in the last 5 seconds):
```lua
local curve = C_CurveUtil.CreateColorCurve()
curve:SetType(Enum.LuaCurveType.Step)
curve:AddPoint(0, CreateColor(1, 0.5, 0.1, 1))
curve:AddPoint(5.001, CreateColor(1, 1, 1, 1))
-- Pass via SetDurationText options:
-- textColor = { curve = curve, property = Enum.DurationTextBindingProperty.RemainingDuration }
```

---

## 4. Opaque `DurationObject` Pipeline (`Cooldown` & `StatusBar`)

When displaying spell cooldowns or unit aura/cast durations outside `AuraContainer`, 12.0+ provides opaque `Duration` handles that Lua passes straight to widgets without reading numbers:

- **Providers:**
  - `C_Spell.GetSpellCooldownDuration(spellID)` -> returns opaque `durationObj`
  - `C_UnitAuras.GetAuraDuration(unit, auraInstanceID)` -> returns opaque `durationObj`
- **Consumers (Sinks):**
  - `cooldownFrame:SetCooldownFromDurationObject(durationObj)`
  - `statusBar:SetTimerDuration(durationObj [, direction])`
- **Other Safe Visual Sinks:**
  - `FontString:SetText(secretValue)` (display-only; do not concatenate or parse in Lua)
  - `StatusBar:SetValue(secretValue)`

---

## 5. Passive Non-Secret Events & Talent Detection on Forever (`16001`)

- **Swing Detection:**
  - `PLAYER_SWING` is native on WoW Forever (`pcall(frame.RegisterEvent, frame, "PLAYER_SWING")`) and is preferred over `COMBAT_LOG_EVENT_UNFILTERED`.
- **Spell Casts:**
  - `UNIT_SPELLCAST_SENT` and `UNIT_SPELLCAST_SUCCEEDED` are passive events. Note that procs (such as Seal of Command proc `20424`) also fire `UNIT_SPELLCAST_SUCCEEDED` on `"player"`.
- **Combat Text / Avoids:**
  - `UNIT_COMBAT(unit, action)` fires for `"player"` and `"target"` (`"WOUND"`, `"PARRY"`, `"MISS"`, `"DODGE"`, etc.), though always guard with `IsSecret(unit) or IsSecret(action)`.
  - `WoWCombatLog-*.txt` (via `/combatlog`) still works on disk for post-combat debugging, but is buffered until `/combatlog` is toggled off and cannot be read by Lua addons.
- **Talents (`C_Traits` vs `C_SpellBook`):**
  - Some custom Forever talents exist in `SkillLineAbility.db2` as passive spellbook entries even when untaken, causing `C_SpellBook.IsSpellInSpellBook` / `IsSpellKnown` to return `true`.
  - Always inspect the active `C_Traits` config (`C_ClassTalents.GetActiveConfigID()`, `C_Traits.GetConfigInfo`, `C_Traits.GetTreeNodes`, `C_Traits.GetNodeInfo`, `C_Traits.GetEntryInfo`, `C_Traits.GetDefinitionInfo`) and verify `nodeInfo.ranksPurchased > 0` (or `currentRank > 0`).
