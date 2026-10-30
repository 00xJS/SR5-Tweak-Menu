-- SR5 Tweak Menu - the player: health and position.
--
-- +1B432F0(0) gives the local player's object (an entry in the game's object
-- table, 0x90 bytes). Its position is three fixed-point ints at +0x30
-- (x, height, z; units of 1/10000 m). +48AF90(object) gives its health
-- component, as the game's get_health_from_object reads it:
--   +0xE8 min health (health can't drop below it), +0xEC max, +0xF0 current,
--   +0xFC max shield, +0x100 shield.
-- God mode raises the min to the max every frame: the game's own floor, so
-- nothing goes through the cheat system and the save stays clean.

local P = { god = false, health_mult = 1 }
local GET_PLAYER, GET_HEALTH = 0x1B432F0, 0x48AF90
local MIN, MAX, CUR = 0xE8, 0xEC, 0xF0
local orig_min, orig_max, written_max, mult_applied_to

function P.object()
  local ok, p = pcall(wml.call, wml.base + GET_PLAYER, 0)
  return ok and p ~= 0 and p or nil
end

function P.health_component()
  local p = P.object()
  if not p then return nil end
  local ok, h = pcall(wml.call, wml.base + GET_HEALTH, p)
  return ok and h ~= 0 and h or nil
end

function P.health()
  local h = P.health_component()
  if not h then return nil end
  return wml.read_f32(h + CUR), wml.read_f32(h + MAX)
end

function P.refill()
  local h = P.health_component()
  if not h then return false end
  wml.write_f32(h + CUR, wml.read_f32(h + MAX))
  return true
end

local function s32(v) return v >= 0x80000000 and v - 0x100000000 or v end
function P.position()
  local p = P.object()
  if not p then return nil end
  return s32(wml.read_u32(p + 0x30)) / 10000, s32(wml.read_u32(p + 0x34)) / 10000, s32(wml.read_u32(p + 0x38)) / 10000
end

-- The game's own teleport (its UI uses it for fast travel to a position).
function P.teleport(x, y, z)
  local ok, r = wml.game(string.format("return player_local_teleport_to_position(%.4f, %.4f, %.4f)", x, y, z))
  return ok
end

-- Every frame: god mode and the health multiplier.
function P.update()
  local h = P.health_component()
  if not h then return end
  -- health multiplier: max health = the game's own max x the multiplier.
  -- A max we didn't write is the game's own (first time, respawn, level up).
  local max = wml.read_f32(h + MAX)
  if P.health_mult ~= 1 then
    if h ~= mult_applied_to or not written_max or math.abs(max - written_max) > 0.5 then orig_max = max end
    local want = orig_max * P.health_mult
    if math.abs(max - want) > 0.5 then wml.write_f32(h + MAX, want) end
    written_max, mult_applied_to = want, h
  elseif written_max then
    if h == mult_applied_to and orig_max then wml.write_f32(h + MAX, orig_max) end
    local m = wml.read_f32(h + MAX)
    if wml.read_f32(h + CUR) > m then wml.write_f32(h + CUR, m) end
    written_max, mult_applied_to, orig_max = nil, nil, nil
  end
  if P.god then
    if not orig_min then orig_min = wml.read_f32(h + MIN) end
    local max = wml.read_f32(h + MAX)
    wml.write_f32(h + MIN, max)
    if wml.read_f32(h + CUR) < max then wml.write_f32(h + CUR, max) end
  elseif orig_min then
    wml.write_f32(h + MIN, orig_min)
    orig_min = nil
  end
end

-- ------------------------------------------------------------------ components
-- Any component of the player: the game's getter +19E8C40(object, {&type,
-- &flag}) gives a handle (low byte: pool, the rest: slot); the pool table is
-- at *(+5CB3F70), 0xD0 bytes a pool: element size +0xB4, base +0x28. This is
-- the whole of +48AF90 (health is type 0x8D).
local COMPONENT_GET, POOLS = 0x19E8C40, 0x5CB3F70
local cbuf
function P.component(ctype, object)
  local p = object or P.object()
  if not p then return nil end
  cbuf = cbuf or wml.buffer(3)
  wml.write_u64(cbuf, cbuf + 0x20)
  wml.write_u64(cbuf + 8, cbuf + 0x28)
  wml.write_u32(cbuf + 0x20, ctype)
  wml.write_u8(cbuf + 0x28, 0)
  local ok, h = pcall(wml.call, wml.base + COMPONENT_GET, p, cbuf)
  if not ok then return nil end
  h = h & 0x1FFFFFF
  if h == 0 then return nil end
  local pool = wml.read_u64(wml.base + POOLS) + (h & 0xFF) * 0xD0
  return (h >> 8) * wml.read_u32(pool + 0xB4) + wml.read_u64(pool + 0x28)
