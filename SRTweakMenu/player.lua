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
SR5TM_VGOD = SR5TM_VGOD or {}
local vgod_orig = SR5TM_VGOD   -- [health component] = original flags
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
-- requested velocity as it is (+0x4B2 = 1), and the extra velocity moved along
-- where the camera looks (the render camera's rows, +41E1AC0, laid out as an
-- object's: the body turns to face its way, so its own rows would go sideways).
-- W A S D or the left stick, Space or the right trigger up, Ctrl or the left trigger
-- down (the triggers by how far they're pulled), Shift held or the left stick clicked
-- fast. The triggers and the click don't reach the game meanwhile.
local clip_on, clip_fast, clip_click
local CLIP_PAD_FAST = 0x40
local CAM_ROWS = 0x41E1AC0
local function stick(v)
  local dead = 7849
  if not v or math.abs(v) < dead then return 0 end
  return (v > 0 and 1 or -1) * (math.abs(v) - dead) / (32767 - dead)
end
local function trigger(v)
  if not v or v <= 30 then return 0 end
  return (v - 30) / 225
end
function P.update_clip(menu_open)
  local e = P.object()
  local c = e and P.component(0x10)
  if not c then return end
  if P.no_clip ~= (clip_on or false) then
    local buf = wml.buffer(4)
    wml.write_u8(buf, P.no_clip and 0 or 1)
    wml.call(wml.base + 0x486CE0, e, 0, 0x10, 0, buf)
    wml.write_u8(c + 0x4B2, P.no_clip and 1 or 0)
    clip_on = P.no_clip
    clip_fast, clip_click = false, false
    P.update_gravity()
  end
  if wml.pad_mask then wml.pad_mask(P.no_clip and CLIP_PAD_FAST or 0, P.no_clip) end
  if not P.no_clip then return end
  wml.write_f32(c + 0x2A8, 0)
  local rows = wml.base + CAM_ROWS
  local fx, fy, fz, rx, rz = wml.read_f32(rows + 0x20), wml.read_f32(rows + 0x24), wml.read_f32(rows + 0x28), wml.read_f32(rows), wml.read_f32(rows + 8)
  local buttons, lt, rt, lx, ly = wml.pad()
  if menu_open or not buttons then buttons = 0 end
  local click = buttons & CLIP_PAD_FAST ~= 0
  if click and not clip_click then clip_fast = not clip_fast end
  clip_click = click
  local speed = (wml.key_down("SHIFT") or clip_fast) and 40 or 12
  local f = math.max(-1, math.min(1, (wml.key_down("W") and 1 or 0) - (wml.key_down("S") and 1 or 0) + stick(ly)))
  local r = math.max(-1, math.min(1, (wml.key_down("D") and 1 or 0) - (wml.key_down("A") and 1 or 0) + stick(lx)))
  local u = math.max(-1, math.min(1, (wml.key_down("SPACE") and 1 or 0) - (wml.key_down("CTRL") and 1 or 0) + trigger(rt) - trigger(lt)))
  wml.write_f32(c + 0x3A0, (fx * f + rx * r) * speed)
  wml.write_f32(c + 0x3A4, (fy * f + u) * speed)
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
function P.update_sides()
  if P.side_gang ~= SR5TM_SIDE_WAS then
    for _, g in ipairs(GANGS) do
      if SR5TM_SIDE_WAS == g or SR5TM_SIDE_WAS == "all" then set_side(g, "saints") end
      if P.side_gang == g or P.side_gang == "all" then set_side(g, "saints", 5) end
    end
    SR5TM_SIDE_WAS = P.side_gang
  end
  if P.saints_enemies ~= SR5TM_ENEMIES_WAS then
    for _, f in ipairs({ "saints friendly", "saints_hq", "saints_hostile" }) do set_side(f, "saints", P.saints_enemies and 1 or nil) end
    SR5TM_ENEMIES_WAS = P.saints_enemies
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
-- Every perk's numbers at once, no slots: their classes and values from the game's table.
-- (Not Flow Gambit or Blood and Guts: those cost you.)
P.all_perks = false
local ALL_PERKS = { { "passive_mod_class__smgs", 1 }, { "passive_mod_class_adrenaline_multiplier", 1.2 }, { "passive_mod_class_adrenaline_no_decay", 1 }, { "passive_mod_class_ammo_pickup_percentage", 0.5 }, { "passive_mod_class_ammo_pickup_scaler", 1.5 }, { "passive_mod_class_ammo_vaccuum", 1 }, { "passive_mod_class_cash_vaccuum", 1 }, { "passive_mod_class_chained_weakshot", 0.3 }, { "passive_mod_class_crouch_speed", 1 }, { "passive_mod_class_durable", 1.5 }, { "passive_mod_class_electrified", 0.35 }, { "passive_mod_class_faster_reload_after_crit_kill", 1 }, { "passive_mod_class_fine_aim_speed", 1 }, { "passive_mod_class_finisher_cooldown_on_headshot_kills", 0.5 }, { "passive_mod_class_finisher_cooldown_on_shove_kill", 0.5 }, { "passive_mod_class_finisher_health", 1 }, { "passive_mod_class_flanking", 1 }, { "passive_mod_class_health_regen_on_enemy_killed", 1 }, { "passive_mod_class_healthy", 1 }, { "passive_mod_class_hipfire_recoil_reduction", 1 }, { "passive_mod_class_hipfire_spread_scaler", 0.7 }, { "passive_mod_class_hipfire_spread_shotgun_scaler", 0.8 }, { "passive_mod_class_horror", 11 }, { "passive_mod_class_notoriety_scaler", -0.6 }, { "passive_mod_class_saints_melee_damage", 1 }, { "passive_mod_class_saints_weapon_damage", 1 }, { "passive_mod_class_saving_throw", 35 }, { "passive_mod_class_shove_damage", 15 }, { "passive_mod_class_skilled", 12 }, { "passive_mod_class_sprint_speed_low_health", 0.3 }, { "passive_mod_class_taser_on_enemy_melee_damage", 15 }, { "passive_mod_class_vehicle_boost_duration", 0.5 }, { "passive_mod_class_vehicle_boost_on_near_miss", 0.6 }, { "passive_mod_class_vehicle_health_on_vehicle_death", 0.5 }, { "passive_mod_class_vehicle_sideswipe_damage", 1 }, { "passive_mod_class_wingsuit_length", 0.5 }, { "passive_mod_class_wingsuit_lift", 0.5 }, { "passive_mod_class_xp_scaler", 0.15 } }
local all_perks_set = false
local perk_stats
function P.update_perks()
  -- a new stats object (a respawn or a reload) has none of what we added
  local e = P.object()
  local c = e and wml.call(wml.base + 0x4A17C0, e) or 0
  local stats = c ~= 0 and wml.read_u64(c + 0x1050) or nil
  if stats and stats ~= perk_stats then perk_stats, perk_set, all_perks_set = stats, {}, false end
  if (P.all_perks or false) ~= all_perks_set then
    for _, a in ipairs(ALL_PERKS) do perk(a[1], a[2], P.all_perks) end
    all_perks_set = P.all_perks or false
  end
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
function P.effect_on(entry, name, secs, dir)
  local B = wml.base
  local cid, oid = comp_ref(0x7B, entry)
  if not cid then return false end
  local me, none = wml.read_u32(P.object() + 0x58), wml.read_u32(B + 0x3C44910)
  local buf = wml.buffer(0)
  for i = 0, 0x100, 8 do wml.write_u64(buf + i, 0) end
  wml.write_u64(buf, B + 0x29C71E8)
  local vals = { { c = cid, o = oid }, { u = crc_of(name) }, { f = 1.0 }, dir and { v = dir } or { u = 0 }, { u = none }, { f = secs }, { u = me }, { u = me }, { u = 0 }, { f = 0.0 }, { u = none }, { u = none }, { u = 0 } }
  for i, v in ipairs(vals) do
    local slot = buf + 0x400 + (i - 1) * 0x20
    wml.write_u64(buf + 0x18 + (i - 1) * 8, slot); wml.write_u64(slot, 0); wml.write_u64(slot + 8, 0)
    if v.c then wml.write_u64(slot, v.c); wml.write_u32(slot + 8, v.o)
    elseif v.v then for j = 1, 3 do wml.write_f32(slot + (j - 1) * 4, v.v[j]) end
    elseif v.f then wml.write_f32(slot, v.f) else wml.write_u32(slot, v.u) end
  end
  wml.call(B + 0x76A6E0, buf)
  return true
end
-- Notoriety's on and off nodes (no input: every faction).
P.no_call_ins, P.no_roadblocks, P.no_escape = false, false, false
local NOTORIETY = { no_call_ins = { 0x705F00, 0x2991A30, 0x705F70, 0x29C9540 }, no_roadblocks = { 0x706130, 0x29958A0, 0x706160, 0x2993878 }, no_escape = { 0x7062F0, 0x29D1F08, 0x706310, 0x29CEB50 } }
local notoriety_set = {}
function P.notoriety_reset() notoriety_set = {} end
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

-- Rows the game can quietly undo (a mission, a load, a respawn) and that are otherwise
-- set only when changed: said again every few seconds while they're on, so a row that
-- says On is on, with no need to switch it off and on.
function P.reassert()
  if P.flow then P.update_flow() end
  if P.takedown then P.update_takedown() end
  if P.walk_style then P.update_walk() end
  if P.render_hide then P.update_render() end
  if P.cam_delay then P.update_cam_delay() end
  if P.forget_fast then P.update_forget() end
  if P.free_skills then P.update_free_skills() end
  if P.no_call_ins or P.no_roadblocks or P.no_escape then P.notoriety_reset() end
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
    if v.p then wml.write_u64(slot, v.p)
    elseif v.v then for j = 1, 3 do wml.write_f32(slot + (j - 1) * 4, v.v[j]) end
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
-- Bodyguards: spawned people carry a gang's goal set and walk off. Set the homie goal
-- set (ai_set_goal_action_set +AE7BD0), the friendly faction and the order a homie gets
-- (+AE5720: "assist player", you), and they stay with you. Either alone didn't do it.
function P.make_follower(id)
  local e = P.entry_of(id)
  local me = P.object()
  if not e or not me then return false end
  local ai = wml.call(wml.base + 0x48A760, e)
  if ai == 0 then return false end
  P.node(0xAE7BD0, 0x29E8570, { { u = id }, { u = faction("homie") } })
  P.node(0xADEB50, 0x29E6A58, { { u = id }, { u = faction("saints friendly") } })
  P.node(0xAE5720, 0x29DD280, { { u = id }, { u = faction("assist player") }, { u = wml.read_u32(me + 0x58) } })
  wml.write_u32(ai + 0x1E68, wml.read_u32(ai + 0x1E68) | 0xC000)
  return true
end
function P.follow_near(radius)
  return each_near(radius, function(p) P.make_follower(id_of(p)) end)
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
-- Movement style: animation_set_anim_group_node (object, pointer to the tag's text, force);
-- animation_clear_anim_group_node (object). Weapons can set their own over it.
P.move_style = false
function P.update_move_style()
  local e = P.object()
  if not e then return end
  local id = wml.read_u32(e + 0x58)
  if P.move_style then
    local s = wml.buffer(0) + 0xE00
    cstr(s, P.move_style)
    P.node(0x18EA2C0, 0x2ABE208, { { u = id }, { p = s }, { u = 1 } })
  else
    P.node(0x18EA440, 0x2ABCF20, { { u = id } })
  end
end
-- Wingsuit from low down: the height it needs is copied once to +2E7FAE4, latched by the
-- byte +5BE7498 (default 5 m). You still need to be falling and press the key.
P.wingsuit_low = false
function P.update_wingsuit_low()
  local a = wml.base + 0x2E7FAE4
  wml.write_u8(wml.base + 0x5BE7498, 1)
  if P.wingsuit_low then
    SR5TM_WING_H = SR5TM_WING_H or wml.read_f32(a)
    wml.write_f32(a, 0.1)
  elseif SR5TM_WING_H then wml.write_f32(a, SR5TM_WING_H) end
end
-- Disarm, kept up: everyone near every two seconds, as new people come along.
P.no_guns = false
function P.update_no_guns() P.near_arms(false, 60) end
-- lofted needs a direction: with none it goes "away from you" and they barely leave the
-- ground (0.2 m); straight up they rose 14 m. disintegrate holds them, taking no damage,
-- and they're gone the moment it ends: 2 s here. toxic_waste is looks only (its total
-- damage input does nothing), so Poison adds a sixth of their health a second.
function P.float_on(e) return P.effect_on(e, "lofted", 8, { 0, 1, 0 }) end
function P.dissolve_on(e) return P.effect_on(e, "disintegrate", 2) end
local poisoned = {}
function P.poison_on(e)
  P.effect_on(e, "toxic_waste", 8)
  poisoned[#poisoned + 1] = { id = wml.read_u32(e + 0x58), ticks = 8 }
  return true
end
function P.poison_active() return #poisoned > 0 end
function P.update_poison()
  local left = {}
  for _, q in ipairs(poisoned) do
    local e = P.entry_of(q.id)
    local h = e and wml.read_u32(e + 0x58) == q.id and P.component(0x8D, e)
    if h and wml.read_u8(h + 0x104) == 0 then
      P.damage(e, wml.read_f32(h + MAX) / 6)
      q.ticks = q.ticks - 1
      if q.ticks > 0 then left[#left + 1] = q end
    end
  end
  poisoned = left
end
-- Other status effects on everyone near, each with its own time; see P.effect_on.
function P.near_effect(name, secs, radius)
  return each_near(radius, function(p) P.effect_on(p.entry, name, secs) end)
end
-- Wingsuit now: the request the game makes when you press the key while falling,
-- +15325A0(gail, &human_wing_suit, id, "CODE"). From the ground that leaves you stuck in
-- the state, not moving, so you're put 40 m up first. The "falling" state can't be trusted to
-- mean in the air: it stays on if asked for on the ground.
local wing_wait
function P.wing_pending() return wing_wait ~= nil end
function P.wingsuit_now()
  local e = P.object()
  local gail = e and wml.call(wml.base + 0x1534D80, e)
  if not gail or gail == 0 then return false end
  local x, y, z = P.position()
  P.teleport(x, y + 40, z)
  wing_wait = 90
  return true
end
function P.update_wing()
  wing_wait = wing_wait - 1
  local e = P.object()
  local gail = e and wml.call(wml.base + 0x1534D80, e)
  if not gail or gail == 0 or wing_wait <= 0 then wing_wait = nil; return end
  -- once the teleport has landed you in the falling state
  if wing_wait < 70 and wml.read_u32(gail + 0x324) == wml.read_u32(wml.base + 0x3C17678) then
    wml.call(wml.base + 0x15325A0, gail, wml.base + 0x3C20F9C, e + 0x58, wml.base + 0x2999C7C)
    wing_wait = nil
  end
end
-- Send in a gang: notoriety_set_level_node (level, faction, 0), then
-- notoriety_call_in_reinforcements_node (faction), which fails at level 0.
function P.send_gang(hash, level)
  P.node(0x7053A0, 0x29CBED8, { { u = level }, { u = hash }, { u = 0 } })
  P.node(0x705DA0, 0x2988678, { { u = hash } })
  return true
end
-- Surf: vehicle_surf_node (+7344A0), filled by hand: it keeps a listener on the block, so the
-- block lives in a host buffer and +0x90 (the listener) keeps its old value, -1 at first.
local SURF = { 0x299DC98, 0x7344A0 }
function P.nearest_car(radius)
  local px, py, pz = P.position()
  local best, bd
  for _, v in ipairs(objects_near(radius, 0x44)) do
    if P.component(0x12, v.entry) then
      local dx, dz = s32(wml.read_u32(v.entry + 0x30)) / 10000 - px, s32(wml.read_u32(v.entry + 0x38)) / 10000 - pz
      local d = dx * dx + dz * dz
      if not bd or d < bd then best, bd = v.entry, d end
    end
  end
  return best
end
function P.surf_nearest()
  local B, me = wml.base, P.object()
  local car = me and P.nearest_car(15)
  if not car then return false, "No vehicle within 15 m" end
  if not P.component(0xC5, car) then return false, "That vehicle can't be surfed" end
  local n = wml.buffer(12) + 0x800
  local h = wml.read_u32(n + 0x90)
  if wml.read_u64(n) ~= B + SURF[1] then h = 0xFFFFFFFF end
  for i = 0, 0xC8, 8 do wml.write_u64(n + i, 0) end
  wml.write_u64(n, B + SURF[1])
  wml.write_u32(n + 0x90, h)
  local vals = { wml.read_u32(me + 0x58), wml.read_u32(car + 0x58), 0, 1, 1, 1, 1, 1, 0, 0 }
  for i, v in ipairs(vals) do
    local c = n + 0x100 + (i - 1) * 8
    wml.write_u64(c, 0); wml.write_u32(c, v)
    wml.write_u64(n + 0x18 + (i - 1) * 8, c)
  end
  wml.call(B + SURF[2], n)
  return true
end
-- Game speed: the frame step divides by this float (+2E80BC4, 1 is normal), so 4 is quarter
-- speed and 0.25 is four times as fast. Nothing else writes it.
P.game_speed = false
function P.update_speed() wml.write_f32(wml.base + 0x2E80BC4, P.game_speed or 1.0) end
-- Stay in combat: the combat state's own force byte.
P.force_combat = false
function P.update_force_combat() wml.write_u8(wml.base + 0x5BE37A4, P.force_combat and 1 or 0) end
-- Go to a time: +76E490 says if time may move on now, +76E5E0(hour) goes to that hour of
-- the clock (read live: not a number of hours to add, as the handler's name suggests).
function P.go_to_hour(h)
  if wml.call(wml.base + 0x76E490) & 0xFF == 0 then return false end
  wml.callf(wml.base + 0x76E5E0, h + 0.0)
  return true
end
-- Warp from map: the big map has a dev teleport behind gml_is_release_build(), ending in
-- debug_teleport_player, a stub in C. Both are ordinary Lua globals, so they're replaced while this
-- is on; the cursor's position comes back to us here, for the host side to teleport to, high up.
P.warp_map = false
local warp_on
function P.update_warp()
  if P.warp_map and not warp_on then
    wml.game([[rawset(_G, "Sr5tm_release", rawget(_G, "Sr5tm_release") or gml_is_release_build)
      gml_is_release_build = function() return false end
      debug_teleport_player = function(x, z) rawset(_G, "Sr5tm_wx", x) rawset(_G, "Sr5tm_wz", z) end]])
    warp_on = true
  elseif not P.warp_map and warp_on then
    wml.game([[if rawget(_G, "Sr5tm_release") then gml_is_release_build = rawget(_G, "Sr5tm_release") end]])
    warp_on = false
  end
  if warp_on then
    local ok, x, z = wml.game([[local x, z = rawget(_G, "Sr5tm_wx"), rawget(_G, "Sr5tm_wz") if x then rawset(_G, "Sr5tm_wx", nil) return x, z end]])
    if ok and type(x) == "number" then P.teleport(x, 300, z) end
  end
end
-- The console: 378 handlers survive with only their registration stripped. One goes in the
-- empty table for one call of the game's parser, +E47A30, with the "ready" byte set, then it's all
-- undone. Never call a handler directly: a bad argument longjmps through a stale buffer.
function P.console(handler, line)
  local B, b = wml.base, wml.buffer(14) + 0x800
  if wml.read_u32(B + 0x4BA9930) ~= 3 then return nil end
  local cmd, name, text = b, b + 0x40, b + 0x60
  for i = 0, 0x20, 8 do wml.write_u64(cmd + i, 0) end
  local function put(a, s)
    for i = 1, #s do wml.write_u8(a + i - 1, s:byte(i)) end
    wml.write_u8(a + #s, 0)
  end
  put(name, "tm")
  put(text, "tm " .. (line or ""))
  wml.write_u64(cmd, name)
  wml.write_u64(cmd + 0x10, B + handler)
  wml.write_u32(cmd + 0x20, 0)
  wml.write_u8(cmd + 0x24, 1)
  local n = wml.read_u32(B + 0x5BEB05C)
  local slot = B + 0x4BA9E50 + n * 8
  wml.write_u64(slot, cmd)
  wml.write_u32(B + 0x5BEB05C, n + 1)
  wml.write_u8(B + 0x5BEB094, 1)
  local r = wml.call(B + 0xE47A30, text)
  wml.write_u8(B + 0x5BEB094, 0)
  wml.write_u32(B + 0x5BEB05C, n)
  wml.write_u64(slot, 0)
  return r & 0xFFFFFFFF
end
-- World tuning. Live config records and globals, each read when it's used, so a write takes at
-- once: originals kept by address for the session. *(+5BE34A8) is damage_system_config: +0x98 AI vs AI
-- damage, +0x60 back shot, +0x78 flinch cooldown, +0x7E your dodge's safe ms, +0x9C damage to yourself.
-- *(+5BE7EC8) ambient config: +0x4C and +0x54 people and cars in bad weather. +2E7FB7C how far off
-- traffic spawns (rewritten on a change of district, so kept up).
local TUNES = {
  fight_damage = { { ptr = 0x5BE34A8, off = 0x98 } }, back_stab = { { ptr = 0x5BE34A8, off = 0x60 } },
  no_flinch = { { ptr = 0x5BE34A8, off = 0x78 } }, dodge_ms = { { ptr = 0x5BE34A8, off = 0x7E, u16 = true } },
  own_blast = { { ptr = 0x5BE34A8, off = 0x9C } }, rain_crowd = { { ptr = 0x5BE7EC8, off = 0x4C }, { ptr = 0x5BE7EC8, off = 0x54 } },
  traffic_far = { { addr = 0x2E7FB7C } },
}
SR5TM_ORIG = SR5TM_ORIG or {}
local function tune_addr(t)
  if t.addr then return wml.base + t.addr end
  local base = wml.read_u64(wml.base + t.ptr)
  return base ~= 0 and base + t.off or nil
end
function P.update_tunes()
  for key, list in pairs(TUNES) do
    for _, t in ipairs(list) do
      local a = tune_addr(t)
      if a then
        local read = t.u16 and wml.read_u16 or wml.read_f32
        local write = t.u16 and wml.write_u16 or wml.write_f32
        if P[key] then
          if SR5TM_ORIG[a] == nil then SR5TM_ORIG[a] = read(a) end
          write(a, P[key])
        elseif SR5TM_ORIG[a] ~= nil then
          write(a, SR5TM_ORIG[a])
          SR5TM_ORIG[a] = nil
        end
      end
    end
  end
  -- World gravity: the physics world's own vector, *(+5CB4FF0) +0xA94 up. Never exactly 0: AI grenades skip then.
  local world = wml.read_u64(wml.base + 0x5CB4FF0)
  if world ~= 0 and (P.world_gravity or SR5TM_GRAVITY) then
    local a = world + 0xA94
    SR5TM_GRAVITY = SR5TM_GRAVITY or wml.read_f32(a)
    wml.write_f32(a, SR5TM_GRAVITY * (P.world_gravity or 1))
    if not P.world_gravity then SR5TM_GRAVITY = nil end
  end
  P.update_density()
end
-- Crowds and traffic: the district's active spawn limits, *(+314A9D0): group list +0x38, chosen by +314A9D8,
-- 0x40 each: +0x04 people, +0x10 vehicles. Originals by address, since districts have their own record.
P.peds, P.traffic = false, false
SR5TM_DENSITY = SR5TM_DENSITY or {}
function P.update_density()
  local rec = wml.read_u64(wml.base + 0x314A9D0)
  if rec == 0 then return end
  local e = wml.read_u64(rec + 0x38) + wml.read_u32(wml.base + 0x314A9D8) * 0x40
  for off, key in pairs({ [0x04] = "peds", [0x10] = "traffic" }) do
    local a = e + off
    if P[key] or SR5TM_DENSITY[a] then
      SR5TM_DENSITY[a] = SR5TM_DENSITY[a] or wml.read_u32(a)
      wml.write_u32(a, math.floor(SR5TM_DENSITY[a] * (P[key] or 1)))
      if not P[key] then SR5TM_DENSITY[a] = nil end
    end
  end
end
function P.tunes_active()
  for key in pairs(TUNES) do if P[key] then return true end end
  return next(SR5TM_ORIG) ~= nil or P.world_gravity or SR5TM_GRAVITY or P.peds or P.traffic or next(SR5TM_DENSITY) ~= nil
end
-- Explosions: the host scales each one as it goes off.
P.blast_size, P.blast_force, P.blast_damage = false, false, false
function P.update_blast()
  if wml.aoe_scale then return wml.aoe_scale(P.blast_size or 1, P.blast_force or 1, P.blast_damage or 1) end
end
-- Launches: physics_apply_impulse_node (object, impulse, cause), in kg m/s; for people
-- physics_start_ragdoll_node (object, blend ms, impulse, 0, 1): 1500 sent one 124 m up, 500 is about 15.
function P.launch_car(impulse)
  local car = P.vehicle_object() or P.nearest_car(30)
  if not car then return false end
  P.node(0x192F2E0, 0x2AC6608, { { u = wml.read_u32(car + 0x58) }, { v = { 0, impulse, 0 } }, { u = wml.read_u32(P.object() + 0x58) } })
  return true
end
function P.launch_near(radius)
  return each_near(radius, function(p)
    if P.component(2, p.entry) then
      P.node(0x1932670, 0x2ACB760, { { u = id_of(p) }, { u = 200 }, { v = { 0, 500, 0 } }, { u = 0 }, { u = 1 } })
    end
  end)
end
-- Enemy aim: how far each kind of shot is meant to miss by, scaled on the game's own records.
P.enemy_aim = false
local aim_entries, aim_set
local AIM_STATES = { "m_stationary", "m_crouching", "m_lateral_move", "m_dodging" }
local AIM_FIELDS = { "m_min_horizontal_distance", "m_max_horizontal_distance", "m_max_height_distance", "m_max_depth_distance" }
function P.update_enemy_aim()
  if (P.enemy_aim or false) == (aim_set or false) then return end
  if not aim_entries then
    local fields = { { path = "m_minimum_miss_distance", what = "min" } }
    for _, st in ipairs(AIM_STATES) do for _, f in ipairs(AIM_FIELDS) do fields[#fields + 1] = { path = st .. "." .. f, what = f } end end
    aim_entries = require("vdata").collect("ai_reflected_miss_information", fields)
  end
  local V = require("vdata")
  for _, e in ipairs(aim_entries) do V.write(e.addr, e.t, e.orig * (P.enemy_aim or 1)) end
  aim_set = P.enemy_aim
  return #aim_entries
end
-- Switches with no inputs, on a change: peds fight back, every AI in combat mode.
P.combative_peds, P.ai_combat = false, false
local switch_was = {}
function P.update_switches()
  local list = { { "combative_peds", 0xAE21A0, 0x29EB1F8, 0xAE21E0, 0x29DB5F0 }, { "ai_combat", 0xAE9C60, 0x29E8AB0, 0xAE9C80, 0x29EB238 } }
  for _, s in ipairs(list) do
    if (P[s[1]] or false) ~= (switch_was[s[1]] or false) then
      if P[s[1]] then P.node(s[2], s[3], {}) else P.node(s[4], s[5], {}) end
      switch_was[s[1]] = P[s[1]]
    end
  end
end
-- Gang war: a hostile override each way between the sides (+ADEC50, read live on every check, undone by
-- +ADED00), plus a belief of the nearest enemy for those who haven't one (+ADE550): neutral people
-- ignore shots at others, and how they spot each other by sight isn't known.
P.gang_war = false
SR5TM_WAR = SR5TM_WAR or {}
local function war_side(a, b, on)
  if on then
    P.node(0xADEC50, 0x29E7320, { { u = a }, { u = b }, { u = 1 } })
    P.node(0xADEC50, 0x29E7320, { { u = b }, { u = a }, { u = 1 } })
  else
    P.node(0xADED00, 0x29E2C00, { { u = a }, { u = b } })
    P.node(0xADED00, 0x29E2C00, { { u = b }, { u = a } })
  end
end
function P.war_active() return P.gang_war or SR5TM_WAR.pairs ~= nil end
function P.update_war()
  if P.gang_war ~= SR5TM_WAR.mode then
    for _, s in ipairs(SR5TM_WAR.pairs or {}) do war_side(s[1], s[2], false) end
    SR5TM_WAR.pairs, SR5TM_WAR.mode = P.gang_war or nil, P.gang_war
    for _, s in ipairs(SR5TM_WAR.pairs or {}) do war_side(s[1], s[2], true) end
  end
  if not P.gang_war then return end
  local enemies = {}
  for _, s in ipairs(P.gang_war) do
    enemies[s[1]] = enemies[s[1]] or {}; enemies[s[1]][s[2]] = true
    enemies[s[2]] = enemies[s[2]] or {}; enemies[s[2]][s[1]] = true
  end
  local B, buf, all = wml.base, wml.buffer(13), {}
  for _, p in ipairs(P.people_near(90)) do
    local ai = wml.call(B + 0x48A760, p.entry)
    if ai ~= 0 and wml.read_u8(p.health + 0x104) == 0 and wml.read_u32(ai + 0xF84) ~= 2 then
      local fighter = wml.read_u32(ai + 0x1E68) & 2 ~= 0 or wml.read_u8(wml.call(B + 0x3207D0, ai) + 0x119) == 0
      wml.call(B + 0x320030, ai, buf)
      all[#all + 1] = { e = p.entry, ai = ai, f = wml.read_u32(buf), fighter = fighter, x = s32(wml.read_u32(p.entry + 0x30)), y = s32(wml.read_u32(p.entry + 0x34)), z = s32(wml.read_u32(p.entry + 0x38)) }
    end
  end
  for _, a in ipairs(all) do
    local want = a.fighter and enemies[a.f]
    if want then
      local best, bd
      for _, t in ipairs(all) do
        if want[t.f] then
          local dx, dy, dz = (t.x - a.x) / 10000, (t.y - a.y) / 10000, (t.z - a.z) / 10000
          local d = dx * dx + dy * dy + dz * dz
          if not bd or d < bd then best, bd = t, d end
        end
      end
      if best and wml.call(B + 0x2F9DA0, a.ai + 0x2B0, best.e + 0x58) & 0xFF == 0 then
        P.node(0xADE550, 0x29EA3F8, { { u = wml.read_u32(a.e + 0x58) }, { u = wml.read_u32(best.e + 0x58) } })
      end
    end
  end
end
-- Get up: the node co-op uses to bring back a downed player.
function P.revive_me()
  local e = P.object()
  if not e then return false end
  P.node(0xAEC2D0, 0x29DDE88, { { u = wml.read_u32(e + 0x58) } })
  return true
end
-- Test guns: dev parents, vehicle mounts and skills' own guns. +988830(record, 0) disowns one
-- silently; a slot holding one is emptied separately.
local INTERNAL = { weapon_ability_quick_draw_pistol = 1, weapon_ability_death_blossom_smg = 1, weapon_sniper_ability_overwatch = 1,
  larp_death_blossom_inventory = 1, larp_death_blossom_smg_inventory = 1, weapon_veh_frostlander_turret = 1 }
function P.weapon_is_internal(name)
  return INTERNAL[name] or name:find("^weapon_parent") or name:find("^weapon_vehicle_")
end
function P.disown_weapon(name)
  local r = P.weapon_record(name)
  if not r then return false end
  if wml.call(wml.base + 0x988AA0, r) & 0xFF ~= 0 then wml.call(wml.base + 0x988830, r, 0) end
  return true
end
function P.clear_internal_slots()
  local _, active = wml.game("return player_local_inventory_get_active_slot()")
  local n = 0
  for s = 1, 12 do
    local _, t = wml.game("return tostring(player_local_inventory_get_item_info(" .. s .. "))")
    local name = type(t) == "string" and t:match('"(.-)"')
    if name and P.weapon_is_internal(name) then
      wml.game("weapon_clear_inventory_slot(" .. s .. ")")
      n = n + 1
      if s == active then wml.game("player_local_inventory_equip(0)") end
    end
  end
  return n
end
-- Prototype weapons: no table names their prefabs, and weapon_inventory_set_slot_item_node refuses
-- them for that reason. The console's give command doesn't look: a bare name, a 1-based slot, a loadout.
function P.give_prefab_weapon(name, slot)
  return P.console(0x989D90, name .. " " .. (slot + 1) .. " primary") == 0
end
-- Friendly fire: your shots do nothing to anyone friendly or allied to you (+3EDA50, a
-- relation of 4 or 5): x0 while +5BE7E38 is 0, x0.5 at 1, full at anything else.
P.friendly_fire = false
function P.update_friendly_fire()
  wml.write_u32(wml.base + 0x5BE7E38, P.friendly_fire or 0)
end
-- Undo my look: the game's own character capture and apply, as its prank and mission backups
-- use, on a state in memory of our own: +4289E0 constructs it (needed), +1424500(cust, state)
-- captures, +1422DF0(cust, state, body, outfit, 0x10) applies. Kept for the session.
local function cust()
  local o = P.object()
  if not o then return nil end
  local c = wml.call(wml.base + 0x496100, o)
  return c ~= 0 and c or nil
end
function P.look_snapshot()
  local B, c = wml.base, cust()
  if not c or wml.read_u8(c + 0x34EE7) ~= 0 then return false end
  if not SR5TM_LOOK_BUF then
    local p = wml.call(wml.read_u64(B + 0x25832C0), 0, 0x10000, 0x3000, 4)   -- VirtualAlloc
    if p == 0 then return false end
    wml.call(B + 0x4289E0, p)
    SR5TM_LOOK_BUF = p
  end
  wml.call(B + 0x1424500, c, SR5TM_LOOK_BUF)
  SR5TM_LOOK_OK = true
  return true
end
function P.look_first() if not SR5TM_LOOK_OK then return P.look_snapshot() end return true end
function P.look_restore()
  local c = cust()
  if not c or not SR5TM_LOOK_OK then return false end
  wml.call(wml.base + 0x1422DF0, c, SR5TM_LOOK_BUF, 1, 1, 0x10)
  return true
end
-- Body past the sliders: a weight holds "customized" (+0xC, what's saved) and "current" (+0x10,
-- what's drawn). +14227E0(cust, &crc, value, 0) writes current only, so the save never sees
-- this. Nothing clamps. Kept up every 2 s: a load or respawn puts the saved values back.
local BODY = { body_muscular = "muscular", body_large = "large", body_thin = "thin", body_gender = "gender", body_breasts = "breasts",
  body_eyes = "eye size", body_nose = "nose size", body_mouth = "mouth size", body_head = "generic_feature_head" }
local body_crc, body_on = {}, {}
local function weight_of(c, crc_v)
  for i = 0, wml.read_u32(c) - 1 do
    local w = c + 8 + i * 0x20
    if wml.read_u32(wml.read_u64(w) + 0x34) == crc_v then return w end
  end
end
function P.update_body()
  local c = cust()
  if not c then return end
  local b = wml.buffer(13)
  for key, name in pairs(BODY) do
    local v = P[key]
    if v or body_on[key] then
      body_crc[name] = body_crc[name] or crc_of(name)
      local w = weight_of(c, body_crc[name])
      if w then
        local want = v or wml.read_f32(w + 0xC)
        if math.abs(wml.read_f32(w + 0x10) - want) > 1e-3 then
          wml.write_u32(b, body_crc[name])
          wml.callf(wml.base + 0x14227E0, c, b, want + 0.0, 0)
        end
        body_on[key] = v and true or nil
      end
    end
  end
end
function P.body_active()
  if next(body_on) then return true end
  for key in pairs(BODY) do if P[key] then return true end end
  return false
end
function P.body_back()
  for key in pairs(BODY) do if P[key] then P[key] = false; body_on[key] = true end end
  P.update_body()
end
-- Radio: the station's entry from +381500(&hash); stopping its audio object (+FE0420)
-- makes its own update pick the next track. The radio is the vehicle's (component 0x8F).
function P.radio_skip()
  local B = wml.base
  local ok, played = wml.game("if playlist_is_playing() then playlist_skip_song() return true end return false")
  if ok and played then return "Skipped" end
  local o = wml.call(B + 0xB5F350, 0, 1, 0)
  local c = o ~= 0 and wml.call(B + 0x5112C0, o) or 0
  if c == 0 then return "Nothing playing" end
  local st = wml.read_u32(c + 0xC)
  local _, off = wml.game('return string_crc("off")')
  if st == math.floor(off) & 0xFFFFFFFF then return "The radio's off" end
  local b = wml.buffer(13)
  wml.write_u32(b, st)
  local entry = wml.call(B + 0x381500, b)
  if entry == 0 then return "Nothing playing" end
  wml.call(B + 0xFE0420, wml.read_u64(entry + 8))
  return "Skipped"
end
-- Props. A prefab's id needs its full path and extension: a bare name has no resource, and spawning
-- one crashes. +E8EA40 only records a name. The load is +E71120(name, 0x12, 0), once each for the
-- .cprefab_pc and the .hprefab_pc, taking a reference; +E715E0 gives 2 loading, 3 finishing, 4 ready,
-- 5 failed. Both 4, spawn; then +E71480(id, 0x12) drops our references (the object has its own).
local PROP_DIRS = {
  ["crib-placeable-electric-chicken_01a"] = "dlc_01", ["crib-placeable-fabulous-egg_01d"] = "dlc_01", ["prop_egg-golden_01a"] = "dlc_01",
  ["crib-placeable-spooky-tree-haunted-hotel-evil_01b"] = "dlc_02", ["crib-placeable-giant-spider_01a"] = "dlc_02", ["crib-placeable-spooky-black-cauldron_01b"] = "dlc_02", ["crib-placeable-spooky-demonic-angel_01b"] = "dlc_02", ["crib-placeable-spooky-clown-painting_01b"] = "dlc_02",
  ["crib-placeable-prop_xmas-tree_01"] = "dlc_03", ["crib-placeable-xmas-tree-pole_01a"] = "dlc_03", ["crib-placeable-dreidel_01a"] = "dlc_03", ["crib-placeable-hanukkah-candle_01a"] = "dlc_03", ["crib-placeable-kwanzaa-candle_01a"] = "dlc_03", ["crib-placeable-xmas-tree-twig_01a"] = "dlc_03",
  ["crib-placeable-rabbit-statue_01a"] = "dlc_cny", ["crib-placeable-prop_shark-statue_01a"] = "dlc_dead",
  ["crib-placeable-drone-marshall_01a"] = "dlc_exp_01_lucky", ["crib-placeable-prop_camera-movie_01a"] = "dlc_exp_01_lucky", ["crib-placeable-prop_statue_silver-siren_01a"] = "dlc_exp_01_lucky", ["crib-placeable-crown-reward_01a"] = "dlc_exp_01_lucky",
  ["crib-placeable-dustfaire-paper-airplane_01a"] = "dlc_exp_02_dusty", ["crib-placeable-storm-giant-bones_01a"] = "dlc_exp_02_dusty", ["crib-placeable-saving-roll_01a"] = "dlc_exp_02_dusty", ["prop_lp02-paint-balloon_01a_spawnable"] = "dlc_exp_02_dusty", ["prop_speaker-large_01a_spawn"] = "dlc_exp_02_dusty",
}
local PROP_PATHS = {
  boot_hill_act_doc_ketchum_stage = [[data\dlc_boothill\spawnables\gameplay\prefabs\activities\boot_hill\]],
  heist_rodeo_stage_scene_01 = [[data\sr_city\spawnables\gameplay\prefabs\activities\heist\]],
  laundromat_rodeo_ramp_01 = [[data\sr_city\spawnables\gameplay\prefabs\activities\laundromat\]],
  roadblock_construction_ramp_01 = [[data\sr_city\spawnables\gameplay\prefabs\roadblocks\]],
  roadblock_idols_ramp_01a = [[data\sr_city\spawnables\gameplay\prefabs\roadblocks\]],
}
local function prop_path(name)
  if PROP_PATHS[name] then return PROP_PATHS[name] .. name end
  local dir = PROP_DIRS[name] or (name:find("boot%-hill") and "dlc_boothill") or "sr_city"
  return "data\\" .. dir .. "\\spawnables\\props\\prefabs\\" .. name
end
P.props = {}
local prop_wait
local prop_release = {}
local PROP_GROUP = 0x12
function P.prop_pending() return prop_wait ~= nil end
function P.spawn_prop(name)
  if prop_wait then return false end
  local B, path = wml.base, prop_path(name)
  local cid = wml.call(B + 0xE71120, wml.buffer(5, path .. ".cprefab_pc"), PROP_GROUP, 0)
  local hid = wml.call(B + 0xE71120, wml.buffer(5, path .. ".hprefab_pc"), PROP_GROUP, 0)
  if cid == 0 or hid == 0 then
    if cid ~= 0 then wml.call(B + 0xE71480, cid, PROP_GROUP) end
    if hid ~= 0 then wml.call(B + 0xE71480, hid, PROP_GROUP) end
    return false
  end
  prop_wait = { path = path, cid = cid, hid = hid, ticks = 1800 }
  return true
end
function P.update_prop()
  local B, w = wml.base, prop_wait
  local a, b = wml.call(B + 0xE715E0, w.cid) & 0xFFFFFFFF, wml.call(B + 0xE715E0, w.hid) & 0xFFFFFFFF
  w.ticks = w.ticks - 1
  local done
  if a == 5 or b == 5 then done = "not found"
  elseif a == 4 and b == 4 then
    local e = P.object()
    if e then
      local obj = P.spawn_prefab(w.path .. ".cprefab_pc", 0, wml.read_f32(e + 0x20) * 6, wml.read_f32(e + 0x28) * 6)
      done = obj and "spawned" or "refused"
      if obj then P.props[#P.props + 1] = obj end
    end
  elseif w.ticks <= 0 then done = "still loading" end
  if done then
    -- Not yet: a spawn may still be populating on a worker thread. Dropped 10 s later.
    prop_release[#prop_release + 1] = { cid = w.cid, hid = w.hid, ticks = 600 }
    prop_wait = nil
  end
  return done
end
function P.update_prop_release()
  local B, left = wml.base, {}
  for _, r in ipairs(prop_release) do
    r.ticks = r.ticks - 1
    if r.ticks > 0 then left[#left + 1] = r
    else
      wml.call(B + 0xE71480, r.cid, PROP_GROUP)
      wml.call(B + 0xE71480, r.hid, PROP_GROUP)
    end
  end
  prop_release = left
end
function P.prop_release_pending() return #prop_release > 0 end
function P.remove_prop(last)
  local B, n = wml.base, 0
  for i = #P.props, 1, -1 do
    local e = wml.call(B + 0x1E69D0, P.props[i] + 0x70, 0)
    if e ~= 0 then wml.call(B + 0x1E6920, e + 0x58); n = n + 1 end
    table.remove(P.props, i)
    if last then break end
  end
  return n
end
-- Off the car: its listener cancelled if it's still waiting, and the state you're
-- normally in (660A9BAD, read live on foot).
function P.surf_stop()
  local B, e = wml.base, P.object()
  local gail = e and wml.call(B + 0x1534D80, e)
  if not gail or gail == 0 then return false end
  local n = wml.buffer(12) + 0x800
  local h = wml.read_u32(n + 0x90)
  if wml.read_u64(n) == B + SURF[1] and h ~= 0xFFFFFFFF then wml.call(B + 0x15363C0, h); wml.write_u32(n + 0x90, 0xFFFFFFFF) end
  local b = wml.buffer(13)
  wml.write_u32(b, 0x660A9BAD)
  wml.call(B + 0x15325A0, gail, b, e + 0x58, B + 0x2999C7C)
  return true
end
-- Free camera: +1B42B40 sets the rendered camera from the gameplay camera's object, gated by byte
-- +5CC7718. With it 0 we call what it ends in, +1505010(&pos, &rows), ourselves: pos 3 int32 at
-- 1/10000 m. The rows still come from the camera object (id at the local player record's +0x1C),
-- so turning the view works as usual. The left stick and keys stop reaching the game meanwhile.
P.free_cam = false
local fc
local FC_GATE = 0x5CC7718
function P.free_cam_active() return P.free_cam or fc ~= nil end
function P.update_free_cam(menu_open)
  local B = wml.base
  local rec = wml.read_u64(B + 0x5BDF320)
  local ce = rec ~= 0 and P.entry_of(wml.read_u32(rec + 0x1C))
  if not P.free_cam or not ce then
    if fc then
      wml.write_u8(B + FC_GATE, 1)
      fc = nil
      if wml.pad_mask then wml.pad_mask(0) end
      if wml.block_input and not menu_open then wml.block_input(false, false) end
    end
    return
  end
  if not fc then
    fc = { s32(wml.read_u32(B + 0x41E1AB0)), s32(wml.read_u32(B + 0x41E1AB4)), s32(wml.read_u32(B + 0x41E1AB8)), wait = 0 }
    wml.write_u8(B + FC_GATE, 0)
  end
  fc.wait = fc.wait - 1
  if fc.wait <= 0 and not menu_open then
    fc.wait = 30
    if wml.pad_mask then wml.pad_mask(0, false, true) end
    if wml.block_input then wml.block_input(true, false, "W", "A", "S", "D", "SPACE", "CTRL", "SHIFT") end
  end
  local buttons, lt, rt, lx, ly = wml.pad()
  local function stick(v) if not v or math.abs(v) < 7849 then return 0 end return (v > 0 and 1 or -1) * (math.abs(v) - 7849) / 24918 end
  local function pull(v) if not v or v <= 30 then return 0 end return (v - 30) / 225 end
  local f, r, u = stick(ly), stick(lx), pull(rt) - pull(lt)
  if not menu_open then
    f = f + (wml.key_down("W") and 1 or 0) - (wml.key_down("S") and 1 or 0)
    r = r + (wml.key_down("D") and 1 or 0) - (wml.key_down("A") and 1 or 0)
    u = u + (wml.key_down("SPACE") and 1 or 0) - (wml.key_down("CTRL") and 1 or 0)
  end
  local step = ((wml.key_down("SHIFT") or (buttons and buttons & 0x40 ~= 0)) and 30 or 8) * 10000 / 60
  fc[1] = fc[1] + (wml.read_f32(ce + 0x20) * f + wml.read_f32(ce) * r) * step
  fc[2] = fc[2] + (wml.read_f32(ce + 0x24) * f + u) * step
  fc[3] = fc[3] + (wml.read_f32(ce + 0x28) * f + wml.read_f32(ce + 8) * r) * step
  local b = wml.buffer(12) + 0xC00
  for i = 1, 3 do wml.write_u32(b + (i - 1) * 4, math.floor(fc[i]) & 0xFFFFFFFF) end
  for i = 0, 0x2F, 4 do wml.write_u32(b + 0x10 + i, wml.read_u32(ce + i)) end
  wml.call(B + 0x1505010, b, b + 0x10)
end
function P.float_near(radius) return each_near(radius, function(p) P.float_on(p.entry) end) end
function P.dissolve_near(radius) return each_near(radius, function(p) P.dissolve_on(p.entry) end) end
function P.toxic_near(radius) return each_near(radius, function(p) P.poison_on(p.entry) end) end
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
  elseif P.no_recoil then
    -- already done for this id, but ids come back and a gun's values can be refilled
    for section = 0, 1 do
      local list, n = wml.read_u64(comp + section * 0x6A0 + 0x138), wml.read_u16(comp + section * 0x6A0 + 0x140)
      if list ~= 0 and n <= 200 then
        for i = 0, n - 1 do
          local e = list + i * 24
          local k = wml.read_u32(e)
          if RECOIL[k] and wml.read_u32(e + 0x10) == 1 and wml.read_f32(e + 8) ~= 0 then set(k, 0) end
        end
      end
    end
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
P.car_brake_lights = false
function P.car_active() return P.car_no_crash or P.car_heavy or P.car_brake_lights or P.car_gravity ~= 1 or next(car_state) ~= nil end
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
  if (P.car_brake_lights or false) ~= (st.brake or false) then
    local lc = P.component(0x4F, v)
    if lc then wml.call(wml.base + 0x1BB22F0, lc, P.car_brake_lights and 1 or 0) end
    st.brake = P.car_brake_lights or false
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
    -- -1 means the gun hasn't initialized its section yet: never keep that as the original
    -- (dividing it gave a delay of days, and off wrote it back). Read again until it's real.
    local o = SR5TM_REFIRE[c]
    if not o or o >= 0x7FFFFFFF then
      o = wml.read_u32(c + 0x7B8)
      SR5TM_REFIRE[c] = o < 0x7FFFFFFF and o or nil
    end
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
    elseif P.entry_of(h.id) then
      if h.mode == "guard" then P.make_follower(h.id) else P.make_hostile(h.id) end
    end
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
      if P.spawn_hostile then hostile_wait[#hostile_wait + 1] = { id = id, ticks = 1, mode = P.spawn_hostile } end
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
local function become(id)
  P.free_cam = false   -- with the camera taken over the game doesn't commit the switch
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
      SR5TM_MY_ID = SR5TM_MY_ID or wml.read_u32(e + 0x58)
      become(id)
      return true
    end
  end
  return false
end
function P.playing_as() return SR5TM_MY_ID ~= nil end
function P.back_to_self()
  if not SR5TM_MY_ID or not P.entry_of(SR5TM_MY_ID) then SR5TM_MY_ID = nil; return false end
  become(SR5TM_MY_ID)
  SR5TM_MY_ID = nil
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
  if not name or not name:find("\\", 1, true) or not name:lower():find("%.cprefab") then return nil end   -- a bare name crashes
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
