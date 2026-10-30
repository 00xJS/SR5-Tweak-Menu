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
  if not id or id == 0 or id >= 0x100000 then return nil end   -- (a bad id would read outside the table)
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
-- entries with a human health component (0x8D), you left out. (Vehicles: 0x44.)
local function objects_near(radius, ctype)
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
          local h = P.component(ctype, e)
          if h then out[#out + 1] = { entry = e, health = h } end
        end
      end
    end
  end
  return out
end
function P.people_near(radius) return objects_near(radius, 0x8D) end

-- Cash on the ground: the game's pickup spawner, +689830(0, 2, &source (none,
-- +3C44910), &{ collectible, amount }, &transform, 0, 0), as its loot code
-- calls it; the collectible from +13E2780(&cash hash, at +3C1A45C), the
-- transform the player's with the position moved. Confirmed in play: within a
-- few metres it's collected at once, further away it lies there until you
-- come close. It's real money: it stays in your save. Any collectible_weapon_info
-- name hash drops that weapon the same way (walking onto it awards it).
function P.drop_pickup(hash, amount, side, up, ahead)
  local B, e = wml.base, P.object()
  if not e then return false end
  local fx, fz = wml.read_f32(e + 0x20), wml.read_f32(e + 0x28)
  local buf = wml.buffer(4)
  for i = 0, 0x78, 8 do wml.write_u64(buf + i, 0) end
  wml.write_u32(buf, hash)
  local obj = wml.call(B + 0x13E2780, buf)
  if obj == 0 then return false end
  wml.write_u32(buf + 0x08, wml.read_u32(B + 0x3C44910))
  wml.write_u64(buf + 0x10, obj)
  wml.write_u32(buf + 0x18, amount)
  for i = 0, 0x38, 4 do wml.write_u32(buf + 0x20 + i, wml.read_u32(e + i)) end
  local function add(off, m) wml.write_u32(buf + 0x20 + off, (s32(wml.read_u32(buf + 0x20 + off)) + math.floor(m * 10000)) & 0xFFFFFFFF) end
  add(0x30, fx * ahead + fz * side); add(0x34, up); add(0x38, fz * ahead - fx * side)
  return wml.call(B + 0x689830, 0, 2, buf + 8, buf + 0x10, buf + 0x20, 0, 0) & 0xFF ~= 0
end
function P.drop_cash(amount, side, up, ahead)
  return P.drop_pickup(wml.read_u32(wml.base + 0x3C1A45C), amount, side, up, ahead)
end
-- Money rain: every `rain` frames a small pile, somewhere around you, falling.
P.rain = false
local rain_wait = 0
function P.update_rain()
  rain_wait = rain_wait - 1
  if rain_wait > 0 then return end
  rain_wait = P.rain
  local a, r = math.random() * 2 * math.pi, 8 + math.random() * 14
  P.drop_cash(250, math.cos(a) * r, 10 + math.random() * 10, math.sin(a) * r)
end

-- Everyone near: an AI reaction (+3603F0(ai, &name hash, 0, 0, 1), the AI's own
-- emote call; names from the class ai_emote_table), disarm (+35A110(ai)) and
-- re-arm (+35A370(ai)). The AI from +48A760(entry). (+A928B0, the avatar emote
-- call, plays on the player whatever id it's given.)
function P.near_reaction(name, radius)
  local _, v = wml.game("return string_crc(" .. string.format("%q", name) .. ")")
  local buf = wml.buffer(4)
  wml.write_u32(buf, math.floor(v) & 0xFFFFFFFF)
  local n = 0
  for _, q in ipairs(P.people_near(radius)) do
    local ai = wml.call(wml.base + 0x48A760, q.entry)
    if ai ~= 0 then wml.call(wml.base + 0x3603F0, ai, buf, 0, 0, 1); n = n + 1 end
  end
  return n
end
function P.near_arms(armed, radius)
  local n = 0
  for _, q in ipairs(P.people_near(radius)) do
    local ai = wml.call(wml.base + 0x48A760, q.entry)
    if ai ~= 0 then wml.call(wml.base + (armed and 0x35A370 or 0x35A110), ai); n = n + 1 end
  end
  return n
end

-- Free shopping: every store price is a store_category_info's m_cost times a
-- per-item float, and a total of 0 skips the payment. The costs go to 0 while
-- it's on and back when it's off; they're the game's data, not your save.
P.free_shop = false
local shop_entries, shop_set
function P.update_free_shop()
  local V = require("vdata")
  if P.free_shop and not shop_entries then
    shop_entries = V.collect("store_category_info", { { path = "m_cost", what = "cost" } })
  end
  if not shop_entries or (P.free_shop and true or false) == shop_set then return shop_entries and #shop_entries or 0 end
  for _, e in ipairs(shop_entries) do V.write(e.addr, e.t, P.free_shop and 0 or e.orig) end
  shop_set = P.free_shop and true or false
  return #shop_entries
end

-- Your gravity: the locomotion component's +0x2A8 (read every frame into the
-- physics request's gravity factor; default 1). Run speed's component too.
P.no_clip = false
local grav_written
function P.update_gravity()
  local want = P.no_clip and 0 or P.move.gravity
  if want == 1 and not grav_written then return end
  local c = P.component(0x10)
  if c then wml.write_f32(c + 0x2A8, want) end
  grav_written = want ~= 1
end

-- No clip: collision off (component message: +486CE0(entry, 0, 0x10, 0, &byte),
-- as physics_enable_collision_node does), no gravity, the mode that takes the
-- requested velocity as it is (+0x4B2 = 1), and the extra velocity moved by
-- keys along where you face: W A S D, Space up, Ctrl down, Shift fast.
local clip_on
function P.update_clip()
  local e = P.object()
  local c = e and P.component(0x10)
  if not c then return end
  if P.no_clip ~= (clip_on or false) then
    local buf = wml.buffer(4)
    wml.write_u8(buf, P.no_clip and 0 or 1)
    wml.call(wml.base + 0x486CE0, e, 0, 0x10, 0, buf)
    wml.write_u8(c + 0x4B2, P.no_clip and 1 or 0)
    clip_on = P.no_clip
    P.update_gravity()
  end
  if not P.no_clip then return end
  wml.write_f32(c + 0x2A8, 0)
  local fx, fz, rx, rz = wml.read_f32(e + 0x20), wml.read_f32(e + 0x28), wml.read_f32(e + 0x00), wml.read_f32(e + 0x08)
  local speed = wml.key_down("SHIFT") and 40 or 12
  local f = (wml.key_down("W") and 1 or 0) - (wml.key_down("S") and 1 or 0)
  local r = (wml.key_down("D") and 1 or 0) - (wml.key_down("A") and 1 or 0)
  local u = (wml.key_down("SPACE") and 1 or 0) - (wml.key_down("CTRL") and 1 or 0)
  wml.write_f32(c + 0x3A0, (fx * f + rx * r) * speed)
  wml.write_f32(c + 0x3A4, u * speed)
  wml.write_f32(c + 0x3A8, (fz * f + rz * r) * speed)
end
function P.clip_active() return P.no_clip or clip_on end

-- The vehicle you're in. Destroy: +1BA6F00(health 0x44, 0.0 hit points, &no
-- object, -1, &none, 0), what vehicle_health_set_hit_points_node calls, with
-- its "indestructible" flags cleared first. Bulletproof tires: +1B91B60(
-- component 0x6A, 1), vehicle_invulnerable_wheels_node. Suspension: the
-- physics vehicle's records, *(*(0x12 + 0x1CC0) + 0x438), 12 bytes a wheel
-- {strength, compression, expansion}; wheels = bytes 0x12 +0x1B8 + +0x378.
function P.destroy_car()
  local v = P.vehicle_object()
  local h = v and P.component(0x44, v)
  if not h then return false end
  wml.write_u8(h + 0x56, wml.read_u8(h + 0x56) & ~0x05 & 0xFF)
  wml.callf(wml.base + 0x1BA6F00, h, 0.0, wml.base + 0x48E778C, 0xFFFFFFFF, wml.base + 0x3C44910, 0)
  return true
