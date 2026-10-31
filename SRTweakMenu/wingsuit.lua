-- SR5 Tweak Menu - wingsuit tweaks, on the game's wingsuit data.
--
-- wingsuit_info (3: default, mission_specific, vehicle_surf) holds its
-- tuning in m_contents: boost (speed 38, accel 20, duration 1.25 s, cooldown
-- 15 s), terminal velocity (44, the top speed unless boosting), gravity
-- (0.5 level, 1.0 diving), base speed decay, stall speed and duration.

local V = require("vdata")
local WS = { loaded = false }
WS.set = { cooldown = 1, boost = 1, speed = 1, glide = "game" }

local FIELDS = {
  { path = "m_contents.m_boost_cooldown", what = "cooldown" },
  { path = "m_contents.m_bounce_boost_cooldown", what = "cooldown" },
  { path = "m_contents.m_boost_speed", what = "boost" },
  { path = "m_contents.m_boost_accel", what = "boost" },
  { path = "m_contents.m_boost_duration", what = "boost" },
  { path = "m_contents.m_terminal_velocity_lateral", what = "speed" },
  { path = "m_contents.m_initial_speed", what = "speed" },
  { path = "m_contents.m_landing_speed_max", what = "speed" },
  { path = "m_contents.m_gravity_min_pct", what = "gravity" },
  { path = "m_contents.m_gravity_max_pct", what = "gravity" },
  { path = "m_contents.m_base_speed_decay", what = "decay" },
  { path = "m_contents.m_stall_speed", what = "stall" },
  { path = "m_contents.m_stall_duration", what = "stall" },
}
local entries = {}

