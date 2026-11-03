-- SR5 Tweak Menu - creator mode: a free camera that places objects, at any angle, and keeps layouts in files.
--
-- Seen in the game (2026-11-02): an object takes its rotation and position from the spawn struct and keeps them, standing
-- still with nothing holding it, and solid. Moving or rotating it after it's made changes its numbers only: the picture and
-- the collision stay put. So every move here removes the object and makes it again. Its prefab has to be loaded first: a
-- spawn of one still loading hung the game once. 121 chairs were fine; this stops at 200.
local P = require("player")
local CR = {}
local function s32(v) return v >= 0x80000000 and v - 0x100000000 or v end
local function iv(m) return math.floor(m * 10000 + 0.5) & 0xFFFFFFFF end

-- Kept across a reload of these files: what's placed, and the camera.
SR5TM_CR = SR5TM_CR or { placed = {}, refs = {}, retire = {}, queue = {}, gen = 0 }
local S = SR5TM_CR
P.creator_step, P.creator_grid = false, false   -- turn step in degrees (false: 15), grid in metres (false: off)
CR.MAX = 200
CR.PAD = { UP = 0x1, DOWN = 0x2, LEFT = 0x4, RIGHT = 0x8, BACK = 0x20, LS = 0x40, LB = 0x100, RB = 0x200, A = 0x1000, B = 0x2000, X = 0x4000, Y = 0x8000 }
local PAD = CR.PAD
local FC_GATE = 0x5CC7718

-- ------------------------------------------------------------------ prefabs: loaded before use, let go a while after
local function ref(path)
  local r = S.refs[path]
  if not r then
    local B = wml.base
    r = { wml.call(B + 0xE71120, wml.buffer(5, path .. ".cprefab_pc"), 0x12, 0), wml.call(B + 0xE71120, wml.buffer(5, path .. ".hprefab_pc"), 0x12, 0) }
    S.refs[path] = r
  end
  r.used = 0
  return r
end
-- true loaded, false can't be, nil still loading
local function ready(path)
  local r = ref(path)
  if r[1] == 0 or r[2] == 0 then return false end
  local B = wml.base
  local a, b = wml.call(B + 0xE715E0, r[1]) & 0xFFFFFFFF, wml.call(B + 0xE715E0, r[2]) & 0xFFFFFFFF
  if a == 5 or b == 5 then return false end
  if a == 4 and b == 4 then return true end
  return nil
end
local function age_refs(keep)
  local B = wml.base
  for path, r in pairs(S.refs) do
    if not keep[path] then
      r.used = (r.used or 0) + 1
      if r.used > 600 then
        if r[1] ~= 0 then wml.call(B + 0xE71480, r[1], 0x12) end
        if r[2] ~= 0 then wml.call(B + 0xE71480, r[2], 0x12) end
        S.refs[path] = nil
      end
    end
  end
end

-- ------------------------------------------------------------------ turning
-- Rows as the object keeps them: right, up, forward, each x y z and a spare. Yaw about up, then pitch about right, then roll
-- about forward. Yaw 0 faces +z.
local function rows(yaw, pitch, roll)
  local r, p, o = math.rad(yaw), math.rad(pitch), math.rad(roll)
  local sy, cy, sp, cp, sr, cr = math.sin(r), math.cos(r), math.sin(p), math.cos(p), math.sin(o), math.cos(o)
  local f = { sy, 0, cy }
  local ri = { cy, 0, -sy }
  local f1 = { f[1] * cp, sp, f[3] * cp }
  local u1 = { -f[1] * sp, cp, -f[3] * sp }
  local r2 = { ri[1] * cr + u1[1] * sr, ri[2] * cr + u1[2] * sr, ri[3] * cr + u1[3] * sr }
  local u2 = { u1[1] * cr - ri[1] * sr, u1[2] * cr - ri[2] * sr, u1[3] * cr - ri[3] * sr }
  return { r2[1], r2[2], r2[3], 0, u2[1], u2[2], u2[3], 0, f1[1], f1[2], f1[3], 0 }
end
CR.rows = rows