end
P.tires = false
P.spring = 1
local tires_car, spring_orig = nil, {}
function P.update_tires()
  local v = P.vehicle_object()
  local c = v and P.component(0x6A, v)
  if not c then tires_car = nil; return end
  if c ~= tires_car or P.tires ~= P.tires_set then
    wml.call(wml.base + 0x1B91B60, c, P.tires and 1 or 0)
    tires_car, P.tires_set = c, P.tires
  end
end
function P.update_spring()
  local v = P.vehicle_object()
  local c = v and P.component(0x12, v)
  if not c then return end
  local hv = wml.read_u64(c + 0x1CC0)
  local arr = hv ~= 0 and wml.read_u64(hv + 0x438) or 0
  local n = wml.read_u8(c + 0x1B8) + wml.read_u8(c + 0x378)
  if arr == 0 or n == 0 or n > 12 then return end
  local o = spring_orig[c]
  if not o then
    if P.spring == 1 then return end
    o = {}
    for i = 0, n * 3 - 1 do o[i] = wml.read_f32(arr + i * 4) end
    spring_orig[c] = o
  end
  local changed = false
  for i = 0, n * 3 - 1 do
    local want = o[i] * P.spring
    if wml.read_f32(arr + i * 4) ~= want then wml.write_f32(arr + i * 4, want); changed = true end
  end
  if changed then wml.write_u8(c + 0x232B, wml.read_u8(c + 0x232B) | 0x40) end
end

-- Owning a weapon: +988830(record, 1), what buying one does; +988AA0(record)
-- reads it back. The record is found from one of its fields' address (the
-- reflection lookup), stepping back to where its name hash sits, at +0x34:
-- nothing is called unless that matches. Returns owned, or nil if not found.
function P.weapon_record(name)
  local q = string.format("%q", name)
  local ok, ud, hash = wml.game('local w = vlib_info_object:get_object("inventory_weapon_info", ' .. q .. ') return w.m_target_reticle, string_crc(' .. q .. ')')
  local a = ok and require("vdata").field_addr(ud)
  if not a or type(hash) ~= "number" then return nil end
  hash = math.floor(hash) & 0xFFFFFFFF
  for back = 0, 0x800, 4 do
    if wml.read_u32(a - back + 0x34) == hash then return a - back end
  end
  return nil
end
function P.own_weapon(name)
  local r = P.weapon_record(name)
  if not r then return false end
  if wml.call(wml.base + 0x988AA0, r) & 0xFF == 0 then wml.call(wml.base + 0x988830, r, 1) end
  return true
end

-- Ragdoll: the game's start-ragdoll (+18A5860(entry, 2 owner, 200 ms blend,
-- the zero vector +3C44930, no impulse, 0)), for people with a ragdoll
-- (component type 2); confirmed in play.
function P.ragdoll_near(radius)
  local n = 0
  for _, p in ipairs(P.people_near(radius)) do
    if P.component(2, p.entry) then wml.call(wml.base + 0x18A5860, p.entry, 2, 200, wml.base + 0x3C44930, 1, 0); n = n + 1 end
  end
  return n
end

-- Damage: the event weapon_request_damage_node sends, +14D3590(&packet): +0 its
-- vtable, +8 target, +C cause, +10 weapon (ids), +14 damage type (crc of a
-- damage_type name), +18 source type (crc of a name: 09C58CBC is melee), +24 amount, +28
-- and +2C 1.0, +44 -1, +48 section (4 = default). The health setter alone left
-- people standing at 0; this runs the real death (+0x104 on the health is then 1).
function P.damage(entry, amount)
  local B, me = wml.base, P.object()
  if not me then return false end
  local _, ty = wml.game('return string_crc("physical")')
  local ok, s = wml.game("return tostring(gml_get_local_player_weapon())")
  local buf = wml.buffer(4) + 0x100
  for i = 0, 0xFC, 4 do wml.write_u32(buf + i, 0) end
  wml.write_u64(buf, B + 0x2966E68)
  wml.write_u32(buf + 0x08, wml.read_u32(entry + 0x58))
  wml.write_u32(buf + 0x0C, wml.read_u32(me + 0x58))
  wml.write_u32(buf + 0x10, ok and tonumber((s or ""):match("object (%x+)") or "", 16) or 0)
  wml.write_u32(buf + 0x14, math.floor(ty) & 0xFFFFFFFF)
  wml.write_u32(buf + 0x18, 0x09C58CBC)
  wml.write_f32(buf + 0x24, amount)
  wml.write_f32(buf + 0x28, 1)
  wml.write_f32(buf + 0x2C, 1)
  wml.write_u32(buf + 0x44, 0xFFFFFFFF)
  wml.write_u32(buf + 0x48, 4)
  wml.call(B + 0x14D3590, buf)
  return true
end
-- Walk style: animation_enable_slow_walk_node (object, walking set name hash), a
-- row of walking_animsets; animation_disable_slow_walk_node (object) ends it.
P.walk_style = false
function P.update_walk()
  local e = P.object()
  if not e then return end
  local id = wml.read_u32(e + 0x58)
  if P.walk_style then
    local _, v = wml.game("return string_crc(" .. string.format("%q", P.walk_style) .. ")")
    P.node(0x18EAC80, 0x2AC22F0, { { u = id }, { u = math.floor(v) & 0xFFFFFFFF } })
  else
    P.node(0x18EAE60, 0x2AD32E8, { { u = id } })
  end
end

-- Sides: faction_set_faction_disposition_node (a, b, 1 hostile .. 3 neutral .. 5 allied),
-- one way, so set both; faction_restore_faction_disposition_node undoes it. The table
-- already has gangs neutral to the Saints: what makes them shoot you is notoriety, so a
-- gang on your side also needs Never wanted to stay quiet. You're faction "saints".
local function crc_of(name)
  local _, v = wml.game("return string_crc(" .. string.format("%q", name) .. ")")
  return math.floor(v) & 0xFFFFFFFF
end
local function set_side(a, b, d)
  a, b = crc_of(a), crc_of(b)
  if d then
    P.node(0xADEC50, 0x29E7320, { { u = a }, { u = b }, { u = d } })
    P.node(0xADEC50, 0x29E7320, { { u = b }, { u = a }, { u = d } })
  else
    P.node(0xADED00, 0x29E2C00, { { u = a }, { u = b } })
    P.node(0xADED00, 0x29E2C00, { { u = b }, { u = a } })
  end
end
P.side_gang, P.saints_enemies = false, false
local GANGS = { "idol", "panteros", "marshal", "police" }
local side_was, enemies_was = false, false
function P.update_sides()
  if P.side_gang ~= side_was then
    for _, g in ipairs(GANGS) do
      if side_was == g or side_was == "all" then set_side(g, "saints") end
      if P.side_gang == g or P.side_gang == "all" then set_side(g, "saints", 5) end
    end
    side_was = P.side_gang
  end
  if P.saints_enemies ~= enemies_was then
    for _, f in ipairs({ "saints friendly", "saints_hq", "saints_hostile" }) do set_side(f, "saints", P.saints_enemies and 1 or nil) end
    enemies_was = P.saints_enemies
  end
end