local by_path = {}   -- "default" wingsuit's entries by field path
function WS.load()
  entries = V.collect("wingsuit_info", FIELDS)
  by_path = {}
  -- kept in a global: a reload of this file would otherwise read what it wrote as the game's own
  SR5TM_WS_ORIG = SR5TM_WS_ORIG or {}
  for _, e in ipairs(entries) do
    SR5TM_WS_ORIG[e.addr] = SR5TM_WS_ORIG[e.addr] or e.orig
    e.orig = SR5TM_WS_ORIG[e.addr]
    if e.object == "default" then by_path[e.path] = e end
  end
  WS.loaded = #entries > 0
  wml.log("wingsuit: " .. #entries .. " values")
  return WS.loaded
end

local TERMINAL_44 = 44   -- m_terminal_velocity_lateral, the game's
local function wanted(e)
  local v, s, w = e.orig, WS.set, e.what
  if w == "cooldown" then
    if s.cooldown == "none" then return 0.05 elseif s.cooldown == "short" then return math.min(v, 2) end
    return v
  elseif w == "boost" then
    -- boost speed is a cap, and if it's under top speed a boost slows you down
    if e.path == "m_contents.m_boost_speed" and (s.boost ~= 1 or s.speed ~= 1) then return math.max(v * s.boost, TERMINAL_44 * s.speed * 1.25) end
    return v * s.boost
  elseif w == "speed" then return v * s.speed
  elseif w == "gravity" then
    if s.glide == "floaty" then return v * 0.5
    elseif s.glide == "level" then return v * 0.12
    elseif s.glide == "climb" then return -0.15 end
    return v
  elseif w == "decay" then
    if s.glide == "floaty" then return v * 0.5 elseif s.glide == "level" or s.glide == "climb" then return 0 end
    return v
  elseif w == "stall" then
    if s.glide == "level" or s.glide == "climb" then return 0 end
    return v
  end
  return v
end

function WS.apply()
  if not WS.loaded and not WS.load() then return false end
  for _, e in ipairs(entries) do
    local want = wanted(e)
    if want ~= (e.written or e.orig) then V.write(e.addr, e.t, want) end
    e.written = want
  end
  return true
end

-- The player's wingsuit component (type 0xB5) keeps its own copy of these
-- numbers (angles in radians), made when the wingsuit sets up; it's written
-- too, every half second while a setting is on.
-- Offsets in the copy, by the data field they copy. The originals come from
-- the "default" wingsuit's own data (not the copy, which may have been made
-- from data we'd already changed).
local COPY = {
  { 0xB8, "m_contents.m_boost_cooldown" }, { 0x5C, "m_contents.m_bounce_boost_cooldown" },
  { 0xB0, "m_contents.m_boost_duration" }, { 0xB4, "m_contents.m_boost_speed" }, { 0xBC, "m_contents.m_boost_accel" },
  { 0xAC, "m_contents.m_terminal_velocity_lateral" }, { 0xC8, "m_contents.m_initial_speed" }, { 0x100, "m_contents.m_landing_speed_max" },
  { 0xDC, "m_contents.m_gravity_min_pct" }, { 0xE0, "m_contents.m_gravity_max_pct" }, { 0x78, "m_contents.m_base_speed_decay" },
  { 0xA0, "m_contents.m_stall_duration" }, { 0xA4, "m_contents.m_stall_speed" },
}
function WS.update_copy(P)
  if not WS.loaded and not WS.load() then return end
  local c = P.component(0xB5)
  if not c then return end
  for _, cp in ipairs(COPY) do
    local e = by_path[cp[2]]
    if e then
      local want = wanted(e)
      if wml.read_f32(c + cp[1]) ~= want then wml.write_f32(c + cp[1], want) end
    end
  end
end

-- Pulling up in Climb. Recorded in flight, gravity alone can't turn a descent into a climb. Turning the suit's
-- real velocity (component 0x86, +0 +4 +8) towards up, keeping its speed, does: a 16 m/s descent became an 11 m/s
-- climb over 3 s at full forward speed. The game's body pitch (+0x10 there) follows it down to the neutral pitch,
-- 0xB5 +0x94 in radians, positive nose down (83 degrees in the data is 0.122), so that's let go nose up while pulling.
-- +0x98 is how fast the body gets there: 5 degrees a second in the game, left behind by a climb, so faster while pulling.
local PULL_ANGLE, PULL_RATE, PULL_NEUTRAL, GAME_NEUTRAL, PULL_SPEED = 0.52, 1.2, -0.35, 0.12217, 25
local PULL_NEUTRAL_RATE, GAME_NEUTRAL_RATE = 0.5, 0.08727
local pulled
function WS.update_lift(P)
  local pull = 0
  local open = false
  if WS.set.glide == "climb" and not P.no_clip then
    local e = P.object()
    local gail = e and wml.call(wml.base + 0x1534D80, e)
    if gail and gail ~= 0 and wml.read_u32(gail + 0x324) == wml.read_u32(wml.base + 0x3C20F9C) then
      open = true
      local _, _, _, _, ly = wml.pad()
      pull = WS.test_pull or (wml.key_down("S") and 1) or (ly and ly < -7849 and (-ly - 7849) / 24919) or 0
    end
  end
  if pull <= 0 then
    if pulled then
      local c = P.component(0xB5)
      if c then wml.write_f32(c + 0x94, GAME_NEUTRAL); wml.write_f32(c + 0x98, GAME_NEUTRAL_RATE) end
      pulled = false
    end
    return
  end
  local a, c = P.component(0x86), P.component(0xB5)
  if not a or not c then return end
  wml.write_f32(c + 0x94, PULL_NEUTRAL * pull)
  wml.write_f32(c + 0x98, PULL_NEUTRAL_RATE)
  pulled = true
  local vx, vy, vz = wml.read_f32(a), wml.read_f32(a + 4), wml.read_f32(a + 8)
  local h = math.sqrt(vx * vx + vz * vz)
  local speed = math.max(math.sqrt(h * h + vy * vy), PULL_SPEED)
  local now = math.atan(vy, math.max(h, 0.01))
  local target = PULL_ANGLE * pull
  if now >= target then return end
  local angle = math.min(target, now + PULL_RATE * wml.read_f32(wml.base + 0x2E80848))
  local k = speed * math.cos(angle) / math.max(h, 0.01)
  wml.write_f32(a, vx * k)
  wml.write_f32(a + 4, speed * math.sin(angle))
  wml.write_f32(a + 8, vz * k)
end

-- Repeat boosts. The game allows one boost a flight: bit 0x40 of +0x54 on component 0x86 is set by each
-- boost and only cleared when you land and fly again. The 15 s cooldown never runs: its only reader sits
-- behind an inverted null check in the game. So the bit's cleared here while not boosting, unless an activity
-- has turned boosts off (0x80). "Every 2 s" also arms the gate's timer, 0xB5 +0x144 in ms. And +0x18,
-- the boost's clock, isn't reset by a new boost, so a repeat would end early: it's zeroed here.
local was_boosting
function WS.update_boost(P)
  local mode = WS.set.cooldown
  if mode == 1 then was_boosting = nil; return end
  local a, c = P.component(0x86), P.component(0xB5)
  if not a or not c then return end
  local f = wml.read_u8(a + 0x54)
  local boosting = f & 0x20 ~= 0
  if boosting and not was_boosting then wml.write_f32(a + 0x18, 0) end
  if not boosting and f & 0xC0 == 0x40 then
    if mode == "short" then wml.write_u32(c + 0x144, wml.read_u32(wml.base + 0x2E80878) + 2000) end
    wml.write_u8(a + 0x54, f & 0xBF)
  end
  -- held down: the boost would start and end in one frame, with the clock already past its end
  if mode == "none" and not boosting and wml.read_u8(c + 0x16C) & 0x80 ~= 0 then wml.write_f32(a + 0x18, 0) end
  was_boosting = boosting
end

function WS.restore()
  for _, e in ipairs(entries) do if e.written and e.written ~= e.orig then V.write(e.addr, e.t, e.orig) end e.written = nil end
end

function WS.any_on()
  local s = WS.set
  return s.cooldown ~= 1 or s.boost ~= 1 or s.speed ~= 1 or s.glide ~= "game"
end

return WS