-- ------------------------------------------------------------------ making and removing
-- As P.spawn_prefab, with our own rotation and position written into the struct. Returns the spawn record, or nil.
local function spawn(path, x, y, z, yaw, pitch, roll)
  local B = wml.base
  local player = P.object()
  if not player then return nil end
  local namep, filep, params = wml.buffer(5, path .. ".cprefab_pc"), wml.buffer(7, "sr5_tweak_menu"), wml.buffer(6)
  local srid = wml.call(B + 0xE8E370, namep)
  if srid == 0 then return nil end
  wml.call(B + 0xE8EA40, srid, namep, 7)
  local layer = wml.call(B + 0x484F40, B + 0x4AA4328)
  if layer == 0 then return nil end
  for i = 0, 0x1F0, 8 do wml.write_u64(params + i, 0) end
  wml.call(B + 0x1A9D3F0, params)
  wml.write_u64(params, srid)
  for i = 0, 0x38, 4 do wml.write_u32(params + 0x10 + i, wml.read_u32(player + i)) end
  for i, v in ipairs(rows(yaw, pitch, roll)) do wml.write_f32(params + 0x10 + (i - 1) * 4, v) end
  wml.write_u32(params + 0x40, iv(x)); wml.write_u32(params + 0x44, iv(y)); wml.write_u32(params + 0x48, iv(z))
  wml.write_u32(params + 0x50, wml.read_u32(layer + 0x34))
  local rec = wml.call(B + 0x4AE810, 0, params, 0, filep, 1)
  return rec ~= 0 and rec or nil
end
local function born(o) if o then o.born = S.t or 0 end return o end
-- An object's id turns up in its record once it exists. Read it once, then go by the id only.
local function settle(o)
  if o.id or not o.rec or o.gen ~= S.gen then return o.id end
  local id = wml.read_u32(o.rec + 0x70)
  if id ~= 0 then o.id, o.rec = id, nil end
  return o.id
end
-- Not before it's 2 s old. The game crashed at +1842726, a missing part in a prefab's list of parts, while previews of the
-- trailer ramp, which is several parts, were being made and taken away several times a second (2026-11-02 20:04). The id turns
-- up before the parts are all made, it seems, so an early removal pulls one out from under the game.
CR.MIN_AGE = 120
local function remove(o)
  if o.gen ~= S.gen then return true end   -- from before a load: already gone
  settle(o)
  if not o.id then return false end
  if o.born and (S.t or 0) - o.born < CR.MIN_AGE then return false end
  local e = P.entry_of(o.id)
  if e and wml.read_u32(e + 0x58) == o.id then wml.call(wml.base + 0x1E6920, e + 0x58) end
  return true
