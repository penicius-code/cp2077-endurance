# Endurance

A second, slower reserve on top of stamina, called Oxygen, shown as a bar under Dark Future's Nerve bar, for Cyberpunk 2077. Single-player only.
Version 1.3.1 | For game version 2.5 and Dark Future 3.0 | Status: not run in game yet (no version has a written in-game test record)

> This is an unofficial fan work and is not approved/endorsed by CD PROJEKT RED. No game files are included.

## The problem

Vanilla stamina refills within seconds, so a long sprint, a long climb or a long fight costs nothing that lasts. Dark Future adds needs like thirst and sleep, and some of them cut stamina directly, as a flat penalty.

## What I built

A redscript system (1,191 lines) and a TweakXL file that adds Oxygen, a deeper reserve that runs down with sustained effort and refills slowly. It changes: max stamina and stamina refill when oxygen is low, weapon sway when oxygen is very low, the stamina cost of a few actions, and Dark Future's direct stamina penalties, which now act through oxygen instead.

- **Oxygen bar.** An aqua bar right under Dark Future's Nerve bar; the three need bars move one row down.
- **Capacity.** 100, raised by Body (up to +30 % at Body 20) and lowered by Dark Future's needs: thirst and sleep take up to 30 % each, hunger up to 20 %, never below 45 %. Chest injuries from the Injuries mod lower it further (tier 1 -10 %, tier 2 -20 %, tier 3 -35 %) when that mod is installed.
- **Drain.** 0.3 oxygen per stamina point spent, plus a steady drain while sprinting, crouch-sprinting, climbing or vaulting, swimming fast or carrying a body.
- **Refill.** After a short wait (3 s, 8 s from empty; longer with low Reflexes, low Nerve, thirst or tiredness), fastest at rest, slower walking or running, never while sprinting.
- **Low oxygen.** Below 50 % max stamina and stamina refill shrink; below 25 % recoil, sway and spread grow and the player breathes heavily.
- **Extra stamina costs.** Takedowns and grapples, finishers, grenade throws and taking hits cost stamina.
- Oxygen is not saved: it is full after every load and after a time skip.

## How it works

- A scriptable system samples the player's activity on a timer and updates oxygen, capacity and the stamina factor. Stamina itself stays vanilla; the mod only scales max stamina and refill and adds a few costs.
- Six game methods are wrapped with `@wrapMethod`: takedown, finisher, quick and charged grenade throw states, `StatPoolsManager.ApplyDamage` (hits taken) and `PlayerWeaponHandlingModifiers.UpdateEquippedWeaponsHandling` (sway). The source audit checked all six against the 2.5 game scripts: they match.
- The bar is built with Dark Future's own HUD bar classes and reads Dark Future's need values. The script imports Dark Future's modules directly, so it does not compile without Dark Future.
- The Injuries mod and Mod Settings are compiled in only when present (`@if(ModuleExists(...))`).
- The TweakXL file sets Dark Future's direct stamina penalties (tiredness on max stamina, thirst on stamina refill) to neutral and replaces the descriptions of eight Dark Future status effects with plain text that names the oxygen reserve. It edits 16 existing Dark Future records and adds none.

```text
package/r6/
  scripts/CyberslopEndurance/CyberslopEndurance.reds   oxygen system, bar, settings
  tweaks/zz_CyberslopEndurance/CyberslopEndurance.yaml  Dark Future stamina penalties and effect descriptions
```

The tweak folder name starts with `zz_` so it loads after Dark Future's own tweak files.

## Requirements

