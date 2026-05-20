# OutOfRange

**A clear, customizable warning the moment your target steps out of range — for any class, any ability, any unit you pick. Now with per-spec profiles.**

Stop hammering an interrupt key while the boss is already past you. Stop wasting a cast because the ally you're hovering ran around a corner. OutOfRange watches one ability's range against one unit (target, mouseover, or focus) and flashes a big readable warning the instant range is broken. The frame disappears the moment you're back in range.

That's the whole addon. One job, done well, no telemetry, no profile sync, no rotation helper, no raid frame, no bloat.

---

## Who it's for

- **Melee DPS, tanks, off-tanks.** Auto-detects a sensible interrupt or main strike for your class so it works out of the box — Pummel, Rebuke, Kick, Crusader Strike, Tiger Palm, Chaos Strike, all of them.
- **Healers.** Set the tracked unit to **Mouseover** and pick a heal spell. Now you know the instant the ally under your cursor is too far away for the cast you're about to start, before you waste the GCD.
- **Ranged DPS and casters.** Pick the spell that defines your effective combat range (Frostbolt, Chaos Bolt, Aimed Shot, Starfire…) and stop overstepping it.
- **Hybrid players.** Tank one fight, DPS the next, heal a dungeon after — each spec keeps its own complete configuration, including tracked spell, warning position, sound preferences, and color. Switch spec and the addon switches with you, no menu-diving required.
- **Anyone learning a new class or spec.** Pick the ability you keep "out of ranging" and turn it into a visible habit.

---

## Features

- **Per-spec profiles.** Every setting is saved independently per specialization — tracked spell, tracked unit, warning text and color, scale, on-screen position, sound preferences, throttle interval, combat-only mode. When you change spec, the addon swaps to that spec's profile automatically. The options panel and minimap tooltip both show which profile is currently active.
- **Auto-detect or hand-pick.** Auto-pick a melee ability for your class, or choose any of your **current spec's** spells from a dropdown that lists each spell's range next to its name. The list always reflects your active spec (off-spec abilities are filtered out) — re-spec mid-session and reopen the dropdown to see the new options.
- **Three units to choose from.** Target, mouseover, or focus. Friendly or hostile, the addon doesn't care — the range check itself decides validity.
- **Customizable warning text and color.** Type any text you like; click the **Color…** button to open a full color picker with wheel, RGB sliders, and hex entry. Live preview while you adjust, Cancel restores cleanly.
- **Configurable size and position.** Slider for scale (50%–300%); unlock the frame to drag it anywhere on screen, then click the X to lock — the options panel reopens automatically so you can keep tweaking.
- **Optional sound.** Off by default. 10 bundled tones to choose from, each routed through a selectable audio channel (SFX / Dialog / Ambient / Music / Master) so it follows the in-game volume slider you're already using.
- **Combat-only mode.** Optionally suppress the warning unless you're actively in combat.
- **Minimap button + addon compartment.** Both include left-click → settings, right-click → toggle on/off, hover for a status tooltip showing the active profile. The minimap button is draggable and uses the same library every other addon does, so it sits alongside them naturally.
- **Slash commands.** `/oor` or `/outofrange` from the keyboard.

---

## Install

**From CurseForge or Wago** (recommended): search for "OutOfRange" and install through the CurseForge or Wago app. Auto-updates from there.

**From source:**

1. Download or clone this repo.
2. Copy the `OutOfRange` folder into `World of Warcraft\_retail_\Interface\AddOns\`. The final path should look like `...\AddOns\OutOfRange\OutOfRange.toc`.
3. Restart WoW or type `/reload`, and make sure **OutOfRange** is enabled on the AddOns screen.

---

## Quick start

1. Install. The defaults work for most melee classes — log in and the addon auto-picks an interrupt or main strike.
2. To pick a specific ability instead, open settings (`/oor` or the minimap button), go to **Trigger Ability**, untick "Auto-detect", and choose from the dropdown.
3. To track a friendly mouseover or focus instead of your target, change the **Track range to** dropdown in the same section.
4. To reposition the warning, scroll to **Appearance** and click **Unlock frame to move**. Drag to taste, click the X on the warning to lock — the options panel pops right back up.
5. Switch spec? The addon switches with you. Configure each spec once and forget about it.

---

## Slash commands

| Command | Effect |
| --- | --- |
| `/oor` | open the options panel |
| `/oor toggle` | enable/disable the addon |
| `/oor sound` | toggle the warning sound |
| `/oor combat` | toggle combat-only mode |
| `/oor unlock` / `/oor lock` | unlock / lock the warning frame position |
| `/oor scale 0.5`–`3` | set the warning size |
| `/oor test` | flash the alert once for placement preview |
| `/oor status` | print what's being tracked and which profile is active |
| `/oor reset` | reset just the active spec's profile to defaults |
| `/oor reset all` | wipe every profile and the minimap state |
| `/oor minimap show` / `hide` / `reset` | minimap button controls |
| `/oor help` | list all commands |

---

## Compatibility

- **WoW Midnight** (patch 12.x). Built for, tested against, and bumped each patch.
- **No required dependencies.** Embeds [LibDBIcon-1.0](https://www.curseforge.com/wow/addons/libdbicon-1-0) (plus LibStub, LibDataBroker-1.1, CallbackHandler-1.0) for the minimap button; these will defer to any newer copy you already have via another addon.
- **No taint.** The addon doesn't hook protected functions or touch combat-locked APIs.
- **Upgrading from a pre-1.10 version?** Your existing settings carry over into your *current* spec's profile automatically — no manual reconfiguration. Other specs start with defaults until you switch to them.

---

## Notes for Midnight

Midnight introduced significant addon API restrictions (the "addon apocalypse" in 12.0.0). This addon stays inside the allowed surface area:

- It only reads units via `UnitExists`, `UnitCanAttack`, `UnitIsDead`, `UnitIsVisible`.
- Range is checked via `C_Spell.IsSpellInRange`, which Blizzard explicitly kept callable.
- The options panel uses the modern `Settings.RegisterCanvasLayoutCategory` API and the modern dropdown menu system (`WowStyle1DropdownTemplate` / `SetupMenu`).
- The ability list is read from the modern `C_SpellBook` API.
- Settings use `SavedVariablesPerCharacter`, so each character has its own configuration (and within that, each spec has its own profile).
- No protected combat decision-making, no automated targeting, no hidden raid debuff scanning.

It should keep working through future 12.x patches without modification.

---

## Feedback and contributions

Found a bug, missing a class ability in auto-detect, or have an idea worth shipping? Open an issue on [GitHub](https://github.com/WowDonf/OutOfRange) or drop a comment on the CurseForge / Wago page. Pull requests welcome.