end
-- Things to take away once their id has arrived.
local function retire(o)
  if not o then return end
  o.waited = 0
  S.retire[#S.retire + 1] = o
  if o.ghostly and o.id then S.recent = S.recent or {}; S.recent[o.id] = 120 end
end
local function update_retire()
  for id, t in pairs(S.recent or {}) do S.recent[id] = t > 1 and t - 1 or nil end
  local left = {}
  for _, o in ipairs(S.retire) do
    if not remove(o) then
      o.waited = o.waited + 1
      if o.waited < 900 then left[#left + 1] = o else wml.log("creator: an object never got an id, left in the world") end
    end
  end
  S.retire = left
end

-- ------------------------------------------------------------------ what a line hits
-- physics_raycast_node, as P.camera_ray: from a to b in metres, ignoring one object. The first hit, or nil. Wires and roofs
-- count, so a line straight down from high up stops on a power line (seen: a preview 10 m up).
local function ray(ax, ay, az, bx, by, bz, ignore)
  P.node(0x1931D90, 0x2AD2238, { { i = { iv(ax), iv(ay), iv(az) } }, { i = { iv(bx), iv(by), iv(bz) } }, { u = ignore or 0 }, { p = 0 }, { u = 0 }, { u = 1 },
    { u = 0 }, { u = 0 }, { u = 0 }, { u = 0 }, { u = 0 } })
  local s = wml.buffer(0) + 0x400
  local id = wml.read_u32(s + 0xC0)
  if id ~= 0 then wml.call(wml.base + 0x4EA450, s + 0xC0) end
  local hx, hy, hz = wml.read_u32(s + 0xE0), wml.read_u32(s + 0xE4), wml.read_u32(s + 0xE8)
  if hx == 0 and hy == 0 and hz == 0 then return nil end
  return s32(hx) / 10000, s32(hy) / 10000, s32(hz) / 10000, id
end
-- The same, going on past you and your vehicle: the camera starts behind you (seen: a preview on your head).
-- Previews too, this one and any taken away in the last two seconds: their shapes linger, and the line climbed onto them.
local function ray_past(ax, ay, az, dx, dy, dz, len, ignore)
  local me, car = P.object(), P.vehicle_object()
  local skip = { [me and wml.read_u32(me + 0x58) or -1] = true, [car and wml.read_u32(car + 0x58) or -1] = true }
  for id in pairs(S.recent or {}) do skip[id] = true end
  if ignore then skip[ignore] = true end
  local gone = 0
  for _ = 1, 4 do
    local hx, hy, hz, id = ray(ax, ay, az, ax + dx * (len - gone), ay + dy * (len - gone), az + dz * (len - gone), ignore)
    if not hx then return nil end
    if not skip[id] then return hx, hy, hz end
    local step = ((hx - ax) ^ 2 + (hy - ay) ^ 2 + (hz - az) ^ 2) ^ 0.5 + 0.3
    ax, ay, az, gone = ax + dx * step, ay + dy * step, az + dz * step, gone + step
    if gone >= len then return nil end
  end
  return nil
end

-- ------------------------------------------------------------------ state
-- S.on: the camera and cursor. S.ghost: the object being placed. S.placed: { path, label, x, y, z, yaw, pitch, roll, rec/id, gen }.
function P.creator_active() return S.on ~= nil end
function P.creator_busy() return S.on ~= nil or #S.retire > 0 or #S.queue > 0 or next(S.refs) ~= nil end
function P.creator_count() return #S.placed end
function P.creator_set_list(list, i) S.list, S.i = list, math.max(1, math.min(i or 1, #list)) end
function P.creator_index() return S.i end
local function pick() return S.list and S.list[S.i] end
local function say(t) S.msg, S.msg_t = t, 240 end
CR.say = say

function P.creator_start()
  if not S.list or #S.list == 0 then return "No objects to place" end
  local B = wml.base
  local rec = wml.read_u64(B + 0x5BDF320)
  local ce = rec ~= 0 and P.entry_of(wml.read_u32(rec + 0x1C))
  if not ce or not P.object() then return "Not now" end
  P.free_cam = false
  S.on = { cam = { s32(wml.read_u32(B + 0x41E1AB0)), s32(wml.read_u32(B + 0x41E1AB4)), s32(wml.read_u32(B + 0x41E1AB8)) },
    yaw = math.floor(math.deg(math.atan(wml.read_f32(ce + 0x20), wml.read_f32(ce + 0x28))) / 15 + 0.5) * 15, pitch = 0, roll = 0, dist = 10, onground = true,
    prev = 0, rep = {}, frames = 0 }
  wml.write_u8(B + FC_GATE, 0)
  say("Creator mode: B or Backspace leaves")
  return nil
end
local function unblock()
  if wml.pad_mask then wml.pad_mask(0) end
  if wml.block_triggers then wml.block_triggers(false) end
  if wml.block_input then wml.block_input(false, false) end
end
function P.creator_stop(put_me)
  if not S.on then return end
  local B = wml.base
  local at = S.on.at
  retire(S.ghost); S.ghost = nil
  retire(S.next_ghost); S.next_ghost = nil
  wml.write_u8(B + FC_GATE, 1)
  S.on = nil
  unblock()
  if put_me and at then P.teleport(at[1], at[2] + 1, at[3]) end
end

-- ------------------------------------------------------------------ placing
local function place_here()
  local o, at = pick(), S.on.at
  if not o or not at then return end
  if #S.placed >= CR.MAX then say("That's " .. CR.MAX .. ": the game's object pools come first. Delete some first."); return end
  local p = { path = P._prop_path(o[2]), name = o[2], label = o[1], x = at[1], y = at[2], z = at[3], yaw = S.on.yaw, pitch = S.on.pitch, roll = S.on.roll, gen = S.gen }
  -- the object already on screen becomes the placed one; the next preview waits until you move
  local g = S.ghost
  if g and g.key == S.on.key then
    p.rec, p.id = g.rec, g.id
    S.ghost = nil
    if p.id and S.recent then S.recent[p.id] = nil end
  else
    p.rec = spawn(p.path, p.x, p.y, p.z, p.yaw, p.pitch, p.roll)
    if not p.rec then say("The game refused it"); return end
    born(p)
  end
  S.placed[#S.placed + 1] = p
  S.on.held = S.on.key
  say("Placed " .. o[1] .. ": " .. #S.placed .. " of " .. CR.MAX)
end
local function delete_near()
  local at = S.on.at
  if not at then return end
  local best, bd
  for i, p in ipairs(S.placed) do
    local d = (p.x - at[1]) ^ 2 + (p.y - at[2]) ^ 2 + (p.z - at[3]) ^ 2
    if not bd or d < bd then best, bd = i, d end
  end
  if not best or bd > 36 then say("Nothing you placed within 6 m of the cursor"); return end
  local p = table.remove(S.placed, best)
  retire(p)
  say("Deleted " .. p.label .. ": " .. #S.placed .. " left")
end
function P.creator_clear()
  local n = #S.placed
  for _, p in ipairs(S.placed) do retire(p) end
  S.placed, S.queue = {}, {}
  return n
end

-- ------------------------------------------------------------------ layouts: TweakMenu\layout_N.txt, one object a line
CR.SLOTS = 8
local function file(n) return wml.root .. "\\layout_" .. n .. ".txt" end
function P.layout_read(n)
  local f = io.open(file(n), "r")
  if not f then return nil end
  local out = { name = "Layout " .. n, objects = {} }
  for line in f:lines() do
    local k, v = line:match("^(.-)=(.*)$")
    if k == "name" then out.name = v
    elseif k == "obj" then
      local name, x, y, z, yaw, pitch, roll = v:match("^(%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)$")
      if name then out.objects[#out.objects + 1] = { name = name, x = tonumber(x), y = tonumber(y), z = tonumber(z), yaw = tonumber(yaw), pitch = tonumber(pitch), roll = tonumber(roll) } end
    end
  end
  f:close()
  return out
end
function P.layout_write(n)
  if #S.placed == 0 then return false, "Nothing placed to keep" end
  local old = P.layout_read(n)
  local f = io.open(file(n), "w")
  if not f then return false, "Couldn't write the file" end
  f:write("name=", old and old.name or ("Layout " .. n), "\n")
  for _, p in ipairs(S.placed) do
    f:write(string.format("obj=%s %.3f %.3f %.3f %.1f %.1f %.1f\n", p.name, p.x, p.y, p.z, p.yaw, p.pitch, p.roll))
  end
  f:close()
  return true, #S.placed
end
function P.layout_delete(n) os.remove(file(n)) end
-- Puts a layout's objects back, a few a frame, each once its prefab has loaded. Far ones are refused: the ground there may
-- not be loaded, and an object in an unloaded spot hasn't been tried.
function P.layout_load(n, labels)
  local l = P.layout_read(n)
  if not l or #l.objects == 0 then return nil, "That layout is empty" end
  local x, y, z = P.position()
  if not x then return nil, "Not now" end
  local o = l.objects[1]
  local far = ((o.x - x) ^ 2 + (o.z - z) ^ 2) ^ 0.5
  if far > 300 then return nil, string.format("It's %.0f m away: use Go to layout first", far) end
  if #S.placed + #l.objects > CR.MAX then return nil, "That would pass " .. CR.MAX .. " objects: clear some first" end
  for _, ob in ipairs(l.objects) do
    S.queue[#S.queue + 1] = { path = P._prop_path(ob.name), name = ob.name, label = labels and labels[ob.name] or ob.name, x = ob.x, y = ob.y, z = ob.z, yaw = ob.yaw, pitch = ob.pitch, roll = ob.roll }
  end
  return #l.objects
end
function P.layout_where(n)
  local l = P.layout_read(n)
  local o = l and l.objects[1]
  if not o then return nil end
  return o.x, o.y, o.z
end
local function update_queue()
  local made = 0
  while #S.queue > 0 and made < 3 do
    local q = S.queue[1]
    local r = ready(q.path)
    if r == nil then return end
    table.remove(S.queue, 1)
    if r == false then
      say("Couldn't load " .. q.label .. ": skipped")
    else
      q.rec, q.gen = spawn(q.path, q.x, q.y, q.z, q.yaw, q.pitch, q.roll), S.gen
      born(q)
      if q.rec then S.placed[#S.placed + 1] = q; made = made + 1 end
    end
  end
end

-- ------------------------------------------------------------------ each frame
local function repeating(name, down)
  local r = S.on.rep
  if not down then r[name] = nil; return false end
  r[name] = (r[name] or 0) + 1
  return r[name] == 1 or (r[name] > 18 and r[name] % 4 == 0)
end
local function snap(v, g) if not g then return v end return math.floor(v / g + 0.5) * g end

-- menu_open: the menu has the controls, so the camera holds still.
function P.update_creator(menu_open)
  local B = wml.base
  S.t = (S.t or 0) + 1
  -- a load or a respawn: what was placed went with the old world
  if not P.object() then
    if #S.placed > 0 or S.ghost then S.gen = S.gen + 1; S.placed, S.ghost, S.next_ghost, S.retire = {}, nil, nil, {} end
    if S.on then P.creator_stop() end
    return
  end
  update_retire()
  update_queue()
  local keep = {}
  for _, q in ipairs(S.queue) do keep[q.path] = true end
  local o = pick()
  if S.on and o then keep[P._prop_path(o[2])] = true end
  age_refs(keep)
  if S.msg_t then S.msg_t = S.msg_t - 1; if S.msg_t <= 0 then S.msg, S.msg_t = nil, nil end end
  local on = S.on
  if not on then return end
  local rec = wml.read_u64(B + 0x5BDF320)
  local ce = rec ~= 0 and P.entry_of(wml.read_u32(rec + 0x1C))
  if not ce then P.creator_stop(); return end
  on.frames = on.frames + 1

  -- input: keep it from the game while the menu is closed
  local buttons, lt, rt, lx, ly = 0, 0, 0, 0, 0
  if not menu_open then
    if on.frames % 15 == 1 or on.menu_was then
      if wml.block_all then wml.block_all(true) elseif wml.block_input then wml.block_input(true, true) end
      if wml.pad_mask then wml.pad_mask(0, true, true) end
    end
    local b, l, r, x, y = wml.pad()
    buttons, lt, rt, lx, ly = b or 0, l or 0, r or 0, x or 0, y or 0
  end
  on.menu_was = menu_open
  local pressed = buttons & ~on.prev
  local released = on.prev & ~buttons
  on.prev = buttons
  local function key(k) return not menu_open and wml.key_pressed(k) end
  local function held(k) return not menu_open and wml.key_down(k) end

  -- the camera, as Free camera does it
  local function stick(v) if math.abs(v) < 7849 then return 0 end return (v > 0 and 1 or -1) * (math.abs(v) - 7849) / 24918 end
  local function pull(v) if v <= 30 then return 0 end return (v - 30) / 225 end
  local f, r, u = stick(ly), stick(lx), pull(rt) - pull(lt)
  f = f + (held("W") and 1 or 0) - (held("S") and 1 or 0)
  r = r + (held("D") and 1 or 0) - (held("A") and 1 or 0)
  u = u + (held("SPACE") and 1 or 0) - (held("CTRL") and 1 or 0)
  local step = ((held("SHIFT") or buttons & PAD.LS ~= 0) and 30 or 8) * 10000 / 60
  local fx, fy, fz = wml.read_f32(ce + 0x20), wml.read_f32(ce + 0x24), wml.read_f32(ce + 0x28)
  local c = on.cam
  c[1] = c[1] + (fx * f + wml.read_f32(ce) * r) * step
  c[2] = c[2] + (fy * f + u) * step
  c[3] = c[3] + (fz * f + wml.read_f32(ce + 8) * r) * step
  -- not far from you: the world around you is what's loaded
  local px, py, pz = P.position()
  local dx, dz = c[1] / 10000 - px, c[3] / 10000 - pz
  local dd = (dx * dx + dz * dz) ^ 0.5
  if dd > 150 then c[1], c[3] = (px + dx * 150 / dd) * 10000, (pz + dz * 150 / dd) * 10000; on.far = true else on.far = false end
  local b = wml.buffer(12) + 0xC00
  for i = 1, 3 do wml.write_u32(b + (i - 1) * 4, math.floor(c[i]) & 0xFFFFFFFF) end
  for i = 0, 0x2F, 4 do wml.write_u32(b + 0x10 + i, wml.read_u32(ce + i)) end
  wml.call(B + 0x1505010, b, b + 0x10)

  -- turning and the rest
  local lb = buttons & PAD.LB ~= 0
  local turn = P.creator_step or 15
  if lb then
    if repeating("roll-", buttons & PAD.LEFT ~= 0) then on.roll = on.roll - turn; on.lb_used = true end
    if repeating("roll+", buttons & PAD.RIGHT ~= 0) then on.roll = on.roll + turn; on.lb_used = true end
    if repeating("near", buttons & PAD.DOWN ~= 0) then on.dist = math.max(3, on.dist - 1); on.lb_used = true end
    if repeating("far", buttons & PAD.UP ~= 0) then on.dist = math.min(60, on.dist + 1); on.lb_used = true end
  else
    if repeating("yaw-", buttons & PAD.LEFT ~= 0) then on.yaw = on.yaw - turn end
    if repeating("yaw+", buttons & PAD.RIGHT ~= 0) then on.yaw = on.yaw + turn end
    if repeating("pitch+", buttons & PAD.UP ~= 0) then on.pitch = on.pitch + turn end
    if repeating("pitch-", buttons & PAD.DOWN ~= 0 and buttons & PAD.RB == 0) then on.pitch = on.pitch - turn end
  end
  if repeating("kyaw-", held("LEFT")) then on.yaw = on.yaw - turn end
  if repeating("kyaw+", held("RIGHT")) then on.yaw = on.yaw + turn end
  if repeating("kpitch+", held("UP")) then on.pitch = on.pitch + turn end
  if repeating("kpitch-", held("DOWN")) then on.pitch = on.pitch - turn end
  if repeating("kroll-", held("Q")) then on.roll = on.roll - turn end
  if repeating("kroll+", held("E")) then on.roll = on.roll + turn end
  if repeating("kfar", held("R")) then on.dist = math.min(60, on.dist + 1) end
  if repeating("knear", held("F")) then on.dist = math.max(3, on.dist - 1) end
  on.yaw, on.pitch, on.roll = on.yaw % 360, on.pitch % 360, on.roll % 360
  -- LB and RB tapped on their own: the previous and next object. RB with D-pad Down is the menu's.
  if pressed & PAD.LB ~= 0 then on.lb_used = false end
  if pressed & PAD.RB ~= 0 then on.rb_used = false end
  if buttons & PAD.RB ~= 0 and buttons & PAD.DOWN ~= 0 then on.rb_used = true end
  local n = S.list and #S.list or 0
  if (released & PAD.LB ~= 0 and not on.lb_used) or key("PAGEUP") then S.i = (S.i - 2) % n + 1; say(S.list[S.i][1]) end
  if (released & PAD.RB ~= 0 and not on.rb_used) or key("PAGEDOWN") then S.i = S.i % n + 1; say(S.list[S.i][1]) end
  if pressed & PAD.Y ~= 0 or key("G") then on.onground = not on.onground; on.hit = nil; say(on.onground and "On the ground" or "Free: in the air, at the cursor's height") end
  if pressed & PAD.BACK ~= 0 or key("HOME") then on.yaw, on.pitch, on.roll = on.yaw, 0, 0; say("Level again") end

  -- where it goes
  o = pick()
  local d = on.dist
  local ax, ay, az = c[1] / 10000 + fx * d, c[2] / 10000 + fy * d, c[3] / 10000 + fz * d
  local g = P.creator_grid
  ax, az = snap(ax, g), snap(az, g)
  -- On the ground: the set distance out, then straight down from just above the camera's height onto the ground, or onto
  -- something you placed. A line along the view kept catching you, a line from high up stopped on power lines, and the
  -- preview's own parts caught it too, whatever was ignored. So when the cursor moves, the preview steps aside, and the
  -- ground is read with nothing of ours in the way; it comes back once you stop.
  on.wait_ground = false
  if on.onground then
    local moved = not on.hit or math.abs(on.hit[4] - ax) > 0.05 or math.abs(on.hit[5] - az) > 0.05
    if moved then
      if S.ghost then retire(S.ghost); S.ghost = nil; on.cleared = on.frames end
      if not S.next_ghost and #S.retire == 0 and on.frames - (on.cleared or -99) > 3 then
        local top = math.max(ay, c[2] / 10000) + 1
        local _, hy = ray_past(ax, top, az, 0, -1, 0, 80)
        on.hit = { ax, hy or ay, az, ax, az }
      else on.wait_ground = true end
    end
    if on.hit then ay = on.hit[2] end
  else ay = snap(ay, g) end
  on.at = { ax, ay, az }
  local path = o and P._prop_path(o[2])
  on.key = o and string.format("%s %.2f %.2f %.2f %.0f %.0f %.0f", o[2], ax, ay, az, on.yaw, on.pitch, on.roll)

  if pressed & PAD.A ~= 0 or key("ENTER") then place_here() end
  if pressed & PAD.X ~= 0 or key("DELETE") then delete_near() end
  if pressed & PAD.B ~= 0 or key("BACKSPACE") then P.creator_stop(); return end
  if key("T") then P.creator_stop(true); return end

  -- the preview: a new one only when something changed, the last has arrived, and not more than ten a second
  if not o then return end
  local ok = ready(path)
  if ok == false then on.status = "This one can't be placed: pick another"; return end
  if ok == nil then on.status = "Loading " .. o[1] .. "..."; return end
  on.status = nil
  local ng = S.next_ghost
  if ng then
    if settle(ng) then retire(S.ghost); S.ghost, S.next_ghost = ng, nil; on.swapped = on.frames
    else ng.wait = (ng.wait or 0) + 1; if ng.wait > 120 then retire(ng); S.next_ghost = nil end end
    return
  end
  if on.wait_ground then return end
  if on.key == on.held then return end   -- just placed: the placed one shows where it is
  on.held = nil
  if on.key ~= on.still_key then on.still_key, on.still = on.key, 0 else on.still = (on.still or 0) + 1 end
  if (S.ghost and S.ghost.key == on.key) or on.still < 12 or on.frames - (on.last or -99) < 30 then return end
  on.last = on.frames
  local r2 = spawn(path, ax, ay, az, on.yaw, on.pitch, on.roll)
  if r2 then S.next_ghost = born({ rec = r2, gen = S.gen, key = on.key, ghostly = true }) end
end

-- The panel while the menu is closed.
function P.creator_lines()
  local on = S.on
  if not on then return nil end
  local o = pick()
  local lines = {
    { label = "Creator: " .. (o and o[1] or "nothing picked"), value = #S.placed .. " / " .. CR.MAX, colour = "title", value_colour = "off" },
    { label = string.format("Turn %.0f  tilt %.0f  roll %.0f%s", on.yaw, on.pitch, on.roll, (on.onground and "  on the ground, " or "  free, ") .. on.dist .. " m out"), colour = "row" },
    { label = "Pad: A place, X delete, Y ground or free, D-pad turn and tilt, hold LB: roll and distance, LB or RB tap: object, B leave", colour = "help" },
    { label = "Keys: Enter place, Delete delete, G ground, arrows turn and tilt, Q E roll, R F distance, PgUp PgDn object, T leave and go there, Backspace leave", colour = "help" },
  }
  local m = S.msg or on.status or (on.far and "That's as far as it goes from you: 150 m")
  if m then lines[#lines + 1] = { label = m, colour = "status" } end
  return lines
end

return CR
