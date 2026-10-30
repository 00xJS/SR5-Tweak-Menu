# SR5 Tweak Menu

The SR Tweak Menu idea (an in-game cheat menu, first for Saints Row 1 on
Saints Reborn, then Saints Row 2) for **Saints Row (2022)** on PC, the
Epic build, DirectX 12.

Work in progress: this first version is built on the game's own 43 cheats.

## Requirements

- Saints Row (2022), Epic Games Store, started with **DirectX 12**
  (`SaintsRow_DX12.exe`). The DirectX 11 and Vulkan executables aren't
  supported yet: with them the menu stays off and the game runs as normal.
- To build it: Visual Studio 2022 with **Desktop development with C++**.

## Build and install

```bat
host\build.bat
install.bat
```

`install.bat` takes the game's `sr5` folder as an argument if the game isn't
in Epic's default folder. It puts:

- `dinput8.dll` (the host) next to `SaintsRow_DX12.exe`.
- the menu in `sr5\TweakMenu\SRTweakMenu\`. An existing `mod.ini` is kept.

To uninstall, delete `sr5\dinput8.dll` and the `sr5\TweakMenu` folder.

## Controls

| | Keyboard | Controller |
|---|---|---|
| Open / close | F5 | hold RB, press D-pad Down |
| Move | Up / Down | D-pad Up / Down |
| Pick a choice | Left / Right | D-pad Left / Right |
| Select | Enter | A |
| Change tab | PgUp / PgDn | LB / RB |
| Close | Backspace | B |

## What's in it

| Tab | |
|---|---|
| Player | God mode (the game's own health floor, not its cheat), health x2 to x10, refill health; run speed, air control, swim speed, your gravity; swap your D-pad emotes, play or stop an emote; summon a homie; wingsuit boosts (to unlimited), boost power, top speed, glide (floaty, level, climb); the game's cheats: invincibility, give cash, max level, Super Saints, Milk Bones, pratfall, Heaven Bound |
| Weapons | Magazine (x2, x5, No reload: 999, launchers too), infinite ammo, fire rate (up to x8), full auto for single-shot guns (mouse or RT), damage (x2 to x10 for your weapons; one-hit kill for every gun), reload speed, perfect aim, no warm-up, no overheat, range, knockback, golden gun, max every weapon's upgrades, back to normal |
| Vehicles | Spawn any of the game's 90 ready-to-drive vehicles next to you, engine power, top speed, repair, keep repaired, drop a car, infinite boost, infinite mass, no traffic laws, monster-truck, luxury and mascot traffic |
| Teleport | The game's 44 fast travel points, save this spot, go to a saved place, delete it, go up (10 m to 3000 m), where am I |
| World | Spawn any character or a crowd of them, weather, time of day, freeze clock, clock speed, pause world, never wanted, low gravity, angry pedestrians, raise or clear notoriety (police, Idols, Marshal, Los Panteros), the custom difficulty sliders |
| Visual | Screen filter (black & white, retro, night vision, old-timey, vapor, western, steamboat), field of view, camera shake, looping shake, camera bobbing, photo mode (free camera), hide HUD |
| Settings | Skip cutscene, pause/resume cutscene, load last save, tutorial popups, keep my save clean, menu opacity, what's on, turn every cheat off, everything back to normal, forget saved tweaks, close menu |

Weapon, player and menu settings are kept for next time as you change them
(`sr5\TweakMenu\saved_tweaks.txt`); saved places are in
`sr5\TweakMenu\saved_places.txt`. Rows marked experimental in their help
line still need a test in play.

Weapon tweaks change the game's own weapon data, shared with everyone who
carries that weapon: fire rate, magazines and one-hit kill apply to enemies'
guns too (x2 to x10 damage doesn't). Pair them with God mode.

Rows marked `*` are the game's "spicy" cheats. In the game, using one
marks your save as cheated and pauses achievements. With **Settings > Keep my
save clean** (on by default) the menu lets them run without marking the
save: achievements pause only while a spicy cheat is on. Nothing outside the
game's cheats (god mode, weapons, teleport) touches that at all.

While the menu is open, its keys (arrows, Enter, Backspace, PgUp, PgDn) and
the controller's buttons don't reach the game; the sticks still do.

Every setting (key, position, size, opacity, keep save clean) is in
`sr5\TweakMenu\SRTweakMenu\mod.ini`. The log is `sr5\TweakMenu\wml.log`.

## How it works

**The host (`host/host.c`, built as `dinput8.dll`)**

- **Loading.** The game imports one function from `dinput8.dll`, so Windows
  loads the host from the game folder. Calls go on to a copy of the system
  DLL (`TweakMenu\dinput8_system.dll`): the Epic overlay hooks any
  `dinput8.dll`'s `DirectInput8Create` and would send the call back here.
- **Frames.** The game's main loop calls one function three times an
  iteration on the main thread; the host detours it and runs the menu's
  Lua 5.4 on the first call, about 60 times a second.
- **The game's Lua.** The game has one Lua 5.1 state, its interface's.
  `wml.game(code)` loads and runs code in it with the game's own
  `lua_load` and `lua_pcall` and returns the results. The game's Lua has
  no string, table or math library and a small memory pool.

**The menu (`SRTweakMenu/`)**

| File | What it is |
|---|---|
| `main.lua` | Runs the menu every frame; the live probe |
| `menu.lua` | Tabs, rows, input |
| `cheats.lua` | The game's cheats: the list, their state, switching them, keeping the save clean |
| `weapons.lua` | Weapon tweaks on the game's weapon data (fields, property lists, defaults) |
| `player.lua` | Health (god mode, multiplier), position, teleport, saved places |
| `tweaks.lua` | Settings kept for next time |
| `world.lua` | The clock (freeze, speed) and pausing the world |
| `wingsuit.lua` | Wingsuit tweaks (its data and your live copy) |
| `vdata.lua` | Shared: field addresses in the game's reflection data |
| `gameui.lua` | Draws the menu with the game's interface (vint text objects) |
| `luadump.lua` | Development: reads a game Lua function's constants from memory |

The `wml` table the Lua sees has the same shape as the SR1 menu's host:
`log`, `setting`, `read_*`/`write_*` (64-bit addresses),
`key_down`, `key_pressed`, `on_frame`, `pad`, plus `game(code)`,
`call(addr, ...)`, `buffer`, `read_string` and `base` (the executable's
load address).

## Testing

- **Live probe.** Set `dev_probe = true` in the installed `mod.ini`. While the
  game runs, anything written to `sr5\TweakMenu\probe_in.lua` is run in the
  menu's Lua (with `game` and `dump` at hand), and what it prints goes to
  `sr5\TweakMenu\probe_out.txt`.
- **Research.** `research/` holds what was found in the game (addresses,
  the game's Lua globals, its interface functions) and `tools/` the Python
  scripts used to find it (they read `SaintsRow_DX12.exe` and the running
  game; `pip install pefile capstone numpy`).

## Credits

SR Tweak Menu by 00xJS and itsMJQ. Saints Row by Volition. Lua 5.4.9 by
PUC-Rio, MIT licensed (`third_party/lua-5.4.9`).

MIT licensed, see `LICENSE`.
