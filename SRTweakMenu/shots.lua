-- SR5 Tweak Menu - weapons and shots. A module of its own: player.lua's main chunk is at 189 of Lua's 200 locals, and this adds 21.
local P = require("player")
local held_gun, objects_near, loaded, prop_path, BOOM = P._held_gun, P._objects_near, P._loaded, P._prop_path, P._BOOM
local MIN = 0xE8
local function s32(v) return v >= 0x80000000 and v - 0x100000000 or v end
local function cstr(a, s)
  for i = 1, #s do wml.write_u8(a + i - 1, s:byte(i)) end
  wml.write_u8(a + #s, 0)
end

-- ------------------------------------------------------------------ the camera's aim
-- A point d metres along where the camera looks, in world ints.
local function cam_at(d)
  local B = wml.base
  local f = B + 0x41E1AC0 + 0x20
  local function at(i) return (s32(wml.read_u32(B + 0x41E1AB0 + i)) + math.floor(wml.read_f32(f + i) * d * 10000)) & 0xFFFFFFFF end
  return { at(0), at(4), at(8) }
end
-- What the camera looks at: physics_raycast_node (+1931D90: start, end, ignore, layer, group, fine; outs: object, position,
-- normal, material, region). Layer is a char*, blank means the game's default filter 0x12. The object out takes a reference
-- (+1E3060), given back with +4EA450. With no hit the position slot stays zero. Returns x, y, z (m), normal, object id, or nil.
function P.camera_ray(dist)
  local B, e = wml.base, P.object()
  if not e then return nil end
  P.node(0x1931D90, 0x2AD2238, { { i = cam_at(0.5) }, { i = cam_at(dist or 300) }, { u = wml.read_u32((P.vehicle_object() or e) + 0x58) }, { p = 0 }, { u = 0 }, { u = 1 },
    { u = 0 }, { u = 0 }, { u = 0 }, { u = 0 }, { u = 0 } })
  local s = wml.buffer(0) + 0x400
  local id = wml.read_u32(s + 0xC0)
  if id ~= 0 then wml.call(B + 0x4EA450, s + 0xC0) end
  local x, y, z = wml.read_u32(s + 0xE0), wml.read_u32(s + 0xE4), wml.read_u32(s + 0xE8)
  if x == 0 and y == 0 and z == 0 then return nil end
  return s32(x) / 10000, s32(y) / 10000, s32(z) / 10000, wml.read_f32(s + 0x100), wml.read_f32(s + 0x104), wml.read_f32(s + 0x108), id
end

-- ------------------------------------------------------------------ teleport on shot, portal pair
-- A shot: gun +0x1CE8 went up (fire events, not bullets; a gun whose +0x7B8 is -1 counts once). The landing is the ray's hit,
-- moved off the surface, then P.teleport with no hold: the ray proves the ground there is loaded.
P.shot_teleport = false   -- false, "go", "portal"
local portal = { next = "a", wait = 0 }
local function off_surface(x, y, z, nx, ny, nz)
  return x + nx * 0.6, y + ny * 0.6 + 0.4, z + nz * 0.6
end
local function land(x, y, z)
  P.teleport(x, y, z, true)
  local c = not P.vehicle_object() and P.component(0x10)
  if c then   -- no fall carried over, as the hold does
    for i = 0, 8, 4 do wml.write_f32(c + 0x3A0 + i, 0) end
  end
end
local function shot_teleport_fired()
  local x, y, z, nx, ny, nz = P.camera_ray(300)
  if not x then return end
  x, y, z = off_surface(x, y, z, nx, ny, nz)
  if P.shot_teleport == "go" then land(x, y, z)
  else
    portal[portal.next] = { x, y, z }
    wml.log("portal " .. portal.next .. string.format(" at %.1f %.1f %.1f", x, y, z))
    portal.next = portal.next == "a" and "b" or "a"
    portal.wait = 60
  end
end
-- Walk into one, come out of the other. No model marks them. Armed again once you've left both.
local function portal_step()
  if not (portal.a and portal.b) then return end
  local x, y, z = P.position()
  if not x then return end
  local function near(p) local dx, dy, dz = p[1] - x, p[2] - y, p[3] - z; return dx * dx + dy * dy + dz * dz < 4 end
  if portal.wait > 0 then portal.wait = portal.wait - 1; return end
  if portal.used then
    if not near(portal.a) and not near(portal.b) then portal.used = nil end
    return
  end
  local to = near(portal.a) and portal.b or near(portal.b) and portal.a
  if to then land(to[1], to[2], to[3]); portal.used = true; portal.wait = 30 end
end
function P.portal_clear()
  portal.a, portal.b, portal.next, portal.used = nil, nil, "a", nil
  return "Portals gone"
end

-- ------------------------------------------------------------------ homing rounds
-- Any projectile the player fires (component 0x79, cause at +0x540), steered each frame with physics_set_velocity_node (+192F220),
-- the same physics command (0x2C) as the game's guided missile. Prefabs with a guided missile component (0xBE) also get
-- guided_missile_set_target_node (+3DE880), so if theirs is awake it chases the same thing. Bullets aren't projectiles: no effect.
P.homing = false          -- false or how hard it turns, 0..1 a frame
local hm = { list = {}, scan = 0, wait = 0 }
local function homing_target()
  local B, me = wml.base, P.object()
  local _, _, _, _, _, _, id = P.camera_ray(300)
  local t = id and P.entry_of(id)
  if t and t ~= me and (P.component(0x8D, t) or P.component(0x44, t)) then return id end
  -- nothing under the crosshair: the nearest thing within about 10 degrees of it
  local f = B + 0x41E1AC0 + 0x20
  local fx, fy, fz = wml.read_f32(f), wml.read_f32(f + 4), wml.read_f32(f + 8)
  local cx, cy, cz = s32(wml.read_u32(B + 0x41E1AB0)) / 10000, s32(wml.read_u32(B + 0x41E1AB4)) / 10000, s32(wml.read_u32(B + 0x41E1AB8)) / 10000
  local best, best_d
  for _, ty in ipairs({ 0x8D, 0x44 }) do
    for _, p in ipairs(objects_near(150, ty)) do
      if ty ~= 0x8D or wml.read_u8(p.health + 0x104) == 0 then
        local dx, dy, dz = s32(wml.read_u32(p.entry + 0x30)) / 10000 - cx, s32(wml.read_u32(p.entry + 0x34)) / 10000 - cy, s32(wml.read_u32(p.entry + 0x38)) / 10000 - cz
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        if d > 1 and (dx * fx + dy * fy + dz * fz) / d > 0.985 and (not best_d or d < best_d) then best, best_d = p.entry, d end
      end
    end
  end
  return best and wml.read_u32(best + 0x58) or nil
end
local function homing_fired()
  hm.scan = 30
  if hm.wait <= 0 then hm.target, hm.wait = homing_target(), 20 end
end
local function homing_step()
  local B = wml.base
  local none = wml.read_u32(B + 0x3C44910)
  hm.wait = hm.wait - 1
  if hm.scan > 0 then
    hm.scan = hm.scan - 1
    local me = P.object()
    if me and hm.scan % 5 == 0 and #hm.list < 8 then   -- walks every object: only just after a shot
      local my_id = wml.read_u32(me + 0x58)
      for _, p in ipairs(objects_near(60, 0x79)) do
        local id = wml.read_u32(p.entry + 0x58)
        local known = false
        for _, t in ipairs(hm.list) do if t.id == id then known = true end end
        if not known and wml.read_u32(p.health + 0x540) == my_id then
          hm.list[#hm.list + 1] = { id = id, n = 360 }
          if hm.target and P.component(0xBE, p.entry) then P.node(0x3DE880, 0x2966750, { { u = id }, { u = hm.target } }) end
        end
      end
    end
  end
  local te = hm.target and P.entry_of(hm.target)
  if te and wml.read_u32(te + 0x58) ~= hm.target then te = nil end
  local now, left = wml.read_u32(B + 0x2E80878), {}
  for _, t in ipairs(hm.list) do
    local e = P.entry_of(t.id)
    t.n = t.n - 1
    if e and wml.read_u32(e + 0x58) == t.id and t.n > 0 and te then
      left[#left + 1] = t
      local x, y, z = s32(wml.read_u32(e + 0x30)) / 10000, s32(wml.read_u32(e + 0x34)) / 10000, s32(wml.read_u32(e + 0x38)) / 10000
      if t.x then
        local vx, vy, vz = x - t.x, y - t.y, z - t.z
        local len, dt = math.sqrt(vx * vx + vy * vy + vz * vz), (now - t.at) / 1000
        if len > 0.01 and dt > 0 then
          t.speed = t.speed or math.max(10, len / dt)
          local dx, dy, dz = s32(wml.read_u32(te + 0x30)) / 10000 - x, s32(wml.read_u32(te + 0x34)) / 10000 + 1 - y, s32(wml.read_u32(te + 0x38)) / 10000 - z
          local dl = math.sqrt(dx * dx + dy * dy + dz * dz)
          if dl > 0.5 then
            local k = P.homing
            local ax, ay, az = vx / len * (1 - k) + dx / dl * k, vy / len * (1 - k) + dy / dl * k, vz / len * (1 - k) + dz / dl * k
            local al = math.sqrt(ax * ax + ay * ay + az * az)
            if al > 0.001 then P.node(0x192F220, 0x2AC9F60, { { u = t.id }, { v = { ax / al * t.speed, ay / al * t.speed, az / al * t.speed } }, { u = none } }) end
          end
        end
      end
      t.x, t.y, t.z, t.at = x, y, z, now
    end
  end
  hm.list = left
end

-- ------------------------------------------------------------------ the rows that wait for a shot
local shot_comp, shot_n = nil, 0
P.prop_gun = false        -- a prop name: every shot throws it (Shoot prop below)
function P.shot_rows_on() return P.shot_teleport or P.homing or P.prop_gun or #hm.list > 0 or portal.a or portal.b end
function P.update_shot_rows()
  if P.shot_teleport ~= "portal" and (portal.a or portal.b) then P.portal_clear() end
  local c = held_gun()
  if c then
    local n = wml.read_u32(c + 0x1CE8)
    local fired = c == shot_comp and n > shot_n   -- comps are reused; a new gun counts from nothing
    shot_comp, shot_n = c, n
    if fired then
      if P.shot_teleport then shot_teleport_fired() end
      if P.homing then homing_fired() end
      if P.prop_gun then P.shoot_prop(P.prop_gun) end
    end
  end
  if P.shot_teleport == "portal" then portal_step() end
  if P.homing or #hm.list > 0 then
    if P.homing then homing_step() else hm.list = {} end
  end
end

-- ------------------------------------------------------------------ black hole
-- Everyone and everything near a point, pulled to it for 8 s, then a blast. People: ragdolled once (+1932670) and pushed
-- (+1932980: object, impulse, sync 1), mission people and the dead left out. Vehicles: velocity added (+192F280), so no mass needed.
-- The list is rebuilt once a second (a whole-table walk), pushes go out 10 times a second. Costs frames: at most 10 people, 6 vehicles.
local hole
function P.black_hole(strength)
  if not strength then hole = nil; return "Black hole off" end
  local x, y, z = P.camera_ray(60)
  if not x then
    local at = cam_at(30)
    x, y, z = s32(at[1]) / 10000, s32(at[2]) / 10000, s32(at[3]) / 10000
  end
  loaded(BOOM)   -- so the blast at the end is ready
  hole = { x = x, y = y, z = z, strength = strength, ticks = 480, people = {}, cars = {}, down = {} }
  return "Black hole"
end
function P.hole_on() return hole ~= nil end
local function hole_gather(h)
  local B = wml.base
  local base, n = wml.read_u64(B + 0x45E8458), wml.read_u32(B + 0x4757308)
  local free_bits, live_bits, live_n = wml.read_u64(B + 0x4757300), wml.read_u64(B + 0x4724648), wml.read_u32(B + 0x4724650)
  local me, mine = P.object(), P.vehicle_object()
  h.people, h.cars = {}, {}
  for i = 0, n - 1 do
    if ((wml.read_u8(free_bits + (i >> 3)) >> (i & 7)) & 1) == 0 and (i >= live_n or ((wml.read_u8(live_bits + (i >> 3)) >> (i & 7)) & 1) == 1) then
      local e = base + i * 0x90
      local dx, dy, dz = s32(wml.read_u32(e + 0x30)) / 10000 - h.x, s32(wml.read_u32(e + 0x34)) / 10000 - h.y, s32(wml.read_u32(e + 0x38)) / 10000 - h.z
      if dx * dx + dy * dy + dz * dz < 1600 and e ~= me and e ~= mine and e ~= P.partner_entry and e ~= P.partner_car then
        local p = #h.people < 10 and P.component(0x8D, e)
        if p then
          if wml.read_f32(p + MIN) == 0 and wml.read_u8(p + 0x104) == 0 and P.component(2, e) then h.people[#h.people + 1] = wml.read_u32(e + 0x58) end
        elseif #h.cars < 6 and P.component(0x44, e) then h.cars[#h.cars + 1] = wml.read_u32(e + 0x58) end
      end
    end
  end
end
local function hole_towards(h, id)
  local e = P.entry_of(id)
  if not e or wml.read_u32(e + 0x58) ~= id then return nil end
  local dx, dy, dz = h.x - s32(wml.read_u32(e + 0x30)) / 10000, h.y - s32(wml.read_u32(e + 0x34)) / 10000, h.z - s32(wml.read_u32(e + 0x38)) / 10000
  local d = math.sqrt(dx * dx + dy * dy + dz * dz)
  if d < 3 then return nil end
  return dx / d, dy / d, dz / d
end
function P.update_black_hole()
  local h = hole
  h.ticks = h.ticks - 1
  if h.ticks <= 0 then
    hole = nil
    P.blast_at(math.floor(h.x * 10000), math.floor(h.y * 10000), math.floor(h.z * 10000))
    return
  end
  if h.ticks % 60 == 0 or h.ticks == 479 then hole_gather(h) end
  if h.ticks % 6 ~= 0 then return end
  local none = wml.read_u32(wml.base + 0x3C44910)
  for _, id in ipairs(h.people) do
    local x, y, z = hole_towards(h, id)
    if x then
      local k = 80 * h.strength
      if h.down[id] then P.node(0x1932980, 0x2AC70E0, { { u = id }, { v = { x * k, y * k + 20, z * k } }, { u = 1 } })
      else
        h.down[id] = true
        P.node(0x1932670, 0x2ACB760, { { u = id }, { u = 200 }, { v = { x * k, y * k + 20, z * k } }, { u = 0 }, { u = 1 } })
      end
    end
  end
  for _, id in ipairs(h.cars) do
    local x, y, z = hole_towards(h, id)
    if x then P.node(0x192F280, 0x2ABBA60, { { u = id }, { v = { x * h.strength, y * h.strength + 0.3, z * h.strength } }, { u = none } }) end
  end
end

-- ------------------------------------------------------------------ shoot prop
-- P.spawn_prefab, then physics_set_velocity_node (+192F220) on it once it exists (spawn record +0x70). No cause ids and no +B446E0:
-- that route's refcounts are avoided altogether. A prop with no free body hangs where it spawned; nothing fails.
local flying = {}
function P.shoot_prop(name)
  local path = prop_path(name)
  local r = loaded(path)
  if r == nil then return "Loading: press again" end
  if r == false then return "Couldn't load that" end
  if #flying >= 6 then return "Wait a moment" end
  local e = P.object()
  if not e then return "Not now" end
  local B = wml.base
  local at = cam_at(4)
  local rec = P.spawn_prefab(path .. ".cprefab_pc", (s32(at[2]) - s32(wml.read_u32(e + 0x34))) / 10000, (s32(at[1]) - s32(wml.read_u32(e + 0x30))) / 10000, (s32(at[3]) - s32(wml.read_u32(e + 0x38))) / 10000)
  if not rec then return "The game refused" end
  P.props[#P.props + 1] = rec
  local f, speed = B + 0x41E1AC0 + 0x20, 40
  flying[#flying + 1] = { rec = rec, v = { wml.read_f32(f) * speed, wml.read_f32(f + 4) * speed, wml.read_f32(f + 8) * speed }, ticks = 180, sent = 0 }
  return "Fired"
end
function P.flying_on() return #flying > 0 end
function P.update_flying()
  local left, none = {}, wml.read_u32(wml.base + 0x3C44910)
  for _, t in ipairs(flying) do
    t.ticks = t.ticks - 1
    local id = wml.read_u32(t.rec + 0x70)
    if id ~= 0 and P.entry_of(id) then
      P.node(0x192F220, 0x2AC9F60, { { u = id }, { v = t.v }, { u = none } })
      t.sent = t.sent + 1
    end
    if t.ticks > 0 and t.sent < 4 then left[#left + 1] = t end   -- a few times: the body may not be awake at once
  end
  flying = left
end

-- ------------------------------------------------------------------ dual wield this gun
-- +98B0F0 says yes for a record with +0x64 set whose name hash is one of three kept in globals, the last at +5CCA254, cached
-- once on first use: so ask once first, then write ours over it. +98E720(inv, slot, 1, 0) re-equips the same slot, passes the answer to
-- +1BF5940, which then spawns a second gun. Only one gun at a time. The record and the global go back on the second press.
local dual = {}
local function dual_keys(slot)   -- the second gun needs telling there are two, on rifles and the like
  local B, lo = wml.base, P.component(0xE)
  if not lo then return end
  local buf, name = wml.buffer(10), wml.buffer(11, "sr5_tweak_menu")
  for inst = 0, 1 do
    local c = wml.call(B + 0x1BF2A30, lo, slot, inst)
    if c ~= 0 then
      for _, k in ipairs({ { 0x5D6427FF, 2 }, { 0xDF16B023, 1 } }) do
        wml.write_u32(buf + 0x10, k[1])
        for i = 0, 15, 4 do wml.write_u32(buf + 0x20 + i, 0) end
        wml.write_u32(buf + 0x20, k[2]); wml.write_u32(buf + 0x28, 0)
        for section = 0, 1 do wml.call(B + 0x1BFF510, c, buf + 0x10, section, buf + 0x20, name) end
      end
    end
  end
end
function P.dual_gun()
  local B, e = wml.base, P.object()
  if not e or P.vehicle_object() then return "On foot, with a gun out" end
  local inv = wml.call(B + 0x4BB340, e)
  if inv == 0 then return "Not now" end
  local slot = wml.read_u32(inv + 0x578)
  if slot >= 7 then return "Take out a gun first" end
  local rec = wml.call(B + 0x98FDA0, inv, slot)
  if rec == 0 then return "Take out a gun first" end
  local again = dual.rec == rec
  if dual.rec then
    wml.write_u8(dual.rec + 0x64, dual.flag)
    wml.write_u32(B + 0x5CCA254, dual.global)
    dual.rec = nil
  end
  if again then wml.call(B + 0x98E720, inv, slot, 1, 0); return "One gun again" end
  local flag = wml.read_u8(rec + 0x64)
  wml.write_u8(rec + 0x64, 1)
  wml.call(B + 0x98B0F0, inv, rec)
  local global = wml.read_u32(B + 0x5CCA254)
  wml.write_u32(B + 0x5CCA254, wml.read_u32(rec + 0x34))
  if wml.call(B + 0x98B0F0, inv, rec) & 0xFF == 0 then
    wml.write_u8(rec + 0x64, flag)
    wml.write_u32(B + 0x5CCA254, global)
    return "The game says no right now"
  end
  dual.rec, dual.flag, dual.global, dual.slot, dual.wait = rec, flag, global, slot, 30
  wml.call(B + 0x98E720, inv, slot, 1, 0)
  return "Two of these"
end
function P.dual_waiting() return dual.wait ~= nil end
function P.update_dual()
  dual.wait = dual.wait - 1
  if dual.wait <= 0 then dual.wait = nil; dual_keys(dual.slot) end
end

-- ------------------------------------------------------------------ guns in cars and on roofs
-- The slot masks (+3128850, count u16 +3128858, 0x48 each: +0 mask, +4 who, +0x44 crc of who). Ones pushed by seats and by surfing
-- are taken out as they appear, and the rest stay, so a mission's "no guns" still holds. A later pop finds nothing and does nothing (+99D480). The game then
-- works out its slot flags again (+99CDF0). Off: seats push again the next time you sit down.
P.guns_anywhere = false
local MASK_WHO = { [0xB8B8A30B] = true, [0x749E0FC9] = true }   -- component_vehicle_common, surfing
function P.update_guns_anywhere()
  local B = wml.base
  local n = wml.read_u16(B + 0x3128858)
  if n == 0 then return end
  local list, out = wml.read_u64(B + 0x3128850), 0
  for i = 0, n - 1 do
    local p = list + i * 0x48
    if not MASK_WHO[wml.read_u32(p + 0x44)] then
      if out ~= i then for k = 0, 0x44, 4 do wml.write_u32(list + out * 0x48 + k, wml.read_u32(p + k)) end end
      out = out + 1
    end
  end
  if out ~= n then
    wml.write_u16(B + 0x3128858, out)
    wml.call(B + 0x99CD10)
    wml.call(B + 0x99CDF0)
  end
end

-- ------------------------------------------------------------------ fire from hand or head
-- weapon_fire_from_socket reads muzzle_on_parent and muzzle_parent from the gun's list at each shot. The string is a bare pointer,
-- so it lives in the host's buffer 3 at +0x800, which never moves. Off: the int back to 0.
P.fire_from = false       -- false, "Right_Hand", "Left_Hand", "Head"
local from_gun, from_was
function P.fire_from_active() return P.fire_from or from_was end
function P.update_fire_from()
  local ok, s = wml.game("return tostring(gml_get_local_player_weapon())")
  local id = ok and tonumber((s or ""):match("object (%x+)") or "", 16)
  if not id or id == 0 or (id == from_gun and P.fire_from == from_was) then return end
  local buf = wml.buffer(10)
  wml.write_u32(buf, id)
  local entry = wml.call(wml.base + 0x1C1F420, buf)
  local comp = entry ~= 0 and wml.call(wml.base + 0x49F8A0, entry) or 0
  if comp == 0 then return end
  local text = wml.buffer(3) + 0x800
  if P.fire_from then cstr(text, P.fire_from) end
  local name = wml.buffer(11, "sr5_tweak_menu")
  for section = 0, 1 do
    wml.write_u32(buf + 0x10, 0xE68DBAFD)
    for i = 0, 15, 4 do wml.write_u32(buf + 0x20 + i, 0) end
    wml.write_u32(buf + 0x20, P.fire_from and 1 or 0); wml.write_u32(buf + 0x28, 0)
    wml.call(wml.base + 0x1BFF510, comp, buf + 0x10, section, buf + 0x20, name)
    if P.fire_from then P.node(0x1C066A0, 0x2AFAE18, { { u = id }, { u = section }, { u = 0x735DD73F }, { p = text } }) end
  end
  from_gun, from_was = id, P.fire_from
end

-- ------------------------------------------------------------------ hold like another gun
-- gml_weapon_info +0x5F0 anim group, +0x5F4 combat ready, +0x5F8 camera (reflection; the old note's +0x610 is refire_delay). A gun copies them when it
-- spawns, parent first then its own (+1C0BD98), so the record in hand is overwritten and the gun re-equipped. The gun's info: +4BAC50(comp +0x128).
-- The record is shared: NPCs with this gun change too. Originals kept per record until Game's or a reload of the game.
SR5TM_HOLD = SR5TM_HOLD or {}
function P.hold_like(donor)
  local B, e = wml.base, P.object()
  if not e or P.vehicle_object() then return "On foot, with a gun out" end
  local ok, s = wml.game("return tostring(gml_get_local_player_weapon())")
  local id = ok and tonumber((s or ""):match("object (%x+)") or "", 16)
  if not id or id == 0 then return "Take out a gun first" end
  local buf = wml.buffer(10)
  wml.write_u32(buf, id)
  local entry = wml.call(B + 0x1C1F420, buf)
  local comp = entry ~= 0 and wml.call(B + 0x49F8A0, entry) or 0
  if comp == 0 then return "Take out a gun first" end
  local info = wml.call(B + 0x4BAC50, comp + 0x128)
  if info == 0 then return "This gun has no record" end
  if donor == "game" then
    local o = SR5TM_HOLD[info]
    if not o then return "Already the game's" end
    for i = 0, 2 do wml.write_u32(info + 0x5F0 + i * 4, o[i + 1]) end
    SR5TM_HOLD[info] = nil
  else
    local g, ud = wml.game("return vlib_info_object:get_object(\"gml_weapon_info\", " .. string.format("%q", donor) .. ").m_anim_group_tag")
    local a = g and require("vdata").field_addr(ud)
    if not a then return "The game doesn't know that gun" end
    if wml.read_u32(a) == wml.read_u32(B + 0x5CD1E60) then return "That gun inherits its pose" end
    if not SR5TM_HOLD[info] then SR5TM_HOLD[info] = { wml.read_u32(info + 0x5F0), wml.read_u32(info + 0x5F4), wml.read_u32(info + 0x5F8) } end
    for i = 0, 2 do wml.write_u32(info + 0x5F0 + i * 4, wml.read_u32(a + i * 4)) end
  end
  local inv = wml.call(B + 0x4BB340, e)
  if inv ~= 0 then wml.call(B + 0x98E720, inv, wml.read_u32(inv + 0x578), 1, 0) end
  return "Done"
end

-- ------------------------------------------------------------------ what a saved row can't show
-- Rows pressed with Enter change the game and keep no setting, so What's on and Everything back to normal ask here.
local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
function P.changes_on()
  local X, on = SR5TM_EXTRA, {}
  local n = count(SR5TM_ENGINE)
  if n > 0 then on[#on + 1] = "Game data " .. n end
  if P.scene_pick then on[#on + 1] = "Street scene" end
  if P._squads_x and P._squads_x ~= 1 then on[#on + 1] = "Bigger squads x" .. P._squads_x end
  if next(SR5TM_ELITES or {}) then on[#on + 1] = "Elite enemies early" end
  if next(P.forever or {}) then on[#on + 1] = "Lasting effects" end
  if next(SR5TM_HIDES or {}) then on[#on + 1] = "Clothes hide each other: No" end
  if P._curve_x and P._curve_x ~= 1 then on[#on + 1] = "XP per level x" .. P._curve_x end
  if next(SR5TM_HOLD or {}) then on[#on + 1] = "Hold gun like" end
  if dual.rec then on[#on + 1] = "Dual wield" end
  if hole then on[#on + 1] = "Black hole" end
  if portal.a or portal.b then on[#on + 1] = "Portals" end
  if P.creator_count and P.creator_count() > 0 then on[#on + 1] = "Creator: " .. P.creator_count() .. " objects placed" end
  if P._video_playing then on[#on + 1] = "Video" end
  if next(P.perk_dial or {}) then on[#on + 1] = "Any perk" end
  if next(P.rule_people or {}) then on[#on + 1] = "Rule on people near" end
  if next(P.immune or {}) then on[#on + 1] = "Immune" end
  if next(P.sky_any or {}) then on[#on + 1] = "Any sky" end
  if #(P.skin_handles or {}) > 0 then on[#on + 1] = "Skin effects" end
  if SR5TM_MY_ID then on[#on + 1] = "Playing as someone" end
  if P.stuck then on[#on + 1] = "Stuck car" end
  if P._me_scaled then on[#on + 1] = "Your size" end
  if P.clone_active and P.clone_active() then on[#on + 1] = "Clone of you" end
  return on
end
-- Each is the row's own way back, and each alone in a pcall: one that fails doesn't stop the rest.
function P.back_to_normal()
  local B, X = wml.base, SR5TM_EXTRA
  local function try(f, ...) local ok, err = pcall(f, ...); if not ok then wml.log("back to normal: " .. tostring(err)) end end
  try(P.engine_undo_all)
  if P.creator_stop then try(P.creator_stop); try(P.creator_clear) end
  if P.scene_pick or next(SR5TM_SCENES or {}) then try(P.scene_set, "off") end
  if X.squads then try(P.bigger_squads, 1) end
  if next(SR5TM_ELITES or {}) then try(P.elites_early, false) end
  if next(P.forever or {}) then try(P.forever_off) end
  if next(P.rule_people or {}) then try(P.rule_near, "off") end
  if next(SR5TM_HIDES or {}) then try(P.no_hide_rules, false) end
  if next(SR5TM_LEVELS or {}) then try(P.level_curve, 1) end
  for info, o in pairs(SR5TM_HOLD or {}) do
    for i = 0, 2 do wml.write_u32(info + 0x5F0 + i * 4, o[i + 1]) end
    SR5TM_HOLD[info] = nil
  end
  if dual.rec then
    wml.write_u8(dual.rec + 0x64, dual.flag)
    wml.write_u32(B + 0x5CCA254, dual.global)
    dual.rec, dual.wait = nil, nil
  end
  hole = nil
  try(P.portal_clear)
  if P._video_playing then try(P.video_off) end
  if P._me_scaled then try(P.scale_me, 1) end
  if P.clone_active and P.clone_active() then try(P.clone_remove) end
  try(P.perks_off); try(P.sky_clear_any); try(P.skins_off); try(P.set_prank, nil)
  local immune = {}
  for name in pairs(P.immune or {}) do immune[#immune + 1] = name end
  for _, name in ipairs(immune) do try(P.toggle_immune, name) end
  if SR5TM_MY_ID then try(P.back_to_self) end
  if P.stuck then try(P.unstick) end
  if P._anim_on then try(P.stop_anim) end
  try(P.move_like, "off")
end

return P
