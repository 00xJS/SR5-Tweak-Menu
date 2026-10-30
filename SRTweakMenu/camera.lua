-- SR5 Tweak Menu - the camera: turn speed past the options' limit, brightness.
--
-- The game keeps the turn speeds it uses as floats: mouse +2EAF170 (the
-- options slider gives 0.001 to 0.13), controller x +2EAFA10, y +2EAEE20.
-- It writes them again when the option is changed, so they're checked every
-- second: a value we didn't write is the game's own, and the multiplier is
-- applied to that.
--
-- Brightness: gml_engine_render_lock_exposure_value() makes the renderer copy
-- its current exposure into +2EAF178 on the next frame and use that from then
-- on (6.7 read live in daylight); the menu then shifts it. Locking stops the
-- game's own adjustment (going indoors, night), so it's undone with
-- gml_engine_render_unlock_exposure_value() when set back to the game's.

local Cam = { turn = 1, bright = 0 }
local SPEEDS = { 0x2EAF170, 0x2EAFA10, 0x2EAEE20 }
local EXPOSURE = 0x2EAF178
local base, written = {}, {}
local locked, lock_wait, exp_base, exp_written

local function update_bright()
  local a = wml.base + EXPOSURE
  if Cam.bright ~= 0 then
    if not locked then
      wml.game("gml_engine_render_lock_exposure_value()")
      locked, lock_wait = true, 2
      return
    end
    if lock_wait > 0 then lock_wait = lock_wait - 1; return end
    local now = wml.read_f32(a)
    if not exp_base or not exp_written or math.abs(now - exp_written) > 1e-4 then exp_base = now end
    exp_written = exp_base + Cam.bright
    if math.abs(now - exp_written) > 1e-4 then wml.write_f32(a, exp_written) end
  elseif locked then
    wml.game("gml_engine_render_unlock_exposure_value()")
    locked, exp_base, exp_written = false, nil, nil
  end
end

function Cam.update(frame)
  if (Cam.bright ~= 0 or locked) and frame % 10 == 3 then update_bright() end
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

function Cam.any_on() return Cam.turn ~= 1 or next(written) ~= nil or Cam.bright ~= 0 or locked end

return Cam
