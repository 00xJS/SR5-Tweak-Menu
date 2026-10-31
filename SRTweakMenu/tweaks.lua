-- SR5 Tweak Menu - settings kept for next time.
--
-- Every setting row (weapon and player settings, the menu's own) is saved by the
-- label of its picked option to TweakMenu\saved_tweaks.txt by Settings > Save tweaks,
-- and picked again when the menu starts. SR5TM_SESSION is what's set this session and
-- comes first, so a reload of the menu's files keeps it. Cheats aren't saved:
-- they're the game's, and it keeps its own.

local T = {}
local FILE = wml.root .. "\\saved_tweaks.txt"
T.saved = {}

function T.load()
  T.saved = {}
  local f = io.open(FILE, "r")
  if not f then return end
  for line in f:lines() do
    local k, v = line:match("^(.-)=(.*)$")
    if k then T.saved[k] = v end
  end
  f:close()
end

function T.save(rows)
  local lines = {}
  for _, row in ipairs(rows) do
    if row.options and row.save_key then lines[#lines + 1] = row.save_key .. "=" .. row.options[row.sel][1] end
  end
  table.sort(lines)
  local f = io.open(FILE, "w")
  if not f then return false end
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
  return true
end

-- The saved option's index for a row, or nil.
function T.pick(row)
  local want = row.save_key and ((SR5TM_SESSION and SR5TM_SESSION[row.save_key]) or T.saved[row.save_key])
  if not want then return nil end
  for i, o in ipairs(row.options) do if o[1] == want then return i end end
  return nil
end

function T.forget()
  os.remove(FILE)
  T.saved = {}
end

T.load()
return T
