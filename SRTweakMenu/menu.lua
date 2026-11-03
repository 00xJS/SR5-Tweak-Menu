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
require("shots")
require("cars")
require("weapons_mix")
require("drops")
require("creator")
require("clone")
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
  local out = { { "Yours", "local v = rawget(_G, 'SR5TM_VOICE') if v then customization_set_avatar_persona(v) return 'Back to yours' end return 'Not changed yet'" } }
  for _, v in ipairs({ "player_f1", "player_f2", "player_f3", "player_f4", "player_m1", "player_m2", "player_m3", "player_m4" }) do
    local label = (v:find("_f") and "Female " or "Male ") .. v:sub(-1)
    out[#out + 1] = { label, "if not rawget(_G, 'SR5TM_VOICE') then rawset(_G, 'SR5TM_VOICE', customization_get_avatar_persona()) end customization_set_avatar_persona('" .. v .. "') return '" .. label .. "'" }
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
  { "World: Witch broom", "dlc_sp04_item_witch-broom_01a" },
  { "World: Pumpkin smash", "dlc_sp05_item_pumpkin-smash_01a" },
  { "World: Headstone haunted 01a husk", "prop_headstone-haunted_01a-husk" },
  { "World: Monument haunted 01a husk", "prop_monument-haunted_01a-husk" },
  { "World: Statue gargoyle 01a husk", "prop_statue-gargoyle_01a-husk" },
  { "World: Train steam engine haunted", "prop_train_steam-engine-haunted_01a" },
  { "World: Real estate hh ghost mover", "real_estate_hh_ghost_mover" },
  { "World: Dreidel emote", "dlc_fp03_dreidel-emote_01a" },
  { "World: Player emote snowball group", "dlc_fp03_prop_player-emote-snowball-group_01a" },
  { "World: Player emote snowball", "dlc_fp03_prop_player-emote-snowball_01a" },
  { "World: Party popper", "dlc_sp06_item_party-popper_01a" },
  { "World: Shake bottle champagne", "dlc_sp06_item_shake-bottle-champagne_01a" },
  { "World: Player emote present open 01a box", "dlc_sp06_prop_player-emote-present-open_01a-box" },
  { "World: Player emote present open 01a lid", "dlc_sp06_prop_player-emote-present-open_01a-lid" },
  { "World: Player emote present open 01a", "dlc_sp06_prop_player-emote-present-open_01a" },
  { "World: Player emote present open 01b", "dlc_sp06_prop_player-emote-present-open_01b" },
  { "World: Cash coin", "dlc_boothill_cash-coin_01a" },
  { "World: Explosive barrel stack 01a husk", "dlc_boothill_prop_explosive-barrel-stack_01a-husk" },
  { "World: Explosive barrel stack 01b husk", "dlc_boothill_prop_explosive-barrel-stack_01b-husk" },
  { "World: Loot chest", "dlc_boothill_prop_loot-chest_01a" },
  { "World: Doc ketchum cane", "item-doc-ketchum-cane_01a" },
  { "World: Emote lantern", "dlc_fp04_prop_emote_lantern_01a" },
  { "World: Envelope stack", "item_envelope_stack_01a" },
  { "World: Umbrella generic", "dlc_dis01_item_prop-umbrella-generic_01a" },
  { "World: Kaijuice qrc board 01a spawnable", "dlc_dis01_kaijuice-qrc-board_01a_spawnable" },
  { "World: Light prop bollard marine 01a husk", "dlc_dis01_light_prop_bollard_marine_01a-husk" },
  { "World: Sign shooting range 03a husk", "dlc_exp_01_lucky_sign-shooting-range_03a-husk" },
  { "World: Marshall generator grid 01a husk", "dlc_lp01_prop_marshall-generator-grid_01a-husk" },
  { "World: Ms chris vendor spawnable", "dlc_lp01_prop_ms-chris_vendor_spawnable_01a" },
  { "World: Vault wall explosion section damaged", "dlc_lp01_prop_vault-wall-explosion-section-damaged_01a" },
  { "World: Vault wall explosion section intact", "dlc_lp01_prop_vault-wall-explosion-section-intact_01a" },
  { "World: Emote prop guitar anaya crush body", "item_emote_prop-guitar-anaya-crush-body_01a" },
  { "World: Emote prop guitar anaya crush neck", "item_emote_prop-guitar-anaya-crush-neck_01a" },
  { "World: Emote prop guitar anaya crush", "item_emote_prop-guitar-anaya-crush_01a" },
  { "World: Tray drinks", "item_tray-drinks_01a" },
  { "World: Crate transport stack 01a spawnable", "prop_crate-transport-stack_01a-spawnable" },
  { "World: Vendor cart 01b spawnable", "prop_vendor-cart_01b_spawnable" },
  { "World: Vignette busker sunshine", "vignette_busker_sunshine" },
  { "World: Vignette group fishing small casual", "vignette_group_fishing_small_casual" },
  { "World: Bubble container", "dlc_dis01_item_bubble-container_01a" },
  { "World: Bubble wand", "dlc_dis01_item_bubble-wand_01a" },
  { "World: Horse skull small", "dlc_dis02_item_horse-skull-small_01a" },
  { "World: Umbrella dustfaire", "dlc_dis02_item_prop-umbrella-dustfaire_01a" },
  { "World: Microphone", "dlc_dis02_item_prop_microphone_01a" },
  { "World: Exploding barrel husk", "dlc_dis02_prop-exploding-barrel-husk_01a" },
  { "World: Emote dustfaire horn", "dlc_dis02_prop_emote_dustfaire-horn_01a" },
  { "World: Fire torch", "dlc_dis02_prop_fire-torch_01a" },
  { "World: Box prop", "dlc_lp02_box_prop_01a" },
  { "World: Larp potion", "dlc_lp02_larp_potion_01" },
  { "World: Desert oil drum", "item_desert-oil-drum_01a" },
  { "World: Dustfaire dj turntable mixer", "item_dustfaire-dj-turntable-mixer_01a" },
  { "World: Dustfaire flame guitar", "item_dustfaire-flame-guitar_01a" },
  { "World: Dustfaire hot dog", "item_dustfaire-hot-dog_01a" },
  { "World: Ghosts bone dusty", "item_ghosts-bone-dusty_01a" },
  { "World: Wastelander revolver hand cannon", "item_wastelander-revolver-hand-cannon_01a" },
  { "World: Barrier dragon tower", "prop_barrier_dragon_tower" },
  { "World: Boogie fishing poll 01a husk", "prop_boogie-fishing-poll_01a-husk" },
  { "World: Chaos fire barrel 01a dustlander", "prop_chaos-fire-barrel_01a_dustlander" },
  { "World: Container shipping idols cover", "prop_container-shipping-idols_cover_01a" },
  { "World: Damien spawnable", "prop_damien_spawnable" },
  { "World: Faire b worm polyp", "prop_faire_b_worm-polyp_01a" },
  { "World: Fence dragon head", "prop_fence_dragon_head" },
  { "World: Luggage stack 2m 02b husk", "prop_luggage-stack-2m_02b-husk" },
  { "World: Tent small idols 03a spawnable", "prop_tent-small-idols_03a_spawnable" },
  { "World: Cardboard box larp supplies 01a spawnable anchored", "prop_cardboard-box_larp-supplies_01a_spawnable_anchored" },
  { "World: Cardboard box larp supplies 01b spawnable anchored", "prop_cardboard-box_larp-supplies_01b_spawnable_anchored" },
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
do
  -- A variant the game doesn't name takes the name of the vehicle its id is built on. No match, and it goes last under its id.
  local named, unnamed = {}, {}
  local function raw(v) return v[1] == "?" or v[1] == v[2] or v[1]:find("^also named in") end
  for _, v in ipairs(VEH.list) do
    if not raw(v) then named[v[2]] = v[1]:match("^(.-) %(") or v[1] end
  end
  for _, v in ipairs(VEH.list) do
    local label, base = v[1], nil
    if raw(v) then
      for id in pairs(named) do
        if v[2]:find(id, 1, true) and (not base or #id > #base) then base = id end
      end
      label = base and (named[base] .. " (" .. v[2] .. ")") or (v[1] == "?" and "Unnamed") or v[2]
    end
    local t = (raw(v) and not base) and unnamed or ANY_VEHICLES
    t[#t + 1] = { label, v[2], v[3] }
  end
  table.sort(ANY_VEHICLES, function(a, b) return a[1]:lower() < b[1]:lower() end)
  table.sort(unnamed, function(a, b) return a[1]:lower() < b[1]:lower() end)
  for _, v in ipairs(unnamed) do ANY_VEHICLES[#ANY_VEHICLES + 1] = v end
end
local function any_variants(i, list)
  local out = {}
  for _, p in ipairs((list or ANY_VEHICLES)[i][3]) do out[#out + 1] = { p[1] .. " (" .. p[2] .. ")", p[1] } end
  return out
end
-- By the name the game gives it. What's unclear stays under All only.
local function vehicle_kind(id)
  if id:find("boat") or id:find("jet_?ski") then return "water" end
  if id:find("heli") or id:find("vtol") then return "air" end
  if id:find("^bike") or id:find("^atv") then return "bike" end
  if id:find("hoverboard") or id:find("broomstick") or id:find("^go_cart") or id:find("^cart_") or id == "novelty_ned" or id == "?" then return "other" end
  if id:find("tank") or id:find("apc") or id:find("truck") or id:find("^semi") or id:find("^bus") or id:find("monster") or id:find("^rv_")
    or id:find("^fire_") or id:find("garbage") or id:find("flatbed") or id:find("ambulance") or id:find("front_loader") or id:find("riot") or id:find("utility") then return "heavy" end
  return "car"
end
local function any_of_kind(kind)
  if not kind then return ANY_VEHICLES end
  local out = {}
  for _, v in ipairs(ANY_VEHICLES) do if vehicle_kind(v[2]) == kind then out[#out + 1] = v end end
  return out
end
local PERK_LIST = require("perks")
-- Engine values: the game's records by system, generated.
local BROWSER = require("browser")
local ENGINE_SYSTEMS, ENGINE_SEEN = {}, {}
for _, c in ipairs(BROWSER) do
  if not ENGINE_SEEN[c.system] then ENGINE_SEEN[c.system] = true; ENGINE_SYSTEMS[#ENGINE_SYSTEMS + 1] = { c.system, c.system } end
end
table.sort(ENGINE_SYSTEMS, function(a, b) return a[1] < b[1] end)
local function engine_classes(i)
  local out = {}
  for _, c in ipairs(BROWSER) do
    if c.system == ENGINE_SYSTEMS[i][1] then out[#out + 1] = { (c[1]:gsub("_", " ")), c[1], c } end
  end
  return out
end
-- { label, path, kind }: numbers first, then on/off flags, then what's in lists
local function engine_fields(c)
  local out, ints = {}, {}
  local function pretty(path) return (path:gsub("m_", ""):gsub("%[%]", " list"):gsub("[_%.]", " ")) end
  for _, n in ipairs(c.ints or {}) do ints[n] = true end
  for j, path in ipairs(c[2]) do out[#out + 1] = { pretty(path), path, ints[j] or false } end
  for _, path in ipairs(c.flags or {}) do out[#out + 1] = { pretty(path) .. " (on/off)", path, "flag" } end
  for _, entry in ipairs(c.arr or {}) do
    local path, mark = entry:match("^(.-)([#?]?)$")
    out[#out + 1] = { pretty(path) .. (mark == "?" and " (on/off)" or ""), path, mark == "?" and "flag" or mark == "#" }
  end
  return out
end
-- The list item row, for the record and field picked: all of them, or one.
local function engine_items(class, rec, field)
  if not field or not field[2]:find("[]", 1, true) then return { { "Not a list", false } } end
  local n = rec and P.engine_list_size(class, rec[2], field[2]) or 0
  local out = { { "All " .. n, false } }
  for i = 0, math.min(n, 512) - 1 do out[#out + 1] = { "Item " .. (i + 1), i } end
  return out
end
local EXTRAS = require("extras")
local function name_list(t)
  local out = {}
  for i, n in ipairs(t) do out[i] = { (n:gsub("_", " ")), n } end
  return out
end
local function swap_options(t)
  local out = { { "Game's", false } }
  for _, path in ipairs(t) do out[#out + 1] = { (path:match("[^\\]+$"):gsub("^vfx%-[a-z]+_", ""):gsub("^vfx_", ""):gsub("_", " ")), path } end
  return out
end
local GOAL_LIST, PROFILE_LIST, REWARD_LIST = name_list(EXTRAS.goal_sets), name_list(EXTRAS.spawn_profiles), name_list(EXTRAS.rewards)
-- Special rounds and blasts, generated. The first row of each keeps its own explosion or RPG's.
local ROUNDS = require("rounds")
local PROP_GUN_OPTIONS = { { "Off", false } }
for _, o in ipairs(SPAWN_PROPS) do PROP_GUN_OPTIONS[#PROP_GUN_OPTIONS + 1] = o end
local ROUND_OPTIONS, BLAST_OPTIONS, ROUND_BLASTS = { { "Off", false } }, { { "Off", false }, { "RPG explosion", [[data\sr_vanguard\spawnables\weapons\launcher\weapon_launcher_rpg_explosion]] } }, { { "The round's own", false } }
for _, r in ipairs(ROUNDS.rounds) do ROUND_OPTIONS[#ROUND_OPTIONS + 1] = { r[1], { r[2], r[3], loads = r[4], keys = r[5] } } end
for _, b in ipairs(ROUNDS.blasts) do BLAST_OPTIONS[#BLAST_OPTIONS + 1] = { b[1], b[2] }; ROUND_BLASTS[#ROUND_BLASTS + 1] = { b[1], b[2] } end
local SIG_OPTIONS = { { "Off", false },
  -- on any gun with bullets
  { "Magnum Rounds: shove at each hit", { record = "weapon_pistol_handcannon", loads = { [[data\sr_city\spawnables\weapons\rifle\weapon_rifle_assault_ultimate_impulse_aoe]] } } },
  { "Aim High: late headshot reloads", { record = "weapon_pistol_tacpistol" } },
  { "Shock & Ouch: muzzle blast", { record = "weapon_rifle_elephant", loads = { [[data\sr_city\spawnables\weapons\rifle\weapon_rifle_elephant_ultimate_explosion]] } } },
  { "Beowulf: hits vehicles harder", { record = "weapon_rifle_generic_burst" } },
  { "Bonus Round: headshot ammo", { record = "weapon_rifle_generic_sniper" } },
  { "Swarm Tracers: random homing shot", { record = "weapon_rifle_marshall_ct_marsh_auto", loads = { [[data\sr_vanguard\spawnables\weapons\rifle\weapon_rifle_marshall_ultimate_micromissile_projectile]], [[data\sr_city\spawnables\weapons\pistol\weapon_marshall_specialist_gunslinger_micromissle_aoe]] } } },
  { "Flow State: damage rises with Flow", { record = "weapon_rifle_marshall_sniper" } },
  { "Buffalo Shot: chance of ragdoll", { record = "weapon_shotgun_cowboy" } },
  { "Supercharger: chance of shock", { record = "weapon_shotgun_marshall_tac" } },
  { "Flechette: stacking bleed", { record = "weapon_shotgun_police" } },
  { "Dragonbreath: chance of fire", { record = "weapon_shotgun_sawedoff" } },
  { "Spray and Pray: tightens as you fire", { record = "weapon_smg_hi_volume" } },
  { "Shocker Rounds: reloads cycle effects", { record = "weapon_smg_tac", keys = { { 0xB0ACE1F9, 0, 1 } }, loads = {
      [[data\sr_city\spawnables\vfx\prefabs\vfx_smg_tactical_tracer_ultimate_01a]], [[data\sr_city\spawnables\vfx\prefabs\vfx_smg_tactical_muzzle_ultimate_01a]],
      [[data\sr_city\spawnables\vfx\prefabs\vfx_smg_tactical_tracer_ultimate_02a]], [[data\sr_city\spawnables\vfx\prefabs\vfx_smg_tactical_muzzle_ultimate_02a]],
      [[data\sr_city\spawnables\vfx\prefabs\vfx_smg_tactical_tracer_ultimate_03a]], [[data\sr_city\spawnables\vfx\prefabs\vfx_smg_tactical_muzzle_ultimate_03a]] } } },
  { "DMR: pierces", { record = "inv_weapon_dlc_rifle_dmr" } },
  { "Pistol shotgun: fire and shock", { record = "inv_dlc_pistol_shotgun", loads = { [[data\dlc_boothill\spawnables\vfx\prefabs\vfx_dlc_boothill_pistol_shotgun_ult_electric]], [[data\dlc_boothill\spawnables\vfx\prefabs\vfx_dlc_boothill_pistol_shotgun_ult_fire]] } } },
  -- on melee, hits only
  { "Bleeding Edge: triple bleed", { record = "weapon_melee_1hand_machete" } },
  { "Bloodsucker: health per hit", { record = "weapon_melee_2hand_axe" } },
  { "Bashmaster: longer stagger", { record = "weapon_melee_2hand_crowbar" } },
  { "Swing Away: kills go flying", { record = "weapon_melee_2hand_generic_bat", loads = { [[data\sr_city\spawnables\vfx\prefabs\vfx-melee_2h_blunt_ult]] } } },
  -- on any gun with bullets, from the DLC
  { "Saintly ghost: kills raise allies", { record = "weapon_rifle_haunted_dlc", loads = { [[data\dlc_02\spawnables\vfx\prefabs\vfx_ghost_saint_spawn]] } } },
  { "Turbo Mode: faster the longer you fire", { record = "inv_weapon_lmg_dlc", loads = { [[data\dlc_boothill\spawnables\vfx\prefabs\vfx_dlc_boothill_lmg_muzzle_overheat]] } } },
}
-- Animations and clothes, generated.
local ANIM_LIST = {}
for _, a in ipairs(require("anims")) do ANIM_LIST[#ANIM_LIST + 1] = { a[1] .. (a[5] and (" (" .. a[5] .. ")") or "") .. (a[4] == 1 and " (never used)" or ""), a[1], a[2], a[3] } end
local CLOTHES = require("clothes")
local Co = require("coop")
local CLOTH_SLOTS = {}
for i, c in ipairs(CLOTHES) do CLOTH_SLOTS[i] = { c[1]:gsub("_", " "), c[1], i } end
local function cloth_items(i)
  local out = {}
  for j, n in ipairs(CLOTHES[i][2]) do out[j] = { (n:gsub("^clo_", ""):gsub("_", " ")), n } end
  return out
end
local SKY_LIST = require("sky")
local SOUND_LIST = {}
for _, n in ipairs(require("sounds")) do SOUND_LIST[#SOUND_LIST + 1] = { n, n } end
local TABS = {
  { name = "Player", rows = {
    pset("god", "God mode", "You can't die. Not the game's cheat, so your save stays clean.", { { "Off", false }, { "On", true } }),
    pset("health_mult", "Max health", "Your maximum health.", { { "Game's", 1 }, { "x2", 2 }, { "x5", 5 }, { "x10", 10 } }),
    pset("proof_bullets", "Bulletproof", "Bullets don't hurt you, without God mode.", { { "Off", false }, { "On", true } }),
    pset("proof_explosions", "Explosion-proof", "Explosions and fire don't hurt you.", { { "Off", false }, { "On", true } }),
    pset("proof_crashes", "Crash-proof", "Being hit by vehicles and objects doesn't hurt you.", { { "Off", false }, { "On", true } }),
    { kind = "refill", label = "Refill health", help = "Back to full health." },
    { kind = "kill_self", label = "Kill yourself", help = "You die as if shot and respawn as usual. Turn God mode off first. Enter twice." },
    pset("regen", "Health regen", "How your health comes back: None, Fast (five times, no wait after a hit) or Always full.", { { "Game's", "game" }, { "None", "none" }, { "Fast", "fast" }, { "Always full", "full" } }),
    pset("no_fall", "No fall damage", "Falls from any height don't hurt.", { { "Off", false }, { "On", true } }),
    { kind = "mvset", key = "run", label = "Run speed", help = "How fast you walk, jog and sprint.", options = { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 }, { "x5", 5 } }, sel = 1, save_key = "move.run" },
    { kind = "mvset", key = "jump", label = "Jump height", help = "How high you jump. Big jumps need God mode or No fall damage.", options = { { "Game's", 1 }, { "x2", 2 }, { "x3", 3 }, { "x5", 5 }, { "x10", 10 } }, sel = 1, save_key = "move.jump" },
    { kind = "mvset", key = "air", label = "Air control", help = "How much you can steer in the air.", options = { { "Game's", 1 }, { "x2", 2 }, { "x4", 4 } }, sel = 1, save_key = "move.air" },
    { kind = "mvset", key = "swim", label = "Swim speed", help = "How fast you swim.", options = { { "Game's", 1 }, { "x2", 2 }, { "x3", 3 } }, sel = 1, save_key = "move.swim" },
    { kind = "mvset", key = "gravity", label = "Your gravity", help = "Lower makes jumps and falls floatier.", options = { { "Game's", 1 }, { "x0.5", 0.5 }, { "x0.25", 0.25 }, { "x2", 2 } }, sel = 1, save_key = "move.gravity" },
    { kind = "emote_slot", slot = "primary", label = "D-pad emote 1", help = "The emote on your first D-pad emote. Left/Right picks, Enter sets it. Then use the D-pad as usual.", sel = 1, options = {}, apply = true },
    { kind = "emote_slot", slot = "secondary", label = "D-pad emote 2", help = "The emote on your second D-pad emote. Left/Right picks, Enter sets it. Then use the D-pad as usual.", sel = 1, options = {}, apply = true },
    { kind = "emote", label = "Play emote", help = "Plays one of the game's emotes now. Left/Right picks, Enter plays it.", sel = 1, options = {} },
    gchoice("Hidden emote", "Plays an emote the game never lists. Left/Right picks, Enter plays it.", { { "Frost speech 2", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "emote frost speech 02")) return "Frost speech 2"]] }, { "Frost speech 3", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "emote frost speech 03")) return "Frost speech 3"]] }, { "Outfit inspect 2", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full action outfit inspect 2")) return "Outfit inspect 2"]] }, { "Walking Frankenstein", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "walking frankenstein")) return "Walking Frankenstein"]] }, { "Crab walk", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full state crab walk")) return "Crab walk"]] }, { "Broom ride", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full state broom ride side")) return "Broom ride"]] }, { "Spooky floating dance", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full state spooky floating dance")) return "Spooky floating dance"]] }, { "Stoney scary", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full state stoney scary")) return "Stoney scary"]] }, { "Skelly show", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full state skelly show")) return "Skelly show"]] }, { "Pumpkin smash", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full action pumpkin smash")) return "Pumpkin smash"]] }, { "Pumpkin throw", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "partial state pumpkin throw")) return "Pumpkin throw"]] }, { "Roachburger dance", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full action roachburger dance")) return "Roachburger dance"]] }, { "Frost speech", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "emote frost speech 01")) return "Frost speech"]] }, { "Stretch", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full action stretch")) return "Stretch"]] }, { "Outfit inspect", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full action outfit inspect 1")) return "Outfit inspect"]] }, { "Phone use", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full state phone use")) return "Phone use"]] }, { "Summoning", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "full state summoning")) return "Summoning"]] }, { "Detonate", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "partial action detonate")) return "Detonate"]] }, { "Phone call", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "partial action phone call")) return "Phone call"]] }, { "Injured phone", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "partial body injured phone")) return "Injured phone"]] }, { "Steam", [[emote_play_in_world(vlib_info_object:get_object("collectible_emote", "partial state steam")) return "Steam"]] } }),
    { kind = "mset", key = "repeat_emote", label = "Repeat emote", help = "Plays the emote picked on Play emote again and again. Stop emote ends it.", options = { { "Off", false }, { "Every 3 s", 180 }, { "Every 6 s", 360 }, { "Every 12 s", 720 } }, sel = 1 },
    { kind = "emote_stop", label = "Stop emote", help = "Stops the emote you're playing, and Repeat emote." },
    { kind = "gchoice", apply = true, label = "Facial expression", help = "Your face holds this expression until you pick Normal. Left/Right picks, Enter sets it.", sel = 1, options = { { "Normal", "selfie_mode_facial_expression_clear() return 'Normal'" },
      { "Anger", "selfie_mode_facial_expression_play(vlib_info_object:get_object('gml_gail_mood_info', 'anger')) return 'Anger'" }, { "Contempt", "selfie_mode_facial_expression_play(vlib_info_object:get_object('gml_gail_mood_info', 'contempt')) return 'Contempt'" },
      { "Disgust", "selfie_mode_facial_expression_play(vlib_info_object:get_object('gml_gail_mood_info', 'disgust')) return 'Disgust'" }, { "Fear", "selfie_mode_facial_expression_play(vlib_info_object:get_object('gml_gail_mood_info', 'fear')) return 'Fear'" },
      { "Happiness", "selfie_mode_facial_expression_play(vlib_info_object:get_object('gml_gail_mood_info', 'happiness')) return 'Happiness'" }, { "Pain", "selfie_mode_facial_expression_play(vlib_info_object:get_object('gml_gail_mood_info', 'pain')) return 'Pain'" },
      { "Sadness", "selfie_mode_facial_expression_play(vlib_info_object:get_object('gml_gail_mood_info', 'sadness')) return 'Sadness'" }, { "Surprise", "selfie_mode_facial_expression_play(vlib_info_object:get_object('gml_gail_mood_info', 'surprise')) return 'Surprise'" } } },
    { kind = "gchoice", apply = true, label = "Your voice", help = "The game's eight player voices. Left/Right picks, Enter sets it. Stays in your save. Yours is the voice you had before changing it this run. Say a line lets you hear it.", sel = 1, options = voices() },
    opt("Voice pitch", "Lower or higher than your voice. Stays in your save.", "customization_get_avatar_voice_pitch()", "customization_set_avatar_voice_pitch(%s)", { { "-1", -1 }, { "-0.5", -0.5 }, { "0", 0 }, { "+0.5", 0.5 }, { "+1", 1 } }),
    pset("move_style", "Movement style", "Walk and run as if holding this. Your gun can override it.", { { "Game's", false }, { "Fists ready", "fists ready" }, { "One-hand melee", "1h_melee_ready" }, { "Two-hand melee", "2h_melee_ready" }, { "Staff", "staff ready" }, { "Pistol", "pistol_ready" }, { "Rifle", "rifle_ready" }, { "Minigun", "minigun_ready" }, { "Dual wield", "dual_wield_ready" }, { "Riot shield", "riotshield_pistol_ready" } }),
    pset("wingsuit_low", "Wingsuit from low down", "The wingsuit opens from any height. You still need to be falling.", { { "Off", false }, { "On", true } }),
    pset("walk_style", "Walk style", "Replaces your walk, jog and sprint animations.", { { "Game's", false }, { "Forced walk", "default" }, { "Sad walk", "sad walk" }, { "Coffee walk", "coffee walk" }, { "Drunk walk", "drunk walk" }, { "Fancy walk", "fancy walk" }, { "Phone walk", "phone walk" } }),
    { kind = "voiceline", label = "Say a line", help = "Says one of the game's voice situations. The first Enter loads the list. Left/Right picks, Enter says it.", sel = 1, options = {} },
    gcall("Dismiss homies", "Sends away every homie who's following you.", [[
      local n = 0
      for _, h in vlib_info_object:ipairs("homie_info") do if homie_is_following(h) then homie_dismiss(h) n = n + 1 end end
      return n .. " dismissed"
    ]]),
    pset("homies", "Homie limit", "How many homies can follow you at once, if you don't own the extra-homies perk.", { { "Game's", 1 }, { "2", 2 }, { "3", 3 }, { "4", 4 } }),
    pset("no_clip", "Fly (no clip)", "Fly where you look, through walls. Left stick or W A S D, RT or Space up, LT or Ctrl down, stick click or Shift for fast. Triggers won't fire guns.", { { "Off", false }, { "On", true } }),
    pset("no_ragdoll", "Get up at once", "When you're knocked over, you're straight back up.", { { "Off", false }, { "On", true } }),
    { kind = "homie", label = "Summon homie", help = "Calls in a homie, if the game lets you. Left/Right picks, Enter calls them.", sel = 1, options = {} },
    wsset("cooldown", "Wingsuit boosts", "The game gives one boost until you land. Every 2 s, or Unlimited once the last one ends.", { { "Game's", 1 }, { "Every 2 s", "short" }, { "Unlimited", "none" } }),
    wsset("boost", "Wingsuit boost power", "Boost speed, acceleration and length.", { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 } }),
    wsset("speed", "Wingsuit top speed", "Top speed without boosting, launch speed and landing speed cap.", { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 } }),
    wsset("glide", "Wingsuit glide", "Floaty: half gravity. Level: barely drops, no stall. Climb: gains height; pull back (stick or S) to go up any time.", { { "Game's", "game" }, { "Floaty", "floaty" }, { "Level", "level" }, { "Climb", "climb" } }),
    toggle("invincibility", "Invincibility (game's)", "The game's Invulnerable effect: you can't be hurt. Pauses autosave while on."),
    action("cash", "Give cash", "The game's cash cheat."),
    action("max level", "Max level", "Jumps you to the top level."),
    pset("free_shop", "Free shopping", "Everything in the stores costs nothing while it's on.", { { "Off", false }, { "On", true } }),
    gchoice("Give XP", "Adds XP the game's way. Left/Right picks, Enter adds it. Stays in your save.", award("xp", { { "1,000 XP", 1000 }, { "10,000 XP", 10000 }, { "100,000 XP", 100000 } })),
    gchoice("Give skill points", "Adds skill points. Left/Right picks, Enter adds them. Stays in your save.", award("skill_point", { { "1", 1 }, { "5", 5 }, { "10", 10 } })),
    gchoice("Add cash", "Adds cash directly. Left/Right picks, Enter adds it. Stays in your save.", award("cash", { { "$10,000", 10000 }, { "$100,000", 100000 }, { "$1,000,000", 1000000 } })),
    { kind = "play_as", back = false, label = "Play as last spawned", help = "Only half works for now: the game counts them as you, but your own body stays put. Back to yourself returns. Don't save while you're them." },
    { kind = "play_as", back = true, label = "Back to yourself", help = "Back to your own character. Remove spawned people does it too." },
    { kind = "outfit", label = "Saved look", help = "Puts you back in a character you saved in the game: body and outfit. Left/Right picks, Enter wears it.", sel = 1, options = {} },
    { kind = "look_preset", label = "Character preset", help = "Replaces your whole character with one of the game's presets. Left/Right picks, Enter twice. Undo my look puts you back.", sel = 1, options = {} },
    gcall("Customize character", "Opens the game's character screen anywhere, through the phone. Esc goes back, Esc again closes the phone.", [[gml_ui_gem_raise_event("ui_cell_phone_open", 1, "requested_screen", string_crci("cell_home_open_profile")) return "open: close this menu"]]),
    pset("all_perks", "All perks on", "Every perk's effect at once, no slots, except the two that cost you.", { { "Off", false }, { "On", true } }),
    pset("flow", "Unlimited Flow", "Your ability meter stays full, as the game does in some missions.", { { "Off", false }, { "On", true } }),
    pset("free_skills", "Free skills", "Skills cost no Flow.", { { "Off", false }, { "On", true } }),
    pset("flow_gain", "Flow gain", "How much faster your Flow fills.", { { "Game's", false }, { "+2", 2.0 }, { "+5", 5.0 }, { "+20", 20.0 } }),
    pset("flow_bars", "Extra Flow bars", "More bars on your Flow meter.", { { "Game's", false }, { "+1", 1.0 }, { "+3", 3.0 } }),
    pset("flow_no_decay", "Flow never drains", "Your Flow stays where it is out of combat.", { { "Off", false }, { "On", 1.0 } }),
    pset("rampage", "Rampage at full Flow", "Extra damage while your Flow is full. The perk gives 0.35.", { { "Game's", false }, { "+1", 1.0 }, { "+3", 3.0 } }),
    pset("takedown", "Takedown cooldown", "How soon you can do another takedown. The game's is 90 s.", { { "Game's", false }, { "10 s", 10000 }, { "1 s", 1000 } }),
    { kind = "call_saints", label = "Call in Saints", help = "Calls in Saints, free. Left/Right picks how many, Enter calls them.", sel = 2, options = { { "1", 1 }, { "2", 2 }, { "4", 4 }, { "8", 8 } } },
    { kind = "prank", label = "Prank yourself", help = "Puts a co-op prank on you. Left/Right picks, Enter puts it on. Pick Off before saving: the mesh ones swap your outfit.", sel = 1, options = {
      { "Off", false }, { "Bees", 0xD1DEBF59 }, { "Cash", 0xF8960CDB }, { "Hearts", 0x9DC3DBAC }, { "On fire", 0xD2FD511D }, { "Radioactive", 0x2FC32EBC }, { "Snow", 0xC8AC4CD1 }, { "Stink", 0xA86F8869 },
      { "Noodle arms", 0xC150DD93 }, { "Upside down", 0x4B60380A }, { "Bow-legged", 0x462A02E2 }, { "Bounce", 0x0339330A }, { "Foam hat", 0xBEFF0993 },
      { "Toilet", 0x70E3C60A }, { "Vending machine", 0xCBD43B2C }, { "Mailbox", 0xDA4E96A4 }, { "Cactus", 0x473E4F01 }, { "Trash can", 0xBDEDFB4D }, { "Burning barrel", 0xEAB2B9D6 } } },
    { kind = "mission", label = "Start mission", help = "Any mission or activity, in any order. It can wreck a save's story. Left/Right picks, Enter twice. Save first.", sel = 1, options = {} },
    gcall("Insurance Fraud here", "Starts the Insurance Fraud activity where you stand. Enter twice.", 'mission_request_start(vlib_info_object:get_object("mission_info", "insurance_fraud_anywhere")) return "Go"', true),
    pset("free_ventures", "Free ventures", "Criminal Ventures cost nothing to build.", { { "Off", false }, { "On", true } }),
    { kind = "unlock", key = "everything", label = "Unlock everything", help = "Every unlock row at once, DLC too. Takes a minute or two. Enter twice. Save first." },
    { kind = "unlock", key = "travel", label = "Unlock fast travel points", help = "All of them, on the map and in the menu. Enter twice. Save first." },
    { kind = "unlock", key = "weapons", label = "Unlock every weapon", help = "Every weapon in the game, DLC and test guns too. Remove test guns takes those back out. Enter twice. Save first." },
    { kind = "unlock", key = "skills", label = "Unlock all skills", help = "Every skill is yours, free, DLC and Boothill too. Enter twice. Save first." },
    { kind = "unlock", key = "perks", label = "Unlock all perks", help = "Every perk and perk slot is yours, free, DLC and Boothill too. Enter twice. Save first." },
    { kind = "unlock", key = "gang", label = "Unlock gang and homies", help = "Every crew look, crew vehicle, homie and homie outfit. Enter twice. Save first." },
    { kind = "unlock", key = "clothing", label = "Unlock all clothing", help = "Every piece of clothing in the game, sold in a store or not. Enter twice. Save first." },
    { kind = "unlock", key = "stores", label = "Unlock all store items", help = "Every store's clothing and emotes. Enter twice. Save first." },
    { kind = "unlock", key = "collectibles", label = "Unlock all collectibles", help = "Every collectible outfit, emote, weapon, car and HQ prop. Enter twice. Save first." },
    toggle("super_saints", "Super Saints", "Your Saints' guns and melee hit far harder. Pauses autosave while on."),
    toggle("milk_bones", "Milk Bones", "Your melee hits far harder and sends people flying. Pauses autosave while on."),
    toggle("pratfall", "Pratfall", "You ragdoll at the slightest touch."),
    toggle("heaven_bound", "Heaven Bound", "Dead bodies lose their gravity and drift upward. No effect on your save."),
  } },
  { name = "Weapons", rows = {
    wset("magazine", "Magazine", "Magazine size. No reload keeps it full, so it never goes down or reloads, launchers too.", {
      { "Game's", 1 }, { "x2", 2 }, { "x5", 5 }, { "No reload", "no_reload" } }),
    pset("money_gun", "Money gun", "Every shot throws $50 out ahead of you. It stays in your save.", { { "Off", false }, { "On", true } }),
    gcall("Remove this weapon", "Takes the gun in your hands out of your inventory. Enter twice. Save first.", "weapon_clear_inventory_slot(player_local_inventory_get_active_slot()) return 'Removed'", true),
    gchoice("Special weapon", "A mission-only weapon no store sells. Left/Right picks, Enter gives it.", { { "Boss pistol", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_pistol_nahualli") weapon_swap_to_inventory(w) return "Boss pistol"]] }, { "Nahualli pistol", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_pistol_nahualli_subgrunt") weapon_swap_to_inventory(w) return "Nahualli pistol"]] }, { "Marshall burst rifle", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_rifle_marshall_burst") weapon_swap_to_inventory(w) return "Marshall burst rifle"]] }, { "Idols pistol SMG", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_smg_pistol_idols_ct_icon") weapon_swap_to_inventory(w) return "Idols pistol SMG"]] }, { "NPC minigun", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_temporary_marshall_minigun_npc") weapon_swap_to_inventory(w) return "NPC minigun"]] }, { "Dojo crowbar", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_1hand_dojo_crowbar") weapon_swap_to_inventory(w) return "Dojo crowbar"]] }, { "Flashcracker", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_grenade_flashcracker") weapon_swap_to_inventory(w) return "Flashcracker"]] }, { "Smoke grenade", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_grenade_smoke") weapon_swap_to_inventory(w) return "Smoke grenade"]] }, { "Molotov", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_grenade_molotov") weapon_swap_to_inventory(w) return "Molotov"]] }, { "Frag grenade", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_grenade_frag") weapon_swap_to_inventory(w) return "Frag grenade"]] }, { "Boot Hill fist cannon", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_fist_cannon_boothill") weapon_swap_to_inventory(w) return "Boot Hill fist cannon"]] }, { "Boot Hill pickaxe", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_2hand_pickaxe_boothill") weapon_swap_to_inventory(w) return "Boot Hill pickaxe"]] }, { "Boot Hill elephant rifle", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_rifle_elephant_boothill") weapon_swap_to_inventory(w) return "Boot Hill elephant rifle"]] }, { "Boot Hill tactical SMG", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_smg_tac_boothill") weapon_swap_to_inventory(w) return "Boot Hill tactical SMG"]] }, { "Boot Hill heavy SMG", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_smg_hi_volume_boothill") weapon_swap_to_inventory(w) return "Boot Hill heavy SMG"]] }, { "Boot Hill sawed-off", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_shotgun_sawedoff_boothill") weapon_swap_to_inventory(w) return "Boot Hill sawed-off"]] }, { "Boot Hill pistol", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_pistol_tacpistol_boothill") weapon_swap_to_inventory(w) return "Boot Hill pistol"]] }, { "Boot Hill box launcher", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_launcher_box_boothill") weapon_swap_to_inventory(w) return "Boot Hill box launcher"]] }, { "Boot Hill RPG", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_launcher_rpg_boothill") weapon_swap_to_inventory(w) return "Boot Hill RPG"]] }, { "Minigun", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_temporary_marshall_minigun") weapon_swap_to_inventory(w) return "Minigun"]] }, { "Riot shield", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_temporary_riot_shield") weapon_swap_to_inventory(w) return "Riot shield"]] }, { "DJ staff", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_temporary_djstaff") weapon_swap_to_inventory(w) return "DJ staff"]] }, { "Maul", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_temporary_panteros_maul") weapon_swap_to_inventory(w) return "Maul"]] }, { "Idols SMG", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_temporary_idols_smg") weapon_swap_to_inventory(w) return "Idols SMG"]] }, { "Heavy sword", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_2hand_heavy_sword_ct_icon") weapon_swap_to_inventory(w) return "Heavy sword"]] }, { "Toy hammer", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_2hand_toy_hammer_ct_icon") weapon_swap_to_inventory(w) return "Toy hammer"]] }, { "Nahualli knife", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_1hand_nahualli_knife") weapon_swap_to_inventory(w) return "Nahualli knife"]] }, { "Butterfly knife", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_1hand_nahualli_butterfly_knife") weapon_swap_to_inventory(w) return "Butterfly knife"]] }, { "Nahualli machete", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_nahualli_machete") weapon_swap_to_inventory(w) return "Nahualli machete"]] }, { "Dojo baton", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_1hand_dojo_baton") weapon_swap_to_inventory(w) return "Dojo baton"]] }, { "Dojo bat", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_2hand_dojo_bat") weapon_swap_to_inventory(w) return "Dojo bat"]] }, { "Dojo crutch", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_2hand_dojo_crutch") weapon_swap_to_inventory(w) return "Dojo crutch"]] }, { "Dojo sledgehammer", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_melee_2hand_dojo_sledgehammer") weapon_swap_to_inventory(w) return "Dojo sledgehammer"]] }, { "Mime invisible pistol", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_pistol_wastelander_invisible") weapon_swap_to_inventory(w) return "Mime invisible pistol"]] }, { "NPC rocket launcher", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_launcher_rpg_npc") weapon_swap_to_inventory(w) return "NPC rocket launcher"]] }, { "Death Blossom", [[local w = vlib_info_object:get_object("inventory_weapon_info", "larp_death_blossom_inventory") weapon_swap_to_inventory(w) return "Death Blossom"]] }, { "Smokescreen", [[local w = vlib_info_object:get_object("inventory_weapon_info", "larp_smokescreen_inventory") weapon_swap_to_inventory(w) return "Smokescreen"]] }, { "Berserk", [[local w = vlib_info_object:get_object("inventory_weapon_info", "larp_berserk_inventory") weapon_swap_to_inventory(w) return "Berserk"]] }, { "Frost grenade", [[local w = vlib_info_object:get_object("inventory_weapon_info", "frostlander_grenade_inventory") weapon_swap_to_inventory(w) return "Frost grenade"]] }, { "Flashbang", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_grenade_flashbang") weapon_swap_to_inventory(w) return "Flashbang"]] }, { "Smoke grenade", [[local w = vlib_info_object:get_object("inventory_weapon_info", "weapon_grenade_smoke") weapon_swap_to_inventory(w) return "Smoke grenade"]] } }),
    { kind = "giveweapon", label = "Give weapon", help = "Puts one of the game's weapons in your inventory. Left/Right picks, Enter gives it.", sel = 1, options = {} },
    { kind = "refill_ammo", label = "Refill all ammo", help = "Every weapon's magazine and reserve full, free." },
    toggle("infinite_ammo", "Infinite ammo", "Your reserve ammo never runs out. The game's cheat; your save stays clean."),
    wset("fire_rate", "Fire rate", "How fast every weapon fires.", { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x4", 4 }, { "x8", 8 } }),
    pset("throw_rate", "Thruster throw speed", "Footballs a second, no throw animation. Hold the trigger. The game keeps 20 in the air and drops the oldest. Save first.", { { "Game's", false }, { "1", 1000 }, { "2", 500 }, { "3", 333 }, { "5", 200 }, { "8", 125 }, { "10", 100 } }),
    pset("throw_warmup", "Thruster warm-up", "How long a thrown football waits before its rocket lights. The game's is half a second.", { { "Game's", false }, { "Instant", 50 }, { "0.2 s", 200 }, { "1 s", 1000 }, { "3 s", 3000 } }),
    pset("throw_fuse", "Thruster fuse", "How long until a football blows up. The game's is 10 s, 6.5 on you. At 5 throws a second keep it under 4 s.", { { "Game's", false }, { "1 s", 1000 }, { "2 s", 2000 }, { "3 s", 3000 }, { "5 s", 5000 }, { "30 s", 30000 } }),
    pset("throw_power", "Thruster power", "How hard a football pushes what it's stuck to, or itself in the air.", { { "Game's", false }, { "x0.25", 0.25 }, { "x0.5", 0.5 }, { "x2", 2 }, { "x3", 3 }, { "x5", 5 }, { "x10", 10 } }),
    pset("ammo", "Hit effect", "What the gun in your hands does to people it hits: fire, shock, chill and more. New guns get it too.", {
      { "Normal", false }, { "Fire", { "on_fire", "fire" } }, { "Shock", { "electrified", "electricity" } }, { "Chill", { "chill", "water" } },
      { "Stun", { "stun", "electricity" } }, { "Bleed", { "bleed", "dot_bleeding" } }, { "Disintegrate", { "disintegrate", "insta_kill" } },
      { "Flee", { "flee", "physical" } }, { "Panic", { "panic", "physical" } }, { "Blind", { "blindness", "physical" } }, { "Slip", { "slippery", "physical" } }, { "Stagger", { "stagger", "physical" } }, { "Fall over", { "eat food ragdoll", "physical" } }, { "Poison look", { "toxic_waste", "physical" } }, { "Lift off", { "lofted", "physical" } }, { "Reel", { "reeling", "physical" } }, { "Stagger sideways", { "side_stagger", "physical" } }, { "Knock back", { "knockback", "physical" } }, { "Ragdoll", { "ragdoll", "physical" } }, { "Ragdoll with a shove", { "ragdoll impulse", "physical" } }, { "Blacklight", { "blacklight", "physical" } }, { "Damage over time", { "dot", "dot_poison" } }, { "Burn over time", { "dot", "dot_fire" } }, { "Fire, no panic", { "on_fire_no_panic", "fire" } }, { "Prank fire", { "prank_fire", "physical" } }, { "Prank dissolve", { "prank_dissolve", "physical" } }, { "Sick", { "eat food stun", "physical" } }, { "Balisong", { "nahualli_balisong_effect", "physical" } }, { "Conscript", { "conscript", "physical" } }, { "Chill building", { "chill_builder", "water" } }, { "Toxic glow", { "toxic_waste", "dot_poison" } }, { "Car floors it", { "forced_accelerate", "physical" } }, { "Car swerves", { "forced_steering", "physical" } }, { "Car jumpy", { "hyper_sensitive", "physical" } } }),
    pset("full_auto", "Full auto", "Single-shot guns keep firing while you hold the trigger, mouse or RT.", { { "Off", false }, { "On", 70 }, { "Fast", 40 } }),
    wset("damage", "Damage", "x2 to x10: your guns only. One-hit kill: every gun, enemies' too, so pair it with God mode.", { { "Game's", 1 }, { "x2", 2 }, { "x5", 5 }, { "x10", 10 }, { "One-hit kill", "kill" } }),
    wset("reload", "Reload speed", "How fast reloads go.", { { "Game's", 1 }, { "x2", 2 }, { "x4", 4 }, { "Instant", 20 } }),
    wset("perfect_aim", "Perfect aim", "No spread: every shot goes where you aim.", { { "Off", false }, { "On", true } }),
    wset("no_recoil", "No recoil", "No kick when you fire, and no camera shake from it.", { { "Off", false }, { "On", true } }),
    wset("no_warmup", "No warm-up", "Miniguns spin up and charged weapons charge at once.", { { "Off", false }, { "On", true } }),
    wset("no_overheat", "No overheat", "Weapons that overheat never do.", { { "Off", false }, { "On", true } }),
    { kind = "any_perk", label = "Any perk", help = "Turns any of the game's perks on or off at Perk strength, until you quit. Left/Right picks, Enter switches. Many do unknown things.", sel = 1, options = PERK_LIST },
    pset("perk_strength", "Perk strength", "How strong Any perk turns one on. To change one already on, switch it off and on. Some are a chance, where 1 is always. Fire and Taser on enemy melee damage are seconds between hits, so lower is stronger.", { { "1", false }, { "0.5", 0.5 }, { "2", 2.0 }, { "5", 5.0 }, { "10", 10.0 } }),
    { kind = "pfn", fn = "perks_off", label = "My perks off", help = "Takes off everything Any perk turned on." },
    pset("melee_backfire", "Melee backfire", "Anyone who hits you with melee burns for 5 s, gets a shock for 5 s, or both, on nearly every hit. Guns don't set it off. All perks on or the shock perk itself adds its 15 s wait between shocks.", { { "Off", false },
      { "Fire", { { "passive_mod_class_fire_on_enemy_melee_damage", 0.1 } } }, { "Shock", { { "passive_mod_class_taser_on_enemy_melee_damage", 0.1 } } },
      { "Both", { { "passive_mod_class_fire_on_enemy_melee_damage", 0.1 }, { "passive_mod_class_taser_on_enemy_melee_damage", 0.1 } } } }),
    { kind = "pfn", fn = "takedown_ready", label = "Takedown ready now", help = "Fills your takedown meter once." },
    pset("always_execute", "Takedowns always kill", "Takedowns always use the kill version.", { { "Off", false }, { "On", true } }),
    pset("invisible_me", "You are invisible", "You fade out for the eye only: enemies still see you.", { { "Off", false }, { "On", true } }),
    { kind = "outfit_only", label = "Saved look: outfit only", help = "Wears the clothes of the look picked on Saved look, keeping your body." },
    pset("body_groin", "Body: groin", "Past the slider's top. Only on screen: your save keeps your real body.", { { "Game's", false }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 } }),
    pset("body_squeezed", "Body: squeezed", "Past the slider's top. Only on screen: your save keeps your real body.", { { "Game's", false }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 } }),
    pset("body_eye_gap", "Face: eye spacing", "Past the slider's top. Only on screen: your save keeps your real face.", { { "Game's", false }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 } }),
    pset("body_mouth_wide", "Face: mouth width", "Past the slider's top. Only on screen: your save keeps your real face.", { { "Game's", false }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 } }),
    wset("proj_speed", "Rocket speed", "How fast launchers and Special rounds fly.", { { "Game's", 1 }, { "x0.25", 0.25 }, { "x0.5", 0.5 }, { "x2", 2 }, { "x4", 4 } }),
    pset("car_ejector", "Ejector cannon", "Ejector seats throw you much higher.", { { "Game's", false }, { "x2", 2 }, { "x5", 5 }, { "x10", 10 } }),
    pset("car_cowcatcher", "Cowcatcher launch", "People the cowcatcher hits fly much further.", { { "Game's", false }, { "x2", 2 }, { "x5", 5 }, { "x10", 10 } }),
    pset("surf_fast", "Surf faster cars", "Jump onto much faster cars, with almost no wait between surfs.", { { "Game's", false }, { "x2", 2 }, { "x5", 5 } }),
    pset("roadblock_mania", "Roadblocks everywhere", "Up to 20 roadblocks, 20 m apart, a new one every 5 s while you're wanted.", { { "Off", false }, { "On", true } }),
    pset("pursuit_cars", "Chase cars", "How many cars chase you at each level. The game's are 1 to 3.", { { "Game's", false }, { "6", 6 }, { "12", 12 }, { "20", 20 } }),
    pset("heat_fast", "Notoriety climbs fast", "A tenth of the points to reach each level, so five stars comes fast.", { { "Off", false }, { "On", true } }),
    pset("escape_radius", "Escape distance", "How far you must get to lose them. The game's are 90 to 130.", { { "Game's", false }, { "Tiny", 20 }, { "Wide", 400 }, { "Huge", 1500 } }),
    { kind = "crowd_act", key = "calm", label = "Stop fights near", help = "Everyone within 40 m forgets who they were fighting, until they see a reason again." },
    { kind = "crowd_act", key = "revive", label = "Revive everyone near", help = "The downed within 40 m get back up." },
    { kind = "crowd_act", key = "strip", label = "Strip shields near", help = "Tough enemies within 40 m lose their shields." },
    { kind = "crowd_act", key = "tough", label = "Make everyone near tough", help = "Everyone within 40 m gets a tough shield, for harder fights." },
    { kind = "crowd_act", key = "stagger", label = "Everyone near staggers easily", help = "Any hit staggers everyone now within 40 m, for as long as they live." },
    { kind = "crowd_act", key = "unseen", label = "Fade out everyone near", help = "Everyone within 40 m fades out. They're still there." },
    { kind = "crowd_act", key = "seen", label = "Fade everyone near back in", help = "Brings back those within 40 m." },
    { kind = "crowd_act", key = "say", label = "Everyone near says it", help = "Everyone within 40 m with a voice says the line picked on Say a line." },
    { kind = "crowd_act", key = "bail", label = "Drivers near bail out", help = "Drivers within 40 m skid to a stop and bail out." },
    { kind = "crowd_act", key = "floor", label = "Drivers near floor it", help = "Drivers within 40 m put their foot down for 8 s." },
    pset("spawned_safe", "Spawned people can't die", "People you spawned stop taking damage, your army and bodyguards too.", { { "Off", false }, { "On", true } }),
    pset("downed_timer", "Downed timer", "How long you or anyone stays down before dying. The game's is 30 s.", { { "Game's", false }, { "2 min", 120 }, { "10 min", 600 }, { "A long time", 60000 } }),
    pset("instant_revive", "Instant revive", "Reviving someone takes no time.", { { "Off", false }, { "On", true } }),
    pset("guardian_angel", "Guardian angel", "The game's save from a lethal hit comes every second, not every 15, and lasts 3 s.", { { "Off", false }, { "On", true } }),
    pset("traffic_mood", "Traffic type", "Adds one of the game's spawn sets as the streets fill. It can ask for models that aren't loaded. Save first.", { { "Game's", false }, { "Bomb trucks", 0xA1CBE10A }, { "Ambulances", 0xCB2114E0 }, { "Dirt bikes", 0xF962793B }, { "Hobos", 0x872E3169 }, { "Modesty outlawed", 0xE1133E4F }, { "Marshall district", 0xA04896DB }, { "Dustfaire", 0x29956940 }, { "Sunshine Springs", 0x1C8C5249 } }),
    pset("long_trains", "Long trains", "Trains made from now on are longer.", { { "Game's", false }, { "x2", 2 }, { "x4", 4 } }),
    { kind = "pfn_list", fn = "start_diversion", label = "Start side job", help = "Starts a side job if the game allows it. Left/Right picks, Enter starts it. Save first.", sel = 1, options = { { "Repo: boat", "repo_boat" }, { "Repo: cache", "repo_cache" }, { "Repo: engine", "repo_engine" }, { "Repo: fire truck", "repo_firetruck" }, { "Repo: fireworks", "repo_fireworks" }, { "Repo: tank", "repo_tank" }, { "Repo: vault", "repo_vault" }, { "Maximum notoriousness", "maxmimum_notoriousness" }, { "Toxic dump", "toxic_dump_ambient" }, { "Radio station: Idols", "radio_station_idols_01" }, { "Radio station: Marshall", "radio_station_marshall_01" }, { "Radio station: Panteros", "radio_station_panteros_01" }, { "Haunted hotel", "dlc_02_haunted_questgiver" }, { "Haunted hotel, complete", "dlc_02_haunted_complete" }, { "Cactus farm", "dlc_dis02_ow_atcha_cactus_farm" }, { "Dumpster dive: Dustfaire 1", "dlc_dis02_ow_dumpster_dive_01" }, { "Dumpster dive: Dustfaire 2", "dlc_dis02_ow_dumpster_dive_02" }, { "Dumpster dive: Sunshine 1", "dlc_lucky_dumpster_dive_01" }, { "Dumpster dive: Sunshine 2", "dlc_lucky_dumpster_dive_02" } } },
    { kind = "pfn", fn = "spawned_to_car", label = "Spawned people get in my car", help = "People you spawned become your followers and climb into your vehicle." },
    { kind = "pfn", fn = "spawned_to_waypoint", label = "Spawned people go to waypoint", help = "People you spawned run to your map waypoint." },
    pset("peds_pay", "Pedestrians always pay", "Every civilian you kill drops cash, not one in four. Real money: it stays in your save.", { { "Off", false }, { "On", true } }),
    pset("downforce", "Downforce", "Your vehicle sticks to the road harder at speed.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    { kind = "game_list", class = "weapon_skin", label = "Weapon skin", help = "Puts a skin on the gun in your hands, if it's for that gun and unlocked. Left/Right picks, Enter puts it on. Save first.", sel = 1, options = {}, code = [[if not weapon_cust_apply_skin(player_local_inventory_get_active_slot(), vlib_info_object:get_object("weapon_skin", "%s")) then error("That skin isn't for this gun, or isn't unlocked") end]] },
    { kind = "pfn", fn = "hermit_juice", label = "Hermit juice", help = "The drink that warps you to a mystery spot and may hand you boots." },
    { kind = "pfn", fn = "radio_step", arg = 1, label = "Next station", help = "The next station on the radio in your vehicle, even if a mission locked it." },
    { kind = "pfn", fn = "radio_step", arg = -1, label = "Previous station", help = "The station before, even if a mission locked it." },
    pset("radio_unlock", "Unlock radio in missions", "You can change station when a mission locked the radio.", { { "Off", false }, { "On", true } }),
    { kind = "hq_fill", label = "Fill the HQ", help = "Fills every spot, one by one. Left/Right picks how, Enter twice. Stays in your save.", sel = 1, options = { { "Random", "random" }, { "Huge props only", "huge" }, { "Clear all", "clear" } } },
    gchoice("Screen tint", "The game's screen-edge colour, in any colour. Left/Right picks, Enter sets it.", { { "Off", [[gml_vignette_override(false) return "off"]] }, { "Red", [[gml_vignette_override(true) gml_vignette_color(1, 0, 0) gml_vignette_intensity(1) return "red"]] }, { "Green", [[gml_vignette_override(true) gml_vignette_color(0, 1, 0) gml_vignette_intensity(1) return "green"]] }, { "Blue", [[gml_vignette_override(true) gml_vignette_color(0, 0, 1) gml_vignette_intensity(1) return "blue"]] }, { "Gold", [[gml_vignette_override(true) gml_vignette_color(1, 0.7, 0) gml_vignette_intensity(1) return "gold"]] }, { "Purple", [[gml_vignette_override(true) gml_vignette_color(0.6, 0, 1) gml_vignette_intensity(1) return "purple"]] }, { "Black", [[gml_vignette_override(true) gml_vignette_color(0, 0, 0) gml_vignette_intensity(1) return "black"]] }, { "White", [[gml_vignette_override(true) gml_vignette_color(1, 1, 1) gml_vignette_intensity(1) return "white"]] } }),
    { kind = "console_row", label = "Camera effects", handler = 0x9CE4B0, help = "The game's switch for camera effects, off or back on." },
    { kind = "console_row", label = "All caps text", handler = 0x1315920, help = "Every piece of interface text in capitals, or back." },
    pset("spawn_loadout", "Spawned people carry", "What people you spawn from now on carry. Pair with Your army or Bodyguards. Some can't take a weapon. Save first.", { { "Their own", false }, { "Saints pistol", "saint_grunt_pistol" }, { "Saints rifle", "saint_grunt_rifle" }, { "Saints shotgun", "saint_grunt_shotgun" }, { "Saints assault", "saint_grunt_assault" }, { "Saints bat", "saint_grunt_bat" }, { "Saints rocket", "saint_grunt_rocket" }, { "Panteros pistol", "panteros_grunt_pistol" }, { "Panteros shotgun", "panteros_grunt_shotgun" }, { "Idols pistol", "idols_grunt_pistol" }, { "Idols SMG", "idols_grunt_smg" }, { "Marshall carbine", "marshall_grunt_carbine" }, { "Police pistol", "police_grunt_pistol" }, { "SWAT burst", "police_swat_burst" }, { "Drug dealer AR", "nonfaction_drug_dealer_ar" }, { "Hitman", "nonfaction_hitman" } }),
    { kind = "pfn_list", fn = "call_follower", label = "Call in follower", help = "Calls someone in as a follower, at most 4 at once. Left/Right picks, Enter calls them. Save first.", sel = 1, options = { { "Saints grunt", "saints_grunt_male" }, { "Panteros grunt", "enemy_panteros_grunt_pistol" }, { "Fighting pedestrian", "enemy_combat_ped" }, { "Cat mascot", "ally_nonfaction_mascot_cat" }, { "Coyote", "enemy_quadruped_coyote" } } },
    { kind = "pfn_list", class = "ai_combat_orders_config", fn = "order_near", label = "Order everyone near", help = "Any of the game's 129 orders. Left/Right picks, Enter gives it. Most do what they say; some need a place or a fight.", sel = 1, options = {} },
    { kind = "pfn_list", fn = "mood_near", label = "Face on everyone near", help = "A mood for everyone's face within 40 m. Left/Right picks, Enter sets it. It may only show in some animations.", sel = 1, options = { { "Anger", "anger" }, { "Contempt", "contempt" }, { "Disgust", "disgust" }, { "Fear", "fear" }, { "Happiness", "happiness" }, { "Pain", "pain" }, { "Sadness", "sadness" }, { "Surprise", "surprise" }, { "None", "none" } } },
    { kind = "pfn_list", class = "radio_station_info", fn = "radios_near", label = "Radios in cars near", help = "Every car within 40 m plays a station. Left/Right picks, Enter plays it. Off stops them.", sel = 1, options = {} },
    { kind = "pfn", fn = "grenade_takedown", label = "Grenade takedown", help = "The Pineapple Express takedown on your current target, without the skill." },
    pset("skill_fast", "Skills recharge at once", "Skills are ready again right after use, from the next time each is drawn.", { { "Off", false }, { "On", true } }),
    { kind = "immune", label = "Immune to", help = "Stops one status effect hitting you. Left/Right picks, Enter turns it on or off. Lost when you respawn.", sel = 1, options = {} },
    { kind = "face_part", class = "char_cust_facial_morph_group", label = "Face part", help = "Sets one of the 50 face parts to Face amount. Left/Right picks, Enter sets it. Stays if you save; Undo my look puts it back.", sel = 1, options = {} },
    pset("face_amount", "Face amount", "How far Face part goes. The game's sliders stop at 100.", { { "+100", false }, { "+200", 200 }, { "+300", 300 }, { "+500", 500 }, { "-100", -100 }, { "-200", -200 }, { "-300", -300 }, { "-500", -500 }, { "Centre", 0 } }),
    pset("crusher", "Crusher", "Your vehicle flattens other cars and props like the monster truck. Off may not fully undo it for that car.", { { "Off", false }, { "On", true } }),
    pset("surf_safe", "Surfing is safe", "The world can't hurt you while you surf a car.", { { "Off", false }, { "On", true } }),
    pset("hover_slam", "Hoverboard slam", "Turns on the hoverboard's slam.", { { "Off", false }, { "On", true } }),
    pset("venture_income", "Venture income", "What ventures pay. It may only reach ones you build from now on. Real money: it stays in your save.", { { "Game's", false }, { "x10", 10 }, { "x100", 100 } }),
    pset("fraud_launch", "Insurance Fraud launch", "How hard you're thrown in Insurance Fraud.", { { "Game's", false }, { "x2", 2 }, { "x5", 5 }, { "x20", 20 } }),
    { kind = "hq_save", label = "Save HQ layout", help = "Keeps what's on every spot in a file. Left/Right picks a slot, Enter keeps it.", sel = 1, options = { { "Slot 1", 1 }, { "Slot 2", 2 }, { "Slot 3", 3 } } },
    { kind = "hq_load", label = "Load HQ layout", help = "Puts a kept layout back. Left/Right picks a slot, Enter twice. Stays in your save.", sel = 1, options = { { "Slot 1", 1 }, { "Slot 2", 2 }, { "Slot 3", 3 } } },
    gcall("New save", "A new save file, as the game's save menu makes.", "gml_ui_save_game_save() return 'saving'"),
    { kind = "gun_slot", label = "Put picked gun in slot", help = "Puts the gun picked on Give weapon in a slot, even one it doesn't belong in, replacing what's there. Left/Right picks, Enter puts it. Save first.", sel = 1, options = { { "Melee", 1 }, { "Pistol", 2 }, { "SMG", 3 }, { "Rifle", 4 }, { "Shotgun", 5 }, { "Launcher", 6 }, { "Special", 7 }, { "Temporary", 8 } } },
    { kind = "radio_line", class = "gml_persona", label = "Radio call from", help = "Plays the line picked on Say a line as a radio call. Left/Right picks a voice, Enter plays it. Silent if that voice isn't loaded.", sel = 1, options = {} },
    pset("surf_autopilot", "Surf autopilot", "The car you surf with Surf nearest car drives itself.", { { "Off", false }, { "On", true } }),
    pset("ride_height", "Ride height", "How high your vehicle sits.", { { "Game's", false }, { "Lowrider", 0.6 }, { "Lifted", 1.5 }, { "Monster", 2.5 } }),
    pset("cam_nose", "Car camera follows the nose", "The camera points where the car points, not where it's sliding.", { { "Off", false }, { "On", true } }),
    pset("car_fov", "Car camera field of view", "A wider or narrower view while you're in a vehicle.", { { "Game's", false }, { "x0.8", 0.8 }, { "x1.2", 1.2 }, { "x1.5", 1.5 } }),
    pset("no_wind", "No wind on clothes", "Your clothes stop blowing about.", { { "Off", false }, { "On", true } }),
    pset("blackout", "Blackout", "The world stops being drawn. The HUD and menu stay.", { { "Off", false }, { "On", true } }),
    pset("enemies_arrive", "Enemies arrive from", "How far away reinforcements appear. The game's are 60 m on foot and 90 m in cars.", { { "Game's", false }, { "Closer", 0.5 }, { "On top of you", 0.25 }, { "Further", 2 } }),
    pset("peds_far", "People appear at", "How far away people appear. The game's is 65 m.", { { "Game's", false }, { "Close", 30.0 }, { "Far", 150.0 }, { "Very far", 300.0 } }),
    pset("notoriety_uncapped", "No notoriety cap", "Removes the limit your story progress puts on notoriety.", { { "Off", false }, { "On", true } }),
    opt("Minimap size", "The game's minimap size option. Takes effect the next time the HUD loads.", "options_get_map_size()", "options_set_map_size(%s)", { { "Small", 0 }, { "Medium", 0.5 }, { "Large", 1 } }),
    pset("no_boundary", "No world boundary", "Fly past the edge of the map with no warning and no turning back.", { { "Off", false }, { "On", true } }),
    pset("unseen_by_ai", "Enemies can't see you", "Enemies don't see you, unless you give them a reason.", { { "Off", false }, { "On", true } }),
    pset("enemy_sight", "Enemy sight", "How far people can see. The game's is 45 m at rest.", { { "Game's", false }, { "Short", 0.25 }, { "Almost blind", 0.05 }, { "Long", 3 } }),
    pset("notoriety_min", "Notoriety at least", "Your notoriety never falls below this, with every gang and the police.", { { "Off", false }, { "1 star", 1 }, { "2 stars", 2 }, { "3 stars", 3 }, { "4 stars", 4 }, { "5 stars", 5 } }),
    pset("notoriety_max", "Notoriety at most", "Your notoriety never rises above this, with every gang and the police.", { { "Off", false }, { "1 star", 1 }, { "2 stars", 2 }, { "3 stars", 3 }, { "4 stars", 4 }, { "5 stars", 5 } }),
    pset("always_wounded", "Wounded walk", "Walk hurt all the time, or never.", { { "Game's", false }, { "Always", 1.01 }, { "Never", 0.0 } }),
    pset("flame_me", "You look on fire", "You burn, with no damage.", { { "Off", false }, { "On", true } }),
    pset("aim_anywhere", "Aim anywhere", "Aim while you sprint or glide.", { { "Off", false }, { "On", true } }),
    pset("quiet_streets", "Quiet streets", "People on the street stop talking.", { { "Off", false }, { "On", true } }),
    pset("quiet_homies", "Quiet homies", "Your homies stop their banter.", { { "Off", false }, { "On", true } }),
    pset("blacklight", "Blacklight world", "Everything lights up as under the Idols' blacklight.", { { "Off", false }, { "On", true } }),
    pset("tracer_colour", "All shots one colour", "Tracers, muzzle flashes and blasts in one colour. Going back to Game's needs a restart.", { { "Game's", false }, { "Red", { 1.0, 0.05, 0.05 } }, { "Green", { 0.05, 1.0, 0.05 } }, { "Blue", { 0.05, 0.2, 1.0 } }, { "Purple", { 0.7, 0.05, 1.0 } }, { "Gold", { 1.0, 0.7, 0.05 } }, { "White", { 1.0, 1.0, 1.0 } } }),
    pset("radial_blur", "Radial blur", "The screen's edges blur, as at speed.", { { "Off", false }, { "Light", 0.3 }, { "Strong", 1.0 } }),
    { kind = "pfn_list", fn = "play_sound", label = "Play sound", help = "Plays one of the game's sound events. Left/Right picks, Enter plays it. Some are silent until they're loaded.", sel = 1, options = SOUND_LIST },
    { kind = "crowd_act", key = "statue", label = "Statues near", help = "Everyone within 40 m stands rigid." },
    { kind = "crowd_act", key = "unstatue", label = "Statues near back to life", help = "Lets those within 40 m move again." },
    { kind = "crowd_act", key = "flame", label = "Flaming look near", help = "Everyone within 40 m burns, with no damage." },
    { kind = "crowd_act", key = "unflame", label = "Flaming look near off", help = "Ends the flaming look within 40 m." },
    { kind = "crowd_act", key = "alarm", label = "Set off car alarms", help = "Every car within 40 m wails." },
    { kind = "crowd_act", key = "siren", label = "Sirens on near", help = "Every car within 40 m that has a siren turns it on." },
    { kind = "crowd_act", key = "spin", label = "Spin cars near", help = "Every car within 40 m spins." },
    gchoice("Wheel size", "The tires of your vehicle. Left/Right picks, Enter sets it.", { { "Game's", [[vehicle_set_tire_scale(vehicle_get_current(), 0, 1, 1) vehicle_set_tire_scale(vehicle_get_current(), 1, 1, 1) return "game's"]] }, { "Big", [[vehicle_set_tire_scale(vehicle_get_current(), 0, 1.5, 1.5) vehicle_set_tire_scale(vehicle_get_current(), 1, 1.5, 1.5) return "big"]] }, { "Huge", [[vehicle_set_tire_scale(vehicle_get_current(), 0, 2.5, 2.5) vehicle_set_tire_scale(vehicle_get_current(), 1, 2.5, 2.5) return "huge"]] }, { "Tiny", [[vehicle_set_tire_scale(vehicle_get_current(), 0, 0.5, 0.5) vehicle_set_tire_scale(vehicle_get_current(), 1, 0.5, 0.5) return "tiny"]] } }),
    gchoice("Underglow preset", "Any of the 27 underglow colours on your vehicle. Left/Right picks, Enter sets it.", { { "Off", [[return "left as it is"]] }, { "Colour 1", [[vehicle_set_underglow_color(vehicle_get_current(), 0) return "colour 1"]] }, { "Colour 2", [[vehicle_set_underglow_color(vehicle_get_current(), 1) return "colour 2"]] }, { "Colour 3", [[vehicle_set_underglow_color(vehicle_get_current(), 2) return "colour 3"]] }, { "Colour 4", [[vehicle_set_underglow_color(vehicle_get_current(), 3) return "colour 4"]] }, { "Colour 5", [[vehicle_set_underglow_color(vehicle_get_current(), 4) return "colour 5"]] }, { "Colour 6", [[vehicle_set_underglow_color(vehicle_get_current(), 5) return "colour 6"]] }, { "Colour 7", [[vehicle_set_underglow_color(vehicle_get_current(), 6) return "colour 7"]] }, { "Colour 8", [[vehicle_set_underglow_color(vehicle_get_current(), 7) return "colour 8"]] }, { "Colour 9", [[vehicle_set_underglow_color(vehicle_get_current(), 8) return "colour 9"]] }, { "Colour 10", [[vehicle_set_underglow_color(vehicle_get_current(), 9) return "colour 10"]] }, { "Colour 11", [[vehicle_set_underglow_color(vehicle_get_current(), 10) return "colour 11"]] }, { "Colour 12", [[vehicle_set_underglow_color(vehicle_get_current(), 11) return "colour 12"]] }, { "Colour 13", [[vehicle_set_underglow_color(vehicle_get_current(), 12) return "colour 13"]] }, { "Colour 14", [[vehicle_set_underglow_color(vehicle_get_current(), 13) return "colour 14"]] }, { "Colour 15", [[vehicle_set_underglow_color(vehicle_get_current(), 14) return "colour 15"]] }, { "Colour 16", [[vehicle_set_underglow_color(vehicle_get_current(), 15) return "colour 16"]] }, { "Colour 17", [[vehicle_set_underglow_color(vehicle_get_current(), 16) return "colour 17"]] }, { "Colour 18", [[vehicle_set_underglow_color(vehicle_get_current(), 17) return "colour 18"]] }, { "Colour 19", [[vehicle_set_underglow_color(vehicle_get_current(), 18) return "colour 19"]] }, { "Colour 20", [[vehicle_set_underglow_color(vehicle_get_current(), 19) return "colour 20"]] }, { "Colour 21", [[vehicle_set_underglow_color(vehicle_get_current(), 20) return "colour 21"]] }, { "Colour 22", [[vehicle_set_underglow_color(vehicle_get_current(), 21) return "colour 22"]] }, { "Colour 23", [[vehicle_set_underglow_color(vehicle_get_current(), 22) return "colour 23"]] }, { "Colour 24", [[vehicle_set_underglow_color(vehicle_get_current(), 23) return "colour 24"]] }, { "Colour 25", [[vehicle_set_underglow_color(vehicle_get_current(), 24) return "colour 25"]] }, { "Colour 26", [[vehicle_set_underglow_color(vehicle_get_current(), 25) return "colour 26"]] }, { "Colour 27", [[vehicle_set_underglow_color(vehicle_get_current(), 26) return "colour 27"]] } }),
    gcall("Headlights on", "Turns on the lights of your vehicle.", "vehicle_activate_lights(vehicle_get_current(), true) return 'on'"),
    pset("swim_land", "Swim on land", "You move as if swimming, on foot.", { { "Off", false }, { "On", true } }),
    pset("crouch_always", "Always crouch", "You stay crouched.", { { "Off", false }, { "On", true } }),
    pset("wind", "Wind push", "Pushes you the way you face for as long as it's on.", { { "Off", false }, { "Breeze", 2.0 }, { "Gale", 8.0 }, { "Hurricane", 25.0 } }),
    pset("no_shove", "No shoving", "You stop bumping people out of the way.", { { "Off", false }, { "On", true } }),
    pset("short_takedowns", "Short takedowns only", "No long takedown animations.", { { "Off", false }, { "On", true } }),
    pset("no_takedowns", "No takedowns", "The takedown prompt stops working.", { { "Off", false }, { "On", true } }),
    pset("dustlander_takedowns", "Dustlander takedowns", "Takedowns use the Dustlander moves. Their animations may not be loaded.", { { "Off", false }, { "On", true } }),
    { kind = "pfn", fn = "wing_bounce", label = "Wingsuit bounce", help = "A kick in mid-air, as off a car roof." },
    { kind = "pfn", fn = "glide_to_car", label = "Glide to nearest car", help = "The wingsuit steers you to the nearest car within 200 m." },
    { kind = "pfn", fn = "level_up", label = "Level up once", help = "One level. Stays in your save." },
    gcall("Refund all skills", "Your skill points come back. Save first.", "player_local_refund_all_skills() return 'refunded'"),
    { kind = "pfn_list", fn = "skin_me", label = "Skin effect on you", help = "Puts a skin effect on you. Left/Right picks, Enter puts it on. Dissolves may hide you until Stop skin effects.", sel = 1, options = { { "Burnt", "vfx_burnt" }, { "Kisses", "vfx_kisses" }, { "Snow", "vfx_snow" }, { "Wet look", "vfx_wet_look" }, { "Toxic glow", "vfx_toxic_glow" }, { "Electric", "vfx_electric_highlight" }, { "Hit flash", "vfx_hit_flash_01" }, { "Edge glow", "vfx_edge_highlight_01" }, { "Edge glow 2", "vfx_edge_highlight_02" }, { "Fist cannon glow", "vfx_fist_cannon_ult_glow" }, { "Combat outline", "vfx_object_outline_combat_01" }, { "Combat outline 2", "vfx_object_outline_combat_02" }, { "Skill active", "vfx_skill-perk_active" }, { "Hologram", "vfx_hologram_spawn" }, { "Hologram out", "vfx_hologram_die" }, { "Energy out", "vfx_energy_derez_out" }, { "Fire dissolve", "vfx_fire_dissolve" }, { "Portal dissolve", "vfx_portal_dissolve" }, { "Toxic dissolve", "vfx_toxic_dissolve" }, { "Tumbleweed dissolve", "vfx_tumbleweed_dissolve" }, { "Fabric rip", "vfx_fabric_rip_dissolve" }, { "Hologram disguise", "vfx_holo_disguise_fullcycle" }, { "Possessed", "possessed_ghost" }, { "Ghost dissolve", "ghost_dissolve" }, { "Face scan", "vfx_face-scan_01" }, { "Gold shimmer", "vfx_cash_hilight_gold" } , { "Build cust hover", "build_cust_hover" }, { "Build cust invalid", "build_cust_invalid" }, { "Build cust valid", "build_cust_valid" }, { "High contrast fill avatar", "high_contrast_fill-avatar" }, { "High contrast fill avatar skill perk activate", "high_contrast_fill-avatar_skill-perk_activate" }, { "High contrast fill avatar skill perk activate durable", "high_contrast_fill-avatar_skill-perk_activate_durable" }, { "High contrast fill avatar skill perk activate elite electric", "high_contrast_fill-avatar_skill-perk_activate_elite-electric" }, { "High contrast fill avatar skill perk activate elite skilled", "high_contrast_fill-avatar_skill-perk_activate_elite-skilled" }, { "High contrast fill avatar skill perk active", "high_contrast_fill-avatar_skill-perk_active" }, { "High contrast fill avatar skill perk active berserk", "high_contrast_fill-avatar_skill-perk_active_berserk" }, { "High contrast fill avatar skill perk active get tough", "high_contrast_fill-avatar_skill-perk_active_get-tough" }, { "High contrast fill avatar skill perk active quick escape", "high_contrast_fill-avatar_skill-perk_active_quick-escape" }, { "High contrast fill enemy", "high_contrast_fill-enemy" }, { "High contrast fill finisher", "high_contrast_fill-finisher" }, { "High contrast fill friend", "high_contrast_fill-friend" }, { "High contrast fill neutral", "high_contrast_fill-neutral" }, { "High contrast fill possessed ghost", "high_contrast_fill_possessed_ghost" }, { "High contrast outline avatar", "high_contrast_outline-avatar" }, { "High contrast outline avatar skill perk activate", "high_contrast_outline-avatar_skill-perk_activate" }, { "High contrast outline avatar skill perk activate durable", "high_contrast_outline-avatar_skill-perk_activate_durable" }, { "High contrast outline avatar skill perk activate elite electric", "high_contrast_outline-avatar_skill-perk_activate_elite-electric" }, { "High contrast outline avatar skill perk activate elite skilled", "high_contrast_outline-avatar_skill-perk_activate_elite-skilled" }, { "High contrast outline avatar skill perk active", "high_contrast_outline-avatar_skill-perk_active" }, { "High contrast outline avatar skill perk active berserk", "high_contrast_outline-avatar_skill-perk_active_berserk" }, { "High contrast outline avatar skill perk active get tough", "high_contrast_outline-avatar_skill-perk_active_get-tough" }, { "High contrast outline avatar skill perk active quick escape", "high_contrast_outline-avatar_skill-perk_active_quick-escape" }, { "High contrast outline enemy", "high_contrast_outline-enemy" }, { "High contrast outline finisher", "high_contrast_outline-finisher" }, { "High contrast outline friend", "high_contrast_outline-friend" }, { "High contrast outline neutral", "high_contrast_outline-neutral" }, { "High contrast possessed ghost", "high_contrast_possessed_ghost" }, { "Prop collect collectable", "prop collect - collectable" }, { "Prop collect collected", "prop collect - collected" }, { "Prop collect new", "prop collect - new" }, { "Prop collectible 01", "prop_collectible_01" }, { "Derez out hologram", "vfx_derez_out_hologram" }, { "Holo disguise off", "vfx_holo_disguise_off" }, { "Holo disguise on", "vfx_holo_disguise_on" }, { "Lmg barrel heat glow", "vfx_lmg_barrel_heat_glow" }, { "Map object outline 01", "vfx_map-object_outline_01" }, { "Object highlight 01", "vfx_object_highlight_01" }, { "Pickup highlight ammo", "vfx_pickup_highlight_ammo" }, { "Pickup highlight cash", "vfx_pickup_highlight_cash" }, { "Pickup highlight collectable", "vfx_pickup_highlight_collectable" }, { "Pickup highlight cuttingedge", "vfx_pickup_highlight_cuttingedge" }, { "Pickup highlight weapons", "vfx_pickup_highlight_weapons" }, { "Skill perk activate", "vfx_skill-perk_activate" }, { "Skill perk activate elite electrified", "vfx_skill-perk_activate_elite-electrified" }, { "Skill perk activate elite skilled", "vfx_skill-perk_activate_elite-skilled" }, { "Skill perk activate major durable", "vfx_skill-perk_activate_major-durable" }, { "Skill perk active berserk", "vfx_skill-perk_active_berserk" }, { "Skill perk active get tough", "vfx_skill-perk_active_get-tough" }, { "Skill perk active quick escape", "vfx_skill-perk_active_quick-escape" }, { "Test", "vfx_test" }, { "Test outline 2", "vfx_test_outline_2" }, { "Tether object highlight", "vfx_tether_object_highlight" }, { "Tumbleweed dissolve no glow", "vfx_tumbleweed_dissolve_no_glow" }} },
    { kind = "pfn", fn = "skins_off", label = "Stop skin effects", help = "Ends every skin effect the menu started." },
    { kind = "pfn_list", fn = "fx_colour_me", label = "Coloured glow on you", help = "A skin effect in a colour the game only uses elsewhere: rim glows, lines, flashes, toy-soldier tints, dissolves and outlines. Left/Right picks, Enter puts it on; Stop skin effects ends it.", sel = 1, options = (function() local o = {} for _, v in ipairs(P.FX_COLOURS) do o[#o + 1] = { v[1], v } end return o end)() },
    { kind = "pfn_list", fn = "fx_colour_near", label = "Coloured glow near", help = "Coloured glow on everyone within 40 m. Left/Right picks, Enter puts it on; Stop skin effects ends it.", sel = 1, options = (function() local o = {} for _, v in ipairs(P.FX_COLOURS) do o[#o + 1] = { v[1], v } end return o end)() },
    { kind = "pfn", fn = "clone_me", label = "Clone of me", help = "A second you, beside you: your body, face, hair and clothes. One at a time: the game has room for one more body like yours. Offline only. It can't be killed." },
    pset("clone_guard", "Clone is your bodyguard", "Your clone follows you, gets in your car and fights beside you. Off: it stands where it is.", { { "Off", false }, { "On", true } }),
    { kind = "pfn", fn = "clone_remove", label = "Remove clone", help = "Takes your clone away." },
    pset("my_glow", "Underglow on you", "A coloured light that goes where you go and lights you, the ground and everyone near, like a car's underglow. Brightest at night. Left/Right changes the colour. Pair with Your glow size and Your glow brightness.", { { "Off", false }, { "Red", { 255, 20, 20 } }, { "Orange", { 255, 120, 0 } }, { "Yellow", { 255, 230, 20 } }, { "Lime", { 150, 255, 20 } }, { "Green", { 20, 255, 40 } }, { "Teal", { 20, 240, 240 } }, { "Sky blue", { 60, 170, 255 } }, { "Blue", { 20, 60, 255 } }, { "Purple", { 150, 30, 255 } }, { "Magenta", { 255, 20, 255 } }, { "Pink", { 255, 80, 190 } }, { "Saints purple", { 120, 0, 200 } }, { "Warm white", { 255, 200, 140 } }, { "White", { 255, 255, 255 } } }),
    pset("my_glow_size", "Your glow size", "How far the light from Underglow on you reaches.", { { "Medium", 6 }, { "Large", 10 }, { "Huge", 16 }, { "Massive", 25 }, { "Tiny", 2 }, { "Small", 3.5 } }),
    pset("my_glow_bright", "Your glow brightness", "How strong the light from Underglow on you is. Left/Right turns it up or down.", { { "Normal", 3000 }, { "Bright", 6000 }, { "Brighter", 12000 }, { "Blinding", 25000 }, { "Faint", 300 }, { "Dim", 800 }, { "Soft", 1500 } }),
    { kind = "pfn", fn = "random_face", label = "Random face", help = "A new random face. Stays if you save; Undo my look puts it back." },
    pset("long_legs", "Long legs", "Stretched legs. May stretch anyone with your skeleton. Only on screen.", { { "Off", false }, { "x1.25", 1.25 }, { "x1.5", 1.5 }, { "x2", 2.0 } }),
    pset("hide_gun", "Hide my gun", "The gun in your hands fades out, and still fires.", { { "Off", false }, { "On", true } }),
    pset("satchels", "More satchels", "How many satchels can be out at once.", { { "Game's", false }, { "10", 10 }, { "25", 25 }, { "50", 50 } }),
    gcall("Random gun colours", "Re-rolls the colours of the gun in your hands. Stays in your save. Draw it again if it doesn't show.", "weapon_cust_randomize_colors(player_local_inventory_get_active_slot()) return 'rolled'"),
    pset("ammo_drops", "Rare ammo drops", "How often enemies drop launcher and special ammo.", { { "Game's", false }, { "x5", 5 }, { "x20", 20 } }),
    { kind = "game_list", class = "vehicle_horn_info", label = "Any horn", help = "Changes your vehicle's horn. Left/Right picks, Enter puts it on.", sel = 1, options = {}, code = [[vehicle_set_horn_audio(vehicle_get_current(), vlib_info_object:get_object("vehicle_horn_info", "%s"), false)]] },
    { kind = "game_list", class = "vehicle_engine_audio_info", label = "Any engine sound", help = "Changes your vehicle's engine sound. Left/Right picks, Enter puts it on. Silent if its sounds aren't loaded.", sel = 1, options = {}, code = [[vehicle_set_engine_audio(vehicle_get_current(), vlib_info_object:get_object("vehicle_engine_audio_info", "%s"), false)]] },
    pset("tire_marks", "Always tire marks", "Your vehicle always leaves black marks.", { { "Off", false }, { "On", true } }),
    pset("twitchy", "Twitchy body", "Your vehicle's body yaws about.", { { "Off", false }, { "Some", 0.5 }, { "A lot", 2.0 } }),
    { kind = "pfn", fn = "back_on_road", label = "Back on the road", help = "Your vehicle jumps to the nearest lane." },
    pset("callin_speed", "Reinforcement speed", "Seconds between reinforcement calls, at every level.", { { "Game's", false }, { "Fast", { 1.0, 3.0 } }, { "Non-stop", { 0.2, 0.5 } }, { "Slow", { 60.0, 120.0 } } }),
    pset("no_ramming", "No ramming", "Chasing cars stop ramming you.", { { "Off", false }, { "On", true } }),
    pset("chase_speed", "Chase speed", "How fast chasing cars drive.", { { "Game's", false }, { "Slow", 0.5 }, { "Fast", 1.5 }, { "Very fast", 3.0 } }),
    { kind = "weather_now", label = "Any weather, instantly", help = "Goes straight to the weather picked on Any weather, with no blend." },
    pset("time_stop", "Only you move", "Pair with Pause world. It may not free you: the game's own use isn't known.", { { "Off", false }, { "On", true } }),
    pset("weather_indoors", "Indoor weather outside", "The outdoors gets interior weather.", { { "Off", false }, { "On", true } }),
    pset("no_trains", "No trains", "The lines stay empty.", { { "Off", false }, { "On", true } }),
    { kind = "pfn_list", fn = "traffic_light", label = "Traffic light here", help = "Sets the junction you're standing at. Left/Right picks, Enter sets it. Reset it from the same spot.", sel = 1, options = { { "Red", 1 }, { "Green", 2 }, { "Yellow", 3 }, { "Reset", 0 } } },
    gchoice("Shuffle playlists", "Every playlist plays shuffled. Left/Right picks, Enter sets it. Stays in your save.", { { "On", [[for _, p in vlib_info_object:ipairs("playlist_info") do playlist_set_shuffle(p, true) end return "on"]] }, { "Off", [[for _, p in vlib_info_object:ipairs("playlist_info") do playlist_set_shuffle(p, false) end return "off"]] } }),
    { kind = "pfn_list", class = "radio_station_info", fn = "radio_foot", label = "Radio on foot", help = "The real station with its DJ and ads, as you walk. Left/Right picks, Enter plays it. It stops in a vehicle. Off ends it.", sel = 1, options = {} },
    opt("Master volume", "How loud everything is. The game's own setting.", "option_get_master_volume()", "option_set_master_volume(%s)", { { "Mute", 0 }, { "25%", 0.25 }, { "50%", 0.5 }, { "75%", 0.75 }, { "Full", 1 } }),
    opt("Music volume", "How loud music is. The game's own setting.", "option_get_music_volume()", "option_set_music_volume(%s)", { { "Mute", 0 }, { "25%", 0.25 }, { "50%", 0.5 }, { "75%", 0.75 }, { "Full", 1 } }),
    opt("Effects volume", "How loud sound effects are. The game's own setting.", "option_get_sfx_volume()", "option_set_sfx_volume(%s)", { { "Mute", 0 }, { "25%", 0.25 }, { "50%", 0.5 }, { "75%", 0.75 }, { "Full", 1 } }),
    opt("Voice volume", "How loud voices are. The game's own setting.", "option_get_voice_volume()", "option_set_voice_volume(%s)", { { "Mute", 0 }, { "25%", 0.25 }, { "50%", 0.5 }, { "75%", 0.75 }, { "Full", 1 } }),
    pset("city_noise", "City panic noise", "Crowd panic in the sound mix, on demand. The game may keep overriding it.", { { "Off", false }, { "Some", 50 }, { "Full", 100 } }),
    opt("Takedown outlines", "The outline around people you can finish off. Off hides it. It's the game's own setting, so it stays.", "option_get_finisher_outline()", "option_set_finisher_outline(%s)", { { "On", 1 }, { "Off", 2 } }),
    opt("High contrast", "The game's accessibility look: people outlined by side. Outline everyone near needs it.", "option_get_high_contrast()", "option_set_high_contrast(%s)", { { "Off", 1 }, { "On", 2 }, { "On, extra pass", 3 } }),
    opt("Crosshair size", "How big the crosshair is. The game's own setting.", "option_get_reticle_cursor_scale()", "option_set_reticle_cursor_scale(%s)", { { "Small", 0.5 }, { "Normal", 1 }, { "Big", 1.5 }, { "Huge", 2 } }),
    gchoice("HUD style", "The Saints, Marshall or plain tint on the HUD. Left/Right picks, Enter sets it.", { { "Game's", [[local o = rawget(_G, "SR5TM_HUD") if o then saints_hud_is_enabled, saints_hud_is_marshall, saints_hud_is_vanilla, saints_hud_select_style = o[1], o[2], o[3], o[4] if hud_3d_refresh_saints_hud then hud_3d_refresh_saints_hud() end end return "set"]] }, { "Saints", [[if not rawget(_G, "SR5TM_HUD") then rawset(_G, "SR5TM_HUD", { saints_hud_is_enabled, saints_hud_is_marshall, saints_hud_is_vanilla, saints_hud_select_style }) end local S = 2 function saints_hud_is_enabled() return S == 2 end function saints_hud_is_marshall() return S == 0 end function saints_hud_is_vanilla() return S == 1 end function saints_hud_select_style(a, b, c) if S == 0 then return a elseif S == 1 then return b end return c end if hud_3d_refresh_saints_hud then hud_3d_refresh_saints_hud() end return "set"]] }, { "Marshall", [[if not rawget(_G, "SR5TM_HUD") then rawset(_G, "SR5TM_HUD", { saints_hud_is_enabled, saints_hud_is_marshall, saints_hud_is_vanilla, saints_hud_select_style }) end local S = 0 function saints_hud_is_enabled() return S == 2 end function saints_hud_is_marshall() return S == 0 end function saints_hud_is_vanilla() return S == 1 end function saints_hud_select_style(a, b, c) if S == 0 then return a elseif S == 1 then return b end return c end if hud_3d_refresh_saints_hud then hud_3d_refresh_saints_hud() end return "set"]] }, { "Plain", [[if not rawget(_G, "SR5TM_HUD") then rawset(_G, "SR5TM_HUD", { saints_hud_is_enabled, saints_hud_is_marshall, saints_hud_is_vanilla, saints_hud_select_style }) end local S = 1 function saints_hud_is_enabled() return S == 2 end function saints_hud_is_marshall() return S == 0 end function saints_hud_is_vanilla() return S == 1 end function saints_hud_select_style(a, b, c) if S == 0 then return a elseif S == 1 then return b end return c end if hud_3d_refresh_saints_hud then hud_3d_refresh_saints_hud() end return "set"]] } }),
    gchoice("Tunnel vision", "Dark edges closing in. Left/Right picks, Enter sets it.", { { "Off", [[gml_vignette_override(false) return "off"]] }, { "Some", [[gml_vignette_override(true) gml_vignette_color(0, 0, 0) gml_vignette_intensity(1) gml_vignette_radius(0.6) gml_vignette_softness(0.4) return "some"]] }, { "Narrow", [[gml_vignette_override(true) gml_vignette_color(0, 0, 0) gml_vignette_intensity(1) gml_vignette_radius(0.3) gml_vignette_softness(0.2) return "narrow"]] } }),
    pset("aim_blur", "Aim blur", "A stronger background blur when you aim. Needs the game's depth of field option on.", { { "Off", false }, { "On", true } }),
    { kind = "pfn_list", fn = "world_material", label = "World material", help = "The whole scene in one material, if it's already loaded. Left/Right picks, Enter sets it. Can crash. Save first.", sel = 1, options = { { "Flat grey", "ctg_flat_grey" }, { "Off", "off" } } },
    { kind = "pfn_list", fn = "mosaic", label = "Censor mosaic", help = "The game's pixel censor on bodies. Left/Right picks, Enter sets it.", sel = 1, options = { { "On", "true" }, { "Off", "false" } } },
    pset("no_autosave", "No autosave", "Autosaves stop.", { { "Off", false }, { "On", true } }),
    { kind = "pfn_list", fn = "load_zone", label = "Load hidden place", help = "Loads an off-map or cut area's files; you still have to get there. Left/Right picks, Enter loads it. Can crash. Save first.", sel = 1, options = { { "Idols camp", "idols_camp" }, { "Haunted hotel 1", "haunted_hotel_1" }, { "Haunted hotel 2", "cinco-haunted_hotel_2" }, { "Haunted hotel 3", "cinco-haunted_hotel_3" }, { "Haunted hotel 4", "cinco-haunted_hotel_4" }, { "Haunted hotel 5", "cinco-haunted_hotel_5" }, { "Marshall HQ interior", "mission_mh_exec_interior" }, { "Pals interior", "mission_ct_pals_interior" }, { "Hunt ground floor", "mission_ct_hunt_ground_floor" }, { "Airport interior", "dlc_lp02_ms_airport_interior" }, { "Lucky interior", "mission_dlc_lucky_ideal_interior" }, { "Queen's place", "dlc_lp02_ms_queen" }, { "Boot Hill", "dlc_boothill_01" }, { "Boot Hill city", "dlc_boothill_city_zones" }, { "Sunshine Springs", "dlc_exp_01_lucky" }, { "Sunshine Springs group", "dlc_01_lucky" }, { "Sunshine Springs gameplay", "dlc_lucky_gameplay" }, { "Sunshine Springs lighting", "dlc_dis01_lighting" }, { "Dustfaire", "dlc_exp_02_dusty" }, { "Dustfaire group", "dlc_02_dusty" }, { "Dustfaire gameplay", "dlc_dusty_02_gameplay" }, { "Dustfaire lighting", "dlc_dis02_lighting" }, { "Sunshine wingsuit 1", "dlc_lp01_ow_wing_01" }, { "Sunshine wingsuit 2", "dlc_lp01_ow_wing_02" }, { "Sunshine wingsuit 3", "dlc_lp01_ow_wing_03" }, { "Sunshine wingsuit 4", "dlc_lp01_ow_wing_04" }, { "Sunshine wingsuit 5", "dlc_lp01_ow_wing_05" }, { "Dustfaire wingsuit saboteur", "dlc_dis02_ow_wingsuit_saboteur_01" }, { "Riding Shotgun", "dlc_act_riding_shotgun_lucky_01" }, { "Caper mission", "dlc_lp01_ms_caper" }, { "Chris mission", "mission_dlc_lp01_ms_chris" }, { "Sunshine intro mission", "mission_dlc_lucky_intro" }, { "Carl mission", "dlc_lp02_ms_carl" }, { "Faire mission", "dlc_lp02_ms_faire" }, { "Hammer mission", "dlc_lp02_ms_hammer" }, { "Rod mission", "dlc_lp02_ms_rod" }, { "Wedding mission", "dlc_lp02_ms_wed" }, { "DLC 2 global", "dlc_02_global" }, { "Boot Hill global", "dlc_boothill_global" }, { "DLC placeholder 1", "dlc_placeholder_01" }, { "DLC placeholder 2", "dlc_placeholder_02" }, { "DLC placeholder 3", "dlc_placeholder_03" } } },
    { kind = "pfn_list", fn = "unload_zone", label = "Unload hidden place", help = "Unloads it again. Left/Right picks, Enter unloads it.", sel = 1, options = { { "Idols camp", "idols_camp" }, { "Haunted hotel 1", "haunted_hotel_1" }, { "Haunted hotel 2", "cinco-haunted_hotel_2" }, { "Haunted hotel 3", "cinco-haunted_hotel_3" }, { "Haunted hotel 4", "cinco-haunted_hotel_4" }, { "Haunted hotel 5", "cinco-haunted_hotel_5" }, { "Marshall HQ interior", "mission_mh_exec_interior" }, { "Pals interior", "mission_ct_pals_interior" }, { "Hunt ground floor", "mission_ct_hunt_ground_floor" }, { "Airport interior", "dlc_lp02_ms_airport_interior" }, { "Lucky interior", "mission_dlc_lucky_ideal_interior" }, { "Queen's place", "dlc_lp02_ms_queen" }, { "Boot Hill", "dlc_boothill_01" }, { "Boot Hill city", "dlc_boothill_city_zones" }, { "Sunshine Springs", "dlc_exp_01_lucky" }, { "Sunshine Springs group", "dlc_01_lucky" }, { "Sunshine Springs gameplay", "dlc_lucky_gameplay" }, { "Sunshine Springs lighting", "dlc_dis01_lighting" }, { "Dustfaire", "dlc_exp_02_dusty" }, { "Dustfaire group", "dlc_02_dusty" }, { "Dustfaire gameplay", "dlc_dusty_02_gameplay" }, { "Dustfaire lighting", "dlc_dis02_lighting" }, { "Sunshine wingsuit 1", "dlc_lp01_ow_wing_01" }, { "Sunshine wingsuit 2", "dlc_lp01_ow_wing_02" }, { "Sunshine wingsuit 3", "dlc_lp01_ow_wing_03" }, { "Sunshine wingsuit 4", "dlc_lp01_ow_wing_04" }, { "Sunshine wingsuit 5", "dlc_lp01_ow_wing_05" }, { "Dustfaire wingsuit saboteur", "dlc_dis02_ow_wingsuit_saboteur_01" }, { "Riding Shotgun", "dlc_act_riding_shotgun_lucky_01" }, { "Caper mission", "dlc_lp01_ms_caper" }, { "Chris mission", "mission_dlc_lp01_ms_chris" }, { "Sunshine intro mission", "mission_dlc_lucky_intro" }, { "Carl mission", "dlc_lp02_ms_carl" }, { "Faire mission", "dlc_lp02_ms_faire" }, { "Hammer mission", "dlc_lp02_ms_hammer" }, { "Rod mission", "dlc_lp02_ms_rod" }, { "Wedding mission", "dlc_lp02_ms_wed" }, { "DLC 2 global", "dlc_02_global" }, { "Boot Hill global", "dlc_boothill_global" }, { "DLC placeholder 1", "dlc_placeholder_01" }, { "DLC placeholder 2", "dlc_placeholder_02" }, { "DLC placeholder 3", "dlc_placeholder_03" } } },
    { kind = "venture_lot", label = "Venture lot", help = "The lot Build venture on lot uses. Left/Right picks.", sel = 1, options = { { "barrio_01", "barrio_01" }, { "barrio_02", "barrio_02" }, { "casino_01", "casino_01" }, { "commercial_01", "commercial_01" }, { "commercial_02", "commercial_02" }, { "financial_01", "financial_01" }, { "financial_02", "financial_02" }, { "industrial_01", "industrial_01" }, { "industrial_02", "industrial_02" }, { "mansion_hills_01", "mansion_hills_01" }, { "mercado_01", "mercado_01" }, { "mercado_02", "mercado_02" }, { "old_town_01", "old_town_01" }, { "old_town_02", "old_town_02" }, { "rodeo_01", "rodeo_01" }, { "rodeo_02", "rodeo_02" } } },
    { kind = "venture_build", class = "real_estate_blueprint", label = "Build venture on lot", help = "Builds any venture on Venture lot. Left/Right picks, Enter builds. Save first.", sel = 1, options = {} },
    { kind = "pfn_list", fn = "people_speed", label = "Speed of everyone near", help = "How fast everyone within 40 m moves. Left/Right picks, Enter sets it.", sel = 1, options = { { "x0.25", 0.25 }, { "x0.5", 0.5 }, { "Normal", 1.0 }, { "x2", 2.0 }, { "x4", 4.0 } } },
    { kind = "pfn_list", fn = "outline_near", label = "Outline everyone near", help = "Everyone within 40 m outlined as this. Left/Right picks, Enter does it. Only shows with Visual > HUD > High contrast on.", sel = 1, options = { { "Friend", 3 }, { "Enemy", 4 }, { "Neutral", 5 } } },
    { kind = "pfn_list", fn = "skin_near", label = "Skin effect near", help = "Puts a skin effect on everyone within 40 m. Left/Right picks, Enter puts it on.", sel = 1, options = { { "Burnt", "vfx_burnt" }, { "Kisses", "vfx_kisses" }, { "Snow", "vfx_snow" }, { "Wet look", "vfx_wet_look" }, { "Toxic glow", "vfx_toxic_glow" }, { "Electric", "vfx_electric_highlight" }, { "Hit flash", "vfx_hit_flash_01" }, { "Edge glow", "vfx_edge_highlight_01" }, { "Edge glow 2", "vfx_edge_highlight_02" }, { "Fist cannon glow", "vfx_fist_cannon_ult_glow" }, { "Combat outline", "vfx_object_outline_combat_01" }, { "Combat outline 2", "vfx_object_outline_combat_02" }, { "Skill active", "vfx_skill-perk_active" }, { "Hologram", "vfx_hologram_spawn" }, { "Hologram out", "vfx_hologram_die" }, { "Energy out", "vfx_energy_derez_out" }, { "Fire dissolve", "vfx_fire_dissolve" }, { "Portal dissolve", "vfx_portal_dissolve" }, { "Toxic dissolve", "vfx_toxic_dissolve" }, { "Tumbleweed dissolve", "vfx_tumbleweed_dissolve" }, { "Fabric rip", "vfx_fabric_rip_dissolve" }, { "Hologram disguise", "vfx_holo_disguise_fullcycle" }, { "Possessed", "possessed_ghost" }, { "Ghost dissolve", "ghost_dissolve" }, { "Face scan", "vfx_face-scan_01" }, { "Gold shimmer", "vfx_cash_hilight_gold" } , { "Build cust hover", "build_cust_hover" }, { "Build cust invalid", "build_cust_invalid" }, { "Build cust valid", "build_cust_valid" }, { "High contrast fill avatar", "high_contrast_fill-avatar" }, { "High contrast fill avatar skill perk activate", "high_contrast_fill-avatar_skill-perk_activate" }, { "High contrast fill avatar skill perk activate durable", "high_contrast_fill-avatar_skill-perk_activate_durable" }, { "High contrast fill avatar skill perk activate elite electric", "high_contrast_fill-avatar_skill-perk_activate_elite-electric" }, { "High contrast fill avatar skill perk activate elite skilled", "high_contrast_fill-avatar_skill-perk_activate_elite-skilled" }, { "High contrast fill avatar skill perk active", "high_contrast_fill-avatar_skill-perk_active" }, { "High contrast fill avatar skill perk active berserk", "high_contrast_fill-avatar_skill-perk_active_berserk" }, { "High contrast fill avatar skill perk active get tough", "high_contrast_fill-avatar_skill-perk_active_get-tough" }, { "High contrast fill avatar skill perk active quick escape", "high_contrast_fill-avatar_skill-perk_active_quick-escape" }, { "High contrast fill enemy", "high_contrast_fill-enemy" }, { "High contrast fill finisher", "high_contrast_fill-finisher" }, { "High contrast fill friend", "high_contrast_fill-friend" }, { "High contrast fill neutral", "high_contrast_fill-neutral" }, { "High contrast fill possessed ghost", "high_contrast_fill_possessed_ghost" }, { "High contrast outline avatar", "high_contrast_outline-avatar" }, { "High contrast outline avatar skill perk activate", "high_contrast_outline-avatar_skill-perk_activate" }, { "High contrast outline avatar skill perk activate durable", "high_contrast_outline-avatar_skill-perk_activate_durable" }, { "High contrast outline avatar skill perk activate elite electric", "high_contrast_outline-avatar_skill-perk_activate_elite-electric" }, { "High contrast outline avatar skill perk activate elite skilled", "high_contrast_outline-avatar_skill-perk_activate_elite-skilled" }, { "High contrast outline avatar skill perk active", "high_contrast_outline-avatar_skill-perk_active" }, { "High contrast outline avatar skill perk active berserk", "high_contrast_outline-avatar_skill-perk_active_berserk" }, { "High contrast outline avatar skill perk active get tough", "high_contrast_outline-avatar_skill-perk_active_get-tough" }, { "High contrast outline avatar skill perk active quick escape", "high_contrast_outline-avatar_skill-perk_active_quick-escape" }, { "High contrast outline enemy", "high_contrast_outline-enemy" }, { "High contrast outline finisher", "high_contrast_outline-finisher" }, { "High contrast outline friend", "high_contrast_outline-friend" }, { "High contrast outline neutral", "high_contrast_outline-neutral" }, { "High contrast possessed ghost", "high_contrast_possessed_ghost" }, { "Prop collect collectable", "prop collect - collectable" }, { "Prop collect collected", "prop collect - collected" }, { "Prop collect new", "prop collect - new" }, { "Prop collectible 01", "prop_collectible_01" }, { "Derez out hologram", "vfx_derez_out_hologram" }, { "Holo disguise off", "vfx_holo_disguise_off" }, { "Holo disguise on", "vfx_holo_disguise_on" }, { "Lmg barrel heat glow", "vfx_lmg_barrel_heat_glow" }, { "Map object outline 01", "vfx_map-object_outline_01" }, { "Object highlight 01", "vfx_object_highlight_01" }, { "Pickup highlight ammo", "vfx_pickup_highlight_ammo" }, { "Pickup highlight cash", "vfx_pickup_highlight_cash" }, { "Pickup highlight collectable", "vfx_pickup_highlight_collectable" }, { "Pickup highlight cuttingedge", "vfx_pickup_highlight_cuttingedge" }, { "Pickup highlight weapons", "vfx_pickup_highlight_weapons" }, { "Skill perk activate", "vfx_skill-perk_activate" }, { "Skill perk activate elite electrified", "vfx_skill-perk_activate_elite-electrified" }, { "Skill perk activate elite skilled", "vfx_skill-perk_activate_elite-skilled" }, { "Skill perk activate major durable", "vfx_skill-perk_activate_major-durable" }, { "Skill perk active berserk", "vfx_skill-perk_active_berserk" }, { "Skill perk active get tough", "vfx_skill-perk_active_get-tough" }, { "Skill perk active quick escape", "vfx_skill-perk_active_quick-escape" }, { "Test", "vfx_test" }, { "Test outline 2", "vfx_test_outline_2" }, { "Tether object highlight", "vfx_tether_object_highlight" }, { "Tumbleweed dissolve no glow", "vfx_tumbleweed_dissolve_no_glow" }} },
    { kind = "pfn_list", fn = "takedown_nearest", label = "Take down nearest", help = "Takes down the nearest person within 10 m. Left/Right picks a style, Enter does it.", sel = 1, options = { { "Normal", 0 }, { "Stealth", 1 }, { "Throw", 2 }, { "Jump", 3 }, { "Summon", 4 } } },
    { kind = "pfn_list", fn = "near_act", label = "Stunt for cars near", help = "Every car within 40 m tries it. Left/Right picks, Enter does it.", sel = 1, options = { { "J-turn", "jturn" }, { "Hairpin", "hairpin" }, { "Ram", "ram" }, { "Ramp mode", "ramp" } } },
    { kind = "pfn", fn = "delete_nearest_car", label = "Delete nearest car", help = "The nearest car within 30 m stops existing." },
    { kind = "near_act", key = "swarm", label = "Crowd around me", help = "Everyone within 40 m flocks to you." },
    { kind = "near_act", key = "unswarm", label = "Stop crowding", help = "Lets the crowd from Crowd around me go." },
    { kind = "near_act", key = "taunt", label = "Make everyone near target you", help = "Everyone within 40 m fixes on you." },
    { kind = "near_act", key = "untaunt", label = "Stop targeting me", help = "Lets them go after Make everyone near target you." },
    { kind = "near_act", key = "shoot", label = "Make everyone near shoot you", help = "Everyone armed within 40 m opens fire on you." },
    { kind = "near_act", key = "unshoot", label = "Stop shooting", help = "Everyone within 40 m holds fire." },
    { kind = "near_act", key = "pull_over", label = "Drivers near pull over", help = "Drivers within 40 m stop at the kerb." },
    { kind = "near_act", key = "weave", label = "Drivers near weave", help = "Drivers within 40 m leave their lane." },
    { kind = "near_act", key = "stay_in", label = "Drivers near stay in", help = "Drivers within 40 m won't get out." },
    { kind = "near_act", key = "no_pip", label = "Hide everyone near on minimap", help = "Everyone within 40 m loses their minimap mark." },
    { kind = "near_act", key = "pip", label = "Show everyone near on minimap", help = "Gives them their minimap mark back." },
    { kind = "near_act", key = "unoutline", label = "Clear outlines", help = "Clears outlines within 40 m." },
    { kind = "near_act", key = "reel", label = "Everyone near can be reeled", help = "Everyone within 40 m can be reeled. What that does in play isn't confirmed." },
    { kind = "near_act", key = "delete", label = "Delete everyone near", help = "Everyone within 40 m stops existing, mission characters too. Save first." },
    { kind = "near_act", key = "stall", label = "Stall engines near", help = "Every engine within 40 m cuts out." },
    { kind = "near_act", key = "unstall", label = "Engines back on", help = "Gives engines within 40 m back." },
    { kind = "near_act", key = "normal", label = "Cars near stop stunts", help = "Ends Stunt for cars near." },
    { kind = "near_act", key = "hazards", label = "Hazard lights near", help = "Cars within 40 m flash their hazards." },
    { kind = "near_act", key = "lock", label = "Lock cars near", help = "Nobody can get in cars within 40 m." },
    { kind = "near_act", key = "unlock", label = "Unlock cars near", help = "Unlocks cars within 40 m." },
    { kind = "near_act", key = "trunk", label = "Pop trunks near", help = "Trunks within 40 m open." },
    { kind = "near_act", key = "crush", label = "Crush cars near", help = "Cars within 40 m flatten as if run over." },
    { kind = "near_act", key = "tip", label = "Tip bikes near", help = "Anything on two wheels within 40 m tips over." },
    { kind = "near_act", key = "ghost", label = "Ghost through cars near", help = "You pass through cars within 40 m." },
    { kind = "near_act", key = "unghost", label = "Solid cars near", help = "Makes cars within 40 m solid again." },
    pset("sky_look", "Look", "A whole look in one press. Any sky row you've set yourself wins over it.", { { "Game's", false },
      { "No golden tint", { sky_col_sun = { 0.82, 0.9, 1.0 } } },
      { "Moody nights", { sky_col_sun = { 0.8, 0.84, 1.0 }, sky_exposure = 3.2, sky_ambient = 0.07 } },
      { "Neon nights", { sky_col_sun = { 0.9, 0.8, 1.0 }, sky_col_fog = { 0.88, 0.76, 1.0 }, sky_exposure = 3.2, sky_ambient = 0.07 } } }),
    pset("sky_fog", "Fog", "How thick the fog is.", { { "Game's", false }, { "Light", 100.0 }, { "Thick", 400.0 }, { "Wall", 1000.0 }, { "None", 0.0 } }),
    pset("sky_haze", "Haze", "How much distance blurs.", { { "Game's", false }, { "None", 0.0 }, { "Heavy", 0.7 }, { "Full", 1.0 } }),
    pset("sky_exposure", "Sky exposure", "How bright the camera wants the world. The game aims for 4.", { { "Game's", false }, { "Dim", 1.0 }, { "Low", 2.0 }, { "High", 10.0 }, { "Blinding", 40.0 } }),
    pset("sky_godrays", "Light shafts", "Shafts of light through the air.", { { "Game's", false }, { "Some", 0.5 }, { "Full", 1.0 } }),
    pset("sky_ambient", "Ambient light", "Flat fill light. The game uses 0.1.", { { "Game's", false }, { "None", 0.0 }, { "Some", 0.5 }, { "Bright", 2.0 } }),
    pset("sky_gi", "Bounced light", "Indirect light. The game uses 1.", { { "Game's", false }, { "None", 0.0 }, { "x3", 3.0 }, { "x10", 10.0 } }),
    pset("sky_sun", "Sun size", "How big the sun looks. The game uses 0.27 degrees.", { { "Game's", false }, { "Big", 2.0 }, { "Huge", 8.0 }, { "Fills the sky", 32.0 } }),
    pset("sky_moon", "Moon size", "How big the moon looks. The game uses 0.26 degrees.", { { "Game's", false }, { "Big", 2.0 }, { "Huge", 8.0 }, { "Fills the sky", 32.0 } }),
    pset("sky_stars", "Star brightness", "How bright the stars are at night. The game uses 5.", { { "Game's", false }, { "None", 0.0 }, { "Bright", 50.0 }, { "Very", 500.0 }, { "Blinding", 2048.0 } }),
    pset("sky_clouds", "Cloud cover", "All the cloud layers.", { { "Game's", false }, { "None", 0.0 }, { "Half", 0.5 }, { "Overcast", 1.0 } }),
    pset("sky_rain", "Rain amount", "The weather's rain setting. Whether rain follows it isn't known.", { { "Game's", false }, { "None", 0.0 }, { "Half", 0.5 }, { "Full", 1.0 } }),
    pset("sky_heat", "Heat haze", "Shimmer over everything.", { { "Game's", false }, { "Some", 0.5 }, { "Full", 1.0 } }),
    pset("sky_wind", "Wind speed", "How strong the wind is, in mph. The game uses 9.", { { "Game's", false }, { "Still", 0.0 }, { "50", 50.0 }, { "100", 100.0 }, { "200", 200.0 } }),
    pset("sky_spin", "Sun speed", "How fast the sun and moon cross the sky. Time of day itself carries on.", { { "Game's", false }, { "Stopped", 0.0 }, { "x60", 60.0 }, { "x600", 600.0 }, { "x5000", 5000.0 }, { "Backwards", -600.0 } }),
    pset("sky_grain", "Film grain", "Noise over the picture.", { { "Game's", false }, { "Some", 1.0 }, { "Heavy", 5.0 } }),
    pset("sky_vignette", "Dark screen edges", "Darkened edges from the lighting itself.", { { "Game's", false }, { "Some", 0.5 }, { "Full", 1.0 } }),
    pset("sky_col_sky", "Sky colour", "The whole sky gradient.", { { "Game's", false }, { "Red", { 5.0, 0.25, 0.25 } }, { "Orange", { 5.0, 2.0, 0.25 } }, { "Green", { 0.25, 5.0, 0.25 } }, { "Teal", { 0.25, 5.0, 5.0 } }, { "Blue", { 0.25, 0.5, 5.0 } }, { "Purple", { 3.0, 0.25, 5.0 } }, { "Pink", { 5.0, 1.0, 3.5 } }, { "Black", { 0.0, 0.0, 0.0 } } }),
    pset("sky_col_sun", "Sun colour", "The sun's tint.", { { "Game's", false }, { "Red", { 1.0, 0.05, 0.05 } }, { "Orange", { 1.0, 0.4, 0.05 } }, { "Green", { 0.05, 1.0, 0.05 } }, { "Teal", { 0.05, 1.0, 1.0 } }, { "Blue", { 0.05, 0.1, 1.0 } }, { "Purple", { 0.6, 0.05, 1.0 } }, { "Pink", { 1.0, 0.2, 0.7 } }, { "Black", { 0.0, 0.0, 0.0 } } }),
    pset("sky_col_moon", "Moon colour", "The moon's tint.", { { "Game's", false }, { "Red", { 1.0, 0.05, 0.05 } }, { "Orange", { 1.0, 0.4, 0.05 } }, { "Green", { 0.05, 1.0, 0.05 } }, { "Teal", { 0.05, 1.0, 1.0 } }, { "Blue", { 0.05, 0.1, 1.0 } }, { "Purple", { 0.6, 0.05, 1.0 } }, { "Pink", { 1.0, 0.2, 0.7 } }, { "Black", { 0.0, 0.0, 0.0 } } }),
    pset("sky_col_fog", "Fog colour", "The fog's tint. Pair with Fog.", { { "Game's", false }, { "Red", { 1.0, 0.05, 0.05 } }, { "Orange", { 1.0, 0.4, 0.05 } }, { "Green", { 0.05, 1.0, 0.05 } }, { "Teal", { 0.05, 1.0, 1.0 } }, { "Blue", { 0.05, 0.1, 1.0 } }, { "Purple", { 0.6, 0.05, 1.0 } }, { "Pink", { 1.0, 0.2, 0.7 } }, { "Black", { 0.0, 0.0, 0.0 } } }),
    pset("sky_col_stars", "Star colour", "The stars' tint at night.", { { "Game's", false }, { "Red", { 1.0, 0.05, 0.05 } }, { "Orange", { 1.0, 0.4, 0.05 } }, { "Green", { 0.05, 1.0, 0.05 } }, { "Teal", { 0.05, 1.0, 1.0 } }, { "Blue", { 0.05, 0.1, 1.0 } }, { "Purple", { 0.6, 0.05, 1.0 } }, { "Pink", { 1.0, 0.2, 0.7 } }, { "Black", { 0.0, 0.0, 0.0 } } }),
    pset("sun_height", "Sun position", "Holds the sun where you put it. The game may overrule it.", { { "Game's", false }, { "Low", 5.0 }, { "Halfway", 45.0 }, { "Overhead", 85.0 }, { "Below the horizon", -20.0 } }),
    gchoice("Lock exposure", "Stops the camera adjusting to bright and dark. Left/Right picks, Enter sets it.", { { "On", [[gml_engine_render_lock_exposure_value() return "locked"]] }, { "Off", [[gml_engine_render_unlock_exposure_value() return "free"]] } }),
    pset("lamps", "City lights on", "The city's light fixtures. The only name found for it, so it may do nothing.", { { "Off", false }, { "On", true } }),
    { kind = "sky_any", label = "Any sky setting", help = "Sets any of the game's sky settings to Sky amount. Left/Right picks, Enter sets it.", sel = 1, options = SKY_LIST },
    pset("sky_amount", "Sky amount", "How far along its range Any sky setting goes. Clear puts that one back.", { { "Half", false }, { "Lowest", 0.0 }, { "A quarter", 0.25 }, { "Three quarters", 0.75 }, { "Highest", 1.0 }, { "Clear", "clear" } }),
    { kind = "pfn", fn = "sky_clear_any", label = "Clear sky settings", help = "Every Any sky setting back to the game's." },
    pset("dof", "Depth of field", "Everything past 3 m blurs. The camera may overrule it.", { { "Off", false }, { "Some", 8.0 }, { "Strong", 1.0 } }),
    pset("shift_view", "Shift view", "The picture moves off centre.", { { "Off", false }, { "Left", { -0.3, 0.0 } }, { "Right", { 0.3, 0.0 } }, { "Up", { 0.0, 0.3 } }, { "Down", { 0.0, -0.3 } } }),
    { kind = "pfn_list", fn = "colour_filter", label = "Colour vision filter", help = "The game's colour blindness filters. Left/Right picks, Enter sets it. May be subtle.", sel = 1, options = { { "None", "none" }, { "Protanopia", "protanopia" }, { "Deuteranopia", "deuteranopia" }, { "Tritanopia", "tritanopia" } } },
    { kind = "pfn", fn = "explosion_here", label = "Explosion here", help = "An RPG explosion 8 m ahead of you. The first press loads it. Save first." },
    { kind = "pfn_list", fn = "gravity_near", label = "Gravity near", help = "Gravity for everyone and every car within 40 m. Left/Right picks, Enter sets it.", sel = 1, options = { { "Float up", -0.3 }, { "None", 0.0 }, { "x0.2", 0.2 }, { "Normal", 1.0 }, { "x3", 3.0 }, { "x10", 10.0 } } },
    { kind = "pfn_list", fn = "fake_noise", label = "Fake a noise", help = "Everyone around reacts as if they heard it. Left/Right picks, Enter does it.", sel = 1, options = { { "Car alarm", "car alarm" }, { "Far explosion", "explosion - far" }, { "Player death", "player death" }, { "Oh snap", "oh snap" }, { "Prank bees", "prank bees" } } },
    { kind = "pfn_list", fn = "homie_outfit", label = "Next homie outfit", help = "Puts a homie in their next outfit. Left/Right picks who, each Enter changes it. Stays in your save.", sel = 1, options = { { "Eli", "eli" }, { "Kevin", "kev" }, { "Nahualli", "nahualli" }, { "Neenah", "neenah" } } },
    pset("tire_smoke", "Always tire smoke", "Your vehicle smokes its tires as if doing this.", { { "Off", false }, { "Rolling", 2 }, { "Skidding", 3 }, { "Burning out", 4 } }),
    { kind = "pfn", fn = "launch_my_car", label = "Launch start", help = "Your vehicle launches to 40 m/s in a second." },
    { kind = "pfn", fn = "fall_through_near", label = "Drop everyone near through ground", help = "Everyone within 40 m falls through the world. No undo." },
    { kind = "pfn", fn = "drivers_bolt", label = "Drivers near flee", help = "Drivers within 40 m flee in their cars." },
    { kind = "pfn", fn = "pop_tires_near", label = "Pop tires near", help = "Every tire within 40 m pops." },
    { kind = "pfn", fn = "freeze_cars_near", label = "Freeze cars near", help = "Cars within 40 m stop dead where they are, in mid-air too." },
    { kind = "pfn", fn = "unfreeze_cars_near", label = "Unfreeze cars near", help = "Lets frozen cars go." },
    { kind = "pfn", fn = "launch_cars_near", label = "Launch cars near", help = "Every car within 40 m launches forward." },
    { kind = "pfn", fn = "stick_nearest", label = "Stick nearest car on me", help = "The nearest car within 15 m rides on you, if it can attach." },
    { kind = "pfn", fn = "unstick", label = "Unstick car", help = "Lets go of the car from Stick nearest car on me." },
    pset("audio_ctx_0", "Volume: Ambience", "How loud background sound is. Changes your audio setting while it's on.", { { "Game's", false }, { "Mute", "mute" }, { "25%", 0.25 }, { "50%", 0.5 }, { "Full", 1 } }),
    pset("audio_ctx_1", "Volume: Combat", "How loud fights are. Changes your audio setting while it's on.", { { "Game's", false }, { "Mute", "mute" }, { "25%", 0.25 }, { "50%", 0.5 }, { "Full", 1 } }),
    pset("audio_ctx_2", "Volume: Interface", "How loud menus and the HUD are. Changes your audio setting while it's on.", { { "Game's", false }, { "Mute", "mute" }, { "25%", 0.25 }, { "50%", 0.5 }, { "Full", 1 } }),
    pset("audio_ctx_3", "Volume: Vehicles", "How loud vehicles are. Changes your audio setting while it's on.", { { "Game's", false }, { "Mute", "mute" }, { "25%", 0.25 }, { "50%", 0.5 }, { "Full", 1 } }),
    pset("audio_ctx_4", "Volume: Radio", "How loud the radio is. Changes your audio setting while it's on.", { { "Game's", false }, { "Mute", "mute" }, { "25%", 0.25 }, { "50%", 0.5 }, { "Full", 1 } }),
    pset("audio_ctx_5", "Volume: Music in the world", "How loud music in the world is. Changes your audio setting while it's on.", { { "Game's", false }, { "Mute", "mute" }, { "25%", 0.25 }, { "50%", 0.5 }, { "Full", 1 } }),
    pset("audio_ctx_6", "Volume: Menu music", "How loud menu music is. Changes your audio setting while it's on.", { { "Game's", false }, { "Mute", "mute" }, { "25%", 0.25 }, { "50%", 0.5 }, { "Full", 1 } }),
    pset("audio_ctx_7", "Volume: Explosions", "How loud explosions are. Changes your audio setting while it's on.", { { "Game's", false }, { "Mute", "mute" }, { "25%", 0.25 }, { "50%", 0.5 }, { "Full", 1 } }),
    pset("audio_ctx_8", "Volume: Gore", "How loud gore is. Changes your audio setting while it's on.", { { "Game's", false }, { "Mute", "mute" }, { "25%", 0.25 }, { "50%", 0.5 }, { "Full", 1 } }),
    pset("audio_ctx_9", "Volume: Voices", "How loud voices are. Changes your audio setting while it's on.", { { "Game's", false }, { "Mute", "mute" }, { "25%", 0.25 }, { "50%", 0.5 }, { "Full", 1 } }),
    pset("audio_ctx_10", "Volume: Pedestrian voices", "How loud people on the street are. Changes your audio setting while it's on.", { { "Game's", false }, { "Mute", "mute" }, { "25%", 0.25 }, { "50%", 0.5 }, { "Full", 1 } }),
    { kind = "cloth_slot", label = "Clothing slot", help = "The slot the rows below use: hat, glasses, hair, shoes and so on. Left/Right picks.", sel = 1, options = CLOTH_SLOTS },
    { kind = "cloth_item", label = "Clothing item", help = "Any item for that slot, owned or not, hidden or cut too. Left/Right picks, Enter wears it. Stays in your save. Undo my look puts you back.", sel = 1, options = cloth_items(1) },
    { kind = "cloth_off", label = "Take off this slot", help = "Empties the slot picked on Clothing slot. Eyes, teeth and face parts may leave a gap." },
    { kind = "cloth_now", label = "What's on this slot", help = "Shows what's worn in the slot picked on Clothing slot." },
    { kind = "console_list", class = "char_cust_wearable_info", handler = 0x13DE6D0, what = "Wearing", label = "Wear any item", help = "Any of the game's 2,686 items, tattoos, makeup and tans too. Left/Right picks, Enter wears it.", sel = 1, options = {} },
    { kind = "look_colour", cloth = true, label = "Item colour", help = "Colours part of what's in Clothing slot. Left/Right picks, Enter colours it. Stays in your save.", sel = 1, options = { { "Red", { 220, 20, 20 } }, { "Orange", { 240, 120, 20 } }, { "Yellow", { 240, 220, 30 } }, { "Green", { 30, 190, 40 } }, { "Teal", { 20, 190, 190 } }, { "Blue", { 20, 60, 220 } }, { "Purple", { 130, 30, 200 } }, { "Pink", { 240, 90, 180 } }, { "White", { 245, 245, 245 } }, { "Grey", { 120, 120, 120 } }, { "Black", { 10, 10, 10 } }, { "Brown", { 90, 55, 30 } }, { "Blond", { 220, 190, 120 } }, { "Ginger", { 180, 80, 30 } } } },
    pset("colour_part", "Colour part", "Which colour of an item Item colour changes. Most items have up to three.", { { "First", false }, { "Second", "color_2" }, { "Third", "color_3" }, { "Glow", "glow_color_1" } }),
    { kind = "look_colour", slot = "hair", part = "color_1", label = "Hair colour", help = "Colours your hair. Left/Right picks, Enter colours it. Stays in your save.", sel = 1, options = { { "Red", { 220, 20, 20 } }, { "Orange", { 240, 120, 20 } }, { "Yellow", { 240, 220, 30 } }, { "Green", { 30, 190, 40 } }, { "Teal", { 20, 190, 190 } }, { "Blue", { 20, 60, 220 } }, { "Purple", { 130, 30, 200 } }, { "Pink", { 240, 90, 180 } }, { "White", { 245, 245, 245 } }, { "Grey", { 120, 120, 120 } }, { "Black", { 10, 10, 10 } }, { "Brown", { 90, 55, 30 } }, { "Blond", { 220, 190, 120 } }, { "Ginger", { 180, 80, 30 } } } },
    { kind = "look_colour", slot = "facial_hair", part = "hair_color", label = "Beard colour", help = "Colours your beard. Left/Right picks, Enter colours it. Stays in your save.", sel = 1, options = { { "Red", { 220, 20, 20 } }, { "Orange", { 240, 120, 20 } }, { "Yellow", { 240, 220, 30 } }, { "Green", { 30, 190, 40 } }, { "Teal", { 20, 190, 190 } }, { "Blue", { 20, 60, 220 } }, { "Purple", { 130, 30, 200 } }, { "Pink", { 240, 90, 180 } }, { "White", { 245, 245, 245 } }, { "Grey", { 120, 120, 120 } }, { "Black", { 10, 10, 10 } }, { "Brown", { 90, 55, 30 } }, { "Blond", { 220, 190, 120 } }, { "Ginger", { 180, 80, 30 } } } },
    { kind = "look_colour", slot = "eyes", part = "iris_outer", label = "Eye colour", help = "Colours your eyes. Left/Right picks, Enter colours them. Stays in your save.", sel = 1, options = { { "Red", { 220, 20, 20 } }, { "Orange", { 240, 120, 20 } }, { "Yellow", { 240, 220, 30 } }, { "Green", { 30, 190, 40 } }, { "Teal", { 20, 190, 190 } }, { "Blue", { 20, 60, 220 } }, { "Purple", { 130, 30, 200 } }, { "Pink", { 240, 90, 180 } }, { "White", { 245, 245, 245 } }, { "Grey", { 120, 120, 120 } }, { "Black", { 10, 10, 10 } }, { "Brown", { 90, 55, 30 } }, { "Blond", { 220, 190, 120 } }, { "Ginger", { 180, 80, 30 } } } },
    pset("skin_colour", "Skin colour", "Your whole skin in one colour. Normal skins only. Stays in your save while it's on. Off or Undo my look puts you back.", { { "Off", false }, { "Red", { 255, 0, 0 } }, { "Orange", { 255, 90, 0 } }, { "Yellow", { 255, 210, 0 } }, { "Green", { 0, 255, 40 } }, { "Cyan", { 0, 220, 255 } }, { "Blue", { 0, 40, 255 } }, { "Purple", { 130, 0, 255 } }, { "Pink", { 255, 0, 140 } }, { "White", { 255, 255, 255 } }, { "Black", { 0, 0, 0 } } }),
    { kind = "game_list", look = true, class = "char_cust_skin_shader_info", label = "Skin type", help = "Changes your skin. Left/Right picks, Enter puts it on. Stays in your save. Undo my look puts you back.", sel = 1, options = {}, code = [[gml_customization_set_shader(gml_get_local_player():get_component_by_type("gml_component_character_customization"), vlib_info_object:get_object("char_cust_skin_shader_info", "%s"))]] },
    { kind = "game_list", look = true, class = "ui_char_cust_skin_shader_value_set", label = "Skin set", help = "One of the game's skin looks. Left/Right picks, Enter puts it on. Stays in your save.", sel = 1, options = {}, code = [[gml_customization_apply_skin_shader_preset(gml_get_local_player():get_component_by_type("gml_component_character_customization"), vlib_info_object:get_object("ui_char_cust_skin_shader_value_set", "%s"))]] },
    { kind = "game_list", class = "gml_persona", label = "Any voice", help = "Speak with any of the 495 voices. Left/Right picks, Enter sets it. Silent if that voice isn't loaded.", sel = 1, options = {}, code = [[customization_set_override_avatar_persona(vlib_info_object:get_object("gml_persona", "%s"))]] },
    { kind = "play_as_pick", from = "person", label = "Play as picked person", help = "Only half works for now: see Play as last spawned. Spawns who's picked on Spawn person. Back to yourself returns. Don't save while you're them." },
    { kind = "play_as_pick", from = "special_person", label = "Play as picked special", help = "Only half works for now: see Play as last spawned. Uses who's picked on Special person. The coyote can't: it isn't built like a person." },
    { kind = "any_anim", label = "Any animation", help = "Plays any of over 1,000 animations, never-used ones marked. Left/Right picks, Enter plays it. Some only fit certain poses.", sel = 1, options = ANIM_LIST },
    pset("anim_mode", "Animation mode", "Loop it, play it once, or hold it as your whole body's pose, which may stick you in place.", { { "Loop", false }, { "Once", "once" }, { "Hold", "hold" } }),
    pset("anim_speed", "Animation speed", "How fast your animation plays, or Freeze to hold the frame. Works while it's playing.", { { "Normal", false }, { "Freeze", 0.0 }, { "x0.1", 0.1 }, { "x0.25", 0.25 }, { "x0.5", 0.5 }, { "x0.75", 0.75 }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    { kind = "pfn", fn = "stop_anim", label = "Stop animation", help = "Ends Any animation, its Hold mode, Move like and Idle animation." },
    { kind = "anim_near", label = "Everyone near plays it", help = "Everyone within 40 m plays what's picked on Any animation." },
    { kind = "pfn_list", fn = "move_like", label = "Move like", help = "Moves you with one of the game's pedestrian animations. Left/Right picks, Enter sets it. Stop animation ends it.", sel = 1, options = { { "Drunk", "ped_drunk" }, { "Fancy", "ped_fancy" }, { "Old", "ped_oldman" }, { "Pimp", "ped_pimp" }, { "Sad", "ped_sad" }, { "Angry", "ped_angry" }, { "Athletic", "ped_athletic" }, { "With coffee", "ped_coffee" }, { "On the phone", "ped_phone" }, { "Cowboy", "ped_cowboy" }, { "Homeless", "ped_homeless" }, { "Gut wound", "ped_wounded_gut" }, { "With a bag", "ped_bag" }, { "Back to yours", "off" } } },
    { kind = "pfn_list", class = "gml_gail_state_info", fn = "gail_state", label = "Force body state", help = "Puts your body in a state: stagger, wall run and so on. Left/Right picks, Enter forces it. Back on foot is the way out. Save first.", sel = 1, options = {} },
    { kind = "pfn", fn = "gail_foot", label = "Back on foot", help = "Asks your body to return to normal." },
    { kind = "pfn_list", fn = "cinematic", label = "Play cutscene", help = "Plays one of the game's cutscene timelines. Left/Right picks, Enter plays it. It can break missions and may need its scene loaded. Save first.", sel = 1, options = { { "Announce screenshot 01", "cin3d_announce_screenshot_01" }, { "Beep test", "cin3d_beep_test" }, { "Boothill binkcontainer", "cin3d_boothill_binkcontainer" }, { "Ct bond in", "cin3d_ct_bond_in" }, { "Ct bond mid 01 bink container", "cin3d_ct_bond_mid_01_bink_container" }, { "Ct bond out", "cin3d_ct_bond_out" }, { "Ct bond out pt1", "cin3d_ct_bond_out_pt1" }, { "Ct bond out pt2", "cin3d_ct_bond_out_pt2" }, { "Ct build in", "cin3d_ct_build_in" }, { "Ct city in", "cin3d_ct_city_in" }, { "Ct cold open", "cin3d_ct_cold_open" }, { "Ct cold open bink", "cin3d_ct_cold_open_bink" }, { "Ct cold open bink church", "cin3d_ct_cold_open_bink_church" }, { "Ct cold open bink container", "cin3d_ct_cold_open_bink_container" }, { "Ct cold open laughs", "cin3d_ct_cold_open_laughs" }, { "Ct cold open lineup", "cin3d_ct_cold_open_lineup" }, { "Ct cold open moneyfight", "cin3d_ct_cold_open_moneyfight" }, { "Ct cust", "cin3d_ct_cust" }, { "Ct dead in", "cin3d_ct_dead_in" }, { "Ct dead in pt1", "cin3d_ct_dead_in_pt1" }, { "Ct dead in pt2", "cin3d_ct_dead_in_pt2" }, { "Ct dead mid 01", "cin3d_ct_dead_mid_01" }, { "Ct dead mid 01 pt1", "cin3d_ct_dead_mid_01_pt1" }, { "Ct dead mid 01 pt2", "cin3d_ct_dead_mid_01_pt2" }, { "Ct dead out", "cin3d_ct_dead_out" }, { "Ct dead out nahualli", "cin3d_ct_dead_out_nahualli" }, { "Ct epilogue", "cin3d_ct_epilogue" }, { "Ct epilogue antonio bink", "cin3d_ct_epilogue_antonio_bink" }, { "Ct epilogue boardroom bink", "cin3d_ct_epilogue_boardroom_bink" }, { "Ct epilogue coyote bink", "cin3d_ct_epilogue_coyote_bink" }, { "Ct epilogue highway bink", "cin3d_ct_epilogue_highway_bink" }, { "Ct epilogue pt1", "cin3d_ct_epilogue_pt1" }, { "Ct epilogue pt2", "cin3d_ct_epilogue_pt2" }, { "Ct epilogue thunderpump bink", "cin3d_ct_epilogue_thunderpump_bink" }, { "Ct guard mid 01", "cin3d_ct_guard_mid_01" }, { "Ct guard out", "cin3d_ct_guard_out" }, { "Ct heist in", "cin3d_ct_heist_in" }, { "Ct heist mid 01", "cin3d_ct_heist_mid_01" }, { "Ct heist mid 02", "cin3d_ct_heist_mid_02" }, { "Ct heist mid 03", "cin3d_ct_heist_mid_03" }, { "Ct heist out", "cin3d_ct_heist_out" }, { "Ct hq in", "cin3d_ct_hq_in" }, { "Ct hq out", "cin3d_ct_hq_out" }, { "Ct hunt in", "cin3d_ct_hunt_in" }, { "Ct hunt mid 01", "cin3d_ct_hunt_mid_01" }, { "Ct hunt mid 02", "cin3d_ct_hunt_mid_02" }, { "Ct hunt out", "cin3d_ct_hunt_out" }, { "Ct icon mid 01 bink container", "cin3d_ct_icon_mid_01_bink_container" }, { "Ct icon mid 02 bink container", "cin3d_ct_icon_mid_02_bink_container" }, { "Ct icon out", "cin3d_ct_icon_out" }, { "Ct idols in", "cin3d_ct_idols_in" }, { "Ct idols mid 01 bink container", "cin3d_ct_idols_mid_01_bink_container" }, { "Ct idols out", "cin3d_ct_idols_out" }, { "Ct jail in", "cin3d_ct_jail_in" }, { "Ct jail in bink container", "cin3d_ct_jail_in_bink_container" }, { "Ct jail out", "cin3d_ct_jail_out" }, { "Ct marsh in apc", "cin3d_ct_marsh_in_apc" }, { "Ct marsh in atticus", "cin3d_ct_marsh_in_atticus" }, { "Ct marsh in celebrate", "cin3d_ct_marsh_in_celebrate" }, { "Ct marsh in savior", "cin3d_ct_marsh_in_savior" }, { "Ct marsh in training", "cin3d_ct_marsh_in_training" }, { "Ct marsh in training pt1", "cin3d_ct_marsh_in_training_pt1" }, { "Ct marsh in training pt2", "cin3d_ct_marsh_in_training_pt2" }, { "Ct marsh in training pt3", "cin3d_ct_marsh_in_training_pt3" }, { "Ct marsh mid 01", "cin3d_ct_marsh_mid_01" }, { "Ct marsh mid 01 02", "cin3d_ct_marsh_mid_01_02" }, { "Ct marsh mid 02", "cin3d_ct_marsh_mid_02" }, { "Ct marsh mid 03", "cin3d_ct_marsh_mid_03" }, { "Ct marsh mid 03 04", "cin3d_ct_marsh_mid_03_04" }, { "Ct marsh mid 04 pt1", "cin3d_ct_marsh_mid_04_pt1" }, { "Ct marsh mid 04 pt2", "cin3d_ct_marsh_mid_04_pt2" }, { "Ct marsh mid hang", "cin3d_ct_marsh_mid_hang" }, { "Ct marsh mid nah", "cin3d_ct_marsh_mid_nah" }, { "Ct marsh out", "cin3d_ct_marsh_out" }, { "Ct pals mid 01", "cin3d_ct_pals_mid_01" }, { "Ct pals mid 01 channel", "cin3d_ct_pals_mid_01_channel" }, { "Ct pals mid 01 couch", "cin3d_ct_pals_mid_01_couch" }, { "Ct pals mid 01 knives", "cin3d_ct_pals_mid_01_knives" }, { "Ct pals mid 01 party", "cin3d_ct_pals_mid_01_party" }, { "Ct pals mid 02", "cin3d_ct_pals_mid_02" }, { "Ct pals out", "cin3d_ct_pals_out" }, { "Ct road in", "cin3d_ct_road_in" }, { "Ct road mid 01", "cin3d_ct_road_mid_01" }, { "Ct road mid serge", "cin3d_ct_road_mid_serge" }, { "Ct road out", "cin3d_ct_road_out" }, { "Ct steal mid 01", "cin3d_ct_steal_mid_01" }, { "Ct steal out", "cin3d_ct_steal_out" }, { "Ct steal out lastshot", "cin3d_ct_steal_out_lastshot" }, { "Ct trap in", "cin3d_ct_trap_in" }, { "Ct trap in pt1", "cin3d_ct_trap_in_pt1" }, { "Ct trap in pt2", "cin3d_ct_trap_in_pt2" }, { "Ct trap out", "cin3d_ct_trap_out" }, { "Cto enforcer01", "cin3d_cto_enforcer01" }, { "Id potty in", "cin3d_id_potty_in" }, { "Id potty mid 01", "cin3d_id_potty_mid_01" }, { "Id potty mid 02", "cin3d_id_potty_mid_02" }, { "Mh exec in", "cin3d_mh_exec_in" }, { "Mh exec out", "cin3d_mh_exec_out" }, { "Mh pay out", "cin3d_mh_pay_out" }, { "Mh pay out pt2", "cin3d_mh_pay_out_pt2" }, { "Mh pay out pt3", "cin3d_mh_pay_out_pt3" }, { "Mh pay out pt4", "cin3d_mh_pay_out_pt4" }, { "Mh pay out qte", "cin3d_mh_pay_out_qte" }, { "Ms boothill docketchum explains bink container", "cin3d_ms_boothill_docketchum_explains_bink_container" }, { "Ms boothill docketchum intro consuela bink container", "cin3d_ms_boothill_docketchum_intro_consuela_bink_container" }, { "Ms boothill docketchum intro danielli bink container", "cin3d_ms_boothill_docketchum_intro_danielli_bink_container" }, { "Ms boothill docketchum intro hunter bink container", "cin3d_ms_boothill_docketchum_intro_hunter_bink_container" }, { "Ms boothill docketchum intro justice bink container", "cin3d_ms_boothill_docketchum_intro_justice_bink_container" }, { "Ms boothill sizzle bink container", "cin3d_ms_boothill_sizzle_bink_container" }, { "Ms caper in walk", "cin3d_ms_caper_in_walk" }, { "Ms caper out", "cin3d_ms_caper_out" }, { "Ms queen mid 01 bink container", "cin3d_ms_queen_mid_01_bink_container" }, { "Ms queen out", "cin3d_ms_queen_out" }, { "Ms stiff mid 01", "cin3d_ms_stiff_mid_01" }, { "Ms wed in battle", "cin3d_ms_wed_in_battle" }, { "Ms wed in ceremony", "cin3d_ms_wed_in_ceremony" }, { "Ms wed out", "cin3d_ms_wed_out" }, { "Pn break out", "cin3d_pn_break_out" }, { "Pn forge mid 01", "cin3d_pn_forge_mid_01" }, { "Pn forge out bink container", "cin3d_pn_forge_out_bink_container" }, { "Sm side bink container", "cin3d_sm_side_bink_container" }, { "Vs bar showdown", "cin3d_vs_bar_showdown" }, { "Vs potty01", "cin3d_vs_potty01" }, { "Wl siege in", "cin3d_wl_siege_in" }, { "Wl siege out", "cin3d_wl_siege_out" } } },
    pset("hover_fly", "Hover rise and lower", "On the Prototype RTP and other hover vehicles, hold B to rise and X to lower, as high as you like. It stays where you leave it.", { { "Off", false }, { "Slow", 6.0 }, { "Normal", 12.0 }, { "Fast", 24.0 } }),
    pset("hover_speed", "Hover top speed", "How fast hover vehicles go. The game's limit is about 45 m/s.", { { "Game's", false }, { "x2", 2.0 }, { "x4", 4.0 }, { "x8", 8.0 } }),
    pset("hover_height", "Hover height", "How high it rides without Hover rise and lower. The game's is 0.4 m; past 9 m it can't feel the ground.", { { "Game's", false }, { "1 m", 1.0 }, { "3 m", 3.0 }, { "9 m", 9.0 } }),
    pset("hover_jump", "Hover jump", "How high hover vehicles jump.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("hover_guns", "Hover guns", "Take this gun out on a hover vehicle and hold RT to fire where the camera looks. It uses ammo. There's no aiming pose.", { { "Off", false }, { "Pistol", 2 }, { "SMG", 3 }, { "Rifle", 4 }, { "Shotgun", 5 } }),
    pset("round_stick", "Rounds stick", "Special rounds stick to what they hit.", { { "Off", false }, { "On", true } }),
    pset("round_lob", "Rounds arc", "Special rounds are lobbed in an arc.", { { "Off", false }, { "On", true } }),
    pset("sig_key", "Signature effects on any gun", "The gun in your hands acts upgraded where the game checks. Most only show it if they have a signature of their own. Not saved.", { { "Off", false }, { "On", true } }),
    pset("aircraft_speed", "Aircraft speed", "How fast helicopters and VTOLs go, climbing too.", { { "Game's", false }, { "x2", 2.0 }, { "x4", 4.0 }, { "x8", 8.0 } }),
    pset("vtol_boost", "VTOL boost", "How strong a VTOL's jets are.", { { "Game's", false }, { "x2", 2.0 }, { "x4", 4.0 }, { "x8", 8.0 } }),
    pset("heli_agility", "Helicopter agility", "Sharper flying. May only reach ones spawned from now on.", { { "Game's", false }, { "x2", 2.0 }, { "x4", 4.0 }, { "x8", 8.0 } }),
    pset("boat_speed", "Boat speed", "How fast boats go.", { { "Game's", false }, { "x2", 2.0 }, { "x4", 4.0 }, { "x8", 8.0 } }),
    pset("tank_steer", "Tank steering", "Tank controls on your vehicle.", { { "Off", false }, { "On", true } }),
    pset("windshield", "Windshield launch", "A crash throws people through your vehicle's windshield. You too.", { { "Off", false }, { "On", true } }),
    { kind = "pfn_list", fn = "car_upgrade", label = "Vehicle upgrade", help = "Sets an upgrade on your vehicle at Upgrade level. Left/Right picks, Enter sets it. Level 0 takes it off.", sel = 1, options = { { "Nitro", "veh_upgrade_nitro" }, { "Top speed", "veh_upgrade_top_speed" }, { "Torque", "veh_upgrade_torque" }, { "Frame", "veh_upgrade_frame" }, { "Bumper", "veh_upgrade_bumper" }, { "Tires", "veh_upgrade_tires" }, { "Off-road kit", "veh_upgrade_offroad_kit" }, { "Ability", "veh_upgrade_ultimate_upgrade" }, { "Tow hook", "veh_upgrade_tether_equipped" } } },
    pset("upgrade_level", "Upgrade level", "The level Vehicle upgrade uses.", { { "1", false }, { "0 (off)", 0 }, { "2", 2 }, { "3", 3 }, { "5", 5 } }),
    { kind = "pfn_list", fn = "car_rims", label = "Rims", help = "Changes the rims on your vehicle. Left/Right picks, Enter puts them on.", sel = 1, options = { { "Rims 0", 0 }, { "Rims 1", 1 }, { "Rims 2", 2 }, { "Rims 3", 3 }, { "Rims 4", 4 }, { "Rims 5", 5 }, { "Rims 6", 6 }, { "Rims 7", 7 }, { "Rims 8", 8 }, { "Rims 9", 9 }, { "Rims 10", 10 }, { "Rims 11", 11 }, { "Rims 12", 12 }, { "Rims 13", 13 }, { "Rims 14", 14 }, { "Rims 15", 15 }, { "Rims 16", 16 }, { "Rims 17", 17 }, { "Rims 18", 18 }, { "Rims 19", 19 }, { "Rims 20", 20 }, { "Rims 21", 21 }, { "Rims 22", 22 }, { "Rims 23", 23 }, { "Rims 24", 24 }, { "Rims 25", 25 }, { "Rims 26", 26 }, { "Rims 27", 27 }, { "Rims 28", 28 }, { "Rims 29", 29 }, { "Rims 30", 30 } } },
    { kind = "pfn_list", fn = "car_tires", label = "Tires", help = "Changes the tires on your vehicle. Left/Right picks, Enter puts them on.", sel = 1, options = { { "Tires 0", 0 }, { "Tires 1", 1 }, { "Tires 2", 2 }, { "Tires 3", 3 }, { "Tires 4", 4 }, { "Tires 5", 5 }, { "Tires 6", 6 }, { "Tires 7", 7 }, { "Tires 8", 8 }, { "Tires 9", 9 }, { "Tires 10", 10 }, { "Tires 11", 11 }, { "Tires 12", 12 } } },
    { kind = "pfn_list", fn = "car_paint", label = "Any paint", help = "One of the game's paints, gold, meat and lava among them. Left/Right picks, Enter puts it on.", sel = 1, options = { { "Paint 0", 0 }, { "Paint 1", 1 }, { "Paint 2", 2 }, { "Paint 3", 3 }, { "Paint 4", 4 }, { "Paint 5", 5 }, { "Paint 6", 6 }, { "Paint 7", 7 }, { "Paint 8", 8 }, { "Paint 9", 9 }, { "Paint 10", 10 }, { "Paint 11", 11 }, { "Paint 12", 12 }, { "Paint 13", 13 }, { "Paint 14", 14 }, { "Paint 15", 15 }, { "Paint 16", 16 }, { "Paint 17", 17 }, { "Paint 18", 18 }, { "Paint 19", 19 }, { "Paint 20", 20 }, { "Paint 21", 21 }, { "Paint 22", 22 }, { "Paint 23", 23 }, { "Paint 24", 24 }, { "Paint 25", 25 }, { "Paint 26", 26 }, { "Paint 27", 27 }, { "Paint 28", 28 }, { "Paint 29", 29 }, { "Paint 30", 30 }, { "Paint 31", 31 }, { "Paint 32", 32 }, { "Paint 33", 33 }, { "Paint 34", 34 }, { "Paint 35", 35 }, { "Paint 36", 36 }, { "Paint 37", 37 }, { "Paint 38", 38 }, { "Paint 39", 39 }, { "Paint 40", 40 }, { "Paint 41", 41 }, { "Paint 42", 42 }, { "Paint 43", 43 }, { "Paint 44", 44 }, { "Paint 45", 45 }, { "Paint 46", 46 }, { "Paint 47", 47 }, { "Paint 48", 48 }, { "Paint 49", 49 }, { "Paint 50", 50 }, { "Paint 51", 51 }, { "Paint 52", 52 }, { "Paint 53", 53 }, { "Paint 54", 54 }, { "Paint 55", 55 }, { "Paint 56", 56 }, { "Paint 57", 57 }, { "Paint 58", 58 }, { "Paint 59", 59 }, { "Paint 60", 60 }, { "Paint 61", 61 }, { "Paint 62", 62 }, { "Paint 63", 63 }, { "Paint 64", 64 }, { "Paint 65", 65 }, { "Paint 66", 66 }, { "Paint 67", 67 }, { "Paint 68", 68 }, { "Paint 69", 69 }, { "Paint 70", 70 }, { "Paint 71", 71 }, { "Paint 72", 72 }, { "Paint 73", 73 }, { "Paint 74", 74 } } },
    { kind = "pfn_list", fn = "car_glow", label = "Underglow colour", help = "Any colour under your vehicle. Left/Right picks, Enter sets it. Pair with Underglow brightness.", sel = 1, options = { { "Red", { 255, 20, 20 } }, { "Orange", { 255, 120, 0 } }, { "Yellow", { 255, 230, 20 } }, { "Green", { 20, 255, 40 } }, { "Teal", { 20, 240, 240 } }, { "Blue", { 20, 60, 255 } }, { "Purple", { 150, 30, 255 } }, { "Pink", { 255, 80, 190 } }, { "White", { 255, 255, 255 } } } },
    { kind = "pfn_list", fn = "car_glow_power", label = "Underglow brightness", help = "How bright the underglow is. Left/Right picks, Enter sets it.", sel = 1, options = { { "Off", 0 }, { "Some", 0.5 }, { "Full", 1 }, { "Blinding", 5 } } },
    { kind = "pfn", fn = "car_offroad", label = "Off-road kit anywhere", help = "The off-road kit, on cars that normally can't have it." },
    { kind = "ability_act", how = "fire", label = "Fire that ability", help = "Triggers what's picked on Vehicle ability without its button." },
    { kind = "ability_act", how = "stop", label = "Stop that ability", help = "Ends what's picked on Vehicle ability." },
    { kind = "ability_act", how = "remove", label = "Remove that ability", help = "Takes what's picked on Vehicle ability off your vehicle." },
    { kind = "pfn", fn = "drop_tow", label = "Drop tow hook", help = "Lets go of what you're towing." },
    { kind = "pfn", fn = "make_towable", label = "Make nearest car towable", help = "The nearest car within 30 m can be hooked, even one that normally refuses." },
    pset("car_crab", "Crab steering strength", "How far crab steering goes.", { { "Game's", false }, { "x2", 2.0 }, { "x4", 4.0 }, { "x8", 8.0 } }),
    pset("car_air", "Air control strength", "How much Super air control turns you.", { { "Game's", false }, { "x2", 2.0 }, { "x4", 4.0 }, { "x8", 8.0 } }),
    pset("car_honk", "Honk blast strength", "How hard Honk blast throws things.", { { "Game's", false }, { "x2", 2.0 }, { "x4", 4.0 }, { "x8", 8.0 } }),
    pset("car_bowel", "Bowelrod launch", "How hard the Bowelrod throws people out.", { { "Game's", false }, { "x2", 2.0 }, { "x4", 4.0 }, { "x8", 8.0 } }),
    { kind = "engine_sys", label = "Data system", help = "Step 1 of changing a value in the game's data: pick a system with Left/Right, then go down the rows.", sel = 1, options = ENGINE_SYSTEMS },
    { kind = "engine_class", label = "Data group", help = "The groups in that system. Left/Right picks.", sel = 1, options = engine_classes(1) },
    { kind = "engine_rec", label = "Data entry", help = "Which entry of that group. Enter loads the list, then Left/Right picks.", sel = 1, options = {} },
    { kind = "engine_field", label = "Data value", help = "Which value: numbers, then on/off, then lists. Left/Right picks, Enter shows what it is now.", sel = 1, options = engine_fields(engine_classes(1)[1][3]) },
    { kind = "engine_item", label = "Data list item", help = "For a value in a list: all of its items, or one. Left/Right picks, Enter shows that item's value.", sel = 1, options = { { "Not a list", false } } },
    pset("engine_amount", "Data change", "How to change it. x multiplies the game's value. On an on/off value any x flips it; Set to 0 is off, Set to 1 is on.", { { "x2", false }, { "x0.1", { "mul", 0.1 } }, { "x0.5", { "mul", 0.5 } }, { "x5", { "mul", 5 } }, { "x10", { "mul", 10 } }, { "x100", { "mul", 100 } }, { "Set to 0", { "set", 0 } }, { "Set to 1", { "set", 1 } }, { "Back to the game's", { "back" } } }),
    { kind = "engine_apply", all = false, label = "Change this entry", help = "Applies Data change to that value of that entry. May do nothing: some are only read at load. Lasts until you quit. Save first." },
    { kind = "engine_apply", all = true, label = "Change all entries", help = "The same on every entry of the group. May do nothing. Lasts until you quit. Save first." },
    { kind = "pfn", fn = "engine_undo_all", label = "Undo all data changes", help = "Every value changed here, back to the game's." },
    pset("gun_car", "Car damage", "How much the gun in your hands hurts vehicles.", { { "Game's", false }, { "x0.5", 0.5 }, { "x3", 3.0 }, { "x6", 6.0 }, { "x12", 12.0 } }),
    pset("gun_people", "People damage", "A separate scale against people, on the gun in your hands.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("gun_shield", "Shield damage", "How much the gun in your hands hurts tough shields.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("gun_pellets", "Pellets", "How many pellets a shotgun fires, or rounds in a burst. Lots can slow the game.", { { "Game's", false }, { "4", 4 }, { "12", 12 }, { "24", 24 }, { "48", 48 } }),
    pset("gun_spread", "Spread", "How wide shots go. For none at all, use Perfect aim.", { { "Game's", false }, { "x0.25", 0.25 }, { "x0.5", 0.5 }, { "x2", 2.0 }, { "x4", 4.0 }, { "x8", 8.0 } }),
    pset("gun_hip", "Accurate hip fire", "No accuracy penalty from the hip.", { { "Off", false }, { "On", true } }),
    pset("gun_recover", "Recoil recovery", "How fast the gun settles.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("gun_stagger", "Stagger on hit", "How hard each hit staggers people.", { { "Game's", false }, { "Light", 5.0 }, { "Heavy", 20.0 }, { "Massive", 50.0 } }),
    pset("gun_ragdoll", "Bodies fly on kill", "How far bodies fly when this gun kills.", { { "Game's", false }, { "Far", 100.0 }, { "Very far", 300.0 }, { "Into orbit", 500.0 } }),
    pset("gun_dmgtype", "Damage type", "What this gun's hits count as. The effects aren't confirmed; Heal may do nothing.", { { "Game's", false }, { "Instant kill", 0xDC2D1A57 }, { "Electric", 0x64382DD1 }, { "Water", 0x3D11E3C7 }, { "No flinch", 0xD966281B }, { "Heal", 0x886CA1B2 }, { "Fire", 0x799AD6D3 }, { "Burn over time", 0x7A355353 }, { "Poison over time", 0xEEE754A1 }, { "Bleed over time", 0xB6E85B66 }, { "Explosive", 0x9B4C0522 }, { "Haunted", 0x9097CBDD }, { "Foam", 0x75E983E4 }, { "Heavy melee", 0x8B67A9CB } }),
    pset("gun_impact", "Hit visuals", "What hits look like.", { { "Game's", false }, { "Fist cannon", 0x2A12F13F }, { "Potato launcher", 0xFF73E1CB }, { "Berserk", 0x0188E89C }, { "Overwatch", 0x5B34077E }, { "Flaming punch", 0xA0F36031 }, { "Star launcher", 0xADBF1954 }, { "Minigun", 0x1DD7C14A }, { "Heli gun", 0xBD9F7781 }, { "Marshall turret", 0x62025BD4 }, { "VTOL beam", 0x83FEFF42 }, { "Elephant", 0xEB845045 }, { "Focus", 0xA335EDC6 }, { "Retrowave", 0xD43CA574 }, { "Cowboy", 0xAC355B12 }, { "Boss SMG", 0xECE6161C }, { "Tactical SMG", 0xE5F04030 }, { "Idols SMG", 0x5831F89C }, { "Sword", 0x0100C1D9 }, { "Toy hammer", 0xDA3C22E2 }, { "Twinkle bat", 0x8268E4BA }, { "Pinata stick", 0xA00A2DA5 }, { "Claws", 0xE5813A82 }, { "Haunted rifle", 0x6DCF003C }, { "Ban hammer", 0x56D4347B }, { "Ban hammer swing", 0x399D69D8 }, { "Dead mace", 0x6B5AC3CB }, { "LMG", 0x4248D355 }, { "Pistol shotgun", 0x1B59513E }, { "Marksman", 0xA4AD72CF }, { "Paintball", 0x61F8CAB0 }, { "Paintball turret", 0x145981DC }, { "Frost axe", 0x936827F8 } }),
    pset("gun_fuse", "Explosive fuse", "Seconds before thrown things and rounds go off.", { { "Game's", false }, { "Instant", 0.0 }, { "5 s", 5.0 }, { "30 s", 30.0 } }),
    pset("gun_wide", "Melee swing width", "Melee arcs reach further around you.", { { "Off", false }, { "x2", 2.0 }, { "x5", 5.0 } }),
    pset("gun_tracer", "Tracer", "What the shots of the gun in your hands look like. Not with Special rounds.", { { "Game's", false }, { "haunted-rifle tracer 02", [[data\dlc_02\spawnables\vfx\prefabs\vfx_haunted-rifle_tracer_02]] }, { "lmg tracer 01", [[data\dlc_boothill\spawnables\vfx\prefabs\vfx-particle_lmg_tracer_01]] }, { "marksman-rifle tracer 01", [[data\dlc_boothill\spawnables\vfx\prefabs\vfx-particle_marksman-rifle_tracer_01]] }, { "dlc boothill pistol shotgun tracer", [[data\dlc_boothill\spawnables\vfx\prefabs\vfx_dlc_boothill_pistol_shotgun_tracer]] }, { "frostlander paintball tracer", [[data\dlc_exp_02_dusty\spawnables\vfx\prefabs\vfx_frostlander_paintball_tracer]] }, { "frostlander paintball tracer turret", [[data\dlc_exp_02_dusty\spawnables\vfx\prefabs\vfx_frostlander_paintball_tracer_turret]] }, { "smg frostlander tracer cinematic", [[data\dlc_exp_02_dusty\spawnables\vfx\prefabs\vfx_smg_frostlander_tracer_cinematic]] }, { "base-sniper tracer 01", [[data\sr_city\spawnables\vfx\prefabs\vfx-particle_base-sniper_tracer_01]] }, { "beercan-launcher tracer 01", [[data\sr_city\spawnables\vfx\prefabs\vfx-particle_beercan-launcher_tracer_01]] }, { "cowboy shotgun tracer 01a", [[data\sr_city\spawnables\vfx\prefabs\vfx-particle_cowboy_shotgun_tracer_01a]] }, { "elephant-rifle tracer 01a", [[data\sr_city\spawnables\vfx\prefabs\vfx-particle_elephant-rifle_tracer_01a]] }, { "focus rifle tracer 01a", [[data\sr_city\spawnables\vfx\prefabs\vfx-particle_focus_rifle_tracer_01a]] }, { "god blaster tracer", [[data\sr_city\spawnables\vfx\prefabs\vfx-particle_god_blaster_tracer]] }, { "heavy-smg tracer 01", [[data\sr_city\spawnables\vfx\prefabs\vfx-particle_heavy-smg_tracer_01]] }, { "high-volume smg tracer 01a", [[data\sr_city\spawnables\vfx\prefabs\vfx-particle_high-volume_smg_tracer_01a]] }, { "lawgiver tracer 01", [[data\sr_city\spawnables\vfx\prefabs\vfx-particle_lawgiver_tracer_01]] }, { "potato launcher tracer 01", [[data\sr_city\spawnables\vfx\prefabs\vfx-particle_potato_launcher_tracer_01]] }, { "retrowave-sniper tracer 01", [[data\sr_city\spawnables\vfx\prefabs\vfx-particle_retrowave-sniper_tracer_01]] }, { "idols-pistol-tracer 01", [[data\sr_city\spawnables\vfx\prefabs\vfx-weapon_idols-pistol-tracer_01]] }, { "idols-pistol-tracer cinematic ct pals mid 02", [[data\sr_city\spawnables\vfx\prefabs\vfx-weapon_idols-pistol-tracer_cinematic_ct_pals_mid_02]] }, { "pistol tracer invisible", [[data\sr_city\spawnables\vfx\prefabs\vfx-weapon_pistol_tracer_invisible]] }, { "wastelander crossbow tracer postlaunch", [[data\sr_city\spawnables\vfx\prefabs\vfx-weapon_wastelander_crossbow_tracer_postlaunch]] }, { "wastelander pistol tracer city city 03", [[data\sr_city\spawnables\vfx\prefabs\vfx-weapon_wastelander_pistol_tracer_city_city_03]] }, { "idols-smg-tracer 01", [[data\sr_city\spawnables\vfx\vfx-weapon_idols-smg-tracer_01]] }, { "panteros-sawed-shotgun-tracer 01", [[data\sr_city\spawnables\vfx\vfx-weapon_panteros-sawed-shotgun-tracer_01]] }, { "police-shotgun-basic-tracer 01", [[data\sr_city\spawnables\vfx\vfx-weapon_police-shotgun-basic-tracer_01]] }, { "recycled-smg tracer 01a", [[data\sr_city\spawnables\vfx\vfx-weapon_recycled-smg_tracer_01a]] }, { "shotgun wastelander tracer 01", [[data\sr_city\spawnables\vfx\vfx-weapon_shotgun_wastelander_tracer_01]] }, { "smg-idols-miniboss tracer 01a", [[data\sr_city\spawnables\vfx\vfx-weapon_smg-idols-miniboss_tracer_01a]] }, { "weapon firework-cannon-tracer 01a", [[data\sr_city\spawnables\vfx\vfx_weapon_firework-cannon-tracer_01a]] }, { "assault-rifle tracer 01a", [[data\sr_vanguard\spawnables\vfx\prefabs\vfx-particle_assault-rifle_tracer_01a]] }, { "marshall-rifle-burst ultimate tracer 01a", [[data\sr_vanguard\spawnables\vfx\prefabs\vfx-particle_marshall-rifle-burst_ultimate_tracer_01a]] }, { "marshall-six-shooter tracer 01a", [[data\sr_vanguard\spawnables\vfx\prefabs\vfx-particle_marshall-six-shooter_tracer_01a]] }, { "marshall minigun tracer 01", [[data\sr_vanguard\spawnables\vfx\prefabs\vfx_marshall_minigun_tracer_01]] }, { "marshall-generic-burst-tracer 01", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_marshall-generic-burst-tracer_01]] }, { "marshall-rifle-burst-tracer 01", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_marshall-rifle-burst-tracer_01]] }, { "marshall carbine-tracer 01", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_marshall_carbine-tracer_01]] }, { "marshall charged-shotgun-tracer 01", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_marshall_charged-shotgun-tracer_01]] }, { "marshall overwatch tracer 01", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_marshall_overwatch_tracer_01]] }, { "marshall pistol-tracer 01", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_marshall_pistol-tracer_01]] }, { "marshall turret tracer apc", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_marshall_turret_tracer_apc]] }, { "marshall turret tracer tank 02", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_marshall_turret_tracer_tank_02]] }, { "marshall turret tracer train", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_marshall_turret_tracer_train]] }, { "nahualli overwatch tracer 01", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_nahualli_overwatch_tracer_01]] }, { "nonfaction tracer 02", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_nonfaction_tracer_02]] }, { "nonfaction tracer heli", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_nonfaction_tracer_heli]] }, { "panteros-pistol-handcannon-tracer 01", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_panteros-pistol-handcannon-tracer_01]] }, { "panteros shotgun tracer cinematic", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_panteros_shotgun_tracer_cinematic]] }, { "panteros tracer 02", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_panteros_tracer_02]] }, { "player overwatch tracer 01", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_player_overwatch_tracer_01]] }, { "police-pistol-basic-tracer 01", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_police-pistol-basic-tracer_01]] }, { "shotgun-tac-semi-auto tracer 01", [[data\sr_vanguard\spawnables\vfx\vfx-weapon_shotgun-tac-semi-auto_tracer_01]] }, { "tracer parent", [[data\sr_vanguard\spawnables\weapons\shots\tracer_parent]] }, { "smg tactical tracer", [[data\sr_vanguard\spawnables\weapons\shots\vfx_smg_tactical_tracer]] } }),
    pset("gun_muzzle", "Muzzle flash", "Any flash on the gun in your hands.", swap_options(EXTRAS.muzzle)),
    pset("gun_casing", "Shell casing", "What the gun in your hands ejects.", swap_options(EXTRAS.shell)),
    pset("gun_shake", "Firing shake", "How the camera kicks when you fire.", swap_options(EXTRAS.shake)),
    pset("double_jump", "Double jump", "Extra jumps in the air: press A or Space again.", { { "Off", false }, { "One more", 1 }, { "Three more", 3 }, { "Ten more", 10 } }),
    pset("jetpack", "Jetpack", "Hold A or Space in the air to climb.", { { "Off", false }, { "Gentle", 4.0 }, { "Strong", 8.0 }, { "Rocket", 20.0 } }),
    pset("air_dash", "Air dash", "Press X or Shift in the air to shoot where the camera looks.", { { "Off", false }, { "Quick", 15.0 }, { "Far", 30.0 }, { "Very far", 60.0 } }),
    pset("ice_floor", "Ice floor", "You slide around on foot.", { { "Off", false }, { "Slippery", 0.1 }, { "Ice", 0.02 } }),
    pset("air_drift", "Air momentum", "Less turning in the air: you keep going the way you were.", { { "Off", false }, { "Some", 50.0 }, { "Lots", 10.0 } }),
    { kind = "pfn_list", fn = "stay_ragdoll", label = "Go limp", help = "You go limp and stay that way until you pick Get back up. Left/Right picks, Enter does it.", sel = 1, options = { { "Go limp", 1 }, { "Get back up", 0 } } },
    { kind = "pfn_list", fn = "scale_me", label = "Your size", help = "Makes you bigger or smaller, collision too. Animations and doors won't fit. Left/Right picks, Enter sets it. Normal puts you back.", sel = 1, options = { { "x0.25", 0.25 }, { "x0.5", 0.5 }, { "x0.75", 0.75 }, { "Normal", 1 }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 } } },
    { kind = "pfn_list", fn = "scale_car", label = "Vehicle size", help = "Giant or tiny, collision too. The wheels stay their size. Left/Right picks, Enter sets it. Start small.", sel = 1, options = { { "x0.25", 0.25 }, { "x0.5", 0.5 }, { "x0.75", 0.75 }, { "Normal", 1 }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 } } },
    { kind = "pfn_list", fn = "scale_near", label = "Size of everything near", help = "Every person and car within 40 m. Left/Right picks, Enter sets it.", sel = 1, options = { { "x0.25", 0.25 }, { "x0.5", 0.5 }, { "x0.75", 0.75 }, { "Normal", 1 }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 } } },
    { kind = "look_num", cloth = true, part = "glossiness", label = "Item gloss", help = "How shiny what's in Clothing slot is. Left/Right picks, Enter sets it. Stays in your save.", sel = 1, options = { { "None", 0 }, { "Some", 0.5 }, { "Full", 1 }, { "Double", 2 }, { "Way past", 5 } } },
    { kind = "look_num", slot = "eyes", part = "iris_glow_intensity", label = "Eye glow", help = "Glowing eyes, past the game's limit, on eyes that have it. Left/Right picks, Enter sets it. Stays in your save.", sel = 1, options = { { "None", 0 }, { "Some", 0.5 }, { "Full", 1 }, { "Double", 2 }, { "Way past", 5 } } },
    { kind = "stack_item", label = "Stack that item", help = "Wears what's on Clothing item in Stack on slot, even if it doesn't belong: two hats, a suit over a suit. Stays in your save." },
    { kind = "stack_slot", label = "Stack on slot", help = "The slot Stack that item puts it in. Left/Right picks.", sel = 1, options = CLOTH_SLOTS },
    pset("front_grip", "Front grip", "How the front tires hold. Low means it won't turn in.", { { "Game's", false }, { "x0.25", 0.25 }, { "x0.5", 0.5 }, { "x2", 2.0 }, { "x4", 4.0 }, { "x8", 8.0 } }),
    pset("rear_grip", "Rear grip", "How the rear tires hold. Low means it drifts.", { { "Game's", false }, { "x0.25", 0.25 }, { "x0.5", 0.5 }, { "x2", 2.0 }, { "x4", 4.0 }, { "x8", 8.0 } }),
    pset("drift", "Drift angle", "How far your vehicle slides.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("burnout", "Burnout", "Longer, spinnier burnouts.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("bike_lean", "Bike lean", "How deep bikes lean.", { { "Game's", false }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 } }),
    pset("boost_tank", "Boost tank", "How much boost your vehicle holds.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("boost_refill", "Boost refill", "How fast boost comes back.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("boost_punch", "Boost power", "How hard boost pushes.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("launch_power", "Launch strength", "How hard a launch start pushes.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("heli_lift", "Helicopter lift", "Snappier climbs.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("water_float", "Floats on water", "How high anything rides in water.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("never_sink", "Never sink", "Your vehicle survives deep water.", { { "Off", false }, { "On", true } }),
    pset("engine_fire", "Engine catches fire", "When your vehicle's engine catches fire.", { { "Game's", false }, { "Never", -1.0 }, { "First hit", 1.0 } }),
    pset("stay_on_bike", "Stay on bike", "No bail-outs. On a car it may eject you.", { { "Off", false }, { "On", true } }),
    pset("auto_flip", "Auto-flip", "When your vehicle rights itself.", { { "Game's", false }, { "Never", 1 }, { "Always", 2 }, { "On its side", 3 } }),
    pset("ice_body", "Slippery body", "Your vehicle slides off walls and things.", { { "Off", false }, { "On", true } }),
    pset("car_crash", "Crash force", "How hard walls hit cars, boats, helicopters and jets, other people's too.", { { "Game's", false }, { "x0.25", 0.25 }, { "x0.5", 0.5 }, { "x2", 2.0 }, { "x4", 4.0 }, { "x8", 8.0 } }),
    pset("car_burn", "Fire burn speed", "How fast burning vehicles take damage.", { { "Game's", false }, { "x0.25", 0.25 }, { "x0.5", 0.5 }, { "x2", 2.0 }, { "x4", 4.0 }, { "x8", 8.0 } }),
    pset("traffic_gap", "Traffic spacing", "How far apart cars keep. The game's are 25 to 50.", { { "Game's", false }, { "Close", 8.0 }, { "Sparse", 150.0 } }),
    gchoice("Car camera distance", "A long chase camera. Left/Right picks, Enter sets it.", { { "Normal", [[player_camera_set_param("CP Normal Combat DTT", 6) return "normal"]] }, { "Far", [[player_camera_set_param("CP Normal Combat DTT", 20) return "far"]] }, { "Very far", [[player_camera_set_param("CP Normal Combat DTT", 60) return "very far"]] } }),
    pset("cam_through", "Camera through walls", "The camera doesn't pull in for walls.", { { "Off", false }, { "On", true } }),
    pset("moon", "Moon mode", "Everything at a sixth of gravity, you too.", { { "Off", false }, { "On", true } }),
    pset("airstrike", "Airstrike", "Blasts land around you. Turn on God mode first. It costs frames.", { { "Off", false }, { "Now and then", 90 }, { "Heavy", 30 }, { "Carpet", 10 } }),
    { kind = "pfn", fn = "blast_waypoint", label = "Explosion at waypoint", help = "An explosion at your map waypoint. The first press loads it." },
    { kind = "pfn_list", fn = "goal_near", label = "Give everyone near a behaviour", help = "Everyone within 40 m acts that way, as far as their animations let them. Left/Right picks, Enter gives it.", sel = 1, options = GOAL_LIST },
    { kind = "pfn_list", fn = "hunted_near", label = "Everyone near hunts you", help = "How everyone within 40 m tracks you. Left/Right picks, Enter sets it. Press again for people who arrive later.", sel = 1, options = { { "Always find me", 4 }, { "On sight", 1 }, { "Back to normal", 0 } } },
    { kind = "pfn_list", fn = "district_crowd", label = "Any district's crowd", help = "This place fills with another district's people and cars until you change district. Left/Right picks, Enter fills it.", sel = 1, options = PROFILE_LIST },
    { kind = "pfn_list", fn = "give_reward", label = "Give reward", help = "Gives one of the game's reward tables. Left/Right picks, Enter gives it. Save first.", sel = 1, options = REWARD_LIST },
    pset("no_fast_travel", "No map fast travel", "The map's own fast travel stops. The menu's teleport still works.", { { "Off", false }, { "On", true } }),
    pset("ai_find", "Enemies always find you", "All enemies and people know where you are.", { { "Off", false }, { "On", true } }),
    pset("ai_flee", "Enemies flee fights", "They run from combat areas.", { { "Off", false }, { "On", true } }),
    pset("ai_nonlethal", "Non-lethal enemies", "Enemies fight to subdue.", { { "Off", false }, { "On", true } }),
    pset("ai_shield", "Riot shields for all", "Melee enemies carry riot shields, where they have the animations.", { { "Off", false }, { "On", true } }),
    pset("ai_smoke", "Enemies use smoke", "Squads throw smoke on their coordinated attacks.", { { "Off", false }, { "On", true } }),
    pset("ai_swarm", "Enemies attacking at once", "More enemies attack you at once.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("corpses_stay", "Bodies and wrecks stay", "Bodies and wrecks linger longer. It costs frames.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("fraud_score", "Insurance Fraud score", "Insurance Fraud pays far more per hit.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    wset("range", "Range", "How far every gun reaches. Melee has its own row.", { { "Game's", 1 }, { "x2", 2 }, { "x4", 4 } }),
    pset("melee_lunge", "Melee lunge", "How far you dash at a swing. None: everyone swings from where they stand. Far: x4 when no one's in reach.", { { "None", "none" }, { "Game's", "game" }, { "Far", "far" } }),
    wset("knockback", "Knockback", "How hard hits push people and things.", { { "Game's", 1 }, { "x3", 3 }, { "x10", 10 } }),
    wset("blast", "Blast radius", "How far launchers' and thrown weapons' explosions reach.", { { "Game's", 1 }, { "x2", 2 }, { "x5", 5 } }),
    gcall("Max all weapon upgrades", "Every upgradeable weapon to its top level, like buying them. Save first.", [[
      local n = 0
      for _, inv in vlib_info_object:ipairs("inventory_weapon_info") do
        if weapon_has_upgrades(inv) then
          local lvl, max = weapon_get_upgrade_level(inv)
          if max and lvl and lvl < max then weapon_set_upgrade_level(inv, max) n = n + 1 end
        end
      end
      return n .. " weapons upgraded"
    ]]),
    toggle("golden_gun", "Golden gun", "All your guns kill in one shot. Pauses autosave while on."),
    { kind = "weapons_reset", label = "Weapons back to normal", help = "Every weapon setting back to the game's." },
  } },
  { name = "Vehicles", rows = {
    { kind = "garage_car", label = "From my garage", help = "A car from your garage with your paint and parts, next to you, no mechanic or wait. Left/Right picks, Enter spawns it.", sel = 1, options = {} },
    pset("keep_spawns", "Keep earlier spawns", "A new spawn no longer removes the last one. Move away between spawns or they land on each other. Holds 10, oldest goes first.", { { "Off", false }, { "On", true } }),
    { kind = "pfn_list", fn = "get_in", label = "Get in nearest", help = "Gets you in the driver's seat of the nearest vehicle within 30 m, boards and aircraft too. Left/Right picks how, Enter does it.", sel = 1, options = { { "Instantly", true }, { "Walk up to it", false } } },
    { kind = "pfn_list", fn = "get_out", label = "Get out", help = "Gets you out of the vehicle you're in. Left/Right picks how, Enter does it.", sel = 1, options = { { "The normal way", false }, { "Instantly", true } } },
    pset("get_in_spawned", "Get in when spawned", "Spawning a vehicle puts you straight in it.", { { "Off", false }, { "On", true } }),
    { kind = "deliver", label = "Spawn vehicle", help = "One of the game's 90 vehicles, next to you. Left/Right picks, Enter spawns it.", sel = 1, options = {} },
    { kind = "carset", key = "power", label = "Engine power", help = "The torque of your vehicle.", options = { { "Game's", 1 }, { "x2", 2 }, { "x3", 3 }, { "x5", 5 } }, sel = 1, save_key = "car.power" },
    { kind = "carset", key = "grip", label = "Grip", help = "How hard the tires of your vehicle hold the road.", options = { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 } }, sel = 1, save_key = "car.grip" },
    { kind = "carset", key = "brake", label = "Brakes", help = "How hard the vehicle you're in stops.", options = { { "Game's", 1 }, { "Weak", 0.5 }, { "Strong", 2 }, { "Very strong", 3 }, { "Stop dead", 5 } }, sel = 1, save_key = "car.brake" },
    pset("offroad_grip", "Off-road grip", "How well every vehicle holds on dirt and sand, no kit needed. Takes effect once you're in a vehicle.", { { "Game's", false }, { "x0.5", 0.5 }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 } }),
    { kind = "carset", key = "steer", label = "Steering", help = "How far the wheels turn, and up to what speed.", options = { { "Game's", 1 }, { "x1.25", 1.25 }, { "x1.5", 1.5 }, { "x2", 2 } }, sel = 1, save_key = "car.steer" },
    { kind = "carset", key = "top", label = "Vehicle top speed", help = "The top speed of your vehicle.", options = { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 } }, sel = 1, save_key = "car.top" },
    action("vehicle_health", "Repair vehicle", "Fixes the vehicle you're in."),
    pset("vgod", "Vehicle god mode", "Your vehicle can't be damaged.", { { "Off", false }, { "On", true } }),
    pset("car_no_crash", "No collision damage", "Crashing doesn't hurt your vehicle.", { { "Off", false }, { "On", true } }),
    pset("car_heavy", "Heavy vehicle", "Your vehicle pushes through traffic, as Infinite mass but only this one.", { { "Off", false }, { "On", true } }),
    pset("car_gravity", "Vehicle gravity", "How hard your vehicle is pulled down.", { { "Game's", 1 }, { "x0.5", 0.5 }, { "x0.25", 0.25 }, { "x2", 2 } }),
    { kind = "car_act", key = "boost", label = "Boost now", help = "Three seconds of boost. Some vehicles refuse." },
    { kind = "car_act", key = "jump", label = "Jump this vehicle", help = "Throws your vehicle upward." },
    { kind = "car_act", key = "paint", label = "Next paint", help = "Each press changes your vehicle to the next paint." },
    { kind = "special_car", label = "Special vehicle", help = "A vehicle missing from the spawn list. Left/Right picks, Enter spawns it. Boats need water.", sel = 1, options = { { "Fireworks flatbed", "flatbed_fireworks", "flatbed_01_ambient" }, { "Toxic flatbed", "flatbed_toxic", "flatbed_01_beater" }, { "Statue flatbed", "flatbed_choplifter_statue", "flatbed_01_beater" }, { "Fuel tanker", "quickshot_tanker_truck", "truck_base_tanker" }, { "Armored truck", "truck_armored_01", "truck_armored_01_ambient" }, { "Casino armored truck", "truck_armored_01", "truck_armored_01_casino" }, { "APC", "sp_apc_01", "apc_01_ambient" }, { "National Guard APC", "sp_apc_01", "apc_01_ng" }, { "Turret pickup", "pickup_03_turret", "pickup_03_marshall" }, { "Panteros turret truck", "truck_classic_02_turret", "truck_classic_02_panteros" }, { "Turret helicopter", "heli_standard_02_turret", "heli_standard_02_activity" }, { "Police spotlight helicopter", "heli_police_spotlight", "heli_police_01_police" }, { "Idols helicopter", "helicopter_police_idol_01", "heli_police_01_idols" }, { "Saints wingsuit helicopter", "heli_wingsuit_deploy", "heli_police_01_saints" }, { "Tether helicopter", "heli_standard_02_choplifter", "heli_standard_02_tether" }, { "Rotorhead", "heli_standard_03_rotorhead", "heli_standard_03_rotorhead_reward" }, { "Armored boss boat", "ct_idols_boss_boat", "boat_speed_01_armored" }, { "Boot Hill boat", "boat_speed_01_boothill", "boat_speed_01_boothill" }, { "Boat", "boat_standard_01", "boat_standard_01_ambient" }, { "Armored muscle 3", "muscle_03_armored", "muscle_03_armored_panteros" }, { "Monster, Panteros", "monster_02_ct_road", "monster_02_panteros" }, { "RV", "rv_01", "sp_rv_01_ambient" }, { "Meth lab RV", "rv_01_meth_lab", "sp_rv_01_meth_lab" }, { "Roofless Idols compact", "compact_01_idol_stream", "compact_01_ambient_idol_no_roof" }, { "Ned's compact", "compact_01_ned", "compact_01_ned_mission" }, { "Weiner truck", "foodtruck_01", "food_01_weiner" }, { "Sushi truck", "foodtruck_01", "food_01_sushi" }, { "Ice cream truck", "foodtruck_01", "food_01_ice_cream" }, { "Junk go-kart", "go_cart_ms_faire_b", "go_cart_junker" }, { "Covered cart, Marshall", "cart_01_covered", "cart_01_covered_marshall" }, { "Golf cart", "cart_02", "cart_02_reward" }, { "Reward wagon", "wagon_09", "wagon_09_reward" }, { "Sports 1", "sport_01", "sports_01_ambient" }, { "Sports 2", "sport_02", "sports_02_ambient" }, { "Muscle 1", "muscle_01", "muscle_01_ambient" }, { "Muscle 5", "muscle_05", "muscle_05_ambient" }, { "Classic 3", "classic_03", "classic_03_ambient" }, { "Utility truck", "utility_01", "sp_utility_01_ambient" }, { "Van 4", "van_04", "van_04_ambient" }, { "Bomb car", "wt_gas_bombcar", "sports_01_ambient" }, { "Mission tank", "tank_mh_pay_01", "tank_02_mh_pay" }, { "Bus", "bus_01", "bus_01_ambient" }, { "Bus, roadblock", "bus_01", "bus_01_road_block" }, { "Tank", "tank_01", "tank_01_ambient" }, { "Police tank", "tank_01", "tank_01_police" }, { "Yacht", "boat_yacht_01", "boat_yacht_01_ambient" }, { "Sailboat", "boat_sail_01", "boat_sail_01_ambient" }, { "Jet ski", "jet_ski", "jet_ski_ambient" }, { "Fire truck", "fire_01", "fire_01_ambient" }, { "Hearse", "hearse_01", "hearse_01_ambient" }, { "ATV", "atv_01", "atv_01_ambient" }, { "Attack helicopter", "heli_fighter_01_nahualli", "heli_fighter_01_nahualli" }, { "VTOL", "vanguard_vtol_02", "vanguard_vtol_02_ambient" }, { "Armored muscle", "muscle_01_armored", "muscle_01_armored_panteros" }, { "Police car", "police_01", "police_01_police" }, { "SWAT car", "police_01", "police_01_swat" }, { "Marshall luxury", "luxury_04", "luxury_04_marshall" }, { "Hoverboard", "hoverboard_01", "hoverboard_01_ambient" } } },
    gcall("Save vehicle to garage", "Saves your vehicle to your garage. Enter twice. Stays in your save.", "return vehicle_save_vehicle_to_garage(enemy_get_occupied_vehicle(gml_get_local_player()))", true),
    { kind = "car_act", key = "remove", label = "Remove spawned vehicles", help = "Removes vehicles the menu spawned, except the one you're in." },
    pset("cam_delay", "Car camera resets after", "How long the camera waits before swinging back behind your vehicle.", { { "Game's", false }, { "2 s", 2 }, { "10 s", 10 }, { "Never", 9999 } }),
    opt("Free camera in cars", "The camera stays where you put it instead of following your vehicle.", "option_get_camera_vehicle_follow()", "option_set_camera_vehicle_follow(%s)", { { "Game's", 1 }, { "Free", 2 } }),
    { kind = "car_ability", label = "Vehicle ability", help = "Gives your vehicle an ability. Left/Right picks, Enter gives it. Some need parts the vehicle lacks.", sel = 1, options = {
      { "Jump", 0xC243039A }, { "Air boost", 0x5C782702 }, { "Ball and chain", 0x585D60F8 }, { "Crab steering", 0x9027B56C }, { "Ejector seats", 0x8C3A98AD }, { "Front loader flip", 0xC8A6C120 },
      { "Honk blast", 0x80D9EC2B }, { "Infinite boost", 0x3BF698E8 }, { "Kneecappers", 0xEE7A9FAD }, { "Super air control", 0x4CDDA777 }, { "Cowcatcher and blast", 0xEABCC755 } } },
    { kind = "car_act", key = "tow", label = "Add tow hook", help = "Puts a tow hook on your vehicle." },
    pset("car_jump_power", "Vehicle jump power", "How high the Jump ability throws you.", { { "Game's", false }, { "x2", 2 }, { "x3", 3 }, { "x5", 5 } }),
    pset("car_ability_cd", "No ability cooldowns", "Vehicle abilities are ready at once.", { { "Off", false }, { "On", true } }),
    pset("car_takedowns", "Takedowns at any speed", "Spinouts, T-bones and flips happen from 5 mph, not 40 to 50.", { { "Off", false }, { "On", true } }),
    pset("car_ram", "Ram power", "How hard hitting things throws them.", { { "Game's", false }, { "x2", 2 }, { "x3", 3 }, { "x10", 10 } }),
    pset("car_brake_lights", "Brake lights stay on", "Your vehicle keeps its brake lights lit.", { { "Off", false }, { "On", true } }),
    pset("tires", "Bulletproof tires", "The tires of your vehicle can't be shot out.", { { "Off", false }, { "On", true } }),
    pset("spring", "Suspension", "Softer or stiffer springs on your vehicle.", { { "Game's", 1 }, { "Bouncy", 0.25 }, { "Soft", 0.5 }, { "Stiff", 2 }, { "Rock hard", 4 } }),
    { kind = "destroy_car", label = "Destroy this vehicle", help = "It blows up, and it can take you with it. Enter twice." },
    pset("keep_repaired", "Keep vehicle repaired", "Repairs your vehicle every second, with the game's repair cheat: near god mode.", { { "Off", false }, { "On", true } }),
    action("drop_car", "Drop a car", "Drops a car from the sky."),
    toggle("infinite_boost", "Infinite boost", "Vehicle boost never runs out."),
    toggle("infinite_mass", "Infinite mass", "Your vehicle shoves anything aside."),
    toggle("no_traffic_laws", "No traffic laws", "Drivers ignore traffic lights and stop signs. Pauses autosave while on."),
    toggle("city_monster_truck", "Monster truck traffic", "Traffic is monster trucks."),
    toggle("city_luxury_spawn", "Luxury traffic", "Traffic is luxury cars."),
    toggle("city_mascot", "Mascots", "Pedestrians spawn in mascot costumes. Turns off the other two traffic cheats."),
  } },
  { name = "Teleport", rows = {
    { kind = "waypoint", label = "Go to waypoint", help = "Takes you to the waypoint you set on the map, or the mission marker." },
    pset("auto_waypoint", "Auto-teleport to waypoint", "Place a waypoint on the map and you're there.", { { "Off", false }, { "On", true } }),
    { kind = "map_place", stores = true, label = "Go to store", help = "A store the map knows. Left/Right picks, Enter takes you there.", sel = 1, options = {} },
    { kind = "map_place", stores = false, label = "Go to map place", help = "An activity or place the map knows. Left/Right picks, Enter takes you there.", sel = 1, options = {} },
    { kind = "warp", label = "Go to travel point", help = "One of the game's 44 travel points. Left/Right picks, Enter takes you there.", sel = 1, options = {} },
    pset("teleport_style", "Teleport style", "Instant moves you straight there, in your vehicle too, with no loading screen. Game's is the old way, with one.", { { "Instant", false }, { "Game's, loading screen", "game" } }),
    { kind = "place_save", label = "Save this spot", help = "Saves where you stand to your places." },
    { kind = "places", label = "Go to saved place", help = "One of your places. Left/Right picks, Enter takes you there.", sel = 1 },
    { kind = "place_delete", label = "Delete that place", help = "Removes the place picked on Go to saved place." },
    { kind = "lift", label = "Go up", help = "Takes you straight up. Left/Right picks how high, Enter goes. Long falls kill: turn on God mode first.", sel = 2,
      options = { { "10 m", 10 }, { "50 m", 50 }, { "100 m", 100 }, { "250 m", 250 }, { "500 m", 500 }, { "1000 m", 1000 }, { "2000 m", 2000 }, { "3000 m", 3000 } } },
    { kind = "where", label = "Where am I", help = "Shows your position." },
  } },
  { name = "World", rows = {
    choice("Weather", "The game's weather cheat. Left/Right picks; it applies after a moment.", {
      { "Clear", "weather_clear" }, { "Dust", "weather_dust" }, { "Fog", "weather_fog" } }),
    { kind = "weathernode", label = "Any weather", help = "Blends to any of the game's weathers. Left/Right picks, Enter starts it.", sel = 1, options = {}, apply = true },
    choice("Time of day", "The game's time cheat. Left/Right picks; it applies after a moment.", {
      { "Morning", "tod_morning" }, { "Noon", "tod_noon" }, { "Afternoon", "tod_afternoon" },
      { "Evening", "tod_evening" }, { "Midnight", "tod_midnight" } }),
    { kind = "wdset", key = "freeze_clock", label = "Freeze clock", help = "Stops the time of day where it is.", options = { { "Off", false }, { "On", true } }, sel = 1, save_key = "world.freeze_clock" },
    { kind = "wdset", key = "clock_speed", label = "Clock speed", help = "How fast the time of day passes.", options = { { "Game's", 1 }, { "x0.5", 0.5 }, { "x2", 2 }, { "x5", 5 }, { "x10", 10 } }, sel = 1, save_key = "world.clock_speed" },
    { kind = "wdset", key = "pause", label = "Pause world", help = "Everything stops, you too. The menu still works.", options = { { "Off", false }, { "On", true } }, sel = 1 },
    { kind = "person", label = "Spawn person", help = "One of the game's characters, beside you. Left/Right picks, Enter spawns them.", sel = 1, options = {} },
    pset("spawn_hostile", "Spawned people act", "What people you spawn do from now on: wander off, guard you, fight gangs at your side, or fight you.", { { "Passive", false }, { "Bodyguards", "guard" }, { "Your army", "army" }, { "Fight you", true } }),
    gchoice("Radio station", "Tunes your vehicle, premium stations too. Left/Right picks, Enter tunes it.", { { "Off", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("off", false) return 'Off']] }, { "88.7 Dos Ochos", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("dos ochos", false) return '88.7 Dos Ochos']] }, { "90.5 Public Radio", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("public radio", false) return '90.5 Public Radio']] }, { "93.3 Tumbleweed", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("tumbleweed", false) return '93.3 Tumbleweed']] }, { "95.7 The Drop", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("thedrop", false) return '95.7 The Drop']] }, { "99.5 The Cipher", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("the cipher", false) return '99.5 The Cipher']] }, { "101.1 Outrun", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("outrun", false) return '101.1 Outrun']] }, { "103.3 Overdrive", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("overdrive", false) return '103.3 Overdrive']] }, { "201 Flex", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("flex", false) return '201 Flex']] }, { "203 El Latido", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("el_latido", false) return '203 El Latido']] }, { "204 Nuclear Blast", [[if not radio_get_current_station():is_valid() then return 'Get in a vehicle first' end radio_wheel_set_station("nuclear_blast", false) return '204 Nuclear Blast']] } }),
    gchoice("Music anywhere", "Plays a station's songs anywhere, on foot too, no DJ or ads. Left/Right picks, Enter plays them.", { { "Stop", [[playlist_stop() return 'Music off']] }, { "The Drop", [[playlist_play(vlib_info_object:get_object("playlist_info", "kbpm_thedrop")) return 'Playing The Drop']] }, { "Outrun", [[playlist_play(vlib_info_object:get_object("playlist_info", "kfdr_outrun")) return 'Playing Outrun']] }, { "Dos Ochos", [[playlist_play(vlib_info_object:get_object("playlist_info", "kfst_dosochos")) return 'Playing Dos Ochos']] }, { "Overdrive", [[playlist_play(vlib_info_object:get_object("playlist_info", "kfvzz_overdrive")) return 'Playing Overdrive']] }, { "The Cipher", [[playlist_play(vlib_info_object:get_object("playlist_info", "kjmz_thecipher")) return 'Playing The Cipher']] }, { "Public Radio", [[playlist_play(vlib_info_object:get_object("playlist_info", "ksipr_santopublic")) return 'Playing Public Radio']] }, { "Tumbleweed", [[playlist_play(vlib_info_object:get_object("playlist_info", "kwpke_tumbleweed")) return 'Playing Tumbleweed']] }, { "Flex", [[playlist_play(vlib_info_object:get_object("playlist_info", "sm1_flex")) return 'Playing Flex']] }, { "El Latido", [[playlist_play(vlib_info_object:get_object("playlist_info", "sm3_ellatido")) return 'Playing El Latido']] }, { "Nuclear Blast", [[playlist_play(vlib_info_object:get_object("playlist_info", "sm4_nuclearblast")) return 'Playing Nuclear Blast']] } }),
    { kind = "song", label = "Play song", help = "Plays any song anywhere, including three no station plays. Left/Right picks, Enter plays it.", sel = 1, options = SONGS },
    { kind = "skip_track", label = "Skip track", help = "The next track on the music or the radio." },
    gcall("Pause or resume music", "Pauses Music anywhere, or starts it again.", [[if not playlist_is_playing() and not playlist_is_paused() then return 'No music on' end if playlist_is_paused() then playlist_resume() return 'Resumed' end playlist_pause() return 'Paused']]),
    gcall("Now playing", "Shows what's on.", [[if playlist_is_playing() then local s = playlist_get_active_song() if s:is_valid() then return vint_insert_values_in_string("{1:text_tag} - {2:text_tag}", s.m_artist:get_handle(), s.m_title:get_handle()) end end local t, a = radio_get_playing_title() if not t or t == 0 then return 'Nothing playing' end if a and a ~= 0 then return vint_insert_values_in_string("{1:text_tag} - {2:text_tag}", a, t) end return vint_insert_values_in_string("{1:text_tag}", t)]]),
    { kind = "spawn_prop", label = "Spawn prop", help = "Loads a prop and puts it in front of you. Left/Right picks, Enter spawns it. Gone when you reload.", sel = 1, options = SPAWN_PROPS },
    { kind = "remove_prop", last = true, label = "Remove last prop", help = "Removes the prop you spawned last." },
    { kind = "remove_prop", label = "Remove all props", help = "Removes every prop you've spawned." },
    { kind = "creator", label = "Creator mode", help = "Fly a camera and place objects at any angle: stunt jumps, walls, whole courses. Enter starts it and closes the menu; the controls show on screen. Gone when you reload: keep a layout." },
    { kind = "creator_obj", label = "Creator object", help = "What creator mode places. Ramps first, then every prop. Left/Right picks; LB or RB taps change it in creator mode.", sel = 1, options = (function() local o = { { "Trailer ramp (NOT A RAMP)", "roadblock_idols_ramp_01a" }, { "Construction ramp", "roadblock_construction_ramp_01" }, { "Rodeo ramp with digger", "laundromat_rodeo_ramp_01" } } for _, v in ipairs(SPAWN_PROPS) do o[#o + 1] = v end return o end)() },
    pset("creator_step", "Creator turn step", "How far each press turns, tilts or rolls what you're placing.", { { "15 degrees", false }, { "5 degrees", 5 }, { "45 degrees", 45 }, { "90 degrees", 90 } }),
    pset("creator_grid", "Creator grid", "Snaps what you place to a grid, for lining things up.", { { "Off", false }, { "0.5 m", 0.5 }, { "1 m", 1 }, { "2 m", 2 }, { "5 m", 5 } }),
    { kind = "layout", label = "Layout", help = "A saved layout of placed objects. Left/Right picks one. Edit the name= line in TweakMenu\\layout_1.txt to rename it, or pass the file to someone." },
    { kind = "layout_save", label = "Save layout", help = "Keeps everything you've placed in the layout picked above. Enter, and Enter twice over one that's in use." },
    { kind = "layout_load", label = "Load layout", help = "Puts the picked layout's objects back where they were. You have to be within 300 m: Go to layout takes you there." },
    { kind = "layout_go", label = "Go to layout", help = "Takes you to the picked layout's first object." },
    { kind = "layout_delete", label = "Delete layout", help = "Deletes the picked layout's file. Enter twice." },
    { kind = "creator_clear", label = "Clear placed objects", help = "Removes everything creator mode placed. Enter twice. Save a layout first to keep it." },
    { kind = "hq_spot", label = "HQ spot", help = "The spot in your headquarters the rows below use. Left/Right picks.", sel = 1, options = { { "Armory normal 1", "hq_prop_anchor_armory_normal_01" }, { "Armory wall 1", "hq_prop_anchor_armory_wall_01" }, { "Bar large 1", "hq_prop_anchor_bar_large_01" }, { "Bar large 2", "hq_prop_anchor_bar_large_02" }, { "Bar normal 1", "hq_prop_anchor_bar_normal_01" }, { "Bar wall 1", "hq_prop_anchor_bar_wall_01" }, { "Exterior huge 1", "hq_prop_anchor_exterior_huge_01" }, { "Exterior huge 2", "hq_prop_anchor_exterior_huge_02" }, { "Exterior large 1", "hq_prop_anchor_exterior_large_01" }, { "Exterior large 2", "hq_prop_anchor_exterior_large_02" }, { "Gameroom large 1", "hq_prop_anchor_gameroom_large_01" }, { "Gameroom normal 1", "hq_prop_anchor_gameroom_normal_01" }, { "Gameroom wall 1", "hq_prop_anchor_gameroom_wall_01" }, { "Hall huge 1", "hq_prop_anchor_hall_huge_01" }, { "Hall large 1", "hq_prop_anchor_hall_large_01" }, { "Hall large 2", "hq_prop_anchor_hall_large_02" }, { "Hall large 3", "hq_prop_anchor_hall_large_03" }, { "Sunshine large 1", "sunshine_hq_anchor_large_01" }, { "Sunshine large 2", "sunshine_hq_anchor_large_02" }, { "Sunshine large 3", "sunshine_hq_anchor_large_03" }, { "Sunshine large 4", "sunshine_hq_anchor_large_04" }, { "Sunshine normal 1", "sunshine_hq_anchor_normal_01" } } },
    { kind = "hq_prop", label = "HQ prop", help = "Puts a prop on HQ spot from anywhere, owned or not, any size. Left/Right picks, Enter puts it. Stays in your save. Big ones may clip.", sel = 1, options = CRIB_PROPS },
    { kind = "hq_clear", label = "Clear this HQ spot", help = "Empties the spot picked on HQ spot." },
    { kind = "look_undo", label = "Undo my look", help = "Back to your last snapshot, or how you looked before Saved look or Character preset this session. Enter twice." },
    { kind = "look_snap", label = "Snapshot my look", help = "Undo my look will come back to how you look now. Lasts until you quit." },
    pset("friendly_fire", "Friendly fire", "Normally the game's shots do nothing to friends, followers and gang allies. Half or Full lets them hurt.", { { "Game's (none)", false }, { "Half", 1 }, { "Full", 2 } }),
    pset("body_muscular", "Body: muscle", "Past the slider's top. Only on screen: your save keeps your real body.", { { "Game's", false }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 } }),
    pset("body_large", "Body: fat", "Past the slider's top. Only on screen: your save keeps your real body.", { { "Game's", false }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 } }),
    pset("body_thin", "Body: thin", "Past the slider's top. Only on screen: your save keeps your real body.", { { "Game's", false }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 } }),
    pset("body_breasts", "Body: chest", "Past the slider's top. Only on screen: your save keeps your real body.", { { "Game's", false }, { "x1.5", 1.5 }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 } }),
    pset("body_gender", "Body: masculine to feminine", "That slider, past both ends. Only on screen: your save keeps your real body.", { { "Game's", false }, { "-0.5", -0.5 }, { "0", 0.0001 }, { "0.5", 0.5 }, { "1", 1.0 }, { "1.5", 1.5 } }),
    pset("body_head", "Face: head shape", "Past the slider's top. Only on screen: your save keeps your real face.", { { "Game's", false }, { "1", 1.0 }, { "2", 2.0 }, { "3", 3.0 } }),
    pset("body_eyes", "Face: eye size", "Past the slider's top. Only on screen: your save keeps your real face.", { { "Game's", false }, { "0", 0.0001 }, { "1", 1.0 }, { "2", 2.0 }, { "3", 3.0 }, { "5", 5.0 } }),
    pset("body_nose", "Face: nose size", "Past the slider's top. Only on screen: your save keeps your real face.", { { "Game's", false }, { "0", 0.0001 }, { "1", 1.0 }, { "2", 2.0 }, { "3", 3.0 }, { "5", 5.0 } }),
    pset("body_mouth", "Face: mouth size", "Past the slider's top. Only on screen: your save keeps your real face.", { { "Game's", false }, { "0", 0.0001 }, { "1", 1.0 }, { "2", 2.0 }, { "3", 3.0 }, { "5", 5.0 } }),
    { kind = "body_back", label = "Back to my real body", help = "Sets every Body: and Face: row back to the game's." },
    pset("game_speed", "Game speed", "Slow motion, or the whole game faster. You too.", { { "Normal", false }, { "x0.1", 10.0 }, { "x0.25", 4.0 }, { "x0.5", 2.0 }, { "x2", 0.5 }, { "x4", 0.25 } }),
    pset("force_combat", "Stay in combat", "The game thinks you're always in a fight.", { { "Off", false }, { "On", true } }),
    { kind = "go_to_hour", label = "Go to time", help = "Moves the clock there at once. Left/Right picks, Enter moves it.", sel = 1, options = { { "Dawn", 6 }, { "Morning", 9 }, { "Noon", 12 }, { "Afternoon", 15 }, { "Dusk", 18 }, { "Evening", 20 }, { "Midnight", 0.01 }, { "Small hours", 3 } } },
    pset("warp_map", "Warp from map", "The game's dev teleport: on the big map, look for DEBUG WARP. You arrive 300 m up: use God mode or the wingsuit.", { { "Off", false }, { "On", true } }),
    opt("Dev: never die", "Developer switch left in the game. Effect unknown.", "global_script_variable_get_bool('never_die')", "global_script_variable_set_bool('never_die', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: never die, AI", "Developer switch left in the game. Effect unknown.", "global_script_variable_get_bool('never_die_ai')", "global_script_variable_set_bool('never_die_ai', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: Shawn mode", "Developer switch named after someone. Effect unknown.", "global_script_variable_get_bool('shawn_mode')", "global_script_variable_set_bool('shawn_mode', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: capture mode", "Developer switch, for filming. Effect unknown.", "global_script_variable_get_bool('capture_mode')", "global_script_variable_set_bool('capture_mode', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: auto sprint", "Developer switch left in the game. Effect unknown.", "global_script_variable_get_bool('auto_sprint_enable')", "global_script_variable_set_bool('auto_sprint_enable', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: infinite ammo", "Developer switch the game reads: no cheat flag on your save.", "global_script_variable_get_bool('infinite_ammo')", "global_script_variable_set_bool('infinite_ammo', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: infinite magazine", "Developer switch: no cheat flag on your save.", "global_script_variable_get_bool('infinite_magazine')", "global_script_variable_set_bool('infinite_magazine', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: radio on", "Developer switch: off silences the radio.", "global_script_variable_get_bool('radio_enabled')", "global_script_variable_set_bool('radio_enabled', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: vehicle ramps", "Developer switch left in the game. Effect unknown.", "global_script_variable_get_bool('vehicle_ramp_override')", "global_script_variable_set_bool('vehicle_ramp_override', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: weapon raycasts", "Developer switch. May draw nothing in this build.", "global_script_variable_get_bool('debug_weapon_raycasts')", "global_script_variable_set_bool('debug_weapon_raycasts', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: notoriety bubbles", "Developer switch. May draw nothing in this build.", "global_script_variable_get_bool('debug_render_notoriety_bubbles')", "global_script_variable_set_bool('debug_render_notoriety_bubbles', %s)", { { "Off", false }, { "On", true } }),
    opt("Dev: HQ mask off", "Developer switch left in the game. Effect unknown.", "global_script_variable_get_bool('hq_mask_disabled')", "global_script_variable_set_bool('hq_mask_disabled', %s)", { { "Off", false }, { "On", true } }),
    { kind = "console_row", label = "Freeze emote", handler = 0xA914F0, help = "Freezes the emote you're doing mid-pose, or lets it go." },
    { kind = "outfit_any", label = "Hidden outfit", help = "Clothes the wardrobe doesn't list. Left/Right picks, Enter wears them. Undo my look puts you back.", sel = 1, options = { { "Armadillo mascot", "clo_suit_armadillo_mascot_01" }, { "Cookie suit", "clo_suit_cookie_suit_01" }, { "Demon bodysuit", "clo_suit_demon_bodysuit_01" }, { "Halloween cat", "clo_suit_halloween_bodysuit_cat_01" }, { "Halloween devil", "clo_suit_halloween_bodysuit_devil_01" }, { "Pumpkin", "clo_suit_pumpkin_01" }, { "Stripes", "clo_suit_stripes_01" }, { "Wetsuit", "clo_suit_wetsuit_01" }, { "Marshall subgrunt", "clo_suit_marshall_subgrunt_01" }, { "Marshall grunt", "clo_suit_marshall_grunt_02" }, { "Star band hat", "clo_hat_starband" }, { "Devil horns", "clo_head_devil_horns_headband_01" }, { "Large horns", "clo_head_large_horns_headband_01" }, { "Firefighter", "clo_suit_firefighter_01" } } },
    pset("gang_war", "Gang war", "Gangs near you fight each other, without you. Go where they are, or use Send in a gang twice.", { { "Off", false }, { "Panteros vs Idols", { { 0xCFD91205, 0xAF91816E } } }, { "Panteros vs Marshall", { { 0xCFD91205, 0xAD77A00A } } }, { "Idols vs Marshall", { { 0xAF91816E, 0xAD77A00A } } }, { "All three gangs", { { 0xCFD91205, 0xAF91816E }, { 0xCFD91205, 0xAD77A00A }, { 0xAF91816E, 0xAD77A00A } } }, { "Gangs vs police", { { 0xCFD91205, 0x55BEF8FA }, { 0xAF91816E, 0x55BEF8FA }, { 0xAD77A00A, 0x55BEF8FA } } }, { "Everyone", { { 0xCFD91205, 0xAF91816E }, { 0xCFD91205, 0xAD77A00A }, { 0xAF91816E, 0xAD77A00A }, { 0xCFD91205, 0x55BEF8FA }, { 0xAF91816E, 0x55BEF8FA }, { 0xAD77A00A, 0x55BEF8FA } } } }),
    pset("fight_damage", "People fight damage", "How hard people hurt each other, not you. The game's is 0.6, which is why their fights drag.", { { "Game's", false }, { "1", 1.0 }, { "2", 2.0 }, { "5", 5.0 } }),
    pset("combative_peds", "Pedestrians fight back", "Passers-by fight instead of running.", { { "Off", false }, { "On", true } }),
    pset("ai_combat", "Everyone battle ready", "Everyone stays in combat mode.", { { "Off", false }, { "On", true } }),
    pset("world_gravity", "World gravity", "Gravity for everything loose: people, grenades, things. Cars hold the road better. Upward sends what's loose away.", { { "Game's", false }, { "x0.5", 0.5 }, { "x0.25", 0.25 }, { "x0.1", 0.1 }, { "x2", 2.0 }, { "x3", 3.0 }, { "Upward", -0.2 } }),
    pset("blast_size", "Explosion size", "How far every explosion reaches, everyone's. The fireball itself stays the same size.", { { "Game's", false }, { "x2", 2.0 }, { "x3", 3.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("blast_force", "Explosion force", "How hard every explosion throws things.", { { "Game's", false }, { "x3", 3.0 }, { "x10", 10.0 }, { "x30", 30.0 } }),
    pset("blast_damage", "Explosion damage", "How hard explosions hurt. Some take their damage from the weapon instead.", { { "Game's", false }, { "x2", 2.0 }, { "x5", 5.0 } }),
    pset("own_blast", "Damage to yourself", "The damage you do to yourself, as from your own explosions.", { { "Game's", false }, { "None", 0.0001 } }),
    { kind = "launch_car", label = "Launch this vehicle", help = "Throws your vehicle, or the nearest, into the air. Left/Right picks, Enter throws it.", sel = 1, options = { { "Small", 30000 }, { "Big", 80000 }, { "Moon", 200000 } } },
    { kind = "crowd_act", key = "zombies", label = "Zombie outbreak", help = "A third of the people within 40 m turn on everyone else." },
    { kind = "crowd_act", key = "riot", label = "Start a riot near", help = "Everyone within 40 m splits into two sides, which fight." },
    { kind = "crowd_act", key = "downed", label = "Downed, not dead", help = "People within 40 m go down instead of dying when they're killed." },
    pset("free_for_all", "Free for all", "These factions attack anyone they don't have a rule for, you and their own included.", { { "Off", false }, { "Gangs", "gangs" }, { "Gangs and police", "all" } }),
    pset("gang_presence", "Gang presence", "How many of each gang the district keeps on its streets. Districts only have the gangs they have. Watch your frame rate.", { { "Game's", false }, { "x3", 3 }, { "x6", 6 } }),
    { kind = "crowd_act", key = "launch", label = "Launch everyone near", help = "Everyone within 40 m flies up." },
    pset("peds", "Pedestrian count", "How many people the district keeps around. Watch your frame rate.", { { "Game's", false }, { "Few", 0.25 }, { "x2", 2 }, { "x3", 3 } }),
    pset("traffic", "Traffic amount", "How many cars the district keeps around. Watch your frame rate.", { { "Game's", false }, { "Few", 0.25 }, { "x2", 2 }, { "x3", 3 } }),
    pset("traffic_far", "Traffic appears at", "How far away traffic appears.", { { "Game's", false }, { "Further", 300.0 }, { "Far", 500.0 } }),
    pset("rain_crowd", "Crowds in the rain", "The streets normally empty when it rains.", { { "Game's", false }, { "Same as sunny", 1.0 } }),
    pset("enemy_aim", "Enemy aim", "How far enemies' shots are meant to miss by. If nothing changes, try on fresh enemies.", { { "Game's", false }, { "Laser", 0.0001 }, { "Poor", 3 }, { "Stormtroopers", 8 } }),
    pset("back_stab", "Damage from behind", "The bonus for hits from behind. The game's is x2.5.", { { "Game's", false }, { "None", 1.0 }, { "x5", 5.0 }, { "x10", 10.0 } }),
    pset("no_flinch", "No flinch", "Taking a hit doesn't make you flinch.", { { "Off", false }, { "On", 100000.0 } }),
    pset("dodge_ms", "Dodge safe time", "How long a dodge keeps you from harm.", { { "Game's", false }, { "1 s", 1000 }, { "2 s", 2000 }, { "5 s", 5000 } }),
    { kind = "revive_me", label = "Get up", help = "Stands you back up when you're down." },
    pset("slow_button", "Slow motion button", "Hold LB and RB, or Alt, for slow motion while it's held. Everyone slows, you too.", { { "Off", false }, { "x0.5", 2.0 }, { "x0.25", 4.0 }, { "x0.1", 10.0 } }),
    pset("panic", "Panic distance", "How far gunfire and explosions scare people. New scares only.", { { "Game's", false }, { "Hardly at all", 0.05 }, { "Whole block", 3 } }),
    pset("ragdoll_easy", "How easily you fall", "How hard something has to hit you to knock you over.", { { "Game's", false }, { "Easily", 0.2 }, { "Hardly ever", 5 } }),
    pset("no_parked", "No parked cars", "Stops new parked cars appearing. The ones already there stay.", { { "Off", false }, { "On", true } }),
    pset("rockets", "Special rounds", "The gun in your hands fires one of these, at most 4 a second. Each loads its models first. A stuck football gives you 6 s to run. Save first.", ROUND_OPTIONS),
    pset("explosive_melee", "Explosive punches", "Melee hits make any blast in the game, your fists too. Pair it with God mode. Save first.", BLAST_OPTIONS),
    pset("headshot_blast", "Headshot kill blast", "Kill someone with a headshot and they blow up with this, any blast in the game, every time. Not melee kills. Many blasts at once can crash the game: Save first.", BLAST_OPTIONS),
    pset("hits_recruit", "Hits recruit", "Anyone you hurt may turn on their friends for 10 s. The percent is the chance each time you hurt them. Fists and blasts may not count.", { { "Off", false },
      { "25%", { { "passive_mod_class_besties", 0.25 } } }, { "100%", { { "passive_mod_class_besties", 1.0 } } } }),
    pset("all_my_damage", "All my damage", "Everyone you hurt also burns, gets a shock or bleeds, for 1 s each time. Not tied to the gun: fists count, and blasts may. Strongest on fast guns.", { { "Off", false },
      { "Burn", { { "object_mod_class_enemy_damage_conflagration", 1.0 } } }, { "Shock", { { "object_mod_class_enemy_damage_electrification", 1.0 } } }, { "Bleed", { { "object_mod_class_enemy_damage_bleed", 1.0 } } },
      { "All three", { { "object_mod_class_enemy_damage_conflagration", 1.0 }, { "object_mod_class_enemy_damage_electrification", 1.0 }, { "object_mod_class_enemy_damage_bleed", 1.0 } } } }),
    pset("round_blast", "Round blast", "What Special rounds explode into, any blast in the game.", ROUND_BLASTS),
    pset("sig_from", "Signature from", "Adds another gun's signature to the gun in your hands, with no upgrade. Bullet ones need a gun, melee ones a swing. May do nothing on the wrong kind. Save first.", SIG_OPTIONS),
    pset("sig_from2", "Second signature", "Another one on top.", SIG_OPTIONS),
    pset("bullet_blast", "Blast on hit", "Your bullets make this blast where they land, with no rocket. The gun keeps its fire and aim. Bullets only: launchers use Round blast. Heavy ones are held to 4 shots a second. Save first.", BLAST_OPTIONS),
    pset("fire_mode", "Fire mode", "Changes how the trigger behaves. Bursts pause between groups. Charge waits before every shot; spin-up waits once. With a single-shot gun, use Full auto too. No charge sound or lights.", { { "Game's", false },
      { "Burst of 3", { "burst", 3, 400 } }, { "Burst of 5", { "burst", 5, 500 } }, { "Burst of 10", { "burst", 10, 800 } },
      { "Charge 1 s", { "charge", 1000 } }, { "Charge 3 s", { "charge", 3000 } }, { "Spin up 1 s", { "spin", 1000 } }, { "Spin up 3 s", { "spin", 3000 } } }),
    pset("nth_round", "Round in N shots", "Every few shots the gun fires this instead of a bullet. Bullets the rest of the time. Save first.", ROUND_OPTIONS),
    pset("nth_every", "N shots", "How often.", { { "Every 5th", 5 }, { "Every 2nd", 2 }, { "Every 3rd", 3 }, { "Every 10th", 10 }, { "Every 30th", 30 } }),
    pset("fire_sound", "Fire sound", "Another gun's firing sound. May not change, or only on the next gun.", { { "Game's", false },
      { "Minigun", 0x6C6084C4 }, { "Star God", 0x86E6F4CD }, { "Foam finger", 0x2431C32C }, { "Lawman", 0x2CF3CA16 }, { "Retrowave", 0xA1AC88AC }, { "Haunted", 0x66718EE1 }, { "Elephant", 0x41FEE15D }, { "Focus", 0xC20D60CD },
      { "Cowboy", 0x064FEA0A }, { "Heavy SMG", 0x4C51E183 }, { "Hi-volume", 0x051409B3 }, { "RPG", 0xAA943BC5 }, { "Potato", 0x6E2BD461 }, { "Beer can", 0xDFE6F3DE }, { "Guitar", 0x083D978D }, { "Pinata", 0xC683369F }, { "Thrustbuster", 0xF95F3797 },
      { "VTOL laser", 0xAF6009C1 }, { "Tank", 0xF9C0A08C }, { "Heli gun", 0x56F3ECD0 }, { "Taser", 0xEFAAC538 }, { "Anvil", 0x7CE9AEFB }, { "Ban hammer", 0xCEABCE13 }, { "LMG", 0x963C2F3A },
      { "DMR", 0x18023E4B }, { "Pistol shotgun", 0x04D72048 }, { "Breacher", 0x84841928 }, { "Frost SMG", 0xB582B2A1 }, { "Frost turret", 0xB7F55D6B }, { "Ban hammer swing", 0x19318327 }, { "Dead mace", 0x5E51E5CC }, { "Dead mace, heavy", 0xD246CA7D } }),
    { kind = "console_list", class = "char_cust_outfit", handler = 0x14055C0, what = "Wearing", label = "Wear any outfit", help = "Any of the game's whole outfits. Left/Right picks, Enter wears it. Undo my look puts you back.", sel = 1, options = {} },
    { kind = "console_list", class = "skill_info", handler = 0x68B530, what = "Equipped", label = "Equip any skill", help = "Gives you any skill and equips it. Left/Right picks, Enter equips. Stays in your save.", sel = 1, options = {} },
    { kind = "game_list", class = "radio_newscast_info", label = "Newscast", help = "Plays any newscast. Left/Right picks, Enter plays it. Later ones spoil the story, and you've finished it.", sel = 1, options = {}, code = [[newscast_play(vlib_info_object:get_object("radio_newscast_info", %q))]] },
    gcall("Stop newscast", "Stops the newscast.", [[newscast_stop() return 'Stopped']]),
    { kind = "hq_theme", label = "HQ room theme", help = "Rebuilds your HQ's rooms in another level's look. Stays in your save. Don't stand inside if you can help it.", sel = 1, options = { { "Normal", false }, { "Level 1", "hq_level_1" }, { "Level 2", "hq_level_2" }, { "Level 3", "hq_level_3" }, { "Dead", "hq_room_theme_ct_dead" } } },
    { kind = "vehicle_type", label = "Vehicle type", help = "Narrows Any vehicle to one kind.", sel = 1, options = { { "All", false }, { "Cars", "car" }, { "Bikes", "bike" }, { "Heavy", "heavy" }, { "Water", "water" }, { "Aircraft", "air" }, { "Other", "other" } } },
    { kind = "any_vehicle", label = "Any vehicle", help = "Any of the game's vehicles, rare and reward ones too. Left/Right picks, Enter spawns it. The next row picks its version.", sel = 1, options = ANY_VEHICLES },
    { kind = "any_variant", label = "Any vehicle version", help = "Which version of Any vehicle, with how you'd normally meet it. Left/Right picks, Enter spawns it. Some need water or a mission, or may not appear.", sel = 1, options = any_variants(1) },
    pset("rare_traffic", "Rare traffic", "Cars this district rarely shows come out far more. Only the ones it already lists, and only as they load.", { { "Off", false }, { "On", true } }),
    { kind = "car_effect", label = "Effect on this car", help = "Your vehicle, or the nearest, gets it for 30 seconds. Left/Right picks, Enter puts it on.", sel = 1,
      options = { { "Slippery", "slippery" }, { "Super grip", "supergrip" }, { "Plow", "plow" }, { "Vehicular manslaughter", "vehicular_manslaughter" } } },
    { kind = "proto_weapon", label = "Prototype weapon", help = "A weapon no list in the game names, in place of what's in its slot. Left/Right picks, Enter twice. May not work. Can crash. Save first.", sel = 1,
      options = { { "Boss hammer", "weapon_panteros_miniboss_melee_player", 1 }, { "Sonic staff", "weapon_idols_miniboss_staff_player", 1 }, { "Poi", "weapon_idols_raver_melee", 1 }, { "Thrown poi", "weapon_idols_raver_thrown", 12 }, { "Cluster grenade", "weapon_grenade_multi", 12 }, { "Full-auto police shotgun", "weapon_shotgun_police_full_auto", 5 }, { "Idols miniboss SMG", "weapon_smg_idols_miniboss_hidden", 3 }, { "Idols knife", "weapon_melee_idols_subgrunt_knife", 1 }, { "Panther claws", "weapon_panteros_specialist_melee", 1 }, { "Coyote's bite", "weapon_melee_coyote", 1 }, { "Frost shield", "weapon_frostlander_shield_player", 8 }, { "Sticky bomb", "weapon_special_sticky_proximity_bomb", 7 }, { "Small mine", "weapon_proximity_mine_small", 12 }, { "Marshall burst launcher", "weapon_launcher_marshall_burst_rocket", 7 }, { "Guitar launcher", "weapon_launcher_guitar", 7 }, { "Potato cannon", "weapon_launcher_potato", 7 }, { "Beer can launcher", "weapon_launcher_beer_can", 7 }, { "Star God blaster", "weapon_pistol_star_god", 2 }, { "Saints Lawgiver", "weapon_pistol_saints_lawgiver", 2 }, { "Foam finger", "weapon_pistol_foam_finger", 2 }, { "Boss SMG", "weapon_smg_idols_miniboss_player", 3 }, { "Saintsblade", "weapon_melee_saints_blade", 1 }, { "Wrangler focus rifle", "weapon_rifle_focus_wrangler_lvl1", 8 }, { "Frost Queen melee", "weapon_frostlander_queen_melee", 1 }, { "Yeti melee", "weapon_frostlander_yeti_melee", 1 }, { "Yeti belly flop", "weapon_frostlander_yeti_finisher", 1 }, { "Genki finisher", "weapon_genki_finisher", 1 }, { "Frost shield, enemy", "weapon_frostlander_shield", 8 }, { "Chill ball", "weapon_frostlander_chill_ball", 12 }, { "Frost turret", "weapon_frostlander_turret", 8 }, { "Frost SMG, one hand", "weapon_smg_frostlander_1h", 3 }, { "Frost SMG, cinematic", "weapon_smg_frostlander_cinematic", 3 }, { "Frost SMG, Death Blossom", "weapon_smg_frostlander_deathblossom", 3 } } },
    { kind = "unlock", key = "tidy", label = "Remove test guns", help = "Takes the 41 test guns and vehicle mounts that Unlock every weapon adds out of your wheel and save. Enter twice. Save first." },
    { kind = "unlock", key = "skins", label = "Unlock all weapon skins", help = "Every weapon skin, in the game's weapon screen. Enter twice. Save first." },
    { kind = "near_effect", label = "Short effect on everyone near", help = "Everyone within 40 m gets it for a few seconds. Left/Right picks, Enter does it.", sel = 1,
      options = { { "Flee", "flee", 8 }, { "Shock", "electrified", 8 }, { "Panic", "panic", 8 }, { "Blind", "blindness", 8 }, { "Slip", "slippery", 8 }, { "Stagger", "stagger", 3 }, { "Stagger sideways", "side_stagger", 3 }, { "Reel", "reeling", 3 }, { "Fall over", "eat food ragdoll", 3 }, { "Chill", "chill", 8 }, { "Prank fire", "prank_fire", 8 }, { "Prank dissolve", "prank_dissolve", 8 } } },
    { kind = "me_effect", label = "Skill effect on you", help = "A skill's effect for 30 seconds, with no Flow. Left/Right picks, Enter starts it.", sel = 1,
      options = { { "Berserker", "berserk" }, { "Transfusion", "vampire" }, { "Tough Mother", "get_tough" }, { "Overwatch", "overwatch" }, { "Quick Draw", "quick_draw" } } },
    { kind = "wing_now", label = "Open wingsuit now", help = "Opens the wingsuit at once, lifting you 40 m first if you're on the ground." },
    gcall("Signature ability on this gun", "Switches this gun's signature ability on or off, with no challenge to finish. Stays in your save.",
      [[local i = player_local_inventory_get_item_info(player_local_inventory_get_active_slot()) local d = weapon_get_ultimate_data(i) if d == 0 then return 'This gun has none' end weapon_set_ultimate_activate_state(i, not d.activated) return d.activated and 'Signature ability off' or 'Signature ability on']]),
    gcall("All signature abilities", "Every gun's signature ability on. Enter twice. Save first.",
      [[local n = 0 for _, w in vlib_info_object:ipairs("inventory_weapon_info") do if weapon_get_ultimate_data(w) ~= 0 then weapon_set_ultimate_activate_state(w, true) n = n + 1 end end return n .. ' signature abilities on']], true),
    { kind = "surf", label = "Surf nearest car", help = "Puts you on the nearest vehicle within 15 m, as the game's car surfing does." },
    { kind = "surf_stop", label = "Stop surfing", help = "Gets you off the vehicle you're surfing." },
    { kind = "send_gang", label = "Send in a gang", help = "Sets their notoriety to 3 stars and calls in a wave. Left/Right picks who, Enter sends them.", sel = 1,
      options = { { "Panteros", 0xCFD91205 }, { "Idols", 0xAF91816E }, { "Marshall", 0xAD77A00A }, { "Police", 0x55BEF8FA } } },
    { kind = "pfn_list", class = "game_vignette_info", fn = "scene_set", label = "Street scene", help = "Makes it the only scene wherever the district lists it. Left/Right picks, Enter sets it. Walk around to see it.", sel = 1, options = {} },
    { kind = "pfn", fn = "scene_set", arg = "off", label = "Street scenes normal", help = "Puts the street scenes back." },
    { kind = "pfn_list", fn = "send_wave", label = "Send in a wave", help = "3 stars and that wave. Left/Right picks, Enter sends it. It can ask for people that aren't loaded. Save first.", sel = 1, options = {
  { "Panteros grunts, forge", { "panteros_forge_wave_sequence", 0xCFD91205 } }, { "Panteros miniboss", { "panteros_miniboss_wave_sequence", 0xCFD91205 } }, { "Panteros vehicles", { "pn_forge_vehicles", 0xCFD91205 } },
  { "Idol grunts", { "idol_grunt_wave_sequence", 0xAF91816E } }, { "Idol ravers", { "idol_raver_wave_sequence", 0xAF91816E } }, { "Idol miniboss", { "idol_miniboss_wave_sequence", 0xAF91816E } }, { "Idol icon", { "idol_icon_wave_sequence", 0xAF91816E } },
  { "Marshall grunts", { "marshall_grunt_wave_sequence", 0xAD77A00A } }, { "Marshall gatling", { "marshall_turfwar_financial_gatlinggunner", 0xAD77A00A } },
  { "Police grunts", { "police_grunt_wave_sequence", 0x55BEF8FA } } } },
    { kind = "pfn_list", fn = "bigger_squads", label = "Bigger squads", help = "Enemies arriving on foot come in bigger groups, up to 16 a wave. Left/Right picks, Enter sets it.", sel = 1, options = { { "Normal", 1 }, { "x2", 2 }, { "x3", 3 }, { "x5", 5 } } },
    { kind = "pfn_list", fn = "elites_early", label = "Elite enemies early", help = "Enemy types the story hasn't unlocked can turn up in waves. Left/Right picks, Enter sets it. May stay in your save. Save first.", sel = 1, options = { { "Unlock", true }, { "Lock those again", false } } },
    { kind = "pfn_list", class = "status_effect", fn = "forever_near", label = "Lasting effect on everyone near", help = "Everyone within 40 m has it for six hours. Left/Right picks, Enter does it. Fire and the like will kill them.", sel = 1, options = {} },
    { kind = "pfn_list", class = "status_effect", fn = "forever_me", label = "Lasting effect on you", help = "You have it for six hours or until you respawn. Left/Right picks, Enter does it. Some can trap you. Save first.", sel = 1, options = {} },
    { kind = "pfn", fn = "forever_off", label = "Lasting effects off", help = "Takes those off you and everyone now within 40 m." },
    { kind = "pfn_list", fn = "rule_near", label = "Rule on people near", help = "Puts a Boot Hill rule or any perk on everyone within 40 m, or on your homies within 100 m, until they die or you pick Take rules off. Left/Right picks, Enter does it. People who arrive later need another press. Perks use Perk strength, and the game may refuse many. Drops are a 1 in 4 chance, and many blasts at once can crash the game: Save first.", sel = 1, options = P.rule_options(PERK_LIST) },
    pset("stagger_cd", "Stagger cooldown", "How soon a stagger can follow another. Short keeps people stumbling, you included.", { { "Game's", false }, { "None", 0.01 }, { "Short", 0.15 }, { "Long", 5.0 }, { "Once a minute", 60.0 } }),
    { kind = "pfn_list", fn = "knock_near", label = "Knock everyone near down", help = "Everyone within 40 m on the floor for this long. Left/Right picks, Enter does it.", sel = 1, options = { { "3 s", 3.0 }, { "10 s", 10.0 }, { "30 s", 30.0 }, { "2 min", 120.0 } } },
    pset("always_sprint", "Always sprint", "You sprint whenever you're moving on foot. It can interrupt aiming: use Aim anywhere with it.", { { "Off", false }, { "On", true } }),
    { kind = "pfn_list", class = "char_cust_slot", fn = "mat_slot_pick", label = "Material slot", help = "The slot Item material uses. Left/Right picks, Enter sets it.", sel = 1, options = {} },
    { kind = "pfn_list", class = "char_cust_material", fn = "item_material", label = "Item material", help = "Puts one of the game's materials on Material slot's item. Left/Right picks, Enter puts it on. Many won't fit. Stays in your save: Undo my look.", sel = 1, options = {} },
    { kind = "pfn_list", fn = "no_hide_rules", label = "Clothes hide each other", help = "Choose No and a hat stops hiding your hair, a coat your shirt. Left/Right picks, Enter sets it. Change an item to see it. Expect clipping.", sel = 1, options = { { "No", true }, { "Yes", false } } },
    { kind = "pfn_list", fn = "world_idle", label = "Idle animation", help = "One of the pedestrians' idles on you. Left/Right picks, Enter plays it. The first press may need a second. Stop animation ends it.", sel = 1, options = {
  { "Mime", { "ped_world_mime", "life_stand_mime_001" } }, { "Hula hoop", { "ped_world_hoolahoop", "ped_world_hoolahoop_01" } }, { "Sit", { "interaction_sit", "life_sit_01" } }, { "Sit 2", { "interaction_sit", "life_sit_02" } },
  { "Smoke", { "ped_world_cigarette_smoking", "ped_world_cigarette_smoking_001" } }, { "Air guitar", { "ped_world_air_guitar", "life_stand_air_guitar_001" } }, { "Headbang", { "ped_world_headbang", "life_stand_headbang_001" } },
  { "Drunk", { "ped_world_drunk", "life_stand_drunk_01" } }, { "Party", { "ped_world_party", "life_stand_party_01" } }, { "Drink", { "ped_world_drink", "life_stand_drink_01" } }, { "Eat", { "ped_world_eat", "life_stand_eat_01" } },
  { "Vomit", { "ped_world_vomit", "life_stand_vomit_01" } }, { "Pee on a wall", { "ped_world_pee_on_wall", "life_stand_pee_on_wall_001" } }, { "Think", { "ped_world_think", "life_stand_think_01" } },
  { "Mariachi guitar", { "ped_world_mariachis", "ped_world_mariachis_guitar_01" } }, { "Beg", { "ped_world_hermit", "ped_world_hermit_begging_001" } }, { "Flex", { "panteros_world", "panteros_world_flexing_001" } },
  { "On the phone", { "ped_world_on_phone", "life_stand_on_phone_01" } }, { "Phone talk", { "ped_world_cellphone_talk", "life_stand_cellphone_talk_01" } }, { "Talk", { "ped_world_talking", "life_stand_talking_a" } }, { "Wait", { "ped_world_waiting", "life_stand_waiting_01" } } } },
    { kind = "pfn_list", fn = "world_idle_near", label = "Everyone near does an idle", help = "Everyone within 40 m does it and stays until End idle near. Left/Right picks, Enter starts it.", sel = 1, options = {
  { "Mime", { "ped_world_mime", "life_stand_mime_001" } }, { "Hula hoop", { "ped_world_hoolahoop", "ped_world_hoolahoop_01" } }, { "Sit", { "interaction_sit", "life_sit_01" } }, { "Sit 2", { "interaction_sit", "life_sit_02" } },
  { "Smoke", { "ped_world_cigarette_smoking", "ped_world_cigarette_smoking_001" } }, { "Air guitar", { "ped_world_air_guitar", "life_stand_air_guitar_001" } }, { "Headbang", { "ped_world_headbang", "life_stand_headbang_001" } },
  { "Drunk", { "ped_world_drunk", "life_stand_drunk_01" } }, { "Party", { "ped_world_party", "life_stand_party_01" } }, { "Drink", { "ped_world_drink", "life_stand_drink_01" } }, { "Eat", { "ped_world_eat", "life_stand_eat_01" } },
  { "Vomit", { "ped_world_vomit", "life_stand_vomit_01" } }, { "Pee on a wall", { "ped_world_pee_on_wall", "life_stand_pee_on_wall_001" } }, { "Think", { "ped_world_think", "life_stand_think_01" } },
  { "Mariachi guitar", { "ped_world_mariachis", "ped_world_mariachis_guitar_01" } }, { "Beg", { "ped_world_hermit", "ped_world_hermit_begging_001" } }, { "Flex", { "panteros_world", "panteros_world_flexing_001" } },
  { "On the phone", { "ped_world_on_phone", "life_stand_on_phone_01" } }, { "Phone talk", { "ped_world_cellphone_talk", "life_stand_cellphone_talk_01" } }, { "Talk", { "ped_world_talking", "life_stand_talking_a" } }, { "Wait", { "ped_world_waiting", "life_stand_waiting_01" } } } },
    { kind = "pfn", fn = "world_idle_near_stop", label = "End idle near", help = "Everyone within 40 m can move again." },
    { kind = "pfn", fn = "sit_chair", label = "Sit down", help = "Sits on what's nearest within 8 m, or brings a chair for a second press. It uses whatever is nearest, shops too." },
    { kind = "pfn", fn = "use_near_row", label = "Use nearest", help = "Uses the nearest thing you could interact with, within 6 m, even if the game isn't offering it." },
    { kind = "pfn_list", fn = "payout", label = "Cash from kills", help = "How much money people and caches drop. Left/Right picks, Enter sets it. Stays in your save.", sel = 1, options = { { "Normal", { 3, 1 } }, { "x2", { 3, 2 } }, { "x5", { 3, 5 } }, { "x20", { 3, 20 } } } },
    { kind = "pfn_list", fn = "payout", label = "XP from kills", help = "How much XP a kill gives. Left/Right picks, Enter sets it. Levels gained stay in your save.", sel = 1, options = { { "Normal", { 2, 1 } }, { "x2", { 2, 2 } }, { "x5", { 2, 5 } }, { "x20", { 2, 20 } } } },
    { kind = "pfn_list", fn = "level_curve", label = "XP needed per level", help = "How much XP a level takes, from your next XP on. Left/Right picks, Enter sets it. Levels gained stay in your save.", sel = 1, options = { { "Game's", 1 }, { "x0.5", 0.5 }, { "x0.25", 0.25 }, { "x0.1", 0.1 }, { "x2", 2 } } },
    { kind = "pfn_list", fn = "activity_clock", label = "Activity time limits", help = "Time limits in Mayhem, Insurance Fraud, Pony Express and the like. Left/Right picks, Enter sets it before you start one.", sel = 1, options = { { "Game's", 1 }, { "x0.5", 0.5 }, { "x2", 2 }, { "x5", 5 }, { "x20", 20 } } },
    { kind = "pfn_list", fn = "video_on", label = "Video on screens", help = "Plays one of the game's videos in the world. Left/Right picks, Enter plays it. You may only hear it: few screens are wired up.", sel = 1, options = { { "Idols TV", "ct_idols_tv" }, { "Laptop", "ct_icon_laptop" }, { "Pals channel", "ct_pals_mid_channel" }, { "Side map", "ct_side_map" }, { "Promo", "lp1_promo" }, { "Epilogue lyrics", "ct_epilogue_lyrics_shot04_thru_16" }, { "Chalupacabra ad", "brush_chalupacabra_final" }, { "Laundromat ad", "brush_laudromat_final" }, { "Jim Rob's ad", "brush_jim_robs_final" } } },
    { kind = "pfn", fn = "video_off", label = "Video off", help = "Stops the video." },
    { kind = "pfn_list", fn = "fake_objective", label = "Fake objective", help = "Puts words on the mission HUD. Left/Right picks, Enter shows it. Nothing happens when the clock runs out.", sel = 1, options = {
  { "Kill the mayor", { "Civic duty", "Kill the mayor", false } }, { "Find the sandwich", { "Lunch", "Find the sandwich", 120 } }, { "Do crime", { "Santo Ileso", "Do crime", false } }, { "Don't look back", { "Run", "Don't look back", 30 } },
  { "Mission passed", "done" }, { "Clear it", "clear" } } },
    pset("free_cam", "Free camera", "The camera flies free while you stay put. Left stick or W A S D, RT or Space up, LT or Ctrl down, stick click or Shift for fast. You can't walk.", { { "Off", false }, { "On", true } }),
    { kind = "car_group", src = "parts", label = "Part slot", help = "Hood, bumper and so on, locked ones too. Enter reads your vehicle, then Left/Right picks.", sel = 1, options = { { "Press Enter", false } } },
    { kind = "car_item", src = "parts", label = "Part", help = "A part for Part slot. Left/Right picks, Enter fits it. * is what's on now.", sel = 1, options = { { "none", false } } },
    { kind = "car_group", src = "paint", label = "Paint area", help = "Which material and palette Paint colour uses. Enter reads your vehicle, then Left/Right picks.", sel = 1, options = { { "Press Enter", false } } },
    { kind = "car_item", src = "paint", label = "Paint colour", help = "A colour for Paint area. Left/Right picks, Enter paints it.", sel = 1, options = { { "none", false } } },
    { kind = "car_group", src = "tex", label = "Pattern area", help = "Which group Pattern uses. Enter reads your vehicle, then Left/Right picks.", sel = 1, options = { { "Press Enter", false } } },
    { kind = "car_item", src = "tex", label = "Pattern", help = "A pattern from Pattern area. Left/Right picks, Enter puts it on. Only unlocked ones.", sel = 1, options = { { "none", false } } },
    pset("car_rgb_mat", "Any colour: material", "Which material Any colour paints. The body is often not the first.", { { "1", 0 }, { "2", 1 }, { "3", 2 }, { "4", 3 }, { "5", 4 }, { "6", 5 }, { "7", 6 }, { "8", 7 } }),
    { kind = "pfn_list", fn = "car_rgb", label = "Any colour", help = "Paints the material on Any colour: material. Left/Right picks, Enter paints it.", sel = 1, options = { { "Black", { 0, 0, 0 } }, { "White", { 255, 255, 255 } }, { "Red", { 255, 0, 0 } }, { "Purple", { 128, 0, 255 } }, { "Saints purple", { 90, 13, 153 } }, { "Gold", { 255, 191, 25 } }, { "Hot pink", { 255, 25, 153 } }, { "Toxic green", { 51, 255, 25 } } } },
    pset("wheel_guns", "Fire vehicle's guns", "On a vehicle with guns, hold R3 or G to fire them, from any seat. They fire where the barrel points, which doesn't turn. Can crash.", { { "Off", false }, { "On", true } }),
    { kind = "pfn_list", fn = "car_mount", label = "Swap vehicle gun", help = "Replaces this vehicle's gun, on a vehicle that has one. Left/Right picks, Enter swaps it. Can crash. Save first.", sel = 1, options = { { "Marshall manned", [[data\sr_city\spawnables\weapons\turret\weapon_marshall_turret_manned]] }, { "Panteros manned", [[data\sr_city\spawnables\weapons\turret\weapon_panteros_manned_turret_ct_road]] }, { "Tank turret", [[data\sr_city\spawnables\weapons\turret\weapon_veh_tank_turret]] }, { "Jet bike", [[data\sr_city\spawnables\weapons\turret\weapon_veh_jet_bike_turret]] }, { "Nahualli heli", [[data\sr_city\spawnables\weapons\turret\weapon_veh_nahualli_heli_fighter_turret]] }, { "Nahualli manned", [[data\sr_vanguard\spawnables\weapons\turret\weapon_nuhalli_manned_turret]] } } },
    { kind = "spawn_prop", label = "Spawn standing turret", help = "Puts one in front of you; walk up to get on. Left/Right picks, Enter spawns it. Get off before removing props.", sel = 1, options = { { "Marshall", "turret_standalone_ring_marshall_01" }, { "Panteros", "turret_standalone_ring_panteros_01" }, { "Nahualli", "turret_standalone_ring_nahualli" } } },
    pset("seat_guns", "Shoot from any seat", "Guns out in every seat, on vehicles that forbid it too. Pilots and tank drivers stay as they are. Some seats have no animation.", { { "Off", false }, { "On", true } }),
    pset("car_bounce", "Bouncy car", "Your vehicle bounces off walls. Wheels don't bounce, only the body.", { { "Game's", false }, { "Some", 0.5 }, { "Rubber", 0.9 }, { "Super", 1.5 } }),
    pset("car_max_speed", "Vehicle speed limit", "The physics limit on your vehicle's speed. Its engine may not reach a higher one.", { { "Game's", false }, { "x0.5", 0.5 }, { "x2", 2 }, { "x5", 5 } }),
    pset("car_lin_damp", "Air drag", "How fast your vehicle loses speed on its own.", { { "Game's", false }, { "None", 0 }, { "Some", 0.5 }, { "Heavy", 2 }, { "Treacle", 8 } }),
    pset("car_ang_damp", "Spin drag", "How fast your vehicle stops spinning.", { { "Game's", false }, { "None", 0 }, { "Heavy", 3 }, { "Won't spin", 20 } }),
    pset("car_time", "Vehicle time", "Your vehicle's own clock. Unproven: may do nothing.", { { "Game's", false }, { "x0.5", 0.5 }, { "x2", 2 } }),
    pset("car_com", "Weight balance", "Moves the centre of mass. Low is hard to flip, high rolls, nose or tail flips forward or back.", { { "Game's", false }, { "Low", { 0, -0.7, 0 } }, { "High", { 0, 1.2, 0 } }, { "Nose heavy", { 0, 0, 1.5 } }, { "Tail heavy", { 0, 0, -1.5 } } }),
    pset("flight_mode", "Flight mode", "How this aircraft flies. Refused if it has no such settings. Controls change with it, except VTOL. Risky to change in the air.", { { "Game's", false }, { "Helicopter", 0 }, { "Fixed-wing", 1 }, { "VTOL", 2 } }),
    pset("shot_teleport", "Teleport on shot", "Each shot takes you where the crosshair lands, or sets a portal pair: two shots, walk into either. Portals are invisible. Teleport style: Instant.", { { "Off", false }, { "Go where I shoot", "go" }, { "Portal pair", "portal" } }),
    { kind = "pfn", fn = "portal_clear", label = "Clear portals", help = "Removes both portals." },
    { kind = "pfn_list", fn = "black_hole", label = "Black hole", help = "Pulls people and vehicles within 40 m of the crosshair for 8 s, then a blast. Left/Right picks, Enter fires. Costs frames. Save first.", sel = 1, options = { { "Mild", 0.6 }, { "Strong", 1.5 }, { "Extreme", 4 }, { "Stop", false } } },
    pset("guns_anywhere", "Any gun in vehicles and surfing", "Seats and car surfing stop limiting your guns. A mission's own limit stays. Launchers and melee may look wrong. Off applies next time you sit.", { { "Off", false }, { "On", true } }),
    pset("homing", "Homing rounds", "Launcher shots and Special rounds chase what's under the crosshair, or near it. Bullets don't change.", { { "Off", false }, { "Gentle", 0.06 }, { "Normal", 0.15 }, { "Hard", 0.4 } }),
    { kind = "pfn_list", fn = "shoot_prop", label = "Shoot prop", help = "Fires a prop from the camera. Left/Right picks, Enter fires; the first press loads it. Fixed props just hang there. Remove all props clears them.", sel = 1, options = SPAWN_PROPS },
    pset("prop_gun", "Prop gun", "Every shot also throws this. No more than 6 in the air.", PROP_GUN_OPTIONS),
    { kind = "pfn", fn = "dual_gun", label = "Dual wield this gun", help = "A second gun of the same kind. Enter with a gun out, again to go back to one. Only automatics and shotguns fire both. Can crash. Save first.", },
    pset("fire_from", "Shots start from", "Shots start from your hand or head instead of the muzzle. Comes on within half a second for each gun you take out.", { { "Muzzle", false }, { "Right hand", "Right_Hand" }, { "Left hand", "Left_Hand" }, { "Head", "Head" } }),
    { kind = "pfn_list", fn = "hold_like", label = "Hold gun like", help = "The gun in your hands takes this gun's poses and swaps out once. Left/Right picks, Enter sets it. NPCs with your gun change too, until Game's or a restart.", sel = 1, options = { { "Game's", "game" }, { "Pistol", "weapon_basic_pistol" }, { "Dual pistols", "weapon_parent_dual" }, { "Dual SMGs", "dual_smg_idols_01" }, { "Assault rifle", "rifle_assault_boothill" }, { "Sniper", "rifle_sniper_boothill" }, { "Shotgun", "weapon_parent_shotgun" }, { "Tactical SMG", "smg_tactical_boothill" }, { "RPG", "launcher_rpg_boothill" }, { "Shoulder box", "launcher_shoulder_box_boothill" }, { "Grenade launcher", "weapon_idol_icon_launcher_boothill" }, { "Minigun", "gatlin_marshall_basic" }, { "Flamethrower", "special_panteros_flamethrower" }, { "Crossbow", "rifle_wastelanders_crossbow" }, { "Thrustbuster", "weapon_special_thrustbuster" }, { "Tac pistol", "pistol_tac" }, { "Hand cannon", "pistol_hand_cannon" }, { "Feather pistol", "pistol_idols_01" }, { "Taser", "pistol_police_taser" }, { "Pistol SMG", "smg_pistol" }, { "Heavy SMG", "smg_heavy_basic_boothill" }, { "Hi-volume SMG", "smg_hi_volume_boothill" }, { "Burst rifle", "rifle_generic_burst" }, { "Marshall auto rifle", "rifle_marshall_ct_marsh_auto_boothill" }, { "Marshall carbine", "rifle_marshall_sniper" }, { "Elephant rifle", "rifle_elephant_boothill" }, { "Focus rifle", "rifle_focus_boothill" }, { "Ant rifle", "rifle_ant" }, { "Police shotgun", "shotgun_police" }, { "Cowboy shotgun", "shotgun_cowboy" }, { "Tac shotgun", "shotgun_tac_semi_auto_boothill" }, { "Sawed-off", "weapon_panteros_grunt_shotgun_boothill" }, { "Marshall shotgun", "shotgun_marshall_tac_boothill" }, { "Marshall launcher", "marshall_burst_rocket" }, { "Pinata launcher", "special_pinatabomb_launcher_boothill" }, { "Platethrower", "weapon_launcher_platethrower_boothill" }, { "Chancla", "special_la_chancla" }, { "Poi", "weapon_idols_raver_thrown" }, { "DJ staff", "temp_idols_melee_staff_player" }, { "Fist cannon", "melee_fist_cannon_boothill" }, { "Bare fists", "weapon_melee_fists_prisoner" }, { "One-hand melee", "weapon_parent_melee_light" }, { "Two-hand melee", "weapon_parent_melee_heavy" }, { "Twinkle bat", "melee_idols_twinklebat" }, { "Shovel", "melee_shovel" }, { "Pipe wrench", "melee_wrench" }, { "Longsword", "test_melee_sword" }, { "Marshall minigun", "temp_marshall_minigun_player" }, { "Rage", "melee_panteros_dust_storm" }, { "Panic", "melee_panic" }, { "Rifle", "weapon_parent_full_auto" }, { "Anvil gun", "weapon_anvil_gun" }, { "Ban hammer", "weapon_ban_hammer" }, { "Frost SMG", "frostlander_smg" }, { "Frost axe", "frostlander_axe" }, { "Haunted rifle", "weapon_rifle_haunted_dlc" }, { "Boot Hill LMG", "weapon_lmg_dlc" }, { "DMR", "weapon_dlc_rifle_dmr" }, { "Pistol shotgun", "weapon_dlc_pistol_shotgun" } } },
    pset("skip_intro", "Skip intro", "Skips the logos at start-up, if you have a save. Works from the next start: use Save tweaks for next time.", { { "Off", false }, { "On", true } }),
    { kind = "special_person", label = "Special person", help = "A boss, ghost, skeleton, mascot or other hard-to-find character. Left/Right picks, Enter spawns them. Some may just stand there.", sel = 1, options = { { "Sergio, Panteros boss", 0xDCE51BE6 }, { "Atticus, Marshall boss", 0x034278F8 }, { "Atticus, formal", 0xAAA6FDA8 }, { "Gwen", 0x28A8EC7B }, { "Gwen, battle gear", 0x15908C61 }, { "Gwen, gala", 0xDC5AF17A }, { "Dust King", 0x1D515B0E }, { "Nahualli boss", 0x0C716465 }, { "Nahualli, prison", 0x7DA925AA }, { "Wally", 0x67B9A90C }, { "Frostlander Queen", 0xBC931455 }, { "Karl as Thegn", 0x5BCBA1B8 }, { "Myra Starr", 0x54F025E6 }, { "JimRob, Marshall", 0xD6942A10 }, { "Evil spirit", 0xB20AA33D }, { "Doc Ketchum", 0x6A6005F3 }, { "Genki", 0x7A86E560 }, { "Mr Big", 0x7755874D }, { "John Blande", 0x5237E8B8 }, { "Stab Lincoln", 0x1A53AAB9 }, { "Skeleton, red male", 0x9DBA3030 }, { "Skeleton, red female", 0x14E5AF45 }, { "Skeleton, blue male", 0x077C1307 }, { "Skeleton, blue female", 0x2685E4C5 }, { "Skeleton, green male", 0xD4C79E63 }, { "Skeleton, green female", 0xB41D6640 }, { "Chicken, female", 0x2915B12E }, { "Thrall, female", 0x39F1A42A }, { "Ghost, victim", 0x4B8E3E08 }, { "Ghost Saint 2", 0x513FDC41 }, { "Ghost Saint 3", 0x7C03058B }, { "Ghost Saint 4", 0xB9A43B05 }, { "Oldesteel mascot", 0xAF39DC23 }, { "Twisty mascot", 0xA56D935B }, { "Roadrunner mascot", 0xA09AD9B5 }, { "Hostile mascot 1", 0x3693E344 }, { "Hostile mascot 2", 0x41225090 }, { "Hostile mascot 3", 0x7A992D13 }, { "Hostile mascot 4", 0x10F7555B }, { "Hostile mascot 5", 0x00D35732 }, { "Hostile mascot 6", 0x43EC16C0 }, { "Mannequin 2", 0x820BC491 }, { "Furry 2", 0x697FF87C }, { "Gimp 1", 0x23B092ED }, { "Gimp 2", 0xE664D346 }, { "Grindler Davis", 0x878F797C }, { "Movie star", 0x52343131 }, { "Shotdog", 0x54BEFCD2 }, { "Assassin, female", 0xA6B16C9D }, { "Assassin, male", 0x36EFBC36 }, { "Furloughed soldier", 0x8302786E }, { "Chicken", 0x14BECB08 }, { "Big chicken", 0x3D30397E }, { "Mime", 0x3AC8420F }, { "Grandma", 0x56B3FA95 }, { "Necromancer", 0x081D88E9 }, { "Thrall", 0x7FE1AE66 }, { "Panteros Gigante", 0x8046C9D3 }, { "Wrestler mascot", 0xC9EC39AC }, { "Thumper", 0xF20C6DB8 }, { "Idols enforcer, cop", 0x749A38DE }, { "Police tank crew", 0x53F6572A }, { "Ghost, businessman", 0x58421D8D }, { "Ghost, conductor", 0x6E8323A5 }, { "Ghost, girl", 0x7F26949D }, { "Ghost, prospector", 0xC05EF71E }, { "Ghost Saint", 0x9498E2CF }, { "Coyote", 0x7932AF07 }, { "Hotdog mascot", 0x9470E338 }, { "Hot sauce mascot", 0x02EC61BD }, { "Ketchup mascot", 0xEA958148 }, { "Bunny mascot", 0x2761093B }, { "Cat mascot", 0x795A97A1 }, { "Coyote mascot", 0x02A90DA4 }, { "Dog mascot", 0x32D42A32 }, { "Leopard mascot", 0xB6E229D9 }, { "Alien", 0x554C38BC }, { "Bodysuit", 0xB491B1CF }, { "Taco terror", 0x2109925B }, { "Furry Saint", 0x50F2C4B9 }, { "Hitman Saint", 0xFE75544E }, { "Nixon", 0x28CED4F9 }, { "Reagan", 0x1F2F0947 }, { "Mannequin", 0x19290B59 }, { "Hazmat", 0x109C2A4D }, { "GI", 0xBB62C8DB }, { "Scrubs", 0x0D7B17F6 }, { "Dancer", 0xFE77057A }, { "Sandy Kraken", 0x5FB8E1E8 } } },
    { kind = "crowd", label = "Spawn 10 of that person", help = "Ten of the person picked on Spawn person, in a ring around you." },
    { kind = "random_people", label = "Spawn 10 random people", help = "Ten of the game's characters, picked at random, around you." },
    { kind = "despawn", label = "Remove spawned people", help = "Removes everyone the menu spawned." },
    { kind = "cash_drop", label = "Drop cash", help = "Drops real cash 8 m ahead of you. Left/Right picks how much, Enter drops it. Stays in your save.", sel = 1, options = { { "$1,000", 1000 }, { "$10,000", 10000 }, { "$100,000", 100000 } } },
    { kind = "weapon_drop", label = "Drop weapon", help = "Drops a weapon 6 m ahead of you; walk onto it to collect it. Left/Right picks, Enter drops it. Stays in your save.", sel = 1, options = {} },
    pset("rain", "Money rain", "Cash falls all around you, $250 a pile. What you pick up stays in your save.", { { "Off", false }, { "Light", 30 }, { "Heavy", 8 } }),
    { kind = "unlock", key = "icons", label = "Show activities on the map", help = "Shows diversions, flashpoints and discoverables on the map. Enter twice. Save first." },
    { kind = "reaction", label = "Make everyone near react", help = "Everyone within 40 m cheers, laughs, takes pics and so on. Left/Right picks, Enter does it.", sel = 1,
      options = { { "Cheer", "cheer" }, { "Laugh", "laugh" }, { "Taunt", "taunt" }, { "Take pics", "take pics" }, { "Wave", "wave" }, { "Hype", "hype emote" }, { "Angry", "angry" }, { "Disgusted", "disgusted" } } },
    { kind = "arms", armed = false, label = "Disarm everyone near", help = "People within 40 m can't use their guns. New arrivals still can." },
    { kind = "arms", armed = true, label = "Re-arm everyone near", help = "Gives people within 40 m their guns back." },
    { kind = "crowd_act", key = "ragdoll", label = "Trip everyone near", help = "Everyone within 40 m falls over." },
    { kind = "crowd_act", key = "kill", label = "Kill everyone near", help = "Everyone within 40 m dies, as if you shot them. Mission characters are left alone." },
    { kind = "crowd_act", key = "fire", label = "Set everyone near on fire", help = "Everyone within 40 m bursts into flames, as if you lit them." },
    { kind = "crowd_act", key = "stun", label = "Stun everyone near", help = "Everyone within 40 m is stunned where they stand." },
    { kind = "crowd_act", key = "hostile", label = "Make everyone near hostile", help = "Everyone within 40 m turns on you for an hour." },
    { kind = "crowd_act", key = "friendly", label = "Make everyone near friendly", help = "Everyone within 40 m joins the Saints' side." },
    { kind = "crowd_act", key = "follow", label = "Make everyone near follow you", help = "Everyone within 40 m joins your side and stays with you." },
    { kind = "crowd_act", key = "dance", label = "Make everyone near dance", help = "Everyone within 40 m starts dancing." },
    pset("no_guns", "Gangs and police without guns", "Everyone near you keeps being disarmed, new arrivals too.", { { "Off", false }, { "On", true } }),
    pset("side_gang", "Gang on your side", "This gang counts as your ally. Use No notoriety too, as notoriety still sends them after you.", { { "None", false }, { "Idols", "idol" }, { "Panteros", "panteros" }, { "Marshal", "marshal" }, { "Police", "police" }, { "All", "all" } }),
    pset("saints_enemies", "Saints are enemies", "Saints in the world count you as hostile.", { { "Off", false }, { "On", true } }),
    pset("forget_fast", "Notoriety fades fast", "Out of sight, notoriety clears in a second instead of the game's seven.", { { "Off", false }, { "On", true } }),
    { kind = "crowd_act", key = "float", label = "Float everyone near", help = "Everyone within 40 m floats up about 14 m, then comes back down." },
    { kind = "crowd_act", key = "dissolve", label = "Dissolve everyone near", help = "Everyone within 40 m dissolves and is gone in 2 seconds." },
    { kind = "crowd_act", key = "toxic", label = "Poison everyone near", help = "Everyone within 40 m gets the toxic effect and loses health until they drop, about 6 s." },
    pset("no_call_ins", "No reinforcements", "Wanted factions don't call in more people.", { { "Off", false }, { "On", true } }),
    pset("no_roadblocks", "No roadblocks", "No roadblocks when you're wanted.", { { "Off", false }, { "On", true } }),
    pset("no_escape", "Can't lose notoriety", "You can't evade a pursuit by getting away.", { { "Off", false }, { "On", true } }),
    { kind = "crowd_act", key = "cars", label = "Blow up cars near", help = "Every vehicle within 40 m explodes, except the one you're in." },
    { kind = "wdset", key = "empty_streets", label = "Empty streets", help = "No more people or traffic appear; the ones out there go as you leave them.", options = { { "Off", false }, { "On", true } }, sel = 1, save_key = "world.empty_streets" },
    toggle("low_gravity", "Low gravity", "Everything floats a little."),
    toggle("ped_agro", "Angry pedestrians", "People on the street turn on you."),
    { kind = "wdset", key = "never_wanted", label = "No notoriety", help = "Clears notoriety as soon as you get it: from anyone, the police and Marshal, or gangs.",
      options = { { "Off", false }, { "By anyone", "all" }, { "By police", "police" }, { "By gangs", "gangs" } }, sel = 1, save_key = "world.never_wanted" },
    choice("Police", "Raises or clears your notoriety with them; Max goes to the top. Left/Right picks, Enter does it.", { { "Raise", "increase_police" }, { "Clear", "clear_police" }, { "Max", "increase_police", max = true } }),
    choice("Idols", "Raises or clears your notoriety with them; Max goes to the top. Left/Right picks, Enter does it.", { { "Raise", "increase_idols" }, { "Clear", "clear_idols" }, { "Max", "increase_idols", max = true } }),
    choice("Marshal", "Raises or clears your notoriety with them; Max goes to the top. Left/Right picks, Enter does it.", { { "Raise", "increase_marshal" }, { "Clear", "clear_marshal" }, { "Max", "increase_marshal", max = true } }),
    choice("Los Panteros", "Raises or clears your notoriety with them; Max goes to the top. Left/Right picks, Enter does it.", { { "Raise", "increase_panteros" }, { "Clear", "clear_panteros" }, { "Max", "increase_panteros", max = true } }),
    difficulty(0, "player health"), difficulty(1, "player damage"), difficulty(2, "enemies"), difficulty(3, "vehicles"),
    difficulty(4, "notoriety"), difficulty(5, "ammo reserve"), difficulty(6, "timer speed"),
  } },
  { name = "Visual", rows = {
    pset("glow_weapons", "Dropped gun glow", "The glow on guns people drop. Only new drops change.", { { "Game's", false }, { "Off", "Off" }, { "Green", "Green" }, { "Cyan", "Cyan" }, { "White", "White" }, { "Violet", "Violet" }, { "Gold", "Gold" }, { "Purple", "Purple" }, { "Orange", "Orange" } }),
    pset("glow_cash", "Cash glow", "The glow on cash on the ground. Only new drops change.", { { "Game's", false }, { "Off", "Off" }, { "Green", "Green" }, { "Cyan", "Cyan" }, { "White", "White" }, { "Violet", "Violet" }, { "Gold", "Gold" }, { "Purple", "Purple" }, { "Orange", "Orange" } }),
    pset("glow_ammo", "Ammo glow", "The glow on ammo boxes on the ground. Only new drops change.", { { "Game's", false }, { "Off", "Off" }, { "Green", "Green" }, { "Cyan", "Cyan" }, { "White", "White" }, { "Violet", "Violet" }, { "Gold", "Gold" }, { "Purple", "Purple" }, { "Orange", "Orange" } }),
    pset("glow_coins", "Coin glow", "The glow on Boot Hill gold coins. Only new drops change.", { { "Game's", false }, { "Off", "Off" }, { "Green", "Green" }, { "Cyan", "Cyan" }, { "White", "White" }, { "Violet", "Violet" }, { "Gold", "Gold" }, { "Purple", "Purple" }, { "Orange", "Orange" } }),
    choice("Screen filter", "The game's screen filters. Left/Right picks; it applies after a moment.", {
      { "Off", false }, { "Black & white", "screen_effect_black_white" }, { "Retro", "screen_effect_retro" },
      { "Night vision", "screen_effect_night_vision" }, { "Old-timey", "screen_effect_old_timey" },
      { "Vapor", "screen_effect_vapor" }, { "Western", "screen_effect_western" }, { "Steamboat", "screen_effect_steamboat" } }, "filter"),
    opt("Field of view", "The game's camera field of view option, wider than its menu allows at the top.",
      "option_get_camera_fov_offset()", "option_set_camera_fov_offset(%s)",
      { { "0", 0 }, { "0.25", 0.25 }, { "0.5", 0.5 }, { "0.75", 0.75 }, { "1", 1 }, { "1.5", 1.5 } }),
    opt("Camera shake", "The game's camera shake option.", "option_get_camera_shake_enabled()", "option_set_camera_shake_enabled(%s)", { { "On", 1 }, { "Off", 2 } }),
    opt("Looping camera shake", "The game's looping camera shake option: engines, idle sway.", "option_get_looping_camera_shake_enabled()", "option_set_looping_camera_shake_enabled(%s)", { { "On", 1 }, { "Off", 2 } }),
    opt("Camera bobbing", "The game's camera bobbing option.", "option_get_camera_bobbing_enabled()", "option_set_camera_bobbing_enabled(%s)", { { "On", 1 }, { "Off", 2 } }),
    gchoice("Shoulder camera", "Moves the camera over a shoulder, or back to the middle. Left/Right picks; it applies after a moment.", {
      { "Centred", "gml_set_camera_ndc_offset(0, 0) return 'centred'" }, { "Right shoulder", "gml_set_camera_ndc_offset(0.45, 0) return 'right'" },
      { "Left shoulder", "gml_set_camera_ndc_offset(-0.45, 0) return 'left'" } }),
    { kind = "camset", key = "turn", label = "Turn speed", help = "How fast the camera turns, mouse and controller, past the options' top.", options = { { "Game's", 1 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 } }, sel = 1, save_key = "camera.turn" },
    { kind = "camset", key = "bright", label = "Brightness", help = "While it's on, the game stops adjusting brightness by itself, indoors or at night.", options = { { "Game's", 0 }, { "Brighter", -1 }, { "Much brighter", -2 }, { "Darker", 1 }, { "Much darker", 2 } }, sel = 1 },
    pset("render_hide", "Stop drawing", "Stops drawing the sky, particles, shadows or tree billboards.", { { "Nothing", false }, { "Sky", 0x8000 }, { "Particles", 0x4000 }, { "Shadows", 0x1000 }, { "Far trees", 0x20000 } }),
    gchoice("Low health screen", "The red screen effects when you're hurt. Left/Right picks; it applies after a moment.", { { "On", [[gml_ui_gem_raise_event("ui_enable_hud_full_screen_effects", 1, "enable", true) return "on"]] }, { "Off", [[gml_ui_gem_raise_event("ui_enable_hud_full_screen_effects", 1, "enable", false) return "off"]] } }),
    gchoice("Show only people", "Hides the world's background, as the game's demo mode does. Left/Right picks; it applies after a moment.", { { "Off", [[demo_hide_background(false) return "off"]] }, { "On", [[demo_hide_background(true) return "on"]] } }),
    pset("cam_distance", "Camera distance", "How far behind you the camera sits. First person is from inside your head; aiming stays as it was.", { { "Game's", false }, { "First person", 0.01 }, { "Close", 1.5 }, { "Far", 6 }, { "Very far", 14 } }),
    gchoice("Letterbox", "Black bars, as in the game's cutscenes. Left/Right picks; it applies after a moment.", { { "Off", [[gml_ui_gem_raise_event("segue_letterbox_end") return "off"]] }, { "On", [[gml_ui_gem_raise_event("segue_letterbox_begin") return "on"]] } }),
    gcall("Photo mode", "The game's photo mode: a free camera. Close the menu to move it; press again to leave.", "cell_photo_mode_toggle() return cell_photo_mode_is_active() and 'on' or 'off'"),
    { kind = "hud", label = "Hide HUD", help = "Hides the HUD the way the game's own option does.", options = { { "Off", false }, { "On", true } }, sel = 1, save_key = "visual.hide_hud" },
  } },
  { name = "Co-op", rows = {
    { kind = "coop", act = "session", label = "Session", help = "Solo, host or guest, as the game sees it. Enter says who's with you and how many are connected." },
    { kind = "coop", act = "goto", label = "Go to partner", help = "Puts you beside your partner, or brings your vehicle if you're in one." },
    { kind = "coop", act = "pin", label = "Waypoint on partner", help = "Puts your waypoint on your partner, and it follows them. Enter again clears it. It replaces any waypoint you had." },
    { kind = "revive_me", label = "Revive me", help = "Stands you back up when you're down, without waiting for your partner." },
    opt("Partner friendly fire", "The pause menu's co-op friendly fire: how much you and your partner can hurt each other.", "option_get_coop_friendly_fire()", "option_set_coop_friendly_fire(%s)", { { "Off", 0 }, { "Half", 1 }, { "Full", 2 } }),
    opt("Pranks from partner", "The pause menu's setting: whether your partner's pranks can land on you.", "option_get_local_pranking_enabled()", "option_set_local_pranking_enabled(%s)", { { "On", 1 }, { "Off", 2 } }),
    { kind = "coop", act = "open", label = "Open to co-op", help = "Whether your game takes a partner. Enter or Left/Right changes it." },
    { kind = "coop", act = "wait", label = "Stop waiting for partner", help = "Ends the game's wait for a partner who isn't coming. Does nothing when it isn't waiting." },
    { kind = "coop", act = "error", label = "Last co-op error", help = "Enter shows the game's last connection error in words, and clears it." },
    { kind = "coop", act = "leave", confirm = true, label = "Leave co-op", help = "Ends the session the way the game's own screens do. Enter twice." },
    { kind = "coop", act = "mark", label = "Mark the co-op log", help = "Puts a mark in TweakMenu\\coop_log.txt, so a drop or glitch is easy to find. The log has no names in it." },
    { kind = "mset", key = "coop_safe", save_key = "coop_safe", label = "Safety limits", help = "On: with a partner in, rows that could break the session stop, and come back after. Off: every row works, at your own risk.", options = { { "On", true }, { "Off", false } }, sel = 1 },
    table.unpack(Co.balance_rows)
  } },
  { name = "Settings", rows = {
    gcall("Skip cutscene", "Skips the cutscene that's playing.", "cinematic_skip() return 'skipped'"),
    gcall("Pause / resume cutscene", "Pauses the cutscene that's playing, or resumes it.", "if rawget(_G, 'SR5TM_CINE_PAUSED') then cinematic_resume() rawset(_G, 'SR5TM_CINE_PAUSED', nil) return 'resumed' else cinematic_pause() rawset(_G, 'SR5TM_CINE_PAUSED', true) return 'paused' end"),
    gcall("Quick save", "The game's autosave, now. Needs Autosave on in the game's options.", "game_save_request_autosave() return 'saving'"),
    gcall("Load last save", "Loads your newest save. Unsaved progress is lost. Enter twice.", "gml_ui_save_game_request_load_newest() return 'loading'", true),
    opt("Tutorial popups", "The game's tutorial popups option. Off is none.", "options_get_tutorial_frequency()", "options_set_tutorial_frequency(%s)", { { "Off", 0 }, { "1", 1 }, { "2", 2 }, { "3", 3 } }),
    { kind = "mset", key = "tweaks_paused", label = "Pause all tweaks", help = "Paused: every menu tweak back to the game's for now. No: they all come back. Cheats stay.", options = { { "No", false }, { "Paused", true } }, sel = 1 },
    { kind = "mset", key = "menu_still", label = "Keep moving in the menu", help = "On: you can still move, look and drive with the menu open. Off: nothing at all reaches the game while it's up.", options = { { "On", false }, { "Off", true } }, sel = 1, save_key = "menu.menu_still" },
    { kind = "mset", key = "rb_hold", label = "Hold RB back", help = "On: RB reaches the game 0.15 s late, so opening the menu with RB + D-pad Down doesn't also press RB in the game. Off: RB is instant.", options = { { "Off", false }, { "On", 150 } }, sel = 1, save_key = "menu.rb_hold" },
    { kind = "profile", label = "Profile", help = "Saved sets of tweaks. Left/Right picks one. Edit the name= line in TweakMenu\\profile_1.txt to rename it, or pass the file to someone." },
    { kind = "profile_load", label = "Load profile", help = "Every menu tweak goes to what the profile holds and the rest back to the game's. Enter twice. It lasts until you quit: Save tweaks for next time keeps it." },
    { kind = "profile_save", label = "Save to profile", help = "Puts the tweaks that are on now into the profile picked above. Enter, and Enter twice over one that's in use." },
    { kind = "profile_delete", label = "Delete profile", help = "Deletes the profile picked above. Enter twice." },
    { kind = "mset", key = "hold_back", label = "Hold Back opens the menu", help = "Hold Back (View) for a second to open or close the menu. The game sees it too.", options = { { "Off", false }, { "On", true } }, sel = 1, save_key = "menu.hold_back" },
    { kind = "clean", label = "Keep my save clean", help = "Rows marked * don't mark your save. Achievements pause only while one is on." },
    { kind = "opacity", label = "Menu opacity", help = "How dark the panel behind the menu is." },
    { kind = "active", label = "What's on", help = "Lists every tweak and cheat that's on right now." },
    { kind = "all_off", label = "Turn every cheat off", help = "Switches off every cheat from the Cheats tab that's on." },
    { kind = "normal", label = "Everything back to normal", help = "Every menu tweak back to the game's, pressed rows and Game data too. Cheats, game options and your save stay. Enter twice." },
    { kind = "save_now", label = "Save tweaks for next time", help = "Your tweaks last until you quit. This keeps them for the next start." },
    { kind = "forget", label = "Forget saved tweaks", help = "Clears what Save tweaks for next time keeps, so the next start is fresh." },
    { kind = "close", label = "Close menu", help = "F5, or hold RB and press D-pad Down, opens it again." },
  } },
}

-- Rows that are settings rather than one-off actions: picking with
-- Left/Right applies them (after a short pause, so scrolling past options
-- doesn't fire each one). Actions (spawn, teleport, give, unlock) still wait
-- for Enter.
local APPLY_ON_PICK = { ["Weather"] = true, ["Time of day"] = true, ["Screen filter"] = true, ["Shoulder camera"] = true, ["Letterbox"] = true, ["Low health screen"] = true, ["Show only people"] = true, ["Material slot"] = true }
for _, t in ipairs(TABS) do for _, r in ipairs(t.rows) do if APPLY_ON_PICK[r.label] then r.apply = true end end end

-- The rows grouped: each tab is a list of pages, then rows of its own. "Cheats" holds
-- the game's own phone cheats. A row not named here stays at the end of its tab.
-- Rows whose text is built in a helper: new label and help by old label.
local WORDS = {
  ["Difficulty: player health"] = { "Difficulty: player health", "The pause menu's custom slider. Stays in your save." },
  ["Difficulty: player damage"] = { "Difficulty: player damage", "The pause menu's custom slider. Stays in your save." },
  ["Difficulty: enemies"] = { "Difficulty: enemies", "The pause menu's custom slider. Stays in your save." },
  ["Difficulty: vehicles"] = { "Difficulty: vehicles", "The pause menu's custom slider. Stays in your save." },
  ["Difficulty: notoriety"] = { "Difficulty: notoriety", "The pause menu's custom slider. Stays in your save." },
  ["Difficulty: ammo reserve"] = { "Difficulty: ammo reserve", "The pause menu's custom slider. Stays in your save." },
  ["Difficulty: timer speed"] = { "Difficulty: timer speed", "The pause menu's custom slider. Stays in your save." },
}
for _, t in ipairs(TABS) do for _, r in ipairs(t.rows) do local w = WORDS[r.label]; if w then r.label, r.help = w[1], w[2] end end end

local LAYOUT = {
  { "Player", {
    { "Health", "God mode, health and getting back up.", { "God mode", "Max health", "Refill health", "Health regen", "Get up", "Downed timer", "Kill yourself" } },
    { "Protection", "What can't hurt you or knock you over.", { "No fall damage", "Bulletproof", "Explosion-proof", "Crash-proof", "Damage to yourself", "Immune to", "Get up at once", "No flinch", "How easily you fall", "Dodge safe time", "Guardian angel" } },
    { "Movement", "Speed, size, gravity and flying through walls.", { "Run speed", "Always sprint", "Swim speed", "Fly (no clip)", "Your gravity", "Moon mode", "Your size", "Wind push", "Ice floor", "No shoving" } },
    { "Jumping and air", "Jump height, double jump, jetpack and air dash.", { "Jump height", "Double jump", "Jetpack", "Air dash", "Air control", "Air momentum" } },
    { "Wingsuit", "Boosts, power, speed and glide.", { "Open wingsuit now", "Wingsuit boosts", "Wingsuit boost power", "Wingsuit top speed", "Wingsuit glide", "Wingsuit from low down", "Wingsuit bounce", "Glide to nearest car" } },
    { "Flow", "Your ability meter.", { "Unlimited Flow", "Flow gain", "Extra Flow bars", "Flow never drains", "Rampage at full Flow" } },
    { "Skills and perks", "Any skill, any perk, no cost.", { "Free skills", "Skills recharge at once", "Equip any skill", "Skill effect on you", "All perks on", "Any perk", "Perk strength", "My perks off", "Melee backfire" } },
    { "Takedowns", "How often, which ones, or none.", { "Takedown ready now", "Takedown cooldown", "Grenade takedown", "Takedowns always kill", "Short takedowns only", "Dustlander takedowns", "No takedowns" } },
    { "Money", "Cash, prices and ventures.", { "Add cash", "Drop cash", "Money rain", "Free shopping", "Cash from kills", "Pedestrians always pay", "Free ventures", "Venture income", "Venture lot", "Build venture on lot" } },
    { "XP and levels", "XP, skill points and how fast you level.", { "Give XP", "Give skill points", "Level up once", "XP from kills", "XP needed per level", "Refund all skills" } },
    { "Unlocks", "Everything here stays in your save. Each needs Enter twice.", { "Unlock everything", "Unlock fast travel points", "Unlock every weapon", "Unlock all skills", "Unlock all perks", "Unlock gang and homies", "Unlock all clothing", "Unlock all store items", "Unlock all weapon skins", "Unlock all collectibles", "Show activities on the map" } },
  } },
  { "Character", {
    { "Outfits", "Whole looks, and undoing them.", { "Saved look", "Saved look: outfit only", "Character preset", "Wear any outfit", "Hidden outfit", "Wear any item", "Customize character", "Clothes hide each other", "No wind on clothes", "Snapshot my look", "Undo my look" } },
    { "Clothing", "One item at a time: pick a slot, then an item.", { "Clothing slot", "Clothing item", "What's on this slot", "Take off this slot", "Item colour", "Colour part", "Item gloss", "Stack on slot", "Stack that item", "Material slot", "Item material" } },
    { "Hair, eyes and skin", "Colours and skin, past what the game offers.", { "Hair colour", "Beard colour", "Eye colour", "Eye glow", "Skin colour", "Skin type", "Skin set" } },
    { "Face", "Face parts, past-limit sizes and expression.", { "Face part", "Face amount", "Random face", "Face: head shape", "Face: eye size", "Face: nose size", "Face: mouth size", "Face: eye spacing", "Face: mouth width", "Facial expression" } },
    { "Body", "Past the sliders' ends. Only on screen: your save keeps your real body.", { "Body: muscle", "Body: fat", "Body: thin", "Body: chest", "Body: masculine to feminine", "Body: groin", "Body: squeezed", "Long legs", "Back to my real body" } },
    { "Effects on you", "Burning, fading and the rest, for show.", { "You are invisible", "You look on fire", "Skin effect on you", "Stop skin effects", "Prank yourself", "Underglow on you", "Your glow size", "Your glow brightness", "Coloured glow on you" } },
    { "Emotes", "Play any emote, or put it on the D-pad.", { "Play emote", "Hidden emote", "D-pad emote 1", "D-pad emote 2", "Repeat emote", "Freeze emote", "Stop emote" } },
    { "Voice", "How you sound and what you say.", { "Your voice", "Voice pitch", "Any voice", "Say a line", "Radio call from", "Everyone near says it" } },
    { "Animations", "Any of the game's animations, used or not.", { "Any animation", "Animation mode", "Animation speed", "Everyone near plays it", "Idle animation", "Everyone near does an idle", "End idle near", "Move like", "Stop animation" } },
    { "Poses and actions", "Forced body states, cutscenes, sitting down, using things.", { "Force body state", "Back on foot", "Play cutscene", "Sit down", "Use nearest" } },
    { "How you walk", "Walk, run and pose styles.", { "Walk style", "Movement style", "Wounded walk", "Swim on land", "Always crouch", "Go limp" } },
  } },
  { "Weapons", {
    { "Firing", "Fire rate, magazines, reloads and range.", { "Fire rate", "Full auto", "Fire mode", "Magazine", "Reload speed", "No warm-up", "No overheat", "Range", "Any gun in vehicles and surfing", "Dual wield this gun" } },
    { "Aim and recoil", "Spread, kick and where shots go.", { "No recoil", "Perfect aim", "Spread", "Accurate hip fire", "Recoil recovery", "Firing shake", "Aim anywhere" } },
    { "Damage and hits", "How hard shots hit, and who they hurt.", { "Damage", "People damage", "Car damage", "Shield damage", "Damage from behind", "Friendly fire", "Damage type", "Pellets", "Knockback", "Stagger on hit", "Bodies fly on kill" } },
    { "Melee and explosives", "Swings, thrown weapons, rockets and blasts.", { "Melee lunge", "Melee swing width", "Explosive punches", "Headshot kill blast", "Blast radius", "Explosive fuse", "More satchels", "Rocket speed" } },
    { "Thrustbuster", "The thruster football: how fast it goes out, and what it does then.", { "Thruster throw speed", "Thruster warm-up", "Thruster fuse", "Thruster power" } },
    { "Rounds and hit effects", "What your gun fires, and what its hits do.", { "Special rounds", "Round blast", "Blast on hit", "Rounds stick", "Rounds arc", "Homing rounds", "Hit effect", "Signature from", "Second signature", "Signature effects on any gun", "Shots start from" } },
    { "Shot tricks", "Teleport shots, portals, a black hole, shooting props, hits that recruit or burn.", { "Teleport on shot", "Clear portals", "Black hole", "Money gun", "Prop gun", "Shoot prop", "Round in N shots", "N shots", "Hits recruit", "All my damage" } },
    { "Gun looks", "Tracers, flashes, skins and how you hold it.", { "Tracer", "Muzzle flash", "Shell casing", "Hit visuals", "All shots one colour", "Hide my gun", "Random gun colours", "Weapon skin", "Hold gun like", "Fire sound" } },
    { "Get weapons", "Give, drop and fill.", { "Give weapon", "Special weapon", "Prototype weapon", "Put picked gun in slot", "Refill all ammo", "Rare ammo drops", "Drop weapon" } },
    { "Upgrades and removal", "Signature abilities, top levels, taking guns away.", { "Max all weapon upgrades", "Signature ability on this gun", "All signature abilities", "Remove this weapon", "Remove test guns" } },
    "Weapons back to normal",
  } },
  { "Vehicles", {
    { "Get a vehicle", "Spawn one, keep it, or clear them away.", { "From my garage", "Spawn vehicle", "Special vehicle", "Vehicle type", "Any vehicle", "Any vehicle version", "Keep earlier spawns", "Get in when spawned", "Get in nearest", "Get out", "Remove spawned vehicles" } },
    { "Speed and boost", "Engine, top speed, drag and boost.", { "Engine power", "Vehicle top speed", "Vehicle speed limit", "Air drag", "Vehicle gravity", "Vehicle time", "Boat speed", "Boost tank", "Boost refill", "Boost power", "Boost now" } },
    { "Grip, brakes and steering", "Tires, drifting, bikes and tank steering.", { "Grip", "Off-road grip", "Front grip", "Rear grip", "Brakes", "Steering", "Drift angle", "Burnout", "Tank steering", "Bike lean", "Downforce" } },
    { "Body and weight", "Suspension, size and how it moves.", { "Suspension", "Ride height", "Vehicle size", "Wheel size", "Weight balance", "Heavy vehicle", "Bouncy car", "Slippery body", "Twitchy body", "Spin drag", "Auto-flip" } },
    { "Toughness", "Keeping it in one piece, or not.", { "Vehicle god mode", "No collision damage", "Bulletproof tires", "Keep vehicle repaired", "Engine catches fire", "Fire burn speed", "Crash force", "Floats on water", "Never sink", "Destroy this vehicle" } },
    { "Aircraft and hover", "Helicopters, VTOLs and hover vehicles.", { "Aircraft speed", "VTOL boost", "Helicopter agility", "Helicopter lift", "Flight mode", "Hover rise and lower", "Hover top speed", "Hover height", "Hover jump", "Hover guns" } },
    { "Upgrades and parts", "The garage's options, on the vehicle you're in.", { "Vehicle upgrade", "Upgrade level", "Rims", "Tires", "Off-road kit anywhere", "Part slot", "Part", "Save vehicle to garage" } },
    { "Paint", "Paints, colours and patterns.", { "Next paint", "Any paint", "Paint area", "Paint colour", "Pattern area", "Pattern", "Any colour: material", "Any colour" } },
    { "Lights and sound", "Underglow, lights, tire marks, horn and engine.", { "Underglow preset", "Underglow colour", "Underglow brightness", "Headlights on", "Brake lights stay on", "Always tire marks", "Always tire smoke", "Any horn", "Any engine sound" } },
    { "Abilities", "Give, fire and strengthen vehicle abilities.", { "Vehicle ability", "Fire that ability", "Stop that ability", "Remove that ability", "No ability cooldowns", "Vehicle jump power", "Crab steering strength", "Air control strength", "Honk blast strength", "Ejector cannon", "Hoverboard slam" } },
    { "Rams and towing", "Hitting things, and hauling them.", { "Ram power", "Crusher", "Takedowns at any speed", "Bowelrod launch", "Cowcatcher launch", "Windshield launch", "Add tow hook", "Drop tow hook", "Make nearest car towable", "Stick nearest car on me", "Unstick car" } },
    { "Stunts", "Launches, jumps and getting back on the road.", { "Launch start", "Launch strength", "Launch this vehicle", "Jump this vehicle", "Effect on this car", "Back on the road", "Stay on bike" } },
    { "Surfing and guns", "Car surfing, and guns on vehicles.", { "Surf nearest car", "Stop surfing", "Surf faster cars", "Surf autopilot", "Surfing is safe", "Fire vehicle's guns", "Shoot from any seat", "Swap vehicle gun" } },
  } },
  { "Teleport", {
    "Go to waypoint", "Go to travel point", "Go to store", "Go to map place",
    { "Saved places", "Your own spots.", { "Save this spot", "Go to saved place", "Delete that place" } },
    "Go up", "Auto-teleport to waypoint", "Warp from map", "Teleport style", "No map fast travel", "Where am I",
  } },
  { "People", {
    { "Spawn people", "Spawn anyone, or become them.", { "Spawn person", "Special person", "Spawn 10 of that person", "Spawn 10 random people", "Spawned people act", "Spawned people carry", "Play as last spawned", "Play as picked person", "Play as picked special", "Back to yourself", "Remove spawned people" } },
    { "Clone of you", "A second you: in photos, or as a bodyguard.", { "Clone of me", "Clone is your bodyguard", "Remove clone" } },
    { "Homies and followers", "Who's with you, and what they do.", { "Summon homie", "Call in Saints", "Call in follower", "Dismiss homies", "Homie limit", "Quiet homies", "Next homie outfit", "Spawned people get in my car", "Spawned people go to waypoint", "Spawned people can't die" } },
    { "Near: mood and sides", "Everyone within 40 m: how they act, whose side they're on.", { "Make everyone near react", "Make everyone near dance", "Make everyone near follow you", "Make everyone near friendly", "Make everyone near hostile", "Stop fights near", "Start a riot near", "Zombie outbreak", "Crowd around me", "Stop crowding" } },
    { "Near: attacks", "Everyone within 40 m: knock down, burn, kill or delete.", { "Stun everyone near", "Trip everyone near", "Knock everyone near down", "Float everyone near", "Launch everyone near", "Set everyone near on fire", "Poison everyone near", "Dissolve everyone near", "Kill everyone near", "Take down nearest", "Delete everyone near" } },
    { "Near: orders", "Everyone within 40 m: what they do next.", { "Order everyone near", "Give everyone near a behaviour", "Everyone near hunts you", "Make everyone near target you", "Stop targeting me", "Make everyone near shoot you", "Stop shooting", "Fake a noise", "Speed of everyone near" } },
    { "Near: toughness", "Everyone within 40 m: harder or easier to beat.", { "Disarm everyone near", "Re-arm everyone near", "Strip shields near", "Make everyone near tough", "Everyone near staggers easily", "Revive everyone near", "Downed, not dead", "Everyone near can be reeled" } },
    { "Near: looks", "Everyone within 40 m: faded, frozen, burning, outlined.", { "Fade out everyone near", "Fade everyone near back in", "Statues near", "Statues near back to life", "Flaming look near", "Flaming look near off", "Face on everyone near", "Skin effect near", "Outline everyone near", "Clear outlines", "Size of everything near" } },
    { "Near: effects", "Everyone within 40 m: effects, gravity and the minimap.", { "Short effect on everyone near", "Lasting effect on everyone near", "Lasting effect on you", "Lasting effects off", "Rule on people near", "Coloured glow near", "Gravity near", "Drop everyone near through ground", "Hide everyone near on minimap", "Show everyone near on minimap" } },
    { "Notoriety", "How wanted you are, and how fast it changes.", { "No notoriety", "Notoriety at least", "Notoriety at most", "No notoriety cap", "Notoriety fades fast", "Notoriety climbs fast", "Can't lose notoriety", "Escape distance", "Send in a gang", "Send in a wave" } },
    { "Chases and waves", "Reinforcements, chase cars and roadblocks.", { "No reinforcements", "Enemies arrive from", "Reinforcement speed", "Chase cars", "Chase speed", "No ramming", "No roadblocks", "Roadblocks everywhere", "Bigger squads", "Elite enemies early", "Enemies attacking at once" } },
    { "Enemies", "How they aim, see and fight.", { "Enemy aim", "Enemy sight", "Enemies can't see you", "Enemies always find you", "Enemies flee fights", "Non-lethal enemies", "Riot shields for all", "Enemies use smoke", "Gangs and police without guns", "Stay in combat", "Stagger cooldown" } },
    { "Gangs", "Gangs fighting each other, and whose side they're on.", { "Gang war", "Free for all", "Gang presence", "Gang on your side", "Saints are enemies", "People fight damage", "Pedestrians fight back", "Everyone battle ready", "Instant revive" } },
  } },
  { "World", {
    { "Time and weather", "The clock, the weather, slow motion and pausing.", { "Go to time", "Freeze clock", "Clock speed", "Any weather", "Any weather, instantly", "Indoor weather outside", "Game speed", "Slow motion button", "Pause world", "Only you move" } },
    { "People on the streets", "How busy the streets are, and with whom.", { "Pedestrian count", "Empty streets", "People appear at", "Quiet streets", "Crowds in the rain", "Panic distance", "Any district's crowd", "Street scene", "Street scenes normal", "Bodies and wrecks stay" } },
    { "Traffic", "How many cars, which ones, and trains.", { "Traffic amount", "Traffic type", "Rare traffic", "Traffic spacing", "Traffic appears at", "No parked cars", "Traffic light here", "Long trains", "No trains" } },
    { "Cars near: wreck", "Every car within 40 m: stop, launch or destroy.", { "Freeze cars near", "Unfreeze cars near", "Launch cars near", "Spin cars near", "Pop tires near", "Stall engines near", "Engines back on", "Crush cars near", "Tip bikes near", "Blow up cars near", "Delete nearest car" } },
    { "Drivers near", "Every driver within 40 m: how they drive.", { "Drivers near bail out", "Drivers near floor it", "Drivers near flee", "Drivers near pull over", "Drivers near weave", "Drivers near stay in", "Stunt for cars near", "Cars near stop stunts" } },
    { "Cars near: horns and locks", "Alarms, sirens, locks and walking through cars.", { "Set off car alarms", "Sirens on near", "Hazard lights near", "Lock cars near", "Unlock cars near", "Pop trunks near", "Ghost through cars near", "Solid cars near" } },
    { "Gravity and blasts", "World gravity, explosions and the map's edge.", { "World gravity", "Explosion here", "Explosion at waypoint", "Airstrike", "Explosion size", "Explosion force", "Explosion damage", "No world boundary" } },
    { "Props", "Spawn props anywhere, or a turret to ride.", { "Spawn prop", "Spawn standing turret", "Remove last prop", "Remove all props" } },
    { "Creator", "Build stunt jumps and courses: place objects at any angle, keep layouts.", { "Creator mode", "Creator object", "Creator turn step", "Creator grid", "Layout", "Save layout", "Load layout", "Go to layout", "Delete layout", "Clear placed objects" } },
    { "Headquarters", "Dress your HQ: spot by spot, or all at once.", { "HQ spot", "HQ prop", "Clear this HQ spot", "Fill the HQ", "Save HQ layout", "Load HQ layout", "HQ room theme" } },
    { "Missions and side jobs", "Start the game's activities by hand. Save first.", { "Start mission", "Start side job", "Insurance Fraud here", "Insurance Fraud launch", "Insurance Fraud score", "Activity time limits", "Hermit juice", "Give reward", "Load hidden place", "Unload hidden place" } },
  } },
  { "Visual", {
    { "Camera", "Where the camera sits and how it moves.", { "Field of view", "Camera distance", "Shoulder camera", "Turn speed", "Camera shake", "Looping camera shake", "Camera bobbing", "Camera through walls", "Photo mode", "Free camera" } },
    { "Driving camera", "The camera while you're in a vehicle.", { "Car camera resets after", "Free camera in cars", "Car camera follows the nose", "Car camera field of view", "Car camera distance" } },
    { "HUD", "Minimap, crosshair and what the HUD shows.", { "Hide HUD", "Minimap size", "Crosshair size", "HUD style", "High contrast", "Takedown outlines", "All caps text", "Fake objective" } },
    { "Screen effects", "Filters, blur, tint and bars.", { "Brightness", "Low health screen", "Letterbox", "Screen tint", "Tunnel vision", "Radial blur", "Depth of field", "Aim blur", "Shift view", "Colour vision filter", "Camera effects" } },
    { "What's drawn", "Hide parts of the world, or swap how it looks.", { "Stop drawing", "Show only people", "Blackout", "Blacklight world", "World material", "Censor mosaic", "Video on screens", "Video off" } },
    { "Sun, moon and stars", "Size, colour and speed. Lasts until you quit or load.", { "Sun size", "Moon size", "Sun speed", "Sun position", "Sun colour", "Moon colour", "Star brightness", "Star colour" } },
    { "Fog, cloud and rain", "Lasts until you quit or load.", { "Fog", "Fog colour", "Haze", "Cloud cover", "Rain amount", "Heat haze", "Wind speed" } },
    { "Light and colour", "Exposure and light. Lasts until you quit or load.", { "Look", "Sky exposure", "Lock exposure", "Light shafts", "Ambient light", "Bounced light", "Sky colour", "City lights on", "Film grain", "Dark screen edges" } },
    { "Pickup glow", "The glow on things lying on the ground.", { "Dropped gun glow", "Cash glow", "Ammo glow", "Coin glow" } },
    { "All sky settings", "Over 300 of the game's sky numbers, one at a time.", { "Any sky setting", "Sky amount", "Clear sky settings" } },
  } },
  { "Sound", {
    { "Radio", "Stations in your vehicle, on foot and around you.", { "Radio station", "Next station", "Previous station", "Unlock radio in missions", "Radio on foot", "Radios in cars near", "Newscast", "Stop newscast", "Dev: radio on" } },
    { "Music", "Songs and stations anywhere, on foot too.", { "Music anywhere", "Play song", "Pause or resume music", "Skip track", "Now playing", "Shuffle playlists" } },
    { "Volume and sounds", "The game's main volumes, and any sound on demand.", { "Master volume", "Music volume", "Effects volume", "Voice volume", "City panic noise", "Play sound" } },
    { "Sound mix", "One group of sounds at a time.", { "Volume: Ambience", "Volume: Combat", "Volume: Interface", "Volume: Vehicles", "Volume: Radio", "Volume: Music in the world", "Volume: Menu music", "Volume: Explosions", "Volume: Gore", "Volume: Voices", "Volume: Pedestrian voices" } },
  } },
  { "Cheats", {
    { "Player", "The game's own phone cheats.", { "Invincibility (game's)", "Give cash", "Max level", "Super Saints", "Milk Bones", "Pratfall", "Heaven Bound" } },
    { "Weapons", "The game's own phone cheats.", { "Infinite ammo", "Golden gun" } },
    { "Vehicles", "The game's own phone cheats.", { "Repair vehicle", "Drop a car", "Infinite boost", "Infinite mass", "No traffic laws" } },
    { "Traffic", "The game's own phone cheats: what's on the roads.", { "Monster truck traffic", "Luxury traffic", "Mascots" } },
    { "World", "The game's own phone cheats.", { "Weather", "Time of day", "Screen filter", "Low gravity", "Angry pedestrians" } },
    { "Notoriety", "The game's own phone cheats: raise, clear or max.", { "Police", "Idols", "Marshal", "Los Panteros" } },
  } },
  { "Co-op", {
    "Session", "Go to partner", "Waypoint on partner", "Revive me", "Partner friendly fire", "Pranks from partner",
    { "Balance", "The game's own co-op numbers. It weakens you and toughens enemies when you're close: these change that.", { "Balance preset", "Together: your damage", "Together: damage taken", "Together: tough grunts", "Together: tough specialists", "Together: reinforcements", "Co-op enemy limit", "What counts as close", "Together: Flow bonus", "Co-op activity scores", "Co-op activity clocks" } },
    { "Connection", "Joining, waiting, errors and leaving.", { "Open to co-op", "Stop waiting for partner", "Last co-op error", "Leave co-op", "Mark the co-op log" } },
    "Safety limits",
  } },
  { "Settings", {
    "What's on", "Save tweaks for next time", "Everything back to normal", "Turn every cheat off", "Pause all tweaks",
    { "Game", "Cutscenes, saving and tutorials.", { "Skip cutscene", "Pause / resume cutscene", "Quick save", "New save", "Load last save", "No autosave", "Skip intro", "Tutorial popups" } },
    { "Difficulty", "The pause menu's custom sliders. They stay in your save.", { "Difficulty: player health", "Difficulty: player damage", "Difficulty: enemies", "Difficulty: vehicles", "Difficulty: notoriety", "Difficulty: ammo reserve", "Difficulty: timer speed" } },
    { "Menu", "How the menu looks, opens and remembers.", { "Menu opacity", "Hold Back opens the menu", "Hold RB back", "Keep moving in the menu", "Keep my save clean", "Forget saved tweaks" } },
    { "Profiles", "Saved sets of tweaks you can switch between.", { "Profile", "Load profile", "Save to profile", "Delete profile" } },
    { "Game data", "Almost any number or on/off value in the game. Work down the rows.", { "Data system", "Data group", "Data entry", "Data value", "Data list item", "Data change", "Change this entry", "Change all entries", "Undo all data changes" } },
    { "Developer switches", "Left in the game by its developers. Most do unknown things.", { "Dev: never die", "Dev: never die, AI", "Dev: Shawn mode", "Dev: capture mode", "Dev: auto sprint", "Dev: infinite ammo", "Dev: infinite magazine", "Dev: vehicle ramps", "Dev: weapon raycasts", "Dev: notoriety bubbles", "Dev: HQ mask off" } },
    "Close menu",
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
-- The rows the co-op limits look at (coop.lua).
local coop_rows = Co.classify(TABS)
M.coop_safe = true

-- Favourites: a page of real rows, kept by label in favourites.txt.
local favs = { kind = "page", label = "Favourites", help = "Press Y or F6 on any row to add it here, or to take it off.", rows = {}, live = true }
table.insert(TABS[1].rows, 1, favs)

-- Settings kept from last time (tweaks.lua).
local function all_rows()
  local rows = {}
  for _, t in ipairs(TABS) do
    for _, r in ipairs(t.rows) do
      if r.kind == "page" then if not r.live then for _, c in ipairs(r.rows) do rows[#rows + 1] = c end end
      else rows[#rows + 1] = r end
    end
  end
  return rows
end
-- These lists have Normal in the middle: start on what's really in force.
for _, r in ipairs(all_rows()) do
  if r.kind == "pfn_list" then for i, o in ipairs(r.options) do if o[1] == "Normal" and i > 1 then r.sel, r.home = i, i end end end
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
  return (r.save_key or r.kind == "wdset" or r.kind == "camset") and r.options and r.kind ~= "opt" and r.kind ~= "hud" and r.kind ~= "mset" and r.kind ~= "coop_bal"
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
  -- and the same for rows the co-op limits are holding back
  local function swap()
    for r, sel in pairs(M.stash or {}) do r.sel, M.stash[r] = sel, r.sel end
    for r, sel in pairs(M.coop_stash or {}) do r.sel, M.coop_stash[r] = sel, r.sel end
  end
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

-- Profiles. A row's key is its save key, or its label for the few without one.
local function profile_key(r) return r.save_key or ("row." .. r.label) end
M.profile_sel = 1
function M.profile_get(n, fresh)
  M.profiles = M.profiles or {}
  if fresh or M.profiles[n] == nil then M.profiles[n] = T.profile_read(n) or false end
  return M.profiles[n] or nil
end
function M.profile_save(n)
  local have = M.profile_get(n, true)
  local rows, swap = saveable()
  swap()
  local set = {}
  for _, r in ipairs(rows) do
    if tweak_row(r) and r.sel ~= 1 and r.options[r.sel] then set[profile_key(r)] = r.options[r.sel][1] end
  end
  swap()
  local ok = T.profile_write(n, have and have.name or ("Profile " .. n), set)
  M.profile_get(n, true)
  return ok
end
-- Returns how many tweaks it set and how many it couldn't find, or nil.
function M.profile_load(n)
  local p = M.profile_get(n, true)
  if not p then return nil end
  M.stash, M.coop_stash = nil, nil
  local on, found = 0, {}
  for _, r in ipairs(all_rows()) do
    if r.key == "tweaks_paused" then r.sel = 1; M.tweaks_paused = false end
    if tweak_row(r) and #r.options > 0 then
      local want, key = 1, profile_key(r)
      if p.set[key] then
        for i, o in ipairs(r.options) do if o[1] == p.set[key] then want = i; found[key] = true; on = on + 1 end end
      end
      if r.sel ~= want then r.sel = want; set_value(r, r.options[want][2]) end
    end
  end
  W.restore(); WS.restore()
  if W.any_on() then W.apply() end
  if WS.any_on() then WS.apply() end
  M.gun_dirty = true
  M.save_tweaks()
  local missed = 0
  for k in pairs(p.set) do if not found[k] then missed = missed + 1 end end
  return on, missed
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
-- Nothing's on unless you saved it: say so the first time the menu opens.
do
  local n = 0
  for _, r in ipairs(all_rows()) do if tweak_row(r) and r.sel ~= 1 then n = n + 1 end end
  if n > 0 then
    M.saved_notice = n .. " saved tweaks are on. Settings > Forget saved tweaks clears them"
    wml.log(M.saved_notice)
  end
end
function M._on_open()
  M.open, M.pending_confirm, M.status_frames = true, nil, 0
  if M.saved_notice then M.status, M.status_kind, M.status_frames, M.saved_notice = M.saved_notice, "warn", 240, nil end
end

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

local CROWD = { statue = { "statue_near", "turned to statues" }, unstatue = { "unstatue_near", "free again" }, flame = { "flame_near", "burning" }, unflame = { "unflame_near", "put out" },
  calm = { "calm_near", "calmed" }, revive = { "revive_near", "told to get up" }, strip = { "strip_near", "stripped" }, tough = { "tough_near", "toughened" }, stagger = { "stagger_near", "easier to stagger" }, unseen = { "unseen_near", "faded out" }, seen = { "seen_near", "faded in" },
  ragdoll = { "ragdoll_near", "ragdolled" }, kill = { "kill_near", "killed" }, fire = { "fire_near", "set on fire" },
  stun = { "stun_near", "stunned" }, launch = { "launch_near", "launched" }, zombies = { "zombies_near", "near an outbreak" }, riot = { "riot_near", "rioting" }, downed = { "downed_near", "won't die" }, follow = { "follow_near", "following you" }, float = { "float_near", "floating" }, dissolve = { "dissolve_near", "dissolving" }, toxic = { "toxic_near", "poisoned" }, dance = { "dance_near", "dancing" }, hostile = { "hostile_near", "turned on you" }, friendly = { "friendly_near", "on your side" } }
local function select_row(row)
  wml.log("row: " .. tostring(row.label) .. (row.options and row.options[row.sel] and (" = " .. tostring(row.options[row.sel][1])) or ""))   -- so a crash log says what was last pressed
  local stopped = Co.blocked(row)
  if stopped then say(row.label .. ": " .. Co.why(stopped) .. " (Safety limits, on the Co-op tab)", "warn"); return end
  if Co.in_coop() then Co.log("row: " .. tostring(row.label) .. (row.options and row.options[row.sel] and (" = " .. tostring(row.options[row.sel][1])) or "")) end
  if M.stash then M.stash[row] = nil end   -- changed while All tweaks is off: keep the new choice
  if row.kind == "coop" then
    if row.confirm and M.pending_confirm ~= row then M.pending_confirm = row; say(row.label .. ": press again to confirm", "warn")
    else M.pending_confirm = nil; Co.press(row, say, P) end
  elseif row.kind == "coop_bal" then
    say(Co.balance_press(row, P), "status")
    M.save_tweaks()
  elseif row.kind == "toggle" or row.kind == "action" then
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
    elseif M.pending_confirm ~= row then M.pending_confirm = row; say(row.label .. ": press again to confirm (stays in your save)", "warn")
    else M.pending_confirm = nil; start_unlock(row) end
  elseif row.kind == "gchoice" then
    local o = row.options[row.sel]
    local ok, msg = wml.game(o[2])
    say(row.label .. ": " .. tostring(ok and (msg or "done") or msg), ok and "status" or "warn")
    -- the game has one screen-edge effect: this one on means the other's off
    if ok and row.sel ~= 1 and (row.label == "Screen tint" or row.label == "Tunnel vision") then
      for _, r in ipairs(all_rows()) do
        if r ~= row and (r.label == "Screen tint" or r.label == "Tunnel vision") then r.sel = 1 end
      end
    end
    if ok and row.label == "Lock exposure" then Cam.user_lock = row.sel == 1 end
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
    else
      local ok, why = P.play_as_spawned()
      say(ok and "You're them now: Back to yourself returns" or why or "Spawn someone first (People > Spawn person)", "status")
    end
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
  elseif row.kind == "pfn" then
    say(P[row.fn](row.arg), "status")
    if row.fn == "engine_undo_all" then
      for _, r in ipairs(Co.balance_rows) do r.sel = 1 end
      M.save_tweaks()
    end
  elseif row.kind == "pfn_list" then
    local o = row.options[row.sel]
    if o then say(P[row.fn](o[2]), "status") end
  elseif row.kind == "gun_slot" then
    local gun
    for _, r in ipairs(all_rows()) do if r.kind == "giveweapon" then gun = r.options[r.sel] end end
    if not gun then say("Pick a gun on Give weapon first", "warn") else
      say(gun[1] .. ", " .. row.options[row.sel][1] .. ": " .. P.gun_to_slot(gun[2]:match('"(.*)"') or gun[2], row.options[row.sel][2]), "status")
    end
  elseif row.kind == "radio_line" then
    local line
    for _, r in ipairs(all_rows()) do if r.kind == "voiceline" then line = r.options[r.sel] end end
    local who = row.options[row.sel]
    if not line then say("Pick a line on Say a line first", "warn") elseif who then say(P.radio_line(who[2], line[3]), "status") end
  elseif row.kind == "sky_any" then
    local o = row.options[row.sel]
    local a = P.sky_amount or 0.5
    if a == "clear" then P.sky_set(o[2], nil); say(o[1] .. ": the game's")
    else
      local v = o[3] + (o[4] - o[3]) * a
      P.sky_set(o[2], v)
      say(o[1] .. ": " .. string.format("%.3f", v))
    end
  elseif row.kind == "near_act" then
    say(P.near_act(row.key), "status")
  elseif row.kind == "engine_sys" or row.kind == "engine_class" then
    say("Pick with Left/Right")
  elseif row.kind == "engine_rec" or row.kind == "engine_field" or row.kind == "engine_item" or row.kind == "engine_apply" then
    local class_row, rec_row, field_row, item_row
    for _, r in ipairs(all_rows()) do
      if r.kind == "engine_class" then class_row = r elseif r.kind == "engine_rec" then rec_row = r elseif r.kind == "engine_field" then field_row = r elseif r.kind == "engine_item" then item_row = r end
    end
    local class = class_row.options[class_row.sel][2]
    if #rec_row.options == 0 then
      for i, n in ipairs(P.engine_records(class)) do rec_row.options[i] = { n, n } end
      item_row.options, item_row.sel = engine_items(class, rec_row.options[1], field_row.options[field_row.sel]), 1
    end
    local rec, field = rec_row.options[rec_row.sel], field_row.options[field_row.sel]
    local item = item_row.options[item_row.sel] and item_row.options[item_row.sel][2] or false
    if not rec then say("No entries of that group are loaded", "warn")
    elseif not field then say("That group has no values to change", "warn")
    elseif row.kind == "engine_rec" then say(#rec_row.options .. " entries: Left/Right picks")
    elseif row.kind == "engine_field" or row.kind == "engine_item" then
      local v = P.engine_read(class, rec[2], field[2], field[3], item or 0)
      say(field[1] .. " on " .. rec[2] .. ": " .. tostring(v), "status")
    else
      local recs = {}
      if row.all then for i, o in ipairs(rec_row.options) do recs[i] = o[2] end else recs[1] = rec[2] end
      local n = P.engine_apply(class, recs, field[2], field[3], P.engine_amount or { "mul", 2 }, item or nil)
      say(field[1] .. ": changed " .. n .. (n == 1 and " value" or " values"), "status")
    end
  elseif row.kind == "look_num" then
    local v, slot, part = row.options[row.sel][2], row.slot, row.part
    if row.cloth then for _, r in ipairs(all_rows()) do if r.kind == "cloth_slot" then slot = r.options[r.sel][2] end end end
    P.look_first()
    local ok, n = wml.game(string.format([[local c = gml_get_local_player():get_component_by_type("gml_component_character_customization")
      local i = gml_customization_get_slot_index(c, vlib_info_object:get_object("char_cust_slot", %q))
      local n = 0
      for _, e in ipairs(gml_customization_get_shader_params(c, i)) do
        if e.info:get_handle() == vlib_info_object:get_object("char_cust_shader_value", %q):get_handle() then gml_customization_set_shader_param_value(c, i, e.material, %q, %s); n = n + 1 end
      end
      return n]], slot, part, part, tostring(v)))
    say(not ok and tostring(n) or (n == 0 and ("That has no " .. part) or (row.label .. ": " .. row.options[row.sel][1])), ok and "status" or "warn")
  elseif row.kind == "stack_item" then
    local item, slot
    for _, r in ipairs(all_rows()) do
      if r.kind == "cloth_item" then item = r.options[r.sel] elseif r.kind == "stack_slot" then slot = r.options[r.sel] end
    end
    if item and slot then
      P.look_first()
      local ok, err = wml.game(string.format([[local c = gml_get_local_player():get_component_by_type("gml_component_character_customization")
        local i = gml_customization_get_slot_index(c, vlib_info_object:get_object("char_cust_slot", %q))
        gml_customization_select_wearable(c, i, vlib_info_object:get_object("char_cust_wearable_info", %q), nil, nil, true)]], slot[2], item[2]))
      say(ok and ("Stacked " .. item[1] .. " on " .. slot[1]) or tostring(err), ok and "status" or "warn")
    end
  elseif row.kind == "ability_act" then
    local o
    for _, r in ipairs(all_rows()) do if r.kind == "car_ability" then o = r.options[r.sel] end end
    if o then say(o[1] .. ": " .. P.car_ability_act(row.how, o[2]), "status") end
  elseif row.kind == "car_group" then
    local groups, err = P.car_read(row.src)
    if not groups then say(err, "status") else
      row.options, row.sel, row.car = groups, 1, wml.read_u32(P.vehicle_object() + 0x58)
      for _, r in ipairs(all_rows()) do if r.kind == "car_item" and r.src == row.src then r.options, r.sel = groups[1].items, 1 end end
      say(#groups .. " found", "status")
    end
  elseif row.kind == "car_item" then
    local g, o = nil, row.options[row.sel]
    local carv = P.vehicle_object()
    for _, r in ipairs(all_rows()) do
      if r.kind == "car_group" and r.src == row.src then
        g = r.options[r.sel]
        if not carv or r.car ~= wml.read_u32(carv + 0x58) then g = nil end
      end
    end
    if not g then say("Another vehicle: press Enter on the area row again", "warn") end
    if g and g[2] and o and o[2] then say(P.car_apply(row.src, g[2], o[2]), "status")
    else say("Press Enter on the row above first: it reads your vehicle", "warn") end
  elseif row.kind == "cloth_item" then
    local o = row.options[row.sel]
    if o then
      P.look_first()
      say(P.console(0x13DE6D0, o[2]) == 0 and ("Wearing " .. o[1]) or "The game refused", "status")
    end
  elseif row.kind == "cloth_off" or row.kind == "cloth_now" then
    local slot
    for _, r in ipairs(all_rows()) do if r.kind == "cloth_slot" then slot = r.options[r.sel] end end
    if row.kind == "cloth_off" then
      P.look_first()
      say(P.console(0x13DE8C0, slot[2]) == 0 and (slot[1] .. ": off") or "The game refused", "status")
    else
      local ok, s = wml.game(string.format([[return tostring(gml_customization_get_slotted_wearable(gml_get_local_player():get_component_by_type("gml_component_character_customization"), %q))]], slot[2]))
      say(slot[1] .. ": " .. (ok and (tostring(s):match('"(.*)"') or "nothing") or tostring(s)), "status")
    end
  elseif row.kind == "look_colour" then
    local c, slot, part = row.options[row.sel][2], row.slot, row.part
    if row.cloth then
      for _, r in ipairs(all_rows()) do if r.kind == "cloth_slot" then slot = r.options[r.sel][2] end end
      part = P.colour_part or "color_1"
    end
    P.look_first()
    local ok, n = wml.game(string.format([[local c = gml_get_local_player():get_component_by_type("gml_component_character_customization")
      local i = gml_customization_get_slot_index(c, vlib_info_object:get_object("char_cust_slot", %q))
      local v = gml_customization_get_shader_params(c, i)
      local n = 0
      for _, e in ipairs(v) do
        if e.info:get_handle() == vlib_info_object:get_object("char_cust_shader_value", %q):get_handle() then gml_customization_set_shader_param_value(c, i, e.material, %q, { R = %d, G = %d, B = %d }); n = n + 1 end
      end
      return n]], slot, part, part, c[1], c[2], c[3]))
    say(not ok and tostring(n) or (n == 0 and ("That has no " .. part) or (row.label .. ": " .. row.options[row.sel][1])), ok and "status" or "warn")
  elseif row.kind == "any_anim" then
    local o = row.options[row.sel]
    if o then say(P.play_anim(o), "status") end
  elseif row.kind == "anim_near" then
    local o
    for _, r in ipairs(all_rows()) do if r.kind == "any_anim" then o = r.options[r.sel] end end
    if o then say(P.anim_near(o), "status") end
  elseif row.kind == "play_as_pick" then
    local pick
    for _, r in ipairs(all_rows()) do if r.kind == row.from then pick = r.options[r.sel] end end
    if not pick then say("Pick someone on Spawn person first", "warn")
    elseif not P.spawn_npc(pick[2], 0, 2) then say("Couldn't spawn them right now", "warn")
    else M.play_as_wait = 300; say("Becoming " .. pick[1] .. "...") end
  elseif row.kind == "weather_now" then
    local pick
    for _, r in ipairs(all_rows()) do if r.kind == "weathernode" then pick = r.options[r.sel] end end
    if not pick then say("Pick one on Any weather first", "warn")
    else say(P.console(0x1C0CD00, pick[2] .. " 1 10 1") == 0 and ("Weather: " .. pick[1]) or "The game refused", "status") end
  elseif row.kind == "venture_build" then
    local lot
    for _, r in ipairs(all_rows()) do if r.kind == "venture_lot" then lot = r.options[r.sel] end end
    local bp = row.options[row.sel]
    if bp and lot then say(P.console(0x66E370, bp[2] .. " " .. lot[2]) == 0 and ("Building " .. bp[1]) or "The game refused", "status") end
  elseif row.kind == "immune" then
    local o = row.options[row.sel]
    local on = o and P.toggle_immune(o[2])
    say(not o and "Load into the game first" or on == nil and "Not now" or (o[1] .. (on and ": immune" or ": no longer immune")), "status")
  elseif row.kind == "face_part" then
    local o = row.options[row.sel]
    if o then
      P.look_first()
      local amount = P.face_amount == 0 and 0 or P.face_amount or 100
      local ok, err = wml.game(string.format([[gml_customization_apply_bidirectional_ambisymmetric_weight(gml_get_local_player():get_component_by_type("gml_component_character_customization"), vlib_info_object:get_object("char_cust_facial_morph_group", %q), true, true, %d)]], o[2], amount))
      say(ok and (o[1] .. ": " .. amount) or tostring(err), ok and "status" or "warn")
    end
  elseif row.kind == "hq_save" then
    local f = io.open(wml.root .. "\\hq_layout_" .. row.options[row.sel][2] .. ".txt", "w")
    if not f then say("Couldn't write the file", "warn") else
      local n = 0
      for _, r in ipairs(all_rows()) do
        if r.kind == "hq_spot" then
          for _, spot in ipairs(r.options) do
            local _, s = wml.game("return tostring(hq_customization_get_prop(" .. string.format("%q", spot[2]) .. "))")
            local name = tostring(s):match('"(.*)"')
            if name then f:write(spot[2], "\t", name, "\n"); n = n + 1 end
          end
        end
      end
      f:close()
      say(row.options[row.sel][1] .. ": " .. n .. " spots kept")
    end
  elseif row.kind == "hq_load" then
    local f = io.open(wml.root .. "\\hq_layout_" .. row.options[row.sel][2] .. ".txt", "r")
    if not f then say("Nothing saved in " .. row.options[row.sel][1], "warn")
    elseif (M.hq_armed or 0) < os.clock() then
      f:close()
      M.hq_armed = os.clock() + 5
      say("Press again: this replaces every spot in your headquarters, saved with your game", "warn")
    else
      M.hq_armed = nil
      local layout, spots = {}, {}
      for line in f:lines() do
        local a, b = line:match("^(.-)\t(.*)$")
        if a then layout[a] = b end
      end
      f:close()
      for _, r in ipairs(all_rows()) do if r.kind == "hq_spot" then spots = r.options end end
      M.hq_queue = { spots = spots, pool = {}, layout = layout, i = 0 }
      say("Putting the layout back...")
    end
  elseif row.kind == "any_perk" then
    local o = row.options[row.sel]
    local on, why = P.toggle_perk(o[2])
    say(on == nil and (o[1] .. ": " .. (why or "the game refused")) or (o[1] .. (on and (": on at " .. on .. P.perk_note(o[2])) or ": off")), "status")
  elseif row.kind == "outfit_only" then
    local pick
    for _, r in ipairs(all_rows()) do if r.kind == "outfit" then pick = r.options[r.sel] end end
    if not pick then say("Pick a look on Saved look first", "warn") else
      P.look_first()
      local ok, err = wml.game([[local n, c = 0, gml_get_local_player():get_component_by_type("gml_component_character_customization")
        for _, p in vlib_info_data_object:ipairs("char_cust_player_saved_preset_data") do n = n + 1
          if n == ]] .. pick[2] .. [[ then gml_customization_apply_player_preset(c, p, false, true) return end end]])
      say(ok and ("Wearing the clothes of " .. pick[1]) or tostring(err), ok and "status" or "warn")
    end
  elseif row.kind == "hq_fill" then
    if (M.hq_armed or 0) < os.clock() then
      M.hq_armed = os.clock() + 5
      say("Press again: this replaces every spot in your headquarters, saved with your game", "warn")
    else
      M.hq_armed = nil
      local spots, props = {}, {}
      for _, r in ipairs(all_rows()) do
        if r.kind == "hq_spot" then spots = r.options end
        if r.kind == "hq_prop" then props = r.options end
      end
      local mode = row.options[row.sel][2]
      local pool = {}
      for _, p in ipairs(props) do
        if type(p[2]) == "string" and (mode == "random" or p[1]:find("^Huge")) then pool[#pool + 1] = p[2] end
      end
      M.hq_queue = { spots = spots, pool = pool, clear = mode == "clear", i = 0 }
      say("Filling the HQ...")
    end
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
      if row.class == "char_cust_outfit" or row.class == "char_cust_wearable_info" then P.look_first() end
      say(P.console(row.handler, o[2]) == 0 and (row.what .. " " .. o[1]) or "The game refused", "status")
    end
  elseif row.kind == "game_list" then
    local o = row.options[row.sel]
    if o then
      if row.look then P.look_first() end
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
  elseif row.kind == "vehicle_type" then
    say("Left/Right picks the kind")
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
      P.keep_prior_spawn()
      P.watch_spawned_car(o[1])
      local ok = C.activate("drop_car")
      wml.write_u32(e + 0x10, a)
      wml.write_u32(e + 0x14, b)
      say(ok and (o[1] .. ": asked for") or "The game refused", ok and "status" or "warn")
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
    elseif row.key == "bail" or row.key == "floor" or row.key == "alarm" or row.key == "siren" or row.key == "spin" then
      local fn = { bail = { "bail_cars_near", " stopping" }, floor = { "floor_cars_near", " flooring it" }, alarm = { "alarm_cars_near", " wailing" }, siren = { "siren_cars_near", " told to sound off" }, spin = { "spin_cars_near", " spinning" } }
      local act = fn[row.key]
      local n = P[act[1]](40)
      say(n == 0 and "No vehicles near" or (n .. (n == 1 and " vehicle" or " vehicles") .. act[2]))
    elseif row.key == "say" then
      local line
      for _, r in ipairs(all_rows()) do if r.kind == "voiceline" then line = r.options[r.sel] end end
      if not line then say("Pick a line on Say a line first", "warn") else
        local n = P.say_near(40, line[3])
        say(n == 0 and "Nobody near" or (n .. (n == 1 and " person" or " people") .. ": " .. line[1]))
      end
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
    if x and P.teleport(x, y + up, z, true) then say("Up " .. up .. " m") else say("No player right now", "warn") end
  elseif row.kind == "where" then
    local x, y, z = P.position()
    say(x and string.format("You're at %.1f, %.1f, %.1f", x, y, z) or "No player right now")
  elseif row.kind == "weapons_reset" then
    local MIX = { sig_from = true, sig_from2 = true, bullet_blast = true, fire_mode = true, nth_round = true, fire_sound = true, hits_recruit = true, all_my_damage = true, headshot_blast = true }
    for _, r in ipairs(all_rows()) do
      if r.kind == "wset" then r.sel = 1; W.set[r.key] = r.options[1][2] end
      if MIX[r.key] then r.sel = 1 end
    end
    P.mix_off()
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
  elseif row.kind == "garage_car" then
    local o = row.options[row.sel]
    if not o then say("Nothing in your garage list yet: open the menu again", "warn")
    else select_row({ kind = "deliver", label = row.label, sel = 1, options = { o } }) end
  elseif row.kind == "deliver" then
    -- the game's drop-car cheat, pointed at the picked table entry: it spawns
    -- the vehicle properly (wheels, variant) about 5 m from you
    local o = row.options[row.sel]
    if not o or not C.by_name.drop_car then say("No vehicles (load into the game first)", "warn") else
      wml.write_u32(wml.base + 0x3110E08, o[2])
      C.allow_spicy(); M.spicy_hold = 120
      P.keep_prior_spawn()
      P.watch_spawned_car(o[1])
      local ok = C.activate("drop_car")
      say(ok and (o[1] .. ": asked for") or (o[1] .. ": the game refused right now"), ok and "status" or "warn")
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
      if P.teleport_style == "game" then
        local ok, err = wml.game([[for _, w in vlib_info_object:ipairs("city_warp_point") do
          if tostring(w) == ]] .. string.format("%q", w[2]) .. [[ then player_local_teleport_to_warp_point(w) return end end]])
        say(ok and ("Off to " .. w[1]) or ("Travel: " .. tostring(err)), ok and "status" or "warn")
      else
        local x, y, z = P.warp_position(w[2]:match('"(.*)"') or w[2])
        if x and P.teleport(x, y + 1, z) then say("Off to " .. w[1])
        else say("That point isn't loaded here: Teleport style can use the game's, with its loading screen", "warn") end
      end
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
    -- the real rows, so Left/Right here changes them; they stay listed until you reopen it
    local on, reset = {}, nil
    for _, r in ipairs(all_rows()) do
      if r.kind == "normal" then reset = r end
      local amount = r.key == "engine_amount" or r.key == "sky_amount" or r.key == "perk_strength" or r.key == "upgrade_level" or r.key == "face_amount" or r.key == "colour_part" or r.key == "car_rgb_mat" or r.key == "anim_mode" or r.key == "spawn_hostile"
      if not amount and (tweak_row(r) or r.kind == "mset" or r.kind == "hud" or r.kind == "coop_bal" or (r.kind == "opt" and r.label:find("^Dev:"))) and r.sel ~= 1 then on[#on + 1] = r
      elseif r.kind == "toggle" and C.by_name[r.cheat] and C.by_name[r.cheat].active then on[#on + 1] = r end
    end
    for _, s in ipairs(P.changes_on()) do
      on[#on + 1] = { kind = "note", label = s, help = "Set with a one-time row: change it on its own page, or use Everything back to normal." }
    end
    if #on == 0 then say("Nothing's on: the game as it comes") else
      on[#on + 1] = reset
      M.page = { kind = "page", label = "What's on", help = "", rows = on, cursor = 1 }
    end
  elseif row.kind == "normal" then
    if M.pending_confirm ~= row then
      M.pending_confirm = row
      say(row.label .. ": press again to confirm", "warn")
    else
      M.pending_confirm = nil
      M.stash, M.coop_stash = nil, nil
      for _, r in ipairs(all_rows()) do
        if tweak_row(r) and r.sel ~= 1 then r.sel = 1; set_value(r, r.options[1][2]) end
        if r.kind == "coop_bal" then r.sel = 1 end
        if r.key == "tweaks_paused" then r.sel = 1; M.tweaks_paused = false end
        if r.key == "repeat_emote" then r.sel = 1; M.repeat_emote = false end
        if r.kind == "opt" and r.label:find("^Dev:") and r.sel ~= 1 then wml.game(string.format(r.set, "false")); r.sel = 1 end
      end
      W.restore(); WS.restore()
      M.gun_dirty = true
      M.save_tweaks()
      P.back_to_normal()
      for _, r in ipairs(all_rows()) do
        if r.fn == "bigger_squads" or r.fn == "level_curve" or r.fn == "activity_clock" or r.fn == "payout" or r.fn == "scale_me" or r.fn == "hold_like" or r.fn == "no_hide_rules" or r.fn == "elites_early" then r.sel = r.home or 1 end
      end
      say("Everything back to the game's own")
    end
  elseif row.kind == "page" then
    M.page = row
    row.cursor = row.cursor or 1
    M.pending_confirm = nil
  elseif row.kind == "save_now" then
    say(M.save_now() and "Saved: your tweaks will be back next start" or "Couldn't write the file", "status")
  elseif row.kind == "creator" then
    if P.creator_active() then P.creator_stop(); say("Creator mode off")
    elseif Co.in_coop() and Co.mode == "guest" then say("Only the host can place objects", "warn")
    else
      local list
      for _, r in ipairs(all_rows()) do if r.kind == "creator_obj" then list = r end end
      P.creator_set_list(list.options, list.sel)
      local why = P.creator_start()
      if why then say(why, "warn") else M.open = false end
    end
  elseif row.kind == "creator_obj" then
    say(row.options[row.sel][1] .. ": Creator mode places it", "status")
  elseif row.kind == "layout" then
    local l = P.layout_read(M.layout_sel or 1)
    say(l and (l.name .. ": " .. #l.objects .. " objects") or "Empty: place some, then Save layout", "status")
  elseif row.kind == "layout_save" or row.kind == "layout_delete" or row.kind == "creator_clear" then
    local n = M.layout_sel or 1
    local l = P.layout_read(n)
    if row.kind == "layout_delete" and not l then say("Layout " .. n .. " is empty", "warn")
    elseif row.kind == "creator_clear" and P.creator_count() == 0 then say("Nothing placed", "warn")
    elseif (l or row.kind == "creator_clear") and M.pending_confirm ~= row then
      M.pending_confirm = row
      say(row.label .. (row.kind ~= "creator_clear" and (" " .. l.name) or "") .. ": press again to confirm", "warn")
    else
      M.pending_confirm = nil
      if row.kind == "layout_delete" then P.layout_delete(n); say("Deleted " .. l.name)
      elseif row.kind == "creator_clear" then say(P.creator_clear() .. " objects removed")
      else
        local ok, x = P.layout_write(n)
        say(ok and ("Saved " .. x .. " objects to " .. (P.layout_read(n).name)) or x, ok and "status" or "warn")
      end
    end
  elseif row.kind == "layout_load" then
    local labels = {}
    for _, r in ipairs(all_rows()) do if r.kind == "creator_obj" then for _, o in ipairs(r.options) do labels[o[2]] = o[1] end end end
    local n, why = P.layout_load(M.layout_sel or 1, labels)
    say(n and ("Putting back " .. n .. " objects") or why, n and "status" or "warn")
  elseif row.kind == "layout_go" then
    local x, y, z = P.layout_where(M.layout_sel or 1)
    if not x then say("That layout is empty", "warn")
    elseif P.teleport(x + 3, y + 1, z) then say("Off to the layout") else say("The game refused the teleport", "warn") end
  elseif row.kind == "profile" then
    local p = M.profile_get(M.profile_sel, true)
    say(p and (p.name .. ": " .. p.count .. " tweaks") or ("Profile " .. M.profile_sel .. " is empty: use Save to profile"), "status")
  elseif row.kind == "profile_load" or row.kind == "profile_save" or row.kind == "profile_delete" then
    local n = M.profile_sel
    local p = M.profile_get(n, true)
    if row.kind ~= "profile_save" and not p then say("Profile " .. n .. " is empty", "warn")
    elseif row.kind == "profile_load" and Co.in_coop() then say("Not in co-op: the limits there decide which tweaks can be on", "warn")
    elseif p and M.pending_confirm ~= row then
      M.pending_confirm = row
      say(row.label .. " " .. p.name .. ": press again to confirm", "warn")
    else
      M.pending_confirm = nil
      if row.kind == "profile_save" then
        say(M.profile_save(n) and ("Saved to " .. M.profile_get(n).name .. ": " .. M.profile_get(n).count .. " tweaks") or "Couldn't write the file", "status")
      elseif row.kind == "profile_delete" then
        T.profile_delete(n)
        M.profile_get(n, true)
        say("Deleted " .. p.name)
      else
        local on, missed = M.profile_load(n)
        say(p.name .. " loaded: " .. tostring(on) .. " tweaks on" .. ((missed or 0) > 0 and (", " .. missed .. " not found in this version") or ""), "status")
      end
    end
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
  elseif row.options then
    say("Left/Right picks: the rows below use it")
  end
end

local function row_value(row)
  if row.kind == "coop" then
    return Co.value(row)
  elseif row.kind == "coop_bal" then
    return "<  " .. row.options[row.sel][1] .. "  >", row.sel == 1 and "off" or "on"
  elseif row.kind == "toggle" then
    local on = C.by_name[row.cheat].active
    return on and "<  On  >" or "<  Off  >", on and "on" or "off"
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
  elseif row.kind == "forget" or row.kind == "all_off" or row.kind == "close" or row.kind == "weapons_reset" then
    return "Enter", "off"
  elseif row.kind == "person" then
    M.person_row = row
    local o = row.options[row.sel]
    return o and ("<  " .. o[1] .. "  >") or "none", o and "row" or "off"
  elseif row.kind == "crowd" then
    return "Enter", "off"
  elseif row.kind == "voiceline" and not row.loaded then
    return "Enter to load", "off"
  elseif row.kind == "active" or row.kind == "normal" or row.kind == "random_people" or row.kind == "emote_stop" or row.kind == "waypoint" or row.kind == "despawn" or row.kind == "refill_ammo" or row.kind == "unlock" or row.kind == "crowd_act" or row.kind == "arms" or row.kind == "destroy_car" or row.kind == "kill_self" or row.kind == "car_act" or row.kind == "play_as" or row.kind == "revive_me" or row.kind == "console_row" or row.kind == "look_undo" or row.kind == "look_snap" or row.kind == "body_back" or row.kind == "wing_now" or row.kind == "surf" or row.kind == "surf_stop" or row.kind == "skip_track" or row.kind == "remove_prop" or row.kind == "hq_clear" or row.kind == "pfn" or row.kind == "outfit_only" or row.kind == "near_act" or row.kind == "weather_now" or row.kind == "engine_apply" or row.kind == "stack_item" or row.kind == "ability_act" or row.kind == "cloth_off" or row.kind == "cloth_now" or row.kind == "anim_near" or row.kind == "play_as_pick" then
    return "Enter", "off"
  elseif row.kind == "page" then
    return #row.rows .. "  >", "off"
  elseif row.kind == "save_now" then
    return M.unsaved and "Not saved" or "Saved", M.unsaved and "on" or "off"
  elseif row.kind == "creator" then
    return P.creator_active() and "On" or (P.creator_count() > 0 and (P.creator_count() .. " placed") or "Enter"), P.creator_active() and "on" or "off"
  elseif row.kind == "creator_obj" then
    local i = P.creator_index()
    if i and P.creator_active() then row.sel = i end
    return "<  " .. row.options[row.sel][1] .. "  >", "row"
  elseif row.kind == "layout" then
    local n = M.layout_sel or 1
    local l = P.layout_read(n)
    return "<  " .. (l and (l.name .. " (" .. #l.objects .. ")") or (n .. ": empty")) .. "  >", l and "row" or "off"
  elseif row.kind == "profile" then
    local p = M.profile_get(M.profile_sel)
    return "<  " .. (p and (p.name .. " (" .. p.count .. ")") or (M.profile_sel .. ": empty")) .. "  >", p and "row" or "off"
  elseif row.kind == "mset" then
    local o = row.options[row.sel]
    return "<  " .. o[1] .. "  >", row.sel == 1 and "off" or "on"
  elseif row.kind == "vehicle_type" or row.kind == "car_group" or row.kind == "car_item" or row.kind == "any_perk" or row.kind == "pfn_list" or row.kind == "hq_fill" or row.kind == "cloth_slot" or row.kind == "cloth_item" or row.kind == "look_colour" or row.kind == "any_anim" or row.kind == "engine_sys" or row.kind == "engine_class" or row.kind == "engine_rec" or row.kind == "engine_field" or row.kind == "engine_item" or row.kind == "look_num" or row.kind == "stack_slot" or row.kind == "garage_car" or row.kind == "sky_any" or row.kind == "venture_lot" or row.kind == "venture_build" or row.kind == "immune" or row.kind == "face_part" or row.kind == "gun_slot" or row.kind == "radio_line" or row.kind == "hq_save" or row.kind == "hq_load" or row.kind == "any_vehicle" or row.kind == "any_variant" or row.kind == "console_list" or row.kind == "game_list" or row.kind == "hq_theme" or row.kind == "launch_car" or row.kind == "go_to_hour" or row.kind == "outfit_any" or row.kind == "car_effect" or row.kind == "proto_weapon" or row.kind == "song" or row.kind == "spawn_prop" or row.kind == "hq_spot" or row.kind == "hq_prop" or row.kind == "near_effect" or row.kind == "me_effect" or row.kind == "send_gang" or row.kind == "lift" or row.kind == "warp" or row.kind == "deliver" or row.kind == "homie" or row.kind == "emote" or row.kind == "emote_slot" or row.kind == "giveweapon" or row.kind == "voiceline" or row.kind == "gchoice" or row.kind == "weathernode" or row.kind == "cash_drop" or row.kind == "weapon_drop" or row.kind == "reaction" or row.kind == "map_place" or row.kind == "outfit" or row.kind == "look_preset" or row.kind == "call_saints" or row.kind == "prank" or row.kind == "car_ability" or row.kind == "special_person" or row.kind == "special_car" or row.kind == "mission" then
    local o = row.options[row.sel]
    return o and ("<  " .. o[1] .. "  >") or "none", o and "row" or "off"
  elseif row.kind == "gcall" then
    return "Enter", "off"
  elseif row.kind == "refill" or row.kind == "place_save" or row.kind == "place_delete" or row.kind == "where" then
    return "Enter", "off"
  elseif row.kind == "clean" then
    return M.clean and "<  On  >" or "<  Off  >", M.clean and "on" or "off"
  elseif row.kind == "opacity" then
    return "<  " .. U.opacity .. "%  >"
  end
  return ""
end

-- Left/Right sets these by itself; every other list only picks, and Enter does the work.
local SETS_ITSELF = { coop = true, toggle = true, clean = true, wset = true, pset = true, hud = true, opt = true, wdset = true, wsset = true, mvset = true, carset = true, camset = true, mset = true, opacity = true,
  cloth_slot = true, stack_slot = true, venture_lot = true, hq_spot = true, engine_sys = true, engine_class = true, engine_rec = true, engine_field = true, engine_item = true, car_group = true, places = true }
local TWICE = { unlock = true, normal = true, look_undo = true, kill_self = true, destroy_car = true, mission = true, proto_weapon = true, look_preset = true, hq_fill = true, hq_load = true }
local function shown_value(row)
  local stopped = Co.blocked(row)
  if stopped then return Co.why(stopped), "off" end
  local value, colour = row_value(row)
  local twice = TWICE[row.kind] or row.confirm
  if value == "Enter" then return twice and "Enter twice" or value, colour end
  if value:sub(1, 1) == "<" and not SETS_ITSELF[row.kind] and not row.apply then
    return value .. (twice and "  Enter twice" or "  Enter"), colour
  end
  return value, colour
end

local function render()
  local tab = view()
  local cur = view_cursor()
  local lines = {}
  local title = "SR5 Tweak Menu" .. Co.title()
  lines[1] = { label = title, value = "Cash " .. C.money(M.cash), colour = "title", value_colour = "off" }
  local names = {}
  for i, t in ipairs(TABS) do names[#names + 1] = (i == M.tab) and t.name:upper() or t.name end
  if not M.page and #tab.rows > ROWS then lines[1].label = title .. "   " .. cur .. "/" .. #tab.rows end
  lines[2] = { label = M.page and (TABS[M.tab].name .. "  >  " .. M.page.label .. "   " .. cur .. "/" .. #tab.rows .. "     B or Backspace: back") or table.concat(names, "  "), colour = "tabs" }
  local first = math.max(1, math.min(cur - math.floor(ROWS / 2), #tab.rows - ROWS + 1))
  for i = 0, ROWS - 1 do
    local row = tab.rows[first + i]
    if row then
      local value, vcol = shown_value(row)
      local label = (first + i == cur and "> " or "   ") .. row.label .. (row.cheat and is_spicy(row.cheat) and " *" or "")
      lines[3 + i] = { label = label, value = value, colour = first + i == cur and "cursor" or "row", value_colour = vcol }
    end
  end
  local row = tab.rows[cur]
  -- the help text, wrapped onto two lines
  local stopped = row and Co.blocked(row)
  local help = U.wrap(stopped == "off" and "Off while you're in co-op: it could break the session for both of you. Safety limits on the Co-op tab can lift this."
    or stopped and "Only the host can use this in co-op: it changes the world you share. Safety limits on the Co-op tab can lift this."
    or row and row.help or "", 2)
  lines[ROWS + 3] = { label = help[1] or "", colour = "help" }
  lines[ROWS + 4] = { label = help[2] or "", colour = "help" }
  if M.status_frames > 0 then lines[ROWS + 5] = { label = M.status, colour = M.status_kind }
  elseif M.unsaved then lines[ROWS + 5] = { label = "Tweaks changed: Settings > Save tweaks keeps them for next start", colour = "off" }
  else
    local starred = false
    for _, r in ipairs(tab.rows) do if r.cheat and is_spicy(r.cheat) then starred = true end end
    lines[ROWS + 5] = { label = not starred and "" or M.clean and "* would mark your save: Keep my save clean is stopping it" or "* marks your save: Settings > Menu > Keep my save clean", colour = "off" }
  end
  U.show(lines)
  -- fit again every 10 frames: the game's measure can lag behind new text
  M.renders = (M.renders or 0) + 1
  if M.renders % 10 == 5 then U.refit() end
end

-- ------------------------------------------------------------------ input
local PAD = { UP = 0x1, DOWN = 0x2, LEFT = 0x4, RIGHT = 0x8, BACK = 0x20, LB = 0x100, RB = 0x200, A = 0x1000, B = 0x2000, Y = 0x8000 }
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
local function change_tab(delta)
  M.pending_confirm = nil
  if M.page then
    local rows, at = TABS[M.tab].rows, nil
    for i, r in ipairs(rows) do if r == M.page then at = i end end
    local n = at and #rows or 0
    for step = 1, n do
      local i = (at - 1 + delta * step) % n + 1
      if rows[i].kind == "page" then
        M.page, M.cursor[M.tab] = rows[i], i
        M.page.cursor = M.page.cursor or 1
        return
      end
    end
  end
  M.page = nil; M.tab = (M.tab - 1 + delta) % #TABS + 1
end
local function adjust(delta)
  M.pending_confirm = nil
  local row = view().rows[view_cursor()]
  local stopped = row and Co.blocked(row)
  if stopped then say(row.label .. ": " .. Co.why(stopped) .. " (Safety limits, on the Co-op tab)", "warn"); return end
  if row and row.kind == "coop" and row.act == "open" then select_row(row); return end
  if row and row.options then
    local n, o = #row.options, nil
    if n > 0 then o = row.options[(row.sel - 1 + delta) % n + 1] end
    if row.save_key or row.kind == "wdset" then
      wml.log("set: " .. tostring(row.label) .. " = " .. tostring(o and o[1]))
      if Co.in_coop() then Co.log("set: " .. tostring(row.label) .. " = " .. tostring(o and o[1])) end
    end
  end
  if row and M.stash then M.stash[row] = nil end
  if row and row.kind == "voiceline" and not row.loaded then load_voice_lines(row) end
  if row and (row.kind == "toggle" or row.kind == "clean") then select_row(row)
  elseif row and row.kind == "mset" then M.adjust_mset(row, delta)
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
  elseif row and row.kind == "layout" then
    M.layout_sel = ((M.layout_sel or 1) - 1 + delta) % 8 + 1
  elseif row and row.kind == "creator_obj" then
    row.sel = (row.sel - 1 + delta) % #row.options + 1
    if P.creator_active() then P.creator_set_list(row.options, row.sel) end
  elseif row and row.kind == "profile" then
    M.profile_sel = (M.profile_sel - 1 + delta) % T.PROFILES + 1
    M.profile_get(M.profile_sel, true)
  elseif row and row.options and #row.options == 0 then
    say(row.kind == "engine_rec" and "Press Enter to load this list" or "Nothing to pick yet: load into the game first", "warn")
  elseif row and row.options then
    row.sel = (row.sel - 1 + delta) % #row.options + 1
    if row.apply then
      if M.apply_row and M.apply_row ~= row then select_row(M.apply_row) end
      M.apply_row, M.apply_wait = row, 20
    end
    if row.kind == "engine_sys" or row.kind == "engine_class" then
      local class_row, rec_row, field_row
      for _, r in ipairs(all_rows()) do
        if r.kind == "engine_class" then class_row = r elseif r.kind == "engine_rec" then rec_row = r elseif r.kind == "engine_field" then field_row = r end
      end
      if row.kind == "engine_sys" then class_row.options, class_row.sel = engine_classes(row.sel), 1 end
      local c = class_row.options[class_row.sel]
      rec_row.options, rec_row.sel = {}, 1
      field_row.options, field_row.sel = engine_fields(c[3]), 1
    end
    if row.kind == "engine_sys" or row.kind == "engine_class" or row.kind == "engine_rec" or row.kind == "engine_field" then
      local class_row, rec_row, field_row, item_row
      for _, r in ipairs(all_rows()) do
        if r.kind == "engine_class" then class_row = r elseif r.kind == "engine_rec" then rec_row = r elseif r.kind == "engine_field" then field_row = r elseif r.kind == "engine_item" then item_row = r end
      end
      item_row.options, item_row.sel = engine_items(class_row.options[class_row.sel][2], rec_row.options[rec_row.sel], field_row.options[field_row.sel]), 1
    end
    if row.kind == "car_group" and row.options[row.sel].items then
      for _, r in ipairs(all_rows()) do if r.kind == "car_item" and r.src == row.src then r.options, r.sel = row.options[row.sel].items, 1 end end
    end
    if row.kind == "cloth_slot" then
      for _, r in ipairs(all_rows()) do if r.kind == "cloth_item" then r.options, r.sel = cloth_items(row.sel), 1 end end
    end
    if row.kind == "vehicle_type" then
      for _, r in ipairs(all_rows()) do if r.kind == "any_vehicle" then r.options, r.sel = any_of_kind(row.options[row.sel][2]), 1 end end
    end
    if row.kind == "any_vehicle" or row.kind == "vehicle_type" then
      local list
      for _, r in ipairs(all_rows()) do if r.kind == "any_vehicle" then list = r end end
      for _, r in ipairs(all_rows()) do if r.kind == "any_variant" then r.options, r.sel = any_variants(list.sel, list.options), 1 end end
    end
  elseif row and row.kind == "opacity" then U.opacity = math.max(0, math.min(100, U.opacity + delta * 10)); M.save_tweaks() end
end

local FAV_FILE = wml.root .. "\\favourites.txt"
local function save_favs()
  local f = io.open(FAV_FILE, "w")
  if not f then return end
  for _, r in ipairs(favs.rows) do f:write(r.label, "\n") end
  f:close()
end
local function load_favs()
  local f = io.open(FAV_FILE, "r")
  if not f then return end
  local by = {}
  for _, r in ipairs(all_rows()) do by[r.label] = r end
  for line in f:lines() do if by[line] then favs.rows[#favs.rows + 1] = by[line] end end
  f:close()
end
local function toggle_fav()
  local row = view().rows[view_cursor()]
  if not row or row.kind == "page" or row.kind == "note" then return end
  for i, r in ipairs(favs.rows) do
    if r == row then
      table.remove(favs.rows, i)
      favs.cursor = math.max(1, math.min(favs.cursor or 1, #favs.rows))
      save_favs()
      say(row.label .. ": off your favourites")
      return
    end
  end
  favs.rows[#favs.rows + 1] = row
  save_favs()
  say(row.label .. ": on your favourites")
end

local function load_cheats()
  if C.loaded then return true end
  if not C.load() then return false end
  prune()
  load_favs()
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
    elseif r.kind == "immune" and #r.options == 0 then
      for _, q in ipairs(all_rows()) do
        if q.kind == "near_effect" then for _, o in ipairs(q.options) do r.options[#r.options + 1] = { o[1], o[2] } end end
      end
    elseif (r.kind == "console_list" or r.kind == "game_list" or r.kind == "face_part" or r.kind == "radio_line" or r.kind == "venture_build" or (r.kind == "pfn_list" and r.class)) and #r.options == 0 then
      -- names_of keeps the game's text; lists with a class are sorted by label
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
    -- your garage, by the same list the phone's mechanic uses; garage_index is the drop-car table's index
    if r.kind == "garage_car" and #r.options == 0 then
      local ok, s = wml.game([[local o = ""
        for _, v in pairs(vehicle_get_garage_list(vlib_info_object:get_object("store_info", "garage"))) do
          o = o .. tostring(v.garage_index) .. "|" .. tostring(v.vehicle_info) .. "|" .. tostring(v.variant_info) .. "|" .. tostring(v.has_customization) .. "\n"
        end
        return o]])
      if ok and type(s) == "string" then
        for i, car, variant, custom in s:gmatch('(%d+)|[^|]-"([^"|]*)"|[^|]-"([^"|]*)"|(%a+)\n') do
          local way = variant:gsub("^" .. car:gsub("%p", "%%%0") .. "_?", "")
          r.options[#r.options + 1] = { pretty(car) .. (way ~= "" and way ~= "player" and (": " .. way) or "") .. (custom == "true" and " (customized)" or ""), tonumber(i) }
        end
        table.sort(r.options, function(a, b) return a[1] < b[1] end)
      end
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

-- Co-op: read the session; rows now stopped are put back to the game's until they aren't.
function M.coop_tick()
  Co.safe = M.coop_safe
  Co.update(P.position)
  P.partner_entry, P.partner_car = Co.partner, Co.partner_car
  if C.loaded and not M.coop_bal_done and Co.mode ~= "guest" then M.coop_bal_done = true; Co.balance_saved(P) end
  if not Co.in_coop() and not M.coop_stash then return end
  local changed = 0
  for _, r in ipairs(coop_rows) do
    if r.sel ~= 1 and Co.blocked(r) then
      if tweak_row(r) then
        M.coop_stash = M.coop_stash or {}
        M.coop_stash[r] = r.sel
        r.sel = 1
        set_value(r, r.options[1][2])
        changed = changed + 1
        Co.log("held back: " .. r.label)
      elseif r.kind == "opt" and r.label:find("^Dev:") then
        wml.game(string.format(r.set, "false"))
        r.sel = 1
        changed = changed + 1
        Co.log("switched off: " .. r.label)
      end
    end
  end
  local back = 0
  for r, sel in pairs(M.coop_stash or {}) do
    if not Co.blocked(r) then
      M.coop_stash[r] = nil
      if M.stash then M.stash[r] = sel else r.sel = sel; set_value(r, r.options[sel][2]) end
      back = back + 1
      Co.log("back on: " .. r.label)
    end
  end
  if M.coop_stash and next(M.coop_stash) == nil then M.coop_stash = nil end
  if changed > 0 or back > 0 then
    M.gun_dirty = true
    if C.loaded and W.any_on() then W.apply() end
    if C.loaded and WS.any_on() then WS.apply() end
    if changed > 0 then say("Co-op: " .. changed .. " tweak" .. (changed == 1 and "" or "s") .. " held back while you're in a session", "warn")
    else say("Co-op over: " .. back .. " tweak" .. (back == 1 and "" or "s") .. " back on") end
  end
end

local frame = 0
function M.update()
  frame = frame + 1
  P._tick = P._tick + 1
  if frame % 30 == 23 then M.coop_tick() end
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
    elseif ensure_ready() then M._on_open(); frame = 0 end
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
  if C.loaded and frame % 30 == 20 and (P.car_on() or P.car_pending()) then P.update_car()
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
  if C.loaded and frame % 5 == 3 and (P.rockets or P.rockets_set) then P.update_rockets() end
  local reach = P.melee_lunge == "far" and 4 or 1
  if W.set.melee_reach ~= reach then W.set.melee_reach = reach; M.gun_dirty = true end
  local rk = (P.rockets or P.bullet_blast or P.nth_round) and true or false
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
  if C.loaded then P.update_run(); P.update_jump(M.open) end
  if C.loaded and P.kill_active() then P.update_kill_self() end
  if C.loaded then P.update_refire(W.set.fire_rate); P.update_thrustbuster(); P.update_car_watch(); P.update_enter_wait(); P.update_minimap_watch(); if P.spawn_note then say(P.spawn_note[1], P.spawn_note[2]); P.spawn_note = nil end end
  if C.loaded and P.money_gun then P.update_money_gun() end
  if C.loaded and P.shot_rows_on() then P.update_shot_rows() end
  if C.loaded and P.hole_on() then P.update_black_hole() end
  if C.loaded and P.flying_on() then P.update_flying() end
  if C.loaded and P.dual_waiting() then P.update_dual() end
  if C.loaded and P.guns_anywhere then P.update_guns_anywhere() end
  if C.loaded and frame % 30 == 17 and P.fire_from_active() then P.update_fire_from() end
  if C.loaded and frame % 60 == 31 then P.update_sides() end
  if C.loaded and P.move_style ~= (M.move_style_was or false) then P.update_move_style(); M.move_style_was = P.move_style end
  if C.loaded and P.wingsuit_low ~= (M.wing_low_was or false) then P.update_wingsuit_low(); M.wing_low_was = P.wingsuit_low end
  if C.loaded and frame % 300 == 57 then P.reassert() end
  if C.loaded and frame % 60 == 37 then P.update_perks(); P.update_notoriety_nodes(); P.update_ventures() end
  if C.loaded and P.flow ~= (M.flow_was or false) then P.update_flow(); M.flow_was = P.flow end
  if C.loaded and P.takedown ~= (M.takedown_was or false) then P.update_takedown(); M.takedown_was = P.takedown end
  if C.loaded and P.free_skills ~= (M.free_skills_was or false) then P.update_free_skills(); M.free_skills_was = P.free_skills end
  if C.loaded and frame % 15 == 2 then
    local cfg = P.car_cfg_key()
    if cfg ~= M.car_cfg_was then
      if M.car_cfg_was or cfg:find("=[^f]") then P.update_car_cfg() end
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
  if C.loaded and P.creator_busy() then P.update_creator(M.open) end
  if C.loaded and frame % 15 == 11 and P.clone_active() then P.update_clone() end
  if C.loaded and P.wing_pending() then P.update_wing() end
  if P.prop_release_pending() then P.update_prop_release() end
  if C.loaded then WS.update_lift(P); WS.update_boost(P) end
  if C.loaded and frame % 60 == 49 and P.tunes_active() then P.update_tunes() end
  if C.loaded and frame % 60 == 57 and P.ffa_active() then P.update_free_for_all() end
  if C.loaded and frame % 120 == 58 and P.rare_active() then P.update_rare_traffic(VEH.rare) end
  if C.loaded and frame % 120 == 59 and P.scenes_active() then P.update_scenes() end
  if C.loaded and P.always_sprint and frame % 15 == 11 then P.update_sprint() end
  if C.loaded and (P.explosive_melee or P._melee_on) and frame % 15 == 6 then P.update_explosive_melee() end
  if C.loaded and frame % 30 == 27 then P.update_melee_lunge(); P.update_extras() end
  if C.loaded and P.wind then P.update_wind() end
  if C.loaded and P.tp_holding() then P.update_tp_hold() end
  if C.loaded and P.hover_active() then P.update_hover(M.open) end
  if C.loaded and P.wheel_guns then P.update_wheel_guns(M.open) end
  if C.loaded and P.mount_pending() then P.update_car_mount() end
  if C.loaded and (P.seat_guns or SR5TM_EXTRA.seat_rows) then P.update_seat_guns() end
  if C.loaded and frame % 30 == 3 then
    P._update_car_physics()
    local fv = (P.flight_mode or SR5TM_EXTRA.flight_orig) and P.vehicle_object()
    if fv then P._update_flight_mode(fv) end
  end
  if C.loaded and P.moves_active() then P.update_moves(M.open) end
  if C.loaded and frame % 15 == 9 and P.gun_tune_active() then P.update_gun_tune() end
  if C.loaded and P._reequip_wait then P.update_reequip() end
  if C.loaded and frame % 60 == 31 then P.update_drop_glow() end
  if C.loaded and frame % 60 == 47 then P.update_skin_colour() end
  if C.loaded and frame % 15 == 7 and P.my_glow_active() then P.update_my_glow() end
  if P.fx_colour_pending() then P.update_fx_colour() end
  if C.loaded and frame % 15 == 11 and P.sig_from_active() then P.update_sig_from() end
  if C.loaded and frame % 5 == 2 and P.bullet_blast_active() then P.update_bullet_blast() end
  if C.loaded and P.fire_mode then P.update_fire_mode() end
  if C.loaded and P.nth_active() then P.update_nth() end
  if C.loaded and frame % 30 == 19 and P.fire_sound_active() then P.update_fire_sound() end
  if C.loaded and frame % 30 == 23 and P.perk_rows_active() then local why = P.update_perk_rows(); if why then say(why, "warn") end end
  if C.loaded and P.airstrike and frame % P.airstrike == 0 then P.update_airstrike() end
  if C.loaded and frame % 15 == 8 and P.sig_active() then P.update_sig_key() end
  if C.loaded and M.play_as_wait then
    M.play_as_wait = M.play_as_wait - 1
    local became, why = false, nil
    if not P.spawned_pending() then became, why = P.play_as_spawned() end
    if why then
      M.play_as_wait = nil
      say(why, "warn")
    elseif became then
      M.play_as_wait = nil
      say("You're them now: Back to yourself returns")
    elseif M.play_as_wait <= 0 then
      M.play_as_wait = nil
      say("They didn't arrive in time", "warn")
    end
  end
  if C.loaded and P.sky_active() then P.update_sky(frame % 600 == 300) end
  if C.loaded and (P.sun_height or M.sun_was) then P.update_sun(); M.sun_was = P.sun_height end
  if C.loaded and P.cam_look_active() then P.update_cam_look() end
  if C.loaded and M.hq_queue and frame % 4 == 1 then
    local q = M.hq_queue
    q.i = q.i + 1
    local spot = q.spots[q.i]
    if not spot then
      M.hq_queue = nil
      say("HQ filled: " .. (q.i - 1) .. " spots")
    elseif q.clear or q.layout or #q.pool > 0 then
      local prop
      if q.layout then prop = q.layout[spot[2]] elseif not q.clear then prop = q.pool[math.random(#q.pool)] end
      wml.game("hq_customization_set_prop(" .. string.format("%q", spot[2]) .. ", " .. (prop and string.format("%q", prop) or [[vlib_info_object:invalid("building_customization_prop_info")]]) .. ")")
    end
  end
  if C.loaded and P.slow_active() then P.update_slow_button(M.open) end
  if C.loaded and frame % 30 == 26 then P.update_scaled(); P.update_parked() end
  if C.loaded and frame % 60 == 3 and P.gangs_active() then P.update_gang_presence() end
  if C.loaded and frame % 60 == 9 then if P._proto_given then P.fix_zero_damage() end; P.log_state(); P.log_pools() end
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
  if C.loaded and frame % 30 == 22 and (P.spring ~= 1 or next(P._spring_orig)) then P.update_spring() end
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
      if M.open then M.open = false elseif ensure_ready() then M._on_open(); frame = 0 end
    end
  else
    M.back_frames = 0
  end
  -- Full auto's simulated clicks only on a gun that's single-shot by nature:
  -- on an automatic one they just interrupt its own firing.
  local pulse = P.throw_pulse_ms() or (P.full_auto and W.gun_single and P.full_auto) or false
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
    if frame % 180 == 0 and not M.open then C.refresh() end
    if M.clean and frame % 15 == 0 then
      local clear = M.spicy_hold == 0 and not C.spicy_active()
      if C.keep_clean(clear) and not M.told_clean then
        M.told_clean = true
        wml.log("cleared the save's cheated mark")
      end
    end
  end

  -- While it's open the game only gets moving and looking. On foot the triggers would fire and
  -- aim, so they stop too; in a vehicle they're the pedals, so they keep going.
  if wml.rb_delay and (M.rb_hold or 0) ~= (M.rb_sent or 0) then wml.rb_delay(M.rb_hold or 0); M.rb_sent = M.rb_hold or 0 end
  local still = M.open and M.menu_still or false
  if (M.open ~= M.blocking or still ~= M.blocking_still) and wml.block_input then
    if wml.block_move then wml.block_move(still) end
    wml.block_input(M.open, M.open)
    M.blocking, M.blocking_still = M.open, still
  end
  if wml.block_triggers then
    local t = M.open and C.loaded and (still or not P.vehicle_object()) or false
    if t ~= M.block_triggers then wml.block_triggers(t); M.block_triggers = t end
  end

  if not M.open then
    local cl = P.creator_lines()
    if cl and U.lines == 0 then U.create(LINES) end
    if cl and U.lines > 0 then U.show(cl, true); M.hidden = false
    elseif U.lines > 0 and not M.hidden then U.show(nil); M.hidden = true end
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
  if wml.key_pressed("F6") or (pressed & PAD.Y ~= 0) then toggle_fav() end
  if wml.key_pressed("BACKSPACE") or (pressed & PAD.B ~= 0) then
    if M.page then M.page = nil else M.open = false end
    M.pending_confirm = nil
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
  if M.status_frames > 0 then M.status_frames = M.status_frames - 1 elseif M.pending_confirm then M.pending_confirm = nil end
  if M.open then render() else U.show(nil); M.hidden = true end
end

return M
