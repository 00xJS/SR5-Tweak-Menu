-- SR5 Tweak Menu - main loop.
--
-- Runs the menu every frame. With dev_probe on (mod.ini) it also runs the
-- live probe: anything written to TweakMenu\probe_in.lua is run here (with
-- `game`, a shortcut for wml.game, and `dump`), what it prints goes to
-- TweakMenu\probe_out.txt, and the input is renamed to probe_done.lua.

local probe_on = wml.setting("dev_probe", false)
local probe_in = wml.root .. "\\probe_in.lua"
local probe_out = wml.root .. "\\probe_out.txt"

local function show(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

-- game(code) -> ok, ...  (code runs in the game's Lua 5.1; use `return`)
function game(code) return wml.game(code) end

-- dump(...): the values game() returned, as one line.
function dump(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = show((select(i, ...))) end
  return table.concat(t, ", ")
end

MENU = require("menu")

local tick = 0
local function run_probe()
  local f = io.open(probe_in, "r")
  if not f then return end
  local code = f:read("a")
  f:close()
  os.remove(wml.root .. "\\probe_done.lua")
  os.rename(probe_in, wml.root .. "\\probe_done.lua")
  wml.log("probe: running " .. #code .. " bytes")
  local out = {}
  local env = setmetatable({
    print = function(...)
      local t = {}
      for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
      out[#out + 1] = table.concat(t, "\t")
    end,
  }, { __index = _G })
  local fn, err = load(code, "=probe", "t", env)
  local ok, res = false, err
  if fn then ok, res = pcall(fn) end
  if not ok then out[#out + 1] = "ERROR: " .. tostring(res) end
  local o = io.open(probe_out, "w")
  if o then o:write(table.concat(out, "\n"), "\n"); o:close() end
end

local menu_error
wml.on_frame(function()
  -- a menu error mustn't stop the probe, or nothing can be fixed live
  local ok, err = pcall(MENU.update)
  if not ok and err ~= menu_error then menu_error = err; wml.log("menu error: " .. tostring(err)) end
  tick = tick + 1
  if probe_on and tick % 15 == 0 then run_probe() end
end)

wml.log("main.lua loaded; probe " .. (probe_on and "on" or "off"))
