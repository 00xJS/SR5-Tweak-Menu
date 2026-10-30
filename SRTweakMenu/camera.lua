-- SR5 Tweak Menu - the camera: turn speed past the options' limit.
--
-- The game keeps the turn speeds it uses as floats: mouse +2EAF170 (the
-- options slider gives 0.001 to 0.13), controller x +2EAFA10, y +2EAEE20.
-- It writes them again when the option is changed, so they're checked every
-- second: a value we didn't write is the game's own, and the multiplier is
-- applied to that.

local Cam = { turn = 1 }
local SPEEDS = { 0x2EAF170, 0x2EAFA10, 0x2EAEE20 }
local base, written = {}, {}

function Cam.update(frame)
  if frame % 60 ~= 50 then return end
  for _, off in ipairs(SPEEDS) do
    local a = wml.base + off
    local now = wml.read_f32(a)
    if Cam.turn ~= 1 then
      if not written[off] or math.abs(now - written[off]) > 1e-6 then base[off] = now end
      written[off] = base[off] * Cam.turn
      if math.abs(now - written[off]) > 1e-6 then wml.write_f32(a, written[off]) end
    elseif written[off] then
      if base[off] and math.abs(now - written[off]) <= 1e-6 then wml.write_f32(a, base[off]) end
      written[off], base[off] = nil, nil
    end
  end
end

function Cam.any_on() return Cam.turn ~= 1 or next(written) ~= nil end

return Cam
