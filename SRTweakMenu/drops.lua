-- SR5 Tweak Menu - the glow on things lying on the ground. A material effect, not a particle: an outline layer and a
-- scrolling lines layer drawn over the pickup's own mesh, in material_effect_info records. Each layer's name is read
-- each time an effect starts, so this only changes new drops. Layer 1 is the mesh and stays.
local P = require("player")

local RECS = { glow_weapons = "vfx_pickup_highlight_weapons", glow_cash = "vfx_pickup_highlight_cash",
  glow_ammo = "vfx_pickup_highlight_ammo", glow_coins = "vfx_cash_hilight_gold" }
local COLOURS = {   -- outline, lines
  Green = { "vfx_matfx_outline_cash", "vfx-matfx_pickup_highlight_cash" },
  Cyan = { "vfx_matfx_outline", "vfx-matfx_pickup_highlight_weapons" },
  White = { "vfx_matfx_outline", "vfx-matfx_pickup_highlight_ammo" },
  Violet = { "vfx_matfx_outline", "vfx-matfx_pickup_highlight_collectable" },
  Gold = { "vfx_matfx_outline", "vfx-matfx_pickup_highlight_cuttingedge" },
  Purple = { "vfx_matfx_outline_purple", "vfx-matfx_hilight_purple_pulse" },
  Orange = { "vfx_matfx_outline_orange", "vfx-matfx_hilight_orange_pulse" },
  Off = { "", "" },
}
local WEAPON_HASH, NO_HASH = 0x3BE30E8, 0x3C44910   -- the weapon effect's name hash, read when a gun drops; the invalid id

SR5TM_GLOW = SR5TM_GLOW or { names = {}, sent = {} }   -- the game's own names by record and layer, and what's been sent
local G = SR5TM_GLOW
for key in pairs(RECS) do P[key] = false end