| Requirement | Version | Link |
|---|---|---|
| Cyberpunk 2077 | 2.5 | |
| redscript | a build for 2.5 | [Nexus Mods, mod 1511](https://www.nexusmods.com/cyberpunk2077/mods/1511) |
| TweakXL | a build for 2.5 | [Nexus Mods, mod 4197](https://www.nexusmods.com/cyberpunk2077/mods/4197) |
| Dark Future | 3.0 | [Nexus Mods, mod 16300](https://www.nexusmods.com/cyberpunk2077/mods/16300) |
| Mod Settings (optional) | a build for 2.5 | [Nexus Mods, mod 4885](https://www.nexusmods.com/cyberpunk2077/mods/4885) |
| Injuries (optional) | | [Nexus Mods, mod 30508](https://www.nexusmods.com/cyberpunk2077/mods/30508) |

Without Mod Settings the defaults below apply. Requirements are not bundled. Install them first.

## Install

1. Install the requirements above.
2. Copy the contents of `package/` into the game folder, so that `r6\scripts\CyberslopEndurance\CyberslopEndurance.reds` exists.
3. Start the game and load a save: the aqua Oxygen bar shows under Dark Future's Nerve bar.

## Uninstall / roll back

1. Close the game.
2. Delete:
   - `r6\scripts\CyberslopEndurance\`
   - `r6\tweaks\zz_CyberslopEndurance\`
3. Saves are not affected: oxygen is not stored in the save.
4. Requirements are left alone. To restore an unmodified game, verify the game files in your launcher.

## Configuration

Mod Settings > Cyberslop Endurance:

| Category | Setting | Default | Range |
|---|---|---|---|
| Oxygen | Enabled | on | |
| Oxygen | Oxygen per stamina point | 0.3 | 0 to 1 |
| Oxygen | Sprint drain (% per second) | 0.8 | 0 to 5 |
| Oxygen | Crouch sprint drain (% per second) | 0.6 | 0 to 5 |
| Oxygen | Climb / vault / ladder drain (% per second) | 1.2 | 0 to 5 |
| Oxygen | Fast swimming drain (% per second) | 1.0 | 0 to 5 |
| Oxygen | Fast swimming from (m/s) | 2.0 | 0.5 to 6 |
| Oxygen | Carrying a body drain (% per second) | 0.8 | 0 to 5 |
| Oxygen | Refill at rest (% per second) | 1.5 | 0 to 10 |
| Oxygen | Refill walking (% per second) | 0.8 | 0 to 10 |
| Oxygen | Refill running (% per second) | 0.3 | 0 to 10 |
| Oxygen | Rest speed (m/s) | 0.5 | 0.1 to 3 |
| Oxygen | Walk speed (m/s) | 3.0 | 1 to 8 |
| Oxygen | Refill wait after light effort (s) | 3.0 | 0 to 20 |
| Oxygen | Refill wait from empty (s) | 8.0 | 0 to 30 |
| Well-being (Dark Future) | Thirst: capacity lost at 0 (%) | 30 | 0 to 60 |
| Well-being (Dark Future) | Sleep: capacity lost at 0 (%) | 30 | 0 to 60 |
| Well-being (Dark Future) | Hunger: capacity lost at 0 (%) | 20 | 0 to 60 |
| Low oxygen | Stamina at 0 oxygen (x) | 0.5 | 0.2 to 1 |
| Low oxygen | Weapon sway at 0 oxygen (x) | 1.4 | 1 to 2.5 |
| Low oxygen | Heavy breathing | on | |
| Stamina costs | Takedown / grapple (% stamina) | 15 | 0 to 50 |
| Stamina costs | Finisher (% stamina) | 10 | 0 to 50 |
| Stamina costs | Grenade throw (% stamina) | 4 | 0 to 50 |
| Stamina costs | Taking a melee hit (% stamina) | 6 | 0 to 50 |
| Stamina costs | Taking a strong melee hit (% stamina) | 10 | 0 to 50 |
| Stamina costs | Taking a bullet or blast (% stamina) | 3 | 0 to 50 |
| Debug | Log | on | |
| Debug | Verbose log | off | |

"Enabled" off keeps oxygen full and removes the stamina shrink and the extra costs. The TweakXL file still keeps Dark Future's direct stamina penalties neutral, so remove the mod to get them back.

## Status

| Version | Game | Result |
|---|---|---|
| 1.0.0 to 1.2.0 | 2.31 | No written in-game test record. |
| 1.3.0 | 2.5 | Port to 2.5 and Dark Future 3.0. No written in-game test record. |
| 1.3.1 | 2.5 | Not run in game yet. |

The source audit checked all six wrap targets against the 2.5 game scripts.

## Compatibility

| Item | Status | Notes |
|---|---|---|
| Dark Future 3.0 | required | The bar uses its HUD classes and its need values. Its direct stamina penalties are set to neutral. Other Dark Future versions were not checked; 1.3.0 had to follow a renamed HUD slot in 3.0. |
| Injuries | optional | Chest injuries lower the capacity. |
| Other mods that change stamina costs | not tested | Stamina stays vanilla and keeps other mods' costs; this mod scales max stamina and refill on top. |

## Known issues

- Logging is on by default on purpose: "Log" writes `[Endurance]` event lines to the CET game log, buffered and written every 5 s, at most 60 lines per write, plus a summary every 10 s while oxygen moves. Turn it off in Mod Settings if you do not need it.
- No version has been played in a written test.

## Engineering notes

There is no written in-game test, so these notes describe fixes and design decisions that the code records.

**Stuck heavy breathing after a load (1.3.1).** The heavy-breathing effect the mod applies below 25 % oxygen is a status effect the game saves. A save made under 25 % loaded with the sway still on, while oxygen itself (not saved) was full again. The mod now removes that effect in the first 5 seconds after a load unless the mod applied it itself.

**Port to 2.5 and Dark Future 3.0 (1.3.0).** Dark Future 3.0 renamed its HUD slot and dropped the lock icon fields of its bar setup. Game 2.5 passes the left-hand weapon to the weapon handling update and puts the same handling modifiers on both weapons, so the low-oxygen sway is now applied to both hands.

**No double counting.** Thirst and tiredness used to cut stamina directly in Dark Future. Here they shrink the oxygen capacity, and low oxygen shrinks stamina, so the TweakXL file sets Dark Future's direct stamina penalties to neutral.

**A log that cannot flood.** The event log is buffered and capped at 60 lines per write; dropped lines are counted and reported.

**Rollback.** Each version was kept in its own release folder. For a user: delete two folders.

## Changelog

See [CHANGELOG.md](CHANGELOG.md). Latest: 1.3.1 (2026-11-23): a save made under 25 % oxygen no longer loads with the heavy-breathing sway stuck on.

## Credits and licence

Built on Dark Future, whose modules and HUD classes the script uses. Runs on redscript and TweakXL. None of them are included here.

MIT, see [LICENSE](LICENSE). The licence covers my code only. Game names and trademarks belong to their owners.

Built with AI assistance (Claude); designed, tested and maintained by me.