end

-- The vehicle you're in: the game's enemy_get_occupied_vehicle() gives an
-- object userdata (payload: its id); ids map to object table entries through
-- *(+5CB5440) (& 0x3FFFFFFF), entries are 0x90 bytes at *(+45E8458), as the
-- game's get_health_from_object does.
function P.vehicle_object()
  local ok, v = wml.game("local v = enemy_get_occupied_vehicle(gml_get_local_player()) if v == nil or tostring(v) == 'Invalid' then return nil end return v")
  local ud = ok and type(v) == "string" and tonumber(v:match("(%x+)>$") or "", 16)
  if not ud then return nil end
  local id = wml.read_u32(ud + 0x28)
  local idx = wml.read_u32(wml.read_u64(wml.base + 0x5CB5440) + id * 4) & 0x3FFFFFFF
  if idx == 0x3FFFFFFF then return nil end
  return wml.read_u64(wml.base + 0x45E8458) + idx * 0x90
end

-- An object table entry from an object id (nil if it's gone).
function P.entry_of(id)
  if not id or id == 0 then return nil end
  local idx = wml.read_u32(wml.read_u64(wml.base + 0x5CB5440) + id * 4) & 0x3FFFFFFF
  if idx == 0x3FFFFFFF then return nil end
  return wml.read_u64(wml.base + 0x45E8458) + idx * 0x90
end

-- Vehicle god mode (experimental): the vehicle's own health component, type
-- 0x44 (get_vehicle_health_from_object, +A03E00, reads it): +0x00 max hit
-- points, +0x78 current, +0x88 min; byte +0x56 flags, 0x01 indestructible,
-- 0x04 invulnerable (hit points can't change). Both set, health kept full;
-- the flags go back when it's off or you leave the vehicle.
P.vgod = false
local VH_MAX, VH_CUR, VH_FLAGS = 0x00, 0x78, 0x56
local vgod_orig = {}   -- [health component] = original flags
function P.update_vehicle()
  local v = P.vgod and P.vehicle_object()
  local h = v and P.component(0x44, v)
  for comp, flags in pairs(vgod_orig) do
    if comp ~= h then wml.write_u8(comp + VH_FLAGS, flags); vgod_orig[comp] = nil end
  end
  if not h then return end
  if not vgod_orig[h] then vgod_orig[h] = wml.read_u8(h + VH_FLAGS) end
  wml.write_u8(h + VH_FLAGS, vgod_orig[h] | 0x05)
  local max = wml.read_f32(h + VH_MAX)
  if max > 0 and wml.read_f32(h + VH_CUR) < max then wml.write_f32(h + VH_CUR, max) end
end
function P.vgod_active() return P.vgod or next(vgod_orig) ~= nil end

-- Health regen (experimental), in the health component: +0x150 regen
-- behaviour (0 the game's, 2 always back to full, 3 none), +0x158 regen a
-- second, +0x15C the wait after a hit (ms). "fast": five times the rate, no
-- wait. The originals go back when it's set to the game's.
P.regen = "game"
local regen_orig = {}   -- [health component] = { behaviour, rate, wait }
function P.update_regen()
  local h = P.health_component()
  for comp, o in pairs(regen_orig) do
    if comp ~= h or P.regen == "game" then
      wml.write_u32(comp + 0x150, o[1]); wml.write_u32(comp + 0x158, o[2]); wml.write_u32(comp + 0x15C, o[3])
      regen_orig[comp] = nil
    end
  end
  if not h or P.regen == "game" then return end
  local o = regen_orig[h]
  if not o then
    o = { wml.read_u32(h + 0x150), wml.read_u32(h + 0x158), wml.read_u32(h + 0x15C) }
    regen_orig[h] = o
  end
  local beh, rate, wait = o[1], o[2], o[3]
  if P.regen == "none" then beh = 3
  elseif P.regen == "full" then beh = 2
  elseif P.regen == "fast" then rate, wait = math.max(o[2] * 5, 50), 0 end
  if wml.read_u32(h + 0x150) ~= beh then wml.write_u32(h + 0x150, beh) end
  if wml.read_u32(h + 0x158) ~= rate then wml.write_u32(h + 0x158, rate) end
  if wml.read_u32(h + 0x15C) ~= wait then wml.write_u32(h + 0x15C, wait) end
end
function P.regen_active() return P.regen ~= "game" or next(regen_orig) ~= nil end

-- The map waypoint: the game's GPS slots, 4 of 0x1C bytes at +3BFA170 (slot
-- 0 the local player's, as gps_start sets it): +0xC the target's object id,
-- +0x18 a byte set while it's active. Returns its position, or nil.
function P.waypoint()
  for slot = 0, 3 do
    local s = wml.base + 0x3BFA170 + slot * 0x1C
    if wml.read_u8(s + 0x18) ~= 0 then
      local e = P.entry_of(wml.read_u32(s + 0xC))
      if e then return s32(wml.read_u32(e + 0x30)) / 10000, s32(wml.read_u32(e + 0x34)) / 10000, s32(wml.read_u32(e + 0x38)) / 10000, slot end
    end
  end
  return nil
end

-- No fall damage: the game's human_collision_system_config ("default"),
-- m_fall_config: falling faster than instant_death_velocity (22 m/s in play)
-- kills, faster than minimum_damage_velocity (12) hurts; the same for the
-- wingsuit, surfing and motorcycles. All raised to 1000 m/s while it's on.
local FALL = {}
for _, f in ipairs({ "instant_death_velocity", "minimum_damage_velocity", "instant_death_velocity_wingsuit", "minimum_damage_velocity_wingsuit",
                     "instant_death_velocity_surfing", "minimum_damage_velocity_surfing", "instant_death_velocity_moto", "minimum_damage_velocity_moto" }) do
  FALL[#FALL + 1] = { path = "m_fall_config." .. f, what = f }
end
P.no_fall = false
local fall_entries, fall_written
function P.update_fall()
  if not fall_entries then
    fall_entries = require("vdata").collect("human_collision_system_config", FALL)
    if #fall_entries == 0 then fall_entries = nil; return end
  end
  local V = require("vdata")
  for _, e in ipairs(fall_entries) do
    local want = P.no_fall and 1000 or e.orig
    if V.read(e.addr, e.t) ~= want then V.write(e.addr, e.t, want) end
  end
  fall_written = P.no_fall
end
function P.fall_active() return P.no_fall or fall_written end

-- Everyone near you: the object table (0x90-byte entries at *(+45E8458)),
-- entry i live when bit i of *(+4757300) is clear and (below *(+4724650))
-- bit i of *(+4724648) is set, count *(+4757308); people are the live
-- entries with a human health component (0x8D), you left out.
function P.people_near(radius)
  local B = wml.base
  local base, n = wml.read_u64(B + 0x45E8458), wml.read_u32(B + 0x4757308)
  local free_bits, live_bits, live_n = wml.read_u64(B + 0x4757300), wml.read_u64(B + 0x4724648), wml.read_u32(B + 0x4724650)
  local px, py, pz = P.position()
  local me = P.object()
  local out = {}
  if not px or base == 0 then return out end
  local r2 = radius * radius
  for i = 0, n - 1 do
    if ((wml.read_u8(free_bits + (i >> 3)) >> (i & 7)) & 1) == 0 and (i >= live_n or ((wml.read_u8(live_bits + (i >> 3)) >> (i & 7)) & 1) == 1) then
      local e = base + i * 0x90
      local dx, dz = s32(wml.read_u32(e + 0x30)) / 10000 - px, s32(wml.read_u32(e + 0x38)) / 10000 - pz
      if dx * dx + dz * dz < r2 and e ~= me then
        local dy = s32(wml.read_u32(e + 0x34)) / 10000 - py
        if dx * dx + dy * dy + dz * dz < r2 then
          local h = P.component(0x8D, e)
          if h then out[#out + 1] = { entry = e, health = h } end
        end
      end
    end
  end
  return out
end

-- Ragdoll: the game's start-ragdoll (+18A5860(entry, 2 owner, 200 ms blend,
-- the zero vector +3C44930, no impulse, 0)), for people with a ragdoll
-- (component type 2); confirmed in play. Kill, in two steps: health at 0
-- alone leaves people "down but not out" (seen in play), so first that's
-- switched off for each of them, as the game's
-- human_health_disable_dbno_on_death_node does: a reference on their handle
-- (the count at *(+2EB2330) + id * 4), then +3EEFD0(&id, 0), which releases
-- it and sends the change on (it may land a frame later). Then, some frames
-- on, the health range is pinned to 0 and the game's health setter (+3E58F0,
-- the source the script node passes, +3C1F3F8) runs the death. People with a
-- minimum health (mission characters) are left alone.
function P.ragdoll_near(radius)
  local n = 0
  for _, p in ipairs(P.people_near(radius)) do
    if P.component(2, p.entry) then wml.call(wml.base + 0x18A5860, p.entry, 2, 200, wml.base + 0x3C44930, 1, 0); n = n + 1 end
  end
  return n
end
-- Step 1: returns the people to kill ({ id, entry }), "down but not out" off.
function P.kill_prepare(radius)
  local out = {}
  local refs = wml.read_u64(wml.base + 0x2EB2330)
  local buf = wml.buffer(13)
  for _, p in ipairs(P.people_near(radius)) do
    local h = p.health
    if wml.read_f32(h + 0xE8) <= 0 and wml.read_f32(h + 0xF0) > 0 then
      local id = wml.read_u32(p.entry + 0x58)
      wml.write_u32(refs + id * 4, wml.read_u32(refs + id * 4) + 1)
      wml.write_u32(buf, id)
      wml.call(wml.base + 0x3EEFD0, buf, 0)
      out[#out + 1] = { id = id }
    end
  end
  return out
end
-- Step 2: the deaths, for those still there.
function P.kill_finish(list)
  local n = 0
  for _, k in ipairs(list) do
    local e = P.entry_of(k.id)
    local h = e and wml.read_u32(e + 0x58) == k.id and P.component(0x8D, e)
    if h and wml.read_f32(h + 0xF0) > 0 then
      wml.write_f32(h + 0xE8, 0); wml.write_f32(h + 0xEC, 0)
      wml.call(wml.base + 0x3E58F0, h, 0, wml.base + 0x3C1F3F8)
      n = n + 1
    end
  end
  return n
end

-- Special ammo on the gun in your hands: the per-gun property override
-- (+1BFF510(weapon component, &key, 0, &value, name), as the game's set-
-- status-effect node does; component from +49F8A0(+1C1F420(&gun id))).
-- value: 16 bytes, the value at +0 and its type at +8 (1 float, 3 enum).
-- Keys: status_effect, its magnitude, duration, damage and damage type.
-- Only that gun changes; a new gun in your hands gets it too.
P.ammo = false   -- false or { effect name, damage type name }
local ammo_gun
local function crc(name)
  local ok, v = wml.game("return string_crc(" .. string.format("%q", name) .. ")")
  return ok and type(v) == "number" and (math.floor(v) & 0xFFFFFFFF) or 0
end
function P.update_ammo(force)
  local ok, s = wml.game("return tostring(gml_get_local_player_weapon())")
  local id = ok and tonumber((s or ""):match("object (%x+)") or "", 16)
  if not id or id == 0 then return end
  if id == ammo_gun and not force then return end
  local buf = wml.buffer(10)
  wml.write_u32(buf, id)
  local entry = wml.call(wml.base + 0x1C1F420, buf)
  local comp = entry ~= 0 and wml.call(wml.base + 0x49F8A0, entry) or 0
  if comp == 0 then return end
  local name = wml.buffer(11, "sr5_tweak_menu")
  local function set(key, value, kind)
    wml.write_u32(buf + 0x10, key)
    for i = 0, 15, 4 do wml.write_u32(buf + 0x20 + i, 0) end
    if kind == "f" then wml.write_f32(buf + 0x20, value); wml.write_u32(buf + 0x28, 1)
    else wml.write_u32(buf + 0x20, value); wml.write_u32(buf + 0x28, 3) end
    wml.call(wml.base + 0x1BFF510, comp, buf + 0x10, 0, buf + 0x20, name)
  end
  local a = P.ammo
  set(73301821, a and crc(a[1]) or 0, "e")                -- status_effect
  set(2640671745, 1.0, "f")                               -- status_effect_magnitude
  set(216245579, a and 4.0 or 1.0, "f")                   -- status_effect_duration
  set(1310126570, a and 20.0 or 0.0, "f")                 -- status_effect_damage
  set(1026999258, crc(a and a[2] or "physical"), "e")     -- status_effect_damage_type
  ammo_gun = id
end

-- Homie limit: how many homies can follow you is 1 + the stat
-- passive_mod_class_extra_homies; without the perk that owns it, the stat is
-- the class default, a float at +3C0DC10 + index * 0x10 + 8 (table of 0x10-
-- byte entries, the class's name crc at +0, count u32 at +5BE5DA0; read live:
-- index 141, default 0). With the perk owned, the perk decides.
P.homies = 1
local homie_default
local function homie_stat()
  local n = wml.read_u32(wml.base + 0x5BE5DA0)
  for i = 0, math.min(n, 1000) - 1 do
    local e = wml.base + 0x3C0DC10 + i * 0x10
    if wml.read_u32(e) == 0xF448041B then return e + 8 end
  end
  return nil
end
function P.update_homies()
  local a = homie_stat()
  if not a then return end
  if not homie_default then homie_default = wml.read_f32(a) end
  local want = P.homies == 1 and homie_default or (P.homies - 1)
  if wml.read_f32(a) ~= want then wml.write_f32(a, want) end
  if P.homies == 1 then homie_default = nil end
end
function P.homies_active() return P.homies ~= 1 or homie_default ~= nil end

-- People the menu spawned (their object ids), and removing them: +1E6920(&id)
-- destroys an object (the game's "gameplay util destroy"). An entry's own id
-- is at +0x58; ids are reused, so an id is only removed while its entry still
-- carries it.
P.spawned = {}
function P.remember(entry) if entry then P.spawned[#P.spawned + 1] = wml.read_u32(entry + 0x58) end end
function P.remove_spawned()
  local n = 0
  for _, id in ipairs(P.spawned) do
    local e = P.entry_of(id)
    if e and wml.read_u32(e + 0x58) == id then wml.call(wml.base + 0x1E6920, e + 0x58); n = n + 1 end
  end
  P.spawned = {}
  return n
end

-- Spawning: the game's own spawner (game_customize_anywhere_spawn_lightrig,
-- +454980) step by step, so the position can be moved: look up the prefab
-- (+E8E370), request it (+E8EA40, type 7), fill the spawn struct (+1A9D3F0;
-- [0] prefab, +0x10..+0x4B the player's transform, position ints at +0x40,
-- +0x44 height, +0x48; +0x50 the layer id from +484F40(+4AA4328)+0x34),
-- spawn (+4AE810). Returns the new object, or nil.
function P.spawn_prefab(name, up, side, ahead)
  local B = wml.base
  local player = P.object()
  if not player or not name then return nil end
  local namep = wml.buffer(5, name)
  local filep = wml.buffer(7, "sr5_tweak_menu")
  local params = wml.buffer(6)
  local srid = wml.call(B + 0xE8E370, namep)
  if srid == 0 then return nil end
  wml.call(B + 0xE8EA40, srid, namep, 7)
  local layer = wml.call(B + 0x484F40, B + 0x4AA4328)
  if layer == 0 then return nil end
  for i = 0, 0x1F0, 8 do wml.write_u64(params + i, 0) end
  wml.call(B + 0x1A9D3F0, params)
  wml.write_u64(params, srid)
  for i = 0, 0x38, 4 do wml.write_u32(params + 0x10 + i, wml.read_u32(player + i)) end
  local function add(off, metres) wml.write_u32(params + off, (s32(wml.read_u32(params + off)) + math.floor(metres * 10000)) & 0xFFFFFFFF) end
  add(0x40, side or 0)
  add(0x44, up or 0)
  add(0x48, ahead or 0)
  wml.write_u32(params + 0x50, wml.read_u32(layer + 0x34))
  local obj = wml.call(B + 0x4AE810, 0, params, 0, filep, 1)
  return obj ~= 0 and obj or nil
end

-- Spawning a person the game's way (heads, outfits): the NPC spawner, as the
-- homie summon and encounters call it. +B39E90(&context, &id, 0, &transform,
-- &category) builds the context (id: the npc_variant's name hash; transform:
-- the player's 0x3C bytes, position moved; category: the u32 at +3C3CC38),
-- then +B3B580(0, &context, 0, 0, file, line) spawns it.
function P.spawn_npc(id, side, ahead)
  local B = wml.base
  local player = P.object()
  if not player or not id then return nil end
  local ctx, misc = wml.buffer(8), wml.buffer(9)
  for i = 0, 4088, 8 do wml.write_u64(ctx + i, 0) end
  for i = 0, 0x38, 4 do wml.write_u32(misc + i, wml.read_u32(player + i)) end
  local function add(off, metres) wml.write_u32(misc + off, (s32(wml.read_u32(misc + off)) + math.floor(metres * 10000)) & 0xFFFFFFFF) end
  add(0x30, side or 0)
  add(0x38, ahead or 0)
  wml.write_u32(misc + 0x100, id)
  wml.write_u32(misc + 0x108, wml.read_u32(B + 0x3C3CC38))
  wml.call(B + 0xB39E90, ctx, misc + 0x100, 0, misc, misc + 0x108)
  local obj = wml.call(B + 0xB3B580, 0, ctx, 0, 0, wml.buffer(7, "sr5_tweak_menu"), 1)
  -- it gives back the new person's entry (callers read its id at +0x58)
  if obj ~= 0 then P.remember(obj) end
  return obj ~= 0 and obj or nil
end

-- Vehicle handling (experimental): the vehicle's wheeled locomotion
-- component (type 0x12) keeps the handling it drives with in a block at
-- +0x8BC (each value resolved from the vehicle's data): +0x04 / +0x0C wheel
-- friction and max friction multipliers (flag byte +0x10), +0x2C steering
-- max angle (radians) and +0x30 the speed it's allowed up to (flag +0x48),
-- +0x5C max torque (flag +0x60), +0x74 top speed, m/s (flag +0x78). The
-- block in use is the pointer at +0x1DE8: the vehicle's own, or (seen live
-- while the player drives) the player's handling block at +0x1DD8, or a
-- mission's at +0x1DE0, which is left alone. The menu changes the block in
-- use; originals are kept per block. +1B67C30(component, block, 1) pushes a
-- block into the live physics, for the categories whose flag is set: it's
-- called after each change.
P.car = { power = 1, top = 1, grip = 1, steer = 1 }
local BLOCK, PLAYER_BLOCK, IN_USE, APPLY = 0x8BC, 0x1DD8, 0x1DE8, 0x1B67C30
local CAR = {
  power = { offs = { 0x5C }, flag = 0x60 }, top = { offs = { 0x74 }, flag = 0x78 },
  grip = { offs = { 0x04, 0x0C }, flag = 0x10 }, steer = { offs = { 0x2C, 0x30 }, flag = 0x48 },
}
local car_orig = {}   -- [block address] = { [block offset] = original value or flag }
function P.update_car()
  local v = P.vehicle_object()
  local c = v and P.component(0x12, v)
  if not c then return end
  local used = wml.read_u64(c + IN_USE)
  local b
  if used == 0 or used == c + BLOCK then b = c + BLOCK
  elseif used == wml.read_u64(c + PLAYER_BLOCK) then b = used
  else return end   -- a mission's own handling
  local o = car_orig[b]
  if not o then
    o = {}
    for _, cat in pairs(CAR) do
      for _, off in ipairs(cat.offs) do o[off] = wml.read_f32(b + off) end
      o[cat.flag] = wml.read_u8(b + cat.flag)
    end
    car_orig[b] = o
  end
  local changed, restored = false, {}
  for key, cat in pairs(CAR) do
    for _, off in ipairs(cat.offs) do
      local want = o[off] * P.car[key]
      if wml.read_f32(b + off) ~= want then
        wml.write_f32(b + off, want)
        changed = true
        if P.car[key] == 1 then restored[#restored + 1] = cat.flag end
      end
    end
    if P.car[key] ~= 1 and wml.read_u8(b + cat.flag) ~= 1 then wml.write_u8(b + cat.flag, 1); changed = true end
  end
  if changed then
    wml.call(wml.base + APPLY, c, b, 1)
    -- back to the game's: its own flag again, once the originals are pushed
    for _, flag in ipairs(restored) do wml.write_u8(b + flag, o[flag]) end
  end
end
function P.car_on() for _, v in pairs(P.car) do if v ~= 1 then return true end end return false end

-- Movement (experimental): the character locomotion component (type 0x1F).
-- From +D0, in the reflection's order: gravity multiplier, walk, run, on-foot
-- gain, in-air gain, in-air acceleration, swim gain, swim acceleration.
P.move = { run = 1, air = 1, swim = 1, gravity = 1 }
local MOVE = { run = { 0xD4, 0xD8 }, air = { 0xE0, 0xE4 }, swim = { 0xE8, 0xEC }, gravity = { 0xD0 } }
local move_orig = {}   -- [component address] = { [offset] = original }
function P.update_move()
  local c = P.component(0x1F)
  if not c then return end
  local o = move_orig[c]
  if not o then
    o = {}
    for _, offs in pairs(MOVE) do for _, off in ipairs(offs) do o[off] = wml.read_f32(c + off) end end
    move_orig = { [c] = o }   -- (one player: forget older components)
  end
  for key, offs in pairs(MOVE) do
    for _, off in ipairs(offs) do
      local want = o[off] * P.move[key]
      if wml.read_f32(c + off) ~= want then wml.write_f32(c + off, want) end
    end
  end
end
function P.move_on()
  local m = P.move
  return m.run ~= 1 or m.air ~= 1 or m.swim ~= 1 or m.gravity ~= 1
end

-- ------------------------------------------------------------------ saved places
P.places = {}
local PLACES = wml.root .. "\\saved_places.txt"

function P.load_places()
  P.places = {}
  local f = io.open(PLACES, "r")
  if not f then return end
  for line in f:lines() do
    local name, x, y, z = line:match("^(.-)\t([%-%d%.]+)\t([%-%d%.]+)\t([%-%d%.]+)$")
    if name then P.places[#P.places + 1] = { name = name, x = tonumber(x), y = tonumber(y), z = tonumber(z) } end
  end
  f:close()
end

function P.save_places()
  local f = io.open(PLACES, "w")
  if not f then return false end
  for _, p in ipairs(P.places) do f:write(string.format("%s\t%.4f\t%.4f\t%.4f\n", p.name, p.x, p.y, p.z)) end
  f:close()
  return true
end

function P.save_here()
  local x, y, z = P.position()
  if not x then return nil end
  local place = { name = "Place " .. (#P.places + 1), x = x, y = y, z = z }
  P.places[#P.places + 1] = place
  P.save_places()
  return place
end

P.load_places()
return P
