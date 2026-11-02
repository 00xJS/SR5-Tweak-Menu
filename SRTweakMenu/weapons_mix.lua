-- SR5 Tweak Menu - things one gun can borrow from another. A module of its own: player.lua's main chunk is at Lua's limit of locals.
-- Everything is keyed on the gun's id. A gun's component address is reused, and only read after the id is checked this pass.
-- Off: P._reequip_soon(), which rebuilds the gun from its record, one second later, once however many rows asked.
local P = require("player")
local loaded = P._loaded
local NAME = "sr5_tweak_menu"

local function crc(s)
  local ok, v = wml.game("return string_crc(" .. string.format("%q", s) .. ")")
  return ok and type(v) == "number" and (math.floor(v) & 0xFFFFFFFF) or 0
end
-- The gun in hand: id, object entry, weapon component.
local function gun()
  local B = wml.base
  local ok, s = wml.game("return tostring(gml_get_local_player_weapon())")
  local id = ok and tonumber((s or ""):match("object (%x+)") or "", 16)
  if not id or id == 0 then return nil end
  local buf = wml.buffer(10)
  wml.write_u32(buf, id)
  local entry = wml.call(B + 0x1C1F420, buf)
  local comp = entry ~= 0 and wml.call(B + 0x49F8A0, entry) or 0
  if comp == 0 then return nil end
  return id, entry, comp
end
-- All the models a choice needs: true, false if one failed, nil while waiting.
local function all_loaded(list)
  local out = true
  for _, path in ipairs(list or {}) do
    local r = loaded(path)
    if r == false then return false end
    if r == nil then out = nil end
  end
  return out
end

-- ------------------------------------------------------------------ signature from another gun
-- The game's own way (+996A20): an upgrade's "Script to Attach" (record +0x110 list, 0x268 each, +0x18 id) goes on the gun's object as a
-- named script component: +1847510(&out, entry, id, 1, &name hash), +193FD50(comp, script name), +1C3AB70 to commit. The scripts live
-- in the inventory tables' own containers, so they're there without the donor gun (M). +193FD50 refuses a script not at state 4.
-- Our own name per slot, so a gun's own "UltimateUpgrade" stays and two can run. The donor's upgrade tier doesn't matter.
P.sig_from, P.sig_from2 = false, false   -- false or { record = inventory record, loads = { paths }, keys = { {key, kind, value}... } }
local sig_gun, sig_done = nil, {}
local function record_of(name)
  local ok, ud = wml.game("return vlib_info_object:get_object(\"inventory_weapon_info\", " .. string.format("%q", name) .. ").m_reserve_size")
  local a = ok and ud and require("vdata").field_addr(ud)
  return a and a - 0x9C or nil
end
local function script_id(rec)
  local list, n = wml.read_u64(rec + 0x110), wml.read_u16(rec + 0x118)
  for i = n - 1, 0, -1 do
    local srid = wml.read_u64(list + i * 0x268 + 0x18)
    if srid ~= 0 then return srid end
  end
end
local function attach(entry, srid, slot_name)
  local B = wml.base
  if wml.call(B + 0xE715E0, srid) & 0xFFFFFFFF ~= 4 then return "not loaded" end
  local text = wml.call(B + 0xD82FA0, srid)
  if text == 0 then return "no name" end
  local mem = wml.buffer(10) + 0x100
  wml.write_u32(mem, crc(slot_name))
  if wml.call(B + 0x4BEC80, entry, mem) ~= 0 then return "name taken" end
  -- the object's kind allows it (+996C74)
  local v = wml.read_u32(entry + 0x5C) >> 10
  local d = wml.read_u64(B + 0x496B7A8) + (v & 0x3F) * 0x40
  local kind = wml.read_u64(d + 0x18) + wml.read_u64(d + 0x10) * ((v >> 6) & 0x3FFFFFF)
  if wml.read_u8(kind + 0x6D) ~= 0 then return "not this object" end
  local out = mem + 0x10
  wml.write_u64(out, 0)
  local count = wml.read_u64(B + 0x5CB42A0) + 1
  wml.write_u64(B + 0x5CB42A0, count)
  local comp = wml.call(B + 0x1847510, out, entry, count | (1 << 63), 1, mem)
  if comp == 0 then return "no component" end
  wml.call(B + 0x193FD50, comp, text)
  local h = wml.read_u32(out) & 0x1FFFFFF
  wml.write_u32(mem + 0x20, h)
  wml.write_u64(mem + 0x30, mem + 0x20)
  wml.write_u32(mem + 0x38, 1)
  if wml.call(B + 0x1C3AB70, mem + 0x30) & 0xFF == 0 then
    wml.call(B + 0x148F670, h)
    return "commit refused"
  end
  return true