local function put(rec, i, name)
  local a = P._engine_addr("material_effect_info", rec, "m_layers[" .. i .. "].m_masking_layer")
  if not a then return false end   -- the coin record without its DLC
  a = a - 0xFF                     -- the layer's name is at its start, 0xFF before this field
  local own = rec .. i
  if not G.names[own] then
    local s = wml.read_string(a, 0xFE):match("^[^\0]*")
    if not s:find("%.mat$") then return false end   -- not what's expected: touch nothing
    G.names[own] = s
  end
  name = name or G.names[own]
  for k = 1, #name do wml.write_u8(a + k - 1, name:byte(k)) end
  wml.write_u8(a + #name, 0)
  return true
end
local function send(key, colour)
  local c = colour and COLOURS[colour] or {}
  local ok = put(RECS[key], 0, c[1]) and put(RECS[key], 2, c[2])
  if key == "glow_weapons" then
    -- Off for guns is cleaner still: the game refuses that hash before it reaches the materials.
    local B = wml.base
    G.hash = G.hash or wml.read_u32(B + WEAPON_HASH)
    wml.write_u32(B + WEAPON_HASH, colour == "Off" and wml.read_u32(B + NO_HASH) or G.hash)
  end
  return ok
end
-- On a change, and every so often while on: nothing says the records outlive a reload of the game's tables.
function P.update_drop_glow()
  local again = P._tick % 600 < 60
  for key in pairs(RECS) do
    local want = P[key] or false
    if want ~= (G.sent[key] or false) or (want and again) then
      if send(key, want) then G.sent[key] = want or nil
      elseif want ~= (G.tried and G.tried[key]) then
        wml.log("drop glow: couldn't set " .. key .. " to " .. tostring(want))
        G.tried = G.tried or {}
        G.tried[key] = want
      end
    end
  end
end

-- ------------------------------------------------------------------ skin effects in other colours
-- Many effect looks exist in several colours as separate materials (research_effect_colours.md). An effect reads its layers'
-- material names when it starts, so: write another material into a carrier record's layer, play it, and put the game's own
-- name back half a second later. What's already playing keeps its colour, so two people can wear two colours.
-- { label, carrier record, layer, material }
local RIM, DIS, OUT = "vfx_toxic_glow", "vfx_fire_dissolve", "vfx_object_outline_combat_01"
P.FX_COLOURS = {
  { "Rim glow: toxic green", RIM, 1, "vfx-matfx_toxic_glow_01" }, { "Rim glow: teal", RIM, 1, "vfx-matfx_skill-perk-activate_outline-pulse_01" },
  { "Rim glow: gold", RIM, 1, "vfx-matfx_skill-perk-activate_outline-pulse_get-tough_01" }, { "Rim glow: red", RIM, 1, "vfx-matfx_skill-perk-activate_outline-pulse_vampire_01" },
  { "Rim glow: silver", RIM, 1, "vfx-matfx_skill-perk-activate_outline-pulse_quick-escape_01" }, { "Rim glow: orange", RIM, 1, "vfx-matfx_hilight_orange_pulse" },
  { "Rim glow: blue", RIM, 1, "vfx-matfx_edge_highlight_02" }, { "Rim glow: mint", RIM, 1, "vfx-matfx_edge_highlight_tether_03" },
  { "Rim glow: scan blue", RIM, 1, "vfx-matfx_face_scan_01b" }, { "Rim glow: kisses pink", RIM, 1, "vfx-matfx_kisses_01" },
  { "Edge glow: violet", RIM, 1, "vfx-matfx_edge_highlight_01" }, { "Edge glow: orange-red", RIM, 1, "vfx-matfx_hit_flash_01" },
  { "Lines: green", RIM, 1, "vfx-matfx_pickup_highlight_cash" }, { "Lines: cyan", RIM, 1, "vfx-matfx_pickup_highlight_weapons" },
  { "Lines: white", RIM, 1, "vfx-matfx_pickup_highlight_ammo" }, { "Lines: violet", RIM, 1, "vfx-matfx_pickup_highlight_collectable" },
  { "Lines: gold", RIM, 1, "vfx-matfx_pickup_highlight_cuttingedge" }, { "Lines: purple", RIM, 1, "vfx-matfx_hilight_purple_pulse" },
  { "Lines: pale gold", RIM, 1, "vfx-matfx_pickup_highlight_cash_gold" },
  { "Flash: teal", RIM, 1, "vfx-matfx_skill-perk-activate_body-flash_01" }, { "Flash: yellow", RIM, 1, "vfx-matfx_skill-perk-activate_body-flash_yellow_01" },
  { "Flash: red", RIM, 1, "vfx-matfx_skill-perk-activate_body-flash_red_01" }, { "Flash: blue", RIM, 1, "vfx-matfx_face_scan_01c_flash" },
  { "Toy soldier: green", RIM, 1, "ctg_flat_green" }, { "Toy soldier: red", RIM, 1, "ctg_flat_red" }, { "Toy soldier: blue", RIM, 1, "ctg_flat_blue" }, { "Toy soldier: grey", RIM, 1, "ctg_flat_grey" },
  { "Neon pink", RIM, 1, "com_outfit_glow1" }, { "Gold rim light", RIM, 1, "prop_hero-collectible-rim-light_01a" }, { "Lava glow", RIM, 1, "vfx_dlc_boothill_lmg_glow" },
  { "Dissolve: red", DIS, 2, "vfx-matfx_energy-derez-edge-burn-out_01" }, { "Dissolve: green", DIS, 2, "vfx-matfx_energy-derez-toxic_01" },
  { "Dissolve: orange", DIS, 2, "vfx-matfx_tumbleweed_dissolve_01" }, { "Dissolve: ghost red", DIS, 2, "vfx-matfx_evilghost_dissolve_01" },
  { "Outline: red", OUT, 0, "vfx-mesh_object-outline_combat_01" }, { "Outline: deep blue", OUT, 0, "vfx-mesh_object-outline_combat_02" },
  { "Outline: teal", OUT, 0, "vfx_matfx_outline" }, { "Outline: green", OUT, 0, "vfx_matfx_outline_cash" }, { "Outline: orange", OUT, 0, "vfx_matfx_outline_orange" },
  { "Outline: purple", OUT, 0, "vfx_matfx_outline_purple" }, { "Outline: gold", OUT, 0, "vfx_matfx_outline_cash_gold" },
}
local fx_back   -- { record, layer, frames left }
-- Plays a recoloured effect on each id. o = one of P.FX_COLOURS.
function P.fx_colour_on(ids, o)
  if fx_back then put(fx_back[1], fx_back[2]); fx_back = nil end
  if not put(o[2], o[3], o[4]) then return false end
  for _, id in ipairs(ids) do P._skin_on(id, o[2]) end
  fx_back = { o[2], o[3], 30 }
  return true
end
function P.fx_colour_pending() return fx_back ~= nil end
function P.update_fx_colour()
  if not fx_back then return end
  fx_back[3] = fx_back[3] - 1
  if fx_back[3] <= 0 then put(fx_back[1], fx_back[2]); fx_back = nil end
end
function P.fx_colour_me(o)
  local e = P.object()
  if not e then return "Not now" end
  return P.fx_colour_on({ wml.read_u32(e + 0x58) }, o) and ("On you: " .. o[1]) or "That effect isn't loaded"
end
function P.fx_colour_near(o)
  local ids = {}
  for _, p in ipairs(P.people_near(40)) do ids[#ids + 1] = wml.read_u32(p.entry + 0x58) end
  if #ids == 0 then return "Nobody near" end
  return P.fx_colour_on(ids, o) and (#ids .. " people: " .. o[1]) or "That effect isn't loaded"
end

-- ------------------------------------------------------------------ underglow on you
-- A light prefab, plugged into your Torso socket so it goes where you go (attachment_attach_node), then coloured with the
-- game's light nodes (research_player_underglow.md). The haunted hotel's body light is one light and no mesh; without
-- that DLC, a base-game light rig of three. A light's values only reach the renderer when a setter marks it dirty, so the
-- intensity node goes last. Nothing on you changes: off unplugs it and removes it, once it's 2 s old.
P.my_glow, P.my_glow_size, P.my_glow_bright = false, 6, 3000
local GLOW_PATHS = { [[data\dlc_02\spawnables\gameplay\prefabs\real_estate\dlc_haunted_hotel_player_body_light]],
  [[data\sr_vanguard\spawnables\lighting\prefabs\light_rig_ct-cust_01a]] }
local function ref(ctype, entry)
  local B, b = wml.base, wml.buffer(13)
  wml.write_u64(b, b + 0x20); wml.write_u64(b + 8, b + 0x28)
  wml.write_u32(b + 0x20, ctype); wml.write_u8(b + 0x28, 0)
  local h = wml.call(B + 0x19E8C40, entry, b) & 0x1FFFFFF
  if h == 0 then return nil end
  local pool = wml.read_u64(B + 0x5CB3F70) + (h & 0xFF) * 0xD0
  return wml.read_u64(wml.read_u64(pool + 0x88) + ((h >> 8) & 0x1FFFF) * 8), wml.read_u32(entry + 0x58)
end
local function linear(c) return (c / 255) ^ 2.2 end
local function glow_off(L)
  local root = L.id and P.entry_of(L.id)
  if root and wml.read_u32(root + 0x58) == L.id then
    local c, o = ref(9, root)
    if c then P.node(0x18EB150, 0x2ABCD60, { { c = c, o = o } }) end
    P._remove_safe("id", L.id)
  end
end
function P.my_glow_active() return P.my_glow or G.me ~= nil end
-- Called about 4 times a second.
function P.update_my_glow()
  local L, me = G.me, P.object()
  if not P.my_glow then
    if L then glow_off(L); G.me = nil end
    return
  end
  if not me then return end
  local my_id = wml.read_u32(me + 0x58)
  if L and L.owner ~= my_id then G.me = nil; L = nil end   -- a respawn or a load: the old one went with the world
  if not L then L = { owner = my_id, path = 1 }; G.me = L end
  if L.failed then return end
  if not L.rec then
    local ok = P._loaded(GLOW_PATHS[L.path])
    if ok == false then
      L.path = L.path + 1
      if not GLOW_PATHS[L.path] then L.failed = true; wml.log("underglow on you: no light would load") end
      return
    end
    if not ok then return end
    L.before = {}
    for _, o in ipairs(P._objects_near(4, 0x19)) do L.before[o.entry] = true end
    L.rec = P.spawn_prefab(GLOW_PATHS[L.path] .. ".cprefab_pc")
    if not L.rec then L.failed = true end
    return
  end
  if not L.id then
    local id = wml.read_u32(L.rec + 0x70)
    local root = id ~= 0 and P.entry_of(id)
    if not root then return end
    L.id, L.lights = id, {}
    P._born[id] = P._born[L.rec]   -- its age, for the 2 s rule on removal
    for _, o in ipairs(P._objects_near(4, 0x19)) do if not L.before[o.entry] then L.lights[#L.lights + 1] = o.entry end end
    local c, o = ref(9, root)
    if c then P.node(0x18EAF40, 0x2AC2710, { { c = c, o = o }, { u = my_id }, { p = wml.buffer(5, "Torso") } }) end
    L.before = nil
  end
  local want = table.concat(P.my_glow, ",") .. "/" .. P.my_glow_size .. "/" .. P.my_glow_bright
  L.n = (L.n or 0) + 1
  if L.sent == want and L.n % 20 ~= 0 then return end   -- and again every 5 s, in case something reset it
  L.sent = want
  local B = wml.base
  for _, e in ipairs(L.lights) do
    local light = P.component(0x19, e)
    local c, o = ref(0x19, e)
    if light and c then
      wml.call(B + 0x1450D30, light, 0xF)   -- lights the ground, cars, people and you
      wml.write_f32(light + 0x30, P.my_glow_size)
      P.node(0x18FD080, 0x2ABD0A0, { { c = c, o = o }, { v = { linear(P.my_glow[1]), linear(P.my_glow[2]), linear(P.my_glow[3]) } } })
      P.node(0x18FD1A0, 0x2AC8F00, { { c = c, o = o }, { f = P.my_glow_bright / #L.lights } })
    end
  end
end

-- ------------------------------------------------------------------ your skin, in any colour
-- The skin's tint_composite on each material that has it, head, body, arms and legs, with the game's own call. Normal skins
-- only: reward skins like galaxy_skin expose no values, and the mannequin preset's white has no colour to set. Tried live:
-- solid green, and a look restore put it back. It's a colour, not a glow: past 255 shifts the hue and adds no light.
P.skin_colour = false
local TINT = [[local c = gml_get_local_player():get_component_by_type("gml_component_character_customization")
  local si, p = gml_customization_get_skin_shader_values(c)
  local want, n = vlib_info_object:get_object("char_cust_shader_value", "tint_composite"):get_handle(), 0
  for _, e in ipairs(p) do
    if e.info:get_handle() == want then
      gml_customization_set_skin_shader_value(c, e.material, e.info, { R = %d, G = %d, B = %d })
      n = n + 1
    end
  end
  return n]]
function P.update_skin_colour()
  local want = P.skin_colour
  if not want then
    if G.skin then
      G.skin = nil
      P.look_restore()
    end
    return
  end
  if not G.skin then
    P.look_first()
    G.skin = { n = 0 }
  end
  -- A respawn or a load can take the colour away, so it's sent again now and then.
  G.skin.n = G.skin.n + 1
  if G.skin.want == want and G.skin.n % 5 ~= 0 then return end
  G.skin.want = want
  local ok, n = wml.game(string.format(TINT, want[1], want[2], want[3]))
  if not ok or n == 0 then
    local why = ok and "this skin has no tint: only normal skins do" or tostring(n)
    if why ~= G.skin.why then wml.log("skin colour: " .. why); G.skin.why = why end
  end
end
