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
-- damage_type name), +18 source type (a gun's own, 09C58CBC), +24 amount, +28
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
-- Mission characters (a minimum health) and the dead are left alone.
function P.kill_near(radius)
  local n = 0
  for _, p in ipairs(P.people_near(radius)) do
    if wml.read_f32(p.health + MIN) == 0 and wml.read_u8(p.health + 0x104) == 0 then
      P.damage(p.entry, 1000000)
      n = n + 1
    end
  end
  return n
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
function P.update_recoil(force)
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
function P.recoil_active() return P.no_recoil or next(recoil_orig) ~= nil end

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

-- People the menu spawned (their object ids), and removing them: +1E6920(&id)
-- destroys an object (the game's "gameplay util destroy"). An entry's own id
-- is at +0x58; ids are reused, so an id is only removed while its entry still
-- carries it.
P.spawned = {}
local spawn_pending = {}
function P.remember(obj) if obj then spawn_pending[#spawn_pending + 1] = obj end end
-- The spawner returns a spawn record: the person's id is at +0x70 (read live),
-- filled in once they exist.
local function spawn_settle()
  local left = {}
  for _, o in ipairs(spawn_pending) do
    local id = wml.read_u32(o + 0x70)
    if id ~= 0 and P.entry_of(id) then P.spawned[#P.spawned + 1] = id else left[#left + 1] = o end
  end
  spawn_pending = left
end
function P.spawned_pending() return #spawn_pending > 0 end
P.spawn_settle = spawn_settle
function P.remove_spawned()
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

-- Movement (experimental): the character locomotion component (type 0x1F).
-- From +D0, in the reflection's order: gravity multiplier, walk, run, on-foot
-- gain, in-air gain, in-air acceleration, swim gain, swim acceleration.
P.move = { run = 1, jump = 1, air = 1, swim = 1, gravity = 1 }
-- (Run speed is the sprint speed stat, above: +D4 / +D8 changed nothing in
-- play.) Originals are kept in a global: a reload of this file must not take
-- changed values for the game's (it did, and they compounded).
local MOVE = { air = { 0xE0, 0xE4 }, swim = { 0xE8, 0xEC } }
SR5TM_MOVE_ORIG = SR5TM_MOVE_ORIG or {}
function P.update_move()
  local c = P.component(0x1F)
  if not c then return end
  local o = SR5TM_MOVE_ORIG[c]
  if not o then
    o = {}
    for _, offs in pairs(MOVE) do for _, off in ipairs(offs) do o[off] = wml.read_f32(c + off) end end
    SR5TM_MOVE_ORIG = { [c] = o }   -- (one player: forget older components)
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