-- Rewards: damage_scaling_set_damage_source_resistance_node (object, source name hash,
-- 0 to 1), a list on your component 0x82. The same again after a respawn. The crash
-- sources are guesses at the names.
P.proof_bullets, P.proof_explosions, P.proof_crashes = false, false, false
local PROOF = { proof_bullets = { "ranged" }, proof_explosions = { "explosion", "fire" }, proof_crashes = { "collision", "object collision" } }
local proof_set = {}
function P.proof_active()
  return P.proof_bullets or P.proof_explosions or P.proof_crashes or next(proof_set) ~= nil
end
function P.update_proof()
  local e = P.object()
  if not e then return end
  local id = wml.read_u32(e + 0x58)
  for key, sources in pairs(PROOF) do
    local on = P[key] and true or false
    if on or proof_set[key] then
      for _, src in ipairs(sources) do P.node(0x6976D0, 0x29D0410, { { u = id }, { u = crc_of(src) }, { f = on and 1.0 or 0.0 } }) end
      proof_set[key] = on or nil
    end
  end
end

-- Notoriety forgets fast: the config at *(+4BA0DB8), +0x48 and +0x4C, seconds until
-- notoriety clears out of sight (+0x4C is 7 in the game's table).
P.forget_fast = false
function P.update_forget()
  local cfg = wml.read_u64(wml.base + 0x4BA0DB8)
  if cfg == 0 then return end
  SR5TM_FORGET = SR5TM_FORGET or { wml.read_u32(cfg + 0x48), wml.read_u32(cfg + 0x4C) }
  wml.write_u32(cfg + 0x48, P.forget_fast and 1 or SR5TM_FORGET[1])
  wml.write_u32(cfg + 0x4C, P.forget_fast and 1 or SR5TM_FORGET[2])
end

-- Flow, the game's ability meter: +773770(1) makes it unlimited, as a mission does.
P.flow = false
function P.update_flow() wml.call(wml.base + 0x773770, P.flow and 1 or 0) end
-- Takedown cooldown, ms: +6A0E10(ms) sets it, +6A0E40() puts it back (90 s).
P.takedown = false
function P.update_takedown()
  if P.takedown then wml.call(wml.base + 0x6A0E10, P.takedown) else wml.call(wml.base + 0x6A0E40) end
end
-- Perk values on you, without slots: +6EA430(stats, class index, &params, 0, on), then
-- +6EA6B0. Additive: off takes away exactly what on added. Class table at +3C0DC10.
local function perk(name, m, on)
  local B, e, h, i = wml.base, P.object(), crc_of(name), nil
  if not e then return false end
  for k = 0, wml.read_u32(B + 0x5BE5DA0) - 1 do if wml.read_u32(B + 0x3C0DC10 + k * 16) == h then i = k break end end
  if not i then return false end
  local c = wml.call(B + 0x4A17C0, e)
  if c == 0 then return false end
  local stats, p, none = wml.read_u64(c + 0x1050), wml.buffer(13) + 0x800, wml.read_u32(B + 0x3C44910)
  for o = 0, 0x70, 8 do wml.write_u64(p + o, 0) end
  wml.write_f32(p, m); wml.write_u32(p + 0x10, none); wml.write_u32(p + 0x14, none); wml.write_u32(p + 0x18, none)
  wml.write_u64(p + 0x20, p + 0x38); wml.write_u32(p + 0x2C, 8)
  local ok = wml.call(B + 0x6EA430, stats, i, p, 0, on and 1 or 0) & 0xFF
  if ok == 1 then wml.call(B + 0x6EA6B0, e, i) end
  return ok == 1
end
P.flow_gain, P.flow_bars, P.rampage, P.flow_no_decay = false, false, false, false
local PERKS = { flow_gain = "passive_mod_class_adrenaline_multiplier", flow_bars = "passive_mod_class_extra_adrenaline",
  rampage = "passive_mod_class_electrified", flow_no_decay = "passive_mod_class_adrenaline_no_decay" }
local perk_set = {}
function P.update_perks()
  for key, class in pairs(PERKS) do
    local want = P[key] or false
    if want ~= (perk_set[key] or false) then
      if perk_set[key] then perk(class, perk_set[key], false) end
      if want then perk(class, want, true) end
      perk_set[key] = want or nil
    end
  end
end
-- Skills free: inventory_weapon_info m_adrenaline_cost, read each use. Most cost 2.
P.free_skills = false
function P.update_free_skills()
  local V = require("vdata")
  SR5TM_SKILL_COST = SR5TM_SKILL_COST or V.collect("inventory_weapon_info", { { path = "m_adrenaline_cost", what = "cost" } })
  for _, e in ipairs(SR5TM_SKILL_COST) do if e.orig ~= 0 then V.write(e.addr, e.t, P.free_skills and 0 or e.orig) end end
end
-- Pranks, a co-op leftover: +84A7E0(&name hash) finds it, +748DC0(info, 0) puts it on
-- you, +7492A0(info, 0) takes it off. One at a time: the mesh ones swap your outfit.
local prank_on
function P.set_prank(hash)
  local B = wml.base
  local b = wml.buffer(0) + 0xC00
  if prank_on then wml.call(B + 0x7492A0, prank_on, 0); prank_on = nil end
  if not hash then return true end
  wml.write_u32(b, hash)
  local info = wml.call(B + 0x84A7E0, b)
  if info == 0 then return false end
  wml.call(B + 0x748DC0, info, 0)
  prank_on = info
  return true
end
-- Status effects on anyone: status_effect_add_timed_stack_node, a 13-input node. Its
-- component input is 16 bytes: the component's id from its pool, then the object.
local function comp_ref(ctype, entry)
  local b = wml.buffer(13)
  wml.write_u64(b, b + 0x20); wml.write_u64(b + 8, b + 0x28)
  wml.write_u32(b + 0x20, ctype); wml.write_u8(b + 0x28, 0)
  local h = wml.call(wml.base + 0x19E8C40, entry, b) & 0x1FFFFFF
  if h == 0 then return nil end
  local pool = wml.read_u64(wml.base + 0x5CB3F70) + (h & 0xFF) * 0xD0
  return wml.read_u64(wml.read_u64(pool + 0x88) + ((h >> 8) & 0x1FFFF) * 8), wml.read_u32(entry + 0x58)
end
function P.effect_on(entry, name, secs)
  local B = wml.base
  local cid, oid = comp_ref(0x7B, entry)
  if not cid then return false end
  local me, none = wml.read_u32(P.object() + 0x58), wml.read_u32(B + 0x3C44910)
  local buf = wml.buffer(0)
  for i = 0, 0x100, 8 do wml.write_u64(buf + i, 0) end
  wml.write_u64(buf, B + 0x29C71E8)
  local vals = { { c = cid, o = oid }, { u = crc_of(name) }, { f = 1.0 }, { u = 0 }, { u = none }, { f = secs }, { u = me }, { u = me }, { u = 0 }, { f = 0.0 }, { u = none }, { u = none }, { u = 0 } }
  for i, v in ipairs(vals) do
    local slot = buf + 0x400 + (i - 1) * 0x20
    wml.write_u64(buf + 0x18 + (i - 1) * 8, slot); wml.write_u64(slot, 0); wml.write_u64(slot + 8, 0)
    if v.c then wml.write_u64(slot, v.c); wml.write_u32(slot + 8, v.o)
    elseif v.f then wml.write_f32(slot, v.f) else wml.write_u32(slot, v.u) end
  end
  wml.call(B + 0x76A6E0, buf)
  return true
end
-- Notoriety's on and off nodes (no input: every faction).
P.no_call_ins, P.no_roadblocks, P.no_escape = false, false, false
local NOTORIETY = { no_call_ins = { 0x705F00, 0x2991A30, 0x705F70, 0x29C9540 }, no_roadblocks = { 0x706130, 0x29958A0, 0x706160, 0x2993878 }, no_escape = { 0x7062F0, 0x29D1F08, 0x706310, 0x29CEB50 } }
local notoriety_set = {}
function P.update_notoriety_nodes()
  for key, n in pairs(NOTORIETY) do
    local want = P[key] and true or false
    if want ~= (notoriety_set[key] or false) then
      if want then P.node(n[1], n[2], {}) else P.node(n[3], n[4], {}) end
      notoriety_set[key] = want
    end
  end
end
-- Free ventures: real_estate free mode, byte +5BE58D0.
P.free_ventures = false
local ventures_set = false
function P.update_ventures()
  if P.free_ventures ~= ventures_set then
    if P.free_ventures then P.node(0x66D1C0, 0x29CB248, {}) else P.node(0x66D1F0, 0x29C8FE0, {}) end
    ventures_set = P.free_ventures
  end
end
-- vehicle_system_config, *(+5BE6CE0), read live by the game: takedowns, rams, ability power.
P.car_takedowns, P.car_ram, P.car_jump_power, P.car_ability_cd = false, false, false, false
local CAR_CFG = {
  car_takedowns = { { 0x54, "set", 5 }, { 0x74, "set", 5 }, { 0xAC, "set", 5 }, { 0xC8, "set", 5 } },
  car_ram = { { 0x120, "mul" }, { 0x138, "mul" } },
  car_jump_power = { { 0x330, "mul" }, { 0x334, "mul" } },
  car_ability_cd = { { 0x274, "zero" }, { 0x348, "zero" }, { 0x368, "zero" } },
}
SR5TM_CAR_CFG = SR5TM_CAR_CFG or {}
function P.update_car_cfg()
  local c = wml.read_u64(wml.base + 0x5BE6CE0)
  if c == 0 then return end
  for key, fields in pairs(CAR_CFG) do
    local want = P[key]
    for _, f in ipairs(fields) do
      local off, how = f[1], f[2]
      if how == "zero" then
        SR5TM_CAR_CFG[off] = SR5TM_CAR_CFG[off] or wml.read_u32(c + off)
        wml.write_u32(c + off, want and 0 or SR5TM_CAR_CFG[off])
      else
        SR5TM_CAR_CFG[off] = SR5TM_CAR_CFG[off] or wml.read_f32(c + off)
        local o = SR5TM_CAR_CFG[off]
        wml.write_f32(c + off, not want and o or how == "set" and f[3] or o * want)
      end
    end
  end
end
function P.car_equip_ability(hash)
  local v = P.vehicle_object()
  if not v then return false end
  P.node(0xBB9350, 0x29E7AE8, { { u = wml.read_u32(v + 0x58) }, { u = hash } })
  return true
end
function P.car_tow_hook()
  local v = P.vehicle_object()
  if not v then return false end
  P.node(0xBB3740, 0x29EA560, { { u = wml.read_u32(v + 0x58) } })
  return true
end

-- Mission characters (a minimum health) and the dead are left alone.
local function each_near(radius, fn)
  local n = 0
  for _, p in ipairs(P.people_near(radius)) do
    if wml.read_f32(p.health + MIN) == 0 and wml.read_u8(p.health + 0x104) == 0 then
      fn(p)
      n = n + 1
    end
  end
  return n
end
function P.kill_near(radius)
  return each_near(radius, function(p) P.damage(p.entry, 1000000) end)
end

-- Any script node can be run without its graph: a stand-in node with its vtable,
-- each input at +0x18 on a pointer to its value, and the outs left zero (+19413F0
-- does nothing with an empty one). Exec is the vtable's third slot. Inputs: { u = }
-- a u32 (object id, hash), { f = } a float, { v = { x, y, z } } a vector.
function P.node(exec, vtable, inputs)
  local buf = wml.buffer(0)
  for i = 0, 0x100, 8 do wml.write_u64(buf + i, 0) end
  wml.write_u64(buf, wml.base + vtable)
  for i, v in ipairs(inputs) do
    local slot = buf + 0x400 + (i - 1) * 0x20
    wml.write_u64(buf + 0x18 + (i - 1) * 8, slot)
    wml.write_u64(slot, 0)
    wml.write_u64(slot + 8, 0)
    if v.v then for j = 1, 3 do wml.write_f32(slot + (j - 1) * 4, v.v[j]) end
    elseif v.f then wml.write_f32(slot, v.f) else wml.write_u32(slot, v.u) end
  end
  return wml.call(wml.base + exec, buf)
end
local function faction(name)
  local _, v = wml.game("return string_crc(" .. string.format("%q", name) .. ")")
  return math.floor(v) & 0xFFFFFFFF
end
local function id_of(p) return wml.read_u32(p.entry + 0x58) end
-- flammable_ignite_node (target, cause), ai_stun_node (ai, reason), and two that
-- change sides. ai_make_temporarily_hostile_to_faction_node (ai, faction, seconds)
-- changed how a wandering spawned person moved (running, then losing health).
-- ai_set_faction_node (ai, faction). Some spawned people come out inert, with or
-- without these: they never move and don't catch fire. Cause not known yet.
function P.fire_near(radius)
  local me = id_of({ entry = P.object() })
  return each_near(radius, function(p) P.node(0x6AC130, 0x2994870, { { u = id_of(p) }, { u = me } }) end)
end
function P.stun_near(radius)
  return each_near(radius, function(p) P.node(0xAE02E0, 0x29DB1B8, { { u = id_of(p) }, { u = 0 } }) end)
end
function P.make_hostile(id)
  P.node(0xADF210, 0x29D9488, { { u = id }, { u = faction("saints") }, { f = 3600 } })
end
function P.hostile_near(radius)
  return each_near(radius, function(p) P.make_hostile(id_of(p)) end)
end
-- Dance: the action the game's emotes request, +1532830(gail (+1534D80(entry)),
-- &"human_emote", "looping taunt", tag, &id, &"emote_priority", a name). Their AI walks
-- them off otherwise, so they're held with ai_add_immobilize_node (ai, reason).
-- (Listing a spawned person as a follower, +2CE810, changed nothing: they go on with
-- the ambient behaviour every spawn gets, whatever the spawn context says.)
local DANCES = { "emote loop floppy dance", "emote loop pump dance", "skanking emote" }
local function cstr(a, s)
  for i = 1, #s do wml.write_u8(a + i - 1, s:byte(i)) end
  wml.write_u8(a + #s, 0)
end
function P.dance_near(radius)
  local B = wml.base
  local b = wml.buffer(0) + 0x800
  wml.write_u32(b, faction("human_emote"))
  wml.write_u32(b + 4, faction("emote_priority"))
  cstr(b + 0x10, "looping taunt")
  cstr(b + 0x90, "sr5_tweak_menu")
  return each_near(radius, function(p)
    local gail = wml.call(B + 0x1534D80, p.entry)
    if gail ~= 0 then
      P.node(0xAE04C0, 0x2A02F18, { { u = id_of(p) }, { u = 0 } })
      cstr(b + 0x30, DANCES[math.random(#DANCES)])
      wml.write_u32(b + 8, id_of(p))
      wml.call(B + 0x1532830, gail, b, b + 0x10, b + 0x30, b + 8, b + 4, b + 0x90)
    end
  end)
end
-- Disarm, kept up: everyone near every two seconds, as new people come along.
P.no_guns = false
function P.update_no_guns() P.near_arms(false, 60) end
function P.float_near(radius) return each_near(radius, function(p) P.effect_on(p.entry, "lofted", 8) end) end
function P.dissolve_near(radius) return each_near(radius, function(p) P.effect_on(p.entry, "disintegrate", 8) end) end
function P.toxic_near(radius) return each_near(radius, function(p) P.effect_on(p.entry, "toxic_waste", 8) end) end
function P.call_saints(n)
  local e = P.object()
  if not e then return false end
  P.node(0x68CBD0, 0x2997078, { { u = wml.read_u32(e + 0x58) }, { u = n } })
  return true
end
function P.friendly_near(radius)
  local f = faction("saints friendly")
  return each_near(radius, function(p) P.node(0xADEB50, 0x29E6A58, { { u = id_of(p) }, { u = f } }) end)
end
-- You: one hit only takes you to 1 health ("down but not out"). That's switched
-- off first, as human_health_disable_dbno_on_death_node does it: a reference on
-- your handle, then +3EEFD0(&id, 0), which releases it. Two hits a second apart,
-- and it's switched back on (1) once you've respawned.
local function set_dbno(e, on)
  local B, id = wml.base, wml.read_u32(e + 0x58)
  local buf = wml.buffer(4) + 0x300
  wml.write_u32(buf, id)
  local refs = wml.read_u64(B + 0x2EB2330) + id * 4
  wml.write_u32(refs, wml.read_u32(refs) + 1)
  wml.call(B + 0x3EEFD0, buf, on and 1 or 0)
end
local kill_wait, kill_hits
function P.kill_self()
  local e = P.object()
  if not e or not P.health_component() then return false end
  set_dbno(e, false)
  kill_wait, kill_hits = 20, 2
  return true
end
function P.kill_active() return kill_wait ~= nil end
function P.update_kill_self()
  local e, h = P.object(), P.health_component()
  if not e or not h then return end
  if kill_hits == 0 then
    if wml.read_u8(h + 0x104) == 0 and wml.read_f32(h + CUR) > 0 and kill_wait <= 0 then
      set_dbno(e, true)
      kill_wait, kill_hits = nil, nil
    end
    kill_wait = kill_wait and kill_wait - 1
    return
  end
  kill_wait = kill_wait - 1
  if kill_wait <= 0 then
    P.damage(e, 1000000)
    kill_hits, kill_wait = kill_hits - 1, 60
  end
end
-- Every car near but the one you're in, as Destroy this vehicle does it. Doors
-- and panels have a 0x44 too: only what has wheels (0x12) is a whole vehicle.
function P.destroy_near(radius)
  local mine, n = P.vehicle_object(), 0
  for _, v in ipairs(objects_near(radius, 0x44)) do
    if v.entry ~= mine and P.component(0x12, v.entry) then
      wml.write_u8(v.health + 0x56, wml.read_u8(v.health + 0x56) & ~0x05 & 0xFF)
      wml.callf(wml.base + 0x1BA6F00, v.health, 0.0, wml.base + 0x48E778C, 0xFFFFFFFF, wml.base + 0x3C44910, 0)
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
    -- both fire modes (sections 0 and 1)
    for section = 0, 1 do wml.call(wml.base + 0x1BFF510, comp, buf + 0x10, section, buf + 0x20, name) end
  end
  local a = P.ammo
  set(73301821, a and crc(a[1]) or 0, "e")                -- status_effect
  set(2640671745, 1.0, "f")                               -- status_effect_magnitude
  set(216245579, a and 4.0 or 1.0, "f")                   -- status_effect_duration
  set(1310126570, a and 20.0 or 0.0, "f")                 -- status_effect_damage
  set(1026999258, crc(a and a[2] or "physical"), "e")     -- status_effect_damage_type
  ammo_gun = id
end

-- Rocket ammo on the gun in hand (confirmed in play): its shot type set to
-- "projectile" (enum key shot_type, through +1BFF510), and its prefab
-- properties "shot" (the projectile) and "explosion" set to a launcher's
-- (+1C001E0(component, &key, section, prefab id, name), as the game's
-- weapon_set_prefab_property_node does), both fire modes. A gun is remade
-- when you switch to it, so every new gun gets it; turning it off leaves the
-- gun in hand as it is until the next switch brings a plain copy.
P.rockets = false   -- false or { shot prefab, explosion prefab or nil }
local rocket_gun
local prefab_ids = {}
local function prefab_id(path)
  if not prefab_ids[path] then
    local p = wml.buffer(5, path)
    local srid = wml.call(wml.base + 0xE8E370, p)
    wml.call(wml.base + 0xE8EA40, srid, p, 7)   -- request (load) it
    prefab_ids[path] = srid
  end
  return prefab_ids[path]
end
-- Firing a model that hasn't finished loading shuts the game down with no error
-- (three times live, each within seconds of the first request; firing later
-- was fine). So: request the models, and only touch a gun some time later.
local rocket_wait, rocket_for = 0, nil
function P.rockets_waiting() return rocket_wait > 0 end
function P.update_rockets()
  local r = P.rockets
  if not r then rocket_gun, rocket_for = nil, nil; return end
  if rocket_for ~= r then
    rocket_for, rocket_wait = r, 120   -- called every 5 frames: 10 s
    prefab_id(r[1] .. ".cprefab_pc"); prefab_id(r[2] .. ".cprefab_pc")
  end
  if rocket_wait > 0 then rocket_wait = rocket_wait - 1; return end
  local ok, s = wml.game("return tostring(gml_get_local_player_weapon())")
  local id = ok and tonumber((s or ""):match("object (%x+)") or "", 16)
  if not id or id == 0 or (id == rocket_gun and P.rockets_set == r) then return end
  local buf = wml.buffer(10)
  wml.write_u32(buf, id)
  local entry = wml.call(wml.base + 0x1C1F420, buf)
  local comp = entry ~= 0 and wml.call(wml.base + 0x49F8A0, entry) or 0
  if comp == 0 then return end
  local name = wml.buffer(11, "sr5_tweak_menu")
  for i = 0, 15, 4 do wml.write_u32(buf + 0x20 + i, 0) end
  wml.write_u32(buf + 0x10, 817162218)                    -- shot_type
  wml.write_u32(buf + 0x20, crc("projectile")); wml.write_u32(buf + 0x28, 3)
  for section = 0, 1 do wml.call(wml.base + 0x1BFF510, comp, buf + 0x10, section, buf + 0x20, name) end
  for key, path in pairs({ shot = r[1], explosion = r[2] }) do
    wml.write_u32(buf + 0x10, crc(key))
    local srid = prefab_id(path .. ".cprefab_pc")
    for section = 0, 1 do wml.call(wml.base + 0x1C001E0, comp, buf + 0x10, section, srid, name) end
  end
  rocket_gun, P.rockets_set = id, r
end

-- No recoil on the gun in hand. A gun keeps its own copy of most of its
-- properties, made when it's created (read live: a list at the weapon
-- component's +0x138 pointer, inline at +0x150, count u16 at +0x140, 24-byte
-- entries: key hash +0, value +8, type +0x10), so the shared weapon data
-- (weapons.lua) only reaches guns made later. Its recoil keys are saved,
-- then set to 0 with the per-gun setter (+1BFF510); off puts them back the
-- next time that gun is in your hands. Keys a gun doesn't list come back as
-- the keys' defaults.
local RECOIL = {   -- key hash = default
  [3476011760] = 2, [4628092] = 1, [635825236] = 10, [1210448282] = 5,   -- pitch, heading, max pitch, max heading
  [562308622] = 1, [665612735] = 1, [1177745254] = 1,                    -- hip-fire recoil, camera shake, hip-fire shake
}
P.no_recoil = false
local recoil_orig, recoil_gun = {}, nil   -- [gun id] = { [key] = value }
-- Firing animations also trigger the shakes in gml_animation_camera_shake (five
-- of them, camera_shake_pistol_fire at 3 and _strong among them), whatever the
-- gun's own recoil is: their intensity goes to 0 too. Globals, so a reload of
-- this file doesn't take a 0 for the game's value.
local function update_shakes()
  local want = P.no_recoil and true or false
  if want == (SR5TM_SHAKE_ZERO or false) then return end
  local V = require("vdata")
  SR5TM_SHAKES = SR5TM_SHAKES or V.collect("gml_animation_camera_shake", { { path = "m_shake_intensity", what = "shake" } })
  for _, e in ipairs(SR5TM_SHAKES) do V.write(e.addr, e.t, want and 0 or e.orig) end
  SR5TM_SHAKE_ZERO = want
end
function P.update_recoil(force)
  update_shakes()
  local ok, s = wml.game("return tostring(gml_get_local_player_weapon())")
  local id = ok and tonumber((s or ""):match("object (%x+)") or "", 16)
  if not id or id == 0 or (id == recoil_gun and not force) then return end
  local buf = wml.buffer(10)
  wml.write_u32(buf, id)
  local entry = wml.call(wml.base + 0x1C1F420, buf)
  local comp = entry ~= 0 and wml.call(wml.base + 0x49F8A0, entry) or 0
  if comp == 0 then return end
  local name = wml.buffer(11, "sr5_tweak_menu")
  local function set(key, value)
    wml.write_u32(buf + 0x10, key)
    for i = 0, 15, 4 do wml.write_u32(buf + 0x20 + i, 0) end
    wml.write_f32(buf + 0x20, value); wml.write_u32(buf + 0x28, 1)
    for section = 0, 1 do wml.call(wml.base + 0x1BFF510, comp, buf + 0x10, section, buf + 0x20, name) end
  end
  if P.no_recoil and not recoil_orig[id] then
    local o = {}
    for k, d in pairs(RECOIL) do o[k] = d end
    local list, n = wml.read_u64(comp + 0x138), wml.read_u16(comp + 0x140)
    if list ~= 0 and n <= 200 then
      for i = 0, n - 1 do
        local e = list + i * 24
        local k = wml.read_u32(e)
        if RECOIL[k] and wml.read_u32(e + 0x10) == 1 then o[k] = wml.read_f32(e + 8) end
      end
    end
    recoil_orig[id] = o
    for k in pairs(RECOIL) do set(k, 0) end
  elseif not P.no_recoil and recoil_orig[id] then
    for k, v in pairs(recoil_orig[id]) do set(k, v) end
    recoil_orig[id] = nil
  end
  recoil_gun = id
end
function P.recoil_active() return P.no_recoil or next(recoil_orig) ~= nil or SR5TM_SHAKE_ZERO end

-- No reload: the gun in hand's magazine kept full. The game's inventory
-- (+4BB340(player)): +98F500(inventory, &magazine, &reserve, &magazine size,
-- slot) reads a slot, +98F870(inventory, slot, magazine, reserve, 0, &none
-- id, 0) sets it (what the Infinite Ammo cheat's refill +662FF0 does for the
-- reserve). The slot in hand: player_local_inventory_get_active_slot().
function P.keep_magazine()
  local p = P.object()
  if not p then return end
  local ok, slot = wml.game("return player_local_inventory_get_active_slot()")
  if not ok or type(slot) ~= "number" or slot < 0 or slot > 12 then return end
  local inv = wml.call(wml.base + 0x4BB340, p)
  if inv == 0 then return end
  local buf = wml.buffer(14)
  for i = 0, 31, 4 do wml.write_u32(buf + i, 0) end
  if (wml.call(wml.base + 0x98F500, inv, buf, buf + 4, buf + 8, slot, 0, 0, 0) & 0xFF) == 0 then return end
  local mag, reserve, size = wml.read_u32(buf), wml.read_u32(buf + 4), wml.read_u32(buf + 8)
  if size > 0 and size < 100000 and mag < size then
    wml.write_u32(buf + 16, wml.read_u32(wml.base + 0x3C44910))
    wml.call(wml.base + 0x98F870, inv, slot, size, reserve, 0, buf + 16, 0)
  end
end

-- Moddable stats ("passive_mod_class_*"): without a perk that owns one, a
-- stat is its class default, a float at +3C0DC10 + index * 0x10 + 8 (a table
-- of 0x10-byte entries, the class's name crc at +0, count u32 at +5BE5DA0).
-- Read live: sprint speed (index 2) default 1.0, a multiplier; extra homies
-- (index 141) default 0, the homie limit being 1 + it. With a perk owned,
-- the perk decides. The game's own defaults are kept in a global, so a
-- reload of this file never takes a changed value for the game's.
SR5TM_STAT_DEFAULTS = SR5TM_STAT_DEFAULTS or {}
local STATS = { sprint = 0x0E6AC014, homies = 0xF448041B }
local function stat_addr(crc)
  local n = wml.read_u32(wml.base + 0x5BE5DA0)
  for i = 0, math.min(n, 1000) - 1 do
    local e = wml.base + 0x3C0DC10 + i * 0x10
    if wml.read_u32(e) == crc then return e + 8 end
  end
  return nil
end
-- want: a value, or nil for the game's own
local function set_stat(crc, want)
  local a = stat_addr(crc)
  if not a then return end
  local d = SR5TM_STAT_DEFAULTS[crc]
  if not d then d = wml.read_f32(a); SR5TM_STAT_DEFAULTS[crc] = d end
  local v = want or d
  if wml.read_f32(a) ~= v then wml.write_f32(a, v) end
end

-- Homie limit: 1 + extra homies.
P.homies = 1
function P.update_homies()
  set_stat(STATS.homies, P.homies ~= 1 and (P.homies - 1) or nil)
  P.homies_written = P.homies ~= 1
end
function P.homies_active() return P.homies ~= 1 or P.homies_written end

-- Run speed: on foot you move by the animation's root motion. The locomotion
-- component (type 0x10): +0x270 last frame's root motion velocity (x, y, z,
-- m/s), +0x3A0 extra velocity for this frame, added to it and cleared after
-- physics. So every frame the extra is (N - 1) x the horizontal root motion:
-- same direction, N times the speed. Only while +0x340, the desired speed, is
-- above 0: stopping animations keep some root motion, and boosting those left
-- you sliding after letting go. (The animation speed parameters, Lateral and
-- Horizontal Move Speed Scalar, changed punch lunges but not running.)
local run_comp, run_frames = nil, 0
function P.update_run()
  local x = P.move.run
  if x == 1 then return end
  run_frames = run_frames - 1
  if run_frames <= 0 or not run_comp then run_comp = P.component(0x10); run_frames = 60 end
  local c = run_comp
  if not c then return end
  if wml.read_f32(c + 0x340) <= 0.01 then return end
  wml.write_f32(c + 0x3A0, wml.read_f32(c + 0x270) * (x - 1))
  wml.write_f32(c + 0x3A8, wml.read_f32(c + 0x278) * (x - 1))
end

-- Jump height: a jump lifts you about 1.35 m, +0x274 (vertical velocity) rising
-- to 6.5 m/s; +0x4B1 is set while you're off the ground. That velocity includes
-- the extra, so scaling it runs away (x10 went past 500 m): the extra is fixed,
-- and lasts a quarter of a second from the jump button and leaving the ground.
local jump_comp, jump_frames, jump_left, jump_armed, jump_was_up = nil, 0, 0, 0, false
function P.update_jump()
  local x = P.move.jump
  if x == 1 then return end
  jump_frames = jump_frames - 1
  if jump_frames <= 0 or not jump_comp then jump_comp = P.component(0x10); jump_frames = 60 end
  local c = jump_comp
  if not c then return end
  if wml.key_down("SPACE") or (wml.pad() or 0) & 0x1000 ~= 0 then jump_armed = 30
  elseif jump_armed > 0 then jump_armed = jump_armed - 1 end
  local up = wml.read_f32(c + 0x274) > 0.5
  if jump_left > 0 then
    jump_left = jump_left - 1
    wml.write_f32(c + 0x3A4, 5 * (x - 1))
  elseif up and not jump_was_up and jump_armed > 0 then
    jump_left, jump_armed = 15, 0
  end
  jump_was_up = up
end

-- The car you're in, kept up every half second: No collision damage (0x44 +0x54 = 0,
-- the handler +1BAB550 returns at once), Heavy (+5A4C40(entry, 0, 0x0A), what the
-- Infinite Mass cheat sends; the car's own category is byte 0x12 +0x2310), its gravity
-- (physics_set_gravity_factor_node). Each put back when turned off or when you change car.
P.car_no_crash, P.car_heavy, P.car_gravity = false, false, 1
local car_state = {}
function P.car_active() return P.car_no_crash or P.car_heavy or P.car_gravity ~= 1 or next(car_state) ~= nil end
function P.update_car_extras()
  local v = P.vehicle_object()
  local h, w = v and P.component(0x44, v), v and P.component(0x12, v)
  if not h then car_state = {}; return end
  if car_state.car ~= v then car_state = { car = v } end
  local st = car_state
  if P.car_no_crash then
    if not st.crash then st.crash = wml.read_u8(h + 0x54) end
    wml.write_u8(h + 0x54, 0)
  elseif st.crash then wml.write_u8(h + 0x54, st.crash); st.crash = nil end
  if w and (P.car_heavy and true or false) ~= (st.heavy or false) then
    wml.call(wml.base + 0x5A4C40, v, 0, P.car_heavy and 0x0A or wml.read_u8(w + 0x2310))
    st.heavy = P.car_heavy and true or false
  end
  if P.car_gravity ~= (st.gravity or 1) then
    P.node(0x1931450, 0x2AC0B08, { { u = wml.read_u32(v + 0x58) }, { f = P.car_gravity } })
    st.gravity = P.car_gravity
  end
end
-- One-press: a boost (vehicle_force_boost_node: plain cars may refuse), a jump
-- (physics_add_velocity_node), the next paint (the game's Lua, 0-based).
function P.car_boost()
  local v = P.vehicle_object()
  if not v then return false end
  P.node(0xBB4CF0, 0x29EB138, { { u = wml.read_u32(v + 0x58) }, { u = 3000 } })
  return true
end
function P.car_jump()
  local v = P.vehicle_object()
  if not v then return false end
  P.node(0x192F280, 0x2ABBA60, { { u = wml.read_u32(v + 0x58) }, { v = { 0, 12, 0 } }, { u = wml.read_u32(wml.base + 0x3C44910) } })
  return true
end
function P.car_next_paint()
  local ok, a, b = wml.game([[local c = vehicle_get_current():get_component_by_type("gml_component_vehicle_customization")
    local n, cur = #vehicle_get_paint_choices(c), vehicle_get_paint_choice(c)
    if n == 0 then return 0, 0 end
    local nxt = (cur + 1) % n
    vehicle_set_paint_choice(c, nxt)
    return nxt + 1, n]])
  return ok and a or nil, b
end
-- Spawned cars: the drop-car cheat's callback leaves the new car's id in +3C2261C.
P.spawned_cars = {}
local car_watch
function P.watch_spawned_car() car_watch = { was = wml.read_u32(wml.base + 0x3C2261C), frames = 600 } end
function P.update_car_watch()
  if not car_watch then return end
  local id = wml.read_u32(wml.base + 0x3C2261C)
  car_watch.frames = car_watch.frames - 1
  if id ~= car_watch.was and id ~= 0 then P.spawned_cars[#P.spawned_cars + 1] = id; car_watch = nil
  elseif car_watch.frames <= 0 then car_watch = nil end
end
function P.remove_spawned_cars()
  local mine, n = P.vehicle_object(), 0
  local left = {}
  for _, id in ipairs(P.spawned_cars) do
    local e = P.entry_of(id)
    if e and e == mine then left[#left + 1] = id
    elseif e and wml.read_u32(e + 0x58) == id then wml.call(wml.base + 0x1E6920, e + 0x58); n = n + 1 end
  end
  P.spawned_cars = left
  return n
end
-- What's drawn: a global render mask, +3389098: 0x8000 sky, 0x4000 particles,
-- 0x1000 shadows, 0x20000 tree billboards. One at a time here; the rest stay on.
P.render_hide = false
local render_bit
function P.update_render()
  local a = wml.base + 0x3389098
  local m = wml.read_u32(a)
  if render_bit then m = m | render_bit end
  render_bit = P.render_hide or nil
  if render_bit then m = m & ~render_bit & 0xFFFFFFFF end
  wml.write_u32(a, m)
end

-- Camera distance: the camera's follow distance, +0x7FC of component 0x1D (from
-- +1FCD10(+1B434C0(player + 0x58))), written every frame while it's changed. 0 is
-- from inside your head: aiming stays third-person. Original kept in a global.
P.cam_distance = false
function P.update_cam_distance()
  local e = P.object()
  if not e then return end
  local cam = wml.call(wml.base + 0x1FCD10, wml.call(wml.base + 0x1B434C0, e + 0x58))
  if cam == 0 then return end
  SR5TM_CAM_DIST = SR5TM_CAM_DIST or wml.read_f32(cam + 0x7FC)
  wml.write_f32(cam + 0x7FC, P.cam_distance or SR5TM_CAM_DIST)
end

-- Auto-teleport: a new player waypoint (slot 0) takes you there at once.
P.auto_waypoint = false
local waypoint_last
function P.update_auto_waypoint()
  local x, y, z, slot = P.waypoint()
  if not x or slot ~= 0 then waypoint_last = nil; return end
  if waypoint_last and math.abs(waypoint_last[1] - x) + math.abs(waypoint_last[2] - z) < 1 then return end
  waypoint_last = { x, z }
  P.teleport(x, y + 1, z)
end

-- Places on the map: the HUD's own icon list, Hud_oi_icons. Each has the object it's
-- on (obj_handle), its kind (oi_type) and what it is (gameplay_info: a store_info name
-- hash for stores). Only what the map has published so far.
function P.map_places(stores)
  local ok, s = wml.game([[collectgarbage("collect") local s = ""
    for _, i in pairs(Hud_oi_icons) do
      if i.obj_handle and i.gameplay_info and i.is_player ~= true then
        local st = vlib_info_object:get_object("store_info", i.gameplay_info):exists()
        if ]] .. (stores and "st" or "not st") .. [[ then
          s = s .. i.obj_handle .. "\t" .. tostring(st and vlib_info_object:get_object("store_info", i.gameplay_info) or i.oi_type) .. "\n"
        end
      end
    end
    return s]])
  local out = {}
  if ok then
    for id, name in tostring(s):gmatch("(%d+)\t([^\n]*)\n") do
      out[#out + 1] = { name:match('"(.*)"') or name, tonumber(id) }
    end
    table.sort(out, function(a, b) return a[1] < b[1] end)
  end
  return out
end
function P.go_to_object(id)
  local e = P.entry_of(id)
  if not e then return false end
  return P.teleport(s32(wml.read_u32(e + 0x30)) / 10000, s32(wml.read_u32(e + 0x34)) / 10000 + 1, s32(wml.read_u32(e + 0x38)) / 10000)
end

-- The car camera: +2EAED68 is how long it waits before swinging back, in seconds.
P.cam_delay = false
function P.update_cam_delay()
  local a = wml.base + 0x2EAED68
  SR5TM_CAM_DELAY = SR5TM_CAM_DELAY or wml.read_f32(a)
  wml.write_f32(a, P.cam_delay or SR5TM_CAM_DELAY)
end

-- Fire rate past the game's limit: the gun caches its refire delay in ms at +0x7B8,
-- which the property lists don't reach, and bit 0x20 of +0x7C4 skips the gate on the
-- firing animation (the game clears it on letting go). Every frame while it's above x1.
-- Originals by gun component. Money gun: +0x1CE8 counts shots.
SR5TM_REFIRE = SR5TM_REFIRE or {}
P.money_gun = false
local gun_comp, gun_wait, gun_shots = nil, 0, nil
local refire_frames, refire_shots = 0, nil
local function held_gun()
  gun_wait = gun_wait - 1
  if gun_wait <= 0 then
    gun_wait = 15
    local ok, s = wml.game("return tostring(gml_get_local_player_weapon())")
    local id = ok and tonumber((s or ""):match("object (%x+)") or "", 16)
    gun_comp = nil
    if id and id ~= 0 then
      local buf = wml.buffer(10) + 0x200
      wml.write_u32(buf, id)
      local e = wml.call(wml.base + 0x1C1F420, buf)
      local c = e ~= 0 and wml.call(wml.base + 0x49F8A0, e) or 0
      if c ~= 0 then gun_comp = c end
    end
  end
  return gun_comp
end
function P.update_refire(x)
  if type(x) ~= "number" then x = 1 end
  if x == 1 and next(SR5TM_REFIRE) == nil then return end
  local c = held_gun()
  if not c then return end
  if x ~= 1 then
    local o = SR5TM_REFIRE[c] or wml.read_u32(c + 0x7B8)
    SR5TM_REFIRE[c] = o
    -- -1 means the gun hasn't cached one (seen live): dividing it gave a delay of days.
    -- No faster than 20 shots a second: the first floor, 16 ms, took the game down.
    if o < 0x7FFFFFFF then wml.write_u32(c + 0x7B8, math.max(50, math.floor(o / x))) end
    if P.refire_gate ~= false then wml.write_u8(c + 0x7C4, wml.read_u8(c + 0x7C4) | 0x20) end
    -- a line a second while firing: the real rate, and the last thing before a crash
    refire_frames = refire_frames + 1
    if refire_frames >= 60 then
      local n = wml.read_u32(c + 0x1CE8)
      if refire_shots and n > refire_shots then wml.log(string.format("firing: %d shots in 1 s, delay %d ms (game's %d)", n - refire_shots, wml.read_u32(c + 0x7B8), o)) end
      refire_shots, refire_frames = n, 0
    end
  elseif SR5TM_REFIRE[c] then
    wml.write_u32(c + 0x7B8, SR5TM_REFIRE[c])
    SR5TM_REFIRE[c] = nil
  end
end
function P.update_money_gun()
  local c = held_gun()
  if not c then gun_shots = nil; return end
  local n = wml.read_u32(c + 0x1CE8)
  if gun_shots and n > gun_shots then P.drop_cash(50 * (n - gun_shots), 0, 1, 12) end
  gun_shots = n
end

-- People the menu spawned (their object ids), and removing them: +1E6920(&id)
-- destroys an object (the game's "gameplay util destroy"). An entry's own id
-- is at +0x58; ids are reused, so an id is only removed while its entry still
-- carries it.
P.spawned = {}
local spawn_pending = {}
-- Spawned people: left wandering, or (a moment after they appear) set on you.
P.spawn_hostile = false
local hostile_wait = {}
function P.hostile_pending() return #hostile_wait > 0 end
function P.update_hostile()
  local left = {}
  for _, h in ipairs(hostile_wait) do
    h.ticks = h.ticks - 1
    if h.ticks > 0 then left[#left + 1] = h
    elseif P.entry_of(h.id) then P.make_hostile(h.id) end
  end
  hostile_wait = left
end
function P.remember(obj) if obj then spawn_pending[#spawn_pending + 1] = obj end end
-- The spawner returns a spawn record: the person's id is at +0x70 (read live),
-- filled in once they exist.
local function spawn_settle()
  local left = {}
  for _, o in ipairs(spawn_pending) do
    local id = wml.read_u32(o + 0x70)
    if id ~= 0 and P.entry_of(id) then
      P.spawned[#P.spawned + 1] = id
      if P.spawn_hostile then hostile_wait[#hostile_wait + 1] = { id = id, ticks = 3 } end
    else left[#left + 1] = o end
  end
  spawn_pending = left
end
function P.spawned_pending() return #spawn_pending > 0 end
P.spawn_settle = spawn_settle
-- Playing as someone else: the local player record *(+5BDF320), +0x10 current object.
-- +1B44BC0(record, &id, 1) sets who's next, +1B44800(record) commits: the path the world
-- start uses. The game then reports them as the local player. You go back the same way,
-- and at once if that body disappears.
local my_id
local function become(id)
  local rec = wml.read_u64(wml.base + 0x5BDF320)
  local b = wml.buffer(13)
  wml.write_u32(b, id)
  wml.call(wml.base + 0x1B44BC0, rec, b, 1)
  wml.call(wml.base + 0x1B44800, rec)
end
function P.play_as_spawned()
  local e = P.object()
  if not e then return false end
  spawn_settle()
  for i = #P.spawned, 1, -1 do
    local id = P.spawned[i]
    local t = P.entry_of(id)
    local h = t and t ~= e and P.component(0x8D, t)
    if h and wml.read_u8(h + 0x104) == 0 then
      my_id = my_id or wml.read_u32(e + 0x58)
      become(id)
      return true
    end
  end
  return false
end
function P.playing_as() return my_id ~= nil end
function P.back_to_self()
  if not my_id or not P.entry_of(my_id) then my_id = nil; return false end
  become(my_id)
  my_id = nil
  return true
end
function P.check_body()
  local rec = wml.read_u64(wml.base + 0x5BDF320)
  local cur = wml.read_u32(rec + 0x10)
  if not P.entry_of(cur) or wml.read_u32(P.entry_of(cur) + 0x58) ~= cur then P.back_to_self() end
end
function P.remove_spawned()
  P.back_to_self()
  spawn_settle()
  spawn_pending = {}
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
  -- it gives back their spawn record (see P.remember)
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

-- Movement (experimental): component 0x10, in the reflection's order but 0x10 lower:
-- +0x35C in-air gain, +0x364 swimming gain. (These rows first wrote 0x1F, which is
-- the camera target, not you.) Originals are kept in a global: a reload of this file
-- must not take changed values for the game's (it did, and they compounded).
P.move = { run = 1, jump = 1, air = 1, swim = 1, gravity = 1 }
local MOVE = { air = 0x35C, swim = 0x364 }
SR5TM_MOVE_ORIG = SR5TM_MOVE_ORIG or {}
function P.update_move()
  local c = P.component(0x10)
  if not c then return end
  local o = SR5TM_MOVE_ORIG[c]
  if not o then
    o = {}
    for _, off in pairs(MOVE) do o[off] = wml.read_f32(c + off) end
    SR5TM_MOVE_ORIG = { [c] = o }   -- (one player: forget older components)
  end
  for key, off in pairs(MOVE) do
    local want = o[off] * P.move[key]
    if wml.read_f32(c + off) ~= want then wml.write_f32(c + off, want) end
  end
end
function P.move_on()
  local m = P.move
  return m.air ~= 1 or m.swim ~= 1
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
