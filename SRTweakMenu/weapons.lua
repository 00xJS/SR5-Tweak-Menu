-- SR5 Tweak Menu - weapon tweaks, on the game's own weapon data.
--
-- Every weapon is a gml_weapon_info (391), listed with
-- vlib_info_object:ipairs("gml_weapon_info"). A weapon's numbers live in
-- three places, and the menu changes all three:
--   1. its own fields (m_refire_delay, m_magazine_size, m_damage_player...);
--   2. its named property lists (m_weapon_float_properties /
--      m_weapon_int_properties: { m_key = the key's name hash, m_value }),
--      which override the fields (the launcher's magazine, the assault
--      rifle's refire delay are there);
--   3. each property key's m_default_value (gml_weapon_*_property_key),
--      used by weapons that don't list that property.
-- The address of any field comes from the game's own lookup, +17D4660
-- (field object -> containing object; the last field descriptor's bit
-- offset is at +0x38). The game reads these values while you play.
-- Unset values (INT_MAX, FLT_MAX, -1) mean "inherit" and are left alone.

local W = { loaded = false, count = 0 }
local RESOLVE = 0x17D4660

-- Property keys (name hash -> what the menu calls it). Names from the
-- game's gml_weapon_*_property_key lists (research/weapon_property_keys).
local FLOAT_KEYS = {
  [2068864722] = "refire",        -- refire_delay
  [3848690817] = "reload_speed",  -- reload_speed_scale
  [1030134537] = "warmup",        -- warmup_time
  [1288717430] = "charge",        -- charge_time
  [1729008533] = "overheat",      -- overheat_per_shot
  [2685072847] = "damage_all",    -- damage (everyone's: one-hit kill only)
  [3092279371] = "spread",        -- deviation_angle_start
  [3039539812] = "spread",        -- deviation_angle_end
  [3278015433] = "spread",        -- hip_fire_deviation_scalar
  [1296480626] = "feather",       -- refire_delay_feathering (0.1 s by default)
  [184102078] = "damage_player",  -- damage_avatar (a gun's own damage when you fire it)
  [1436921172] = "range",         -- range
  [2003839093] = "impulse",       -- impulse
  [3476011760] = "recoil",        -- recoil_pitch
  [4628092] = "recoil",           -- recoil_heading
  [635825236] = "recoil",         -- recoil_max_pitch
  [1210448282] = "recoil",        -- recoil_max_heading
  [562308622] = "recoil",         -- hip_fire_recoil_scalar
  [665612735] = "recoil",         -- camera shake intensity
  [1177745254] = "recoil",        -- hip_fire_camera_shake_scalar
}
local INT_KEYS = {
  [2201942346] = "magazine",      -- magazine size
  [1271462471] = "single_shot",   -- is_single_shot (one shot a trigger pull)
}
-- The weapon's own fields: offset in its data, type, what.
local FIELDS = {
  { 0x5FC, "f", "damage_all" }, { 0x600, "f", "damage_player" }, { 0x604, "f", "spread" }, { 0x608, "f", "impulse" },
  { 0x60C, "f", "range" }, { 0x610, "f", "refire" }, { 0x614, "i", "magazine" },
}

-- Settings (1 = the game's own).
W.set = { magazine = 1, fire_rate = 1, damage = 1, perfect_aim = false, range = 1, knockback = 1,
          reload = 1, no_warmup = false, no_overheat = false, no_recoil = false, full_auto = false, rockets = false }
W.NO_RELOAD = 999

local entries = {}   -- { addr =, t = "f"/"i", what =, orig = }

local function game(code)
  local r = table.pack(wml.game(code))
  if not r[1] then wml.log("weapons: game Lua error: " .. tostring(r[2])); return nil end
  return table.unpack(r, 2, r.n)
end
local function ptr(v) return tonumber(tostring(v):match("(%x+)>$") or "", 16) end
local function s32(v) return v >= 0x80000000 and v - 0x100000000 or v end

local function read(addr, t)
  if t == "i" then return s32(wml.read_u32(addr)) end
  return wml.read_f32(addr)
end
local function write(addr, t, v)
  if t == "i" then wml.write_u32(addr, math.floor(v) & 0xFFFFFFFF) else wml.write_f32(addr, v) end
end

-- Address of a field object (a game userdata), through the game's lookup.
local buf
local function field_addr(ud)
  local p = ptr(ud)
  if not p then return nil end
  buf = buf or wml.buffer(1)
  local base = wml.call(wml.base + RESOLVE, p + 0x28, buf, buf + 16)
  if base == 0 then return nil end
  local desc = wml.read_u64(buf)
  if desc == 0 or s32(wml.read_u32(buf + 16)) >= 0 then return nil end
  return base + (wml.read_u32(desc + 0x38) >> 3)
end

-- Picks "i" or "f" by which reading matches the game's own number.
local function typed(addr, number)
  local f = wml.read_f32(addr)
  if f == number or (number ~= 0 and math.abs(f - number) <= 1e-4 * math.abs(number)) then return "f" end
  if s32(wml.read_u32(addr)) == number then return "i" end
  return nil
end

local function add(addr, t, what)
  if addr and t and what then entries[#entries + 1] = { addr = addr, t = t, what = what, orig = read(addr, t) } end
end

function W.load()
  entries = {}
  local total = game([[local n = 0 for _ in vlib_info_object:ipairs("gml_weapon_info") do n = n + 1 end return n]])
  if type(total) ~= "number" or total == 0 then return false end
  local weapons = 0
  for first = 1, total, 4 do
    -- per weapon: "W", magazine field; then "F"/"I", key, value field, value
    local r = table.pack(game([[
      local i, o = 0, {}
      for _, info in vlib_info_object:ipairs("gml_weapon_info") do
        i = i + 1
        if i >= ]] .. first .. [[ and i < ]] .. (first + 4) .. [[ then
          o[#o + 1] = "W" o[#o + 1] = info.m_magazine_size
          for _, e in info.m_weapon_float_properties:ipairs() do
            o[#o + 1] = "F" o[#o + 1] = e.m_key:get_number() o[#o + 1] = e.m_value o[#o + 1] = e.m_value:get_number()
          end
          for _, e in info.m_weapon_int_properties:ipairs() do
            o[#o + 1] = "I" o[#o + 1] = e.m_key:get_number() o[#o + 1] = e.m_value o[#o + 1] = e.m_value:get_number()
          end
        end
      end
      return unpack(o)
    ]]))
    -- resolve at once, while the game still holds the field objects
    local j = 1
    while j <= r.n do
      local tag = r[j]
      if tag == "W" then
        local a = field_addr(r[j + 1])
        if a then
          local base = a - 0x614
          for _, f in ipairs(FIELDS) do add(base + f[1], f[2], f[3]) end
          weapons = weapons + 1
        end
        j = j + 2
      elseif tag == "F" or tag == "I" then
        local key, ud, number = r[j + 1], r[j + 2], r[j + 3]
        local what = (tag == "F" and FLOAT_KEYS or INT_KEYS)[key]
        if what then
          local a = field_addr(ud)
          if a then add(a, typed(a, number), what) end
        end
        j = j + 4
      else
        j = j + 1
      end
    end
  end
  -- the property keys' defaults
  for _, cls in ipairs({ { "gml_weapon_float_property_key", FLOAT_KEYS }, { "gml_weapon_int_property_key", INT_KEYS } }) do
    local r = table.pack(game([[
      local o = {}
      for _, info in vlib_info_object:ipairs("]] .. cls[1] .. [[") do
        o[#o + 1] = info o[#o + 1] = info.m_default_value o[#o + 1] = info.m_default_value:get_number()
      end
      return unpack(o)
    ]]))
    for j = 1, r.n, 3 do
      local p = ptr(r[j])
      local key = p and ((wml.read_u64(p + 0x28) >> 32) & 0xFFFFFFFF)
      local what = key and cls[2][key]
      if what then
        local a = field_addr(r[j + 1])
        if a then add(a, typed(a, r[j + 2]), what) end
      end
    end
  end
  W.count = weapons
  W.loaded = weapons > 0
  wml.log("weapons: " .. weapons .. " weapons, " .. #entries .. " values")
  return W.loaded
end

local function is_set(t, v)
  if t == "i" then return v > 0 and v < 0x7FFFFFFF end
  return v == v and v > 0 and v < 1e30
end

-- What a value should be for the current settings.
local function wanted(e)
  local v, s = e.orig, W.set
  local w = e.what
  -- One-hit kill: every weapon's player damage, inherited ones included, and
  -- the shared damage values (so it can't be missed; enemies' guns too).
  if s.damage == "kill" and (w == "damage_player" or w == "damage_all") then return 100000 end
  if w == "damage_all" then return v end
  if w == "feather" then return s.fire_rate ~= 1 and 0 or v end
  -- Full auto: no gun fires just once a trigger pull
  if w == "single_shot" then return s.full_auto and 0 or v end
  -- No recoil: kick, its limits and the camera shake from firing, all 0
  if w == "recoil" then return s.no_recoil and 0 or v end
  if w == "spread" then return (s.perfect_aim and v == v and v > 0 and v < 1e30) and 0 or v end
  if not is_set(e.t, v) then return v end
  if w == "magazine" then
    if s.magazine == "no_reload" then return W.NO_RELOAD end
    return math.max(1, math.floor(v * s.magazine + 0.5))
  elseif w == "refire" then
    -- Rockets: at most 4 a second. Near 12 a second the game shut itself down
    -- with no error (likely out of room for projectiles or explosions).
    if s.rockets then return math.max(v / s.fire_rate, 0.25) end
    -- No faster than 20 shots a second, as player.lua's cached copy: faster crashed.
    return math.min(v, math.max(v / s.fire_rate, 0.05))
  elseif w == "damage_player" then return s.damage == "kill" and 100000 or v * s.damage
  elseif w == "range" then return v * s.range
  elseif w == "impulse" then return v * s.knockback
  elseif w == "reload_speed" then return v * s.reload
  elseif w == "warmup" or w == "charge" then return s.no_warmup and 0.01 or v
  elseif w == "overheat" then return s.no_overheat and 0 or v
  end
  return v
end

-- Writes every value for the current settings.
function W.apply()
  if not W.loaded and not W.load() then return false end
  local n = 0
  for _, e in ipairs(entries) do
    -- A new gun copies the shared data, so tuning both stacked (x8 became x64):
    -- only what a gun may not list is tuned here, the rest on the gun in hand.
    local want = (e.what == "recoil" or e.what == "feather") and wanted(e) or e.orig
    if want ~= (e.written or e.orig) then write(e.addr, e.t, want); n = n + 1 end
    e.written = want
  end
  return true, n
end

-- The gun in hand. A gun keeps its own copy of most of its properties, made
-- when you switch to it, so the shared data above only reaches later copies:
-- at the weapon component (+49F8A0(+1C1F420(&gun id))), one list per fire mode
-- (0x6A0 apart): pointer +0x138, count u16 +0x140, 24-byte entries (key hash
-- +0, value +8, type +0x10: 1 float, 0 int). What the menu tunes is written
-- straight into them, with each entry's original kept for this gun; a new gun
-- starts over. (Recoil has its own code, in player.lua.)
-- Entries are found by key on every pass: the per-gun setter (special ammo,
-- rockets, recoil) adds properties to these lists, which can move them, so a
-- remembered address could end up writing over something else.
local gun_id, gun_orig   -- gun_orig: [section * 2^32 + key] = original value
function W.update_gun(force)
  if not W.loaded then return end
  local ok, str = wml.game("return tostring(gml_get_local_player_weapon())")
  local id = ok and tonumber((str or ""):match("object (%x+)") or "", 16)
  if not id or id == 0 then return end
  if id ~= gun_id then
    gun_id, gun_orig, force = id, {}, true
    W.gun_single = false
  end
  if not force then return end
  local buf = wml.buffer(15)
  wml.write_u32(buf, id)
  local entry = wml.call(wml.base + 0x1C1F420, buf)
  local comp = entry ~= 0 and wml.call(wml.base + 0x49F8A0, entry) or 0
  if comp == 0 then gun_id = nil; return end
  for section = 0, 1 do
    local list = wml.read_u64(comp + section * 0x6A0 + 0x138)
    local n = wml.read_u16(comp + section * 0x6A0 + 0x140)
    if list ~= 0 and n <= 200 then
      for i = 0, n - 1 do
        local p = list + i * 24
        local key, kind = wml.read_u32(p), wml.read_u32(p + 0x10)
        local what = (kind == 1 and FLOAT_KEYS or kind ~= 3 and INT_KEYS or {})[key]
        if what and what ~= "recoil" then
          local t = kind == 1 and "f" or "i"
          local slot = section * 0x100000000 + key
          local orig = gun_orig[slot]
          if orig == nil then
            orig = read(p + 8, t)
            gun_orig[slot] = orig
            if what == "single_shot" and section == 0 and orig ~= 0 then W.gun_single = true end
          end
          local want = wanted({ t = t, what = what, orig = orig })
          if read(p + 8, t) ~= want then write(p + 8, t, want) end
        end
      end
    end
  end
end
function W.gun_active() return W.any_on() or gun_orig ~= nil end

-- Puts every weapon back as the game had it.
function W.restore()
  for _, e in ipairs(entries) do if e.written and e.written ~= e.orig then write(e.addr, e.t, e.orig) end e.written = nil end
end

-- Still the same data? (If the game reloaded its weapon data, load again.)
function W.check()
  local e = entries[1]
  if not e then return end
  local now = read(e.addr, e.t)
  local expect = e.written or e.orig
  if now ~= expect and not (e.t == "f" and math.abs(now - expect) <= 1e-4 * math.max(1, math.abs(expect))) then
    wml.log("weapons: the game's weapon data changed; loading it again")
    W.load()
    W.apply()
  end
end

function W.any_on()
  local s = W.set
  return s.magazine ~= 1 or s.fire_rate ~= 1 or s.damage ~= 1 or s.perfect_aim or s.range ~= 1 or s.knockback ~= 1
      or s.reload ~= 1 or s.no_warmup or s.no_overheat or s.no_recoil or s.full_auto
end

return W
