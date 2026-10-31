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
local Cam = require("camera")
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
-- A choice of game calls: Left/Right picks, Enter runs the picked code.
local function gchoice(label, help, options) return { kind = "gchoice", label = label, help = help, options = options, sel = 1 } end
local function voices()
  local out = {}
  for _, v in ipairs({ "player_f1", "player_f2", "player_f3", "player_f4", "player_m1", "player_m2", "player_m3", "player_m4" }) do
    local label = (v:find("_f") and "Female " or "Male ") .. v:sub(-1)
    out[#out + 1] = { label, "customization_set_avatar_persona('" .. v .. "') return '" .. label .. "'" }
  end
  return out
end
local function award(what, amounts)
  local out = {}
  for _, a in ipairs(amounts) do out[#out + 1] = { a[1], "gml_collectibles_award(string_crc('" .. what .. "'), " .. a[2] .. ") return '" .. a[1] .. " given'" } end
  return out
end
-- A wingsuit setting (wingsuit.lua), applied at once.
local function wsset(key, label, help, options) return { kind = "wsset", key = key, label = label, help = help, options = options, sel = 1, save_key = "wingsuit." .. key } end
-- A weapon setting: Left/Right (or Enter) changes it and applies it at once.
local function wset(key, label, help, options) return { kind = "wset", key = key, label = label, help = help, options = options, sel = 1, save_key = "weapons." .. key } end

-- From the game's tables: every HQ prop by the size of spot it's meant for, props made
-- for spawning, and every song.
local CRIB_PROPS = {
  { "Huge: Boot hill head cart", "crib-placeable-boot-hill-head-cart_01a" },
  { "Huge: Boot hill medicine cart", "crib-placeable-boot-hill-medicine-cart_01a" },
  { "Huge: Bottle liquor", "crib-placeable-bottle-liquor_08a" },
  { "Huge: Cactus cowboy", "crib-placeable-cactus-cowboy_01a" },
  { "Huge: Dustfaire paper airplane", "crib-placeable-dustfaire-paper-airplane_01a" },
  { "Huge: Electric chicken", "crib-placeable-electric-chicken_01a" },
  { "Huge: Fabulous egg", "crib-placeable-fabulous-egg_01d" },
  { "Huge: Owl windmill installation", "crib-placeable-owl-windmill-installation_01a" },
  { "Huge: Prop xmas tree", "crib-placeable-prop_xmas-tree_01" },
  { "Huge: Radio station tower", "crib-placeable-radio-station-tower_01a" },
  { "Huge: Sign golf course sculpture", "crib-placeable-sign-golf-course-sculpture_01a" },
  { "Huge: Sign ice cream stand", "crib-placeable-sign_ice-cream-stand_01a" },
  { "Huge: Spooky tree haunted hotel evil", "crib-placeable-spooky-tree-haunted-hotel-evil_01b" },
  { "Huge: Statue atlas", "crib-placeable-statue-atlas_01a" },
  { "Huge: Statue eagle", "crib-placeable-statue-eagle_01a" },
  { "Huge: Statue saints", "crib-placeable-statue-saints_02a" },
  { "Huge: Talltales jim rob", "crib-placeable-talltales-jim-rob_01a" },
  { "Huge: Thunderpump lighting bolt arrow", "crib-placeable-thunderpump-lighting-bolt-arrow_01a" },
  { "Huge: Triceratops skull", "crib-placeable-triceratops-skull_01a" },
  { "Huge: Twin coyote sculpture", "crib-placeable-twin-coyote-sculpture_01a" },
  { "Huge: Weird west rabbit singer", "crib-placeable-weird-west-rabbit-singer_01a" },
  { "Huge: Weird west tirepede", "crib-placeable-weird-west-tirepede_01a" },
  { "Huge: Weird west vulture tree", "crib-placeable-weird-west-vulture-tree_01a" },
  { "Huge: Western chuckwagon", "crib-placeable-western-chuckwagon" },
  { "Huge: Western novelty cowboy hat", "crib-placeable-western-novelty-cowboy-hat_01a" },
  { "Huge: Western oversized cowboy boot", "crib-placeable-western-oversized-cowboy-boot_01a" },
  { "Huge: Windmill dutch", "crib-placeable-windmill-dutch_01a" },
  { "Huge: Zombie bear", "crib-placeable-zombie-bear_01a" },
  { "Large: Armadillo gold", "crib-placeable-armadillo-gold_01a" },
  { "Large: Banana head carrot", "crib-placeable-banana-head-carrot_01a" },
  { "Large: Big football helmet statue gold", "crib-placeable-big-football-helmet-statue-gold_01a" },
  { "Large: Boot hill coffin", "crib-placeable-boot-hill-coffin_01a" },
  { "Large: Boot hill ketchumbud", "crib-placeable-boot-hill-ketchumbud_01a" },
  { "Large: Boot hill loot chest", "crib-placeable-boot-hill-loot-chest_01a" },
  { "Large: Boot hill medicine cart horse", "crib-placeable-boot-hill-medicine-cart-horse_01a" },
  { "Large: Bowling art", "crib-placeable-bowling-art_01a" },
  { "Large: Cactus jack", "crib-placeable-cactus-jack_01a" },
  { "Large: Casino shoe light sign", "crib-placeable-casino-shoe-light-sign_01a" },
  { "Large: Cemetery monument", "crib-placeable-cemetery-monument_01a" },
  { "Large: Crossing gate", "crib-placeable-crossing-gate_01a" },
  { "Large: Cutting edge lab tank", "crib-placeable-cutting-edge-lab-tank_01a" },
  { "Large: Disc golf basket goal", "crib-placeable-disc-golf-basket-goal_01a" },
  { "Large: Drone marshall", "crib-placeable-drone-marshall_01a" },
  { "Large: Financial art", "crib-placeable-financial-art_01a" },
  { "Large: Financial art", "crib-placeable-financial_art_04a" },
  { "Large: Fountain city hall", "crib-placeable-fountain-city-hall_01a" },
  { "Large: Games chess piece knight", "crib-placeable-games-chess-piece-knight_01a" },
  { "Large: Games d20 dice", "crib-placeable-games-d20-dice_01a" },
  { "Large: Gatling gun tripod", "crib-placeable-gatling-gun-tripod_01a" },
  { "Large: Giant spider", "crib-placeable-giant-spider_01a" },
  { "Large: Guitar guy", "crib-placeable-guitar-guy_01a" },
  { "Large: Interstellar phone booth", "crib-placeable-interstellar-phone-booth_01a" },
  { "Large: Jail urinal", "crib-placeable-jail-urinal_01a" },
  { "Large: Lets pretend mannequin", "crib-placeable-lets-pretend-mannequin_05a" },
  { "Large: Microbrewery topiary pigs", "crib-placeable-microbrewery-topiary-pigs_01a" },
  { "Large: Mine cart", "crib-placeable-mine-cart_01a" },
  { "Large: Prop camera movie", "crib-placeable-prop_camera-movie_01a" },
  { "Large: Prop shark statue", "crib-placeable-prop_shark-statue_01a" },
  { "Large: Prop statue silver siren", "crib-placeable-prop_statue_silver-siren_01a" },
  { "Large: Rabbit statue", "crib-placeable-rabbit-statue_01a" },
  { "Large: Rack bike sculpture", "crib-placeable-rack-bike-sculpture_01a" },
  { "Large: Red faction brewery tank", "crib-placeable-red-faction-brewery-tank_01a" },
  { "Large: Rodeo feather", "crib-placeable-rodeo-feather_02a" },
  { "Large: Rs gas pump saints", "crib-placeable-rs-gas-pump_saints" },
  { "Large: Sculpture mercado metal jackalope", "crib-placeable-sculpture-mercado-metal-jackalope_01a" },
  { "Large: Sculpture school compass", "crib-placeable-sculpture_school-compass_01a" },
  { "Large: Statue deer", "crib-placeable-statue-deer_01a" },
  { "Large: Storm giant bones", "crib-placeable-storm-giant-bones_01a" },
  { "Large: Strange santo spur statue", "crib-placeable-strange-santo-spur-statue" },
  { "Large: Swan float", "crib-placeable-swan-float_01a" },
  { "Large: Swole hole arm", "crib-placeable-swole-hole-arm_01a" },
  { "Large: Talltales jackalope", "crib-placeable-talltales-jackalope_01a" },
  { "Large: Talltales saddle nuke", "crib-placeable-talltales-saddle-nuke_01a" },
  { "Large: Talltales wastelander throne", "crib-placeable-talltales-wastelander-throne_01a" },
  { "Large: Toy mechaburger", "crib-placeable-toy-mechaburger_01a" },
  { "Large: Turdis", "crib-placeable-turdis" },
  { "Large: Weird west apple", "crib-placeable-weird-west-apple_01a" },
  { "Large: Weird west bug driver", "crib-placeable-weird-west-bug-driver_01a" },
  { "Large: Weird west cow", "crib-placeable-weird-west-cow_01a" },
  { "Large: Western cowboy horse sculpture", "crib-placeable-western-cowboy-horse-sculpture_01a" },
  { "Large: Western golden cannon", "crib-placeable-western-golden-cannon" },
  { "Large: Western piano", "crib-placeable-western-piano_01a" },
  { "Large: Western saddle bar stool", "crib-placeable-western-saddle-bar-stool_01a" },
  { "Large: Wing chun wooden dummy", "crib-placeable-wing-chun-wooden-dummy_01a" },
  { "Large: Xmas tree pole", "crib-placeable-xmas-tree-pole_01a" },
  { "Large: Toilet portable", "crib-placeable_toilet-portable_01a" },
  { "Normal: Boat steering wheel", "crib-placeable-boat-steering-wheel_02a" },
  { "Normal: Boat anchor", "crib-placeable-boat_anchor_01a" },
  { "Normal: Boot hill bear", "crib-placeable-boot-hill-bear_01a" },
  { "Normal: Boot hill coin", "crib-placeable-boot-hill-coin_01a" },
  { "Normal: Boot hill ketchum cane", "crib-placeable-boot-hill-ketchum-cane_01a" },
  { "Normal: Boot hill puppet", "crib-placeable-boot-hill-puppet_01a" },
  { "Normal: Boot hill puppet", "crib-placeable-boot-hill-puppet_02a" },
  { "Normal: Boot hill rabbit", "crib-placeable-boot-hill-rabbit_01a" },
  { "Normal: Cinematic stand knife", "crib-placeable-cinematic-stand-knife_02a" },
  { "Normal: Crown reward", "crib-placeable-crown-reward_01a" },
  { "Normal: Dreidel", "crib-placeable-dreidel_01a" },
  { "Normal: Drug pallet", "crib-placeable-drug-pallet_01a" },
  { "Normal: Financial art", "crib-placeable-financial_art_07a" },
  { "Normal: Flamingo saints", "crib-placeable-flamingo-saints_01a" },
  { "Normal: Game marble", "crib-placeable-game-marble_01a" },
  { "Normal: Go cart trophy 01a", "crib-placeable-go-cart-trophy-01a" },
  { "Normal: Hanukkah candle", "crib-placeable-hanukkah-candle_01a" },
  { "Normal: Hover board", "crib-placeable-hover-board_01a" },
  { "Normal: Keg beer painted", "crib-placeable-keg-beer-painted_01a" },
  { "Normal: Kwanzaa candle", "crib-placeable-kwanzaa-candle_01a" },
  { "Normal: Model plane", "crib-placeable-model-plane_01a" },
  { "Normal: Monolith silver", "crib-placeable-monolith-silver_01a" },
  { "Normal: Pedestal planet saints", "crib-placeable-pedestal-planet-saints_01a" },
  { "Normal: Poker chip stack", "crib-placeable-poker-chip-stack_01a" },
  { "Normal: Saving roll", "crib-placeable-saving-roll_01a" },
  { "Normal: Sculpture mercado flower", "crib-placeable-sculpture_mercado-flower_01a" },
  { "Normal: Space ship", "crib-placeable-space-ship_01a" },
  { "Normal: Spooky black cauldron", "crib-placeable-spooky-black-cauldron_01b" },
  { "Normal: Spooky demonic angel", "crib-placeable-spooky-demonic-angel_01b" },
  { "Normal: Statue cutout scorpion", "crib-placeable-statue-cutout-scorpion_01a" },
  { "Normal: Statue ramparts pig", "crib-placeable-statue-ramparts-pig_01a" },
  { "Normal: Talltales cabbit", "crib-placeable-talltales-cabbit_01a" },
  { "Normal: Talltales cactus santa", "crib-placeable-talltales-cactus-santa_01a" },
  { "Normal: Talltales singing bush", "crib-placeable-talltales-singing-bush_01a" },
  { "Normal: Talltales thors hammer", "crib-placeable-talltales-thors-hammer_01a" },
  { "Normal: Tank chemical", "crib-placeable-tank-chemical_01a" },
  { "Normal: Toilet golden", "crib-placeable-toilet-golden_01a" },
  { "Normal: Trophy hummingbird codex", "crib-placeable-trophy-hummingbird-codex_01a" },
  { "Normal: Universe diorama", "crib-placeable-universe-diorama_01a" },
  { "Normal: Vase", "crib-placeable-vase_02a" },
  { "Normal: Western centerpiece", "crib-placeable-western-centerpiece_01b" },
  { "Normal: Western oversized bullet", "crib-placeable-western-oversized-bullet_01a" },
  { "Normal: Xmas tree twig", "crib-placeable-xmas-tree-twig_01a" },
  { "Wall: Boot hill reward wall", "crib-placeable-boot-hill-reward-wall_01a" },
  { "Wall: Boot hill reward wall", "crib-placeable-boot-hill-reward-wall_02a" },
  { "Wall: Casino sign queen", "crib-placeable-casino-sign-queen_01a" },
  { "Wall: Casino sign varmint", "crib-placeable-casino-sign-varmint_01a" },
  { "Wall: El bar visual", "crib-placeable-el-bar-visual_01a" },
  { "Wall: Fantasy map board", "crib-placeable-fantasy-map-board_01a" },
  { "Wall: Fox tails", "crib-placeable-fox-tails_01a" },
  { "Wall: Shady oaks", "crib-placeable-shady-oaks_01a" },
  { "Wall: Sign building commercial king", "crib-placeable-sign-building_commercial_king_01a" },
  { "Wall: Sign joe cola", "crib-placeable-sign-joe-cola_01a" },
  { "Wall: Sign neon tipsy lizard watering hole", "crib-placeable-sign-neon_tipsy_lizard_watering_hole_01a" },
  { "Wall: Sign repo yard", "crib-placeable-sign-repo-yard_01a" },
  { "Wall: Sign roadside route66 shield sculpture", "crib-placeable-sign-roadside-route66-shield-sculpture_01a" },
  { "Wall: Spooky clown painting", "crib-placeable-spooky-clown-painting_01b" },
  { "Wall: Talltales chalupacabra sign", "crib-placeable-talltales-chalupacabra-sign_01a" },
  { "Wall: Wall relief herding cats", "crib-placeable-wall-relief-herding-cats_01a" },
  { "Wall: Western bear rug", "crib-placeable-western-bear-rug_01a" },
  { "Wall: Western cowboy silhouette", "crib-placeable-western-cowboy-silhouette_01a" },
  { "Wall: Western wanted poster", "crib-placeable-western-wanted-poster_01a" }
}
local SPAWN_PROPS = {
  { "World: Chaos explosive barrel", "prop_chaos-explosive-barrel_01b" },
  { "World: Chaos toxic barrel", "prop_chaos-toxic-barrel_01a" },
  { "World: Chaos fire barrel", "prop_chaos-fire-barrel_01a" },
  { "World: Barrel stack dynamic", "prop_barrel_stack_dynamic" },
  { "World: Detonator bomb", "prop_detonator-bomb_01a" },
  { "World: Barrel toxic 01a spawn", "prop_barrel-toxic_01a_spawn" },
  { "World: Ct bond giant penny spawnable tetherable rideable", "prop_ct_bond_giant_penny_spawnable_tetherable_rideable" },
  { "World: Lp02 paint balloon 01a spawnable", "prop_lp02-paint-balloon_01a_spawnable" },
  { "World: Fireworks cake launcher 01a spawn", "fireworks_cake_launcher_01a_spawn" },
  { "World: Atm machine 01a spawnable", "prop_atm-machine_01a_spawnable" },
  { "World: Campfire spawnable", "prop_campfire-spawnable_02a" },
  { "World: Camp chair spawnable", "prop_camp-chair-spawnable_01a" },
  { "World: Car 2dr muscle spawnable", "prop_car_2dr_muscle-spawnable_01a" },
  { "World: Speaker large 01a spawn", "prop_speaker-large_01a_spawn" },
  { "World: Boombox spawnable", "prop_boombox-spawnable_01a" },
  { "World: Egg golden", "prop_egg-golden_01a" },
  { "World: Coffin loot air drop boot hill", "prop_coffin-loot-air-drop-boot-hill_01a" },
  { "World: Shooting gallery target ufo", "location_challenge_shooting_gallery_target_ufo" },
  { "World: Roadblock construction ramp", "roadblock_construction_ramp_01" },
  { "World: Roadblock idols ramp", "roadblock_idols_ramp_01a" },
  { "World: Laundromat rodeo ramp", "laundromat_rodeo_ramp_01" },
  { "World: Boot hill act doc ketchum stage", "boot_hill_act_doc_ketchum_stage" },
  { "World: Heist rodeo stage scene", "heist_rodeo_stage_scene_01" },
  { "Huge: Boot hill head cart", "crib-placeable-boot-hill-head-cart_01a" },
  { "Huge: Boot hill medicine cart", "crib-placeable-boot-hill-medicine-cart_01a" },
  { "Huge: Bottle liquor", "crib-placeable-bottle-liquor_08a" },
  { "Huge: Cactus cowboy", "crib-placeable-cactus-cowboy_01a" },
  { "Huge: Dustfaire paper airplane", "crib-placeable-dustfaire-paper-airplane_01a" },
  { "Huge: Electric chicken", "crib-placeable-electric-chicken_01a" },
  { "Huge: Fabulous egg", "crib-placeable-fabulous-egg_01d" },
  { "Huge: Owl windmill installation", "crib-placeable-owl-windmill-installation_01a" },
  { "Huge: Prop xmas tree", "crib-placeable-prop_xmas-tree_01" },
  { "Huge: Radio station tower", "crib-placeable-radio-station-tower_01a" },
  { "Huge: Sign golf course sculpture", "crib-placeable-sign-golf-course-sculpture_01a" },
  { "Huge: Sign ice cream stand", "crib-placeable-sign_ice-cream-stand_01a" },
  { "Huge: Spooky tree haunted hotel evil", "crib-placeable-spooky-tree-haunted-hotel-evil_01b" },
  { "Huge: Statue atlas", "crib-placeable-statue-atlas_01a" },
  { "Huge: Statue eagle", "crib-placeable-statue-eagle_01a" },
  { "Huge: Statue saints", "crib-placeable-statue-saints_02a" },
  { "Huge: Talltales jim rob", "crib-placeable-talltales-jim-rob_01a" },
  { "Huge: Thunderpump lighting bolt arrow", "crib-placeable-thunderpump-lighting-bolt-arrow_01a" },
  { "Huge: Triceratops skull", "crib-placeable-triceratops-skull_01a" },
  { "Huge: Twin coyote sculpture", "crib-placeable-twin-coyote-sculpture_01a" },
  { "Huge: Weird west rabbit singer", "crib-placeable-weird-west-rabbit-singer_01a" },
  { "Huge: Weird west tirepede", "crib-placeable-weird-west-tirepede_01a" },
  { "Huge: Weird west vulture tree", "crib-placeable-weird-west-vulture-tree_01a" },
  { "Huge: Western chuckwagon", "crib-placeable-western-chuckwagon" },
  { "Huge: Western novelty cowboy hat", "crib-placeable-western-novelty-cowboy-hat_01a" },
  { "Huge: Western oversized cowboy boot", "crib-placeable-western-oversized-cowboy-boot_01a" },
  { "Huge: Windmill dutch", "crib-placeable-windmill-dutch_01a" },
  { "Huge: Zombie bear", "crib-placeable-zombie-bear_01a" },
  { "Large: Armadillo gold", "crib-placeable-armadillo-gold_01a" },
  { "Large: Banana head carrot", "crib-placeable-banana-head-carrot_01a" },
  { "Large: Big football helmet statue gold", "crib-placeable-big-football-helmet-statue-gold_01a" },
  { "Large: Boot hill coffin", "crib-placeable-boot-hill-coffin_01a" },
  { "Large: Boot hill ketchumbud", "crib-placeable-boot-hill-ketchumbud_01a" },
  { "Large: Boot hill loot chest", "crib-placeable-boot-hill-loot-chest_01a" },
  { "Large: Boot hill medicine cart horse", "crib-placeable-boot-hill-medicine-cart-horse_01a" },
  { "Large: Bowling art", "crib-placeable-bowling-art_01a" },
  { "Large: Cactus jack", "crib-placeable-cactus-jack_01a" },
  { "Large: Casino shoe light sign", "crib-placeable-casino-shoe-light-sign_01a" },
  { "Large: Cemetery monument", "crib-placeable-cemetery-monument_01a" },
  { "Large: Crossing gate", "crib-placeable-crossing-gate_01a" },
  { "Large: Cutting edge lab tank", "crib-placeable-cutting-edge-lab-tank_01a" },
  { "Large: Disc golf basket goal", "crib-placeable-disc-golf-basket-goal_01a" },
  { "Large: Drone marshall", "crib-placeable-drone-marshall_01a" },
  { "Large: Financial art", "crib-placeable-financial-art_01a" },
  { "Large: Financial art", "crib-placeable-financial_art_04a" },
  { "Large: Fountain city hall", "crib-placeable-fountain-city-hall_01a" },
  { "Large: Games chess piece knight", "crib-placeable-games-chess-piece-knight_01a" },
  { "Large: Games d20 dice", "crib-placeable-games-d20-dice_01a" },
  { "Large: Gatling gun tripod", "crib-placeable-gatling-gun-tripod_01a" },
  { "Large: Giant spider", "crib-placeable-giant-spider_01a" },
  { "Large: Guitar guy", "crib-placeable-guitar-guy_01a" },
  { "Large: Interstellar phone booth", "crib-placeable-interstellar-phone-booth_01a" },
  { "Large: Jail urinal", "crib-placeable-jail-urinal_01a" },
  { "Large: Lets pretend mannequin", "crib-placeable-lets-pretend-mannequin_05a" },
  { "Large: Microbrewery topiary pigs", "crib-placeable-microbrewery-topiary-pigs_01a" },
  { "Large: Mine cart", "crib-placeable-mine-cart_01a" },
  { "Large: Prop camera movie", "crib-placeable-prop_camera-movie_01a" },
  { "Large: Prop shark statue", "crib-placeable-prop_shark-statue_01a" },
  { "Large: Prop statue silver siren", "crib-placeable-prop_statue_silver-siren_01a" },
  { "Large: Rabbit statue", "crib-placeable-rabbit-statue_01a" },
  { "Large: Rack bike sculpture", "crib-placeable-rack-bike-sculpture_01a" },
  { "Large: Red faction brewery tank", "crib-placeable-red-faction-brewery-tank_01a" },
  { "Large: Rodeo feather", "crib-placeable-rodeo-feather_02a" },
  { "Large: Rs gas pump saints", "crib-placeable-rs-gas-pump_saints" },
  { "Large: Sculpture mercado metal jackalope", "crib-placeable-sculpture-mercado-metal-jackalope_01a" },
  { "Large: Sculpture school compass", "crib-placeable-sculpture_school-compass_01a" },
  { "Large: Statue deer", "crib-placeable-statue-deer_01a" },
  { "Large: Storm giant bones", "crib-placeable-storm-giant-bones_01a" },
  { "Large: Strange santo spur statue", "crib-placeable-strange-santo-spur-statue" },
  { "Large: Swan float", "crib-placeable-swan-float_01a" },
  { "Large: Swole hole arm", "crib-placeable-swole-hole-arm_01a" },
  { "Large: Talltales jackalope", "crib-placeable-talltales-jackalope_01a" },
  { "Large: Talltales saddle nuke", "crib-placeable-talltales-saddle-nuke_01a" },
  { "Large: Talltales wastelander throne", "crib-placeable-talltales-wastelander-throne_01a" },
  { "Large: Toy mechaburger", "crib-placeable-toy-mechaburger_01a" },
  { "Large: Turdis", "crib-placeable-turdis" },
  { "Large: Weird west apple", "crib-placeable-weird-west-apple_01a" },
  { "Large: Weird west bug driver", "crib-placeable-weird-west-bug-driver_01a" },
  { "Large: Weird west cow", "crib-placeable-weird-west-cow_01a" },
  { "Large: Western cowboy horse sculpture", "crib-placeable-western-cowboy-horse-sculpture_01a" },
  { "Large: Western golden cannon", "crib-placeable-western-golden-cannon" },
  { "Large: Western piano", "crib-placeable-western-piano_01a" },
  { "Large: Western saddle bar stool", "crib-placeable-western-saddle-bar-stool_01a" },
  { "Large: Wing chun wooden dummy", "crib-placeable-wing-chun-wooden-dummy_01a" },
  { "Large: Xmas tree pole", "crib-placeable-xmas-tree-pole_01a" },
  { "Large: Toilet portable", "crib-placeable_toilet-portable_01a" },
  { "Normal: Boat steering wheel", "crib-placeable-boat-steering-wheel_02a" },
  { "Normal: Boat anchor", "crib-placeable-boat_anchor_01a" },
  { "Normal: Boot hill bear", "crib-placeable-boot-hill-bear_01a" },
  { "Normal: Boot hill coin", "crib-placeable-boot-hill-coin_01a" },
  { "Normal: Boot hill ketchum cane", "crib-placeable-boot-hill-ketchum-cane_01a" },
  { "Normal: Boot hill puppet", "crib-placeable-boot-hill-puppet_01a" },
  { "Normal: Boot hill puppet", "crib-placeable-boot-hill-puppet_02a" },
  { "Normal: Boot hill rabbit", "crib-placeable-boot-hill-rabbit_01a" },
  { "Normal: Cinematic stand knife", "crib-placeable-cinematic-stand-knife_02a" },
  { "Normal: Crown reward", "crib-placeable-crown-reward_01a" },
  { "Normal: Dreidel", "crib-placeable-dreidel_01a" },
  { "Normal: Drug pallet", "crib-placeable-drug-pallet_01a" },
  { "Normal: Financial art", "crib-placeable-financial_art_07a" },
  { "Normal: Flamingo saints", "crib-placeable-flamingo-saints_01a" },
  { "Normal: Game marble", "crib-placeable-game-marble_01a" },
  { "Normal: Go cart trophy 01a", "crib-placeable-go-cart-trophy-01a" },
  { "Normal: Hanukkah candle", "crib-placeable-hanukkah-candle_01a" },
  { "Normal: Hover board", "crib-placeable-hover-board_01a" },
  { "Normal: Keg beer painted", "crib-placeable-keg-beer-painted_01a" },
  { "Normal: Kwanzaa candle", "crib-placeable-kwanzaa-candle_01a" },
  { "Normal: Model plane", "crib-placeable-model-plane_01a" },
  { "Normal: Monolith silver", "crib-placeable-monolith-silver_01a" },
  { "Normal: Pedestal planet saints", "crib-placeable-pedestal-planet-saints_01a" },
  { "Normal: Poker chip stack", "crib-placeable-poker-chip-stack_01a" },
  { "Normal: Saving roll", "crib-placeable-saving-roll_01a" },
  { "Normal: Sculpture mercado flower", "crib-placeable-sculpture_mercado-flower_01a" },
  { "Normal: Space ship", "crib-placeable-space-ship_01a" },
  { "Normal: Spooky black cauldron", "crib-placeable-spooky-black-cauldron_01b" },
  { "Normal: Spooky demonic angel", "crib-placeable-spooky-demonic-angel_01b" },
  { "Normal: Statue cutout scorpion", "crib-placeable-statue-cutout-scorpion_01a" },
  { "Normal: Statue ramparts pig", "crib-placeable-statue-ramparts-pig_01a" },
  { "Normal: Talltales cabbit", "crib-placeable-talltales-cabbit_01a" },
  { "Normal: Talltales cactus santa", "crib-placeable-talltales-cactus-santa_01a" },
  { "Normal: Talltales singing bush", "crib-placeable-talltales-singing-bush_01a" },
  { "Normal: Talltales thors hammer", "crib-placeable-talltales-thors-hammer_01a" },
  { "Normal: Tank chemical", "crib-placeable-tank-chemical_01a" },
  { "Normal: Toilet golden", "crib-placeable-toilet-golden_01a" },
  { "Normal: Trophy hummingbird codex", "crib-placeable-trophy-hummingbird-codex_01a" },
  { "Normal: Universe diorama", "crib-placeable-universe-diorama_01a" },
  { "Normal: Vase", "crib-placeable-vase_02a" },
  { "Normal: Western centerpiece", "crib-placeable-western-centerpiece_01b" },
  { "Normal: Western oversized bullet", "crib-placeable-western-oversized-bullet_01a" },
  { "Normal: Xmas tree twig", "crib-placeable-xmas-tree-twig_01a" },
  { "Wall: Boot hill reward wall", "crib-placeable-boot-hill-reward-wall_01a" },
  { "Wall: Boot hill reward wall", "crib-placeable-boot-hill-reward-wall_02a" },
  { "Wall: Casino sign queen", "crib-placeable-casino-sign-queen_01a" },
  { "Wall: Casino sign varmint", "crib-placeable-casino-sign-varmint_01a" },
  { "Wall: El bar visual", "crib-placeable-el-bar-visual_01a" },
  { "Wall: Fantasy map board", "crib-placeable-fantasy-map-board_01a" },
  { "Wall: Fox tails", "crib-placeable-fox-tails_01a" },
  { "Wall: Shady oaks", "crib-placeable-shady-oaks_01a" },
  { "Wall: Sign building commercial king", "crib-placeable-sign-building_commercial_king_01a" },
  { "Wall: Sign joe cola", "crib-placeable-sign-joe-cola_01a" },
  { "Wall: Sign neon tipsy lizard watering hole", "crib-placeable-sign-neon_tipsy_lizard_watering_hole_01a" },
  { "Wall: Sign repo yard", "crib-placeable-sign-repo-yard_01a" },
  { "Wall: Sign roadside route66 shield sculpture", "crib-placeable-sign-roadside-route66-shield-sculpture_01a" },
  { "Wall: Spooky clown painting", "crib-placeable-spooky-clown-painting_01b" },
  { "Wall: Talltales chalupacabra sign", "crib-placeable-talltales-chalupacabra-sign_01a" },
  { "Wall: Wall relief herding cats", "crib-placeable-wall-relief-herding-cats_01a" },
  { "Wall: Western bear rug", "crib-placeable-western-bear-rug_01a" },
  { "Wall: Western cowboy silhouette", "crib-placeable-western-cowboy-silhouette_01a" },
  { "Wall: Western wanted poster", "crib-placeable-western-wanted-poster_01a" }
}
local SONGS = {
  { "The Drop: all the time", "all the time" },
  { "The Drop: bawdy", "bawdy" },
  { "The Drop: controller", "controller" },
  { "The Drop: dfr", "dfr" },
  { "The Drop: go off", "go off" },
  { "The Drop: my high", "my high" },
  { "The Drop: rat", "rat" },
  { "The Drop: salsabahton", "salsabahton" },
  { "The Drop: streets", "streets" },
  { "The Drop: swoopin", "swoopin" },
  { "The Drop: take control", "take control" },
  { "The Drop: trifecta", "trifecta" },
  { "The Drop: unconditional", "unconditional" },
  { "The Drop: what you like", "what you like" },
  { "Outrun: 1983", "1983" },
  { "Outrun: arcade dreams", "arcade_dreams" },
  { "Outrun: assault", "assault" },
  { "Outrun: blurred lights", "blurred_lights" },
  { "Outrun: bootloader", "bootloader" },
  { "Outrun: feel so wavy", "feel_so_wavy" },
  { "Outrun: grand theft audio", "grand_theft_audio" },
  { "Outrun: laser dreams", "laser_dreams" },
  { "Outrun: low gravity judo", "low_gravity_judo" },
  { "Outrun: megaupload", "megaupload" },
  { "Outrun: night driver", "night_driver" },
  { "Outrun: nighthawk", "nighthawk" },
  { "Outrun: redshift", "redshift" },
  { "Outrun: time runner", "time_runner" },
  { "Outrun: yakuza", "yakuza" },
  { "Dos Ochos: colas", "colas" },
  { "Dos Ochos: cumbia", "cumbia" },
  { "Dos Ochos: feliz", "feliz" },
  { "Dos Ochos: huapango", "huapango" },
  { "Dos Ochos: indita mia", "indita mia" },
  { "Dos Ochos: jarabe tapatito", "jarabe tapatito" },
  { "Dos Ochos: la adelita", "la adelita" },
  { "Dos Ochos: la bendecida", "la bendecida" },
  { "Dos Ochos: las mananitas", "las mananitas" },
  { "Dos Ochos: mariachi de amigos", "mariachi de amigos" },
  { "Dos Ochos: mascara del diablo", "mascara del diablo" },
  { "Dos Ochos: muneca de jalisco", "muneca de jalisco" },
  { "Dos Ochos: sangre sinaloense", "sangre sinaloense" },
  { "Dos Ochos: te tengo a ti", "te tengo a ti" },
  { "Dos Ochos: tres tiros", "tres tiros" },
  { "Overdrive: bet my brains", "bet my brains" },
  { "Overdrive: broken boy", "broken boy" },
  { "Overdrive: buck", "buck" },
  { "Overdrive: cruisin the night", "cruisin the night" },
  { "Overdrive: fairlady", "fairlady" },
  { "Overdrive: floating features", "floating features" },
  { "Overdrive: i wanna lose", "i wanna lose" },
  { "Overdrive: im still here", "im still here" },
  { "Overdrive: model village", "model village" },
  { "Overdrive: people", "people" },
  { "Overdrive: raw", "raw" },
  { "Overdrive: taste", "taste" },
  { "Overdrive: without you", "without you" },
  { "The Cipher: aint 2 proud 2 beg", "aint 2 proud 2 beg" },
  { "The Cipher: ante up", "ante up" },
  { "The Cipher: feel me flow", "feel me flow" },
  { "The Cipher: left my wallet", "left my wallet" },
  { "The Cipher: microphone fiend", "microphone fiend" },
  { "The Cipher: party up", "party up" },
  { "The Cipher: runnin", "runnin" },
  { "The Cipher: slam", "slam" },
  { "The Cipher: sound of da police", "sound of da police" },
  { "The Cipher: tres delinquentes", "tres delinquentes" },
  { "The Cipher: woohah", "woohah" },
  { "Public Radio: concerto for two trumpets", "concerto for two trumpets" },
  { "Public Radio: farandole", "farandole" },
  { "Public Radio: flower duet", "flower_duet" },
  { "Public Radio: funeral of the marionettes", "funeral of the marionettes" },
  { "Public Radio: fur elise", "fur elise" },
  { "Public Radio: gavotte", "gavotte" },
  { "Public Radio: hungarian dances", "hungarian dances" },
  { "Public Radio: il travatore", "il travatore" },
  { "Public Radio: merry wives of windsor", "merry wives of windsor" },
  { "Public Radio: nocturne", "nocturne" },
  { "Public Radio: piano concerto no1", "piano concerto no1" },
  { "Public Radio: string quartet no1", "string quartet no1" },
  { "Public Radio: symphony no40", "symphony no40" },
  { "Public Radio: violin concerto", "violin concerto" },
  { "Public Radio: water music", "water music" },
  { "Tumbleweed: born to be a cowboy", "born to be a cowboy" },
  { "Tumbleweed: campfire", "campfire" },
  { "Tumbleweed: dribbling smile", "dribbling smile" },
  { "Tumbleweed: in the shadow of the valley", "in the shadow of the valley" },
  { "Tumbleweed: long road", "long road" },
  { "Tumbleweed: making eyes", "making eyes" },
  { "Tumbleweed: nine train", "nine train" },
  { "Tumbleweed: old engine driver", "old engine driver" },
  { "Tumbleweed: pound another nail", "pound another nail" },
  { "Tumbleweed: red rock canyon", "red rock canyon" },
  { "Tumbleweed: revolver", "revolver" },
  { "Tumbleweed: ride stallion ride", "ride stallion ride" },
  { "Tumbleweed: run", "run" },
  { "Tumbleweed: squatting journey", "squatting journey" },
  { "Tumbleweed: your lyin eyes", "your lyin eyes" },
  { "Flex: bald", "bald" },
  { "Flex: bang", "bang" },
  { "Flex: blackout", "blackout" },
  { "Flex: calm down", "calm down" },
  { "Flex: crooked smile", "crooked smile" },
  { "Flex: down bad", "down bad" },
  { "Flex: future power sources", "future power sources" },
  { "Flex: harley quinn", "harley quinn" },
  { "Flex: ice", "ice" },
  { "Flex: killing", "killing" },
  { "Flex: miss the rage", "miss the rage" },
  { "Flex: own it", "own it" },
  { "El Latido: boleta", "boleta" },
  { "El Latido: botellas", "botellas" },
  { "El Latido: brillo", "brillo" },
  { "El Latido: con altura", "con altura" },
  { "El Latido: da da da", "da da da" },
  { "El Latido: en la mar", "en la mar" },
  { "El Latido: go bananas", "go bananas" },
  { "El Latido: hazmelo", "hazmelo" },
  { "El Latido: mariposa", "mariposa" },
  { "El Latido: mi poni", "mi poni" },
  { "El Latido: pam", "pam" },
  { "El Latido: pem pem", "pem pem" },
  { "El Latido: rebosando", "rebosando" },
  { "El Latido: rebota", "rebota" },
  { "El Latido: todo lo major", "todo lo major" },
  { "Nuclear Blast: betrayer", "betrayer" },
  { "Nuclear Blast: bleed", "bleed" },
  { "Nuclear Blast: cloud collected", "cloud collected" },
  { "Nuclear Blast: deconstructing self destruction", "deconstructing self destruction" },
  { "Nuclear Blast: empire of the blind", "empire of the blind" },
  { "Nuclear Blast: repentless", "repentless" },
  { "Nuclear Blast: stormcrow", "stormcrow" },
  { "Nuclear Blast: underneath the scars", "underneath the scars" },
  { "Nuclear Blast: weight of the false self", "weight of the false self" },
  { "Nuclear Blast: worship decay", "worship decay" },
  { "Nuclear Blast: zombie apocalypse", "zombie apocalypse" },
  { "Unreleased: get free", "get_free" },
  { "Unreleased: que pasa geno g", "que_pasa_geno_g" },
  { "Unreleased: young men dead", "young_men_dead" }
}
-- Every vehicle and variant, for Any vehicle.
local VEH = require("vehicles")
local ANY_VEHICLES = {}
for _, v in ipairs(VEH.list) do ANY_VEHICLES[#ANY_VEHICLES + 1] = { v[1], v[2], v[3] } end
local function any_variants(i)
  local out = {}
  for _, p in ipairs(ANY_VEHICLES[i][3]) do out[#out + 1] = { p[1] .. " (" .. p[2] .. ")", p[1] } end
  return out
end
local TABS = {
  { name = "Player", rows = {
    pset("god", "God mode", "You can't die. Not the game's cheat: your save stays clean.", { { "Off", false }, { "On", true } }),
    pset("health_mult", "Health", "Your maximum health.", { { "Game's", 1 }, { "x2", 2 }, { "x5", 5 }, { "x10", 10 } }),
    pset("proof_bullets", "Bulletproof", "Experimental: bullets don't hurt you, without God mode.", { { "Off", false }, { "On", true } }),
    pset("proof_explosions", "Explosion-proof", "Experimental: explosions and fire don't hurt you.", { { "Off", false }, { "On", true } }),
    pset("proof_crashes", "Crash-proof", "Experimental: being hit by vehicles and objects doesn't hurt you.", { { "Off", false }, { "On", true } }),
    { kind = "refill", label = "Refill health", help = "Back to full health." },
    { kind = "kill_self", label = "Kill yourself", help = "Press twice, with God mode off: you die as if shot, and respawn the way the game does." },
    pset("regen", "Health regen", "Experimental: None, Fast (five times, no wait after a hit) or Always back to full.", { { "Game's", "game" }, { "None", "none" }, { "Fast", "fast" }, { "Always full", "full" } }),
    pset("no_fall", "No fall damage", "Falls from any height don't hurt (the game's own fall limits raised).", { { "Off", false }, { "On", true } }),
    { kind = "mvset", key = "run", label = "Run speed", help = "How fast you walk, jog and sprint.", options = { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 }, { "x5", 5 } }, sel = 1, save_key = "move.run" },
    { kind = "mvset", key = "jump", label = "Jump height", help = "How high you jump. Big jumps need God mode or No fall damage.", options = { { "Game's", 1 }, { "x2", 2 }, { "x3", 3 }, { "x5", 5 }, { "x10", 10 } }, sel = 1, save_key = "move.jump" },
    { kind = "mvset", key = "air", label = "Air control", help = "Experimental: how much you steer in the air.", options = { { "Game's", 1 }, { "x2", 2 }, { "x4", 4 } }, sel = 1, save_key = "move.air" },
    { kind = "mvset", key = "swim", label = "Swim speed", help = "Experimental: how fast you swim.", options = { { "Game's", 1 }, { "x2", 2 }, { "x3", 3 } }, sel = 1, save_key = "move.swim" },
    { kind = "mvset", key = "gravity", label = "Your gravity", help = "Experimental: lower is floatier jumps and falls.", options = { { "Game's", 1 }, { "x0.5", 0.5 }, { "x0.25", 0.25 }, { "x2", 2 } }, sel = 1, save_key = "move.gravity" },
    { kind = "emote_slot", slot = "primary", label = "D-pad emote 1", help = "Left/Right picks the emote on your first D-pad emote; then use the D-pad as usual.", sel = 1, options = {}, apply = true },
    { kind = "emote_slot", slot = "secondary", label = "D-pad emote 2", help = "Left/Right picks the emote on your second D-pad emote; then use the D-pad as usual.", sel = 1, options = {}, apply = true },
    { kind = "emote", label = "Play emote", help = "Experimental: Left/Right picks one of the game's emotes, Enter plays it now.", sel = 1, options = {} },
    gchoice("Hidden emote", "Experimental: Left/Right picks an emote the game never lists, Enter plays it.", { { "Frost speech 2", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "emote frost speech 02")) return "Frost speech 2"]] }, { "Frost speech 3", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "emote frost speech 03")) return "Frost speech 3"]] }, { "Outfit inspect 2", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full action outfit inspect 2")) return "Outfit inspect 2"]] }, { "Walking Frankenstein", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "walking frankenstein")) return "Walking Frankenstein"]] }, { "Crab walk", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full state crab walk")) return "Crab walk"]] }, { "Broom ride", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full state broom ride side")) return "Broom ride"]] }, { "Spooky floating dance", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full state spooky floating dance")) return "Spooky floating dance"]] }, { "Stoney scary", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full state stoney scary")) return "Stoney scary"]] }, { "Skelly show", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full state skelly show")) return "Skelly show"]] }, { "Pumpkin smash", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full action pumpkin smash")) return "Pumpkin smash"]] }, { "Pumpkin throw", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "partial state pumpkin throw")) return "Pumpkin throw"]] }, { "Roachburger dance", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full action roachburger dance")) return "Roachburger dance"]] }, { "Frost speech", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "emote frost speech 01")) return "Frost speech"]] }, { "Stretch", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full action stretch")) return "Stretch"]] }, { "Outfit inspect", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full action outfit inspect 1")) return "Outfit inspect"]] }, { "Phone use", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full state phone use")) return "Phone use"]] }, { "Summoning", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full state summoning")) return "Summoning"]] }, { "Detonate", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "partial action detonate")) return "Detonate"]] }, { "Phone call", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "partial action phone call")) return "Phone call"]] }, { "Injured phone", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "partial body injured phone")) return "Injured phone"]] }, { "Steam", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "partial state steam")) return "Steam"]] } }),
    { kind = "mset", key = "repeat_emote", label = "Repeat emote", help = "Plays the emote picked in Play emote again and again; Stop emote ends it.", options = { { "Off", false }, { "Every 3 s", 180 }, { "Every 6 s", 360 }, { "Every 12 s", 720 } }, sel = 1 },
    { kind = "emote_stop", label = "Stop emote", help = "Stops the emote you're playing (and Repeat emote)." },
    { kind = "gchoice", apply = true, label = "Facial expression", help = "Your face holds this expression until you pick Normal.", sel = 1, options = { { "Normal", "selfie_mode_facial_expression_clear() return 'Normal'" },
      { "Anger", "selfie_mode_facial_expression_play(vlib_info_object:get_object('gml_gail_mood_info', 'anger')) return 'Anger'" }, { "Contempt", "selfie_mode_facial_expression_play(vlib_info_object:get_object('gml_gail_mood_info', 'contempt')) return 'Contempt'" },
      { "Disgust", "selfie_mode_facial_expression_play(vlib_info_object:get_object('gml_gail_mood_info', 'disgust')) return 'Disgust'" }, { "Fear", "selfie_mode_facial_expression_play(vlib_info_object:get_object('gml_gail_mood_info', 'fear')) return 'Fear'" },
      { "Happiness", "selfie_mode_facial_expression_play(vlib_info_object:get_object('gml_gail_mood_info', 'happiness')) return 'Happiness'" }, { "Pain", "selfie_mode_facial_expression_play(vlib_info_object:get_object('gml_gail_mood_info', 'pain')) return 'Pain'" },
      { "Sadness", "selfie_mode_facial_expression_play(vlib_info_object:get_object('gml_gail_mood_info', 'sadness')) return 'Sadness'" }, { "Surprise", "selfie_mode_facial_expression_play(vlib_info_object:get_object('gml_gail_mood_info', 'surprise')) return 'Surprise'" } } },
    { kind = "gchoice", apply = true, label = "Your voice", help = "The game's eight player voices (saved with your game; pick Say a line to hear it).", sel = 1, options = voices() },
    opt("Voice pitch", "Lower or higher than your voice (saved with your game).", "customization_get_avatar_voice_pitch()", "customization_set_avatar_voice_pitch(%s)", { { "-1", -1 }, { "-0.5", -0.5 }, { "0", 0 }, { "+0.5", 0.5 }, { "+1", 1 } }),
    pset("move_style", "Movement style", "Experimental: walk and run as if holding this. Your gun can override it.", { { "Game's", false }, { "Fists ready", "fists ready" }, { "One-hand melee", "1h_melee_ready" }, { "Two-hand melee", "2h_melee_ready" }, { "Staff", "staff ready" }, { "Pistol", "pistol_ready" }, { "Rifle", "rifle_ready" }, { "Minigun", "minigun_ready" }, { "Dual wield", "dual_wield_ready" }, { "Riot shield", "riotshield_pistol_ready" } }),
    pset("wingsuit_low", "Wingsuit from low down", "Experimental: the wingsuit opens from any height (you still need to be falling).", { { "Off", false }, { "On", true } }),
    pset("walk_style", "Walk style", "Experimental: replaces your walk, jog and sprint animations.", { { "Game's", false }, { "Forced walk", "default" }, { "Sad walk", "sad walk" } }),
    { kind = "voiceline", label = "Say a line", help = "Experimental: Left/Right picks one of the game's voice situations, Enter says it.", sel = 1, options = {} },
    gcall("Dismiss homies", "Sends away every homie who's following you.", [[
      local n = 0
      for _, h in vlib_info_object:ipairs("homie_info") do if homie_is_following(h) then homie_dismiss(h) n = n + 1 end end
      return n .. " dismissed"
    ]]),
    pset("homies", "Homie limit", "Experimental: how many homies can follow you at once (if you don't own the extra-homies perk).", { { "Game's", 1 }, { "2", 2 }, { "3", 3 }, { "4", 4 } }),
    pset("no_clip", "No clip", "Experimental: fly where you look. Left stick or W A S D, RT or Space up, LT or Ctrl down. Click the stick to go fast, or hold Shift. Guns won't fire on the triggers while it's on.", { { "Off", false }, { "On", true } }),
    pset("no_ragdoll", "No ragdoll", "Experimental: whenever you're knocked over, you're straight back up.", { { "Off", false }, { "On", true } }),
    { kind = "homie", label = "Summon homie", help = "Experimental: Left/Right picks a homie, Enter calls them in (if the game lets you).", sel = 1, options = {} },
    wsset("cooldown", "Wingsuit boosts", "The game gives you one boost until you land. Every 2 s, or Unlimited (once the last one ends).", { { "Game's", 1 }, { "Every 2 s", "short" }, { "Unlimited", "none" } }),
    wsset("boost", "Wingsuit boost power", "Boost speed, acceleration and length.", { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 } }),
    wsset("speed", "Wingsuit top speed", "Top speed without boosting, launch speed, landing speed cap.", { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 } }),
    wsset("glide", "Wingsuit glide", "Floaty: half gravity. Level: barely drops, no stall. Climb: gains height, and pull back (stick or S) to go up any time.", { { "Game's", "game" }, { "Floaty", "floaty" }, { "Level", "level" }, { "Climb", "climb" } }),
    toggle("invincibility", "Invincibility (game's)", "The game's Invincibility cheat."),
    action("cash", "Give cash", "The game's cash cheat."),
    action("max level", "Max level", "Jumps you to the top level."),
    pset("free_shop", "Free shopping", "Experimental: everything in the stores costs nothing while it's on (not saved).", { { "Off", false }, { "On", true } }),
    gchoice("Give XP", "Experimental: adds XP the game's way (it stays in your save).", award("xp", { { "1,000 XP", 1000 }, { "10,000 XP", 10000 }, { "100,000 XP", 100000 } })),
    gchoice("Give skill points", "Experimental: adds skill points (they stay in your save).", award("skill_point", { { "1", 1 }, { "5", 5 }, { "10", 10 } })),
    gchoice("Add cash", "Experimental: adds cash directly (it stays in your save).", award("cash", { { "$10,000", 10000 }, { "$100,000", 100000 }, { "$1,000,000", 1000000 } })),
    { kind = "play_as", back = false, label = "Play as spawned person", help = "Experimental: become the last person you spawned (World > Spawn person). Don't save while you're them." },
    { kind = "play_as", back = true, label = "Back to yourself", help = "Back to your own character. Remove spawned people does it too." },
    { kind = "outfit", label = "Saved look", help = "Experimental: Left/Right picks a character you saved in the game, Enter puts you back in it: body and outfit.", sel = 1, options = {} },
    { kind = "look_preset", label = "Character preset", help = "Experimental, press twice: replaces your whole character with the game's preset. Undo my look puts you back.", sel = 1, options = {} },
    gcall("Customize character", "Opens the game's character screen anywhere (through the phone). Esc back, Esc closes the phone.", [[gml_ui_gem_raise_event("ui_cell_phone_open", 1, "requested_screen", string_crci("cell_home_open_profile")) return "open: close this menu"]]),
    pset("all_perks", "All perks on", "Experimental: every perk's effect at once, no slots (not the two that cost you).", { { "Off", false }, { "On", true } }),
    pset("flow", "Unlimited Flow", "Your ability meter stays full, as the game does in some missions.", { { "Off", false }, { "On", true } }),
    pset("free_skills", "Free skills", "Experimental: skills cost no Flow.", { { "Off", false }, { "On", true } }),
    pset("flow_gain", "Flow gain", "Experimental: how much faster your Flow fills.", { { "Game's", false }, { "+2", 2.0 }, { "+5", 5.0 }, { "+20", 20.0 } }),
    pset("flow_bars", "Extra Flow bars", "Experimental: more bars on your Flow meter.", { { "Game's", false }, { "+1", 1.0 }, { "+3", 3.0 } }),
    pset("flow_no_decay", "Flow never drains", "Experimental: your Flow stays where it is out of combat.", { { "Off", false }, { "On", 1.0 } }),
    pset("rampage", "Rampage at full Flow", "Experimental: extra damage while your Flow is full (the perk gives 0.35).", { { "Game's", false }, { "+1", 1.0 }, { "+3", 3.0 } }),
    pset("takedown", "Takedown cooldown", "Experimental: how soon you can do another takedown (the game's is 90 s).", { { "Game's", false }, { "10 s", 10000 }, { "1 s", 1000 } }),
    { kind = "call_saints", label = "Call in Saints", help = "Experimental: Left/Right picks how many, Enter calls them in, free.", sel = 2, options = { { "1", 1 }, { "2", 2 }, { "4", 4 }, { "8", 8 } } },
    { kind = "prank", label = "Prank yourself", help = "A co-op leftover: Left/Right picks, Enter puts it on you. Off first before saving: the mesh ones swap your outfit.", sel = 1, options = {
      { "Off", false }, { "Bees", 0xD1DEBF59 }, { "Cash", 0xF8960CDB }, { "Hearts", 0x9DC3DBAC }, { "On fire", 0xD2FD511D }, { "Radioactive", 0x2FC32EBC }, { "Snow", 0xC8AC4CD1 }, { "Stink", 0xA86F8869 },
      { "Noodle arms", 0xC150DD93 }, { "Upside down", 0x4B60380A }, { "Bow-legged", 0x462A02E2 }, { "Bounce", 0x0339330A }, { "Foam hat", 0xBEFF0993 },
      { "Toilet", 0x70E3C60A }, { "Vending machine", 0xCBD43B2C }, { "Mailbox", 0xDA4E96A4 }, { "Cactus", 0x473E4F01 }, { "Trash can", 0xBDEDFB4D }, { "Burning barrel", 0xEAB2B9D6 } } },
    { kind = "mission", label = "Start mission", help = "Experimental, press twice, ON A SPARE SAVE: starts any mission or activity, in any order. It can wreck a save's story.", sel = 1, options = {} },
    gcall("Insurance Fraud here", "Experimental, press twice: starts the Insurance Fraud activity where you stand.", 'mission_request_start(vlib_info_object:get_object("mission_info", "insurance_fraud_anywhere")) return "Go"', true),
    pset("free_ventures", "Free ventures", "Experimental: Criminal Ventures cost nothing to build.", { { "Off", false }, { "On", true } }),
    { kind = "unlock", key = "everything", label = "Unlock EVERYTHING", help = "Press twice: every unlock row at once, DLC and all. Takes a minute or two (saved in your game)." },
    { kind = "unlock", key = "travel", label = "Unlock fast travel points", help = "Press twice: all of them, on the map and in the menu (saved in your game)." },
    { kind = "unlock", key = "weapons", label = "Own every weapon", help = "Press twice: every weapon entry in the game is yours, DLC and internal ones too (saved in your game)." },
    { kind = "unlock", key = "skills", label = "Unlock all skills", help = "Press twice: every skill is yours, free, DLC and Boothill too (saved in your game)." },
    { kind = "unlock", key = "perks", label = "Unlock all perks", help = "Press twice: every perk and perk slot is yours, free, DLC and Boothill too (saved in your game)." },
    { kind = "unlock", key = "gang", label = "Unlock gang and homies", help = "Press twice: every crew look, crew vehicle, homie and homie outfit is yours (saved in your game)." },
    { kind = "unlock", key = "clothing", label = "Unlock all clothing", help = "Press twice: every piece of clothing in the game is yours, sold in a store or not (saved in your game)." },
    { kind = "unlock", key = "stores", label = "Unlock everything in the stores", help = "Press twice: every store's clothing and emotes are yours (saved in your game)." },
    { kind = "unlock", key = "collectibles", label = "Unlock all collectibles", help = "Press twice: every collectible outfit, emote, weapon, car and HQ prop (saved in your game)." },
    toggle("super_saints", "Super Saints", "The game's Super Saints cheat."),
    toggle("milk_bones", "Milk Bones", "The game's Milk Bones cheat."),
    toggle("pratfall", "Pratfall", "You ragdoll at the slightest touch."),
    toggle("heaven_bound", "Heaven Bound", "The game's Heaven Bound cheat."),
  } },
  { name = "Weapons", rows = {
    wset("magazine", "Magazine", "No reload: your magazine is kept full, so it never goes down or reloads (launchers too).", {
      { "Game's", 1 }, { "x2", 2 }, { "x5", 5 }, { "No reload", "no_reload" } }),
    pset("money_gun", "Money gun", "Experimental: every shot throws $50 out ahead of you (it stays in your save).", { { "Off", false }, { "On", true } }),
    gcall("Remove this weapon", "Press twice: takes the gun in your hands out of your inventory.", "weapon_clear_inventory_slot(player_local_inventory_get_active_slot()) return 'Removed'", true),
    gchoice("Special weapon", "Experimental: Left/Right picks a mission-only weapon no store sells, Enter puts it in your inventory.", { { "Boss pistol", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_pistol_nahualli") weapon_swap_to_inventory(w) return "Boss pistol"]] }, { "Nahualli pistol", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_pistol_nahualli_subgrunt") weapon_swap_to_inventory(w) return "Nahualli pistol"]] }, { "Marshall burst rifle", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_rifle_marshall_burst") weapon_swap_to_inventory(w) return "Marshall burst rifle"]] }, { "Idols pistol SMG", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_smg_pistol_idols_ct_icon") weapon_swap_to_inventory(w) return "Idols pistol SMG"]] }, { "NPC minigun", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_temporary_marshall_minigun_npc") weapon_swap_to_inventory(w) return "NPC minigun"]] }, { "Dojo crowbar", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_1hand_dojo_crowbar") weapon_swap_to_inventory(w) return "Dojo crowbar"]] }, { "Flashcracker", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_grenade_flashcracker") weapon_swap_to_inventory(w) return "Flashcracker"]] }, { "Smoke grenade", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_grenade_smoke") weapon_swap_to_inventory(w) return "Smoke grenade"]] }, { "Molotov", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_grenade_molotov") weapon_swap_to_inventory(w) return "Molotov"]] }, { "Frag grenade", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_grenade_frag") weapon_swap_to_inventory(w) return "Frag grenade"]] }, { "Boot Hill fist cannon", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_fist_cannon_boothill") weapon_swap_to_inventory(w) return "Boot Hill fist cannon"]] }, { "Boot Hill pickaxe", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_2hand_pickaxe_boothill") weapon_swap_to_inventory(w) return "Boot Hill pickaxe"]] }, { "Boot Hill elephant rifle", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_rifle_elephant_boothill") weapon_swap_to_inventory(w) return "Boot Hill elephant rifle"]] }, { "Boot Hill tactical SMG", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_smg_tac_boothill") weapon_swap_to_inventory(w) return "Boot Hill tactical SMG"]] }, { "Boot Hill heavy SMG", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_smg_hi_volume_boothill") weapon_swap_to_inventory(w) return "Boot Hill heavy SMG"]] }, { "Boot Hill sawed-off", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_shotgun_sawedoff_boothill") weapon_swap_to_inventory(w) return "Boot Hill sawed-off"]] }, { "Boot Hill pistol", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_pistol_tacpistol_boothill") weapon_swap_to_inventory(w) return "Boot Hill pistol"]] }, { "Boot Hill box launcher", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_launcher_box_boothill") weapon_swap_to_inventory(w) return "Boot Hill box launcher"]] }, { "Boot Hill RPG", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_launcher_rpg_boothill") weapon_swap_to_inventory(w) return "Boot Hill RPG"]] }, { "Minigun", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_temporary_marshall_minigun") weapon_swap_to_inventory(w) return "Minigun"]] }, { "Riot shield", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_temporary_riot_shield") weapon_swap_to_inventory(w) return "Riot shield"]] }, { "DJ staff", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_temporary_djstaff") weapon_swap_to_inventory(w) return "DJ staff"]] }, { "Maul", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_temporary_panteros_maul") weapon_swap_to_inventory(w) return "Maul"]] }, { "Idols SMG", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_temporary_idols_smg") weapon_swap_to_inventory(w) return "Idols SMG"]] }, { "Heavy sword", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_2hand_heavy_sword_ct_icon") weapon_swap_to_inventory(w) return "Heavy sword"]] }, { "Toy hammer", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_2hand_toy_hammer_ct_icon") weapon_swap_to_inventory(w) return "Toy hammer"]] }, { "Nahualli knife", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_1hand_nahualli_knife") weapon_swap_to_inventory(w) return "Nahualli knife"]] }, { "Butterfly knife", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_1hand_nahualli_butterfly_knife") weapon_swap_to_inventory(w) return "Butterfly knife"]] }, { "Nahualli machete", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_nahualli_machete") weapon_swap_to_inventory(w) return "Nahualli machete"]] }, { "Dojo baton", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_1hand_dojo_baton") weapon_swap_to_inventory(w) return "Dojo baton"]] }, { "Dojo bat", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_2hand_dojo_bat") weapon_swap_to_inventory(w) return "Dojo bat"]] }, { "Dojo crutch", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_2hand_dojo_crutch") weapon_swap_to_inventory(w) return "Dojo crutch"]] }, { "Dojo sledgehammer", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_2hand_dojo_sledgehammer") weapon_swap_to_inventory(w) return "Dojo sledgehammer"]] }, { "Mime invisible pistol", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_pistol_wastelander_invisible") weapon_swap_to_inventory(w) return "Mime invisible pistol"]] }, { "NPC rocket launcher", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_launcher_rpg_npc") weapon_swap_to_inventory(w) return "NPC rocket launcher"]] }, { "Death Blossom", [[local w = vlib_info_object:get_object("inventory_weapon_info", "larp_death_blossom_inventory") weapon_swap_to_inventory(w) return "Death Blossom"]] }, { "Smokescreen", [[local w = vlib_info_object:get_object("inventory_weapon_info", "larp_smokescreen_inventory") weapon_swap_to_inventory(w) return "Smokescreen"]] }, { "Berserk", [[local w = vlib_info_object:get_object("inventory_weapon_info", "larp_berserk_inventory") weapon_swap_to_inventory(w) return "Berserk"]] }, { "Frost grenade", [[local w = vlib_info_object:get_object("inventory_weapon_info", "frostlander_grenade_inventory") weapon_swap_to_inventory(w) return "Frost grenade"]] }, { "Flashbang", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_grenade_flashbang") weapon_swap_to_inventory(w) return "Flashbang"]] }, { "Smoke grenade", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_grenade_smoke") weapon_swap_to_inventory(w) return "Smoke grenade"]] } }),
    { kind = "giveweapon", label = "Give weapon", help = "Experimental: Left/Right picks one of the game's weapons, Enter puts it in your inventory.", sel = 1, options = {} },
    { kind = "refill_ammo", label = "Refill all ammo", help = "Every weapon's magazine and reserve full, free (the game's infinite-ammo refill)." },
    toggle("infinite_ammo", "Infinite ammo", "Your reserve ammo never runs out (the game's cheat; your save stays clean)."),
    wset("fire_rate", "Fire rate", "How fast every weapon fires.", { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x4", 4 }, { "x8", 8 } }),
    pset("ammo", "Special ammo", "Experimental: what the gun in your hands does to people it hits; new guns get it too.", {
      { "Normal", false }, { "Fire", { "on_fire", "fire" } }, { "Shock", { "electrified", "electricity" } }, { "Chill", { "chill", "water" } },
      { "Stun", { "stun", "electricity" } }, { "Bleed", { "bleed", "dot_bleeding" } }, { "Disintegrate", { "disintegrate", "insta_kill" } },
      { "Flee", { "flee", "physical" } }, { "Panic", { "panic", "physical" } }, { "Blind", { "blindness", "physical" } }, { "Slip", { "slippery", "physical" } }, { "Stagger", { "stagger", "physical" } }, { "Fall over", { "eat food ragdoll", "physical" } }, { "Poison look", { "toxic_waste", "physical" } } }),
    pset("full_auto", "Full auto", "Single-shot guns keep firing while you hold the trigger (mouse or RT).", { { "Off", false }, { "On", 70 }, { "Fast", 40 } }),
    wset("damage", "Damage", "x2 to x10: your guns only. One-hit kill: every gun, enemies' too (pair it with God mode).", { { "Game's", 1 }, { "x2", 2 }, { "x5", 5 }, { "x10", 10 }, { "One-hit kill", "kill" } }),
    wset("reload", "Reload speed", "How fast reloads go.", { { "Game's", 1 }, { "x2", 2 }, { "x4", 4 }, { "Instant", 20 } }),
    wset("perfect_aim", "Perfect aim", "No spread: every shot goes where you aim.", { { "Off", false }, { "On", true } }),
    wset("no_recoil", "No recoil", "No kick when you fire, and no camera shake from it.", { { "Off", false }, { "On", true } }),
    wset("no_warmup", "No warm-up", "Miniguns spin up and charged weapons charge at once.", { { "Off", false }, { "On", true } }),
    wset("no_overheat", "No overheat", "Weapons that overheat never do.", { { "Off", false }, { "On", true } }),
    wset("range", "Range", "How far every weapon reaches.", { { "Game's", 1 }, { "x2", 2 }, { "x4", 4 } }),
    wset("knockback", "Knockback", "How hard hits push people and things.", { { "Game's", 1 }, { "x3", 3 }, { "x10", 10 } }),
    wset("blast", "Blast radius", "Experimental: how far launchers' and thrown weapons' explosions reach.", { { "Game's", 1 }, { "x2", 2 }, { "x5", 5 } }),
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
    { kind = "carset", key = "grip", label = "Grip", help = "Experimental: how hard the tires of the vehicle you're in hold the road.", options = { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 } }, sel = 1, save_key = "car.grip" },
    { kind = "carset", key = "steer", label = "Steering", help = "Experimental: how far the wheels turn, and up to what speed.", options = { { "Game's", 1 }, { "x1.25", 1.25 }, { "x1.5", 1.5 }, { "x2", 2 } }, sel = 1, save_key = "car.steer" },
    { kind = "carset", key = "top", label = "Vehicle top speed", help = "Experimental: the top speed of the vehicle you're in.", options = { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 } }, sel = 1, save_key = "car.top" },
    action("vehicle_health", "Repair vehicle", "Fixes the vehicle you're in."),
    pset("vgod", "Vehicle god mode", "Experimental: the vehicle you're in can't be damaged (the game's own indestructible flags).", { { "Off", false }, { "On", true } }),
    pset("car_no_crash", "No collision damage", "Experimental: crashing doesn't hurt the vehicle you're in.", { { "Off", false }, { "On", true } }),
    pset("car_heavy", "Heavy vehicle", "Experimental: the vehicle you're in pushes through traffic, as Infinite mass but only this one.", { { "Off", false }, { "On", true } }),
    pset("car_gravity", "Vehicle gravity", "Experimental: how hard the vehicle you're in is pulled down.", { { "Game's", 1 }, { "x0.5", 0.5 }, { "x0.25", 0.25 }, { "x2", 2 } }),
    { kind = "car_act", key = "boost", label = "Boost now", help = "Experimental: three seconds of boost (some vehicles refuse)." },
    { kind = "car_act", key = "jump", label = "Jump this vehicle", help = "Experimental: throws the vehicle you're in upward." },
    { kind = "car_act", key = "paint", label = "Next paint", help = "Experimental: each press changes the vehicle you're in to the next paint." },
    { kind = "special_car", label = "Special vehicle", help = "Experimental: Left/Right picks a vehicle missing from the spawn list, Enter spawns it. Boats need water.", sel = 1, options = { { "Fireworks flatbed", "flatbed_fireworks", "flatbed_01_ambient" }, { "Toxic flatbed", "flatbed_toxic", "flatbed_01_beater" }, { "Statue flatbed", "flatbed_choplifter_statue", "flatbed_01_beater" }, { "Fuel tanker", "quickshot_tanker_truck", "truck_base_tanker" }, { "Armored truck", "truck_armored_01", "truck_armored_01_ambient" }, { "Casino armored truck", "truck_armored_01", "truck_armored_01_casino" }, { "APC", "sp_apc_01", "apc_01_ambient" }, { "National Guard APC", "sp_apc_01", "apc_01_ng" }, { "Turret pickup", "pickup_03_turret", "pickup_03_marshall" }, { "Panteros turret truck", "truck_classic_02_turret", "truck_classic_02_panteros" }, { "Turret helicopter", "heli_standard_02_turret", "heli_standard_02_activity" }, { "Police spotlight helicopter", "heli_police_spotlight", "heli_police_01_police" }, { "Idols helicopter", "helicopter_police_idol_01", "heli_police_01_idols" }, { "Saints wingsuit helicopter", "heli_wingsuit_deploy", "heli_police_01_saints" }, { "Tether helicopter", "heli_standard_02_choplifter", "heli_standard_02_tether" }, { "Rotorhead", "heli_standard_03_rotorhead", "heli_standard_03_rotorhead_reward" }, { "Armored boss boat", "ct_idols_boss_boat", "boat_speed_01_armored" }, { "Boot Hill boat", "boat_speed_01_boothill", "boat_speed_01_boothill" }, { "Boat", "boat_standard_01", "boat_standard_01_ambient" }, { "Armored muscle 3", "muscle_03_armored", "muscle_03_armored_panteros" }, { "Monster, Panteros", "monster_02_ct_road", "monster_02_panteros" }, { "RV", "rv_01", "sp_rv_01_ambient" }, { "Meth lab RV", "rv_01_meth_lab", "sp_rv_01_meth_lab" }, { "Roofless Idols compact", "compact_01_idol_stream", "compact_01_ambient_idol_no_roof" }, { "Ned's compact", "compact_01_ned", "compact_01_ned_mission" }, { "Weiner truck", "foodtruck_01", "food_01_weiner" }, { "Sushi truck", "foodtruck_01", "food_01_sushi" }, { "Ice cream truck", "foodtruck_01", "food_01_ice_cream" }, { "Junk go-kart", "go_cart_ms_faire_b", "go_cart_junker" }, { "Covered cart, Marshall", "cart_01_covered", "cart_01_covered_marshall" }, { "Golf cart", "cart_02", "cart_02_reward" }, { "Reward wagon", "wagon_09", "wagon_09_reward" }, { "Sports 1", "sport_01", "sports_01_ambient" }, { "Sports 2", "sport_02", "sports_02_ambient" }, { "Muscle 1", "muscle_01", "muscle_01_ambient" }, { "Muscle 5", "muscle_05", "muscle_05_ambient" }, { "Classic 3", "classic_03", "classic_03_ambient" }, { "Utility truck", "utility_01", "sp_utility_01_ambient" }, { "Van 4", "van_04", "van_04_ambient" }, { "Bomb car", "wt_gas_bombcar", "sports_01_ambient" }, { "Mission tank", "tank_mh_pay_01", "tank_02_mh_pay" }, { "Bus", "bus_01", "bus_01_ambient" }, { "Bus, roadblock", "bus_01", "bus_01_road_block" }, { "Tank", "tank_01", "tank_01_ambient" }, { "Police tank", "tank_01", "tank_01_police" }, { "Yacht", "boat_yacht_01", "boat_yacht_01_ambient" }, { "Sailboat", "boat_sail_01", "boat_sail_01_ambient" }, { "Jet ski", "jet_ski", "jet_ski_ambient" }, { "Fire truck", "fire_01", "fire_01_ambient" }, { "Hearse", "hearse_01", "hearse_01_ambient" }, { "ATV", "atv_01", "atv_01_ambient" }, { "Attack helicopter", "heli_fighter_01_nahualli", "heli_fighter_01_nahualli" }, { "VTOL", "vanguard_vtol_02", "vanguard_vtol_02_ambient" }, { "Armored muscle", "muscle_01_armored", "muscle_01_armored_panteros" }, { "Police car", "police_01", "police_01_police" }, { "SWAT car", "police_01", "police_01_swat" }, { "Marshall luxury", "luxury_04", "luxury_04_marshall" }, { "Hoverboard", "hoverboard_01", "hoverboard_01_ambient" } } },
    gcall("Deliver to garage", "Experimental, press twice: saves the vehicle you're in to your garage (saved in your game).", "return vehicle_save_vehicle_to_garage(enemy_get_occupied_vehicle(gml_get_local_player()))", true),
    { kind = "car_act", key = "remove", label = "Remove spawned vehicles", help = "Experimental: removes vehicles the menu spawned, except the one you're in." },
    pset("cam_delay", "Car camera resets after", "Experimental: how long the camera waits before swinging back behind the vehicle.", { { "Game's", false }, { "2 s", 2 }, { "10 s", 10 }, { "Never", 9999 } }),
    opt("Free camera in cars", "Experimental: the camera stays where you put it instead of following the vehicle.", "option_get_camera_vehicle_follow()", "option_set_camera_vehicle_follow(%s)", { { "Game's", 1 }, { "Free", 2 } }),
    { kind = "car_ability", label = "Vehicle ability", help = "Experimental: Left/Right picks, Enter gives it to the vehicle you're in. Some need parts the vehicle lacks.", sel = 1, options = {
      { "Jump", 0xC243039A }, { "Air boost", 0x5C782702 }, { "Ball and chain", 0x585D60F8 }, { "Crab steering", 0x9027B56C }, { "Ejector seats", 0x8C3A98AD }, { "Front loader flip", 0xC8A6C120 },
      { "Honk blast", 0x80D9EC2B }, { "Infinite boost", 0x3BF698E8 }, { "Kneecappers", 0xEE7A9FAD }, { "Super air control", 0x4CDDA777 }, { "Cowcatcher and blast", 0xEABCC755 } } },
    { kind = "car_act", key = "tow", label = "Tow hook", help = "Experimental: puts a tow hook on the vehicle you're in." },
    pset("car_jump_power", "Vehicle jump power", "Experimental: how high the Jump ability throws you.", { { "Game's", false }, { "x2", 2 }, { "x3", 3 }, { "x5", 5 } }),
    pset("car_ability_cd", "No ability cooldowns", "Experimental: vehicle abilities are ready at once.", { { "Off", false }, { "On", true } }),
    pset("car_takedowns", "Takedowns at any speed", "Experimental: spinouts, T-bones and flips happen from 5 mph, not 40 to 50.", { { "Off", false }, { "On", true } }),
    pset("car_ram", "Ram power", "Experimental: how hard hitting things throws them.", { { "Game's", false }, { "x2", 2 }, { "x3", 3 }, { "x10", 10 } }),
    pset("car_brake_lights", "Brake lights stay on", "Experimental: the vehicle you're in keeps its brake lights lit.", { { "Off", false }, { "On", true } }),
    pset("tires", "Bulletproof tires", "Experimental: the tires of the vehicle you're in can't be shot out.", { { "Off", false }, { "On", true } }),
    pset("spring", "Suspension", "Experimental: softer or stiffer springs on the vehicle you're in.", { { "Game's", 1 }, { "Bouncy", 0.25 }, { "Soft", 0.5 }, { "Stiff", 2 }, { "Rock hard", 4 } }),
    { kind = "destroy_car", label = "Destroy this vehicle", help = "Press twice. It blows up, and it can take you with it." },
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
    { kind = "waypoint", label = "Go to waypoint", help = "Experimental: takes you to the waypoint you set on the map (or the mission marker)." },
    pset("auto_waypoint", "Auto-teleport to waypoint", "Experimental: place a waypoint on the map and you're there.", { { "Off", false }, { "On", true } }),
    { kind = "map_place", stores = true, label = "Store", help = "Experimental: Left/Right picks a store the map knows, Enter takes you there.", sel = 1, options = {} },
    { kind = "map_place", stores = false, label = "Map place", help = "Experimental: Left/Right picks an activity or place the map knows, Enter takes you there.", sel = 1, options = {} },
    { kind = "warp", label = "Fast travel point", help = "Left/Right picks one of the game's 44 travel points, Enter takes you there.", sel = 1, options = {} },
    { kind = "place_save", label = "Save this spot", help = "Saves where you stand to your places (TweakMenu, saved_places.txt)." },
    { kind = "places", label = "Go to", help = "Left/Right picks one of your places, Enter takes you there.", sel = 1 },
    { kind = "place_delete", label = "Delete that place", help = "Removes the place picked above." },
    { kind = "lift", label = "Go up", help = "Left/Right picks how high, Enter takes you up. Long falls kill: turn on God mode first.", sel = 2,
      options = { { "10 m", 10 }, { "50 m", 50 }, { "100 m", 100 }, { "250 m", 250 }, { "500 m", 500 }, { "1000 m", 1000 }, { "2000 m", 2000 }, { "3000 m", 3000 } } },
    { kind = "where", label = "Where am I", help = "Shows your position." },
  } },
  { name = "World", rows = {
    choice("Weather", "Left/Right sets it.", {
      { "Clear", "weather_clear" }, { "Dust", "weather_dust" }, { "Fog", "weather_fog" } }),
    { kind = "weathernode", label = "Weather (all)", help = "Experimental: Left/Right blends to any of the game's weathers.", sel = 1, options = {}, apply = true },
    choice("Time of day", "Left/Right sets it.", {
      { "Morning", "tod_morning" }, { "Noon", "tod_noon" }, { "Afternoon", "tod_afternoon" },
      { "Evening", "tod_evening" }, { "Midnight", "tod_midnight" } }),
    { kind = "wdset", key = "freeze_clock", label = "Freeze clock", help = "Stops the time of day where it is.", options = { { "Off", false }, { "On", true } }, sel = 1, save_key = "world.freeze_clock" },
    { kind = "wdset", key = "clock_speed", label = "Clock speed", help = "How fast the time of day passes.", options = { { "Game's", 1 }, { "x0.5", 0.5 }, { "x2", 2 }, { "x5", 5 }, { "x10", 10 } }, sel = 1, save_key = "world.clock_speed" },
    { kind = "wdset", key = "pause", label = "Pause world", help = "Everything stops, you too (the game's own pause); the menu still works.", options = { { "Off", false }, { "On", true } }, sel = 1 },
    { kind = "person", label = "Spawn person", help = "Left/Right picks one of the game's characters, Enter spawns them beside you.", sel = 1, options = {} },
    pset("spawn_hostile", "Spawned people", "Experimental. What people you spawn do from now on: wander off, stay with you as bodyguards, fight gangs at your side, or fight you.", { { "Passive", false }, { "Bodyguards", "guard" }, { "Your army", "army" }, { "Fight you", true } }),
    gchoice("Radio station", "Experimental: Left/Right picks, Enter tunes the vehicle you're in. Premium stations too.", { { "Off", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("off", false) return 'Off']] }, { "88.7 Dos Ochos", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("dos ochos", false) return '88.7 Dos Ochos']] }, { "90.5 Public Radio", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("public radio", false) return '90.5 Public Radio']] }, { "93.3 Tumbleweed", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("tumbleweed", false) return '93.3 Tumbleweed']] }, { "95.7 The Drop", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("thedrop", false) return '95.7 The Drop']] }, { "99.5 The Cipher", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("the cipher", false) return '99.5 The Cipher']] }, { "101.1 Outrun", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("outrun", false) return '101.1 Outrun']] }, { "103.3 Overdrive", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("overdrive", false) return '103.3 Overdrive']] }, { "201 Flex", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("flex", false) return '201 Flex']] }, { "203 El Latido", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("el_latido", false) return '203 El Latido']] }, { "204 Nuclear Blast", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("nuclear_blast", false) return '204 Nuclear Blast']] } }),
    gchoice("Music anywhere", "Experimental: Left/Right picks a station's songs, Enter plays them anywhere, on foot too, no DJ or ads.", { { "Stop", [[playlist_stop() return 'Music off']] }, { "The Drop", [[playlist_play(vlib_info_object:get_object("playlist_info", "kbpm_thedrop")) return 'Playing The Drop']] }, { "Outrun", [[playlist_play(vlib_info_object:get_object("playlist_info", "kfdr_outrun")) return 'Playing Outrun']] }, { "Dos Ochos", [[playlist_play(vlib_info_object:get_object("playlist_info", "kfst_dosochos")) return 'Playing Dos Ochos']] }, { "Overdrive", [[playlist_play(vlib_info_object:get_object("playlist_info", "kfvzz_overdrive")) return 'Playing Overdrive']] }, { "The Cipher", [[playlist_play(vlib_info_object:get_object("playlist_info", "kjmz_thecipher")) return 'Playing The Cipher']] }, { "Public Radio", [[playlist_play(vlib_info_object:get_object("playlist_info", "ksipr_santopublic")) return 'Playing Public Radio']] }, { "Tumbleweed", [[playlist_play(vlib_info_object:get_object("playlist_info", "kwpke_tumbleweed")) return 'Playing Tumbleweed']] }, { "Flex", [[playlist_play(vlib_info_object:get_object("playlist_info", "sm1_flex")) return 'Playing Flex']] }, { "El Latido", [[playlist_play(vlib_info_object:get_object("playlist_info", "sm3_ellatido")) return 'Playing El Latido']] }, { "Nuclear Blast", [[playlist_play(vlib_info_object:get_object("playlist_info", "sm4_nuclearblast")) return 'Playing Nuclear Blast']] } }),
    { kind = "song", label = "Play song", help = "Experimental: Left/Right picks any song, including three no station plays, Enter plays it anywhere.", sel = 1, options = SONGS },
    { kind = "skip_track", label = "Skip track", help = "Experimental: the next track on the music or the radio." },
    gcall("Pause or resume music", "Experimental: pauses Music anywhere, or starts it again.", [[if not playlist_is_playing() and not playlist_is_paused() then return 'No music on' end if playlist_is_paused() then playlist_resume() return 'Resumed' end playlist_pause() return 'Paused']]),
    gcall("Now playing", "Experimental: shows what's on.", [[if playlist_is_playing() then local s = playlist_get_active_song() if s:is_valid() then return vint_insert_values_in_string("{1:text_tag} - {2:text_tag}", s.m_artist:get_handle(), s.m_title:get_handle()) end end local t, a = radio_get_playing_title() if not t or t == 0 then return 'Nothing playing' end if a and a ~= 0 then return vint_insert_values_in_string("{1:text_tag} - {2:text_tag}", a, t) end return vint_insert_values_in_string("{1:text_tag}", t)]]),
    { kind = "spawn_prop", label = "Spawn prop", help = "Experimental: Left/Right picks a prop, Enter loads it and puts it in front of you. Gone when you reload.", sel = 1, options = SPAWN_PROPS },
    { kind = "remove_prop", last = true, label = "Remove last prop", help = "Removes the prop you spawned last." },
    { kind = "remove_prop", label = "Remove all props", help = "Removes every prop you've spawned." },
    { kind = "hq_spot", label = "HQ spot", help = "Experimental: picks a spot in your headquarters for HQ prop.", sel = 1, options = { { "Armory normal 1", "hq_prop_anchor_armory_normal_01" }, { "Armory wall 1", "hq_prop_anchor_armory_wall_01" }, { "Bar large 1", "hq_prop_anchor_bar_large_01" }, { "Bar large 2", "hq_prop_anchor_bar_large_02" }, { "Bar normal 1", "hq_prop_anchor_bar_normal_01" }, { "Bar wall 1", "hq_prop_anchor_bar_wall_01" }, { "Exterior huge 1", "hq_prop_anchor_exterior_huge_01" }, { "Exterior huge 2", "hq_prop_anchor_exterior_huge_02" }, { "Exterior large 1", "hq_prop_anchor_exterior_large_01" }, { "Exterior large 2", "hq_prop_anchor_exterior_large_02" }, { "Gameroom large 1", "hq_prop_anchor_gameroom_large_01" }, { "Gameroom normal 1", "hq_prop_anchor_gameroom_normal_01" }, { "Gameroom wall 1", "hq_prop_anchor_gameroom_wall_01" }, { "Hall huge 1", "hq_prop_anchor_hall_huge_01" }, { "Hall large 1", "hq_prop_anchor_hall_large_01" }, { "Hall large 2", "hq_prop_anchor_hall_large_02" }, { "Hall large 3", "hq_prop_anchor_hall_large_03" }, { "Sunshine large 1", "sunshine_hq_anchor_large_01" }, { "Sunshine large 2", "sunshine_hq_anchor_large_02" }, { "Sunshine large 3", "sunshine_hq_anchor_large_03" }, { "Sunshine large 4", "sunshine_hq_anchor_large_04" }, { "Sunshine normal 1", "sunshine_hq_anchor_normal_01" } } },
    { kind = "hq_prop", label = "HQ prop", help = "Experimental: Left/Right picks a prop, owned or not, any size, Enter puts it on the HQ spot from anywhere (saved with your game; big ones may clip).", sel = 1, options = CRIB_PROPS },
    { kind = "hq_clear", label = "Clear this HQ spot", help = "Experimental: empties the HQ spot." },
    { kind = "look_undo", label = "Undo my look", help = "Experimental, press twice: back to how you looked before you first used Saved look or Character preset this session, or at your last snapshot." },
    { kind = "look_snap", label = "Take a look snapshot", help = "Experimental: Undo my look will come back to how you look now. Lasts until you quit." },
    pset("friendly_fire", "Friendly fire", "Experimental: the game's shots do nothing to anyone friendly to you, followers and gang allies too. Half or Full lets them hurt.", { { "Game's (none)", false }, { "Half", 1 }, { "Full", 2 } }),
    pset("body_muscular", "Body: muscle", "Experimental: past the slider's top. Only on screen: your save keeps your real body.", { { "Game's", false }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 } }),
    pset("body_large", "Body: fat", "Experimental: past the slider's top. Only on screen.", { { "Game's", false }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 } }),
    pset("body_thin", "Body: thin", "Experimental: past the slider's top. Only on screen.", { { "Game's", false }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 } }),
    pset("body_breasts", "Body: chest", "Experimental: past the slider's top. Only on screen.", { { "Game's", false }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 } }),
    pset("body_gender", "Body: blend", "Experimental: the masculine to feminine slider, past both ends. Only on screen.", { { "Game's", false }, { "-0.5", -0.5 }, { "0", 0.0001 }, { "0.5", 0.5 }, { "1", 1.0 }, { "1.5", 1.5 } }),
    pset("body_head", "Face: head shape", "Experimental: past the slider's top. Only on screen.", { { "Game's", false }, { "1", 1.0 }, { "2", 2.0 }, { "3", 3.0 } }),
    pset("body_eyes", "Face: eye size", "Experimental: past the slider's top. Only on screen.", { { "Game's", false }, { "0", 0.0001 }, { "1", 1.0 }, { "2", 2.0 }, { "3", 3.0 }, { "5", 5.0 } }),
    pset("body_nose", "Face: nose size", "Experimental: past the slider's top. Only on screen.", { { "Game's", false }, { "0", 0.0001 }, { "1", 1.0 }, { "2", 2.0 }, { "3", 3.0 }, { "5", 5.0 } }),
    pset("body_mouth", "Face: mouth size", "Experimental: past the slider's top. Only on screen.", { { "Game's", false }, { "0", 0.0001 }, { "1", 1.0 }, { "2", 2.0 }, { "3", 3.0 }, { "5", 5.0 } }),
    { kind = "body_back", label = "Back to my real body", help = "Sets all of these back to the game's." },
    pset("game_speed", "Game speed", "Experimental: slow motion, or the whole game faster. Your character too.", { { "Normal", false }, { "x0.1", 10.0 }, { "x0.25", 4.0 }, { "x0.5", 2.0 }, { "x2", 0.5 }, { "x4", 0.25 } }),
    pset("force_combat", "Stay in combat", "Experimental: the game thinks you're always in a fight.", { { "Off", false }, { "On", true } }),
    { kind = "go_to_hour", label = "Go to time", help = "Left/Right picks, Enter moves the clock there at once.", sel = 1, options = { { "Dawn", 6 }, { "Morning", 9 }, { "Noon", 12 }, { "Afternoon", 15 }, { "Dusk", 18 }, { "Evening", 20 }, { "Midnight", 0.01 }, { "Small hours", 3 } } },
    pset("warp_map", "Warp from map", "Experimental: the game's dev teleport: on the big map, look for DEBUG WARP. You arrive 300 m up: use God mode or the wingsuit.", { { "Off", false }, { "On", true } }),
    opt("Dev: never die", "Experimental: a developer switch left in the game. Effect unknown.", "global_script_variable_get_bool('never_die')", "global_script_variable_set_bool('never_die', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: never die, AI", "Experimental: a developer switch. Effect unknown.", "global_script_variable_get_bool('never_die_ai')", "global_script_variable_set_bool('never_die_ai', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: Shawn mode", "Experimental: a developer switch named after someone. Effect unknown.", "global_script_variable_get_bool('shawn_mode')", "global_script_variable_set_bool('shawn_mode', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: capture mode", "Experimental: a developer switch, for filming. Effect unknown.", "global_script_variable_get_bool('capture_mode')", "global_script_variable_set_bool('capture_mode', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: auto sprint", "Experimental: a developer switch.", "global_script_variable_get_bool('auto_sprint_enable')", "global_script_variable_set_bool('auto_sprint_enable', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: infinite ammo", "A developer switch read by the game: no cheat flag on your save.", "global_script_variable_get_bool('infinite_ammo')", "global_script_variable_set_bool('infinite_ammo', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: infinite magazine", "A developer switch: no cheat flag on your save.", "global_script_variable_get_bool('infinite_magazine')", "global_script_variable_set_bool('infinite_magazine', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: radio on", "A developer switch: off silences the radio.", "global_script_variable_get_bool('radio_enabled')", "global_script_variable_set_bool('radio_enabled', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: vehicle ramps", "Experimental: a developer switch.", "global_script_variable_get_bool('vehicle_ramp_override')", "global_script_variable_set_bool('vehicle_ramp_override', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: weapon raycasts", "Experimental: a developer switch; may draw nothing in this build.", "global_script_variable_get_bool('debug_weapon_raycasts')", "global_script_variable_set_bool('debug_weapon_raycasts', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: notoriety bubbles", "Experimental: a developer switch; may draw nothing in this build.", "global_script_variable_get_bool('debug_render_notoriety_bubbles')", "global_script_variable_set_bool('debug_render_notoriety_bubbles', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: HQ mask off", "Experimental: a developer switch.", "global_script_variable_get_bool('hq_mask_disabled')", "global_script_variable_set_bool('hq_mask_disabled', %s)", { { "Off", false }, { "On", true } }),
    { kind = "console_row", label = "Freeze emote", handler = 0xA914F0, help = "Experimental: freezes the emote you're doing mid-pose, or lets it go." },
    { kind = "outfit_any", label = "Hidden outfit", help = "Experimental: Left/Right picks clothes the wardrobe doesn't list, Enter wears them. Undo my look puts you back.", sel = 1, options = { { "Armadillo mascot", "clo_suit_armadillo_mascot_01" }, { "Cookie suit", "clo_suit_cookie_suit_01" }, { "Demon bodysuit", "clo_suit_demon_bodysuit_01" }, { "Halloween cat", "clo_suit_halloween_bodysuit_cat_01" }, { "Halloween devil", "clo_suit_halloween_bodysuit_devil_01" }, { "Pumpkin", "clo_suit_pumpkin_01" }, { "Stripes", "clo_suit_stripes_01" }, { "Wetsuit", "clo_suit_wetsuit_01" }, { "Marshall subgrunt", "clo_suit_marshall_subgrunt_01" }, { "Marshall grunt", "clo_suit_marshall_grunt_02" }, { "Star band hat", "clo_hat_starband" }, { "Devil horns", "clo_head_devil_horns_headband_01" }, { "Large horns", "clo_head_large_horns_headband_01" }, { "Firefighter", "clo_suit_firefighter_01" } } },
    pset("gang_war", "Gang war", "Experimental: gangs near you fight each other, without you. Go where they are, or use Send in a gang twice.", { { "Off", false }, { "Panteros vs Idols", { { 0xCFD91205, 0xAF91816E } } }, { "Panteros vs Marshall", { { 0xCFD91205, 0xAD77A00A } } }, { "Idols vs Marshall", { { 0xAF91816E, 0xAD77A00A } } }, { "All three gangs", { { 0xCFD91205, 0xAF91816E }, { 0xCFD91205, 0xAD77A00A }, { 0xAF91816E, 0xAD77A00A } } }, { "Gangs vs police", { { 0xCFD91205, 0x55BEF8FA }, { 0xAF91816E, 0x55BEF8FA }, { 0xAD77A00A, 0x55BEF8FA } } }, { "Everyone", { { 0xCFD91205, 0xAF91816E }, { 0xCFD91205, 0xAD77A00A }, { 0xAF91816E, 0xAD77A00A }, { 0xCFD91205, 0x55BEF8FA }, { 0xAF91816E, 0x55BEF8FA }, { 0xAD77A00A, 0x55BEF8FA } } } }),
    pset("fight_damage", "NPC fight damage", "Experimental: how hard people hurt each other (not you). The game's is 0.6, which is why their fights drag.", { { "Game's", false }, { "1", 1.0 }, { "2", 2.0 }, { "5", 5.0 } }),
    pset("combative_peds", "Pedestrians fight back", "Experimental: passers-by fight instead of running.", { { "Off", false }, { "On", true } }),
    pset("ai_combat", "Everyone battle ready", "Experimental: every AI stays in combat mode.", { { "Off", false }, { "On", true } }),
    pset("world_gravity", "World gravity", "Experimental: gravity for everything loose: people, grenades, things. Cars hold the road better than most. Upward sends what's loose away.", { { "Game's", false }, { "x0.5", 0.5 }, { "x0.25", 0.25 }, { "x0.1", 0.1 }, { "x2", 2.0 }, { "x3", 3.0 }, { "Upward", -0.2 } }),
    pset("blast_size", "Explosion size", "Experimental: how far every explosion reaches, yours and everyone's. The fireball itself stays the same size.", { { "Game's", false }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("blast_force", "Explosion force", "Experimental: how hard every explosion throws things.", { { "Game's", false }, { "x3", 3.0 }, { "x10", 10.0 }, { "x30", 30.0 } }),
    pset("blast_damage", "Explosion damage", "Experimental: some explosions take their damage from the weapon instead.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 } }),
    pset("own_blast", "Hurting yourself", "Experimental: the damage you do to yourself, as from your own explosions.", { { "Game's", false }, { "None", 0.0001 } }),
    { kind = "launch_car", label = "Launch this vehicle", help = "Experimental: Left/Right picks, Enter throws the car you're in, or the nearest, into the air.", sel = 1, options = { { "Small", 30000 }, { "Big", 80000 }, { "Moon", 200000 } } },
    { kind = "crowd_act", key = "zombies", label = "Zombie outbreak", help = "Experimental: a third of the people within 40 m turn on everyone else." },
    { kind = "crowd_act", key = "riot", label = "Riot", help = "Experimental: everyone within 40 m splits into two sides, which fight." },
    { kind = "crowd_act", key = "downed", label = "Downed, not dead", help = "Experimental: people within 40 m go down instead of dying when they're killed." },
    pset("free_for_all", "Free for all", "Experimental: these factions attack anyone they don't have a rule for, you and their own included.", { { "Off", false }, { "Gangs", "gangs" }, { "Gangs and police", "all" } }),
    pset("gang_presence", "Gang presence", "Experimental: how many of each gang the district keeps on its streets. Districts only have the gangs they have. Watch your frame rate.", { { "Game's", false }, { "x3", 3 }, { "x6", 6 } }),
    { kind = "crowd_act", key = "launch", label = "Launch everyone near", help = "Experimental: everyone within 40 m flies up." },
    pset("peds", "Pedestrians", "Experimental: how many people the district keeps around. Watch your frame rate.", { { "Game's", false }, { "Few", 0.25 }, { "x2", 2 }, { "x3", 3 } }),
    pset("traffic", "Traffic", "Experimental: how many cars the district keeps around. Watch your frame rate.", { { "Game's", false }, { "Few", 0.25 }, { "x2", 2 }, { "x3", 3 } }),
    pset("traffic_far", "Traffic pop-in", "Experimental: how far away traffic appears.", { { "Game's", false }, { "Further", 300.0 }, { "Far", 500.0 } }),
    pset("rain_crowd", "Crowds in the rain", "Experimental: the streets normally empty when it rains.", { { "Game's", false }, { "Same as sunny", 1.0 } }),
    pset("enemy_aim", "Enemy aim", "Experimental: how far enemies' shots are meant to miss by. If it changes nothing right away, try on fresh enemies.", { { "Game's", false }, { "Laser", 0.0001 }, { "Poor", 3 }, { "Stormtroopers", 8 } }),
    pset("back_stab", "Back shot damage", "Experimental: the bonus for hits from behind (the game's is x2.5).", { { "Game's", false }, { "None", 1.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("no_flinch", "No flinch", "Experimental: taking a hit doesn't make you flinch.", { { "Off", false }, { "On", 100000.0 } }),
    pset("dodge_ms", "Dodge safe time", "Experimental: how long a dodge keeps you from harm.", { { "Game's", false }, { "1 s", 1000 }, { "2 s", 2000 }, { "5 s", 5000 } }),
    { kind = "revive_me", label = "Get up", help = "Experimental: the co-op revive, on yourself: use it when you're down." },
    pset("slow_button", "Slow motion button", "Experimental: hold LB and RB, or Alt, for slow motion while it's held. Everyone slows, you too.", { { "Off", false }, { "x0.5", 2.0 }, { "x0.25", 4.0 }, { "x0.1", 10.0 } }),
    pset("panic", "People panic", "Experimental: how far gunfire and explosions scare people. New scares only.", { { "Game's", false }, { "Hardly at all", 0.05 }, { "Whole block", 3 } }),
    pset("ragdoll_easy", "Knocked over", "Experimental: how hard something has to hit you to knock you over.", { { "Game's", false }, { "Easily", 0.2 }, { "Hardly ever", 5 } }),
    pset("no_parked", "No parked cars", "Experimental: stops new parked cars appearing. The ones already there stay.", { { "Off", false }, { "On", true } }),
    pset("rockets", "Rocket rounds", "Experimental: the gun in your hands fires rockets, no more than 4 a second. This crashed the game before, for a reason that's now fixed: save first.", { { "Off", false }, { "On", { [[data\sr_city\spawnables\weapons\launcher\weapon_launcher_shoulder_box_missile_projectile]], [[data\sr_city\spawnables\weapons\launcher\weapon_launcher_missile_explosion]] } } }),
    pset("explosive_melee", "Explosive punches", "Experimental: melee hits explode, your fists too. Switch away and back if it doesn't take. Pair it with God mode, and save first.", { { "Off", false }, { "On", [[data\sr_city\spawnables\weapons\launcher\weapon_launcher_missile_explosion]] } }),
    { kind = "console_list", class = "char_cust_outfit", handler = 0x14055C0, what = "Wearing", label = "Wear any outfit", help = "Experimental: Left/Right picks a whole outfit, any of the game's, Enter wears it. Undo my look puts you back.", sel = 1, options = {} },
    { kind = "console_list", class = "skill_info", handler = 0x68B530, what = "Equipped", label = "Equip any skill", help = "Experimental: Left/Right picks any skill, Enter gives it to you and equips it (saved with your game).", sel = 1, options = {} },
    { kind = "game_list", class = "radio_newscast_info", label = "Newscast", help = "Experimental: Left/Right picks any newscast, Enter plays it. Later ones spoil the story, and you've finished it.", sel = 1, options = {}, code = [[newscast_play(vlib_info_object:get_object("radio_newscast_info", %q))]] },
    gcall("Stop newscast", "Stops the newscast.", [[newscast_stop() return 'Stopped']]),
    { kind = "hq_theme", label = "HQ room theme", help = "Experimental: rebuilds your headquarters' rooms in another level's look (saved with your game). Don't stand inside if you can help it.", sel = 1, options = { { "Normal", false }, { "Level 1", "hq_level_1" }, { "Level 2", "hq_level_2" }, { "Level 3", "hq_level_3" }, { "Dead", "hq_room_theme_ct_dead" } } },
    { kind = "any_vehicle", label = "Any vehicle", help = "Experimental: Left/Right picks any of the game's vehicles, rare and reward ones too. Next row picks its variant.", sel = 1, options = ANY_VEHICLES },
    { kind = "any_variant", label = "Variant", help = "Experimental: Left/Right picks a version, with how you'd normally meet it, Enter spawns it. Some need water or a mission, and may not appear.", sel = 1, options = any_variants(1) },
    pset("rare_traffic", "Rare traffic", "Experimental: cars this district rarely shows come out far more. Only the ones it already lists, and only as they load.", { { "Off", false }, { "On", true } }),
    { kind = "car_effect", label = "Effect on this car", help = "Experimental: Left/Right picks one, Enter: the car you're in, or the nearest, gets it for 30 seconds.", sel = 1,
      options = { { "Slippery", "slippery" }, { "Super grip", "supergrip" }, { "Plow", "plow" }, { "Vehicular manslaughter", "vehicular_manslaughter" } } },
    { kind = "proto_weapon", label = "Prototype weapon", help = "Experimental, press twice: a weapon no list in the game names, in place of what's in its slot, whose icon and name it shows. May not work, or may crash: save first.", sel = 1,
      options = { { "Full-auto police shotgun", "weapon_shotgun_police_full_auto", 5 }, { "Idols miniboss SMG", "weapon_smg_idols_miniboss_hidden", 3 }, { "Idols knife", "weapon_melee_idols_subgrunt_knife", 1 }, { "Panther claws", "weapon_panteros_specialist_melee", 1 }, { "Coyote's bite", "weapon_melee_coyote", 1 }, { "Frost shield", "weapon_frostlander_shield_player", 8 }, { "Sticky bomb", "weapon_special_sticky_proximity_bomb", 7 }, { "Small mine", "weapon_proximity_mine_small", 12 } } },
    { kind = "unlock", key = "tidy", label = "Remove test guns", help = "Press twice: takes the 41 dev test guns and vehicle mounts that Own every weapon adds (the TEMP ICON ones) out of your wheel and your save. Own every weapon brings them back." },
    { kind = "unlock", key = "skins", label = "Unlock all weapon skins", help = "Press twice: every weapon skin is yours, in the game's weapon screen. Stays in your save." },
    { kind = "near_effect", label = "Status on everyone near", help = "Experimental: Left/Right picks one, Enter: everyone within 40 m gets it for a few seconds.", sel = 1,
      options = { { "Flee", "flee", 8 }, { "Shock", "electrified", 8 }, { "Panic", "panic", 8 }, { "Blind", "blindness", 8 }, { "Slip", "slippery", 8 }, { "Stagger", "stagger", 3 }, { "Stagger sideways", "side_stagger", 3 }, { "Reel", "reeling", 3 }, { "Fall over", "eat food ragdoll", 3 }, { "Chill", "chill", 8 }, { "Prank fire", "prank_fire", 8 }, { "Prank dissolve", "prank_dissolve", 8 } } },
    { kind = "me_effect", label = "Effect on you", help = "Experimental: a skill's effect for 30 seconds, with no Flow.", sel = 1,
      options = { { "Berserker", "berserk" }, { "Transfusion", "vampire" }, { "Tough Mother", "get_tough" }, { "Overwatch", "overwatch" }, { "Quick Draw", "quick_draw" } } },
    { kind = "wing_now", label = "Wingsuit now", help = "Experimental: opens the wingsuit straight away, putting you 40 m up first if you're on the ground." },
    gcall("Signature ability (this gun)", "Experimental: switches this gun's signature ability on or off, with no challenge to finish (saved with your game).",
      [[local i = player_local_inventory_get_item_info(player_local_inventory_get_active_slot()) local d = weapon_get_ultimate_data(i) if d == 0 then return 'This gun has none' end weapon_set_ultimate_activate_state(i, not d.activated) return d.activated and 'Signature ability off' or 'Signature ability on']]),
    gcall("All signature abilities", "Experimental, press twice: every gun's signature ability on (saved with your game).",
      [[local n = 0 for _, w in vlib_info_object:ipairs("inventory_weapon_info") do if weapon_get_ultimate_data(w) ~= 0 then weapon_set_ultimate_activate_state(w, true) n = n + 1 end end return n .. ' signature abilities on']], true),
    { kind = "surf", label = "Surf nearest car", help = "Experimental: puts you on the nearest vehicle within 15 m, as the game's car surfing does." },
    { kind = "surf_stop", label = "Stop surfing", help = "Experimental: gets you off the vehicle you're surfing." },
    { kind = "send_gang", label = "Send in a gang", help = "Experimental: Left/Right picks who, Enter sets their notoriety to 3 stars and calls in a wave.", sel = 1,
      options = { { "Panteros", 0xCFD91205 }, { "Idols", 0xAF91816E }, { "Marshall", 0xAD77A00A }, { "Police", 0x55BEF8FA } } },
    pset("free_cam", "Free camera", "Experimental: the camera flies free while you stay put. Left stick or W A S D, RT or Space up, LT or Ctrl down, click the stick or Shift to go fast. You can't walk while it's on.", { { "Off", false }, { "On", true } }),
    pset("skip_intro", "Skip intro", "Experimental: skips the logos at start-up, if you have a save. Save tweaks to keep it: it works from the next start.", { { "Off", false }, { "On", true } }),
    { kind = "special_person", label = "Special person", help = "Left/Right picks a boss, ghost, skeleton, mascot or other hard-to-find character, Enter spawns them. Some may just stand there.", sel = 1, options = { { "Sergio, Panteros boss", 0xDCE51BE6 }, { "Atticus, Marshall boss", 0x034278F8 }, { "Atticus, formal", 0xAAA6FDA8 }, { "Gwen", 0x28A8EC7B }, { "Gwen, battle gear", 0x15908C61 }, { "Gwen, gala", 0xDC5AF17A }, { "Dust King", 0x1D515B0E }, { "Nahualli boss", 0x0C716465 }, { "Nahualli, prison", 0x7DA925AA }, { "Wally", 0x67B9A90C }, { "Frostlander Queen", 0xBC931455 }, { "Karl as Thegn", 0x5BCBA1B8 }, { "Myra Starr", 0x54F025E6 }, { "JimRob, Marshall", 0xD6942A10 }, { "Evil spirit", 0xB20AA33D }, { "Doc Ketchum", 0x6A6005F3 }, { "Genki", 0x7A86E560 }, { "Mr Big", 0x7755874D }, { "John Blande", 0x5237E8B8 }, { "Stab Lincoln", 0x1A53AAB9 }, { "Skeleton, red male", 0x9DBA3030 }, { "Skeleton, red female", 0x14E5AF45 }, { "Skeleton, blue male", 0x077C1307 }, { "Skeleton, blue female", 0x2685E4C5 }, { "Skeleton, green male", 0xD4C79E63 }, { "Skeleton, green female", 0xB41D6640 }, { "Chicken, female", 0x2915B12E }, { "Thrall, female", 0x39F1A42A }, { "Ghost, victim", 0x4B8E3E08 }, { "Ghost Saint 2", 0x513FDC41 }, { "Ghost Saint 3", 0x7C03058B }, { "Ghost Saint 4", 0xB9A43B05 }, { "Oldesteel mascot", 0xAF39DC23 }, { "Twisty mascot", 0xA56D935B }, { "Roadrunner mascot", 0xA09AD9B5 }, { "Hostile mascot 1", 0x3693E344 }, { "Hostile mascot 2", 0x41225090 }, { "Hostile mascot 3", 0x7A992D13 }, { "Hostile mascot 4", 0x10F7555B }, { "Hostile mascot 5", 0x00D35732 }, { "Hostile mascot 6", 0x43EC16C0 }, { "Mannequin 2", 0x820BC491 }, { "Furry 2", 0x697FF87C }, { "Gimp 1", 0x23B092ED }, { "Gimp 2", 0xE664D346 }, { "Grindler Davis", 0x878F797C }, { "Movie star", 0x52343131 }, { "Shotdog", 0x54BEFCD2 }, { "Assassin, female", 0xA6B16C9D }, { "Assassin, male", 0x36EFBC36 }, { "Furloughed soldier", 0x8302786E }, { "Chicken", 0x14BECB08 }, { "Big chicken", 0x3D30397E }, { "Mime", 0x3AC8420F }, { "Grandma", 0x56B3FA95 }, { "Necromancer", 0x081D88E9 }, { "Thrall", 0x7FE1AE66 }, { "Panteros Gigante", 0x8046C9D3 }, { "Wrestler mascot", 0xC9EC39AC }, { "Thumper", 0xF20C6DB8 }, { "Idols enforcer, cop", 0x749A38DE }, { "Police tank crew", 0x53F6572A }, { "Ghost, businessman", 0x58421D8D }, { "Ghost, conductor", 0x6E8323A5 }, { "Ghost, girl", 0x7F26949D }, { "Ghost, prospector", 0xC05EF71E }, { "Ghost Saint", 0x9498E2CF }, { "Coyote", 0x7932AF07 }, { "Hotdog mascot", 0x9470E338 }, { "Hot sauce mascot", 0x02EC61BD }, { "Ketchup mascot", 0xEA958148 }, { "Bunny mascot", 0x2761093B }, { "Cat mascot", 0x795A97A1 }, { "Coyote mascot", 0x02A90DA4 }, { "Dog mascot", 0x32D42A32 }, { "Leopard mascot", 0xB6E229D9 }, { "Alien", 0x554C38BC }, { "Bodysuit", 0xB491B1CF }, { "Taco terror", 0x2109925B }, { "Furry Saint", 0x50F2C4B9 }, { "Hitman Saint", 0xFE75544E }, { "Nixon", 0x28CED4F9 }, { "Reagan", 0x1F2F0947 }, { "Mannequin", 0x19290B59 }, { "Hazmat", 0x109C2A4D }, { "GI", 0xBB62C8DB }, { "Scrubs", 0x0D7B17F6 }, { "Dancer", 0xFE77057A }, { "Sandy Kraken", 0x5FB8E1E8 } } },
    { kind = "crowd", label = "Spawn a crowd", help = "Ten of the character picked above, in a ring around you." },
    { kind = "random_people", label = "Spawn 10 random people", help = "Ten of the game's characters, picked at random, around you." },
    { kind = "despawn", label = "Remove spawned people", help = "Experimental: removes everyone the menu spawned." },
    { kind = "cash_drop", label = "Drop cash", help = "Left/Right picks how much, Enter drops it 8 m ahead of you. It's real money: it stays in your save.", sel = 1, options = { { "$1,000", 1000 }, { "$10,000", 10000 }, { "$100,000", 100000 } } },
    { kind = "weapon_drop", label = "Drop weapon", help = "Left/Right picks a weapon, Enter drops it 6 m ahead of you. Walking onto it collects it (saved in your game).", sel = 1, options = {} },
    pset("rain", "Money rain", "Cash falls all around you ($250 a pile; what you pick up stays in your save).", { { "Off", false }, { "Light", 30 }, { "Heavy", 8 } }),
    { kind = "unlock", key = "icons", label = "Show activities on the map", help = "Experimental, press twice: diversions, flashpoints and discoverables." },
    { kind = "reaction", label = "Everyone near", help = "Left/Right picks a reaction, Enter: everyone within 40 m does it.", sel = 1,
      options = { { "Cheer", "cheer" }, { "Laugh", "laugh" }, { "Taunt", "taunt" }, { "Take pics", "take pics" }, { "Wave", "wave" }, { "Hype", "hype emote" }, { "Angry", "angry" }, { "Disgusted", "disgusted" } } },
    { kind = "arms", armed = false, label = "Disarm everyone near", help = "Experimental: people within 40 m can't use their guns (new arrivals still can)." },
    { kind = "arms", armed = true, label = "Re-arm everyone near", help = "Gives people within 40 m their guns back." },
    { kind = "crowd_act", key = "ragdoll", label = "Ragdoll everyone near", help = "Everyone within 40 m falls over." },
    { kind = "crowd_act", key = "kill", label = "Kill everyone near", help = "Everyone within 40 m dies, as if you shot them. Mission characters are left alone." },
    { kind = "crowd_act", key = "fire", label = "Set everyone near on fire", help = "Everyone within 40 m bursts into flames, as if you lit them." },
    { kind = "crowd_act", key = "stun", label = "Stun everyone near", help = "Experimental: everyone within 40 m is stunned where they stand." },
    { kind = "crowd_act", key = "hostile", label = "Make everyone near hostile", help = "Experimental: everyone within 40 m turns on you for an hour." },
    { kind = "crowd_act", key = "friendly", label = "Make everyone near friendly", help = "Experimental: everyone within 40 m joins the Saints' side." },
    { kind = "crowd_act", key = "follow", label = "Make everyone near follow you", help = "Experimental: everyone within 40 m joins your side and stays with you." },
    { kind = "crowd_act", key = "dance", label = "Everyone near dance", help = "Experimental: everyone within 40 m starts dancing." },
    pset("no_guns", "Gangs and police without guns", "Experimental: everyone near you keeps being disarmed, new arrivals too.", { { "Off", false }, { "On", true } }),
    pset("side_gang", "Gang on your side", "Experimental: this gang counts as your ally. Use Never wanted too, as notoriety still sends them after you.", { { "None", false }, { "Idols", "idol" }, { "Panteros", "panteros" }, { "Marshal", "marshal" }, { "Police", "police" }, { "All", "all" } }),
    pset("saints_enemies", "Saints are enemies", "Experimental: Saints in the world count you as hostile.", { { "Off", false }, { "On", true } }),
    pset("forget_fast", "Notoriety forgets fast", "Experimental: out of sight, notoriety clears in a second instead of the game's seven.", { { "Off", false }, { "On", true } }),
    { kind = "crowd_act", key = "float", label = "Float everyone near", help = "Experimental: everyone within 40 m floats up about 14 m, then comes back down." },
    { kind = "crowd_act", key = "dissolve", label = "Dissolve everyone near", help = "Experimental: everyone within 40 m dissolves and is gone in 2 seconds." },
    { kind = "crowd_act", key = "toxic", label = "Poison everyone near", help = "Experimental: everyone within 40 m gets the toxic effect and loses health until they drop, about 6 s." },
    pset("no_call_ins", "No reinforcements", "Experimental: wanted factions don't call in more people.", { { "Off", false }, { "On", true } }),
    pset("no_roadblocks", "No roadblocks", "Experimental: no roadblocks when you're wanted.", { { "Off", false }, { "On", true } }),
    pset("no_escape", "Can't lose them", "Experimental: you can't evade a pursuit by getting away.", { { "Off", false }, { "On", true } }),
    { kind = "crowd_act", key = "cars", label = "Blow up cars near", help = "Every vehicle within 40 m explodes, except the one you're in." },
    { kind = "wdset", key = "empty_streets", label = "Empty streets", help = "Experimental: no more people or traffic appear; the ones out there go as you leave them.", options = { { "Off", false }, { "On", true } }, sel = 1, save_key = "world.empty_streets" },
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
    choice("Screen filter", "Left/Right applies it.", {
      { "Off", false }, { "Black & white", "screen_effect_black_white" }, { "Retro", "screen_effect_retro" },
      { "Night vision", "screen_effect_night_vision" }, { "Old-timey", "screen_effect_old_timey" },
      { "Vapor", "screen_effect_vapor" }, { "Western", "screen_effect_western" }, { "Steamboat", "screen_effect_steamboat" } }, "filter"),
    opt("Field of view", "The game's camera field of view option, wider than its menu allows at the top.",
      "option_get_camera_fov_offset()", "option_set_camera_fov_offset(%s)",
      { { "0", 0 }, { "0.25", 0.25 }, { "0.5", 0.5 }, { "0.75", 0.75 }, { "1", 1 }, { "1.5", 1.5 } }),
    opt("Camera shake", "The game's camera shake option.", "option_get_camera_shake_enabled()", "option_set_camera_shake_enabled(%s)", { { "On", 1 }, { "Off", 2 } }),
    opt("Looping camera shake", "The game's looping camera shake option (engines, idle sway).", "option_get_looping_camera_shake_enabled()", "option_set_looping_camera_shake_enabled(%s)", { { "On", 1 }, { "Off", 2 } }),
    opt("Camera bobbing", "The game's camera bobbing option.", "option_get_camera_bobbing_enabled()", "option_set_camera_bobbing_enabled(%s)", { { "On", 1 }, { "Off", 2 } }),
    gchoice("Shoulder camera", "Experimental: Left/Right moves the camera over a shoulder, or back to the middle.", {
      { "Centred", "gml_set_camera_ndc_offset(0, 0) return 'centred'" }, { "Right shoulder", "gml_set_camera_ndc_offset(0.45, 0) return 'right'" },
      { "Left shoulder", "gml_set_camera_ndc_offset(-0.45, 0) return 'left'" } }),
    { kind = "camset", key = "turn", label = "Turn speed", help = "Experimental: how fast the camera turns, mouse and controller, past the options' top.", options = { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 } }, sel = 1, save_key = "camera.turn" },
    { kind = "camset", key = "bright", label = "Brightness", help = "Experimental: while it's on, the game stops adjusting brightness by itself (indoors, night).", options = { { "Game's", 0 }, { "Brighter", -1 }, { "Much brighter", -2 }, { "Darker", 1 }, { "Much darker", 2 } }, sel = 1 },
    pset("render_hide", "Hide from view", "Experimental: stops drawing the sky, particles, shadows or tree billboards.", { { "Nothing", false }, { "Sky", 0x8000 }, { "Particles", 0x4000 }, { "Shadows", 0x1000 }, { "Far trees", 0x20000 } }),
    gchoice("Low health screen", "Experimental: the red screen effects when you're hurt.", { { "On", [[gml_ui_gem_raise_event("ui_enable_hud_full_screen_effects", 1, "enable", true) return "on"]] }, { "Off", [[gml_ui_gem_raise_event("ui_enable_hud_full_screen_effects", 1, "enable", false) return "off"]] } }),
    gchoice("Show only people", "Experimental: hides the world's background, as the game's demo mode does.", { { "Off", [[demo_hide_background(false) return "off"]] }, { "On", [[demo_hide_background(true) return "on"]] } }),
    pset("cam_distance", "Camera distance", "Experimental: how far behind you the camera sits. First person is from inside your head; aiming stays as it was.", { { "Game's", false }, { "First person", 0.01 }, { "Close", 1.5 }, { "Far", 6 }, { "Very far", 14 } }),
    gchoice("Letterbox", "Black bars, as in the game's cutscenes.", { { "Off", [[gml_ui_gem_raise_event("segue_letterbox_end") return "off"]] }, { "On", [[gml_ui_gem_raise_event("segue_letterbox_begin") return "on"]] } }),
    gcall("Photo mode", "The game's photo mode: a free camera. Close the menu to move it; press again to leave.", "cell_photo_mode_toggle() return cell_photo_mode_is_active() and 'on' or 'off'"),
    { kind = "hud", label = "Hide HUD", help = "Experimental: hides the HUD the way the game's own option does.", options = { { "Off", false }, { "On", true } }, sel = 1, save_key = "visual.hide_hud" },
  } },
  { name = "Settings", rows = {
    gcall("Skip cutscene", "Skips the cutscene that's playing.", "cinematic_skip() return 'skipped'"),
    gcall("Pause / resume cutscene", "Pauses the cutscene that's playing, or resumes it.", "if rawget(_G, 'SR5TM_CINE_PAUSED') then cinematic_resume() rawset(_G, 'SR5TM_CINE_PAUSED', nil) return 'resumed' else cinematic_pause() rawset(_G, 'SR5TM_CINE_PAUSED', true) return 'paused' end"),
    gcall("Quick save", "Experimental: the game's autosave, now (needs Autosave on in the game's options).", "game_save_request_autosave() return 'saving'"),
    gcall("Load last save", "Loads your newest save (press twice). Unsaved progress is lost.", "gml_ui_save_game_request_load_newest() return 'loading'", true),
    opt("Tutorial popups", "The game's tutorial popups option (0 = none).", "options_get_tutorial_frequency()", "options_set_tutorial_frequency(%s)", { { "Off", 0 }, { "1", 1 }, { "2", 2 }, { "3", 3 } }),
    { kind = "mset", key = "tweaks_paused", label = "All tweaks", help = "Off: every menu tweak back to the game's for now. On: they all come back. Cheats stay.", options = { { "On", false }, { "Off", true } }, sel = 1 },
    { kind = "mset", key = "hold_back", label = "Hold Back opens the menu", help = "Experimental: hold Back (View) for a second to open or close the menu. The game sees it too.", options = { { "Off", false }, { "On", true } }, sel = 1, save_key = "menu.hold_back" },
    { kind = "clean", label = "Keep my save clean", help = "Spicy cheats don't mark your save; achievements pause only while one is on." },
    { kind = "opacity", label = "Menu opacity", help = "How dark the panel behind the menu is. Left/Right." },
    { kind = "active", label = "What's on", help = "Lists every tweak and cheat that's on right now." },
    { kind = "all_off", label = "Turn every cheat off", help = "Switches off every toggle cheat that's on." },
    { kind = "normal", label = "Everything back to normal", help = "Every menu tweak back to the game's (press twice). Cheats and game options stay." },
    { kind = "save_now", label = "Save tweaks for next time", help = "Your tweaks stay as you set them until you quit; this keeps them for the next start." },
    { kind = "forget", label = "Forget saved tweaks", help = "Clears what Save keeps; this starts fresh." },
    { kind = "close", label = "Close menu", help = "F5, or hold RB and press D-pad Down, opens it again." },
  } },
}

-- Rows that are settings rather than one-off actions: picking with
-- Left/Right applies them (after a short pause, so scrolling past options
-- doesn't fire each one). Actions (spawn, teleport, give, unlock) still wait
-- for Enter.
local APPLY_ON_PICK = { ["Weather"] = true, ["Time of day"] = true, ["Screen filter"] = true, ["Shoulder camera"] = true, ["Letterbox"] = true, ["Low health screen"] = true, ["Show only people"] = true }
for _, t in ipairs(TABS) do for _, r in ipairs(t.rows) do if APPLY_ON_PICK[r.label] then r.apply = true end end end

-- The rows grouped: each tab is a list of pages, then rows of its own. "Cheats" holds
-- the game's own phone cheats. A row not named here stays at the end of its tab.
local LAYOUT = {
  { "Player", {
    { "Health and survival", "God mode, health, and what can't hurt you.", { "God mode", "Health", "Refill health", "Health regen", "No fall damage", "No ragdoll", "No flinch", "Dodge safe time", "Bulletproof", "Explosion-proof", "Crash-proof", "Get up", "Kill yourself" } },
    { "Movement", "How you run, jump and fall.", { "Run speed", "Jump height", "Air control", "Swim speed", "Your gravity", "No clip", "Movement style", "Walk style" } },
    { "Wingsuit", "Boosts, power, speed and glide.", { "Wingsuit boosts", "Wingsuit boost power", "Wingsuit top speed", "Wingsuit glide", "Wingsuit from low down", "Wingsuit now" } },
    { "Flow and abilities", "Your ability meter, skills and takedowns.", { "All perks on", "Equip any skill", "Effect on you", "Unlimited Flow", "Free skills", "Flow gain", "Extra Flow bars", "Flow never drains", "Rampage at full Flow", "Takedown cooldown" } },
    { "Emotes and voice", "Emotes, expressions and how you sound.", { "D-pad emote 1", "D-pad emote 2", "Play emote", "Hidden emote", "Repeat emote", "Freeze emote", "Stop emote", "Facial expression", "Your voice", "Voice pitch", "Say a line" } },
    { "Homies", "Who's with you.", { "Summon homie", "Call in Saints", "Dismiss homies", "Homie limit" } },
    { "Your look", "Who you are and what you're wearing.", { "Play as spawned person", "Back to yourself", "Saved look", "Character preset", "Wear any outfit", "Hidden outfit", "Undo my look", "Take a look snapshot", "Customize character", "Prank yourself" } },
    { "Body beyond limits", "Past the sliders' ends. Only on screen: your save keeps your real body.", { "Body: muscle", "Body: fat", "Body: thin", "Body: chest", "Body: blend", "Face: head shape", "Face: eye size", "Face: nose size", "Face: mouth size", "Back to my real body" } },
    { "Money and progress", "XP, skill points, cash and prices.", { "Give XP", "Give skill points", "Add cash", "Free shopping", "Free ventures", "Start mission", "Insurance Fraud here" } },
    { "Unlocks", "Skills, perks, weapons, clothing and more. These stay in your save.", { "Unlock EVERYTHING", "Unlock fast travel points", "Own every weapon", "Unlock all skills", "Unlock all perks", "Unlock gang and homies", "Unlock all clothing", "Unlock everything in the stores", "Unlock all weapon skins", "Unlock all collectibles" } },
  } },
  { "Weapons", {
    { "Gun tuning", "Fire rate, damage, recoil and the rest of how guns behave.", { "Fire rate", "Full auto", "Damage", "Magazine", "Reload speed", "No recoil", "Perfect aim", "Range", "Knockback", "Blast radius", "Friendly fire", "Back shot damage", "No warm-up", "No overheat" } },
    { "Special ammo", "What your shots and hits do.", { "Special ammo", "Rocket rounds", "Explosive punches", "Money gun" } },
    { "Get weapons", "Give, fill, upgrade or remove.", { "Give weapon", "Special weapon", "Refill all ammo", "Max every weapon's upgrades", "Prototype weapon", "Signature ability (this gun)", "All signature abilities", "Remove this weapon", "Remove test guns" } },
    "Weapons back to normal",
  } },
  { "Vehicles", {
    { "Spawning", "Getting vehicles and getting rid of them.", { "Spawn vehicle", "Special vehicle", "Any vehicle", "Variant", "Remove spawned vehicles", "Deliver to garage" } },
    { "Handling", "Power, grip and how it sits on the road.", { "Engine power", "Grip", "Steering", "Vehicle top speed", "Suspension", "Vehicle gravity", "Heavy vehicle" } },
    { "Toughness", "Keeping it in one piece, or not.", { "Vehicle god mode", "No collision damage", "Bulletproof tires", "Keep vehicle repaired", "Destroy this vehicle" } },
    { "Abilities and combat", "Vehicle abilities, rams and takedowns.", { "Vehicle ability", "Tow hook", "Boost now", "Effect on this car", "Launch this vehicle", "Jump this vehicle", "Surf nearest car", "Stop surfing", "Vehicle jump power", "No ability cooldowns", "Ram power", "Takedowns at any speed" } },
    { "Look and camera", "Paint, lights and the driving camera.", { "Next paint", "Brake lights stay on", "Car camera resets after", "Free camera in cars" } },
  } },
  { "Teleport", {
    "Go to waypoint", "Auto-teleport to waypoint", "Warp from map", "Store", "Map place", "Fast travel point",
    { "Saved places", "Your own spots.", { "Save this spot", "Go to", "Delete that place" } },
    "Go up", "Where am I",
  } },
  { "World", {
    { "Time and weather", "The clock, the sky and pausing.", { "Game speed", "Slow motion button", "Weather (all)", "Freeze clock", "Clock speed", "Go to time", "Pause world" } },
    { "Developer switches", "Left in the game by its developers. Most do unknown things.", { "Dev: never die", "Dev: never die, AI", "Dev: Shawn mode", "Dev: capture mode", "Dev: auto sprint", "Dev: infinite ammo", "Dev: infinite magazine", "Dev: radio on", "Dev: vehicle ramps", "Dev: weapon raycasts", "Dev: notoriety bubbles", "Dev: HQ mask off" } },
    { "Spawn people", "Who to spawn, and what they do.", { "Spawn person", "Special person", "Spawned people", "Spawn a crowd", "Spawn 10 random people", "Remove spawned people" } },
    { "Everyone near", "Everyone within 40 m.", { "Everyone near", "Status on everyone near", "Make everyone near follow you", "Everyone near dance", "Make everyone near friendly", "Make everyone near hostile", "Disarm everyone near", "Re-arm everyone near", "Stun everyone near", "Ragdoll everyone near", "Float everyone near", "Set everyone near on fire", "Dissolve everyone near", "Poison everyone near", "Kill everyone near", "Blow up cars near" } },
    { "Notoriety and gangs", "Who's after you, and whose side they're on.", { "Never wanted", "Enemy aim", "Send in a gang", "Stay in combat", "Notoriety forgets fast", "No reinforcements", "No roadblocks", "Can't lose them", "Gangs and police without guns", "Gang on your side", "Saints are enemies" } },
    { "Gang war", "Gangs and people fighting each other.", { "Gang war", "Zombie outbreak", "Riot", "Free for all", "Gang presence", "NPC fight damage", "Pedestrians fight back", "Everyone battle ready", "Downed, not dead" } },
    { "Physics and explosions", "Gravity, blasts and sending things flying.", { "World gravity", "Explosion size", "Explosion force", "Explosion damage", "Hurting yourself", "Knocked over", "Launch everyone near" } },
    { "Population", "How busy the streets are.", { "Pedestrians", "Traffic", "Rare traffic", "Traffic pop-in", "Crowds in the rain", "People panic", "No parked cars" } },
    { "Music", "Stations, songs and playing them anywhere.", { "Radio station", "Music anywhere", "Play song", "Skip track", "Pause or resume music", "Now playing", "Newscast", "Stop newscast" } },
    { "Props and HQ", "Spawn props anywhere, or dress your headquarters.", { "Spawn prop", "Remove last prop", "Remove all props", "HQ spot", "HQ prop", "Clear this HQ spot", "HQ room theme" } },
    { "Money and drops", "Cash and weapons on the ground.", { "Drop cash", "Drop weapon", "Money rain" } },
    { "Difficulty", "The pause menu's custom sliders.", { "Difficulty: player health", "Difficulty: player damage", "Difficulty: enemies", "Difficulty: vehicles", "Difficulty: notoriety", "Difficulty: ammo reserve", "Difficulty: timer speed" } },
    "Empty streets", "Show activities on the map",
  } },
  { "Visual", {
    { "Camera", "Where the camera sits and how it moves.", { "Field of view", "Camera distance", "Shoulder camera", "Turn speed", "Camera shake", "Looping camera shake", "Camera bobbing", "Photo mode", "Free camera" } },
    { "Screen", "What's drawn.", { "Brightness", "Hide from view", "Low health screen", "Show only people", "Letterbox", "Hide HUD" } },
  } },
  { "Cheats", {
    { "Player", "The game's own phone cheats.", { "Invincibility (game's)", "Give cash", "Max level", "Super Saints", "Milk Bones", "Pratfall", "Heaven Bound" } },
    { "Weapons", "The game's own phone cheats.", { "Infinite ammo", "Golden gun" } },
    { "Vehicles", "The game's own phone cheats.", { "Repair vehicle", "Drop a car", "Infinite boost", "Infinite mass", "No traffic laws" } },
    { "Traffic", "The game's own phone cheats: what's on the roads.", { "Monster truck traffic", "Luxury traffic", "Mascots" } },
    { "World", "The game's own phone cheats.", { "Weather", "Time of day", "Screen filter", "Low gravity", "Angry pedestrians" } },
    { "Notoriety", "The game's own phone cheats: raise, clear or max.", { "Police", "Idols", "Marshal", "Los Panteros" } },
  } },
  { "Settings", {
    "Save tweaks for next time",
    { "Game", "Cutscenes, saving and tutorials.", { "Skip intro", "Skip cutscene", "Pause / resume cutscene", "Quick save", "Load last save", "Tutorial popups" } },
    { "Menu", "How the menu looks and opens.", { "All tweaks", "Hold Back opens the menu", "Keep my save clean", "Menu opacity" } },
    "What's on", "Turn every cheat off", "Everything back to normal", "Forget saved tweaks", "Close menu",
  } },
}
do
  local by_label, home = {}, {}
  for _, t in ipairs(TABS) do
    for _, r in ipairs(t.rows) do by_label[r.label] = r; home[r] = t.name end
  end
  local used, built = {}, {}
  local function take(label)
    local r = by_label[label]
    if r and not used[r] then used[r] = true; return r end
    return nil
  end
  for _, spec in ipairs(LAYOUT) do
    local rows = {}
    for _, item in ipairs(spec[2]) do
      if type(item) == "string" then
        local r = take(item)
        if r then rows[#rows + 1] = r end
      else
        local page = { kind = "page", label = item[1], help = item[2], rows = {} }
        for _, label in ipairs(item[3]) do
          local r = take(label)
          if r then page.rows[#page.rows + 1] = r end
        end
        if #page.rows > 0 then rows[#rows + 1] = page end
      end
    end
    built[#built + 1] = { name = spec[1], rows = rows }
  end
  for _, t in ipairs(TABS) do
    for _, r in ipairs(t.rows) do
      if not used[r] then
        wml.log("menu: row not in a page: " .. tostring(r.label))
        for _, b in ipairs(built) do if b.name == home[r] then b.rows[#b.rows + 1] = r end end
      end
    end
  end
  TABS = built
end

-- Settings kept from last time (tweaks.lua).
local function all_rows()
  local rows = {}
  for _, t in ipairs(TABS) do
    for _, r in ipairs(t.rows) do
      if r.kind == "page" then for _, c in ipairs(r.rows) do rows[#rows + 1] = c end
      else rows[#rows + 1] = r end
    end
  end
  return rows
end
-- What's on screen: the page you're in, or the tab.
local function view() return M.page or TABS[M.tab] end
local function view_cursor() if M.page then return M.page.cursor or 1 end return M.cursor[M.tab] or 1 end
-- Puts a row's value where its module reads it.
local function set_value(r, v)
  if r.kind == "wset" then W.set[r.key] = v elseif r.kind == "pset" then P[r.key] = v
  elseif r.kind == "wdset" then Wd[r.key] = v
  elseif r.kind == "wsset" then WS.set[r.key] = v
  elseif r.kind == "mvset" then P.move[r.key] = v
  elseif r.kind == "carset" then P.car[r.key] = v
  elseif r.kind == "camset" then Cam[r.key] = v
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
  local kept = SR5TM_SESSION or T.saved
  if kept.clean then M.clean = kept.clean == "on" end
  if kept.opacity then U.opacity = tonumber(kept.opacity) or U.opacity end
  M.unsaved = SR5TM_UNSAVED
end
-- Changing a tweak keeps it for this session (and through a reload of these files); only
-- Save writes the file. The menu used to reread the launch copy on a reload, which undid
-- whatever had been set since.
local function saveable()
  local rows = all_rows()
  rows[#rows + 1] = { save_key = "clean", options = { { M.clean and "on" or "off" } }, sel = 1 }
  rows[#rows + 1] = { save_key = "opacity", options = { { tostring(U.opacity) } }, sel = 1 }
  -- with All tweaks off, the tweaks put aside are what's kept
  local function swap() for r, sel in pairs(M.stash or {}) do r.sel, M.stash[r] = sel, r.sel end end
  return rows, swap
end
function M.save_tweaks()
  local rows, swap = saveable()
  swap()
  local kept = {}
  for _, row in ipairs(rows) do
    if row.options and row.save_key and row.options[row.sel] then kept[row.save_key] = row.options[row.sel][1] end
  end
  swap()
  local differs = false
  for k, v in pairs(kept) do if T.saved[k] ~= v then differs = true end end
  SR5TM_SESSION, SR5TM_UNSAVED, M.unsaved = kept, differs, differs
end
function M.save_now()
  local rows, swap = saveable()
  swap()
  local ok = T.save(rows)
  swap()
  if ok then T.load(); SR5TM_UNSAVED, M.unsaved = false, false end
  return ok
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
    M.gun_dirty = true
  elseif not off and M.stash then
    for r, sel in pairs(M.stash) do r.sel = sel; set_value(r, r.options[sel][2]) end
    M.stash = nil
    if W.any_on() then W.apply() end
    if WS.any_on() then WS.apply() end
    M.gun_dirty = true
  end
  M.tweaks_paused = off
end
apply_saved()

-- Rows only for cheats this game has; options likewise.
local function prune()
  local lists = {}
  for _, tab in ipairs(TABS) do
    lists[#lists + 1] = tab
    for _, row in ipairs(tab.rows) do if row.kind == "page" then lists[#lists + 1] = row end end
  end
  for _, tab in ipairs(lists) do
    local kept = {}
    for _, row in ipairs(tab.rows) do
      if row.kind == "page" then kept[#kept + 1] = row
      elseif row.cheat then
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

-- A game name for the menu: underscores to spaces, each word capitalised.
local function pretty(name) return (name:gsub("_", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end)) end

-- The names of every object of a class (the game's tostring of each), a
-- batch a call. Each call stops walking once its batch is full: walking a
-- class makes a userdata per object, and the game's Lua has a small pool
-- (the 14,000 voice line situations ran it out when walked whole each time).
-- `collect`: a full collection first, for very long classes.
local function names_of(cls, collect, n)
  local out, first, N = {}, 1, n or 25
  while true do
    local res = table.pack(wml.game((collect and 'collectgarbage("collect") ' or "") .. [[local i, o = 0, {} for _, x in vlib_info_object:ipairs("]] .. cls .. [[") do
      i = i + 1 if i >= ]] .. first .. [[ then o[#o + 1] = tostring(x) if #o == ]] .. N .. [[ then break end end end return #o, unpack(o)]]))
    if not res[1] then break end
    for j = 3, res.n do out[#out + 1] = res[j] end
    first = first + N
    if res[2] < N then break end
  end
  return out
end
-- every object of a class: { name, hash (the name's hash, from its id) }
local function names_of_objects(cls)
  local out, first, N = {}, 1, 20
  while true do
    local res = table.pack(wml.game([[local i, o = 0, {} for _, x in vlib_info_object:ipairs("]] .. cls .. [[") do
      i = i + 1 if i >= ]] .. first .. [[ then o[#o + 1] = tostring(x) o[#o + 1] = x if #o == ]] .. (2 * N) .. [[ then break end end end return #o, unpack(o)]]))
    if not res[1] then break end
    for j = 3, res.n, 2 do
      local p = tonumber(tostring(res[j + 1]):match("(%x+)>$") or "", 16)
      if p then out[#out + 1] = { name = res[j]:match('"(.*)"') or res[j], hash = (wml.read_u64(p + 0x28) >> 32) & 0xFFFFFFFF, class = wml.read_u64(p + 0x28) & 0xFFFFFFFF } end
    end
    first = first + N
    if res[2] < 2 * N then break end
  end
  return out
end

-- The player's voice lines: of the game's ~14,000 line situations (nearly
-- all mission dialogue), the generic ones a character says anywhere. Loaded
-- the first time the row is used (about a second), with a collection each
-- call, then the game's Lua collected again.
local VOICE = { combat = true, voice = true, special = true, misc = true, observe = true, threat = true, cower = true, flee = true, drunk = true }
local function load_voice_lines(row)
  for _, l in ipairs(names_of("gml_line_situation", true, 200)) do
    local name = l:match('"(.*)"') or l
    local pre = name:match("^(%a+)_")
    if pre and VOICE[pre] and not name:find("%d%d") then row.options[#row.options + 1] = { pretty(name), l, name } end
  end
  wml.game('collectgarbage("collect")')
  table.sort(row.options, function(a, b) return a[1] < b[1] end)
  row.loaded = true
end

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

-- Unlocks, a few at a time over the next frames (M.unlock.queue):
-- * collectibles: gml_collectibles_award(name hash, 1) for every object of
--   the collectible classes, as the game awards a found one.
-- * stores: each store inventory's clothing gets m_purchased on its data record
--   (what the wardrobe's owned list reads; the award does nothing for clothing),
--   its emotes are awarded like a collectible. (The game's console handler for
--   this, +A68880, crashed it.) Store weapons are left to Own every weapon.
-- * weapons: +988830(info, 1), the owned flag buying a weapon sets.
-- Achievements wait meanwhile: the spicy session flag is held (the game's
-- achievement code skips while it's set).
local COLLECTIBLES = { "collectible_wearable_info", "collectible_emote", "collectible_weapon_info", "collectible_vehicle_info", "building_customization_prop_info" }
local function add_awards(q, classes)
  local batch
  for _, cls in ipairs(classes) do
    for _, o in ipairs(names_of_objects(cls)) do
      if not batch or #batch == 20 then batch = {}; q[#q + 1] = { award = batch } end
      batch[#batch + 1] = "gml_collectibles_award(" .. o.hash .. ", 1)"
    end
  end
end
-- What's left at 0 after the award (three emotes refuse it): m_available written
-- to 1 directly, as many as a step's call can return.
local REFUSED = { { "collectible_emote", "collectible_emote_state" }, { "skill_info", "skill_info_data" }, { "perk_entry", "perk_entry_state" } }
local unlock_queue
function unlock_queue(key, q)
  if key == "weapons" then
    for _, o in ipairs(names_of_objects("inventory_weapon_info")) do q[#q + 1] = { weapon = o.name } end
  elseif key == "travel" then
    add_awards(q, { "city_warp_point" })
  elseif key == "icons" then
    for _, cls in ipairs({ "discoverable_info", "diversion_info", "flashpoint_info" }) do
      for _, o in ipairs(names_of_objects(cls)) do q[#q + 1] = { icon = o.hash } end
    end
  elseif key == "stores" then
    for i, o in ipairs(names_of_objects("store_inventory_info")) do
      q[#q + 1] = { store = o.hash, index = i, first = 0 }
    end
  elseif key == "skills" then
    add_awards(q, { "skill_info" })
    q[#q + 1] = { refused = REFUSED[2] }
  elseif key == "perks" then
    add_awards(q, { "perk_entry", "perk_slot" })
    q[#q + 1] = { refused = REFUSED[3] }
  elseif key == "gang" then
    add_awards(q, { "gang_customization", "gang_vehicle_customization", "homie_info", "homie_outfit" })
  elseif key == "clothing" then
    q[#q + 1] = { clothing = true, first = 0 }
  elseif key == "skins" then
    for _ = 1, 10 do q[#q + 1] = { refused = { "weapon_skin", "weapon_skin_state" } } end
  elseif key == "tidy" then
    for _, o in ipairs(names_of_objects("inventory_weapon_info")) do
      if P.weapon_is_internal(o.name) then q[#q + 1] = { disown = o.name } end
    end
    q[#q + 1] = { clear_slots = true }
  elseif key == "everything" then
    for _, k in ipairs({ "travel", "weapons", "skins", "stores", "clothing", "skills", "perks", "gang", "collectibles", "icons" }) do unlock_queue(k, q) end
  else
    add_awards(q, COLLECTIBLES)
    q[#q + 1] = { refused = REFUSED[1] }
  end
end
local function start_unlock(row)
  local q = {}
  unlock_queue(row.key, q)
  if #q == 0 then say(row.label .. ": nothing found (load into the game first)", "warn"); return end
  M.unlock = { queue = q, label = row.label, done = 0, total = #q }
  say(row.label .. ": working...")
end
local function step_unlock()
  local u = M.unlock
  C.allow_spicy(); M.spicy_hold = math.max(M.spicy_hold, 300)
  local item = table.remove(u.queue, 1)
  if item and item.store then
    -- this store's clothing, 40 a step: the purchased flag on each item's data
    local r = table.pack(wml.game([[local i = 0 for _, s in vlib_info_object:ipairs("store_inventory_info") do i = i + 1 if i == ]] .. item.index .. [[ then
      local o, n = {}, 0
      for _, w in s.m_wearables:ipairs() do
        n = n + 1
        if n > ]] .. item.first .. [[ then
          local x = w:get_info("char_cust_wearable_info")
          if x:exists() then
            local d = x:get_data("char_cust_wearable_data")
            if d:exists() then o[#o + 1] = d.m_purchased end
          end
          if #o == 40 then break end
        end
      end
      return n, unpack(o) end end]]))
    local V = require("vdata")
    if r[1] then
      for j = 3, r.n do
        local a = V.field_addr(r[j])
        if a and wml.read_u8(a) == 0 then wml.write_u8(a, 1); u.items = (u.items or 0) + 1 end
      end
    end
    if r[1] and r.n - 2 == 40 then
      table.insert(u.queue, 1, { store = item.store, index = item.index, first = r[2] })
    else
      -- and its emotes, awarded like a collectible
      r = table.pack(wml.game([[local i = 0 for _, s in vlib_info_object:ipairs("store_inventory_info") do i = i + 1 if i == ]] .. item.index .. [[ then
        local o = {}
        for _, w in s.m_emotes:ipairs() do o[#o + 1] = w:get_info("collectible_emote") if #o == 60 then break end end
        return unpack(o) end end]]))
      local awards = {}
      if r[1] then
        for j = 2, r.n do
          local q = V.ptr(r[j])
          if q then awards[#awards + 1] = "gml_collectibles_award(" .. ((wml.read_u64(q + 0x28) >> 32) & 0xFFFFFFFF) .. ", 1)" end
        end
      end
      for i = 1, #awards, 20 do wml.game(table.concat(awards, " ", i, math.min(i + 19, #awards))) end
      u.items = (u.items or 0) + #awards
      u.done = u.done + 1
    end
  elseif item and item.disown then
    if P.disown_weapon(item.disown) then u.items = (u.items or 0) + 1 end
    u.done = u.done + 1
  elseif item and item.clear_slots then
    P.clear_internal_slots()
    u.done = u.done + 1
  elseif item and item.refused then
    local r = table.pack(wml.game([[local o = {} for _, x in vlib_info_object:ipairs("]] .. item.refused[1] .. [[") do
      local d = x:get_data("]] .. item.refused[2] .. [[")
      if d:exists() and d.m_available:get_number() <= 0 then o[#o + 1] = d.m_available if #o == 40 then break end end
    end return unpack(o)]]))
    local V = require("vdata")
    if r[1] then
      for j = 2, r.n do
        local a = V.field_addr(r[j])
        if a and wml.read_u32(a) == 0 then wml.write_u32(a, 1); u.items = (u.items or 0) + 1 end
      end
    end
    u.done = u.done + 1
  elseif item and item.clothing then
    -- every clothing record, 40 a step, whether a store sells it or not
    local r = table.pack(wml.game([[collectgarbage("collect") local o, n = {}, 0
      for _, x in vlib_info_object:ipairs("char_cust_wearable_info") do
        n = n + 1
        if n > ]] .. item.first .. [[ then
          local d = x:get_data("char_cust_wearable_data")
          if d:exists() then o[#o + 1] = d.m_purchased end
          if #o == 40 then break end
        end
      end
      return n, unpack(o)]]))
    local V = require("vdata")
    if r[1] then
      for j = 3, r.n do
        local a = V.field_addr(r[j])
        if a and wml.read_u8(a) == 0 then wml.write_u8(a, 1); u.items = (u.items or 0) + 1 end
      end
    end
    if r[1] and r.n - 2 == 40 then table.insert(u.queue, 1, { clothing = true, first = r[2] })
    else u.done = u.done + 1 end
  elseif item and item.weapon then
    if P.own_weapon(item.weapon) then u.done = u.done + 1 end
  elseif item and item.icon then
    -- gameplay_type_show_oi_node's call: +742650(&name hash, 1 show, 0 no banner)
    local buf = wml.buffer(12)
    wml.write_u32(buf, item.icon)
    wml.call(wml.base + 0x742650, buf, 1, 0)
    u.done = u.done + 1
  elseif item and item.award then
    if wml.game(table.concat(item.award, " ")) then u.done = u.done + 1 end
  end
  if #u.queue == 0 then
    say(u.label .. ": done (" .. u.done .. " of " .. u.total .. (u.label:find("stores") and (" stores, " .. (u.items or 0) .. " items)") or u.label:find("clothing") and (" lists, " .. (u.items or 0) .. " items)") or u.label:find("weapon") and " weapons)" or " batches)"))
    wml.log("unlock: " .. u.label .. ", " .. u.done .. " of " .. u.total .. (u.items and (", " .. u.items .. " items") or ""))
    M.unlock = nil
  end
end

local CROWD = { ragdoll = { "ragdoll_near", "ragdolled" }, kill = { "kill_near", "killed" }, fire = { "fire_near", "set on fire" },
  stun = { "stun_near", "stunned" }, launch = { "launch_near", "launched" }, zombies = { "zombies_near", "near an outbreak" }, riot = { "riot_near", "rioting" }, downed = { "downed_near", "won't die" }, follow = { "follow_near", "following you" }, float = { "float_near", "floating" }, dissolve = { "dissolve_near", "dissolving" }, toxic = { "toxic_near", "poisoned" }, dance = { "dance_near", "dancing" }, hostile = { "hostile_near", "turned on you" }, friendly = { "friendly_near", "on your side" } }
local function select_row(row)
  wml.log("row: " .. tostring(row.label) .. (row.options and row.options[row.sel] and (" = " .. tostring(row.options[row.sel][1])) or ""))   -- so a crash log says what was last pressed
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
  elseif row.kind == "unlock" then
    if M.unlock then say("Unlocking already: wait for it to finish", "warn")
    elseif M.pending_confirm ~= row then M.pending_confirm = row; say(row.label .. ": press again to confirm (saved with your game)", "warn")
    else M.pending_confirm = nil; start_unlock(row) end
  elseif row.kind == "gchoice" then
    local o = row.options[row.sel]
    local ok, msg = wml.game(o[2])
    say(row.label .. ": " .. tostring(ok and (msg or "done") or msg), ok and "status" or "warn")
  elseif row.kind == "camset" then
    M.adjust_camset(row, 1)
  elseif row.kind == "refill_ammo" then
    wml.call(wml.base + 0x662FF0)
    say("Ammo refilled")
  elseif row.kind == "weathernode" then
    local o = row.options[row.sel]
    if not o then say("No weathers (load into the game first)", "warn") else
      local ok, err = wml.game("gml_weather_state_set_node(" .. string.format("%q", o[2]) .. ")")
      say(ok and ("Weather: " .. o[1]) or ("Weather: " .. tostring(err)), ok and "status" or "warn")
    end
  elseif row.kind == "giveweapon" or row.kind == "voiceline" then
    if row.kind == "voiceline" and not row.loaded then load_voice_lines(row); say(#row.options .. " voice lines: Left/Right picks, Enter says it"); return end
    local o = row.options[row.sel]
    if not o then say("Nothing to pick (load into the game first)", "warn") else
      local code = row.kind == "giveweapon"
        and ([[for _, w in vlib_info_object:ipairs("inventory_weapon_info") do if tostring(w) == ]] .. string.format("%q", o[2]) .. [[ then weapon_swap_to_inventory(w) return end end]])
        or ("avatar_play_line_situation(" .. string.format("%q", o[3]) .. ")")
      local ok, err = wml.game(code)
      say(ok and (row.label .. ": " .. o[1]) or (row.label .. ": " .. tostring(err)), ok and "status" or "warn")
    end
  elseif row.kind == "waypoint" then
    local x, y, z, slot = P.waypoint()
    if not x then say("No waypoint set: put one on the map first", "warn")
    elseif P.teleport(x, y + 1, z) then say(slot == 0 and "Off to your waypoint" or "Off to the mission marker")
    else say("The game refused the teleport", "warn") end
  elseif row.kind == "cash_drop" then
    local o = row.options[row.sel]
    say(P.drop_cash(o[2], 0, 2, 8) and (o[1] .. " dropped ahead of you") or "Couldn't drop cash right now", "status")
  elseif row.kind == "weapon_drop" then
    local o = row.options[row.sel]
    local ok, v = wml.game("return string_crc(" .. string.format("%q", o and o[2] or "") .. ")")
    if not o then say("Nothing to pick (load into the game first)", "warn")
    else say(ok and P.drop_pickup(math.floor(v) & 0xFFFFFFFF, 1, 0, 1, 6) and (o[1] .. " dropped ahead of you") or "Couldn't drop it right now", "status") end
  elseif row.kind == "destroy_car" then
    if M.pending_confirm ~= row then M.pending_confirm = row; say(row.label .. ": press again to confirm", "warn")
    else
      M.pending_confirm = nil
      say(P.destroy_car() and "Boom" or "You're not in a vehicle", "status")
    end
  elseif row.kind == "reaction" then
    local o = row.options[row.sel]
    local n = P.near_reaction(o[2], 40)
    say(n == 0 and "Nobody near" or (n .. (n == 1 and " person: " or " people: ") .. o[1]))
  elseif row.kind == "arms" then
    local n = P.near_arms(row.armed, 40)
    say(n == 0 and "Nobody near" or (n .. (n == 1 and " person " or " people ") .. (row.armed and "re-armed" or "disarmed")))
  elseif row.kind == "play_as" then
    if row.back then say(P.back_to_self() and "You again" or "You're already you", "status")
    else say(P.play_as_spawned() and "You're them now: Back to yourself returns" or "Spawn someone first (World > Spawn person)", "status") end
  elseif row.kind == "outfit" then
    local o = row.options[row.sel]
    if not o then say("No saved looks", "warn") else
      P.look_first()
      local ok, err = wml.game([[local n, c = 0, gml_get_local_player():get_component_by_type("gml_component_character_customization")
        for _, p in vlib_info_data_object:ipairs("char_cust_player_saved_preset_data") do n = n + 1
          if n == ]] .. o[2] .. [[ then gml_customization_apply_player_preset(c, p, true, true) return end end]])
      say(ok and ("Wearing " .. o[1]) or tostring(err), ok and "status" or "warn")
    end
  elseif row.kind == "look_preset" then
    local o = row.options[row.sel]
    if not o then say("No presets", "warn")
    elseif M.pending_confirm ~= row then M.pending_confirm = row; say(row.label .. ": " .. o[1] .. ": press again to replace your character", "warn")
    else
      M.pending_confirm = nil
      P.look_first()
      local ok, err = wml.game([[gml_customization_apply_preset(gml_get_local_player():get_component_by_type("gml_component_character_customization"), vlib_info_object:get_object("char_cust_preset", ]] .. string.format("%q", o[2]) .. [[))]])
      say(ok and ("Now " .. o[1]) or tostring(err), ok and "status" or "warn")
    end
  elseif row.kind == "song" then
    local o = row.options[row.sel]
    local ok, err = wml.game([[local pv = vlib_info_object:get_object("playlist_info", "custom_preview") playlist_remove_all_songs(pv) playlist_add_song(pv, vlib_info_object:get_object("radio_song_info", ]] .. string.format("%q", o[2]) .. [[)) playlist_play(pv)]])
    say(ok and ("Playing " .. o[1]) or tostring(err), ok and "status" or "warn")
  elseif row.kind == "skip_track" then
    say(P.radio_skip())
  elseif row.kind == "spawn_prop" then
    say(P.spawn_prop(row.options[row.sel][2]) and ("Loading " .. row.options[row.sel][1] .. "...") or "Couldn't load that", "status")
  elseif row.kind == "remove_prop" then
    local n = P.remove_prop(row.last)
    say(n == 0 and "No props to remove" or (n .. (n == 1 and " prop" or " props") .. " removed"))
  elseif row.kind == "hq_spot" then
    say("Now pick the prop on HQ prop")
  elseif row.kind == "hq_prop" or row.kind == "hq_clear" then
    local spot
    for _, r in ipairs(all_rows()) do if r.kind == "hq_spot" then spot = r.options[r.sel] end end
    local prop = row.kind == "hq_prop" and string.format("%q", row.options[row.sel][2]) or [[vlib_info_object:invalid("building_customization_prop_info")]]
    local ok, err = wml.game("hq_customization_set_prop(" .. string.format("%q", spot[2]) .. ", " .. prop .. ")")
    say(not ok and tostring(err) or (row.kind == "hq_prop" and (row.options[row.sel][1] .. " on " .. spot[1]) or (spot[1] .. " cleared")), ok and "status" or "warn")
  elseif row.kind == "look_undo" then
    if M.pending_confirm ~= row then M.pending_confirm = row; say(row.label .. ": press again to confirm", "warn")
    else M.pending_confirm = nil; say(P.look_restore() and "Back to your snapshot" or "Nothing to undo", "status") end
  elseif row.kind == "look_snap" then
    say(P.look_snapshot() and "Snapshot taken" or "Couldn't right now", "status")
  elseif row.kind == "body_back" then
    P.body_back()
    for _, r in ipairs(all_rows()) do if r.key and r.key:find("^body_") then r.sel = 1 end end
    M.save_tweaks()
    say("Your real body")
  elseif row.kind == "go_to_hour" then
    local o = row.options[row.sel]
    say(P.go_to_hour(o[2]) and (o[1] .. " it is") or "The game won't move the clock right now", "status")
  elseif row.kind == "console_row" then
    say(P.console(row.handler) == 0 and (row.label .. ": done") or "The game refused", "status")
  elseif row.kind == "outfit_any" then
    local o = row.options[row.sel]
    P.look_first()
    say(P.console(0x13DE6D0, o[2]) == 0 and ("Wearing " .. o[1]) or "The game refused", "status")
  elseif row.kind == "console_list" then
    local o = row.options[row.sel]
    if o then
      if row.class == "char_cust_outfit" then P.look_first() end
      say(P.console(row.handler, o[2]) == 0 and (row.what .. " " .. o[1]) or "The game refused", "status")
    end
  elseif row.kind == "game_list" then
    local o = row.options[row.sel]
    if o then
      local ok, err = wml.game(string.format(row.code, o[2]))
      say(ok and (o[1] .. ": on") or tostring(err), ok and "status" or "warn")
    end
  elseif row.kind == "hq_theme" then
    local o = row.options[row.sel]
    P.hq_theme(o[2])
    say("HQ rooms: " .. o[1])
  elseif row.kind == "launch_car" then
    local o = row.options[row.sel]
    say(P.launch_car(o[2]) and (o[1] .. "!") or "No vehicle near", "status")
  elseif row.kind == "revive_me" then
    say(P.revive_me() and "Up you get" or "Couldn't right now", "status")
  elseif row.kind == "car_effect" then
    local o = row.options[row.sel]
    local car = P.vehicle_object() or P.nearest_car(30)
    if not car then say("No vehicle near", "warn")
    else say(P.effect_on(car, o[2], 30) and (o[1] .. " for 30 s") or "That vehicle won't take it", "status") end
  elseif row.kind == "proto_weapon" then
    local o = row.options[row.sel]
    if M.pending_confirm ~= row then M.pending_confirm = row; say(o[1] .. ": press again. Save first", "warn")
    else M.pending_confirm = nil; say(P.give_prefab_weapon(o[2], o[3]) and ("Loading " .. o[1] .. "...") or "Couldn't load that", "status") end
  elseif row.kind == "near_effect" then
    local o = row.options[row.sel]
    local n = P.near_effect(o[2], o[3], 40)
    say(n == 0 and "Nobody near" or (n .. (n == 1 and " person: " or " people: ") .. o[1]))
  elseif row.kind == "me_effect" then
    local o = row.options[row.sel]
    say(P.effect_on(P.object(), o[2], 30) and (o[1] .. " for 30 s") or "Couldn't right now", "status")
  elseif row.kind == "wing_now" then
    say(P.wingsuit_now() and "Wingsuit" or "Couldn't right now", "status")
  elseif row.kind == "surf" then
    local ok, why = P.surf_nearest()
    say(ok and "Surf's up" or why, ok and "status" or "warn")
  elseif row.kind == "surf_stop" then
    say(P.surf_stop() and "Off the car" or "Couldn't right now", "status")
  elseif row.kind == "send_gang" then
    local o = row.options[row.sel]
    P.send_gang(o[2], 3)
    say(o[1] .. " on their way")
  elseif row.kind == "special_person" then
    local o = row.options[row.sel]
    say(P.spawn_npc(o[2], 2, 4) and (o[1] .. " spawned") or "Couldn't spawn them right now", "status")
  elseif row.kind == "any_vehicle" or row.kind == "any_variant" then
    local v, w
    for _, r in ipairs(all_rows()) do
      if r.kind == "any_vehicle" then v = r.options[r.sel] elseif r.kind == "any_variant" then w = r.options[r.sel] end
    end
    select_row({ kind = "special_car", label = "Any vehicle", sel = 1, options = { { v[1] .. ": " .. w[2], v[2], w[2] } } })
  elseif row.kind == "special_car" then
    local o = row.options[row.sel]
    if not C.by_name.drop_car then say("Load into the game first", "warn") else
      -- one drop: the first garage entry points at this vehicle only for this call
      local e = wml.read_u64(wml.base + 0x2F371F0)
      local a, b = wml.read_u32(e + 0x10), wml.read_u32(e + 0x14)
      local _, x = wml.game("return string_crc(" .. string.format("%q", o[2]) .. ")")
      local _, y = wml.game("return string_crc(" .. string.format("%q", o[3]) .. ")")
      wml.write_u32(e + 0x10, math.floor(x) & 0xFFFFFFFF)
      wml.write_u32(e + 0x14, math.floor(y) & 0xFFFFFFFF)
      wml.write_u32(wml.base + 0x3110E08, 0)
      C.allow_spicy(); M.spicy_hold = 120
      P.watch_spawned_car()
      local ok = C.activate("drop_car")
      wml.write_u32(e + 0x10, a)
      wml.write_u32(e + 0x14, b)
      say(ok and (o[1] .. " on its way") or "The game refused", ok and "status" or "warn")
    end
  elseif row.kind == "mission" then
    local o = row.options[row.sel]
    if not o then say("No missions listed", "warn")
    elseif M.pending_confirm ~= row then M.pending_confirm = row; say(o[1] .. ": press again. Use a spare save.", "warn")
    else
      M.pending_confirm = nil
      local ok, err = wml.game("mission_request_start(vlib_info_object:get_object('mission_info', " .. string.format("%q", o[2]) .. "))")
      say(ok and ("Starting " .. o[1]) or tostring(err), ok and "status" or "warn")
    end
  elseif row.kind == "call_saints" then
    local o = row.options[row.sel]
    say(P.call_saints(o[2]) and (o[1] .. " called in") or "Couldn't right now", "status")
  elseif row.kind == "prank" then
    local o = row.options[row.sel]
    say(P.set_prank(o[2]) and ("Prank: " .. o[1]) or "That prank isn't available", "status")
  elseif row.kind == "car_ability" then
    local o = row.options[row.sel]
    say(P.car_equip_ability(o[2]) and (o[1] .. " on this vehicle") or "Get in a vehicle first", "status")
  elseif row.kind == "map_place" then
    local o = row.options[row.sel]
    if not o then say("Nothing on the map yet: open the menu again near some", "warn")
    else say(P.go_to_object(o[2]) and ("Off to " .. o[1]) or "That place isn't loaded right now", "status") end
  elseif row.kind == "car_act" then
    if row.key == "tow" then
      say(P.car_tow_hook() and "Tow hook on" or "Get in a vehicle first", "status")
    elseif row.key == "remove" then
      local n = P.remove_spawned_cars()
      say(n == 0 and "No spawned vehicles to remove" or (n .. " spawned " .. (n == 1 and "vehicle" or "vehicles") .. " removed"))
    elseif not P.vehicle_object() then say("Get in a vehicle first", "warn")
    elseif row.key == "boost" then P.car_boost(); say("Boost")
    elseif row.key == "jump" then P.car_jump(); say("Up you go")
    else
      local i, n = P.car_next_paint()
      say(i and i ~= 0 and ("Paint " .. i .. " of " .. tostring(n)) or "No paints for this vehicle", i and i ~= 0 and "status" or "warn")
    end
  elseif row.kind == "kill_self" then
    if P.god then say("Turn God mode off first", "warn")
    elseif M.pending_confirm ~= row then M.pending_confirm = row; say(row.label .. ": press again to confirm", "warn")
    else M.pending_confirm = nil; say(P.kill_self() and "Goodbye" or "Couldn't right now", "status") end
  elseif row.kind == "crowd_act" then
    if row.key == "cars" then
      local n = P.destroy_near(40)
      say(n == 0 and "No vehicles near" or (n .. (n == 1 and " vehicle" or " vehicles") .. " blown up"))
    else
      local act = CROWD[row.key]
      local n = P[act[1]](40)
      say(n == 0 and "Nobody near" or (n .. (n == 1 and " person " or " people ") .. act[2]))
    end
  elseif row.kind == "despawn" then
    local n = P.remove_spawned()
    say(n == 0 and "Nobody to remove" or (n .. " spawned " .. (n == 1 and "person" or "people") .. " removed"))
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
    for _, r in ipairs(all_rows()) do if r.kind == "wset" then r.sel = 1; W.set[r.key] = r.options[1][2] end end
    W.restore()
    M.gun_dirty = true
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
      P.watch_spawned_car()
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
      M.gun_dirty = true
      M.save_tweaks()
      say("Everything back to the game's own")
    end
  elseif row.kind == "page" then
    M.page = row
    row.cursor = row.cursor or 1
    M.pending_confirm = nil
  elseif row.kind == "save_now" then
    say(M.save_now() and "Saved: your tweaks will be back next start" or "Couldn't write the file", "status")
  elseif row.kind == "forget" then
    T.forget()
    SR5TM_SESSION, SR5TM_UNSAVED, M.unsaved = nil, false, false
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
  elseif row.kind == "wset" or row.kind == "pset" or row.kind == "hud" or row.kind == "opt" or row.kind == "wdset" or row.kind == "wsset" or row.kind == "mvset" or row.kind == "carset" or row.kind == "camset" then
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
  elseif row.kind == "voiceline" and not row.loaded then
    return "Enter to load", "off"
  elseif row.kind == "active" or row.kind == "normal" or row.kind == "random_people" or row.kind == "emote_stop" or row.kind == "waypoint" or row.kind == "despawn" or row.kind == "refill_ammo" or row.kind == "unlock" or row.kind == "crowd_act" or row.kind == "arms" or row.kind == "destroy_car" or row.kind == "kill_self" or row.kind == "car_act" or row.kind == "play_as" or row.kind == "revive_me" or row.kind == "console_row" or row.kind == "look_undo" or row.kind == "look_snap" or row.kind == "body_back" or row.kind == "wing_now" or row.kind == "surf" or row.kind == "surf_stop" or row.kind == "skip_track" or row.kind == "remove_prop" or row.kind == "hq_clear" then
    return "Enter", "off"
  elseif row.kind == "page" then
    return #row.rows .. "  >", "off"
  elseif row.kind == "save_now" then
    return M.unsaved and "Not saved" or "Saved", M.unsaved and "on" or "off"
  elseif row.kind == "mset" then
    local o = row.options[row.sel]
    return "<  " .. o[1] .. "  >", row.sel == 1 and "off" or "on"
  elseif row.kind == "any_vehicle" or row.kind == "any_variant" or row.kind == "console_list" or row.kind == "game_list" or row.kind == "hq_theme" or row.kind == "launch_car" or row.kind == "go_to_hour" or row.kind == "outfit_any" or row.kind == "car_effect" or row.kind == "proto_weapon" or row.kind == "song" or row.kind == "spawn_prop" or row.kind == "hq_spot" or row.kind == "hq_prop" or row.kind == "near_effect" or row.kind == "me_effect" or row.kind == "send_gang" or row.kind == "lift" or row.kind == "warp" or row.kind == "deliver" or row.kind == "homie" or row.kind == "emote" or row.kind == "emote_slot" or row.kind == "giveweapon" or row.kind == "voiceline" or row.kind == "gchoice" or row.kind == "weathernode" or row.kind == "cash_drop" or row.kind == "weapon_drop" or row.kind == "reaction" or row.kind == "map_place" or row.kind == "outfit" or row.kind == "look_preset" or row.kind == "call_saints" or row.kind == "prank" or row.kind == "car_ability" or row.kind == "special_person" or row.kind == "special_car" or row.kind == "mission" then
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
  local tab = view()
  local cur = view_cursor()
  local lines = {}
  lines[1] = { label = "SR5 Tweak Menu", value = "Cash " .. C.money(M.cash), colour = "title", value_colour = "off" }
  local names = {}
  for i, t in ipairs(TABS) do names[#names + 1] = (i == M.tab) and t.name:upper() or t.name end
  lines[2] = { label = M.page and (TABS[M.tab].name .. "  >  " .. M.page.label .. "     (Backspace goes back)") or table.concat(names, "   "), colour = "tabs" }
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
  elseif M.unsaved then lines[ROWS + 5] = { label = "Tweaks changed: Settings > Save tweaks keeps them for next start", colour = "off" }
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
  M.gun_dirty = true
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

function M.adjust_camset(row, delta)
  row.sel = (row.sel - 1 + delta) % #row.options + 1
  Cam[row.key] = row.options[row.sel][2]
  M.save_tweaks()
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
  local tab = view()
  local n = #tab.rows
  if n == 0 then return end
  local c = (view_cursor() - 1 + delta) % n + 1
  if M.page then M.page.cursor = c else M.cursor[M.tab] = c end
  M.pending_confirm = nil
end
local function change_tab(delta) M.page = nil; M.tab = (M.tab - 1 + delta) % #TABS + 1 end
local function adjust(delta)
  local row = view().rows[view_cursor()]
  if row and row.options then
    local n, o = #row.options, nil
    if n > 0 then o = row.options[(row.sel - 1 + delta) % n + 1] end
    if row.save_key or row.kind == "wdset" then wml.log("set: " .. tostring(row.label) .. " = " .. tostring(o and o[1])) end
  end
  if row and M.stash then M.stash[row] = nil end
  if row and row.kind == "voiceline" and not row.loaded then load_voice_lines(row) end
  if row and row.kind == "mset" then M.adjust_mset(row, delta)
  elseif row and row.kind == "wset" then M.adjust_wset(row, delta)
  elseif row and row.kind == "pset" then M.adjust_pset(row, delta)
  elseif row and row.kind == "hud" then M.adjust_hud(row, delta)
  elseif row and row.kind == "opt" then M.adjust_opt(row, delta)
  elseif row and row.kind == "wdset" then M.adjust_wdset(row, delta)
  elseif row and row.kind == "wsset" then M.adjust_wsset(row, delta)
  elseif row and row.kind == "mvset" then M.adjust_mvset(row, delta)
  elseif row and row.kind == "carset" then M.adjust_carset(row, delta)
  elseif row and row.kind == "camset" then M.adjust_camset(row, delta)
  elseif row and row.kind == "places" then
    if #P.places > 0 then row.sel = (row.sel - 1 + delta) % #P.places + 1 end
  elseif row and row.options then
    row.sel = (row.sel - 1 + delta) % #row.options + 1
    if row.apply then M.apply_row, M.apply_wait = row, 20 end
    if row.kind == "any_vehicle" then
      for _, r in ipairs(all_rows()) do if r.kind == "any_variant" then r.options, r.sel = any_variants(row.sel), 1 end end
    end
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
    elseif (r.kind == "console_list" or r.kind == "game_list") and #r.options == 0 then
      for _, w in ipairs(names_of(r.class)) do local n = w:match('"(.*)"') or w; r.options[#r.options + 1] = { pretty(n), n } end
      table.sort(r.options, function(a, b) return a[1] < b[1] end)
    elseif r.kind == "giveweapon" and #r.options == 0 then
      for _, w in ipairs(names_of("inventory_weapon_info")) do r.options[#r.options + 1] = { pretty((w:match('"(.*)"') or w)), w } end
      table.sort(r.options, function(a, b) return a[1] < b[1] end)
    elseif r.kind == "weapon_drop" and #r.options == 0 then
      for _, w in ipairs(names_of("collectible_weapon_info")) do
        local name = w:match('"(.*)"') or w
        r.options[#r.options + 1] = { pretty(name), name }
      end
      table.sort(r.options, function(a, b) return a[1] < b[1] end)
    elseif r.kind == "weathernode" and #r.options == 0 then
      -- gml_weather_state_set_node takes a node's name (any case)
      -- the weathers themselves, not the overlays (critters, blowing trash) or transitions
      for _, w in ipairs(names_of("gml_weather_state_node_settings")) do
        local name = w:match('"(.*)"') or w
        do
          r.options[#r.options + 1] = { pretty((name:gsub("^wsn_", ""))), name }
        end
      end
      table.sort(r.options, function(a, b) return a[1] < b[1] end)
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
    if r.kind == "mission" and #r.options == 0 then
      for _, w in ipairs(names_of("mission_info")) do
        local name = w:match('"(.*)"') or w
        r.options[#r.options + 1] = { pretty(name), name }
      end
      table.sort(r.options, function(a, b) return a[1] < b[1] end)
    end
    if r.kind == "outfit" then
      r.options = {}
      local res = table.pack(wml.game([[local o, n = {}, 0 for _, p in vlib_info_data_object:ipairs("char_cust_player_saved_preset_data") do n = n + 1 o[n] = p.title:get_string() if n == 20 then break end end return unpack(o)]]))
      if res[1] then for j = 2, res.n do r.options[#r.options + 1] = { (tostring(res[j]):gsub("^%[raw%]", "")), j - 1 } end end
      if r.sel > #r.options then r.sel = 1 end
    elseif r.kind == "look_preset" and #r.options == 0 then
      for _, w in ipairs(names_of("char_cust_preset")) do
        local name = w:match('"(.*)"') or w
        r.options[#r.options + 1] = { pretty(name), name }
      end
      table.sort(r.options, function(a, b) return a[1] < b[1] end)
    end
    if r.kind == "map_place" then
      -- again on every open: the map publishes more as you travel
      r.options = P.map_places(r.stores)
      local seen = {}
      for _, o in ipairs(r.options) do
        local label = pretty((o[1]:gsub("^store_", ""):gsub("^building_gp_", ""):gsub("^building_", ""):gsub("^popup_", "")))
        seen[label] = (seen[label] or 0) + 1
        o[1] = seen[label] > 1 and (label .. " " .. seen[label]) or label
      end
      if r.sel > #r.options then r.sel = 1 end
    end
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
  -- Skip intro: the logos are the "legal" screen; these are what its skip key calls.
  if P.skip_intro and not M.intro_done then
    if C.loaded then M.intro_done = true
    else
      local ok, r = wml.game([[if vint_document_find("legal") ~= 0 then legal_input_skip() legal_screen_autosave_complete() return true end]])
      if ok and r then M.intro_done = true; wml.log("skipped the intro at frame " .. frame) end
    end
  end
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
  if P.keep_repaired and C.loaded and frame % 60 == 30 and C.by_name.vehicle_health and P.vehicle_object() then C.activate("vehicle_health") end
  if C.loaded and frame % 15 == 10 and P.vgod_active() then P.update_vehicle() end
  if C.loaded and frame % 30 == 25 and P.regen_active() then P.update_regen() end
  if Cam.any_on() then Cam.update(frame) end
  -- No reload: the gun in hand's magazine kept full (every 3 frames), so it
  -- never empties and no reload starts
  if W.set.magazine == "no_reload" and C.loaded and frame % 3 == 0 then P.keep_magazine() end
  -- No recoil: the gun in hand's own recoil too (it keeps its own copy)
  P.no_recoil = W.set.no_recoil
  if C.loaded and frame % 5 == 3 and P.rockets then P.update_rockets() end
  local rk = P.rockets and true or false
  if W.set.rockets ~= rk then W.set.rockets = rk; M.gun_dirty = true end
  -- Full auto also clears the guns' "one shot a trigger pull"
  local auto = P.full_auto and true or false
  if W.set.full_auto ~= auto then W.set.full_auto = auto; M.gun_dirty = true; if C.loaded then W.apply() end end
  -- weapon tweaks on the gun in hand (each new copy, or a changed setting)
  -- every half second, not only for a new gun: the game can fill a gun's values in after
  -- our first write, and the row would still say On (seen live: x8 and No reload not there)
  if C.loaded and frame % 5 == 1 and W.gun_active() then W.update_gun(M.gun_dirty or frame % 30 == 1); M.gun_dirty = false end
  if C.loaded and frame % 5 == 4 and P.recoil_active() then P.update_recoil(P.no_recoil ~= M.recoil_was or (P.no_recoil and frame % 60 == 4)) M.recoil_was = P.no_recoil end
  if C.loaded and frame % 60 == 35 and P.fall_active() then P.update_fall() end
  if C.loaded and frame % 60 == 45 and P.homies_active() then P.update_homies() end
  -- God mode: back up within 2.5 s of a knockdown (you don't get up by yourself with it on)
  if C.loaded and P.god and frame % 150 == 75 then local me = P.object(); if me then wml.call(wml.base + 0x5B0F60, me + 0x58, 0, 3) end end
  if C.loaded then P.update_run(); P.update_jump() end
  if C.loaded and P.kill_active() then P.update_kill_self() end
  if C.loaded then P.update_refire(W.set.fire_rate); P.update_car_watch() end
  if C.loaded and P.money_gun then P.update_money_gun() end
  if C.loaded and frame % 60 == 31 then P.update_sides() end
  if C.loaded and P.move_style ~= (M.move_style_was or false) then P.update_move_style(); M.move_style_was = P.move_style end
  if C.loaded and P.wingsuit_low ~= (M.wing_low_was or false) then P.update_wingsuit_low(); M.wing_low_was = P.wingsuit_low end
  if C.loaded and frame % 300 == 57 then P.reassert() end
  if C.loaded and frame % 60 == 37 then P.update_perks(); P.update_notoriety_nodes(); P.update_ventures() end
  if C.loaded and P.flow ~= (M.flow_was or false) then P.update_flow(); M.flow_was = P.flow end
  if C.loaded and P.takedown ~= (M.takedown_was or false) then P.update_takedown(); M.takedown_was = P.takedown end
  if C.loaded and P.free_skills ~= (M.free_skills_was or false) then P.update_free_skills(); M.free_skills_was = P.free_skills end
  if C.loaded then
    local cfg = tostring(P.car_takedowns) .. tostring(P.car_ram) .. tostring(P.car_jump_power) .. tostring(P.car_ability_cd)
    if cfg ~= M.car_cfg_was then
      if M.car_cfg_was or cfg ~= "falsefalsefalsefalse" then P.update_car_cfg() end
      M.car_cfg_was = cfg
    end
  end
  if C.loaded and frame % 30 == 9 and P.playing_as() then P.check_body() end
  if C.loaded and frame % 300 == 41 and P.proof_active() then P.update_proof() end
  if C.loaded and frame % 120 == 51 and P.no_guns then P.update_no_guns() end
  if C.loaded and P.forget_fast ~= (M.forget_was or false) then P.update_forget(); M.forget_was = P.forget_fast end
  if C.loaded and P.render_hide ~= (M.render_was or false) then P.update_render(); M.render_was = P.render_hide end
  if C.loaded and (P.cam_distance or M.cam_dist_was) then P.update_cam_distance(); M.cam_dist_was = P.cam_distance end
  if C.loaded and P.auto_waypoint and frame % 20 == 3 then P.update_auto_waypoint() end
  if C.loaded and frame % 30 == 7 and P.car_active() then P.update_car_extras() end
  if C.loaded and P.cam_delay ~= (M.cam_delay_was or false) then P.update_cam_delay(); M.cam_delay_was = P.cam_delay end
  if C.loaded and P.walk_style ~= (M.walk_was or false) then P.update_walk(); M.walk_was = P.walk_style end
  if C.loaded and P.clip_active() then P.update_clip(M.open) end
  if C.loaded and frame % 60 == 41 and P.poison_active() then P.update_poison() end
  if C.loaded and P.free_cam_active() then P.update_free_cam(M.open) end
  if C.loaded and P.wing_pending() then P.update_wing() end
  if P.prop_release_pending() then P.update_prop_release() end
  if C.loaded then WS.update_lift(P); WS.update_boost(P) end
  if C.loaded and frame % 60 == 49 and P.tunes_active() then P.update_tunes() end
  if C.loaded and frame % 60 == 57 and P.ffa_active() then P.update_free_for_all() end
  if C.loaded and frame % 120 == 58 and P.rare_active() then P.update_rare_traffic(VEH.rare) end
  if C.loaded and P.explosive_melee and frame % 15 == 6 then P.update_explosive_melee() end
  if C.loaded and P.slow_active() then P.update_slow_button(M.open) end
  if C.loaded and frame % 30 == 26 then P.update_scaled(); P.update_parked() end
  if C.loaded and frame % 60 == 3 and P.gangs_active() then P.update_gang_presence() end
  if C.loaded and frame % 60 == 9 then P.fix_zero_damage(); P.log_state() end
  if C.loaded and P.proto_pending() then
    local r = P.update_proto()
    if r then say(r == "ready" and "Prototype weapon ready: switch to that slot" or ("Prototype weapon " .. r), r == "ready" and "status" or "warn") end
  end
  if C.loaded and (P.blast_size ~= M.bs_was or P.blast_force ~= M.bf_was or P.blast_damage ~= M.bd_was) then P.update_blast(); M.bs_was, M.bf_was, M.bd_was = P.blast_size, P.blast_force, P.blast_damage end
  if C.loaded and frame % 30 == 53 then P.update_switches(); P.update_enemy_aim() end
  if C.loaded and frame % 60 == 55 and P.war_active() then P.update_war() end
  if C.loaded and (P.game_speed or M.speed_was) and frame % 30 == 16 then P.update_speed(); M.speed_was = P.game_speed end
  if C.loaded and (P.force_combat or M.combat_was) and frame % 60 == 46 then P.update_force_combat(); M.combat_was = P.force_combat end
  if C.loaded and (P.warp_map or M.warp_was) and frame % 15 == 8 then P.update_warp(); M.warp_was = P.warp_map end
  if C.loaded and (P.friendly_fire or M.ff_was) and frame % 60 == 44 then P.update_friendly_fire(); M.ff_was = P.friendly_fire end
  if C.loaded and frame % 120 == 47 and P.body_active() then P.update_body() end
  if C.loaded and P.prop_pending() then
    local r = P.update_prop()
    if r then say(r == "spawned" and "Prop spawned" or ("Prop " .. r), r == "spawned" and "status" or "warn") end
  end
  if C.loaded and frame % 30 == 12 then P.update_gravity() end
  if C.loaded and frame % 30 == 17 and (P.tires or P.tires_set) then P.update_tires() end
  if C.loaded and frame % 30 == 22 and (P.spring ~= 1 or M.spring_was) then P.update_spring(); M.spring_was = P.spring ~= 1 end
  if frame % 30 == 27 and P.spawned_pending() then P.spawn_settle() end
  if frame % 30 == 12 and P.hostile_pending() then P.update_hostile() end
  if C.loaded and P.rain then P.update_rain() end
  -- Free shopping, when it changes
  if C.loaded and (P.free_shop and true or false) ~= (M.shop_was or false) then
    local n = P.update_free_shop()
    M.shop_was = P.free_shop and true or false
    if M.shop_was then wml.log("free shopping: " .. n .. " categories") end
  end
  -- special ammo: on a change, the gun in your hands; then any new gun
  if C.loaded and frame % 5 == 2 and (P.ammo or M.ammo_was) then
    P.update_ammo(P.ammo ~= M.ammo_was or (P.ammo and frame % 120 == 2))
    M.ammo_was = P.ammo
  end
  if M.unlock and C.loaded and frame % 6 == 0 then step_unlock() end
  -- No ragdoll: the game's stop-ragdoll (+5B0F60(&id, 0, 3), what the
  -- Pratfall controls call to get up), the player's id at entry +0x58
  if P.no_ragdoll and C.loaded and frame % 3 == 0 then
    local p = P.object()
    if p then wml.call(wml.base + 0x5B0F60, p + 0x58, 0, 3) end
  end
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
  -- a setting picked with Left/Right: applied once the pick settles
  if M.apply_wait then
    M.apply_wait = M.apply_wait - 1
    if M.apply_wait <= 0 then
      local r = M.apply_row
      M.apply_row, M.apply_wait = nil, nil
      select_row(r)
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
  -- Full auto's simulated clicks only on a gun that's single-shot by nature:
  -- on an automatic one they just interrupt its own firing.
  local pulse = P.full_auto and W.gun_single and P.full_auto or false
  if wml.auto_fire and pulse ~= M.auto_fire_was then
    wml.auto_fire(pulse and true or false, pulse or 70)
    M.auto_fire_was = pulse
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
    local row = view().rows[view_cursor()]
    if row then select_row(row) end
  end
  if wml.key_pressed("BACKSPACE") or (pressed & PAD.B ~= 0) then
    if M.page then M.page = nil else M.open = false end
  end

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
