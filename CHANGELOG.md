# Changelog

## 1.10.2

- The options panel now reopens automatically when you click the **X** to lock the warning frame after using "Unlock frame to move." Saves a click and a slash command. The slash `/oor unlock` path still leaves the panel closed when you lock, since typing a slash command doesn't imply you want options to pop up.

## 1.10.1

- **Fixed:** Spam error `OutOfRangeFrame:SetPoint(): Usage:` on login, introduced by the 1.10.0 per-spec refactor. `ApplySettings` was reading the warning frame's position from the top-level `OutOfRangeDB` table (which now only holds shared keys) instead of the active spec's profile. Now reads from the profile correctly.

## 1.10.0

- **New: per-spec profiles.** Every setting (tracked spell, tracked unit, warning text/color/size/position, sound preferences, throttle, combat-only mode) is now saved independently per specialization. When you change spec, the addon swaps to that spec's profile automatically — no profile-switching action required from you. The minimap button position remains shared across specs.
  - The options panel shows the currently active profile at the top, and refreshes live when you change spec while the panel is open.
  - **Migration:** your existing settings from 1.9.x are carried over into your *current* spec's profile on first load. Other specs you have learned will start with defaults the first time you switch to them.
- **New:** `Reset this profile to defaults` button (in Tools) resets only the active spec's profile. `Reset ALL profiles` next to it wipes every profile plus the minimap state. Slash equivalents: `/oor reset` and `/oor reset all`.
- `/oor status` now includes the active profile name.
- Minimap tooltip and addon-compartment tooltip both show the active profile.

## 1.9.2

- **Fixed:** The "Tracked skill" dropdown was including spells from inactive specializations and abilities the active spec doesn't have. It now filters to active-spec spells only, by skipping off-spec skill-book sections (`offSpecID > 0` and `shouldHide`) and verifying each remaining spell with `IsPlayerSpell`.

> Note: the 1.8.1 changelog claimed this was already handled, but that change only added refresh-on-open. Spec-aware *filtering* didn't actually arrive until this version.

## 1.9.1

- The "Color..." button next to the warning text now opens Blizzard's standard `ColorPickerFrame` (color wheel, RGB sliders, and hex entry), replacing the custom 8-swatch palette from 1.9.0. Dragging any slider gives live preview; Cancel restores the previous color cleanly.

## 1.9.0

- **New: color picker for the warning text.** A "Color..." button next to the warning-text field opens a small popup with an 8-color palette chosen for colorblind accessibility. Clicking a swatch re-colors the warning text in one click, replacing any existing color codes. The text field still accepts manual `|cAARRGGBB...|r` codes if you want a custom color.

## 1.8.2

- **Removed:** "Too close" alerts (the orange warning for abilities with a minimum range, added in 1.8.0). The underlying range API doesn't distinguish too-close from too-far reliably, and the `CheckInteractDistance` probe used to disambiguate produced too many false readings. The unit-selection feature (target / mouseover / focus) from 1.8.0 is retained.
- Cleaned up the now-unused `tooCloseText` saved-variable key on load.

## 1.8.1

- **Fixed:** The "Tracked skill" dropdown was empty the first time the options panel was opened, only populating after closing and reopening. The spell list now refreshes every time the dropdown is opened, so it's always current — including across spec changes and spells learned mid-session.

## 1.8.0

- **New: "too close" alerts.** For abilities with a minimum range (Hunter Aimed Shot, mage / warlock ranged casts, etc.), the addon now shows a separate orange warning when your target is within the minimum range, distinct from the normal red "out of range" warning. The warning text and color are configurable.
- **New: pick which unit to track.** A "Track range to" dropdown in the Trigger Ability section now lets you choose between Target, Mouseover, and Focus. Healers can now use OutOfRange to monitor range to a friendly mouseover or focus target. The unit-validity check no longer enforces hostility, so friendly-unit tracking works naturally.
- New slash command `/oor test close` previews the too-close alert.
- `/oor status` now shows the currently tracked unit.

## 1.7.1

- **Fixed:** Resetting all settings (via the options panel button or `/oor reset`) no longer leaves the "Show minimap button" checkbox out of sync with the actual button visibility.
- **Migrated:** If you used the addon's hand-rolled minimap button in pre-1.7.0 builds, your saved button angle now carries over to the new LibDBIcon-based button on first load.

## 1.7.0

- Switched the minimap button to LibDBIcon, the library used by virtually every other addon's minimap button. Your button now lines up correctly with other addons' buttons regardless of minimap size or shape (round / square / partial-corner).
- The pixel-tuning slash command `/oor minimap nudge` is gone; it isn't needed anymore.

## 1.6.0

- Added a minimap button. Left-click opens options, right-click toggles the addon on/off, drag to reposition.
- Added a "Show minimap button" option to the General section.

## 1.5.x

- Bundled custom OGG warning sounds, accessible from a "Sound" dropdown. The "Volume" dropdown chooses which audio channel slider controls how loud the sound plays.
- Added integration with the addon compartment (the menu next to the minimap).
- The unlocked alert frame now has an X-close button in its top-right corner; one-click locking, no slash command needed.
- Bundled a custom red-crosshair logo as the addon icon.

## 1.0.0

Initial release.

- Flashes a warning whenever your current target is out of range of a tracked ability.
- Auto-detects a melee ability for your class, or pick a specific spell from the dropdown to track any range.
- Configurable sound, scale, throttle interval, position, and warning text.
- Slash commands: `/oor` and `/outofrange`.
- Settings panel under Game Menu → Options → AddOns.
