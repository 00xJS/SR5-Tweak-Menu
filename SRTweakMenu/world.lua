-- SR5 Tweak Menu - the clock and pausing the world.
--
-- The clock: its update (+1AFB5A0) advances it by [+36F6210] (game minutes a
-- second, 15) unless the lock byte +36F6216 is set. The game's own systems
-- set and clear that lock too (missions, cutscenes), so a frozen clock is
-- locked again every frame. Clock speed rewrites the rate the same way.
-- Pause world is the game's own pause (gml_game_pause): everything stops,
-- you included; the menu keeps working.

local Wd = { freeze_clock = false, clock_speed = 1, pause = false, never_wanted = false, empty_streets = false }
local LOCK, RATE = 0x36F6216, 0x36F6210
local base_rate, written_rate, paused, streets_off

function Wd.update(frame)
  if Wd.freeze_clock then
    wml.write_u8(wml.base + LOCK, 1)
    Wd.locked = true
  elseif Wd.locked then
    wml.write_u8(wml.base + LOCK, 0)
    Wd.locked = false
  end
  if frame % 30 == 0 then
    local rate = wml.read_f32(wml.base + RATE)
    if Wd.clock_speed ~= 1 then
      -- a rate we didn't write is the game's own
      if not written_rate or math.abs(rate - written_rate) > 1e-4 then base_rate = rate end
      written_rate = base_rate * Wd.clock_speed
      if math.abs(rate - written_rate) > 1e-4 then wml.write_f32(wml.base + RATE, written_rate) end
    elseif written_rate then
      if base_rate and math.abs(rate - written_rate) < 1e-4 then wml.write_f32(wml.base + RATE, base_rate) end
      written_rate, base_rate = nil, nil
    end
  end
  if Wd.pause ~= (paused or false) then
    wml.game("gml_game_pause(" .. tostring(Wd.pause) .. ")")
    paused = Wd.pause
  end
  if frame % 60 == 40 and (Wd.empty_streets or streets_off) then Wd.update_streets() end
end

-- Empty streets: the spawn manager *(+3C438D0) has a "no ambient" bit (0x40)
-- for people (+0x7DB8) and vehicles (+0x7DBC), as the game's own disable-
-- ambient nodes (+B260A0, +B26140) set it; +AF90F0 / +AFB9F0 (manager, 0)
-- then remove the ones that are out there and may go (not the car you've
-- taken: with 1 they'd all go). Missions use the same bit, so it's set again
-- every second while on, and cleared only if we set it.
local MGR, PEDS, CARS = 0x3C438D0, 0x7DB8, 0x7DBC
function Wd.update_streets()
  local mgr = wml.read_u64(wml.base + MGR)
  if mgr == 0 then return end
  if Wd.empty_streets then
    for _, off in ipairs({ PEDS, CARS }) do
      local v = wml.read_u32(mgr + off)
      if v & 0x40 == 0 then wml.write_u32(mgr + off, v | 0x40) end
    end
    wml.call(wml.base + 0xAF90F0, mgr, 0)
    wml.call(wml.base + 0xAFB9F0, mgr, 0)
    streets_off = true
  elseif streets_off then
    for _, off in ipairs({ PEDS, CARS }) do wml.write_u32(mgr + off, wml.read_u32(mgr + off) & ~0x40 & 0xFFFFFFFF) end
    streets_off = false
  end
end

-- Notoriety: the game's table, as notoriety_get_highest_non_zero_faction
-- (+A0E690) reads it: *(+2F23FF0), count u16 at +2F23FF8, 0x178 an entry;
-- +E8 the faction's name hash (the binding pairs it with gml_faction's class
-- hash as an info id), +EC points, +F0 level (non-zero while you have
-- notoriety), +F4 / +F8 min / max level; byte +15B marks a temporary entry
-- (removed at the next reset): never written.
local NOTO, NOTO_COUNT = 0x2F23FF0, 0x2F23FF8
-- The name hashes of the factions you have notoriety with (nil: none).
function Wd.wanted()
  local tbl, n = wml.read_u64(wml.base + NOTO), wml.read_u16(wml.base + NOTO_COUNT)
  if tbl == 0 or n == 0 or n > 64 then return nil end
  local out
  for i = 0, n - 1 do
    local e = tbl + i * 0x178
    if wml.read_u32(e + 0xF0) ~= 0 and wml.read_u8(e + 0x15B) == 0 then
      out = out or {}
      out[#out + 1] = wml.read_u32(e + 0xE8)
    end
  end
  return out
end

function Wd.any_on() return Wd.empty_streets or streets_off or Wd.freeze_clock or Wd.clock_speed ~= 1 or Wd.pause or Wd.locked or written_rate ~= nil or paused end

return Wd