end
local function put_key(comp, key, kind, value)
  local buf, name = wml.buffer(10), wml.buffer(11, NAME)
  wml.write_u32(buf + 0x10, key)
  for i = 0, 15, 4 do wml.write_u32(buf + 0x20 + i, 0) end
  if kind == 1 then wml.write_f32(buf + 0x20, value) else wml.write_u32(buf + 0x20, value) end
  wml.write_u32(buf + 0x28, kind)
  for section = 0, 1 do wml.call(wml.base + 0x1BFF510, comp, buf + 0x10, section, buf + 0x20, name) end
end
function P.sig_from_active() return P.sig_from or P.sig_from2 or next(sig_done) ~= nil end
function P.update_sig_from()
  local want = { P.sig_from or false, P.sig_from2 or false }
  if not want[1] and not want[2] then
    if next(sig_done) then sig_done, sig_gun = {}, nil; P._reequip_soon() end
    return
  end
  local id, entry, comp = gun()
  if not id then return end
  if id ~= sig_gun then sig_gun, sig_done = id, {} end
  for slot = 1, 2 do
    local w = want[slot]
    if sig_done[slot] and sig_done[slot] ~= w then
      sig_done, sig_gun = {}, nil
      P._reequip_soon()   -- a changed pick: a clean gun, then the new ones go on
      return
    end
    if w and not sig_done[slot] then
      local ready = all_loaded(w.loads)
      if ready == false then wml.log("signature: a model wouldn't load for " .. w.record); sig_done[slot] = w
      elseif ready then
        local rec = record_of(w.record)
        local srid = rec and script_id(rec)
        if srid then
          local r = attach(entry, srid, "sr5tm_sig" .. slot)
          if r ~= true then wml.log("signature " .. w.record .. ": " .. r) end
        end
        for _, k in ipairs(w.keys or {}) do put_key(comp, k[1], k[2], k[3]) end
        sig_done[slot] = w
      end
    end
  end
end

-- ------------------------------------------------------------------ blast on hit
-- Tracer hits read "explosion" from the gun's list and spawn it at the hit (+3FD04A, the Machine Pistol's Splattergun is this). No projectile.
P.bullet_blast = false   -- false or a path
local blast_gun, blast_on
function P.bullet_blast_active() return P.bullet_blast or blast_on end
function P.update_bullet_blast()
  local path = P.bullet_blast
  if not path then blast_gun = nil; if blast_on then blast_on = nil; P._reequip_soon() end; return end
  if not loaded(path) then return end
  local id, _, comp = gun()
  if not id or (id == blast_gun and blast_on == path) then return end
  local buf, name = wml.buffer(10), wml.buffer(11, NAME)
  wml.write_u32(buf + 0x10, 0x979E75B2)   -- explosion
  local srid = P._prefab_id(path .. ".cprefab_pc")
  for section = 0, 1 do wml.call(wml.base + 0x1C001E0, comp, buf + 0x10, section, srid, name) end
  blast_gun, blast_on = id, path
end

-- ------------------------------------------------------------------ fire mode
-- Run from here, no script swap: the fire loop won't fire before the section's +0x7BC, against the clock at +2E80878, and +0x7C4 bit 1 means the
-- trigger's held (+1BFD880). Nothing here outlasts the row: every value is the timer, which the game overwrites.
P.fire_mode = false   -- false or { "burst", n, gap ms } / { "charge", ms } / { "spin", ms }
local fm = {}
function P.update_fire_mode()
  local mode = P.fire_mode
  if not mode then fm = {}; return end
  local id, _, comp = gun()
  if not id then return end
  if fm.id ~= id then fm = { id = id, n0 = wml.read_u32(comp + 0x1CE8) } end
  local now, n = wml.read_u32(wml.base + 0x2E80878), wml.read_u32(comp + 0x1CE8)
  local held = wml.read_u8(comp + 0x7C4) & 1 == 1
  if mode[1] == "burst" then
    if not held then fm.n0 = n
    elseif n - fm.n0 >= mode[2] then
      wml.write_u32(comp + 0x7BC, now + mode[3])
      fm.n0 = n
    end
  else
    if not held then
      fm.t0, fm.n1 = nil, nil
      wml.write_u32(comp + 0x7BC, now + 2000)   -- so the first pull can't fire at once
    elseif not fm.t0 then
      fm.t0, fm.n1 = now, n
      wml.write_u32(comp + 0x7BC, now + mode[2])
    elseif mode[1] == "charge" and n ~= fm.n1 then
      fm.t0, fm.n1 = now, n
      wml.write_u32(comp + 0x7BC, now + mode[2])
    end
  end
