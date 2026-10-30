-- SR5 Tweak Menu - the clock and pausing the world.
--
-- The clock: its update (+1AFB5A0) advances it by [+36F6210] (game minutes a
-- second, 15) unless the lock byte +36F6216 is set. The game's own systems
-- set and clear that lock too (missions, cutscenes), so a frozen clock is
-- locked again every frame. Clock speed rewrites the rate the same way.
-- Pause world is the game's own pause (gml_game_pause): everything stops,
-- you included; the menu keeps working.

local Wd = { freeze_clock = false, clock_speed = 1, pause = false, never_wanted = false }
local LOCK, RATE = 0x36F6216, 0x36F6210
local base_rate, written_rate, paused

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
end

-- Notoriety: the game's table, as notoriety_get_highest_non_zero_faction
-- (+A0E690) reads it: *(+2F23FF0), count u16 at +2F23FF8, 0x178 an entry;
-- +E8 the faction, +EC its level, +F0 non-zero while you have notoriety,
-- byte +15B set for a faction that's switched off. +E8 is the faction's name
-- hash (the binding pairs it with gml_faction's class hash as an info id).
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

function Wd.any_on() return Wd.freeze_clock or Wd.clock_speed ~= 1 or Wd.pause or Wd.locked or written_rate ~= nil or paused end

return Wd
