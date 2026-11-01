-- SR5 Tweak Menu - vehicles: parts, paint, guns, seats, physics and flight. A module of its own: player.lua is at Lua's limit of locals.
local P = require("player")
local CUST, prop_release = P._CUST, P._prop_release

-- Parts and paint on the vehicle you're in, by the game's own bindings. +A24D00 hides locked parts, so the slot's own list is read.
local CAR_GET = [[local v = vehicle_get_current()
local c = v:get_component_by_type("gml_component_vehicle_customization")
local o = ""
]]
local CAR_READ = {
  parts = CAR_GET .. [[
local wrap = c.m_vehicle_info:get_info("gml_vehicle_info").m_wrap_handle:get_info("vehicle_cust_wrap_info")
if not wrap:exists() then return "" end
local i = 0
for _, h in wrap.m_vid_entries:ipairs() do
  local s = h:get_info("vehicle_cust_vid_slot")
  if s:exists() then
    o = o .. "G\t" .. i .. "\t" .. tostring(vehicle_get_vid_slot_choice(v, i)) .. "\t" .. tostring(s) .. "\n"
    local n = 0
    for _, e in s.m_choice_entries:ipairs() do
      o = o .. "I\t" .. n .. "\t" .. tostring(e.m_name:get_info("vehicle_cust_vid_slot_option_name")) .. "\n"
      n = n + 1
    end
  end
  i = i + 1
end
return o]],
  paint = CAR_GET .. [[
for i, e in pairs(vehicle_get_materials(c)) do
  for j, p in pairs(e.palettes) do
    o = o .. "G\t" .. (i - 1) .. ":" .. (j - 1) .. "\t" .. tostring(p.selected) .. "\t" .. tostring(e.material) .. " " .. tostring(p.palette) .. "\n"
    for k, ch in pairs(p.choices) do o = o .. "I\t" .. (k - 1) .. "\t" .. tostring(ch) .. "\n" end
  end
end
return o]],
  tex = CAR_GET .. [[
local m, t = vehicle_get_materials(c)
if t == nil then return "" end
for g, e in pairs(t) do
  o = o .. "G\t" .. (g - 1) .. "\t" .. tostring(e.selected) .. "\t" .. tostring(e.texture_group) .. "\n"
  for _, op in pairs(e.options) do o = o .. "I\t" .. op.choice_index .. "\t" .. tostring(op.texset) .. "\n" end
end
return o]],
}
function P.car_read(src)
  if not P.vehicle_object() then return nil, "Get in a vehicle first" end
  local ok, s = wml.game(CAR_READ[src])
  if not ok then return nil, tostring(s) end
  if type(s) ~= "string" or s == "" then return nil, "Nothing to change on this vehicle" end
  local function nice(x) return ((x:match('"(.-)"') or x):gsub("_", " ")) end
  local groups, g, cur = {}, nil, nil
  for line in s:gmatch("[^\n]+") do
    local f = {}
    for part in line:gmatch("[^\t]+") do f[#f + 1] = part end
    if f[1] == "G" then
      g = { nice(f[4] or f[2]), f[2], items = {} }
      cur = f[3]
      groups[#groups + 1] = g
    elseif f[1] == "I" and g then
      g.items[#g.items + 1] = { (f[2] == cur and "* " or "") .. nice(f[3] or f[2]), tonumber(f[2]) }
    end
  end
  for i = #groups, 1, -1 do if #groups[i].items == 0 then table.remove(groups, i) end end
  if #groups == 0 then return nil, "Nothing to change on this vehicle" end
  return groups
end
function P.car_apply(src, key, val)
  if src == "parts" then
    return P._car_lua(string.format("vehicle_set_vid_slot_choice(vehicle_get_current(), %s, %d)", key, val), "Part fitted")
  elseif src == "paint" then
    local a, b = key:match("(%d+):(%d+)")
    return P._car_lua(string.format("vehicle_material_set_palette_choice(%s, %s, %s, %d)", CUST, a, b, val), "Painted")
  end
  return P._car_lua(string.format("vehicle_material_set_texture_choice(%s, %s, %d)", CUST, key, val), "Pattern on")
end
-- Any colour on one material's colour params. R, G, B in 0..1 is a guess (M): if every colour comes out white, use 0..255.
P.car_rgb_mat = 0
function P.car_rgb(col)
  return P._car_lua(string.format([[local c = %s
local e = vehicle_get_materials(c)[%d]
local want = gml_get_enum_value("shader_param_type", "VEHICLE_CUST_COLOR")
if e then for _, p in pairs(e.params) do
  if p.type == want then vehicle_set_param_from_custom_rgb(c, %d, p.param_index, { R = %s, G = %s, B = %s }) end
end end]], CUST, P.car_rgb_mat + 1, P.car_rgb_mat, col[1], col[2], col[3]), "Colour set")
end

-- Vehicle guns: the vehicle's loadout (comp 0xE) and each station's (+0x40, a handle); a slot's items hold the gun's comp 0x5B handle.
function P.car_guns(v)
  local B, seen, out = wml.base, {}, {}
  local function add(owner)
    local lo = owner and owner ~= 0 and owner ~= P.object() and P.component(0xE, owner)
    if not lo or seen[lo] then return end
    seen[lo] = true
    local base = wml.read_u64(lo + 0x10)
    if base == 0 then return end
    for s = 0, 6 do
      local slot = base + s * 0x88
      local list = wml.read_u64(slot + 0x40)
      if list ~= 0 then
        for i = 0, math.min(wml.read_u16(slot + 0x48), 2) - 1 do
          local h = wml.read_u32(list + i * 8 + 4)
          local e = (h & 0xFF) == 0x5B and wml.call(B + 0x1E62F0, h, 0) or 0
          local c = e ~= 0 and wml.call(B + 0x49F8A0, e) or 0
          if c ~= 0 then out[#out + 1] = { id = wml.read_u32(e + 0x58), entry = e, comp = c, slot = s, loadout = lo } end
        end
      end
    end
  end
  add(v)
  local k = P.component(0x8A, v)
  local h = k and wml.read_u32(k + 0x670) or 0
  if (h & 0xFF) == 0xD then
    local buf = wml.buffer(10)
    wml.write_u32(buf, h)
    local st = wml.call(B + 0x1AB52F0, buf)
    if st ~= 0 then
      local arr = wml.read_u64(st + 0x170)
      for i = 0, wml.read_u16(st + 0x178) - 1 do
        local lh = wml.read_u32(arr + i * 0xE0 + 0x40)
        if (lh & 0xFF) == 0xE then add(wml.call(B + 0x1E62F0, lh, 0)) end
      end
    end
  end
  return out
end
-- Each gun shoots at its own refire from where it sits to where the camera looks. Recoil input 0: +1C01680 is for a held gun.
P.wheel_guns = false
function P.update_wheel_guns(menu_open)
  local B, X, v = wml.base, SR5TM_EXTRA, P.vehicle_object()
  if not v then X.wheel_list, X.wheel_id = nil, nil; return end
  local id = wml.read_u32(v + 0x58)
  X.wheel_wait = (X.wheel_wait or 0) - 1
  if X.wheel_id ~= id or X.wheel_wait <= 0 then
    X.wheel_list, X.wheel_id, X.wheel_wait = P.car_guns(v), id, 120
  end
  local b = wml.pad() or 0
  if menu_open or not ((b & 0x80) ~= 0 or wml.key_down("G")) then return end
  local function s32(x) return x >= 0x80000000 and x - 0x100000000 or x end
  local now = wml.read_u32(B + 0x2E80878)
  local f = B + 0x41E1AC0 + 0x20
  local cx, cy, cz = s32(wml.read_u32(B + 0x41E1AB0)), s32(wml.read_u32(B + 0x41E1AB4)), s32(wml.read_u32(B + 0x41E1AB8))
  local tx, ty, tz = cx + wml.read_f32(f) * 3000000, cy + wml.read_f32(f + 4) * 3000000, cz + wml.read_f32(f + 8) * 3000000   -- 300 m
  local none = wml.read_u32(B + 0x48E778C)
  local function int3(x, y, z) return { math.floor(x) & 0xFFFFFFFF, math.floor(y) & 0xFFFFFFFF, math.floor(z) & 0xFFFFFFFF } end
  for _, g in ipairs(X.wheel_list) do
    if wml.read_u32(g.entry + 0x58) == g.id and (not g.next or now >= g.next) then
      g.next = now + math.max(60, wml.read_u32(g.comp + 0x7B8))
      local gx, gy, gz = s32(wml.read_u32(g.entry + 0x30)), s32(wml.read_u32(g.entry + 0x34)), s32(wml.read_u32(g.entry + 0x38))
      local dx, dy, dz = tx - gx, ty - gy, tz - gz
      local len = math.sqrt(dx * dx + dy * dy + dz * dz)
      if len > 0 then
        local k = 20000 / len   -- 2 m out, past the vehicle's own body
        local shot = 0xD57E1B94
        local list, n = wml.read_u64(g.comp + 0x138), wml.read_u16(g.comp + 0x140)
        for i = 0, n - 1 do
          if wml.read_u32(list + i * 24) == 817162218 then shot = wml.read_u32(list + i * 24 + 8) end
        end
        P.node(0x1C083C0, 0x2AF94F8, { { u = g.id }, { u = 0 }, { i = int3(gx + dx * k, gy + dy * k, gz + dz * k) }, { i = int3(tx, ty, tz) }, { f = 0.0 }, { u = none }, { u = shot }, { u = 0 } })
      end
    end
  end
end

-- Swap the first gun's slot for another prefab, once loaded. Only where a gun already sits.
local mount_wait
function P.car_mount(path)
  if mount_wait then return "Still loading" end
  local v = P.vehicle_object()
  local g = v and P.car_guns(v)[1]
  if not g then return "No mount on this vehicle" end
  local B = wml.base
  local cid = wml.call(B + 0xE71120, wml.buffer(5, path .. ".cprefab_pc"), 0x12, 0)
  local hid = wml.call(B + 0xE71120, wml.buffer(5, path .. ".hprefab_pc"), 0x12, 0)
  if cid == 0 or hid == 0 then
    if cid ~= 0 then wml.call(B + 0xE71480, cid, 0x12) end
    if hid ~= 0 then wml.call(B + 0xE71480, hid, 0x12) end
    return "Couldn't load that"
  end
  mount_wait = { path = path, cid = cid, hid = hid, ticks = 1800, veh = wml.read_u32(v + 0x58), slot = g.slot, loadout = g.loadout }
  return "Loading..."
end
function P.mount_pending() return mount_wait ~= nil end
function P.update_car_mount()
  local B, w = wml.base, mount_wait
  local a, b = wml.call(B + 0xE715E0, w.cid) & 0xFFFFFFFF, wml.call(B + 0xE715E0, w.hid) & 0xFFFFFFFF
  w.ticks = w.ticks - 1
  local v = P.vehicle_object()
  if a == 4 and b == 4 and v and wml.read_u32(v + 0x58) == w.veh then
    local list = (wml.buffer(11) + 15) & ~15
    wml.write_u64(list, list + 0x18); wml.write_u32(list + 8, 0); wml.write_u32(list + 0xC, 2); wml.write_u64(list + 0x10, 0)
    wml.call(B + 0x1BF6260, w.loadout, list, w.slot, 0, 1)
    local items = wml.read_u64(list)
    for i = 0, wml.read_u16(list + 8) - 1 do wml.call(B + 0x1C1F4F0, wml.read_u64(items + i * 8)) end
    local namep = wml.buffer(5, w.path .. ".cprefab_pc")
    local id = wml.call(B + 0xE8E370, namep)
    wml.call(B + 0xE8EA40, id, namep, 7)
    wml.call(B + 0x1BF5940, w.loadout, id, w.slot, 0, 5, 0)
  elseif not (a == 5 or b == 5 or w.ticks <= 0 or not v) then
    return
  end
  -- held on as props are: a spawn may still be populating
  prop_release[#prop_release + 1] = { cid = w.cid, hid = w.hid, ticks = 600 }
  mount_wait = nil
end

-- Every seat armed: the forced-unarmed row like a normal car's, and back seats on anything else. Global rows, changed only with the seats you're in popped.
P.seat_guns = false
local SEAT_ROWS = {
  [0x3C40090] = 0x3C40080, [0x3C40094] = 0x3C40084, [0x3C40098] = 0x3C40084, [0x3C4009C] = 0x3C40084,   -- forced unarmed
  [0x3C4008C] = 0x3C40084, [0x3C400AC] = 0x3C40084,                                                     -- car and bike, last seat
  [0x3C400B4] = 0x3C40084, [0x3C400B8] = 0x3C40084, [0x3C400BC] = 0x3C40084,                            -- tank, not the driver
  [0x3C445F4] = 0x3C40084, [0x3C445F8] = 0x3C40084, [0x3C44604] = 0x3C40084, [0x3C44608] = 0x3C40084,   -- flight, seats 1 and 2
  [0x3C36474] = 0x3C40084,                                                                              -- hover, last seat
}
function P.update_seat_guns()
  local B, X = wml.base, SR5TM_EXTRA
  local on = P.seat_guns and true or false
  if on == (X.seat_rows ~= nil) then return end
  local v = P.vehicle_object()
  local c = v and P.component(0x8A, v)
  local bits = c and (wml.read_u8(c + 0x6F2) & 15) or 0
  for s = 0, 3 do if bits & (1 << s) ~= 0 then wml.call(B + 0xB77F10, c, s, 0) end end
  if on then
    X.seat_rows = {}
    for addr, from in pairs(SEAT_ROWS) do
      X.seat_rows[addr] = wml.read_u32(B + addr)
      wml.write_u32(B + addr, wml.read_u32(B + from))
    end
  else
    for addr, val in pairs(X.seat_rows) do wml.write_u32(B + addr, val) end
    X.seat_rows = nil
  end
  for s = 0, 3 do if bits & (1 << s) ~= 0 then wml.call(B + 0xB77F10, c, s, 1) end end
end

-- Per car, by the game's own Havok calls. Comp 6's copies change too, in case it rebuilds the body from them.
P.car_max_speed, P.car_lin_damp, P.car_ang_damp, P.car_time, P.car_bounce, P.car_com = false, false, false, false, false, false
local MOTION = { car_max_speed = { 0x10, 0x44 }, car_lin_damp = { 0x18, 0x3C, abs = true }, car_ang_damp = { 0x1C, 0x40, abs = true }, car_time = { 0xC } }
local function body_of(v)
  local c = P.component(6, v)
  local id = c and wml.read_u32(c + 0xF0)
  if not id or (id & 0xFFFFFF) == 0xFFFFFF then return nil end
  return id, c
end
function P._update_car_physics()
  local B, X, v = wml.base, SR5TM_EXTRA, P.vehicle_object()
  local id, c
  if v then id, c = body_of(v) end
  local key = table.concat({ tostring(id), tostring(P.car_max_speed), tostring(P.car_lin_damp), tostring(P.car_ang_damp), tostring(P.car_time), tostring(P.car_bounce), tostring(P.car_com) }, ",")
  if not id or X.phys_key == key then return end
  X.phys_key = key
  X.phys_orig = X.phys_orig or {}
  local o = X.phys_orig[id]
  -- a vehicle nothing was ever changed on is left alone
  if not o and not (P.car_max_speed or P.car_lin_damp or P.car_ang_damp or P.car_time or P.car_bounce or P.car_com) then return end
  local w = wml.read_u64(B + 0x5CB4FF0)
  local idx = id & 0xFFFFFF
  if idx >= wml.read_u32(w + 0x30) then return end
  local body = wml.read_u64(w + 0x28) + idx * 0xB0
  if wml.read_u8(body + 0x44) & 1 ~= 0 then return end
  -- motion properties
  local m = wml.read_u64(w + 0x180) + wml.read_u32(body + 0x40) * 0x80
  local pid = wml.read_u16(m + 0x38)
  if pid ~= wml.read_u16(B + 0x45E808C) and pid ~= wml.read_u16(B + 0x36577C8) then
    local src = wml.read_u64(wml.read_u64(w + 0xAB8) + 0x30) + pid * 0x70
    if not o then
      o = { rest = false, com = { wml.read_f32(c + 0x50), wml.read_f32(c + 0x54), wml.read_f32(c + 0x58) }, use = wml.read_u8(c + 0x6C) }
      for k, f in pairs(MOTION) do
        o[k] = wml.read_f32(src + f[1])
        if f[2] then o[k .. "_c"] = wml.read_f32(c + f[2]) end
      end
      local mat = wml.read_u64(wml.read_u64(w + 0xAB0) + 0x30) + wml.read_u16(body + 0x6A) * 0x70
      wml.write_u32(wml.buffer(12), wml.read_u16(mat + 0x36) << 16)
      o.rest = wml.read_f32(wml.buffer(12))
      X.phys_orig[id] = o
    end
    local buf = (wml.buffer(11) + 15) & ~15
    for i = 0, 0x68, 8 do wml.write_u64(buf + i, wml.read_u64(src + i)) end
    for k, f in pairs(MOTION) do
      local want = P[k]
      local val = (not want) and o[k] or (f.abs and want or o[k] * want)
      wml.write_f32(buf + f[1], val)
      if f[2] then wml.write_f32(c + f[2], want and val or o[k .. "_c"]) end
    end
    wml.call(B + 0x18C1660, id, buf)
  end
  -- bounce: a new material copy, as friction does
  if o then
    local want = P.car_bounce or o.rest
    wml.callf(B + 0x18C1140, id, want + 0.0)
    wml.write_f32(c + 0xAC, want)
    -- centre of mass: offsets from where it was, or from the shape's own if it had none (M, that's near the origin)
    local req = (wml.buffer(13) + 15) & ~15
    for i = 0, 0x38, 8 do wml.write_u64(req + i, 0) end
    wml.write_u32(req, 0xFFFFFF)
    wml.write_u8(req + 0x30, 0xC)
    local d = P.car_com
    if d then
      for i = 1, 3 do wml.write_f32(req + 0x20 + (i - 1) * 4, (o.use ~= 0 and o.com[i] or 0) + d[i]) end
    elseif o.use ~= 0 then
      for i = 1, 3 do wml.write_f32(req + 0x20 + (i - 1) * 4, o.com[i]) end
    else
      wml.write_u32(req + 0x20, 0x7F800000)
    end
    if d or X.phys_com == id then
      wml.call(B + 0x1848A70, v, 0x1FFFFFF, 0x1E, req)
      X.phys_com = d and id or nil
    end
  end
end

-- Any aircraft as a helicopter, fixed-wing or VTOL. Empty params (a helicopter's fixed-wing limits are often 0) are refused; a VTOL with no blend time gets one.
P.flight_mode = false
function P._update_flight_mode(v)
  local B, X = wml.base, SR5TM_EXTRA
  local l = P.component(0x15, v)
  local a = P.component(0x88, v)
  if not l or not a or wml.read_u8(a + 0x432) ~= 0 or wml.read_u8(l + 0x39A) ~= 0 then return end   -- no hover boards, no ground huggers
  local id = wml.read_u32(v + 0x58)
  X.flight_orig = X.flight_orig or {}
  local o = X.flight_orig[id]
  local want = P.flight_mode
  if want == false then
    if not o then return end
    want = o.mode
  elseif not o then
    o = { mode = wml.read_u32(l + 0x390), row = wml.read_u32(a + 0x438) }
    X.flight_orig[id] = o
  end
  if wml.read_u32(l + 0x390) == want then
    if P.flight_mode == false then X.flight_orig[id] = nil end
    return
  end
  if want ~= 0 and wml.read_f32(l + 0x1DC) <= 0 then return end
  if want == 2 then
    if wml.read_f32(l + 0x1E0) <= 0 then wml.write_f32(l + 0x1E0, 1.0) end
    if wml.read_f32(l + 0x1E4) <= 0 then wml.write_f32(l + 0x1E4, 1.0) end
  end
  wml.write_u32(l + 0x390, want)
  local c = P.component(0x8A, v)
  local bits = c and (wml.read_u8(c + 0x6F2) & 15) or 0
  local row = P.flight_mode == false and o.row or (want < 2 and want or wml.read_u32(a + 0x438))
  if row ~= wml.read_u32(a + 0x438) then
    for s = 0, 3 do if bits & (1 << s) ~= 0 then wml.call(B + 0xB77F10, c, s, 0) end end
    wml.write_u32(a + 0x438, row)
    for s = 0, 3 do if bits & (1 << s) ~= 0 then wml.call(B + 0xB77F10, c, s, 1) end end
  end
end

return P
