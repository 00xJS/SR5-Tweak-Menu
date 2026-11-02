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
