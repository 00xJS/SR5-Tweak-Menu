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
  for _, e in ipairs(entries) do if e.object == "default" then by_path[e.path] = e end end
  WS.loaded = #entries > 0
  wml.log("wingsuit: " .. #entries .. " values")
  return WS.loaded
end

local function wanted(e)
  local v, s, w = e.orig, WS.set, e.what
  if w == "cooldown" then
    if s.cooldown == "none" then return 0.05 elseif s.cooldown == "short" then return math.min(v, 2) end
    return v
  elseif w == "boost" then return v * s.boost
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

function WS.restore()
  for _, e in ipairs(entries) do if e.written and e.written ~= e.orig then V.write(e.addr, e.t, e.orig) end e.written = nil end
end

function WS.any_on()
  local s = WS.set
  return s.cooldown ~= 1 or s.boost ~= 1 or s.speed ~= 1 or s.glide ~= "game"
end

return WS
