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
function P.vehicles_near(radius)
  local mine, out = P.vehicle_object(), {}
  for _, v in ipairs(objects_near(radius, 0x44)) do
    if v.entry ~= mine and P.component(0x12, v.entry) then out[#out + 1] = v end
  end
  return out
end

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
  if stats and stats ~= perk_stats then
    perk_stats, perk_set, all_perks_set = stats, {}, false
    for class, m in pairs(P.perk_dial) do perk(class, m, true) end
  end
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
-- Any perk: any class at any strength, on top of the rows above. Until you quit; a new stats object gets them again.
P.perk_strength = false
P.perk_dial = {}
function P.toggle_perk(class)
  local m = P.perk_dial[class]
  if m then
    perk(class, m, false)
    P.perk_dial[class] = nil
    return false
  end
  m = P.perk_strength or 1
  if not perk(class, m, true) then return nil end
  P.perk_dial[class] = m
  return m
end
function P.perks_off()
  local n = 0
  for class, m in pairs(P.perk_dial) do perk(class, m, false); P.perk_dial[class] = nil; n = n + 1 end
  return n .. (n == 1 and " perk" or " perks") .. " off"
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
P.car_takedowns, P.car_ram, P.car_jump_power, P.car_ability_cd, P.car_ejector, P.car_cowcatcher = false, false, false, false, false, false
local CAR_CFG = {
  car_takedowns = { { 0x54, "set", 5 }, { 0x74, "set", 5 }, { 0xAC, "set", 5 }, { 0xC8, "set", 5 } },
  car_ram = { { 0x120, "mul" }, { 0x138, "mul" } },
  car_jump_power = { { 0x330, "mul" }, { 0x334, "mul" } },
  car_ability_cd = { { 0x274, "zero" }, { 0x348, "zero" }, { 0x368, "zero" } },
  car_ejector = { { 0x284, "mul" }, { 0x288, "mul" } },
  car_cowcatcher = { { 0x3B8, "mul" }, { 0x3BC, "mul" } },
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
    elseif v.i then for j = 1, 3 do wml.write_u32(slot + (j - 1) * 4, v.i[j]) end
    elseif v.c then wml.write_u64(slot, v.c); wml.write_u32(slot + 8, v.o)
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
-- Everyone near, the rest. ai_clear_all_beliefs (+ADFDA0) ends a fight until they see one again; human_exit_dbno
-- (+3C9B60) gets the downed up; the health nodes change tough shields and how hard a hit must be to stagger
-- (health comp +0x168, read at each hit); object_start_fade and end_fade (+193F3D0, +193F420) fade them out and back.
function P.calm_near(radius)
  return each_near(radius, function(p) P.node(0xADFDA0, 0x2A17880, { { u = id_of(p) } }) end)
end
function P.revive_near(radius)
  local list = P.people_near(radius)
  for _, p in ipairs(list) do P.node(0x3C9B60, 0x296A858, { { u = id_of(p) }, { u = 0 } }) end
  return #list
end
function P.strip_near(radius)
  return each_near(radius, function(p) P.node(0x6955E0, 0x2994BA8, { { u = id_of(p) } }) end)
end
function P.tough_near(radius)
  return each_near(radius, function(p) P.node(0x6954E0, 0x29CF388, { { u = id_of(p) } }) end)
end
function P.stagger_near(radius)
  return each_near(radius, function(p) P.node(0x6951F0, 0x29C6E78, { { u = id_of(p) }, { f = 0.01 } }) end)
end
function P.unseen_near(radius)
  return each_near(radius, function(p) P.node(0x193F3D0, 0x2AC10F0, { { u = id_of(p) }, { f = 0.0 }, { f = 1.0 } }) end)
end
function P.seen_near(radius)
  local list = P.people_near(radius)
  for _, p in ipairs(list) do P.node(0x193F420, 0x2ACBC38, { { u = id_of(p) } }) end
  return #list
end
-- A line from anyone with a voice: persona_post_line_situation_event (+18662C0), target, situation, sync flags.
function P.say_near(radius, name)
  local h = crc_of(name)
  return each_near(radius, function(p) P.node(0x18662C0, 0x2AC61D8, { { u = id_of(p) }, { u = h }, { u = 0 } }) end)
end
-- Statues (+1928C00, undo +1928D00), and a burning look with no damage (+6AC280: target, source; out +6AC3D0).
function P.statue_near(radius)
  return each_near(radius, function(p) P.node(0x1928C00, 0x2AC4F80, { { u = id_of(p) } }) end)
end
function P.unstatue_near(radius)
  local list = P.people_near(radius)
  for _, p in ipairs(list) do P.node(0x1928D00, 0x2ACF7A0, { { u = id_of(p) } }) end
  return #list
end
function P.flame_near(radius)
  local me = id_of({ entry = P.object() })
  return each_near(radius, function(p) P.node(0x6AC280, 0x29D5D18, { { u = id_of(p) }, { u = me } }) end)
end
function P.unflame_near(radius)
  local list = P.people_near(radius)
  for _, p in ipairs(list) do P.node(0x6AC3D0, 0x29D4A10, { { u = id_of(p) } }) end
  return #list
end
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
  local vals = { wml.read_u32(me + 0x58), wml.read_u32(car + 0x58), 0, 1, 1, 1, 1, 1, P.surf_autopilot and 1 or 0, 0 }
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
-- Worlds gone wrong. The game's own factions: zombie is hostile to nearly everyone, iconoclash 1 and 2
-- to each other, saints_hostile fights the gangs and is allied to you. ai_set_faction_node sets the side;
-- ai_make_combatant_node (id, faction, goal set) turns a civilian into a fighter, if their AI data's loaded;
-- ai_create_belief (+ADE550: who, of whom) makes them notice, since nobody reacts to a change of side.
local ZOMBIE, RIOT_A, RIOT_B, ARMY = 0xBA23BB92, 0x5B6567AA, 0xC26C3610, 0xE0FA1670
local function set_side(id, f)
  P.node(0xAE86F0, 0x29FB6D0, { { u = id }, { u = f }, { u = crc_of("combat ped") } })
  P.node(0xADEB50, 0x29E6A58, { { u = id }, { u = f } })
end
local function notice(list)
  for _, a in ipairs(list) do
    local best, bd
    for _, t in ipairs(list) do
      if t.side ~= a.side and t.id ~= a.id then
        local dx, dz = t.x - a.x, t.z - a.z
        local d = dx * dx + dz * dz
        if not bd or d < bd then best, bd = t, d end
      end
    end
    if best then P.node(0xADE550, 0x29EA3F8, { { u = a.id }, { u = best.id } }) end
  end
end
local function sides(radius, pick)
  local list, i = {}, 0
  each_near(radius, function(p)
    i = i + 1
    local id = id_of(p)
    local side = pick(i)
    if side then set_side(id, side) end
    list[#list + 1] = { id = id, side = side or 0, x = s32(wml.read_u32(p.entry + 0x30)), z = s32(wml.read_u32(p.entry + 0x38)) }
  end)
  notice(list)
  return #list
end
function P.zombies_near(radius)
  return sides(radius, function(i) return i % 3 == 1 and ZOMBIE or nil end)
end
function P.riot_near(radius)
  return sides(radius, function(i) return i % 2 == 0 and RIOT_A or RIOT_B end)
end
-- Downed, not dead: human_health_enable_dbno_on_death_node, as you have in the game.
function P.downed_near(radius)
  return each_near(radius, function(p) P.node(0x695350, 0x29C7438, { { u = id_of(p) } }) end)
end
function P.make_army(id)
  P.node(0xAE7BD0, 0x29E8570, { { u = id }, { u = crc_of("homie") } })
  P.node(0xADEB50, 0x29E6A58, { { u = id }, { u = ARMY } })
  local me = P.object()
  if me then P.node(0xAE5720, 0x29DD280, { { u = id }, { u = crc_of("assist player") }, { u = wml.read_u32(me + 0x58) } }) end
end
-- Free for all: each faction's record (+379030(&hash)): +0x3C how it treats anyone not listed, +0x40 its own.
-- 1 is hostile. Read on every check, not saved.
P.free_for_all = false
SR5TM_FFA = SR5TM_FFA or {}
local FFA_SETS = { gangs = { 0xCFD91205, 0xAF91816E, 0xAD77A00A }, all = { 0xCFD91205, 0xAF91816E, 0xAD77A00A, 0x55BEF8FA } }
function P.update_free_for_all()
  local want = {}
  for _, h in ipairs(FFA_SETS[P.free_for_all] or {}) do want[h] = true end
  local b = wml.buffer(13)
  for _, h in ipairs(FFA_SETS.all) do
    wml.write_u32(b, h)
    local rec = wml.call(wml.base + 0x379030, b)
    if rec ~= 0 then
      if want[h] then
        SR5TM_FFA[h] = SR5TM_FFA[h] or { wml.read_u32(rec + 0x3C), wml.read_u32(rec + 0x40) }
        wml.write_u32(rec + 0x3C, 1); wml.write_u32(rec + 0x40, 1)
      elseif SR5TM_FFA[h] then
        wml.write_u32(rec + 0x3C, SR5TM_FFA[h][1]); wml.write_u32(rec + 0x40, SR5TM_FFA[h][2])
        SR5TM_FFA[h] = nil
      end
    end
  end
end
function P.ffa_active() return P.free_for_all or next(SR5TM_FFA) ~= nil end
-- Gang presence: the district's list of who's out on the street, read live: *(+3C438D0) +0x1A70, count
-- +0x1A78, 0x2C each: +0x10 and +0x14 on foot day and night, +0x1C and +0x20 in vehicles. Rebuilt on
-- a change of district, so kept up; originals by address, and only while the list is the same.
P.gang_presence = false
SR5TM_GANGS = SR5TM_GANGS or {}
function P.update_gang_presence()
  local mgr = wml.read_u64(wml.base + 0x3C438D0)
  if mgr == 0 then return end
  local list, n = wml.read_u64(mgr + 0x1A70), wml.read_u16(mgr + 0x1A78)
  if list == 0 or n > 64 then return end
  for i = 0, n - 1 do
    for _, off in ipairs({ 0x10, 0x14, 0x1C, 0x20 }) do
      local a = list + i * 0x2C + off
      local now = wml.read_u32(a)
      if P.gang_presence then
        local o = SR5TM_GANGS[a]
        if not o or now ~= o[2] then o = { now, math.floor(now * P.gang_presence) }; SR5TM_GANGS[a] = o end
        wml.write_u32(a, o[2])
      elseif SR5TM_GANGS[a] then
        if now == SR5TM_GANGS[a][2] then wml.write_u32(a, SR5TM_GANGS[a][1]) end
        SR5TM_GANGS[a] = nil
      end
    end
  end
end
function P.gangs_active() return P.gang_presence or next(SR5TM_GANGS) ~= nil end
-- World tuning. Live config records and globals, each read when it's used, so a write takes at
-- once: originals kept by address for the session. *(+5BE34A8) is damage_system_config: +0x98 AI vs AI
-- damage, +0x60 back shot, +0x78 flinch cooldown, +0x7E your dodge's safe ms, +0x9C damage to yourself.
-- *(+5BE7EC8) ambient config: +0x4C and +0x54 people and cars in bad weather. +2E7FB7C how far off
-- traffic spawns (rewritten on a change of district, so kept up).
local TUNES = {
  fight_damage = { { ptr = 0x5BE34A8, off = 0x98 } }, back_stab = { { ptr = 0x5BE34A8, off = 0x60 } },
  no_flinch = { { ptr = 0x5BE34A8, off = 0x78 } }, dodge_ms = { { ptr = 0x5BE34A8, off = 0x7E, u16 = true } },
  own_blast = { { ptr = 0x5BE34A8, off = 0x9C } }, rain_crowd = { { ptr = 0x5BE7EC8, off = 0x4C }, { ptr = 0x5BE7EC8, off = 0x54 } },
  traffic_far = { { addr = 0x2E7FB7C } }, peds_far = { { addr = 0x2E7FB08 } },
  -- +0x54 how long you stay down (s), +0x56 how long a revive takes (ms), +0x68 and +0x6C the guardian angel's cooldown and safe time (ms)
  -- +0x94: the health share below which you walk hurt
  always_wounded = { { ptr = 0x5BE34A8, off = 0x94 } },
  downed_timer = { { ptr = 0x5BE34A8, off = 0x54, u16 = true } }, instant_revive = { { ptr = 0x5BE34A8, off = 0x56, u16 = true, set = 1 } },
  guardian_angel = { { ptr = 0x5BE34A8, off = 0x68, i32 = true, set = 1000 }, { ptr = 0x5BE34A8, off = 0x6C, i32 = true, set = 3000 } },
  -- *(+4BA0DB8) roadblocks: +0x58 most at once, +0x5C metres apart. *(+4BA2228 + level * 8) notoriety_level:
  -- +0x3C points to reach it, +0x70 seconds between roadblocks, +0x74 pursuit cars, +0x80 the radius to get out of.
  roadblock_mania = { { ptr = 0x4BA0DB8, off = 0x58, i32 = true, set = 20 }, { ptr = 0x4BA0DB8, off = 0x5C, set = 20.0 }, { ptr = 0x4BA2228 + 1 * 8, off = 0x70, i32 = true, set = 5 }, { ptr = 0x4BA2228 + 2 * 8, off = 0x70, i32 = true, set = 5 }, { ptr = 0x4BA2228 + 3 * 8, off = 0x70, i32 = true, set = 5 }, { ptr = 0x4BA2228 + 4 * 8, off = 0x70, i32 = true, set = 5 }, { ptr = 0x4BA2228 + 5 * 8, off = 0x70, i32 = true, set = 5 } },
  pursuit_cars = { { ptr = 0x4BA2228 + 1 * 8, off = 0x74, i32 = true }, { ptr = 0x4BA2228 + 2 * 8, off = 0x74, i32 = true }, { ptr = 0x4BA2228 + 3 * 8, off = 0x74, i32 = true }, { ptr = 0x4BA2228 + 4 * 8, off = 0x74, i32 = true }, { ptr = 0x4BA2228 + 5 * 8, off = 0x74, i32 = true } },
  heat_fast = { { ptr = 0x4BA2228 + 1 * 8, off = 0x3C, i32 = true, set = 10 }, { ptr = 0x4BA2228 + 2 * 8, off = 0x3C, i32 = true, set = 22 }, { ptr = 0x4BA2228 + 3 * 8, off = 0x3C, i32 = true, set = 40 }, { ptr = 0x4BA2228 + 4 * 8, off = 0x3C, i32 = true, set = 62 }, { ptr = 0x4BA2228 + 5 * 8, off = 0x3C, i32 = true, set = 100 } },
  escape_radius = { { ptr = 0x4BA2228 + 1 * 8, off = 0x80, i32 = true }, { ptr = 0x4BA2228 + 2 * 8, off = 0x80, i32 = true }, { ptr = 0x4BA2228 + 3 * 8, off = 0x80, i32 = true }, { ptr = 0x4BA2228 + 4 * 8, off = 0x80, i32 = true }, { ptr = 0x4BA2228 + 5 * 8, off = 0x80, i32 = true } },
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
        local read = t.u16 and wml.read_u16 or t.i32 and wml.read_u32 or wml.read_f32
        local write = t.u16 and wml.write_u16 or t.i32 and wml.write_u32 or wml.write_f32
        if P[key] then
          if SR5TM_ORIG[a] == nil then SR5TM_ORIG[a] = read(a) end
          write(a, t.set or P[key])
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
  local list = { { "combative_peds", 0xAE21A0, 0x29EB1F8, 0xAE21E0, 0x29DB5F0 }, { "ai_combat", 0xAE9C60, 0x29E8AB0, 0xAE9C80, 0x29EB238 },
    { "always_execute", 0x69E930, 0x29ACBA0, 0x69E970, 0x29A6AF0 }, { "notoriety_uncapped", 0x706520, 0x29CDAD0, 0x706560, 0x2990690 },
    { "no_boundary", 0x9C2DD0, 0x29DBBA0, 0x9C2D90, 0x29EBF80 }, { "quiet_streets", 0x1866900, 0x2AC4950, 0x1866940, 0x2AD3C00 }, { "quiet_homies", 0xA9C870, 0x2A009C0, 0xA9C8A0, 0x29E3BE0 },
    { "no_ramming", 0xAE7560, 0x29DA7B0, 0xAE7590, 0x29EAC58 }, { "no_trains", 0x404B80, 0x2969238, 0x404B10, 0x29712A8 }, { "weather_indoors", 0x193E580, 0x2AC3A68, 0x193E5A0, 0x2ABB408 },
    { "no_takedowns", 0x69E850, 0x2987AF8, 0x69E880, 0x29983F0 }, { "dustlander_takedowns", 0x69E9B0, 0x29D73C0, 0x69E9F0, 0x29A6258 } }
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
-- Slow motion on a held button: the game speed float while LB and RB (or Alt) are held, menu closed.
P.slow_button = false
local slow_held
function P.update_slow_button(menu_open)
  local b = wml.pad() or 0
  local held = P.slow_button and not menu_open and ((b & 0x300) == 0x300 or wml.key_down("ALT"))
  if held then
    wml.write_f32(wml.base + 0x2E80BC4, P.slow_button)
  elseif slow_held then
    wml.write_f32(wml.base + 0x2E80BC4, P.game_speed or 1.0)
  end
  slow_held = held
end
function P.slow_active() return P.slow_button or slow_held end
-- Scaled from the game's tables, read when first used: how far an event scares people (ai_stimulus_type)
-- and how hard a knock has to be to ragdoll you (human_collision_system_config, 30 in the table).
P.panic, P.ragdoll_easy = false, false
SR5TM_SCALED = SR5TM_SCALED or {}
local SCALED = {
  panic = { "ai_stimulus_type", { { path = "m_radius", what = "radius" }, { path = "m_overlap_radius", what = "radius" } } },
  ragdoll_easy = { "human_collision_system_config", { { path = "m_object_config.m_impact_ragdoll_min_momentum", what = "ragdoll" } } },
}
local scaled_was = {}
function P.update_scaled()
  local V = require("vdata")
  for key, spec in pairs(SCALED) do
    if (P[key] or false) ~= (scaled_was[key] or false) then
      SR5TM_SCALED[key] = SR5TM_SCALED[key] or V.collect(spec[1], spec[2])
      for _, e in ipairs(SR5TM_SCALED[key]) do V.write(e.addr, e.t, e.orig * (P[key] or 1)) end
      scaled_was[key] = P[key]
    end
  end
end
-- No parked cars: ambient_spawner_disable_node and enable, by the spawner's name.
P.no_parked = false
local parked_was
function P.update_parked()
  if (P.no_parked or false) == (parked_was or false) then return end
  local h = crc_of("parked_car_spawner")
  if P.no_parked then P.node(0x1A8F110, 0x2AFAB78, { { u = h } }) else P.node(0x1A8F0A0, 0x2AF7218, { { u = h } }) end
  parked_was = P.no_parked
end
-- For the crash log: once a second, a line when something that matters has changed. A crash logs where it
-- died, not what you were doing.
local state_was
function P.log_state()
  local _, slot = wml.game("return player_local_inventory_get_active_slot()")
  local _, inf = wml.game("return tostring(player_local_inventory_get_item_info(player_local_inventory_get_active_slot()))")
  local e = P.object()
  local g = e and wml.call(wml.base + 0x1534D80, e)
  local x, y, z = P.position()
  local line = string.format("hand %s %s | state %X | in car %s | rockets %s punches %s ammo %s | spawned %d cars %d props %d", tostring(slot), tostring(inf):match('"(.-)"') or "none",
    g and g ~= 0 and wml.read_u32(g + 0x324) or 0, tostring(P.vehicle_object() ~= nil), tostring(P.rockets and true or false), tostring(P.explosive_melee and true or false),
    P.ammo and P.ammo[1] or "off", #P.spawned, #P.spawned_cars, #P.props)
  if line ~= state_was then
    wml.log(string.format("state: %s | at %.0f %.0f %.0f", line, x or 0, y or 0, z or 0))
    state_was = line
  end
end
-- Takedown meter: finisher_replenish_meter (+69ECF0) takes one cooldown off, once.
function P.takedown_ready()
  local e = P.object()
  if not e then return "Not now" end
  P.node(0x69ECF0, 0x298F9F8, { { u = wml.read_u32(e + 0x58) } })
  return "Takedown ready"
end
function P.hermit_juice()
  P.node(0x71B0E0, 0x29D05F8, {})
  return "Down the hatch"
end
-- Side jobs by name: +69BCA0 is the game's own check, +69B8E0 the start (one at a time, solo).
function P.start_diversion(name)
  local b = wml.buffer(13)
  wml.write_u32(b, crc_of(name))
  if wml.call(wml.base + 0x69BCA0, b) & 0xFF == 0 then return "The game says not now" end
  P.node(0x69CA10, 0x29C5518, { { u = crc_of(name) } })
  return "Started " .. name
end
-- The radio component in your car (+B5F350, +5112C0): +3857B0 next, +385870 previous; byte +8 is a mission's lock.
local function radio_comp()
  local o = wml.call(wml.base + 0xB5F350, 0, 1, 0)
  return o ~= 0 and wml.call(wml.base + 0x5112C0, o) or 0
end
function P.radio_step(dir)
  local c = radio_comp()
  if c == 0 then return "Get in a vehicle first" end
  wml.write_u8(c + 8, 0)
  wml.call(wml.base + (dir > 0 and 0x3857B0 or 0x385870), c)
  return dir > 0 and "Next station" or "Previous station"
end
P.spawn_loadout = false
-- Any order the game has (ai_combat_orders_config), on everyone near, with you as its target.
function P.order_near(name)
  local h, me = crc_of(name), P.object()
  if not me then return "Not now" end
  local mine = wml.read_u32(me + 0x58)
  local n = 0
  for _, p in ipairs(P.people_near(40)) do
    if p.entry ~= me then
      P.node(0xAE5720, 0x29DD280, { { u = wml.read_u32(p.entry + 0x58) }, { u = h }, { u = mine } })
      n = n + 1
    end
  end
  return n == 0 and "Nobody near" or (n .. (n == 1 and " person: " or " people: ") .. name)
end
-- A mood on anyone (gail_add_mood +1920D30: object, mood, priority, length); "none" clears (+1920B30).
function P.mood_near(name)
  local h, n = crc_of(name), 0
  for _, p in ipairs(P.people_near(40)) do
    local id = wml.read_u32(p.entry + 0x58)
    if name == "none" then P.node(0x1920B30, 0x2AC3E70, { { u = id } })
    else P.node(0x1920D30, 0x2ABA420, { { u = id }, { u = h }, { u = 100 }, { u = 30 }, { u = 0 } }) end
    n = n + 1
  end
  return n == 0 and "Nobody near" or (n .. (n == 1 and " person: " or " people: ") .. name)
end
-- Radios in the cars around you: +5112C0 finds one, +385930 tunes it, +3853E0 plays it, +3855E0 stops it.
function P.radios_near(name)
  local B, n, b = wml.base, 0, wml.buffer(13)
  wml.write_u32(b, crc_of(name))
  for _, v in ipairs(P.vehicles_near(40)) do
    local c = wml.call(B + 0x5112C0, v.entry)
    if c ~= 0 then
      if name == "off" then wml.call(B + 0x3855E0, c) else wml.call(B + 0x385930, c, b, 1); wml.call(B + 0x3853E0, c) end
      n = n + 1
    end
  end
  return n == 0 and "No radios near" or (n .. (n == 1 and " radio: " or " radios: ") .. name)
end
-- A follower of any enemy_info, through the game's call-in (+2CDE50: leader, position in world ints, arrival slot, name hash).
local follower_slot = 0
function P.call_follower(name)
  local B, e = wml.base, P.object()
  if not e then return "Not now" end
  local b = wml.buffer(13)
  wml.write_u32(b, (wml.read_u32(e + 0x30) + 30000) & 0xFFFFFFFF)
  wml.write_u32(b + 4, wml.read_u32(e + 0x34))
  wml.write_u32(b + 8, wml.read_u32(e + 0x38))
  wml.write_u32(b + 0x20, crc_of(name))
  local ok = wml.call(B + 0x2CDE50, e, b, follower_slot, b + 0x20) & 0xFF
  follower_slot = (follower_slot + 1) % 4
  return ok == 1 and "On the way" or "The game refused: at most 4 at once"
end
function P.grenade_takedown()
  P.node(0x69EA20, 0x29C6AC8, {})
  return "Pineapple Express"
end
-- Immune to a status effect (status_effect_set_effect_immunity +76B590: component 0x7B, effect, byte). Lost on a respawn.
P.immune = {}
function P.toggle_immune(name)
  local e = P.object()
  if not e then return nil end
  local cid, oid = comp_ref(0x7B, e)
  if not cid then return nil end
  local on = not P.immune[name]
  P.node(0x76B590, 0x29CB338, { { c = cid, o = oid }, { u = crc_of(name) }, { u = on and 1 or 0 } })
  P.immune[name] = on or nil
  return on
end
-- Crusher: the wheeled component's crush mode +0x2320 (1 crusher), the rebuild flag +0x232B, and +1BC2980 to
-- register the body with the crusher list. No matching unregister was found, so off restores the mode only.
P.crusher = false
local function update_crusher()
  local v = P.vehicle_object()
  local c = v and P.component(0x12, v)
  local h = v and P.component(0x44, v)
  if not c or not h then return end
  local X = SR5TM_EXTRA
  X.crush = X.crush or {}
  if P.crusher and not X.crush[c] then
    X.crush[c] = wml.read_u8(c + 0x2320) + 1
    wml.write_u8(c + 0x2320, 1)
    wml.write_u8(c + 0x232B, wml.read_u8(c + 0x232B) | 0x10)
    wml.call(wml.base + 0x1BC2980, h + 0xA0, wml.read_u32(h + 0xB8))
  elseif not P.crusher and X.crush[c] then
    wml.write_u8(c + 0x2320, X.crush[c] - 1)
    wml.write_u8(c + 0x232B, wml.read_u8(c + 0x232B) | 0x10)
    X.crush[c] = nil
  end
end
-- Any gun in any wheel slot: +98DAD0(inventory, weapon record, slot, "", &none, 8, 0), which weapon_swap_to_inventory
-- calls with 0xE for "its usual slot". The record is the info's own data: a top-level field's address less its offset.
function P.gun_to_slot(name, slot)
  local B, e = wml.base, P.object()
  if not e then return "Not now" end
  local V = require("vdata")
  local ok, ud = wml.game("return vlib_info_object:get_object(" .. string.format("%q", "inventory_weapon_info") .. ", " .. string.format("%q", name) .. ").m_weapon_skin")
  local a = ok and V.field_addr(ud)
  if not a then return "The game doesn't know that gun" end
  local inv = wml.call(B + 0x4BB340, e)
  if inv == 0 then return "Not now" end
  local b = wml.buffer(13)
  wml.write_u32(b, wml.read_u32(B + 0x3C44910))
  wml.write_u8(b + 0x20, 0)
  wml.call(B + 0x98DAD0, inv, a - 0x38, slot, b + 0x20, b, 8, 0)
  return "Given"
end
-- A radio call in anyone's voice: the console's +14B9430 "<persona> <situation> local".
function P.radio_line(persona, situation)
  return P.console(0x14B9430, persona .. " " .. situation .. " local") == 0 and ("Calling: " .. persona) or "The game refused"
end
-- Ride height: the wheeled component's spring lengths, front +0x19C and rear +0x35C, read each update. Originals per car.
P.ride_height = false
local function update_ride()
  local v = P.vehicle_object()
  local c = v and P.component(0x12, v)
  if not c then return end
  local X = SR5TM_EXTRA
  X.ride = X.ride or {}
  local o = X.ride[c]
  if not o and not P.ride_height then return end
  if not o then o = { wml.read_f32(c + 0x19C), wml.read_f32(c + 0x35C) }; X.ride[c] = o end
  wml.write_f32(c + 0x19C, o[1] * (P.ride_height or 1))
  wml.write_f32(c + 0x35C, o[2] * (P.ride_height or 1))
  if not P.ride_height then X.ride[c] = nil end
end
-- The driving camera, component 0x1D's follow parameters: +0x7B2 forces following the car's nose; +0x1580 overrides
-- the field of view multiplier until the clock at +1588 passes (+2E80878, ms).
P.cam_nose, P.car_fov = false, false
local function update_car_cam()
  local X, e = SR5TM_EXTRA, P.object()
  if not e then return end
  local cam = wml.call(wml.base + 0x1FCD10, wml.call(wml.base + 0x1B434C0, e + 0x58))
  if cam == 0 then return end
  if (P.cam_nose or false) ~= (X.cam_nose or false) then
    wml.write_u8(cam + 0x7B2, P.cam_nose and 1 or 0)
    X.cam_nose = P.cam_nose or nil
  end
  if P.car_fov and P.vehicle_object() then
    wml.write_f32(cam + 0x1580, P.car_fov)
    wml.write_u32(cam + 0x1588, wml.read_u32(wml.base + 0x2E80878) + 2000)
  end
end
function P.colour_filter(v) return P.console(0x14D09C0, v) == 0 and ("Filter: " .. v) or "The game refused" end
function P.mosaic(v) return P.console(0x169A2A0, v) == 0 and "Censor: " .. v or "The game refused" end
function P.play_sound(name)
  local ok, err = wml.game("gml_audio_play(" .. string.format("%q", name) .. ")")
  return ok and ("Played " .. name) or tostring(err)
end
-- Everyone near, by node: people get their id and yours, cars their id, yours and wheeled component (0x12).
local NEAR_PEOPLE = {
  swarm = { function(id, me) P.node(0xAE8BC0, 0x29E0BF8, { { u = id }, { u = me } }) end, "crowding you" },
  unswarm = { function(id) P.node(0xAE8DD0, 0x29DDB28, { { u = id } }) end, "told to stop" },
  taunt = { function(id, me) P.node(0xADFE80, 0x2A0BFC0, { { u = id }, { u = me } }) end, "fixed on you" },
  untaunt = { function(id) P.node(0xAE0120, 0x29E1030, { { u = id } }) end, "told to stop" },
  shoot = { function(id, me) P.node(0xADE1A0, 0x29ECBA0, { { u = id }, { u = me }, { v = { 0, 0, 0 } }, { u = 0 }, { f = 5.0 }, { f = 1.0 } }) end, "opening fire" },
  unshoot = { function(id) P.node(0xADE380, 0x29F05E8, { { u = id } }) end, "told to stop" },
  pull_over = { function(id) P.node(0xAE7650, 0x29E2A20, { { u = id } }) end, "told to pull over" },
  weave = { function(id) P.node(0xAD8BE0, 0x29FFF80, { { u = id }, { f = 1.0 } }) end, "told to weave" },
  stay_in = { function(id) P.node(0xAE7230, 0x29DE7C0, { { u = id }, { u = 1 } }) end, "staying in their cars" },
  no_pip = { function(id) P.node(0xAE9DD0, 0x2A17AC0, { { u = id }, { u = 1 } }) end, "off the minimap" },
  pip = { function(id) P.node(0xAE9DD0, 0x2A17AC0, { { u = id }, { u = 0 } }) end, "back on the minimap" },
  unoutline = { function(id) P.node(0xAED8A0, 0x29E0E90, { { u = id } }) end, "cleared" },
  reel = { function(id) P.node(0xAEC480, 0x2A14C50, { { u = id } }) end, "reeling" },
  delete = { function(id) P.node(0x192AB80, 0x2ACDFD0, { { u = id } }) end, "gone" },
}
local NEAR_CARS = {
  stall = { function(id, me, cid, oid) P.node(0x19045D0, 0x2AD4100, { { c = cid, o = oid }, { u = 0 } }) end, "stalled" },
  unstall = { function(id, me, cid, oid) P.node(0x19046B0, 0x2AC8558, { { c = cid, o = oid } }) end, "back to normal" },
  hazards = { function(id) P.node(0xBB51F0, 0x29E1978, { { u = id }, { u = 1 } }) end, "flashing" },
  lock = { function(id) P.node(0x1911EB0, 0x2ACA578, { { u = id } }) end, "locked" },
  unlock = { function(id) P.node(0x1911F00, 0x2ABF3C8, { { u = id } }) end, "unlocked" },
  trunk = { function(id) P.node(0x6BB5F0, 0x29D35F0, { { u = id }, { u = 1 }, { u = 0 } }) end, "popped" },
  crush = { function(id, me) P.node(0xBBA170, 0x29E5500, { { u = id }, { u = me }, { f = 1.0 } }) end, "crushed" },
  tip = { function(id, me, cid, oid) P.node(0x19053E0, 0x2ACD208, { { c = cid, o = oid } }) end, "tipped, if on two wheels" },
  ghost = { function(id, me) P.node(0x1932510, 0x2ABCAB0, { { u = me }, { u = id } }) end, "passable" },
  unghost = { function(id, me) P.node(0x1932550, 0x2AD3EF0, { { u = me }, { u = id } }) end, "solid" },
  jturn = { function(id, me, cid, oid) P.node(0x18FFC60, 0x2AD0348, { { c = cid, o = oid }, { u = 1 } }) end, "J-turning" },
  hairpin = { function(id, me, cid, oid) P.node(0x18FF9B0, 0x2ACE738, { { c = cid, o = oid }, { u = 1 } }) end, "hairpinning" },
  ram = { function(id, me, cid, oid) P.node(0x18FFF10, 0x2AC9A08, { { c = cid, o = oid }, { u = 1 } }) end, "ramming" },
  ramp = { function(id, me, cid, oid) P.node(0x1900160, 0x2AC3608, { { c = cid, o = oid }, { u = 1 } }) end, "in ramp mode" },
  normal = { function(id, me, cid, oid)
    P.node(0x18FFD40, 0x2ABF308, { { c = cid, o = oid } })
    P.node(0x18FFA90, 0x2AC7EE8, { { c = cid, o = oid } })
    P.node(0x18FFFF0, 0x2AC2130, { { c = cid, o = oid } })
    P.node(0x1900160, 0x2AC3608, { { c = cid, o = oid }, { u = 0 } })
  end, "back to normal" },
}
function P.near_act(key)
  local e = P.object()
  if not e then return "Not now" end
  local me, n = wml.read_u32(e + 0x58), 0
  local a = NEAR_PEOPLE[key]
  if a then
    n = each_near(40, function(p) a[1](wml.read_u32(p.entry + 0x58), me) end)
    return n == 0 and "Nobody near" or (n .. (n == 1 and " person " or " people ") .. a[2])
  end
  a = NEAR_CARS[key]
  for _, v in ipairs(P.vehicles_near(40)) do
    local cid, oid = comp_ref(0x12, v.entry)
    if cid then a[1](wml.read_u32(v.entry + 0x58), me, cid, oid); n = n + 1 end
  end
  return n == 0 and "No vehicles near" or (n .. (n == 1 and " vehicle " or " vehicles ") .. a[2])
end
function P.people_speed(v)
  return each_near(40, function(p) P.node(0xADB260, 0x29EAD80, { { u = wml.read_u32(p.entry + 0x58) }, { f = v }, { u = 0 } }) end) .. " people at x" .. v
end
-- Outlines: 1 you, 2 your vehicle, 3 friend, 4 enemy, 5 neutral. They only show with High contrast on.
function P.outline_near(class)
  return each_near(40, function(p) P.node(0xAED780, 0x29E2220, { { u = wml.read_u32(p.entry + 0x58) }, { u = class }, { u = 1 } }) end) .. " outlined; needs High contrast on"
end
-- Skin effects (+19064D0: object, name, seconds, propagate, remove on detach, destroy, out handle, which must start
-- as 0xFFFF). The handle comes back in the 7th slot; +1906740 ends one.
P.skin_handles = {}
local function skin_on(id, name)
  P.node(0x19064D0, 0x2AC36C8, { { u = id }, { p = wml.buffer(5, name) }, { f = -1.0 }, { u = 1 }, { u = 1 }, { u = 0 }, { u = 0xFFFF } })
  P.skin_handles[#P.skin_handles + 1] = wml.read_u32(wml.buffer(0) + 0x4C0)
end
function P.skin_me(name)
  local e = P.object()
  if not e then return "Not now" end
  skin_on(wml.read_u32(e + 0x58), name)
  return "On you: " .. name
end
function P.skin_near(name)
  return each_near(40, function(p) skin_on(wml.read_u32(p.entry + 0x58), name) end) .. " people: " .. name
end
function P.skins_off()
  local n = #P.skin_handles
  for _, h in ipairs(P.skin_handles) do P.node(0x1906740, 0x2ACD100, { { u = h } }) end
  P.skin_handles = {}
  return n .. " effects ended"
end
-- The junction you're at: 1 red, 2 green, 3 yellow until it's reset from the same spot.
function P.traffic_light(state)
  local e = P.object()
  if not e then return "Not now" end
  local me = wml.read_u32(e + 0x58)
  if state == 0 then P.node(0x1939A30, 0x2ACA5B8, { { u = me } }) else P.node(0x19397B0, 0x2ACE570, { { u = me }, { u = state } }) end
  return "Sent to the nearest junction, if there is one"
end
function P.takedown_nearest(style)
  local e = P.object()
  if not e then return "Not now" end
  local me = wml.read_u32(e + 0x58)
  local done
  each_near(10, function(p)
    if not done then
      P.node(0x69E4C0, 0x29C3780, { { u = me }, { u = wml.read_u32(p.entry + 0x58) }, { u = style }, { f = 500.0 }, { u = 1 } })
      done = true
    end
  end)
  return done and "Takedown" or "Nobody within 10 m"
end
function P.wing_bounce()
  local e = P.object()
  if not e then return "Not now" end
  P.node(0x5BA1F0, 0x298BE10, { { u = wml.read_u32(e + 0x58) } })
  return "Kicked"
end
function P.level_up()
  P.node(0xA90920, 0x29E2440, {})
  return "A level up"
end
function P.back_on_road()
  local v = P.vehicle_object()
  if not v then return "Get in a vehicle first" end
  P.node(0xAE2760, 0x29DF460, { { u = wml.read_u32(v + 0x58) }, { u = 0 } })
  return "Back on the road"
end
function P.delete_nearest_car()
  local c = P.nearest_car(30)
  if not c or c == P.vehicle_object() then return "No vehicle within 30 m" end
  P.node(0x192AB80, 0x2ACDFD0, { { u = wml.read_u32(c + 0x58) } })
  return "Gone"
end
function P.glide_to_car()
  local c = P.nearest_car(200)
  if not c then return "No vehicle within 200 m" end
  P.node(0x9BFB10, 0x29E77E0, { { u = wml.read_u32(c + 0x58) }, { f = 5.0 } })
  return "Gliding"
end
function P.random_face()
  P.look_first()
  local ok, err = wml.game([[local c = gml_get_local_player():get_component_by_type("gml_component_character_customization")
    for _, g in vlib_info_object:ipairs("char_cust_facial_morph_group") do
      gml_customization_apply_bidirectional_ambisymmetric_weight(c, g, true, true, rand_int(-100, 100))
    end]])
  return ok and "A new face" or tostring(err)
end
-- Radio on foot: you become one of the station's listeners. +3846C0 and +3848D0 each drop a reference on your id, so
-- one's taken first. Comes off when you get in a vehicle, or the two radios could fight.
local foot_station
local function foot_listener(fn, name)
  local B, e = wml.base, wml.call(wml.base + 0x1B432F0, 0)
  if e == 0 then return false end
  local h, id, refs = wml.buffer(13), wml.read_u32(e + 0x58), wml.read_u64(B + 0x2EB2330)
  wml.write_u32(refs + id * 4, wml.read_u32(refs + id * 4) + 1)
  wml.write_u32(h, id)
  wml.write_u32(h + 8, crc_of(name))
  if fn == 0x3846C0 then wml.call(B + fn, h, h + 8, 1) else wml.call(B + fn, h, h + 8) end
  return true
end
function P.radio_foot(name)
  if P.vehicle_object() then return "Get out of the vehicle first" end
  if foot_station then foot_listener(0x3848D0, foot_station); foot_station = nil end
  if name == "off" then return "Radio off" end
  if not foot_listener(0x3846C0, name) then return "Not now" end
  foot_station = name
  return "On foot: " .. name
end
-- Whole-scene material by the console (+14FD5E0). Must already be streamed: the game checks by name.
function P.world_material(name)
  return P.console(0x14FD5E0, name ~= "off" and name or nil) == 0 and ("Material: " .. name) or "The game refused"
end
-- Zone sets directly, since their nodes keep a listener: +3A8500(&hash, 0, 1), 0 when done, 1 while loading; +3A8D50 off.
function P.load_zone(name)
  local b = wml.buffer(13)
  wml.write_u32(b, crc_of(name))
  local r = wml.call(wml.base + 0x3A8500, b, 0, 1) & 0xFF
  return r == 0 and ("Loaded " .. name) or ("Loading " .. name)
end
function P.unload_zone(name)
  local b = wml.buffer(13)
  wml.write_u32(b, crc_of(name))
  wml.call(wml.base + 0x3A8D50, b, 0, 0)
  return "Unloaded " .. name
end
-- Wind: human movement's push (component 0x10), wanted every frame, along where you face.
P.wind = false
function P.update_wind()
  local e = P.object()
  local cid, oid
  if e then cid, oid = comp_ref(0x10, e) end
  if not cid then return end
  P.node(0x18F7C00, 0x2AD2678, { { c = cid, o = oid }, { v = { wml.read_f32(e + 0x20) * P.wind, 0, wml.read_f32(e + 0x28) * P.wind } } })
end
-- Long legs: rig bones (0x40 each: name pointer +0, offset +0x14), scaled. Likely shared with anyone on the same skeleton,
-- and the game re-adds proportions over it when they change.
P.long_legs = false
local LEG_BONES = { LeftLeg = true, LeftFoot = true, RightLeg = true, RightFoot = true }
local function update_legs()
  local X, e = SR5TM_EXTRA, P.object()
  if not e or (P.long_legs or false) == (X.long_legs or false) then return end
  local a = wml.read_u64(e + 0xF8)
  if a == 0 then return end
  local id = wml.read_u32(a + 0x20)
  local rec = wml.read_u64(wml.base + 0x3E297A0) + id * 0x2B0
  if wml.read_u32(rec + 0xC0) ~= id then return end
  local rig = wml.read_u64(rec + 0x38)
  local bones, n = wml.read_u64(rig + 0x60), wml.read_u32(rig + 0x44)
  X.leg_orig = X.leg_orig or {}
  for i = 0, math.min(n, 400) - 1 do
    local b = bones + i * 0x40
    local np = wml.read_u64(b)
    if np ~= 0 and LEG_BONES[wml.read_string(np)] then
      X.leg_orig[b] = X.leg_orig[b] or { wml.read_f32(b + 0x14), wml.read_f32(b + 0x18), wml.read_f32(b + 0x1C) }
      for j = 1, 3 do wml.write_f32(b + 0x10 + j * 4, X.leg_orig[b][j] * (P.long_legs or 1)) end
    end
  end
  X.long_legs = P.long_legs or nil
end
-- Your own on and off switches, kept per value.
P.swim_land, P.crouch_always, P.no_shove, P.short_takedowns, P.hide_gun, P.time_stop, P.tire_marks, P.twitchy, P.callin_speed, P.chase_speed, P.satchels, P.no_autosave, P.city_noise, P.aim_blur, P.ammo_drops = false, false, false, false, false, false, false, false, false, false, false, false, false, false, false
local function update_extras2(e)
  local X = SR5TM_EXTRA
  update_legs()
  if foot_station and P.vehicle_object() then foot_listener(0x3848D0, foot_station); foot_station = nil end
  if e then
    local me = wml.read_u32(e + 0x58)
    if (P.swim_land or false) ~= (X.swim_land or false) or P.swim_land then
      local cid, oid = comp_ref(0x10, e)
      if cid then P.node(0x18F8B00, 0x2AD2D50, { { c = cid, o = oid }, { u = P.swim_land and 1 or 0 } }) end
      X.swim_land = P.swim_land or nil
    end
    if (P.crouch_always or false) ~= (X.crouch_always or false) or P.crouch_always then
      local cid, oid = comp_ref(0x10, e)
      if cid then P.node(0x18F8BD0, 0x2AD0550, { { c = cid, o = oid }, { u = P.crouch_always and 1 or 0 } }) end
      X.crouch_always = P.crouch_always or nil
    end
    if (P.no_shove or false) ~= (X.no_shove or false) then
      if P.no_shove then P.node(0x9CA4A0, 0x2A17988, { { u = me } }) else P.node(0x9CA460, 0x29ECA70, { { u = me } }) end
      X.no_shove = P.no_shove or nil
    end
    if (P.short_takedowns or false) ~= (X.short_takedowns or false) then
      if P.short_takedowns then P.node(0xAEC290, 0x29D9050, { { u = me } }) else P.node(0xAEC250, 0x29E2B38, { { u = me } }) end
      X.short_takedowns = P.short_takedowns or nil
    end
    if (P.time_stop or false) ~= (X.time_stop or false) then
      if P.time_stop then P.node(0x192DE90, 0x2ACCCC0, { { u = me } }) else P.node(0x192DFA0, 0x2ACAED0, { { u = me } }) end
      X.time_stop = P.time_stop or nil
    end
    if P.hide_gun or X.hidden_gun then
      local ok, s = wml.game("return tostring(gml_get_local_player_weapon())")
      local gun = ok and tonumber((s or ""):match("object (%x+)") or "", 16)
      if gun and gun ~= 0 and (not P.hide_gun or gun ~= X.hidden_gun) then
        if P.hide_gun then P.node(0x97B420, 0x29D9330, { { u = gun } }); X.hidden_gun = gun
        else P.node(0x97B550, 0x29E7DB0, { { u = gun } }); X.hidden_gun = nil end
      end
    end
  end
  local v = P.vehicle_object()
  if v then
    local cid, oid = comp_ref(0x12, v)
    if cid then
      if P.tire_marks or X.tire_marks then
        P.node(0x18FDE50, 0x2ABABF0, { { c = cid, o = oid }, { u = P.tire_marks and 1 or 0 } })
        X.tire_marks = P.tire_marks or nil
      end
      if P.twitchy or X.twitchy then
        P.node(0x18FE700, 0x2AC3C10, { { c = cid, o = oid }, { f = P.twitchy or 0.0 } })
        X.twitchy = P.twitchy or nil
      end
    end
  end
  -- Call-in speed: seconds, min and max, over the level's own when above 0 (faction +0x100, +0x104).
  if (P.callin_speed or false) ~= (X.callin_speed or false) then
    local c = P.callin_speed or { 0.0, 0.0 }
    for _, f in ipairs({ 0x55BEF8FA, 0xAF91816E, 0xAD77A00A, 0xCFD91205 }) do
      P.node(0x706590, 0x2991BA8, { { u = f }, { f = c[1] }, { f = c[2] } })
    end
    X.callin_speed = P.callin_speed or nil
  end
  if (P.chase_speed or false) ~= (X.chase_speed or false) then
    if P.chase_speed then P.node(0xAE75D0, 0x29EC3E8, { { f = P.chase_speed } }) else P.node(0xAE7610, 0x29E8B78, {}) end
    X.chase_speed = P.chase_speed or nil
  end
  if (P.satchels or false) ~= (X.satchels or false) then
    X.satchel_orig = X.satchel_orig or wml.read_u32(wml.base + 0x2E7FC18)
    P.node(0x9A4780, 0x29E3C20, { { u = P.satchels or X.satchel_orig }, { u = 0 } })
    X.satchels = P.satchels or nil
  end
  if (P.no_autosave or false) ~= (X.no_autosave or false) then
    P.node(0xAD8B70, 0x2A17718, { { u = P.no_autosave and 0 or 1 } })
    X.no_autosave = P.no_autosave or nil
  end
  if P.city_noise then wml.game('gml_audio_set_rtpc(nil, "Walla_Peds_Panic_Near", ' .. P.city_noise .. ')') end
end
-- Sky and atmosphere: the time-of-day override store. +1B04900(index, float) and +1B049B0(index, 4 floats) set one,
-- +1B04970 and +1B04A20 clear it; it's merged every frame. A reload drops the store, so what's on is sent again now and then.
local SKY = {
  sky_fog = { 15, 17, 21, 23 },
  sky_haze = { 7 },
  sky_exposure = { 267 },
  sky_godrays = { 56 },
  sky_ambient = { 55 },
  sky_gi = { 282 },
  sky_sun = { 73 },
  sky_moon = { 77 },
  sky_stars = { 257 },
  sky_clouds = { 195, 199, 203 },
  sky_rain = { 140 },
  sky_heat = { 144 },
  sky_wind = { 156 },
  sky_spin = { 309 },
  sky_grain = { 316, 322 },
  sky_vignette = { 324 },
}
local SKY_COL = {
  sky_col_sky = { 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 },
  sky_col_sun = { 3 },
  sky_col_moon = { 4 },
  sky_col_fog = { 21, 22 },
  sky_col_stars = { 23 },
}
P.sky_any = {}
function P.sky_active()
  for k in pairs(SKY) do if P[k] or SR5TM_EXTRA[k] then return true end end
  for k in pairs(SKY_COL) do if P[k] or SR5TM_EXTRA[k] then return true end end
  return next(P.sky_any) ~= nil
end
local function sky_colour(i, c)
  local b = wml.buffer(13)
  for j = 1, 3 do wml.write_f32(b + (j - 1) * 4, c[j]) end
  wml.write_f32(b + 12, 1.0)
  wml.call(wml.base + 0x1B049B0, i, b)
end
function P.update_sky(force)
  local X, B = SR5TM_EXTRA, wml.base
  for k, list in pairs(SKY) do
    if force or P[k] ~= (X[k] or false) then
      for _, i in ipairs(list) do
        if P[k] then wml.callf(B + 0x1B04900, i, P[k] + 0.0) else wml.call(B + 0x1B04970, i) end
      end
      X[k] = P[k] or nil
    end
  end
  for k, list in pairs(SKY_COL) do
    if force or P[k] ~= (X[k] or false) then
      for _, i in ipairs(list) do
        if P[k] then sky_colour(i, P[k]) else wml.call(B + 0x1B04A20, i) end
      end
      X[k] = P[k] or nil
    end
  end
  if force then for i, v in pairs(P.sky_any) do wml.callf(B + 0x1B04900, i, v + 0.0) end end
end
function P.sky_set(i, v)
  if v then wml.callf(wml.base + 0x1B04900, i, v + 0.0) else wml.call(wml.base + 0x1B04970, i) end
  P.sky_any[i] = v or nil
end
function P.sky_clear_any()
  local n = 0
  for i in pairs(P.sky_any) do wml.call(wml.base + 0x1B04970, i); P.sky_any[i] = nil; n = n + 1 end
  return n .. " settings back to the game's"
end
-- The sun by hand: the two time-of-day records' azimuth +0x560 and elevation +0x564, every frame; -1 and -91 mean off.
function P.update_sun()
  local B = wml.base
  for _, g in ipairs({ 0x4AA4170, 0x49189B0 }) do
    local r = wml.read_u64(B + g)
    if r ~= 0 then
      wml.write_f32(r + 0x560, P.sun_height and 180.0 or -1.0)
      wml.write_f32(r + 0x564, P.sun_height or -91.0)
    end
  end
end
-- The gameplay camera's depth of field (f-stop +0x734 and +0x11E4, focus +0x738 and +0x11E8) and picture shift
-- (+0x5D8 x, +0x5DC y), each frame, as its rig may overwrite them. Originals kept.
local function write_keep(cam, off, v)
  local X = SR5TM_EXTRA
  X.cam_orig = X.cam_orig or {}
  if X.cam_orig[off] == nil then X.cam_orig[off] = wml.read_f32(cam + off) end
  wml.write_f32(cam + off, v or X.cam_orig[off])
  if not v then X.cam_orig[off] = nil end
end
function P.update_cam_look()
  local e = P.object()
  if not e then return end
  local cam = wml.call(wml.base + 0x1FCD10, wml.call(wml.base + 0x1B434C0, e + 0x58))
  if cam == 0 then return end
  local X = SR5TM_EXTRA
  if P.dof or X.dof then
    write_keep(cam, 0x734, P.dof); write_keep(cam, 0x11E4, P.dof)
    write_keep(cam, 0x738, P.dof and 3.0); write_keep(cam, 0x11E8, P.dof and 3.0)
    X.dof = P.dof or nil
  end
  if P.shift_view or X.shift_view then
    write_keep(cam, 0x5D8, P.shift_view and P.shift_view[1])
    write_keep(cam, 0x5DC, P.shift_view and P.shift_view[2])
    X.shift_view = P.shift_view or nil
  end
end
function P.cam_look_active() return P.dof or P.shift_view or SR5TM_EXTRA.dof or SR5TM_EXTRA.shift_view end
-- The rest of what's near. +486C10 and +486CE0 are the object property setters Vehicle gravity and No clip use (6
-- gravity factor, 0x10 collision).
function P.gravity_near(v)
  local b, n = wml.buffer(13), 0
  wml.write_f32(b, v)
  for _, list in ipairs({ P.people_near(40), P.vehicles_near(40) }) do
    for _, o in ipairs(list) do
      if o.entry ~= P.object() then wml.call(wml.base + 0x486C10, o.entry, 0, 6, 0, b); n = n + 1 end
    end
  end
  return n .. " things at gravity x" .. v
end
function P.fall_through_near()
  local b, n = wml.buffer(13), 0
  wml.write_u8(b, 0)
  for _, o in ipairs(P.people_near(40)) do
    if o.entry ~= P.object() then wml.call(wml.base + 0x486CE0, o.entry, 0, 0x10, 0, b); n = n + 1 end
  end
  return n .. " people through the ground"
end
-- What the flee-in-vehicle node does, by hand, since the node itself needs a real graph: +335430(ai, order, 2), +34DBA0(ai).
function P.drivers_bolt()
  local B, n = wml.base, 0
  local b = wml.buffer(14)
  for _, p in ipairs(P.people_near(40)) do
    if p.entry ~= P.object() then
      local ai = wml.call(B + 0x48A760, p.entry)
      if ai ~= 0 then
        for i = 0, 0xAC, 4 do wml.write_u32(b + i, 0) end
        wml.write_u32(b, wml.read_u32(B + 0x3BE79F8)); wml.write_u32(b + 4, wml.read_u32(B + 0x3BE6FDC))
        for i = 0, 8, 4 do wml.write_u32(b + 8 + i, wml.read_u32(B + 0x3C44D38 + i)) end
        for i = 0, 0x4C, 4 do wml.write_u32(b + 0x20 + i, wml.read_u32(B + 0x3C44930 + i)) end
        wml.write_u32(b + 0x70, wml.read_u32(B + 0x3BCF8BC))
        wml.write_f32(b + 0x80, -1.0); wml.write_f32(b + 0x84, -1.0); wml.write_f32(b + 0x8C, 30.0)
        wml.write_u32(b + 0x90, 1); wml.write_u8(b + 0x94, 1); wml.write_u32(b + 0x9C, 1); wml.write_u32(b + 0xA4, 8); wml.write_u32(b + 0xA8, 0xFFFFFFFF)
        wml.call(B + 0x335430, ai, b, 2)
        wml.call(B + 0x34DBA0, ai)
        wml.write_u32(ai + 0x150, wml.read_u32(ai + 0x150) | 1)
        n = n + 1
      end
    end
  end
  return n .. " people told to bolt"
end
-- Wheels: the wheel objects under component 0x6A: u32 at +0x1C0 + 0x20*wheel + 0x8C*axle. +AEB350 pops one.
function P.pop_tires(v)
  local c, n = P.component(0x6A, v), 0
  if not c then return 0 end
  for a = 0, 1 do
    for w = 0, 3 do
      local id = wml.read_u32(c + 0x1C0 + 0x20 * w + 0x8C * a)
      if id ~= 0 and P.entry_of(id) then P.node(0xAEB350, 0x29EBE80, { { u = id } }); n = n + 1 end
    end
  end
  return n
end
function P.pop_tires_near()
  local n = 0
  for _, v in ipairs(P.vehicles_near(40)) do n = n + P.pop_tires(v.entry) end
  return n .. " tires popped"
end
-- Freeze in place: a body's motion type (component 6), 0 static, 4 vehicle.
local function motion_near(t)
  local n = 0
  for _, v in ipairs(P.vehicles_near(40)) do
    local cid, oid = comp_ref(6, v.entry)
    if cid then P.node(0x190CAD0, 0x2ABED98, { { c = cid, o = oid }, { u = t } }); n = n + 1 end
  end
  return n
end
function P.freeze_cars_near() return motion_near(0) .. " vehicles frozen" end
function P.unfreeze_cars_near() return motion_near(4) .. " vehicles free" end
-- A scripted launch (+19003B0: seconds, end speed, heading, turn radius, handbrake, marks).
local function launch_start(entry)
  local cid, oid = comp_ref(0x12, entry)
  if cid then P.node(0x19003B0, 0x2ACA060, { { c = cid, o = oid }, { f = 1.0 }, { f = 40.0 }, { f = 0.0 }, { f = 0.0 }, { u = 0 }, { u = 1 } }) end
  return cid ~= nil
end
function P.launch_my_car()
  local v = P.vehicle_object()
  if not v then return "Get in a vehicle first" end
  return launch_start(v) and "Launched" or "Not this vehicle"
end
function P.launch_cars_near()
  local n = 0
  for _, v in ipairs(P.vehicles_near(40)) do if launch_start(v.entry) then n = n + 1 end end
  return n .. " vehicles launched"
end
-- A noise everyone reacts to (+AE93A0: stimulus, target, source). An unknown name does nothing.
function P.fake_noise(name)
  local e = P.object()
  if not e then return "Not now" end
  local me = wml.read_u32(e + 0x58)
  P.node(0xAE93A0, 0x29E2DD8, { { u = crc_of(name) }, { u = me }, { u = me } })
  return "Noise: " .. name
end
-- Attach the nearest car or prop's component 9 to a socket on you (only "surf" is known to exist).
function P.stick_nearest()
  local e, c = P.object(), P.nearest_car(15)
  if not e or not c then return "No vehicle within 15 m" end
  local cid, oid = comp_ref(9, c)
  if not cid then return "That can't attach" end
  P.node(0x18EAF40, 0x2AC2710, { { c = cid, o = oid }, { u = wml.read_u32(e + 0x58) }, { p = wml.buffer(5, "surf") } })
  P.stuck = { cid = cid, oid = oid }
  return "Stuck to you"
end
function P.unstick()
  if not P.stuck then return "Nothing stuck" end
  P.node(0x18EB150, 0x2ABCD60, { { c = P.stuck.cid, o = P.stuck.oid } })
  P.stuck = nil
  return "Let go"
end
-- Homies' outfits: the game's own calls, stepping through their list.
local homie_step = {}
function P.homie_outfit(name)
  homie_step[name] = (homie_step[name] or 0) + 1
  local ok, r = wml.game(string.format([[local m = vlib_info_object:get_object("homie_info", %q)
    local list = homie_get_outfits(m)
    local i = (%d - 1) %% #list + 1
    homie_wear_outfit(m, list[i])
    return i .. " of " .. #list]], name, homie_step[name]))
  return ok and (name .. ": outfit " .. tostring(r)) or tostring(r)
end
-- Spawned people take orders once they're followers: ai_issue_enter_vehicle_orders (+AE6180: person, vehicle,
-- seat and a second int, -1 for any, 8 as the game's default), ai_issue_orders (+AE5720) "go to run" with a
-- position as world ints (metres x 10000).
function P.spawned_to_car()
  local v = P.vehicle_object()
  if not v then return "Get in a vehicle first" end
  local vid = wml.read_u32(v + 0x58)
  for _, id in ipairs(P.spawned) do
    if P.make_follower(id) then P.node(0xAE6180, 0x29DDC80, { { u = id }, { u = vid }, { u = 0xFFFFFFFF }, { u = 0xFFFFFFFF }, { u = 8 } }) end
  end
  return #P.spawned == 0 and "Nobody spawned" or (#P.spawned .. " told to get in")
end
function P.spawned_to_waypoint()
  local x, y, z = P.waypoint()
  if not x then return "No waypoint set" end
  local run, none = crc_of("go to run"), wml.read_u32(wml.base + 0x3C44910)
  local at = { math.floor(x * 10000) & 0xFFFFFFFF, math.floor(y * 10000) & 0xFFFFFFFF, math.floor(z * 10000) & 0xFFFFFFFF }
  for _, id in ipairs(P.spawned) do P.node(0xAE5720, 0x29DD280, { { u = id }, { u = run }, { u = none }, { i = at } }) end
  return #P.spawned == 0 and "Nobody spawned" or (#P.spawned .. " running to the waypoint")
end
-- Pedestrians' cash chance: the first entry of loot_table_info "pedestrian", 25%, read at each kill.
P.peds_pay = false
function P.update_peds_pay()
  local X = SR5TM_EXTRA
  if not X.pay_addr then
    local V = require("vdata")
    local ok, ud, num = wml.game([[for _, e in vlib_info_object:get_object("loot_table_info", "pedestrian").m_loot_entries:ipairs() do return e.m_chance, e.m_chance:get_number() end]])
    local a = ok and V.field_addr(ud)
    if not a or not V.typed(a, num) then return end
    X.pay_addr, X.pay_t, X.pay_orig = a, V.typed(a, num), num
  end
  require("vdata").write(X.pay_addr, X.pay_t, P.peds_pay and 100 or X.pay_orig)
end
-- Downforce: the wheeled component's extra gravity on the ground and in the air, +0x1FFC and +0x2000, and the
-- flag at +0x232B that has it rebuilt. Originals per car.
P.downforce = false
local function update_downforce()
  local v = P.vehicle_object()
  local c = v and P.component(0x12, v)
  if not c then return end
  local X = SR5TM_EXTRA
  X.df = X.df or {}
  local o = X.df[c]
  if not o and not P.downforce then return end
  if not o then o = { wml.read_f32(c + 0x1FFC), wml.read_f32(c + 0x2000) }; X.df[c] = o end
  local want = o[1] * (P.downforce or 1)
  if wml.read_f32(c + 0x1FFC) ~= want then
    wml.write_f32(c + 0x1FFC, want)
    wml.write_f32(c + 0x2000, o[2] * (P.downforce or 1))
    wml.write_u8(c + 0x232B, wml.read_u8(c + 0x232B) | 0x10)
  end
  if not P.downforce then X.df[c] = nil end
end
-- What's kept up once a second. Traffic mood: spawn_profile_add and remove (+B34150, +B341C0), as the traffic cheats do.
P.invisible_me, P.radio_unlock, P.spawned_safe, P.traffic_mood, P.surf_fast, P.long_trains = false, false, false, false, false, false
SR5TM_EXTRA = SR5TM_EXTRA or {}
local function collected(key, class, fields)
  if not SR5TM_EXTRA[key] then SR5TM_EXTRA[key] = require("vdata").collect(class, fields) end
  return SR5TM_EXTRA[key]
end
-- Records read when they're used. Venture income may only reach ventures built later (M); skills only their next copy.
P.venture_income, P.fraud_launch, P.skill_fast, P.surf_safe, P.hover_slam, P.enemies_arrive, P.blackout, P.no_wind = false, false, false, false, false, false, false, false
P.unseen_by_ai, P.flame_me, P.aim_anywhere, P.blacklight, P.tracer_colour, P.notoriety_min, P.notoriety_max, P.radial_blur, P.enemy_sight = false, false, false, false, false, false, false, false, false
local SCALED = {
  { key = "venture_income", class = "real_estate_blueprint", fields = { { path = "m_revenue_info.m_complete", what = "c" }, { path = "m_revenue_info.m_initial", what = "i" }, { path = "m_revenue_info.m_increase_per_threat", what = "t" } } },
  { key = "enemies_arrive", class = "encounter_config", fields = { { path = "m_on_foot_spawn_distance", what = "a" }, { path = "m_on_foot_min_spawn_distance", what = "b" }, { path = "m_vehicle_spawn_distance", what = "c" }, { path = "m_vehicle_min_spawn_distance", what = "d" } } },
  { key = "enemy_sight", class = "ai_view_frustum_types", fields = { { path = "m_non_combat_frustum.m_length", what = "a" }, { path = "m_combat_frustum.m_length", what = "b" }, { path = "m_combat_target_frustum.m_length", what = "c" } } },
  { key = "aim_blur", class = "depth_of_field_info", set = 0.5, fields = { { path = "m_dof_fstop_min", what = "a" }, { path = "m_dof_fstop_max", what = "b" } } },
  { key = "ammo_drops", class = "dropped_ammo_table", only = "default_ammo", fields = { { path = "m_launcher_weight", what = "l" }, { path = "m_special_weight", what = "s" } } },
  { key = "fraud_launch", class = "insurance_fraud_tweakable_values", fields = { { path = "m_ragdoll_impulse_up", what = "up" }, { path = "m_ragdoll_impulse_dir", what = "dir" } } },
  { key = "skill_fast", class = "gml_weapon_info", only = "ability", set = 0.05, fields = { { path = "m_refire_delay", what = "refire" } } },
}
function P.update_extras()
  local X, e = SR5TM_EXTRA, P.object()
  update_extras2(e)
  if P.tire_smoke or X.tire_smoke then
    local v = P.vehicle_object()
    local cid, oid
    if v then cid, oid = comp_ref(0x12, v) end
    if cid then
      P.node(0x18FDF30, 0x2AC26D0, { { c = cid, o = oid }, { u = P.tire_smoke or 0 } })
      X.tire_smoke = P.tire_smoke or nil
    end
  end
  if (P.lamps or false) ~= (X.lamps or false) then
    local b = wml.buffer(13)
    wml.write_u32(b, crc_of("tod_lightfixture_control"))
    wml.call(wml.base + 0x1B05E30, b, P.lamps and 1 or 0)
    X.lamps = P.lamps or nil
  end
  for ctx = 0, 10 do
    local k = "audio_ctx_" .. ctx
    if (P[k] or false) ~= (X[k] or false) then
      if not X[k .. "_was"] then
        local ok, v = wml.game("return option_get_audio_context_volume(" .. ctx .. ")")
        X[k .. "_was"] = ok and v or 1
      end
      wml.game("option_set_audio_context_volume(" .. ctx .. ", " .. (P[k] and (P[k] == "mute" and 0 or P[k]) or X[k .. "_was"]) .. ")")
      X[k] = P[k] or nil
    end
  end
  update_downforce()
  update_crusher()
  if e then
    local me = wml.read_u32(e + 0x58)
    -- ai_set_invisible style node (+AE8180: id, seconds), kept up; +AE8370 clears it
    if P.unseen_by_ai then P.node(0xAE8180, 0x29E89B0, { { u = me }, { f = 3.0 } })
    elseif X.unseen_ai then P.node(0xAE8370, 0x29E29E0, { { u = me } }) end
    X.unseen_ai = P.unseen_by_ai or nil
    if (P.flame_me or false) ~= (X.flame_me or false) then
      if P.flame_me then P.node(0x6AC280, 0x29D5D18, { { u = me }, { u = me } }) else P.node(0x6AC3D0, 0x29D4A10, { { u = me } }) end
      X.flame_me = P.flame_me or nil
    end
    if (P.aim_anywhere or false) ~= (X.aim_anywhere or false) then
      if P.aim_anywhere then P.node(0xAEC530, 0x29F83A8, { { u = me } }) else P.node(0xAEC570, 0x29E59D0, { { u = me } }) end
      X.aim_anywhere = P.aim_anywhere or nil
    end
  end
  -- game_render_shader_constants by name (+19369D0 a float, +1936B50 a colour)
  if (P.blacklight or false) ~= (X.blacklight or false) then
    P.node(0x19369D0, 0x2AC8C80, { { u = crc_of("blacklight_activation") }, { f = P.blacklight and 1.0 or 0.0 } })
    X.blacklight = P.blacklight or nil
  end
  if P.tracer_colour and P.tracer_colour ~= X.tracer_colour then
    local c = P.tracer_colour
    for _, n in ipairs({ "p1_primary_color_tracer", "p1_primary_color_muzzle", "p1_primary_color_exp", "p1_secondary_color_tracer", "p1_secondary_color_muzzle", "p1_secondary_color_exp" }) do
      P.node(0x1936B50, 0x2ABB9E0, { { u = crc_of(n) }, { f = c[1] }, { f = c[2] }, { f = c[3] }, { f = 1.0 } })
    end
    X.tracer_colour = c
  end
  -- Notoriety held: the floor (+705580) and ceiling (+7055D0) by faction: level, faction.
  for _, w in ipairs({ { "notoriety_min", 0x705580, 0x29D1930, 0 }, { "notoriety_max", 0x7055D0, 0x29D7910, 5 } }) do
    if (P[w[1]] or false) ~= (X[w[1]] or false) then
      for _, f in ipairs({ 0x55BEF8FA, 0xAF91816E, 0xAD77A00A, 0xCFD91205 }) do
        P.node(w[2], w[3], { { u = P[w[1]] or w[4] }, { u = f } })
      end
      X[w[1]] = P[w[1]] or nil
    end
  end
  -- Radial blur on the gameplay camera: component 0x1D +0x700, as +18EFEC0 writes it.
  if P.radial_blur or X.radial_blur then
    local cam = e and wml.call(wml.base + 0x1FCD10, wml.call(wml.base + 0x1B434C0, e + 0x58)) or 0
    if cam ~= 0 then wml.write_f32(cam + 0x700, P.radial_blur or 0.0) end
    X.radial_blur = P.radial_blur or nil
  end
  update_ride()
  update_car_cam()
  if (P.blackout or false) ~= (X.blackout or false) then
    wml.game("gml_disable_scene_rendering(" .. tostring(P.blackout or false) .. ")")   -- a counter: once each way
    X.blackout = P.blackout or nil
  end
  if (P.no_wind or false) ~= (X.no_wind or false) and e then
    local cid, oid = comp_ref(4, e)
    if cid then P.node(0x190E660, 0x2ABF408, { { c = cid, o = oid }, { f = P.no_wind and 0.0 or 1.0 } }) end
    X.no_wind = P.no_wind or nil
  end
  for _, s in ipairs(SCALED) do
    if (P[s.key] or false) ~= (X[s.key] or false) then
      for _, f in ipairs(collected(s.key .. "_list", s.class, s.fields)) do
        if not s.only or f.object:find(s.only) then
          require("vdata").write(f.addr, f.t, P[s.key] and (s.set or f.orig * P[s.key]) or f.orig)
        end
      end
      X[s.key] = P[s.key] or nil
    end
  end
  if (P.surf_safe or false) ~= (X.surf_safe or false) and e then
    P.node(0x735570, 0x298C120, { { u = wml.read_u32(e + 0x58) }, { u = P.surf_safe and 1 or 0 } })
    X.surf_safe = P.surf_safe or nil
  end
  if (P.hover_slam or false) ~= (X.hover_slam or false) then
    P.node(0xB6D090, 0x29DE3D8, { { u = P.hover_slam and 1 or 0 } })
    X.hover_slam = P.hover_slam or nil
  end
  if (P.peds_pay or false) ~= (X.pay_was or false) then
    P.update_peds_pay()
    X.pay_was = P.peds_pay or nil
  end
  if e and P.invisible_me then
    P.node(0x193F3D0, 0x2AC10F0, { { u = wml.read_u32(e + 0x58) }, { f = 0.0 }, { f = 0.0 } })
    X.unseen = true
  elseif e and X.unseen then
    P.node(0x193F420, 0x2ACBC38, { { u = wml.read_u32(e + 0x58) } })
    X.unseen = nil
  end
  if P.radio_unlock then
    local c = radio_comp()
    if c ~= 0 then wml.write_u8(c + 8, 0) end
  end
  if P.spawned_safe then
    for _, id in ipairs(P.spawned) do P.node(0x697590, 0x29D1E20, { { u = id }, { u = 1 } }) end
  end
  if (P.traffic_mood or false) ~= (X.mood or false) then
    if X.mood then P.node(0xB341C0, 0x29F6DE8, { { u = X.mood } }) end
    if P.traffic_mood then P.node(0xB34150, 0x29D9FA8, { { u = P.traffic_mood } }) end
    X.mood = P.traffic_mood or nil
  end
  if (P.surf_fast or false) ~= (X.surf_was or false) then
    for _, f in ipairs(collected("surf", "wingsuit_info", { { path = "m_contents.m_surf_target_max_mph", what = "mph" }, { path = "m_contents.m_surf_cooldown", what = "cd" } })) do
      require("vdata").write(f.addr, f.t, not P.surf_fast and f.orig or f.what == "mph" and f.orig * P.surf_fast or 0.1)
    end
    X.surf_was = P.surf_fast or nil
  end
  if (P.long_trains or false) ~= (X.trains_was or false) then
    for _, f in ipairs(collected("trains", "train_spawning_config", { { path = "m_min_cars_per_train", what = "min" }, { path = "m_max_cars_per_train", what = "max" } })) do
      require("vdata").write(f.addr, f.t, P.long_trains and f.orig * P.long_trains or f.orig)
    end
    X.trains_was = P.long_trains or nil
  end
end
-- Rare traffic: each active traffic profile's list (+314A958, count +314A950; the list at +0x10E8, count +0x10F0,
-- 0x24 each: +4 variant, +0x10 and +0x14 chance by day and night, +0x18 most at once, +0x20 on the road). Rare
-- ones get a real chance. Originals by address; a district's own list only, so kept up.
P.rare_traffic = false
SR5TM_RARE = SR5TM_RARE or {}
local rare_set
function P.update_rare_traffic(names)
  local B = wml.base
  if P.rare_traffic and not rare_set then
    rare_set = {}
    for _, n in ipairs(names) do rare_set[crc_of(n)] = true end
  end
  if P.rare_traffic then
    for i = 0, math.min(wml.read_u32(B + 0x314A950), 16) - 1 do
      local rec = wml.read_u64(B + 0x314A958 + i * 8)
      if rec ~= 0 then
        local arr, n = wml.read_u64(rec + 0x10E8), wml.read_u16(rec + 0x10F0)
        for j = 0, math.min(n, 400) - 1 do
          local e = arr + j * 0x24
          if rare_set[wml.read_u32(e + 4)] and not SR5TM_RARE[e] then
            SR5TM_RARE[e] = { wml.read_u32(e + 0x10), wml.read_u32(e + 0x14), wml.read_u32(e + 0x18), wml.read_u8(e + 0x20) }
            wml.write_f32(e + 0x10, 1); wml.write_f32(e + 0x14, 1)
            wml.write_u32(e + 0x18, 3); wml.write_u8(e + 0x20, 1)
          end
        end
      end
    end
  else
    for e, o in pairs(SR5TM_RARE) do
      wml.write_u32(e + 0x10, o[1]); wml.write_u32(e + 0x14, o[2]); wml.write_u32(e + 0x18, o[3]); wml.write_u8(e + 0x20, o[4])
      SR5TM_RARE[e] = nil
    end
  end
end
function P.rare_active() return P.rare_traffic or next(SR5TM_RARE) ~= nil end
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
  body_groin = "groin_slider", body_squeezed = "confined_space", body_eye_gap = "eye spacing", body_mouth_wide = "mouth width",
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
  wml.log("spawning prop: " .. name)
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
-- Prototype weapons: no table names their prefabs, and weapon_inventory_set_slot_item_node refuses
-- them for that reason. The console's give command doesn't look: a bare name, a 1-based slot, a loadout.
-- Given bare they were invisible, with no icon and (the miniboss SMG, read live) damage 0. So: load the
-- model first, as props are. Then the slot (inventory +0x30 each: +0 prefab, +8 info, +12 skin), whose
-- info is left empty, gets the info of what it replaced, which gives the wheel an icon and a name.
local PROTO_PATHS = {
  weapon_shotgun_police_full_auto = [[data\sr_city\spawnables\weapons\shotgun\]], weapon_smg_idols_miniboss_hidden = [[data\sr_city\spawnables\weapons\smg\]],
  weapon_melee_idols_subgrunt_knife = [[data\sr_city\spawnables\weapons\melee\]], weapon_panteros_specialist_melee = [[data\sr_city\spawnables\weapons\panteros\]],
  weapon_melee_coyote = [[data\sr_city\spawnables\weapons\melee\]], weapon_frostlander_shield_player = [[data\dlc_exp_02_dusty\spawnables\weapons\frostlander\]],
  weapon_special_sticky_proximity_bomb = [[data\sr_vanguard\spawnables\weapons\special\]], weapon_proximity_mine_small = [[data\sr_vanguard\spawnables\weapons\grenades\]],
}
-- What a slot shows if what it replaced had nothing to show either (an earlier prototype).
local PROTO_HOST = { [1] = "weapon_melee_1hand_nahualli_knife", [3] = "weapon_smg_tac", [5] = "weapon_shotgun_auto", [7] = "inventory_weapon_anvil_gun", [8] = "weapon_temporary_marshall_minigun", [12] = "weapon_grenade_frag" }
local proto_wait
function P.proto_pending() return proto_wait ~= nil end
function P.give_prefab_weapon(name, slot)
  if proto_wait then return false end
  local B, path = wml.base, PROTO_PATHS[name] .. name
  local cid = wml.call(B + 0xE71120, wml.buffer(5, path .. ".cprefab_pc"), PROP_GROUP, 0)
  local hid = wml.call(B + 0xE71120, wml.buffer(5, path .. ".hprefab_pc"), PROP_GROUP, 0)
  if cid == 0 or hid == 0 then return false end
  local inv = wml.call(B + 0x4BB340, P.object())
  local e = wml.read_u64(inv) + slot * 0x30
  proto_wait = { name = name, slot = slot, cid = cid, hid = hid, e = e, a = wml.read_u32(e + 8), b = wml.read_u32(e + 12), ticks = 1800 }
  return true
end
function P.proto_show(e, slot, a, b)
  if a == 0 then a = PROTO_HOST[slot] and crc_of(PROTO_HOST[slot]) or 0 end
  if a ~= 0 then wml.write_u32(e + 8, a); wml.write_u32(e + 12, b) end
end
function P.update_proto()
  local B, w = wml.base, proto_wait
  if w.given then
    w.given = w.given - 1
    if w.given <= 0 then
      P.proto_show(w.e, w.slot, w.a, w.b)
      prop_release[#prop_release + 1] = { cid = w.cid, hid = w.hid, ticks = 600 }
      proto_wait = nil
      return "ready"
    end
    return nil
  end
  local c1, c2 = wml.call(B + 0xE715E0, w.cid) & 0xFFFFFFFF, wml.call(B + 0xE715E0, w.hid) & 0xFFFFFFFF
  w.ticks = w.ticks - 1
  if c1 == 5 or c2 == 5 or w.ticks <= 0 then
    prop_release[#prop_release + 1] = { cid = w.cid, hid = w.hid, ticks = 1 }
    proto_wait = nil
    return "wouldn't load"
  end
  if c1 == 4 and c2 == 4 then
    if P.console(0x989D90, w.name .. " " .. (w.slot + 1) .. " primary") ~= 0 then
      prop_release[#prop_release + 1] = { cid = w.cid, hid = w.hid, ticks = 1 }
      proto_wait = nil
      return "refused"
    end
    w.given = 10
  end
  return nil
end
-- A gun in your hands with no damage of its own at all, as some NPC prefabs have (the keys read
-- 0.0 for damage_avatar and damage): it can't hurt anyone, so it gets a rifle's damage.
local ZERO_AVATAR, ZERO_ALL = 184102078, 2685072847
function P.fix_zero_damage()
  local ok, str = wml.game("return tostring(gml_get_local_player_weapon())")
  local id = ok and tonumber((str or ""):match("object (%x+)") or "", 16)
  if not id or id == 0 then return end
  local buf = wml.buffer(13)
  wml.write_u32(buf, id)
  local entry = wml.call(wml.base + 0x1C1F420, buf)
  local comp = entry ~= 0 and wml.call(wml.base + 0x49F8A0, entry) or 0
  if comp == 0 then return end
  local list, n = wml.read_u64(comp + 0x138), wml.read_u16(comp + 0x140)
  if list == 0 or n > 200 then return end
  local av, all
  for i = 0, n - 1 do
    local p = list + i * 24
    local key = wml.read_u32(p)
    if wml.read_u32(p + 0x10) == 1 then
      if key == ZERO_AVATAR then av = p + 8 elseif key == ZERO_ALL then all = p + 8 end
    end
  end
  if av and wml.read_f32(av) == 0 and (not all or wml.read_f32(all) == 0) then
    wml.write_f32(av, 100.0)
    if all then wml.write_f32(all, 8.0) end
    wml.log("gave a gun with no damage some: " .. str)
  end
end
function P.hq_theme(name)
  if name then
    local b = wml.buffer(13)
    wml.write_u32(b, crc_of(name))
    wml.call(wml.base + 0x6B60C0, b)
  else wml.call(wml.base + 0x6B6E70) end
end
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
-- Cars near: Skidstop (+BB9200: vehicle, steering, evacuate, sync flags), and the status that keeps a driver's foot down.
function P.bail_cars_near(radius)
  local mine, n = P.vehicle_object(), 0
  for _, v in ipairs(objects_near(radius, 0x44)) do
    if v.entry ~= mine and P.component(0x12, v.entry) then
      P.node(0xBB9200, 0x29EB388, { { u = wml.read_u32(v.entry + 0x58) }, { f = 0.0 }, { u = 1 }, { u = 0 } })
      n = n + 1
    end
  end
  return n
end
function P.floor_cars_near(radius)
  local mine, n = P.vehicle_object(), 0
  for _, v in ipairs(objects_near(radius, 0x44)) do
    if v.entry ~= mine and P.component(0x12, v.entry) and P.effect_on(v.entry, "forced_accelerate", 8) then n = n + 1 end
  end
  return n
end
-- Alarms (+BBA5B0), sirens (+BB50F0: vehicle, on; only cars that have one), a spin (+192F410: object, vector, int).
function P.alarm_cars_near(radius)
  local list = P.vehicles_near(radius)
  for _, v in ipairs(list) do P.node(0xBBA5B0, 0x2A0F350, { { u = wml.read_u32(v.entry + 0x58) } }) end
  return #list
end
function P.siren_cars_near(radius)
  local list = P.vehicles_near(radius)
  for _, v in ipairs(list) do P.node(0xBB50F0, 0x29E2E18, { { u = wml.read_u32(v.entry + 0x58) }, { u = 1 } }) end
  return #list
end
function P.spin_cars_near(radius)
  local list = P.vehicles_near(radius)
  for _, v in ipairs(list) do P.node(0x192F410, 0x2ACA0E0, { { u = wml.read_u32(v.entry + 0x58) }, { v = { 0, 30, 0 } }, { u = 0 } }) end
  return #list
end
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
    wml.call(wml.base + 0xE8EA40, srid, p, 7)   -- only records the name; loaded by loaded() below
    prefab_ids[path] = srid
  end
  return prefab_ids[path]
end
-- Firing a model that isn't loaded shuts the game down with no error (three times live). What it
-- takes is a full path and a real load, as props: true once both files read 4, false if one failed, nil while
-- waiting. The references are kept: the gun needs them for as long as it fires these.
local model_refs = {}
local function loaded(path)
  local B = wml.base
  local r = model_refs[path]
  if not r then
    r = { wml.call(B + 0xE71120, wml.buffer(5, path .. ".cprefab_pc"), 0x12, 0), wml.call(B + 0xE71120, wml.buffer(5, path .. ".hprefab_pc"), 0x12, 0) }
    model_refs[path] = r
  end
  if r[1] == 0 or r[2] == 0 then return false end
  local a, b = wml.call(B + 0xE715E0, r[1]) & 0xFFFFFFFF, wml.call(B + 0xE715E0, r[2]) & 0xFFFFFFFF
  if a == 5 or b == 5 then return false end
  if a == 4 and b == 4 then return true end
  return nil
end
-- { key, type (1 float, 3 enum, 0 other), value }: projectile speed, radius, explosion delay, ignore aim assist, and four unnamed.
local ROCKET_KEYS = { { 0x799E7CD4, 1, 120.0 }, { 0x8ABECFF9, 1, 12.75 }, { 0x4A932887, 1, 0.0 }, { 0x624A69F5, 0, 1 },
  { 0x10422728, 3, 1525979922 }, { 0x14A7C15F, 1, 0.0 }, { 0x1CFFB2C2, 1, 4.0 }, { 0x28AAFE06, 1, 0.0 }, { 0x687C2FE7, 0, 1 } }
local rocket_wait, rocket_for = 0, nil
function P.rockets_waiting() return rocket_wait > 0 end
function P.update_rockets()
  local r = P.rockets
  if not r then rocket_gun, rocket_for = nil, nil; return end
  if rocket_for ~= r then
    rocket_for = r
  end
  local a, b = loaded(r[1]), loaded(r[2])
  if a == false or b == false then wml.log("rocket rounds: a model wouldn't load"); P.rockets = false; return end
  if not (a and b) then return end
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
  -- What a launcher has and a gun doesn't, read off the RPG: without these the shot goes off at the muzzle.
  for _, k in ipairs(ROCKET_KEYS) do
    wml.write_u32(buf + 0x10, k[1])
    for i = 0, 15, 4 do wml.write_u32(buf + 0x20 + i, 0) end
    if k[2] == 1 then wml.write_f32(buf + 0x20, k[3]) else wml.write_u32(buf + 0x20, k[3]) end
    wml.write_u32(buf + 0x28, k[2])
    for section = 0, 1 do wml.call(wml.base + 0x1BFF510, comp, buf + 0x10, section, buf + 0x20, name) end
  end
  for key, path in pairs({ shot = r[1], explosion = r[2] }) do
    wml.write_u32(buf + 0x10, crc(key))
    local srid = prefab_id(path .. ".cprefab_pc")
    for section = 0, 1 do wml.call(wml.base + 0x1C001E0, comp, buf + 0x10, section, srid, name) end
  end
  rocket_gun, P.rockets_set = id, r
end

-- Explosive punches: the melee weapon in hand's "explosion" prefab (handle_melee_impact spawns it at the hit),
-- set like the rounds above, once that explosion's loaded.
-- Explosion here: the game's own shape (+B42DA0, +B43470, +3BB5D0), with a really loaded model. Eight metres ahead.
local BOOM = [[data\sr_vanguard\spawnables\weapons\launcher\weapon_launcher_rpg_explosion]]
function P.explosion_here()
  local B, e = wml.base, P.object()
  if not e then return "Not now" end
  local r = loaded(BOOM)
  if r == false then return "The explosion wouldn't load" end
  if not r then return "Loading: press again" end
  local out, x = wml.buffer(14), wml.buffer(13)
  for i = 0, 0x38, 4 do wml.write_u32(x + i, wml.read_u32(e + i)) end
  local function s32(v) return v >= 0x80000000 and v - 0x100000000 or v end
  wml.write_u32(x + 0x30, (s32(wml.read_u32(e + 0x30)) + math.floor(wml.read_f32(e + 0x20) * 80000)) & 0xFFFFFFFF)
  wml.write_u32(x + 0x38, (s32(wml.read_u32(e + 0x38)) + math.floor(wml.read_f32(e + 0x28) * 80000)) & 0xFFFFFFFF)
  for i = 0, 0x400, 8 do wml.write_u64(out + i, 0) end
  wml.call(B + 0xB42DA0, out, prefab_id(BOOM .. ".cprefab_pc"), x, B + 0x3C4117C, B + 0x3C4117C, B + 0x3C44910, 0)
  wml.call(B + 0xB43470, out, 2, 3)
  wml.call(B + 0x3BB5D0, out)
  return "Boom"
end
P.explosive_melee = false
local melee_gun
function P.update_explosive_melee()
  local path = P.explosive_melee
  if not path then melee_gun = nil; return end
  if not loaded(path) then return end
  local ok, s = wml.game("return tostring(gml_get_local_player_weapon())")
  local id = ok and tonumber((s or ""):match("object (%x+)") or "", 16)
  if not id or id == 0 or id == melee_gun then return end
  local buf = wml.buffer(10)
  wml.write_u32(buf, id)
  local entry = wml.call(wml.base + 0x1C1F420, buf)
  local comp = entry ~= 0 and wml.call(wml.base + 0x49F8A0, entry) or 0
  if comp == 0 then return end
  wml.write_u32(buf + 0x10, crc("explosion"))
  local srid = prefab_id(path .. ".cprefab_pc")
  local name = wml.buffer(11, "sr5_tweak_menu")
  -- Every attack section in use: fists have three, and a swing can be any of them.
  for section = 0, 3 do
    if wml.read_u16(comp + section * 0x6A0 + 0x140) > 0 then wml.call(wml.base + 0x1C001E0, comp, buf + 0x10, section, srid, name) end
  end
  melee_gun = id
end

-- Melee lunge. Animations send "correct_melee" (+9B9540): at a target, a dash limited by the weapon's
-- melee_correction_range; at no one, a dash scaled by its range. The name's hash is kept at +3C35470 and
-- only that handler reads it, so with another value there the event's ignored, by everyone.
P.melee_lunge = "none"
local CORRECT_MELEE = 0x19A75A6B
function P.update_melee_lunge()
  local at = wml.base + 0x3C35470
  local now = wml.read_u32(at)
  if now ~= CORRECT_MELEE and now ~= 0 then return end
  local want = P.melee_lunge == "none" and 0 or CORRECT_MELEE
  if now ~= want then wml.write_u32(at, want) end
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
    -- not through P.node: physics_set_gravity_factor_node (+1931450) reads node +8, and a stand-in has none: it
    -- crashed. What it ends in is the same message No clip sends: +486C10(object, 0, 6, 0, &factor).
    local b = wml.buffer(13)
    wml.write_f32(b, P.car_gravity)
    wml.call(wml.base + 0x486C10, v, 0, 6, 0, b)
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
      if h.mode == "guard" then P.make_follower(h.id)
      elseif h.mode == "army" then P.make_army(h.id)
      else P.make_hostile(h.id) end
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
  -- what they carry: a loadout variant's name hash, read by the spawn (+B3A040)
  if P.spawn_loadout then wml.write_u32(ctx + 0x260, crc_of(P.spawn_loadout)) end
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
