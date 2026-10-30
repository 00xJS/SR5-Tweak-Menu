-- SR5 Tweak Menu - the game's own cheats.
--
-- Saints Row (2022) has 43 cheats (the phone's Cheats app, vdo_cheat_app.lua).
-- Each is a cheat_info object; the app lists them with
-- vlib_info_object:ipairs("cheat_info") and calls cheat_activate(info),
-- which turns a toggle cheat on or off and fires a one-shot one.
-- tostring(info) is `Info: <crc> : "name"`: that's how we find one again.
-- Cheats whose m_allow_progression is false are "spicy".
--
-- Spicy flags (bytes in the exe's data; the game's own setters are
-- +662D70 / +662DA0, which write all three):
--   +5BE2B65  spicy cheats allowed this session. cheat_can_activate lets a
--             spicy cheat run only while it's set, and the achievement code
--             (+AD7F40) skips unlocking while it's set.
--   +5BEF714  set alongside it.
--   +3111664  "this save has cheated": sticky, and saved with the game
--             (save section cheat_savegame_state).
-- Keeping the save clean (keep_clean): +3111664 stays 0, so saves aren't
-- marked; the session flags are set only for the moment a spicy cheat is
-- used or while one is on, and cleared again after.

local C = { list = {}, by_name = {}, loaded = false }
local SPICY_SESSION, SPICY_SESSION2, SAVE_CHEATED = 0x5BE2B65, 0x5BEF714, 0x3111664

-- Runs code in the game's Lua; returns its results, or nil and logs.
local function game(code)
  local r = table.pack(wml.game(code))
  if not r[1] then wml.log("cheats: game Lua error: " .. tostring(r[2])); return nil end
  return table.unpack(r, 2, r.n)
end

function C.load()
  C.list, C.by_name = {}, {}
  local count = game([[local n = 0 for _ in vlib_info_object:ipairs("cheat_info") do n = n + 1 end return n]])
  if not count or count == 0 then return false end
  for first = 1, count, 8 do
    local r = table.pack(game([[
      local i, o = 0, {}
      for _, info in vlib_info_object:ipairs("cheat_info") do
        i = i + 1
        if i >= ]] .. first .. [[ and i < ]] .. (first + 8) .. [[ then
          local spicy = info.m_allow_progression
          o[#o + 1] = tostring(info)
          o[#o + 1] = not (spicy and spicy:get_bool())
          o[#o + 1] = cheat_is_toggle(info) and true or false
        end
      end
      return unpack(o)
    ]]))
    for j = 1, r.n, 3 do
      local id = r[j]
      local name = id and id:match('"(.*)"')
      if name then
        local c = { id = id, name = name, spicy = r[j + 1], toggle = r[j + 2], active = false }
        C.list[#C.list + 1] = c
        C.by_name[name] = c
      end
    end
  end
  C.loaded = #C.list > 0
  wml.log("cheats: " .. #C.list .. " found")
  return C.loaded
end

-- Reads every toggle cheat's state (one game call).
function C.refresh()
  if not C.loaded then return end
  local r = table.pack(game([[
    local o = {}
    for _, info in vlib_info_object:ipairs("cheat_info") do
      o[#o + 1] = tostring(info)
      o[#o + 1] = cheat_is_active(info) and true or false
    end
    return unpack(o)
  ]]))
  for j = 1, r.n, 2 do
    local name = r[j] and r[j]:match('"(.*)"')
    if name and C.by_name[name] then C.by_name[name].active = r[j + 1] end
  end
end

function C.spicy_on() return game("return cheat_is_spicy_activated() and true or false") == true end

-- Lets spicy cheats run (the session flag only, not the save's mark).
function C.allow_spicy() wml.write_u8(wml.base + SPICY_SESSION, 1) end

-- Any spicy toggle cheat on?
function C.spicy_active()
  for _, c in ipairs(C.list) do if c.spicy and c.toggle and c.active then return true end end
  return false
end

-- Clears the save's mark, and the session flags when no spicy cheat is on.
-- Returns true if the save's mark had been set.
function C.keep_clean(clear_session)
  local marked = wml.read_u8(wml.base + SAVE_CHEATED) ~= 0
  if marked then wml.write_u8(wml.base + SAVE_CHEATED, 0) end
  if clear_session then
    wml.write_u8(wml.base + SPICY_SESSION, 0)
    wml.write_u8(wml.base + SPICY_SESSION2, 0)
  end
  return marked
end

-- The player's cash (the HUD wallet reads it the same way), or nil.
function C.cash()
  local v = game("local f = rawget(_G, 'get_currency_available') return f and f(CURRENCY_CASH)")
  return type(v) == "number" and v or nil
end

-- 1234567 -> "$1,234,567"
function C.money(v)
  if not v then return "?" end
  local s = tostring(math.floor(v))
  local neg = s:sub(1, 1) == "-"
  if neg then s = s:sub(2) end
  s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (neg and "-$" or "$") .. s
end

-- Fires (or toggles) a cheat by name. Returns true if the game took it.
function C.activate(name)
  local c = C.by_name[name]
  if not c then return false end
  local ok = game([[
    for _, info in vlib_info_object:ipairs("cheat_info") do
      if tostring(info) == ]] .. string.format("%q", c.id) .. [[ then
        if not cheat_can_activate(info) then return false end
        cheat_activate(info)
        return true
      end
    end
    return false
  ]])
  if ok and c.toggle then c.active = not c.active end
  return ok == true
end

function C.set(name, on)
  local c = C.by_name[name]
  if not c or not c.toggle then return false end
  if c.active == on then return true end
  return C.activate(name)
end

return C