end

-- ------------------------------------------------------------------ one round in n
-- Special rounds on every nth shot only. The round's keys go on once; "shot" and "shot_type" flip each time the counter moves. Both are read per shot (+982340).
P.nth_round, P.nth_every = false, 5
local nth = {}
function P.nth_active() return P.nth_round or nth.on end
function P.update_nth()
  local r = P.nth_round
  if not r then
    local was = nth.on
    nth = {}
    if was then P._reequip_soon() end
    return
  end
  local ready = all_loaded({ r[1], r[2] })
  if ready and r.loads then ready = all_loaded(r.loads) end
  if not ready then return end
  local id, _, comp = gun()
  if not id then return end
  local buf, name = wml.buffer(10), wml.buffer(11, NAME)
  if nth.id ~= id or nth.for_r ~= r then
    -- the gun's own shot and type, section 0, before we touch them: { key, section, id } at +0x600, { key, value, type } at +0x138
    local own, own_type = nil, 0xD57E1B94
    local list, cnt = wml.read_u64(comp + 0x600), wml.read_u16(comp + 0x608)
    for i = 0, cnt - 1 do
      if wml.read_u32(list + i * 16) == 0x8A4357A7 and wml.read_u32(list + i * 16 + 4) == 0 then own = wml.read_u64(list + i * 16 + 8) end
    end
    list, cnt = wml.read_u64(comp + 0x138), wml.read_u16(comp + 0x140)
    for i = 0, cnt - 1 do
      if wml.read_u32(list + i * 24) == 0x30B4E7EA then own_type = wml.read_u32(list + i * 24 + 8) end
    end
    if not own then return end
    nth = { id = id, for_r = r, own = own, own_type = own_type, on = true, n = wml.read_u32(comp + 0x1CE8), rare = P._prefab_id(r[1] .. ".cprefab_pc") }
    put_key(comp, 0x30B4E7EA, 3, own_type)   -- first: a section's list holds 50 keys and drops what comes after
    for _, k in ipairs(r.keys or {}) do
      local v = type(k[3]) == "string" and crc(k[3]) or k[3]
      put_key(comp, k[1], k[2], v)
    end
    wml.write_u32(buf + 0x10, 0x979E75B2)
    local blast = P._prefab_id(r[2] .. ".cprefab_pc")
    for section = 0, 1 do wml.call(wml.base + 0x1C001E0, comp, buf + 0x10, section, blast, name) end
  end
  local n = wml.read_u32(comp + 0x1CE8)
  local rare = (n + 1) % (P.nth_every or 5) == 0
  if rare == nth.flip then return end
  nth.flip = rare
  put_key(comp, 0x30B4E7EA, 3, rare and 0xDF712A1B or nth.own_type)   -- shot_type: projectile, or the gun's own
  wml.write_u32(buf + 0x10, 0x8A4357A7)
  for section = 0, 1 do wml.call(wml.base + 0x1C001E0, comp, buf + 0x10, section, rare and nth.rare or nth.own, name) end
end

-- ------------------------------------------------------------------ fire sound
-- comp + section * 0x6A0 + 0x134, a gml_weapon_fire_audio name hash, turned into a bank at spawn (+1BFE820). Whether the shot reads it again: not known.
P.fire_sound = false
local snd = {}
function P.fire_sound_active() return P.fire_sound or snd.id end
function P.update_fire_sound()
  local id, _, comp = gun()
  if not id then return end
  if snd.id == id and snd.want == P.fire_sound then return end
  if snd.id == id and not P.fire_sound then
    wml.write_u32(comp + 0x134, snd.orig)
    snd = {}
    wml.call(wml.base + 0x1BFE820, comp)
    return
  end
  if not P.fire_sound then snd = {}; return end
  if snd.id ~= id then snd = { id = id, orig = wml.read_u32(comp + 0x134) } end
  snd.want = P.fire_sound
  wml.write_u32(comp + 0x134, P.fire_sound)
  wml.call(wml.base + 0x1BFE820, comp)
end

-- ------------------------------------------------------------------ what the back-to-normal rows ask
function P.mix_off()
  P.sig_from, P.sig_from2, P.bullet_blast, P.fire_mode, P.nth_round, P.fire_sound = false, false, false, false, false, false
end
return P
