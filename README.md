# SR5 Tweak Menu

An in-game cheat menu for **Saints Row (2022)** on PC (Epic build, DirectX
12): the [SR Tweak Menu](https://github.com/00xJS/SR-Tweak-Menu) idea from
Saints Row 1, brought to the reboot. Work in progress.

![The menu in game: the Player tab](docs/menu.webp)

## Install

1. Download this repository (**Code > Download ZIP**) and unzip it.
2. Build the host: run `host\build.bat` (needs Visual Studio 2022 with
   **Desktop development with C++**).
3. Run `install.bat`. Give it the game's `sr5` folder as an argument if the
   game isn't in Epic's default folder. It puts `dinput8.dll` (the host) next
   to `SaintsRow_DX12.exe` and the menu in `sr5\TweakMenu\SRTweakMenu\`
   (an existing `mod.ini` is kept).
4. Start the game from Epic with **DirectX 12**. The DirectX 11 and Vulkan
   versions aren't supported yet: with them the menu stays off and the game
   runs as normal.
5. In game, open the menu:
   - **Keyboard:** F5
   - **Xbox controller:** hold RB and press D-pad Down

To uninstall, delete `sr5\dinput8.dll` and the `sr5\TweakMenu` folder.

## Controls

| | Keyboard | Xbox controller |
|---|---|---|
| Open / close menu | F5 | RB + D-pad Down |
| Move | Up / Down | D-pad Up / Down |
| Change value / browse list | Left / Right | D-pad Left / Right |
| Select | Enter | A |
| Change tab, or the next page when you're in one | PgUp / PgDn | LB / RB |
| Add to or take off Favourites | F6 | Y |
| Open a page | Enter | A |
| Back a page / close | Backspace | B |

While the menu is open its keys and the controller's buttons don't reach the
game; the sticks still do, so you can keep moving and looking around. The
controller is read through XInput: a PlayStation controller works when it
shows up as an Xbox one (Steam Input, DS4Windows).

## Features

Every row in the menu, tab by tab, in the menu's order. **Bold** names are
pages: Enter opens one, Backspace or B comes back. Every row has a help line
in the menu.

### Player

- **Health:** God mode, Max health, Refill health, Health regen, Get up, Downed timer, Kill yourself
- **Protection:** No fall damage, Bulletproof, Explosion-proof, Crash-proof, Damage to yourself, Immune to, Get up at once, No flinch, How easily you fall, Dodge safe time, Guardian angel
- **Movement:** Run speed, Always sprint, Swim speed, Fly (no clip), Your gravity, Moon mode, Your size, Wind push, Ice floor, No shoving
- **Jumping and air:** Jump height, Double jump, Jetpack, Air dash, Air control, Air momentum
- **Wingsuit:** Open wingsuit now, Wingsuit boosts, Wingsuit boost power, Wingsuit top speed, Wingsuit glide, Wingsuit from low down, Wingsuit bounce, Glide to nearest car
- **Flow:** Unlimited Flow, Flow gain, Extra Flow bars, Flow never drains, Rampage at full Flow
- **Skills and perks:** Free skills, Skills recharge at once, Equip any skill, Skill effect on you, All perks on, Any perk, Perk strength, My perks off
- **Takedowns:** Takedown ready now, Takedown cooldown, Grenade takedown, Takedowns always kill, Short takedowns only, Dustlander takedowns, No takedowns
- **Money:** Add cash, Drop cash, Money rain, Free shopping, Cash from kills, Pedestrians always pay, Free ventures, Venture income, Venture lot, Build venture on lot
- **XP and levels:** Give XP, Give skill points, Level up once, XP from kills, XP needed per level, Refund all skills
- **Unlocks:** Unlock everything, Unlock fast travel points, Unlock every weapon, Unlock all skills, Unlock all perks, Unlock gang and homies, Unlock all clothing, Unlock all store items, Unlock all weapon skins, Unlock all collectibles, Show activities on the map

### Character

- **Outfits:** Saved look, Saved look: outfit only, Character preset, Wear any outfit, Hidden outfit, Wear any item, Customize character, Clothes hide each other, No wind on clothes, Snapshot my look, Undo my look
- **Clothing:** Clothing slot, Clothing item, What's on this slot, Take off this slot, Item colour, Colour part, Item gloss, Stack on slot, Stack that item, Material slot, Item material
- **Hair, eyes and skin:** Hair colour, Beard colour, Eye colour, Eye glow, Skin type, Skin set
- **Face:** Face part, Face amount, Random face, Face: head shape, Face: eye size, Face: nose size, Face: mouth size, Face: eye spacing, Face: mouth width, Facial expression
- **Body:** Body: muscle, Body: fat, Body: thin, Body: chest, Body: masculine to feminine, Body: groin, Body: squeezed, Long legs, Back to my real body
- **Effects on you:** You are invisible, You look on fire, Skin effect on you, Stop skin effects, Prank yourself
- **Emotes:** Play emote, Hidden emote, D-pad emote 1, D-pad emote 2, Repeat emote, Freeze emote, Stop emote
- **Voice:** Your voice, Voice pitch, Any voice, Say a line, Radio call from, Everyone near says it
- **Animations:** Any animation, Animation mode, Animation speed, Everyone near plays it, Idle animation, Everyone near does an idle, End idle near, Move like, Stop animation
- **Poses and actions:** Force body state, Back on foot, Play cutscene, Sit down, Use nearest
- **How you walk:** Walk style, Movement style, Wounded walk, Swim on land, Always crouch, Go limp

### Weapons

Weapons back to normal

- **Firing:** Fire rate, Full auto, Magazine, Reload speed, No warm-up, No overheat, Range, Any gun in vehicles and surfing, Dual wield this gun
- **Aim and recoil:** No recoil, Perfect aim, Spread, Accurate hip fire, Recoil recovery, Firing shake, Aim anywhere
- **Damage and hits:** Damage, People damage, Car damage, Shield damage, Damage from behind, Friendly fire, Damage type, Pellets, Knockback, Stagger on hit, Bodies fly on kill
- **Melee and explosives:** Melee lunge, Melee swing width, Explosive punches, Blast radius, Explosive fuse, More satchels, Rocket speed
- **Thrustbuster:** Thruster throw speed, Thruster warm-up, Thruster fuse, Thruster power
- **Rounds and hit effects:** Special rounds, Round blast, Rounds stick, Rounds arc, Homing rounds, Hit effect, Signature effects on any gun, Shots start from
- **Shot tricks:** Teleport on shot, Clear portals, Black hole, Money gun, Prop gun, Shoot prop
- **Gun looks:** Tracer, Muzzle flash, Shell casing, Hit visuals, All shots one colour, Hide my gun, Random gun colours, Weapon skin, Hold gun like
- **Get weapons:** Give weapon, Special weapon, Prototype weapon, Put picked gun in slot, Refill all ammo, Rare ammo drops, Drop weapon
- **Upgrades and removal:** Max all weapon upgrades, Signature ability on this gun, All signature abilities, Remove this weapon, Remove test guns

### Vehicles

- **Get a vehicle:** From my garage, Spawn vehicle, Special vehicle, Vehicle type, Any vehicle, Any vehicle version, Keep earlier spawns, Get in when spawned, Get in nearest, Get out, Remove spawned vehicles
- **Speed and boost:** Engine power, Vehicle top speed, Vehicle speed limit, Air drag, Vehicle gravity, Vehicle time, Boat speed, Boost tank, Boost refill, Boost power, Boost now
- **Grip, brakes and steering:** Grip, Off-road grip, Front grip, Rear grip, Brakes, Steering, Drift angle, Burnout, Tank steering, Bike lean, Downforce
- **Body and weight:** Suspension, Ride height, Vehicle size, Wheel size, Weight balance, Heavy vehicle, Bouncy car, Slippery body, Twitchy body, Spin drag, Auto-flip
- **Toughness:** Vehicle god mode, No collision damage, Bulletproof tires, Keep vehicle repaired, Engine catches fire, Fire burn speed, Crash force, Floats on water, Never sink, Destroy this vehicle
- **Aircraft and hover:** Aircraft speed, VTOL boost, Helicopter agility, Helicopter lift, Flight mode, Hover rise and lower, Hover top speed, Hover height, Hover jump, Hover guns
- **Upgrades and parts:** Vehicle upgrade, Upgrade level, Rims, Tires, Off-road kit anywhere, Part slot, Part, Save vehicle to garage
- **Paint:** Next paint, Any paint, Paint area, Paint colour, Pattern area, Pattern, Any colour: material, Any colour
- **Lights and sound:** Underglow preset, Underglow colour, Underglow brightness, Headlights on, Brake lights stay on, Always tire marks, Always tire smoke, Any horn, Any engine sound
- **Abilities:** Vehicle ability, Fire that ability, Stop that ability, Remove that ability, No ability cooldowns, Vehicle jump power, Crab steering strength, Air control strength, Honk blast strength, Ejector cannon, Hoverboard slam
- **Rams and towing:** Ram power, Crusher, Takedowns at any speed, Bowelrod launch, Cowcatcher launch, Windshield launch, Add tow hook, Drop tow hook, Make nearest car towable, Stick nearest car on me, Unstick car
- **Stunts:** Launch start, Launch strength, Launch this vehicle, Jump this vehicle, Effect on this car, Back on the road, Stay on bike
- **Surfing and guns:** Surf nearest car, Stop surfing, Surf faster cars, Surf autopilot, Surfing is safe, Fire vehicle's guns, Shoot from any seat, Swap vehicle gun

### Teleport

Go to waypoint, Go to travel point, Go to store, Go to map place, Go up, Auto-teleport to waypoint, Warp from map, Teleport style, No map fast travel, Where am I

- **Saved places:** Save this spot, Go to saved place, Delete that place

### People

- **Spawn people:** Spawn person, Special person, Spawn 10 of that person, Spawn 10 random people, Spawned people act, Spawned people carry, Play as last spawned, Play as picked person, Play as picked special, Back to yourself, Remove spawned people
- **Homies and followers:** Summon homie, Call in Saints, Call in follower, Dismiss homies, Homie limit, Quiet homies, Next homie outfit, Spawned people get in my car, Spawned people go to waypoint, Spawned people can't die
- **Near: mood and sides:** Make everyone near react, Make everyone near dance, Make everyone near follow you, Make everyone near friendly, Make everyone near hostile, Stop fights near, Start a riot near, Zombie outbreak, Crowd around me, Stop crowding
- **Near: attacks:** Stun everyone near, Trip everyone near, Knock everyone near down, Float everyone near, Launch everyone near, Set everyone near on fire, Poison everyone near, Dissolve everyone near, Kill everyone near, Take down nearest, Delete everyone near
- **Near: orders:** Order everyone near, Give everyone near a behaviour, Everyone near hunts you, Make everyone near target you, Stop targeting me, Make everyone near shoot you, Stop shooting, Fake a noise, Speed of everyone near
- **Near: toughness:** Disarm everyone near, Re-arm everyone near, Strip shields near, Make everyone near tough, Everyone near staggers easily, Revive everyone near, Downed, not dead, Everyone near can be reeled
- **Near: looks:** Fade out everyone near, Fade everyone near back in, Statues near, Statues near back to life, Flaming look near, Flaming look near off, Face on everyone near, Skin effect near, Outline everyone near, Clear outlines, Size of everything near
- **Near: effects:** Short effect on everyone near, Lasting effect on everyone near, Lasting effect on you, Lasting effects off, Gravity near, Drop everyone near through ground, Hide everyone near on minimap, Show everyone near on minimap
- **Notoriety:** No notoriety, Notoriety at least, Notoriety at most, No notoriety cap, Notoriety fades fast, Notoriety climbs fast, Can't lose notoriety, Escape distance, Send in a gang, Send in a wave
- **Chases and waves:** No reinforcements, Enemies arrive from, Reinforcement speed, Chase cars, Chase speed, No ramming, No roadblocks, Roadblocks everywhere, Bigger squads, Elite enemies early, Enemies attacking at once
- **Enemies:** Enemy aim, Enemy sight, Enemies can't see you, Enemies always find you, Enemies flee fights, Non-lethal enemies, Riot shields for all, Enemies use smoke, Gangs and police without guns, Stay in combat, Stagger cooldown
- **Gangs:** Gang war, Free for all, Gang presence, Gang on your side, Saints are enemies, People fight damage, Pedestrians fight back, Everyone battle ready, Instant revive

### World

- **Time and weather:** Go to time, Freeze clock, Clock speed, Any weather, Any weather, instantly, Indoor weather outside, Game speed, Slow motion button, Pause world, Only you move
- **People on the streets:** Pedestrian count, Empty streets, People appear at, Quiet streets, Crowds in the rain, Panic distance, Any district's crowd, Street scene, Street scenes normal, Bodies and wrecks stay
- **Traffic:** Traffic amount, Traffic type, Rare traffic, Traffic spacing, Traffic appears at, No parked cars, Traffic light here, Long trains, No trains
- **Cars near: wreck:** Freeze cars near, Unfreeze cars near, Launch cars near, Spin cars near, Pop tires near, Stall engines near, Engines back on, Crush cars near, Tip bikes near, Blow up cars near, Delete nearest car
- **Drivers near:** Drivers near bail out, Drivers near floor it, Drivers near flee, Drivers near pull over, Drivers near weave, Drivers near stay in, Stunt for cars near, Cars near stop stunts
- **Cars near: horns and locks:** Set off car alarms, Sirens on near, Hazard lights near, Lock cars near, Unlock cars near, Pop trunks near, Ghost through cars near, Solid cars near
- **Gravity and blasts:** World gravity, Explosion here, Explosion at waypoint, Airstrike, Explosion size, Explosion force, Explosion damage, No world boundary
- **Props:** Spawn prop, Spawn standing turret, Remove last prop, Remove all props
- **Headquarters:** HQ spot, HQ prop, Clear this HQ spot, Fill the HQ, Save HQ layout, Load HQ layout, HQ room theme
- **Missions and side jobs:** Start mission, Start side job, Insurance Fraud here, Insurance Fraud launch, Insurance Fraud score, Activity time limits, Hermit juice, Give reward, Load hidden place, Unload hidden place

### Visual

- **Camera:** Field of view, Camera distance, Shoulder camera, Turn speed, Camera shake, Looping camera shake, Camera bobbing, Camera through walls, Photo mode, Free camera
- **Driving camera:** Car camera resets after, Free camera in cars, Car camera follows the nose, Car camera field of view, Car camera distance
- **HUD:** Hide HUD, Minimap size, Crosshair size, HUD style, High contrast, Takedown outlines, All caps text, Fake objective
- **Screen effects:** Brightness, Low health screen, Letterbox, Screen tint, Tunnel vision, Radial blur, Depth of field, Aim blur, Shift view, Colour vision filter, Camera effects
- **What's drawn:** Stop drawing, Show only people, Blackout, Blacklight world, World material, Censor mosaic, Video on screens, Video off
- **Sun, moon and stars:** Sun size, Moon size, Sun speed, Sun position, Sun colour, Moon colour, Star brightness, Star colour
- **Fog, cloud and rain:** Fog, Fog colour, Haze, Cloud cover, Rain amount, Heat haze, Wind speed
- **Light and colour:** Look, Sky exposure, Lock exposure, Light shafts, Ambient light, Bounced light, Sky colour, City lights on, Film grain, Dark screen edges
- **All sky settings:** Any sky setting, Sky amount, Clear sky settings

### Sound

- **Radio:** Radio station, Next station, Previous station, Unlock radio in missions, Radio on foot, Radios in cars near, Newscast, Stop newscast, Dev: radio on
- **Music:** Music anywhere, Play song, Pause or resume music, Skip track, Now playing, Shuffle playlists
- **Volume and sounds:** Master volume, Music volume, Effects volume, Voice volume, City panic noise, Play sound
- **Sound mix:** Volume: Ambience, Volume: Combat, Volume: Interface, Volume: Vehicles, Volume: Radio, Volume: Music in the world, Volume: Menu music, Volume: Explosions, Volume: Gore, Volume: Voices, Volume: Pedestrian voices

### Cheats

- **Player:** Invincibility (game's), Give cash, Max level, Super Saints, Milk Bones, Pratfall, Heaven Bound
- **Weapons:** Infinite ammo, Golden gun
- **Vehicles:** Repair vehicle, Drop a car, Infinite boost, Infinite mass, No traffic laws
- **Traffic:** Monster truck traffic, Luxury traffic, Mascots
- **World:** Weather, Time of day, Screen filter, Low gravity, Angry pedestrians
- **Notoriety:** Police, Idols, Marshal, Los Panteros

### Settings

What's on, Save tweaks for next time, Everything back to normal, Turn every cheat off, Pause all tweaks, Close menu

- **Game:** Skip cutscene, Pause / resume cutscene, Quick save, New save, Load last save, No autosave, Skip intro, Tutorial popups
- **Difficulty:** Difficulty: player health, Difficulty: player damage, Difficulty: enemies, Difficulty: vehicles, Difficulty: notoriety, Difficulty: ammo reserve, Difficulty: timer speed
- **Menu:** Menu opacity, Hold Back opens the menu, Keep my save clean, Forget saved tweaks
- **Game data:** Data system, Data group, Data entry, Data value, Data list item, Data change, Change this entry, Change all entries, Undo all data changes
- **Developer switches:** Dev: never die, Dev: never die, AI, Dev: Shawn mode, Dev: capture mode, Dev: auto sprint, Dev: infinite ammo, Dev: infinite magazine, Dev: vehicle ramps, Dev: weapon raycasts, Dev: notoriety bubbles, Dev: HQ mask off

With nothing saved, cheats and tweaks start off, except Keep my save clean, which starts on, and Melee lunge, which starts on None.
If you've saved tweaks, the menu says how many are on the first time it opens. Tweaks stay as you set them until you quit;
**Settings > Save tweaks for next time** keeps them for the next start (`sr5\TweakMenu\saved_tweaks.txt`); saved places are in
`sr5\TweakMenu\saved_places.txt`. The help line says when a row can crash the game
or should have a save behind it first.

## Settings

Every number is in `sr5\TweakMenu\SRTweakMenu\mod.ini`: the key that opens
the menu, where it's drawn and how big, rows shown at once, the panel's
opacity and Keep my save clean. Restart the game after changing them.

## Notes

- **Your save.** Rows marked `*` are the game's "spicy" cheats: in the game,
  using one marks your save as cheated and pauses achievements. With
  **Settings > Keep my save clean** (on by default) the menu lets them run
  without marking the save; achievements pause only while a spicy cheat is
  on. Nothing outside the game's cheats (god mode, weapons, teleport) touches
  that at all.
- **Weapon tweaks** change the game's own weapon data, shared with everyone
  who carries that weapon: fire rate, magazines and one-hit kill apply to
  enemies' guns too (x2 to x10 damage doesn't). Pair them with God mode.
- Single player only.
- The repository contains no game files.

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
| `player.lua` | Health, movement, position, teleport, saved places, spawning, the car you're in |
| `tweaks.lua` | Settings kept for next time |
| `world.lua` | The clock (freeze, speed), pausing the world, notoriety |
| `wingsuit.lua` | Wingsuit tweaks (its data and your live copy) |
| `camera.lua` | Camera turn speed |
| `vdata.lua` | Shared: field addresses in the game's reflection data |
| `vehicles.lua` | Every vehicle and variant in the game's tables, generated |
| `perks.lua` | The game's perk classes that its code reads, generated |
| `sounds.lua` | Sound event names from the game's audio tables, generated |
| `sky.lua` | The game's time-of-day settings and ranges, generated |
| `anims.lua` | The game's animation tags in always-loaded sets, generated |
| `clothes.lua` | The game's wearables with a model, by slot, generated |
| `rounds.lua` | Projectiles any gun can fire and every blast, generated |
| `browser.lua` | The game's records, numeric fields and flags by system, for Game data, generated |
| `shots.lua` | Rows that act on your shots: teleport, portals, black hole, homing, prop gun, dual wield |
| `cars.lua` | Vehicle parts, paint, guns, seats, physics and flight mode |
| `extras.lua` | Name lists for the weapon swaps and world rows, generated |
| `gameui.lua` | Draws the menu with the game's interface (vint text objects) |
| `luadump.lua` | Development: reads a game Lua function's constants from memory |

The `wml` table the Lua sees has the same shape as the SR1 menu's host:
`log`, `setting`, `read_*`/`write_*` (64-bit addresses),
`key_down`, `key_pressed`, `on_frame`, `pad`, plus `game(code)`,
`call(addr, ...)`, `buffer`, `read_string` and `base` (the executable's
load address).

**Testing**

- **Live probe.** Set `dev_probe = true` in the installed `mod.ini`. While the
  game runs, anything written to `sr5\TweakMenu\probe_in.lua` is run in the
  menu's Lua (with `game` and `dump` at hand), and what it prints goes to
  `sr5\TweakMenu\probe_out.txt`.
- **Research.** `research/` holds what was found in the game (addresses,
  the game's Lua globals, its interface functions) and `tools/` the Python
  scripts used to find it (they read `SaintsRow_DX12.exe` and the running
  game; `pip install pefile capstone numpy`). `tools/vpp.py` lists and
  extracts the game's `.vpp_pc` archives (its interface Lua is plain source
  there); what it extracts stays out of git. `tools/rcls.py` prints a
  reflection class's fields with offsets, `tools/vtbl.py` finds a class's
  vtable.

## Credits

- SR Tweak Menu by 00xJS. Saints Row by Volition.
- Lua 5.4.9 by PUC-Rio, MIT licensed (`third_party/lua-5.4.9`).

SR5 Tweak Menu's own code is MIT licensed, see `LICENSE`.
