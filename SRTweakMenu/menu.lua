-- SR5 Tweak Menu - the on-screen menu.
--
-- As in SR1: tabs across the top, a cursor down the rows, a help line under
-- them. Keys: F5 opens and closes, Up/Down move, Left/Right change a choice,
-- Enter toggles or runs, Backspace closes, PgUp/PgDn change tab.
-- Controller: hold RB and press D-pad Down to open or close, D-pad moves,
-- A selects, B closes, LB/RB change tab.
--
-- Rows are the game's own cheats (cheats.lua); a row whose cheat the game
-- doesn't have (a DLC not installed) is left out.
--
-- Spicy cheats (*): with "Keep my save clean" on (the default) the menu
-- lets them run without marking the save: the session flag is set just for
-- them and cleared once none is on (achievements pause only meanwhile),
-- and the save's "cheated" mark is kept at 0.

local C = require("cheats")
local U = require("gameui")
local W = require("weapons")
local P = require("player")
local T = require("tweaks")
local Wd = require("world")
local WS = require("wingsuit")
local S = wml.setting

local M = { open = false, tab = 1, cursor = {}, status = "", status_kind = "status", status_frames = 0,
  clean = S("keep_save_clean", true), spicy_hold = 0 }
local ROWS = S("menu_rows", 11)
local LINES = ROWS + 5   -- title, tabs, rows, two help lines, status
local OPEN_KEY = tostring(S("menu_key", "F5"))

local function toggle(cheat, label, help) return { kind = "toggle", cheat = cheat, label = label, help = help } end
local function action(cheat, label, help) return { kind = "action", cheat = cheat, label = label, help = help } end
local function choice(label, help, options, kind) return { kind = kind or "choice", label = label, help = help, options = options, sel = 1 } end
-- A player setting (a field of player.lua): Left/Right or Enter changes it.
local function pset(key, label, help, options) return { kind = "pset", key = key, label = label, help = help, options = options, sel = 1, save_key = "player." .. key } end
-- A game option or setting reached through the game's own Lua: `get` is an
-- expression giving the current value (nil: none), `set` a format with %s
-- for the new value. Its value is read when the menu opens; the first choice
-- is then the game's own value.
local function opt(label, help, get, set, options, save) return { kind = "opt", label = label, help = help, get = get, set = set, options = options, sel = 1, save_key = save } end
-- A one-press action that runs game Lua (`confirm`: needs a second press).
local function gcall(label, help, code, confirm) return { kind = "gcall", label = label, help = help, code = code, confirm = confirm } end
local function difficulty(i, label)
  local options = {}
  for v = 0, 10 do options[#options + 1] = { tostring(v), v / 10 } end
  return opt("Difficulty: " .. label, "Experimental: the pause menu's custom difficulty slider (saved with your game, as there).",
    "options_get_difficulty(" .. i .. ")", "options_set_difficulty(" .. i .. ", %s)", options)
end
-- A wingsuit setting (wingsuit.lua), applied at once.
local function wsset(key, label, help, options) return { kind = "wsset", key = key, label = label, help = help, options = options, sel = 1, save_key = "wingsuit." .. key } end
-- A weapon setting: Left/Right (or Enter) changes it and applies it at once.
local function wset(key, label, help, options) return { kind = "wset", key = key, label = label, help = help, options = options, sel = 1, save_key = "weapons." .. key } end

local TABS = {
  { name = "Player", rows = {
    pset("god", "God mode", "You can't die. Not the game's cheat: your save stays clean.", { { "Off", false }, { "On", true } }),
    pset("health_mult", "Health", "Your maximum health.", { { "Game's", 1 }, { "x2", 2 }, { "x5", 5 }, { "x10", 10 } }),
    { kind = "refill", label = "Refill health", help = "Back to full health." },
    { kind = "mvset", key = "run", label = "Run speed", help = "Experimental: walking and running speed.", options = { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 } }, sel = 1, save_key = "move.run" },
    { kind = "mvset", key = "air", label = "Air control", help = "Experimental: how much you steer in the air.", options = { { "Game's", 1 }, { "x2", 2 }, { "x4", 4 } }, sel = 1, save_key = "move.air" },
    { kind = "mvset", key = "swim", label = "Swim speed", help = "Experimental: how fast you swim.", options = { { "Game's", 1 }, { "x2", 2 }, { "x3", 3 } }, sel = 1, save_key = "move.swim" },
    { kind = "mvset", key = "gravity", label = "Your gravity", help = "Experimental: lower is floatier jumps and falls.", options = { { "Game's", 1 }, { "x0.5", 0.5 }, { "x0.25", 0.25 }, { "x2", 2 } }, sel = 1, save_key = "move.gravity" },
    { kind = "emote_slot", slot = "primary", label = "D-pad emote 1", help = "Left/Right picks, Enter puts it on your first D-pad emote; then use the D-pad as usual.", sel = 1, options = {} },
    { kind = "emote_slot", slot = "secondary", label = "D-pad emote 2", help = "Left/Right picks, Enter puts it on your second D-pad emote; then use the D-pad as usual.", sel = 1, options = {} },
    { kind = "emote", label = "Play emote", help = "Experimental: Left/Right picks one of the game's emotes, Enter plays it now.", sel = 1, options = {} },
    { kind = "mset", key = "repeat_emote", label = "Repeat emote", help = "Plays the emote picked in Play emote again and again; Stop emote ends it.", options = { { "Off", false }, { "Every 3 s", 180 }, { "Every 6 s", 360 }, { "Every 12 s", 720 } }, sel = 1 },
    { kind = "emote_stop", label = "Stop emote", help = "Stops the emote you're playing (and Repeat emote)." },
    { kind = "homie", label = "Summon homie", help = "Experimental: Left/Right picks a homie, Enter calls them in (if the game lets you).", sel = 1, options = {} },
    wsset("cooldown", "Wingsuit boosts", "How soon you can boost again (the game's: 15 s).", { { "Game's", 1 }, { "Every 2 s", "short" }, { "Unlimited", "none" } }),
    wsset("boost", "Wingsuit boost power", "Boost speed, acceleration and length.", { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 } }),
    wsset("speed", "Wingsuit top speed", "Top speed without boosting, launch speed, landing speed cap.", { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 } }),
    wsset("glide", "Wingsuit glide", "Floaty: half gravity. Level: barely drops, no stall. Climb: gains height as you fly.", { { "Game's", "game" }, { "Floaty", "floaty" }, { "Level", "level" }, { "Climb", "climb" } }),
    toggle("invincibility", "Invincibility (game's)", "The game's Invincibility cheat."),
    action("cash", "Give cash", "The game's cash cheat."),
    action("max level", "Max level", "Jumps you to the top level."),
    toggle("super_saints", "Super Saints", "The game's Super Saints cheat."),
    toggle("milk_bones", "Milk Bones", "The game's Milk Bones cheat."),
    toggle("pratfall", "Pratfall", "You ragdoll at the slightest touch."),
    toggle("heaven_bound", "Heaven Bound", "The game's Heaven Bound cheat."),
  } },
  { name = "Weapons", rows = {
    wset("magazine", "Magazine", "No reload: every magazine holds " .. W.NO_RELOAD .. ", launchers too. Add Infinite ammo to never run dry.", {
      { "Game's", 1 }, { "x2", 2 }, { "x5", 5 }, { "No reload", "no_reload" } }),
    toggle("infinite_ammo", "Infinite ammo", "Your reserve ammo never runs out (the game's cheat; your save stays clean)."),
    wset("fire_rate", "Fire rate", "How fast every weapon fires.", { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x4", 4 }, { "x8", 8 } }),
    pset("full_auto", "Full auto", "Single-shot guns keep firing while you hold the trigger (mouse or RT).", { { "Off", false }, { "On", 70 }, { "Fast", 40 } }),
    wset("damage", "Damage", "x2 to x10: your guns only. One-hit kill: every gun, enemies' too (pair it with God mode).", { { "Game's", 1 }, { "x2", 2 }, { "x5", 5 }, { "x10", 10 }, { "One-hit kill", "kill" } }),
    wset("reload", "Reload speed", "How fast reloads go.", { { "Game's", 1 }, { "x2", 2 }, { "x4", 4 }, { "Instant", 20 } }),
    wset("perfect_aim", "Perfect aim", "No spread: every shot goes where you aim.", { { "Off", false }, { "On", true } }),
    wset("no_warmup", "No warm-up", "Miniguns spin up and charged weapons charge at once.", { { "Off", false }, { "On", true } }),
    wset("no_overheat", "No overheat", "Weapons that overheat never do.", { { "Off", false }, { "On", true } }),
    wset("range", "Range", "How far every weapon reaches.", { { "Game's", 1 }, { "x2", 2 }, { "x4", 4 } }),
    wset("knockback", "Knockback", "How hard hits push people and things.", { { "Game's", 1 }, { "x3", 3 }, { "x10", 10 } }),
    gcall("Max every weapon's upgrades", "Every upgradeable weapon to its top level (saved with your game, like buying them).", [[
      local n = 0
      for _, inv in vlib_info_object:ipairs("inventory_weapon_info") do
        if weapon_has_upgrades(inv) then
          local lvl, max = weapon_get_upgrade_level(inv)
          if max and lvl and lvl < max then weapon_set_upgrade_level(inv, max) n = n + 1 end
        end
      end
      return n .. " weapons upgraded"
    ]]),
    toggle("golden_gun", "Golden gun", "The game's Golden Gun cheat."),
    { kind = "weapons_reset", label = "Weapons back to normal", help = "Every weapon setting back to the game's." },
  } },
  { name = "Vehicles", rows = {
    { kind = "deliver", label = "Spawn vehicle", help = "Left/Right picks one of the game's 90 vehicles, Enter spawns it next to you.", sel = 1, options = {} },
    { kind = "carset", key = "power", label = "Engine power", help = "Experimental: the torque of the vehicle you're in.", options = { { "Game's", 1 }, { "x2", 2 }, { "x3", 3 }, { "x5", 5 } }, sel = 1, save_key = "car.power" },
    { kind = "carset", key = "top", label = "Vehicle top speed", help = "Experimental: the top speed of the vehicle you're in.", options = { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 } }, sel = 1, save_key = "car.top" },
    action("vehicle_health", "Repair vehicle", "Fixes the vehicle you're in."),
    pset("keep_repaired", "Keep vehicle repaired", "Repairs the vehicle you're in every second (the game's repair cheat): near god mode.", { { "Off", false }, { "On", true } }),
    action("drop_car", "Drop a car", "Drops a car from the sky."),
    toggle("infinite_boost", "Infinite boost", "Vehicle boost never runs out."),
    toggle("infinite_mass", "Infinite mass", "Your vehicle shoves anything aside."),
    toggle("no_traffic_laws", "No traffic laws", "The game's No Traffic Laws cheat."),
    toggle("city_monster_truck", "Monster truck traffic", "Traffic is monster trucks."),
    toggle("city_luxury_spawn", "Luxury traffic", "Traffic is luxury cars."),
    toggle("city_mascot", "Mascots", "The game's City Mascot cheat."),
  } },
  { name = "Teleport", rows = {
    { kind = "warp", label = "Fast travel point", help = "Left/Right picks one of the game's 44 travel points, Enter takes you there.", sel = 1, options = {} },
    { kind = "place_save", label = "Save this spot", help = "Saves where you stand to your places (TweakMenu, saved_places.txt)." },
    { kind = "places", label = "Go to", help = "Left/Right picks one of your places, Enter takes you there.", sel = 1 },
    { kind = "place_delete", label = "Delete that place", help = "Removes the place picked above." },
    { kind = "lift", label = "Go up", help = "Left/Right picks how high, Enter takes you straight up.", sel = 2,
      options = { { "10 m", 10 }, { "50 m", 50 }, { "100 m", 100 }, { "250 m", 250 }, { "500 m", 500 }, { "1000 m", 1000 }, { "2000 m", 2000 }, { "3000 m", 3000 } } },
    { kind = "where", label = "Where am I", help = "Shows your position." },
  } },
  { name = "World", rows = {
    choice("Weather", "Left/Right picks, Enter sets it.", {
      { "Clear", "weather_clear" }, { "Dust", "weather_dust" }, { "Fog", "weather_fog" } }),
    choice("Time of day", "Left/Right picks, Enter sets it.", {
      { "Morning", "tod_morning" }, { "Noon", "tod_noon" }, { "Afternoon", "tod_afternoon" },
      { "Evening", "tod_evening" }, { "Midnight", "tod_midnight" } }),
    { kind = "wdset", key = "freeze_clock", label = "Freeze clock", help = "Stops the time of day where it is.", options = { { "Off", false }, { "On", true } }, sel = 1, save_key = "world.freeze_clock" },
    { kind = "wdset", key = "clock_speed", label = "Clock speed", help = "How fast the time of day passes.", options = { { "Game's", 1 }, { "x0.5", 0.5 }, { "x2", 2 }, { "x5", 5 }, { "x10", 10 } }, sel = 1, save_key = "world.clock_speed" },
    { kind = "wdset", key = "pause", label = "Pause world", help = "Everything stops, you too (the game's own pause); the menu still works.", options = { { "Off", false }, { "On", true } }, sel = 1 },
    { kind = "person", label = "Spawn person", help = "Left/Right picks one of the game's characters, Enter spawns them beside you.", sel = 1, options = {} },
    { kind = "crowd", label = "Spawn a crowd", help = "Ten of the character picked above, in a ring around you." },
    { kind = "random_people", label = "Spawn 10 random people", help = "Ten of the game's characters, picked at random, around you." },
    toggle("low_gravity", "Low gravity", "Everything floats a little."),
    toggle("ped_agro", "Angry pedestrians", "People on the street turn on you."),
    { kind = "wdset", key = "never_wanted", label = "Never wanted", help = "Clears notoriety as soon as you get it: from anyone, the police and Marshal, or gangs.",
      options = { { "Off", false }, { "By anyone", "all" }, { "By police", "police" }, { "By gangs", "gangs" } }, sel = 1, save_key = "world.never_wanted" },
    choice("Police", "Raise or clear your notoriety with them; Max raises it to the top.", { { "Raise", "increase_police" }, { "Clear", "clear_police" }, { "Max", "increase_police", max = true } }),
    choice("Idols", "Raise or clear your notoriety with them; Max raises it to the top.", { { "Raise", "increase_idols" }, { "Clear", "clear_idols" }, { "Max", "increase_idols", max = true } }),
    choice("Marshal", "Raise or clear your notoriety with them; Max raises it to the top.", { { "Raise", "increase_marshal" }, { "Clear", "clear_marshal" }, { "Max", "increase_marshal", max = true } }),
    choice("Los Panteros", "Raise or clear your notoriety with them; Max raises it to the top.", { { "Raise", "increase_panteros" }, { "Clear", "clear_panteros" }, { "Max", "increase_panteros", max = true } }),
    difficulty(0, "player health"), difficulty(1, "player damage"), difficulty(2, "enemies"), difficulty(3, "vehicles"),
    difficulty(4, "notoriety"), difficulty(5, "ammo reserve"), difficulty(6, "timer speed"),
  } },
  { name = "Visual", rows = {
    choice("Screen filter", "Left/Right picks, Enter applies it.", {
      { "Off", false }, { "Black & white", "screen_effect_black_white" }, { "Retro", "screen_effect_retro" },
      { "Night vision", "screen_effect_night_vision" }, { "Old-timey", "screen_effect_old_timey" },
      { "Vapor", "screen_effect_vapor" }, { "Western", "screen_effect_western" }, { "Steamboat", "screen_effect_steamboat" } }, "filter"),
    opt("Field of view", "The game's camera field of view option, wider than its menu allows at the top.",
      "option_get_camera_fov_offset()", "option_set_camera_fov_offset(%s)",
      { { "0", 0 }, { "0.25", 0.25 }, { "0.5", 0.5 }, { "0.75", 0.75 }, { "1", 1 }, { "1.5", 1.5 } }),
    opt("Camera shake", "The game's camera shake option.", "option_get_camera_shake_enabled()", "option_set_camera_shake_enabled(%s)", { { "On", 1 }, { "Off", 2 } }),
    opt("Looping camera shake", "The game's looping camera shake option (engines, idle sway).", "option_get_looping_camera_shake_enabled()", "option_set_looping_camera_shake_enabled(%s)", { { "On", 1 }, { "Off", 2 } }),
    opt("Camera bobbing", "The game's camera bobbing option.", "option_get_camera_bobbing_enabled()", "option_set_camera_bobbing_enabled(%s)", { { "On", 1 }, { "Off", 2 } }),
    gcall("Photo mode", "The game's photo mode: a free camera. Close the menu to move it; press again to leave.", "cell_photo_mode_toggle() return cell_photo_mode_is_active() and 'on' or 'off'"),
    { kind = "hud", label = "Hide HUD", help = "Experimental: hides the HUD the way the game's own option does.", options = { { "Off", false }, { "On", true } }, sel = 1, save_key = "visual.hide_hud" },
  } },
  { name = "Settings", rows = {
    gcall("Skip cutscene", "Skips the cutscene that's playing.", "cinematic_skip() return 'skipped'"),
    gcall("Pause / resume cutscene", "Pauses the cutscene that's playing, or resumes it.", "if rawget(_G, 'SR5TM_CINE_PAUSED') then cinematic_resume() rawset(_G, 'SR5TM_CINE_PAUSED', nil) return 'resumed' else cinematic_pause() rawset(_G, 'SR5TM_CINE_PAUSED', true) return 'paused' end"),
    gcall("Load last save", "Loads your newest save (press twice). Unsaved progress is lost.", "gml_ui_save_game_request_load_newest() return 'loading'", true),
    opt("Tutorial popups", "The game's tutorial popups option (0 = none).", "options_get_tutorial_frequency()", "options_set_tutorial_frequency(%s)", { { "Off", 0 }, { "1", 1 }, { "2", 2 }, { "3", 3 } }),
    { kind = "mset", key = "tweaks_paused", label = "All tweaks", help = "Off: every menu tweak back to the game's for now. On: they all come back. Cheats stay.", options = { { "On", false }, { "Off", true } }, sel = 1 },
    { kind = "mset", key = "hold_back", label = "Hold Back opens the menu", help = "Experimental: hold Back (View) for a second to open or close the menu. The game sees it too.", options = { { "Off", false }, { "On", true } }, sel = 1, save_key = "menu.hold_back" },
    { kind = "clean", label = "Keep my save clean", help = "Spicy cheats don't mark your save; achievements pause only while one is on." },
    { kind = "opacity", label = "Menu opacity", help = "How dark the panel behind the menu is. Left/Right." },
    { kind = "active", label = "What's on", help = "Lists every tweak and cheat that's on right now." },
    { kind = "all_off", label = "Turn every cheat off", help = "Switches off every toggle cheat that's on." },
    { kind = "normal", label = "Everything back to normal", help = "Every menu tweak back to the game's (press twice). Cheats and game options stay." },
    { kind = "forget", label = "Forget saved tweaks", help = "Settings are kept for next time as you change them; this starts fresh." },
    { kind = "close", label = "Close menu", help = "F5, or hold RB and press D-pad Down, opens it again." },
  } },
}

-- Settings kept from last time (tweaks.lua).
local function all_rows()
  local rows = {}
  for _, t in ipairs(TABS) do for _, r in ipairs(t.rows) do rows[#rows + 1] = r end end
  return rows
end
-- Puts a row's value where its module reads it.
local function set_value(r, v)
  if r.kind == "wset" then W.set[r.key] = v elseif r.kind == "pset" then P[r.key] = v
  elseif r.kind == "wdset" then Wd[r.key] = v
  elseif r.kind == "wsset" then WS.set[r.key] = v
  elseif r.kind == "mvset" then P.move[r.key] = v
  elseif r.kind == "carset" then P.car[r.key] = v
  elseif r.kind == "mset" then M[r.key] = v end
end
-- A menu tweak (not a game option, the HUD or the menu's own settings).
local function tweak_row(r)
  return (r.save_key or r.kind == "wdset") and r.options and r.kind ~= "opt" and r.kind ~= "hud" and r.kind ~= "mset"
end
local function apply_saved()
  for _, row in ipairs(all_rows()) do
    local i = T.pick(row)
    if i then
      row.sel = i
      set_value(row, row.options[i][2])
    end
  end
  if T.saved.clean then M.clean = T.saved.clean == "on" end
  if T.saved.opacity then U.opacity = tonumber(T.saved.opacity) or U.opacity end
end
function M.save_tweaks()
  local rows = all_rows()
  rows[#rows + 1] = { save_key = "clean", options = { { M.clean and "on" or "off" } }, sel = 1 }
  rows[#rows + 1] = { save_key = "opacity", options = { { tostring(U.opacity) } }, sel = 1 }
  -- with All tweaks off, the tweaks put aside are what's kept
  local function swap() for r, sel in pairs(M.stash or {}) do r.sel, M.stash[r] = sel, r.sel end end
  swap()
  T.save(rows)
  swap()
end

-- All tweaks off: every menu tweak to the game's, the choices put aside;
-- on: they come back.
function M.pause_tweaks(off)
  if off and not M.stash then
    M.stash = {}
    for _, r in ipairs(all_rows()) do
      if tweak_row(r) and r.sel ~= 1 then M.stash[r] = r.sel; r.sel = 1; set_value(r, r.options[1][2]) end
    end
    W.restore(); WS.restore()
  elseif not off and M.stash then
    for r, sel in pairs(M.stash) do r.sel = sel; set_value(r, r.options[sel][2]) end
    M.stash = nil
    if W.any_on() then W.apply() end
    if WS.any_on() then WS.apply() end
  end
  M.tweaks_paused = off
end
apply_saved()

-- Rows only for cheats this game has; options likewise.
local function prune()
  for _, tab in ipairs(TABS) do
    local kept = {}
    for _, row in ipairs(tab.rows) do
      if row.cheat then
        if C.by_name[row.cheat] then kept[#kept + 1] = row end
      elseif row.options and (row.kind == "choice" or row.kind == "filter") then   -- options that are cheats
        local opts = {}
        for _, o in ipairs(row.options) do if o[2] == false or C.by_name[o[2]] then opts[#opts + 1] = o end end
        row.options = opts
        if #opts > 0 then kept[#kept + 1] = row end
      else
        kept[#kept + 1] = row
      end
    end
    tab.rows = kept
  end
end

-- The names of every object of a class (the game's tostring of each).
local function names_of(cls)
  local out, first = {}, 1
  while true do
    local res = table.pack(wml.game([[local i, o = 0, {} for _, x in vlib_info_object:ipairs("]] .. cls .. [[") do
      i = i + 1 if i >= ]] .. first .. [[ and i < ]] .. (first + 25) .. [[ then o[#o + 1] = tostring(x) end end return i, unpack(o)]]))
    if not res[1] then break end
    for j = 3, res.n do out[#out + 1] = res[j] end
    first = first + 25
    if first > res[2] then break end
  end
  return out
end
-- every object of a class: { name, hash (the name's hash, from its id) }
local function names_of_objects(cls)
  local out, first = {}, 1
  while true do
    local res = table.pack(wml.game([[local i, o = 0, {} for _, x in vlib_info_object:ipairs("]] .. cls .. [[") do
      i = i + 1 if i >= ]] .. first .. [[ and i < ]] .. (first + 20) .. [[ then o[#o + 1] = tostring(x) o[#o + 1] = x end end return i, unpack(o)]]))
    if not res[1] then break end
    for j = 3, res.n, 2 do
      local p = tonumber(tostring(res[j + 1]):match("(%x+)>$") or "", 16)
      if p then out[#out + 1] = { name = res[j]:match('"(.*)"') or res[j], hash = (wml.read_u64(p + 0x28) >> 32) & 0xFFFFFFFF } end
    end
    first = first + 20
    if first > res[2] then break end
  end
  return out
end
local function pretty(name) return (name:gsub("_", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end)) end

-- The game's factions (gml_faction), by name hash: which clear cheat is
-- theirs and whether they're police (police, Marshal) or a gang.
local function load_factions()
  M.factions = {}
  local names = {}
  for _, f in ipairs(names_of_objects("gml_faction")) do
    local n = f.name:lower()
    names[#names + 1] = f.name
    if n:find("marshal") then M.factions[f.hash] = { cheat = "clear_marshal", group = "police" }
    elseif n:find("police") or n:find("cop") then M.factions[f.hash] = { cheat = "clear_police", group = "police" }
    elseif n:find("idol") then M.factions[f.hash] = { cheat = "clear_idols", group = "gangs" }
    elseif n:find("pantero") then M.factions[f.hash] = { cheat = "clear_panteros", group = "gangs" } end
  end
  wml.log("factions: " .. table.concat(names, ", "))
end

local function play_emote(id)
  return wml.game([[for _, e in vlib_info_object:ipairs("collectible_emote") do if tostring(e) == ]] .. string.format("%q", id) .. [[ then
    emote_play_in_world(e) return end end]])
end

local function say(text, kind) M.status, M.status_kind, M.status_frames = text, kind or "status", 240 end

local function is_spicy(name) local c = C.by_name[name]; return c and c.spicy end

local function fire(name, row, label)
  local c = C.by_name[name]
  if c.toggle and c.active then
    if C.activate(name) then say(label .. ": off") else say(label .. ": the game refused", "warn") end
    return
  end
  -- A spicy cheat runs only while the session flag is set: set it, and keep
  -- it a couple of seconds for one-shot cheats to finish.
  if c.spicy then C.allow_spicy(); M.spicy_hold = 120 end
  local cash_before = name == "cash" and C.cash()
  if C.activate(name) then
    say(label .. (c.toggle and ": on" or ": done"))
    -- The cash cheat pays out a moment later: check and report the change.
    if cash_before then M.cash_check = { before = cash_before, frames = 30 } end
  else
    say(label .. ": the game refused right now", "warn")
  end
end

local function select_row(row)
  if M.stash then M.stash[row] = nil end   -- changed while All tweaks is off: keep the new choice
  if row.kind == "toggle" or row.kind == "action" then
    fire(row.cheat, row, row.label)
  elseif row.kind == "choice" then
    local o = row.options[row.sel]
    if o.max then
      -- raise it once every 3/4 s, enough times to reach the top
      M.raise = { name = o[2], label = row.label, left = 6, wait = 0 }
      say(row.label .. ": raising to the top")
    else
      fire(o[2], row, row.label .. " " .. o[1])
    end
  elseif row.kind == "mset" then
    M.adjust_mset(row, 1)
  elseif row.kind == "random_people" then
    local pick
    for _, r in ipairs(all_rows()) do if r.kind == "person" then pick = r end end
    if not pick or #pick.options == 0 then say("No characters (load into the game first)", "warn") else
      local n = 0
      for i = 1, 10 do
        local o = pick.options[math.random(#pick.options)]
        local a = i / 10 * 2 * math.pi
        if P.spawn_npc(o[2], math.cos(a) * 5, math.sin(a) * 5) then n = n + 1 end
      end
      say(n .. " random people spawned")
    end
  elseif row.kind == "emote_stop" then
    for _, r in ipairs(all_rows()) do if r.key == "repeat_emote" then r.sel = 1 end end
    M.repeat_emote = false
    local ok, err = wml.game("emote_attempt_stop()")
    say(ok and "Emote stopped" or ("Stop emote: " .. tostring(err)), ok and "status" or "warn")
  elseif row.kind == "filter" then
    local o = row.options[row.sel]
    for _, other in ipairs(row.options) do
      if other[2] and other[2] ~= o[2] and C.by_name[other[2]].active then C.activate(other[2]) end
    end
    if o[2] and not C.by_name[o[2]].active then fire(o[2], row, "Filter " .. o[1]) else say("Filter: " .. o[1]) end
  elseif row.kind == "wset" then
    M.adjust_wset(row, 1)
  elseif row.kind == "pset" then
    M.adjust_pset(row, 1)
  elseif row.kind == "refill" then
    say(P.refill() and "Health refilled" or "No player right now", "status")
  elseif row.kind == "place_save" then
    local place = P.save_here()
    if place then say(string.format("Saved %s (%.0f, %.0f, %.0f)", place.name, place.x, place.y, place.z)) else say("No player right now", "warn") end
  elseif row.kind == "places" then
    local place = P.places[row.sel]
    if not place then say("No saved places yet: use Save this spot.", "warn")
    elseif P.teleport(place.x, place.y + 0.5, place.z) then say("Off to " .. place.name)
    else say("The game refused the teleport", "warn") end
  elseif row.kind == "place_delete" then
    local pick = M.places_row
    local place = pick and P.places[pick.sel]
    if place then table.remove(P.places, pick.sel); P.save_places(); pick.sel = math.max(1, math.min(pick.sel, #P.places)); say("Deleted " .. place.name)
    else say("No place picked", "warn") end
  elseif row.kind == "lift" then
    local x, y, z = P.position()
    local up = row.options[row.sel][2]
    if x and P.teleport(x, y + up, z) then say("Up " .. up .. " m") else say("No player right now", "warn") end
  elseif row.kind == "where" then
    local x, y, z = P.position()
    say(x and string.format("You're at %.1f, %.1f, %.1f", x, y, z) or "No player right now")
  elseif row.kind == "weapons_reset" then
    for _, t in ipairs(TABS) do for _, r in ipairs(t.rows) do if r.kind == "wset" then r.sel = 1; W.set[r.key] = r.options[1][2] end end end
    W.restore()
    M.save_tweaks()
    say("Weapons back to normal")
  elseif row.kind == "clean" then
    M.clean = not M.clean
    M.save_tweaks()
    say(M.clean and "Your save stays clean." or "Spicy cheats now mark your save, as the game does.", M.clean and "status" or "warn")
  elseif row.kind == "opacity" then
    say("Menu opacity: " .. U.opacity .. "%")
  elseif row.kind == "hud" then
    M.adjust_hud(row, 1)
  elseif row.kind == "opt" then
    M.adjust_opt(row, 1)
  elseif row.kind == "wdset" then
    M.adjust_wdset(row, 1)
  elseif row.kind == "wsset" then
    M.adjust_wsset(row, 1)
  elseif row.kind == "mvset" then
    M.adjust_mvset(row, 1)
  elseif row.kind == "carset" then
    M.adjust_carset(row, 1)
  elseif row.kind == "gcall" then
    if row.confirm and M.pending_confirm ~= row then
      M.pending_confirm = row
      say(row.label .. ": press again to confirm", "warn")
    else
      M.pending_confirm = nil
      local ok, msg = wml.game(row.code)
      say(row.label .. ": " .. tostring(ok and (msg or "done") or msg), ok and "status" or "warn")
    end
  elseif row.kind == "deliver" then
    -- the game's drop-car cheat, pointed at the picked table entry: it spawns
    -- the vehicle properly (wheels, variant) about 5 m from you
    local o = row.options[row.sel]
    if not o or not C.by_name.drop_car then say("No vehicles (load into the game first)", "warn") else
      wml.write_u32(wml.base + 0x3110E08, o[2])
      C.allow_spicy(); M.spicy_hold = 120
      local ok = C.activate("drop_car")
      say(ok and (o[1] .. " spawned") or (o[1] .. ": the game refused right now"), ok and "status" or "warn")
    end
  elseif row.kind == "person" then
    local o = row.options[row.sel]
    local obj = o and P.spawn_npc(o[2], 3, 0)
    say(obj and (o[1] .. " spawned") or "Couldn't spawn that character", obj and "status" or "warn")
  elseif row.kind == "crowd" then
    local pick = M.person_row and M.person_row.options[M.person_row.sel]
    if not pick then say("Pick a character in Spawn person first", "warn") else
      local n = 0
      for i = 1, 10 do
        local a = i / 10 * 2 * math.pi
        if P.spawn_npc(pick[2], math.cos(a) * 5, math.sin(a) * 5) then n = n + 1 end
      end
      say(n .. " x " .. pick[1] .. " spawned")
    end
  elseif row.kind == "homie" then
    local o = row.options[row.sel]
    if not o then say("No homies (load into the game first)", "warn") else
      local ok, can = wml.game([[for _, h in vlib_info_object:ipairs("homie_info") do if tostring(h) == ]] .. string.format("%q", o[2]) .. [[ then
        if not homie_can_summon(h) then return false end homie_summon(h) return true end end]])
      say(can and ("Calling " .. o[1]) or (o[1] .. " can't come right now"), can and "status" or "warn")
    end
  elseif row.kind == "warp" then
    local w = row.options[row.sel]
    if not w then say("No travel points (load into the game first)", "warn")
    else
      local ok, err = wml.game([[for _, w in vlib_info_object:ipairs("city_warp_point") do
        if tostring(w) == ]] .. string.format("%q", w[2]) .. [[ then player_local_teleport_to_warp_point(w) return end end]])
      say(ok and ("Off to " .. w[1]) or ("Travel: " .. tostring(err)), ok and "status" or "warn")
    end
  elseif row.kind == "emote" then
    local o = row.options[row.sel]
    if not o then say("No emotes (load into the game first)", "warn") else
      M.emote_pick, M.emote_frames = o[2], 0
      local ok, err = play_emote(o[2])
      say(ok and ("Emote: " .. o[1]) or ("Emote: " .. tostring(err)), ok and "status" or "warn")
    end
  elseif row.kind == "emote_slot" then
    local o = row.options[row.sel]
    if not o then say("No emotes (load into the game first)", "warn") else
      local ok, now = wml.game([[for _, e in vlib_info_object:ipairs("collectible_emote") do if tostring(e) == ]] .. string.format("%q", o[2]) .. [[ then
        emote_set_active_]] .. row.slot .. [[(e) return tostring(emote_get_active_]] .. row.slot .. [[()) end end]])
      if not ok then say(row.label .. ": " .. tostring(now), "warn")
      elseif now == o[2] then say(row.label .. ": " .. o[1] .. " (press the D-pad to use it)")
      else say(row.label .. ": the game kept its own (" .. tostring(now) .. ")", "warn") end
    end
  elseif row.kind == "active" then
    local on = {}
    for _, r in ipairs(all_rows()) do
      if (tweak_row(r) or r.kind == "mset" or r.kind == "hud") and r.sel ~= 1 then on[#on + 1] = r.label .. " " .. r.options[r.sel][1] end
    end
    for _, c in ipairs(C.list) do if c.toggle and c.active then on[#on + 1] = c.name end end
    local text = #on == 0 and "Nothing's on: the game as it comes" or (#on .. " on: " .. table.concat(on, ", "))
    if #text > 95 then text = text:sub(1, 92) .. "..." end
    say(text)
  elseif row.kind == "normal" then
    if M.pending_confirm ~= row then
      M.pending_confirm = row
      say(row.label .. ": press again to confirm", "warn")
    else
      M.pending_confirm = nil
      M.stash = nil
      for _, r in ipairs(all_rows()) do
        if tweak_row(r) and r.sel ~= 1 then r.sel = 1; set_value(r, r.options[1][2]) end
        if r.key == "tweaks_paused" then r.sel = 1; M.tweaks_paused = false end
      end
      W.restore(); WS.restore()
      M.save_tweaks()
      say("Everything back to the game's own")
    end
  elseif row.kind == "forget" then
    T.forget()
    say("Saved tweaks forgotten: next start is the game's own")
  elseif row.kind == "all_off" then
    local n = 0
    for _, c in ipairs(C.list) do if c.toggle and c.active and C.activate(c.name) then n = n + 1 end end
    say(n .. " cheat" .. (n == 1 and "" or "s") .. " turned off")
  elseif row.kind == "close" then
    M.open = false
  end
end

local function row_value(row)
  if row.kind == "toggle" then
    local on = C.by_name[row.cheat].active
    return on and "ON" or "OFF", on and "on" or "off"
  elseif row.kind == "choice" or row.kind == "filter" then
    local value = "<  " .. row.options[row.sel][1] .. "  >"
    if row.kind == "filter" then
      for i, o in ipairs(row.options) do
        if o[2] and C.by_name[o[2]].active and i == row.sel then value = value .. "  (on)" end
      end
    end
    return value
  elseif row.kind == "action" then
    return "Enter", "off"
  elseif row.kind == "wset" or row.kind == "pset" or row.kind == "hud" or row.kind == "opt" or row.kind == "wdset" or row.kind == "wsset" or row.kind == "mvset" or row.kind == "carset" then
    local o = row.options[row.sel]
    return "<  " .. o[1] .. "  >", row.sel == 1 and "off" or "on"
  elseif row.kind == "places" then
    M.places_row = row
    local place = P.places[row.sel]
    return place and ("<  " .. place.name .. "  >") or "none saved", place and "row" or "off"
  elseif row.kind == "forget" then
    return "Enter", "off"
  elseif row.kind == "person" then
    M.person_row = row
    local o = row.options[row.sel]
    return o and ("<  " .. o[1] .. "  >") or "none", o and "row" or "off"
  elseif row.kind == "crowd" then
    return "Enter", "off"
  elseif row.kind == "active" or row.kind == "normal" or row.kind == "random_people" or row.kind == "emote_stop" then
    return "Enter", "off"
  elseif row.kind == "mset" then
    local o = row.options[row.sel]
    return "<  " .. o[1] .. "  >", row.sel == 1 and "off" or "on"
  elseif row.kind == "lift" or row.kind == "warp" or row.kind == "deliver" or row.kind == "homie" or row.kind == "emote" or row.kind == "emote_slot" then
    local o = row.options[row.sel]
    return o and ("<  " .. o[1] .. "  >") or "none", o and "row" or "off"
  elseif row.kind == "gcall" then
    return "Enter", "off"
  elseif row.kind == "refill" or row.kind == "place_save" or row.kind == "place_delete" or row.kind == "where" then
    return "Enter", "off"
  elseif row.kind == "clean" then
    return M.clean and "ON" or "OFF", M.clean and "on" or "off"
  elseif row.kind == "opacity" then
    return "<  " .. U.opacity .. "%  >"
  end
  return ""
end

local function render()
  local tab = TABS[M.tab]
  local cur = M.cursor[M.tab] or 1
  local lines = {}
  lines[1] = { label = "SR5 Tweak Menu", value = "Cash " .. C.money(M.cash), colour = "title", value_colour = "off" }
  local names = {}
  for i, t in ipairs(TABS) do names[#names + 1] = (i == M.tab) and t.name:upper() or t.name end
  lines[2] = { label = table.concat(names, "   "), colour = "tabs" }
  local first = math.max(1, math.min(cur - math.floor(ROWS / 2), #tab.rows - ROWS + 1))
  for i = 0, ROWS - 1 do
    local row = tab.rows[first + i]
    if row then
      local value, vcol = row_value(row)
      local label = (first + i == cur and "> " or "   ") .. row.label .. (row.cheat and is_spicy(row.cheat) and " *" or "")
      lines[3 + i] = { label = label, value = value, colour = first + i == cur and "cursor" or "row", value_colour = vcol }
    end
  end
  local row = tab.rows[cur]
  -- the help text, wrapped onto two lines
  local help = U.wrap(row and row.help or "", 2)
  lines[ROWS + 3] = { label = help[1] or "", colour = "help" }
  lines[ROWS + 4] = { label = help[2] or "", colour = "help" }
  if M.status_frames > 0 then lines[ROWS + 5] = { label = M.status, colour = M.status_kind }
  else lines[ROWS + 5] = { label = M.clean and "* spicy: your save stays clean (Settings)" or "* spicy: these mark your save", colour = "off" } end
  U.show(lines)
  -- fit again every 10 frames: the game's measure can lag behind new text
  M.renders = (M.renders or 0) + 1
  if M.renders % 10 == 5 then U.refit() end
end

-- ------------------------------------------------------------------ input
local PAD = { UP = 0x1, DOWN = 0x2, LEFT = 0x4, RIGHT = 0x8, BACK = 0x20, LB = 0x100, RB = 0x200, A = 0x1000, B = 0x2000 }
local pad_prev, rb_used = 0, false
local held, held_frames = nil, 0

-- A direction pressed this frame, or repeating while held.
local function repeating(name, down)
  if not down then if held == name then held = nil end return false end
  if held ~= name then held, held_frames = name, 0; return true end
  held_frames = held_frames + 1
  return held_frames > 20 and held_frames % 4 == 0
end

function M.adjust_wset(row, delta)
  row.sel = (row.sel - 1 + delta) % #row.options + 1
  W.set[row.key] = row.options[row.sel][2]
  M.save_tweaks()
  local ok = W.apply()
  say(row.label .. ": " .. row.options[row.sel][1] .. (ok and "" or " (the weapons aren't loaded yet)"), ok and "status" or "warn")
end

function M.adjust_pset(row, delta)
  row.sel = (row.sel - 1 + delta) % #row.options + 1
  P[row.key] = row.options[row.sel][2]
  M.save_tweaks()
  say(row.label .. ": " .. row.options[row.sel][1])
end

function M.adjust_mset(row, delta)
  row.sel = (row.sel - 1 + delta) % #row.options + 1
  local v = row.options[row.sel][2]
  if row.key == "tweaks_paused" then M.pause_tweaks(v) else M[row.key] = v end
  if row.key == "repeat_emote" then M.emote_frames = 0 end
  if row.save_key then M.save_tweaks() end
  say(row.label .. ": " .. row.options[row.sel][1])
end

function M.adjust_carset(row, delta)
  row.sel = (row.sel - 1 + delta) % #row.options + 1
  P.car[row.key] = row.options[row.sel][2]
  M.save_tweaks()
  P.update_car()
  say(row.label .. ": " .. row.options[row.sel][1])
end

function M.adjust_mvset(row, delta)
  row.sel = (row.sel - 1 + delta) % #row.options + 1
  P.move[row.key] = row.options[row.sel][2]
  M.save_tweaks()
  P.update_move()
  say(row.label .. ": " .. row.options[row.sel][1])
end

function M.adjust_wsset(row, delta)
  row.sel = (row.sel - 1 + delta) % #row.options + 1
  WS.set[row.key] = row.options[row.sel][2]
  M.save_tweaks()
  local ok = WS.apply()
  say(row.label .. ": " .. row.options[row.sel][1] .. (ok and "" or " (load into the game first)"), ok and "status" or "warn")
end

function M.adjust_wdset(row, delta)
  row.sel = (row.sel - 1 + delta) % #row.options + 1
  Wd[row.key] = row.options[row.sel][2]
  if row.save_key then M.save_tweaks() end
  say(row.label .. ": " .. row.options[row.sel][1])
end

function M.adjust_opt(row, delta)
  row.sel = (row.sel - 1 + delta) % #row.options + 1
  local v = row.options[row.sel][2]
  local ok, err = wml.game(string.format(row.set, tostring(v)))
  if row.save_key then M.save_tweaks() end
  say(ok and (row.label .. ": " .. row.options[row.sel][1]) or (row.label .. ": " .. tostring(err)), ok and "status" or "warn")
end

function M.adjust_hud(row, delta)
  row.sel = (row.sel - 1 + delta) % #row.options + 1
  local hide = row.options[row.sel][2]
  local ok, err = wml.game("sr5_hud_hide_option(" .. tostring(hide) .. ")")
  M.save_tweaks()
  say(ok and ("HUD " .. (hide and "hidden" or "shown")) or ("Hide HUD: " .. tostring(err)), ok and "status" or "warn")
end

local function move(delta)
  local tab = TABS[M.tab]
  local n = #tab.rows
  if n == 0 then return end
  M.cursor[M.tab] = ((M.cursor[M.tab] or 1) - 1 + delta) % n + 1
  M.pending_confirm = nil
end
local function change_tab(delta) M.tab = (M.tab - 1 + delta) % #TABS + 1 end
local function adjust(delta)
  local row = TABS[M.tab].rows[M.cursor[M.tab] or 1]
  if row and M.stash then M.stash[row] = nil end
  if row and row.kind == "mset" then M.adjust_mset(row, delta)
  elseif row and row.kind == "wset" then M.adjust_wset(row, delta)
  elseif row and row.kind == "pset" then M.adjust_pset(row, delta)
  elseif row and row.kind == "hud" then M.adjust_hud(row, delta)
  elseif row and row.kind == "opt" then M.adjust_opt(row, delta)
  elseif row and row.kind == "wdset" then M.adjust_wdset(row, delta)
  elseif row and row.kind == "wsset" then M.adjust_wsset(row, delta)
  elseif row and row.kind == "mvset" then M.adjust_mvset(row, delta)
  elseif row and row.kind == "carset" then M.adjust_carset(row, delta)
  elseif row and row.kind == "places" then
    if #P.places > 0 then row.sel = (row.sel - 1 + delta) % #P.places + 1 end
  elseif row and row.options then row.sel = (row.sel - 1 + delta) % #row.options + 1
  elseif row and row.kind == "opacity" then U.opacity = math.max(0, math.min(100, U.opacity + delta * 10)); M.save_tweaks() end
end

local function load_cheats()
  if C.loaded then return true end
  if not C.load() then return false end
  prune()
  return true
end

local function ensure_ready()
  if not load_cheats() then say("Load into the game first: the cheats aren't there yet.", "warn"); return false end
  if not U.alive() then
    U.forget()
    if not U.create(LINES) then return false end
  end
  C.refresh()
  M.cash = C.cash()
  -- vehicles, people, homies and emotes, once
  for _, r in ipairs(all_rows()) do
    if r.kind == "deliver" and #r.options == 0 then
      -- the drop-car cheat's table (*(+2F371F0), 0x3B38 an entry, count u16
      -- at +2F371F8): entry +0x10 / +0x14 are the vehicle info's name hash
      local B = wml.base
      local tbl, cnt = wml.read_u64(B + 0x2F371F0), wml.read_u16(B + 0x2F371F8)
      local crc = {}
      for _, v in ipairs(names_of_objects("gml_vehicle_info")) do crc[v.hash] = v.name end
      local count = {}
      for i = 0, cnt - 1 do
        local e = tbl + i * 0x3B38
        local name = crc[wml.read_u32(e + 0x10)] or crc[wml.read_u32(e + 0x14)]
        if name then
          count[name] = (count[name] or 0) + 1
          r.options[#r.options + 1] = { pretty(name), i, name }
        end
      end
      for _, o in ipairs(r.options) do
        if count[o[3]] > 1 then
          count[o[3] .. "#"] = (count[o[3] .. "#"] or 0) + 1
          o[1] = o[1] .. " (" .. count[o[3] .. "#"] .. ")"
        end
      end
      table.sort(r.options, function(a, b) return a[1] < b[1] end)
    elseif r.kind == "person" and #r.options == 0 then
      -- the game's npc variants: each a whole character (body, head, outfit)
      for _, v in ipairs(names_of_objects("npc_variant")) do
        local label = v.name:gsub("^cin_", ""):gsub("_bg$", "")
        r.options[#r.options + 1] = { pretty(label), v.hash }
      end
      table.sort(r.options, function(a, b) return a[1] < b[1] end)
    elseif r.kind == "homie" and #r.options == 0 then
      for _, h in ipairs(names_of("homie_info")) do r.options[#r.options + 1] = { pretty((h:match('"(.*)"') or h):gsub("^homie_", "")), h } end
    elseif (r.kind == "emote" or r.kind == "emote_slot") and #r.options == 0 then
      -- the game's emotes (collectible_emote), listed once and shared
      if not M.emotes then
        M.emotes = {}
        for _, e in ipairs(names_of("collectible_emote")) do M.emotes[#M.emotes + 1] = { pretty((e:match('"(.*)"') or e):gsub("^emote_", "")), e } end
        table.sort(M.emotes, function(a, b) return a[1] < b[1] end)
      end
      for _, o in ipairs(M.emotes) do r.options[#r.options + 1] = o end
      -- a slot row starts on the emote that's on that slot now
      if r.kind == "emote_slot" then
        local ok, now = wml.game("return tostring(emote_get_active_" .. r.slot .. "())")
        for i, o in ipairs(r.options) do if ok and o[2] == now then r.sel = i end end
      end
    end
  end
  -- the game's fast travel points (city_warp_point), once
  for _, r in ipairs(all_rows()) do
    if r.kind == "warp" and #r.options == 0 then
      local first = 1
      while true do
        local res = table.pack(wml.game([[local i, o = 0, {} for _, w in vlib_info_object:ipairs("city_warp_point") do
          i = i + 1 if i >= ]] .. first .. [[ and i < ]] .. (first + 15) .. [[ then o[#o + 1] = tostring(w) end end return i, unpack(o)]]))
        if not res[1] then break end
        for j = 3, res.n do
          local name = res[j]:match('"(.*)"') or res[j]
          local pretty = name:gsub("_ft$", ""):gsub("_", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end)
          r.options[#r.options + 1] = { pretty, res[j] }
        end
        first = first + 15
        if first > res[2] then break end
      end
      table.sort(r.options, function(a, b) return a[1] < b[1] end)
    end
  end
  -- game options: read their current values
  for _, r in ipairs(all_rows()) do
    if r.kind == "opt" and r.get and not r.read then
      local ok, v = wml.game("return " .. r.get)
      if ok and type(v) == "number" then
        r.read = true
        local found
        for i, o in ipairs(r.options) do if type(o[2]) == "number" and math.abs(o[2] - v) < 1e-3 then found = i end end
        if found then r.sel = found
        else table.insert(r.options, 1, { "Game's (" .. string.format("%g", math.floor(v * 100 + 0.5) / 100) .. ")", v }); r.sel = 1 end
      end
    end
    -- saved settings that are game calls (Freeze time): apply once
    if r.kind == "opt" and r.save_key and not r.get and not r.applied and r.sel ~= 1 then
      r.applied = true
      wml.game(string.format(r.set, tostring(r.options[r.sel][2])))
    end
  end
  -- a saved Hide HUD, once per session
  if not M.hud_restored then
    M.hud_restored = true
    for _, r in ipairs(all_rows()) do
      if r.kind == "hud" and r.options[r.sel][2] then wml.game("sr5_hud_hide_option(true)") end
    end
  end
  return true
end

local frame = 0
function M.update()
  frame = frame + 1
  local buttons = wml.pad() or 0
  local pressed = buttons & ~pad_prev
  -- RB alone (pressed and let go without D-pad Down) changes tab.
  local rb_released = (pad_prev & PAD.RB) ~= 0 and (buttons & PAD.RB) == 0
  pad_prev = buttons
  if (pressed & PAD.RB) ~= 0 then rb_used = false end

  -- Open or close: F5, or RB held + D-pad Down.
  local combo = (buttons & PAD.RB ~= 0) and (pressed & PAD.DOWN ~= 0)
  if combo then rb_used = true end
  if wml.key_pressed(OPEN_KEY) or combo then
    if M.open then M.open = false
    elseif ensure_ready() then M.open = true; frame = 0 end
  end

  -- Keep the save clean, open or not (cheats can come from the phone too).
  if not C.loaded and frame % 300 == 0 then load_cheats() end
  if W.loaded and frame % 300 == 150 and W.any_on() then W.check() end
  -- saved weapon settings: apply once the game's weapon data is there
  if not W.loaded and W.any_on() and C.loaded and frame % 300 == 200 then W.apply() end
  if not WS.loaded and WS.any_on() and C.loaded and frame % 300 == 250 then WS.apply() end
  -- live copies the game rebuilds (wingsuit setup, respawn): keep them set
  if C.loaded and frame % 30 == 15 then
    if WS.any_on() or M.ws_was_on then WS.update_copy(P); M.ws_was_on = WS.any_on() end
    if P.move_on() or M.move_was_on then P.update_move(); M.move_was_on = P.move_on() end
  end
  if C.loaded and frame % 30 == 20 and (P.car_on() or M.car_was_on) then P.update_car(); M.car_was_on = P.car_on()
  end
  if P.keep_repaired and C.loaded and frame % 60 == 30 and C.by_name.vehicle_health then C.activate("vehicle_health") end
  if Wd.any_on() then Wd.update(frame) end
  -- Never wanted: the game's clear cheats as soon as there's notoriety
  if (M.wanted_wait or 0) > 0 then M.wanted_wait = M.wanted_wait - 1 end
  local wanted = Wd.never_wanted and C.loaded and frame % 30 == 5 and (M.wanted_wait or 0) == 0 and Wd.wanted()
  if wanted then
    if not M.factions then load_factions() end
    local clear = {}
    for _, hash in ipairs(wanted) do
      local f = M.factions[hash]
      if f and (Wd.never_wanted == "all" or Wd.never_wanted == f.group) then clear[f.cheat] = true
      elseif not f and Wd.never_wanted == "all" then
        for _, n in ipairs({ "clear_police", "clear_idols", "clear_marshal", "clear_panteros" }) do clear[n] = true end
      end
    end
    for name in pairs(clear) do
      local c = C.by_name[name]
      if c then
        if c.spicy then C.allow_spicy(); M.spicy_hold = 120 end
        C.activate(name)
        M.wanted_wait = 120
      end
    end
  end
  -- Max notoriety: one raise every 45 frames
  if M.raise and C.loaded then
    M.raise.wait = M.raise.wait - 1
    if M.raise.wait <= 0 then
      fire(M.raise.name, nil, M.raise.label .. " raised")
      M.raise.left, M.raise.wait = M.raise.left - 1, 45
      if M.raise.left <= 0 then M.raise = nil end
    end
  end
  -- Repeat emote
  if M.repeat_emote and M.emote_pick and C.loaded then
    M.emote_frames = (M.emote_frames or 0) + 1
    if M.emote_frames >= M.repeat_emote then M.emote_frames = 0; play_emote(M.emote_pick) end
  end
  -- Hold Back opens the menu: held for 45 frames
  if M.hold_back and (buttons & PAD.BACK ~= 0) then
    M.back_frames = (M.back_frames or 0) + 1
    if M.back_frames == 45 then
      if M.open then M.open = false elseif ensure_ready() then M.open = true; frame = 0 end
    end
  else
    M.back_frames = 0
  end
  if wml.auto_fire and P.full_auto ~= M.auto_fire_was then
    wml.auto_fire(P.full_auto and true or false, P.full_auto or 70)
    M.auto_fire_was = P.full_auto
  end
  if P.god or P.health_mult ~= 1 or M.player_was_on then
    P.update()
    M.player_was_on = P.god or P.health_mult ~= 1
  end
  if C.loaded then
    if M.spicy_hold > 0 then M.spicy_hold = M.spicy_hold - 1 end
    if frame % 60 == 0 and not M.open then C.refresh() end
    if M.clean and frame % 15 == 0 then
      local clear = M.spicy_hold == 0 and not C.spicy_active()
      if C.keep_clean(clear) and not M.told_clean then
        M.told_clean = true
        wml.log("cleared the save's cheated mark")
      end
    end
  end

  -- The menu's keys and the controller's buttons don't reach the game while it's open.
  if M.open ~= M.blocking and wml.block_input then
    wml.block_input(M.open, M.open)
    M.blocking = M.open
  end

  if not M.open then
    if U.lines > 0 and not M.hidden then U.show(nil); M.hidden = true end
    return
  end
  M.hidden = false

  if repeating("up", wml.key_down("UP") or (buttons & PAD.UP ~= 0)) then move(-1) end
  if repeating("down", wml.key_down("DOWN") or ((buttons & PAD.DOWN ~= 0) and (buttons & PAD.RB == 0))) then move(1) end
  if repeating("left", wml.key_down("LEFT") or (buttons & PAD.LEFT ~= 0)) then adjust(-1) end
  if repeating("right", wml.key_down("RIGHT") or (buttons & PAD.RIGHT ~= 0)) then adjust(1) end
  if wml.key_pressed("PAGEUP") or (pressed & PAD.LB ~= 0) then change_tab(-1) end
  if wml.key_pressed("PAGEDOWN") or (rb_released and not rb_used) then change_tab(1) end
  if wml.key_pressed("ENTER") or (pressed & PAD.A ~= 0) then
    local row = TABS[M.tab].rows[M.cursor[M.tab] or 1]
    if row then select_row(row) end
  end
  if wml.key_pressed("BACKSPACE") or (pressed & PAD.B ~= 0) then M.open = false end

  if frame % 30 == 0 then C.refresh(); M.cash = C.cash() end
  if M.cash_check then
    M.cash_check.frames = M.cash_check.frames - 1
    if M.cash_check.frames <= 0 then
      local now = C.cash()
      local before = M.cash_check.before
      M.cash_check, M.cash = nil, now
      if now and now ~= before then say("Give cash: +" .. C.money(now - before) .. " (now " .. C.money(now) .. ")")
      else say("Give cash: no change yet (" .. C.money(now) .. ")", "warn") end
    end
  end
  if frame % 120 == 0 and not U.alive() then
    U.forget()
    if not U.create(LINES) then M.open = false; return end
  end
  if M.status_frames > 0 then M.status_frames = M.status_frames - 1 end
  if M.open then render() else U.show(nil); M.hidden = true end
end

return M
