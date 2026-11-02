-- SR5 Tweak Menu - co-op: who's in the session, which rows are safe with a partner in, and a log.
--
-- The session is read from memory, the same fields the game's multi_is_* calls read, so the check
-- costs no game calls:
--   *(+5CB4D10)  session. +D80 connections (you count), +D90 joining, +DA0/+DA8 the host's list:
--                different means you're a guest (multi_is_client +169FDD0, multi_is_coop_active +169FC50)
--   +5CB4558     multiplayer on (multi_is_host_with_clients +169FD00)
--   +5CB44BC     current error (multi_get_current_error +16A02F0)
--   +5BE6F91     waiting for a client (multi_stop_waiting_for_client +A0C760)
--   +2EB2374     open to co-op (multi_session_open_to_coop +16A2450)
--   +491BF40     player slots, 8 of 0x24, first dword the player's id, 8 empty (+1B43280)
-- None of this has been read with a real partner in yet.

local K = { mode = "solo", safe = true, partner = nil, count = 0, pending = 0 }

local B = wml.base
local SESSION, MP_ON, ERROR, WAITING, OPEN, SLOTS = 0x5CB4D10, 0x5CB4558, 0x5CB44BC, 0x5BE6F91, 0x2EB2374, 0x491BF40
local GET_PLAYER = 0x1B432F0

-- ------------------------------------------------------------------ the log
local FILE = wml.root .. "\\coop_log.txt"
local MAX_LOG = 256 * 1024
do
  local f = io.open(FILE, "r")
  if f then
    local size = f:seek("end")
    f:close()
    if size and size > MAX_LOG then
      os.remove(FILE .. ".old")
      os.rename(FILE, FILE .. ".old")
    end
  end
end
function K.log(text)
  local f = io.open(FILE, "a")
  if not f then return end
  f:write(os.date("%Y-%m-%d %H:%M:%S  "), text, "\n")
  f:close()
end
K.log("menu loaded")

-- ------------------------------------------------------------------ the session
local function s32(v) return v >= 0x80000000 and v - 0x100000000 or v end

-- A partner's object, or nil. Id 0 is always you; anyone else comes from the slots.
local function find_partner()
  local ok, me = pcall(wml.call, B + GET_PLAYER, 0)
  if not ok then return nil end
  for i = 0, 7 do
    local id = wml.read_u32(B + SLOTS + i * 0x24)
    if id ~= 8 and id ~= 0 then
      local got, o = pcall(wml.call, B + GET_PLAYER, id)
      if got and o ~= 0 and o ~= me then return o end
    end
  end
  return nil
end

local function read_session()
  local s = wml.read_u64(B + SESSION)
  local count, pending, guest = 0, 0, false
  if s ~= 0 then
    count, pending = wml.read_u32(s + 0xD80), wml.read_u32(s + 0xD90)
    guest = wml.read_u64(s + 0xDA0) ~= wml.read_u64(s + 0xDA8)
  end
  local on = wml.read_u8(B + MP_ON) ~= 0
  local mode = "solo"
  if guest then mode = "guest"
  elseif count > 1 or (on and count + pending > 1) then mode = "host" end
  return mode, count, pending, on
end

-- The vehicle someone's in, by the steps of enemy_get_occupied_vehicle (+A011D0): +4897A0 their vehicle link,
-- +1AB52F0 its vehicle component, and from its slot in that pool (+5CB3F70, +0xA90) to the object. Nil on foot.
function K.vehicle_of(e)
  local ok, link = pcall(wml.call, B + 0x4897A0, e)
  if not ok or link == 0 then return nil end
  local got, c = pcall(wml.call, B + 0x1AB52F0, link)
  if not got or c == 0 then return nil end
  local pool = wml.read_u64(B + 0x5CB3F70) + 0xA90
  local size = wml.read_u32(pool + 0xB4)
  if size == 0 then return nil end
  local slot = (c - wml.read_u64(pool + 0x28)) // size
  local index = wml.read_u32(wml.read_u64(pool + 0x78) + slot * 4) & 0x3FFFFFFF
  if index == 0x3FFFFFFF then return nil end
  return wml.read_u64(B + 0x45E8458) + index * 0x90
end

function K.waiting() return wml.read_u8(B + WAITING) ~= 0 end
function K.open() return wml.read_u8(B + OPEN) ~= 0 end
function K.error_code() return s32(wml.read_u32(B + ERROR)) end

-- The error as the game words it.
function K.error_text()
  local code = K.error_code()
  if code == 0 then return nil end
  local ok, text = wml.game("return multi_get_current_error_text()")
  return ok and type(text) == "string" and text ~= "" and text or ("error " .. code)
end

local seen = {}
local function note(key, value, text)
  if seen[key] ~= value then
    if seen[key] ~= nil then K.log(text) end
    seen[key] = value
  end
end

-- Every half second or so (menu.lua). K.fake ("host" or "guest") stands in for a partner, for testing the limits alone.
function K.update(position)
  local mode, count, pending, on = read_session()
  if K.fake then mode = K.fake end
  if mode ~= K.mode then
    local x, y, z = position()
    K.log(string.format("session: %s to %s, %d connected, %d joining, at %s", K.mode, mode, count, pending, x and string.format("%.1f %.1f %.1f", x, y, z) or "nowhere"))
    K.mode = mode
  end
  K.count, K.pending = count, pending
  note("count", count, "connected: " .. count)
  note("pending", pending, "joining: " .. pending)
  note("on", on, "multiplayer " .. (on and "on" or "off"))
  local waiting = K.waiting()
  note("waiting", waiting, waiting and "waiting for partner" or "stopped waiting for partner")
  local open = K.open()
  note("open", open, open and "open to co-op" or "closed to co-op")
  local code = K.error_code()
  if seen.error ~= code then
    if seen.error ~= nil then K.log("error " .. code .. (code ~= 0 and (": " .. tostring(K.error_text())) or " (cleared)")) end
    seen.error = code
  end
  K.partner = mode ~= "solo" and not K.fake and find_partner() or nil
  note("partner", K.partner ~= nil, K.partner and "partner's character is here" or "partner's character is gone")
  -- their car, so rows on cars near leave it alone, and how far off they are. +5BE4ABC is the game's own "close together".
  K.partner_car = K.partner and K.vehicle_of(K.partner) or nil
  K.distance, K.close = nil, false
  if K.partner then
    local x, y, z = position()
    if x then
      local dx, dy, dz = s32(wml.read_u32(K.partner + 0x30)) / 10000 - x, s32(wml.read_u32(K.partner + 0x34)) / 10000 - y, s32(wml.read_u32(K.partner + 0x38)) / 10000 - z
      K.distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    end
    K.close = wml.read_u8(B + 0x5BE4ABC) ~= 0
  end
  note("close", K.close, K.close and "close together" or "apart")
end

-- Is our waypoint on them? Slot 0 of the GPS (+3BFA170, 0x1C each): +0xC target id, +0x18 active.
local function waypoint_on_partner()
  local slot = B + 0x3BFA170
  return K.partner ~= nil and wml.read_u8(slot + 0x18) ~= 0 and wml.read_u32(slot + 0xC) == wml.read_u32(K.partner + 0x58)
end

function K.in_coop() return K.mode ~= "solo" end
function K.partner_position()
  local o = K.mode ~= "solo" and find_partner()
  if not o then return nil end
  return s32(wml.read_u32(o + 0x30)) / 10000, s32(wml.read_u32(o + 0x34)) / 10000, s32(wml.read_u32(o + 0x38)) / 10000
end

-- ------------------------------------------------------------------ what's safe
-- "host": changes the shared world, so a guest can't. "off": can break the session for both of you.
-- Rows not named stay on: they change your own character, your own game's look and sound, or your own car.
-- Audited against the game's code (research_coop_audit.md), where it could be: a row is freed only when the code shows the game
-- routes a guest's press to whoever owns the object. The rest are judgement. No row has been tried with a partner yet.
local WHOLE_TAB = { People = "host", World = "host" }
local WHOLE_PAGE = {
  ["Vehicles/Get a vehicle"] = "host",
  ["World/Missions and side jobs"] = "off",
  ["Settings/Game"] = "host",
  ["Settings/Difficulty"] = "host",
  ["Settings/Game data"] = "host",
  ["Settings/Developer switches"] = "off",
  ["Cheats/Traffic"] = "host",
  ["Cheats/World"] = "host",
  ["Cheats/Notoriety"] = "host",
  ["Co-op/Balance"] = "host",
}
local ROWS = {
  -- the clock and the whole world's speed run on both machines
  ["Pause world"] = "off", ["Only you move"] = "off", ["Game speed"] = "off", ["Slow motion button"] = "off", ["Vehicle time"] = "off",
  -- swaps your character, or deletes what a partner may be standing on or sitting in
  ["Play as last spawned"] = "off", ["Play as picked person"] = "off", ["Play as picked special"] = "off",
  ["Drop everyone near through ground"] = "off", ["Delete nearest car"] = "off",
  -- the game's delete does nothing unless you own the object (+192AB80), and the near list leaves your partner out
  ["Delete everyone near"] = "host",
  -- marked "can crash" alone
  ["Dual wield this gun"] = "off", ["Swap vehicle gun"] = "off",
  -- loads and cutscenes
  ["Play cutscene"] = "off", ["Pause / resume cutscene"] = "off", ["Load last save"] = "off", ["New save"] = "off",
  -- makes new things in the world
  ["Prop gun"] = "host", ["Shoot prop"] = "host", ["Money gun"] = "host", ["Black hole"] = "host",
  ["Drop cash"] = "host", ["Money rain"] = "host", ["Drop weapon"] = "host", ["Drop a car"] = "host", ["Build venture on lot"] = "host",
  -- the game refuses these on a guest anyway (the cheat gate): this only gives a clearer message
  ["Super Saints"] = "host", ["No traffic laws"] = "host", ["Heaven Bound"] = "host",
  -- no check in the game, and the same kind of code as the rows above
  ["Everyone near plays it"] = "host", ["Everyone near does an idle"] = "host", ["End idle near"] = "host", ["Stick nearest car on me"] = "host",
  -- always allowed: the way back, cleaning up, your own settings
  ["Back to yourself"] = false, ["Remove spawned people"] = false, ["Remove spawned vehicles"] = false, ["Remove all props"] = false, ["Remove last prop"] = false,
  ["Skip intro"] = false, ["Tutorial popups"] = false,
  -- the game sends a guest's press to whoever owns the object (RPC flags 2, or runs here and sends with 3), so these work for a guest.
  -- They also let a guest change the host's people. Read in code, not yet seen with a partner.
  ["Make everyone near target you"] = false, ["Stop targeting me"] = false, ["Stop fights near"] = false, ["Stun everyone near"] = false, ["Everyone near hunts you"] = false,
  ["Crowd around me"] = false, ["Stop crowding"] = false, ["Stop shooting"] = false, ["Order everyone near"] = false, ["Make everyone near follow you"] = false,
  ["Float everyone near"] = false, ["Poison everyone near"] = false, ["Dissolve everyone near"] = false, ["Short effect on everyone near"] = false, ["Lasting effect on everyone near"] = false,
  ["Lasting effect on you"] = false, ["Lasting effects off"] = false, ["Set everyone near on fire"] = false, ["Flaming look near"] = false, ["Flaming look near off"] = false,
  ["Trip everyone near"] = false, ["Revive everyone near"] = false, ["Downed, not dead"] = false,
  ["Drivers near floor it"] = false, ["Drivers near stay in"] = false, ["Hazard lights near"] = false, ["Sirens on near"] = false, ["Set off car alarms"] = false,
  ["Summon homie"] = false, ["Dismiss homies"] = false, ["Next homie outfit"] = false,
  ["Hide everyone near on minimap"] = false, ["Show everyone near on minimap"] = false, ["Give everyone near a behaviour"] = false, ["Screen filter"] = false,
  ["Get in nearest"] = false, ["Get out"] = false,
}

-- Marks every row (row.coop). Returns the marked ones, the only rows the limits ever need to look at.
function K.classify(tabs)
  local marked = {}
  local function mark(row, tab, page)
    local c = ROWS[row.label]
    if c == nil and page then c = WHOLE_PAGE[tab .. "/" .. page] end
    if c == nil then c = WHOLE_TAB[tab] end
    if c then row.coop = c; marked[#marked + 1] = row end
  end
  for _, t in ipairs(tabs) do
    for _, r in ipairs(t.rows) do
      if r.kind == "page" then
        if not r.live then for _, c in ipairs(r.rows) do mark(c, t.name, r.label) end end
      else
        mark(r, t.name, nil)
      end
    end
  end
  return marked
end

-- "host" or "off" when this row is stopped right now, else nil.
function K.blocked(row)
  local c = row.coop
  if not c or not K.safe or K.mode == "solo" then return nil end
  if c == "off" or K.mode == "guest" then return c end
  return nil
end
function K.why(c)
  return c == "off" and "Off in co-op" or "Host only"
end
function K.title()
  if K.mode == "solo" then return "" end
  return "   Co-op: " .. (K.mode == "host" and "host" or "guest")
end

-- ------------------------------------------------------------------ the tab's rows
function K.session_text()
  if K.mode == "solo" then
    if K.waiting() then return "Waiting for partner" end
    return K.open() and "Solo, open to co-op" or "Solo, closed"
  end
  local text = (K.mode == "host" and "Host" or "Guest") .. (K.pending > 0 and ", someone joining" or "")
  if K.distance then text = text .. string.format(", %d m%s", math.floor(K.distance + 0.5), K.close and ", close" or "") end
  return text
end
function K.partner_name()
  if K.mode == "solo" or K.fake then return nil end
  local ok, name = wml.game("return multi_get_connected_user_name()")
  return ok and type(name) == "string" and name ~= "" and name or nil
end

-- value, colour for a row of kind "coop"
function K.value(row)
  local a = row.act
  if a == "session" then return K.session_text(), K.mode == "solo" and "off" or "on"
  elseif a == "open" then return K.open() and "<  Open  >" or "<  Closed  >", K.open() and "on" or "off"
  elseif a == "wait" then return K.waiting() and "Waiting: Enter" or "Not waiting", K.waiting() and "on" or "off"
  elseif a == "error" then return K.error_code() ~= 0 and "Error: Enter" or "None", K.error_code() ~= 0 and "on" or "off"
  elseif a == "goto" then return K.mode == "solo" and "No partner" or "Enter", "off"
  elseif a == "pin" then
    if K.mode == "solo" then return "No partner", "off" end
    if waypoint_on_partner() then return "On: Enter clears", "on" end
    return "Enter", "off"
  end
  return "Enter", "off"
end

-- Pressing one. say(text, kind) shows it; P is the player module.
function K.press(row, say, P)
  local a = row.act
  if a == "session" then
    local text = K.session_text()
    local name = K.partner_name()
    say(text .. (name and (", with " .. name) or "") .. ", " .. K.count .. " connected")
  elseif a == "open" then
    local open = not K.open()
    local ok, err = wml.game(open and "multi_session_open_to_coop()" or "multi_session_close_to_coop()")
    if ok then K.log("menu: " .. (open and "opened" or "closed") .. " to co-op") end
    say(ok and (open and "Open to co-op" or "Closed to co-op") or tostring(err), ok and "status" or "warn")
  elseif a == "goto" then
    local x, y, z = K.partner_position()
    if not x then say("No partner to go to", "warn"); return end
    K.log(string.format("menu: go to partner at %.1f %.1f %.1f", x, y, z))
    say(P.teleport(x + 1.5, y, z) and "Going to your partner" or "Couldn't right now", "status")
  elseif a == "pin" then
    if not K.partner then say("No partner to mark", "warn"); return end
    if waypoint_on_partner() then
      wml.game("gps_stop()")
      K.log("menu: waypoint on partner off")
      say("Waypoint cleared")
      return
    end
    -- gps_start_node: target, gps type (0 yours), then race, moving target, hide marker, restrict height
    P.node(0x6B21A0, 0x29BDED0, { { u = wml.read_u32(K.partner + 0x58) }, { u = 0 }, { u = 0 }, { u = 1 }, { u = 0 }, { u = 1 } })
    K.log("menu: waypoint on partner on")
    say(waypoint_on_partner() and "Waypoint on your partner" or "The game didn't take the waypoint", waypoint_on_partner() and "status" or "warn")
  elseif a == "wait" then
    if not K.waiting() then say("The game isn't waiting for anyone"); return end
    local ok, err = wml.game("multi_stop_waiting_for_client()")
    K.log("menu: stop waiting, " .. tostring(ok))
    say(ok and "Stopped waiting for your partner" or tostring(err), ok and "status" or "warn")
  elseif a == "error" then
    local text = K.error_text()
    if not text then say("No error right now"); return end
    wml.game("multi_error_clear()")
    say(text .. " (cleared)", "warn")
  elseif a == "leave" then
    if K.mode == "solo" then say("You're not in a co-op session"); return end
    local ok, err = wml.game("multi_disconnect()")
    K.log("menu: leave co-op, " .. tostring(ok))
    say(ok and "Leaving co-op" or tostring(err), ok and "status" or "warn")
  elseif a == "mark" then
    K.log("MARK: something happened here")
    say("Marked in coop_log.txt")
  end
end

-- ------------------------------------------------------------------ balance
-- The game's own co-op numbers. *(+5BE37D8), the difficulty config, reads as (live, solo):
--   +BE0 reinforcement speed 1, +BE4 tough grunts 1.5, +BE8 tough specialists 1.5, +BEC your damage 0.7, +BF0 resistance scale 1.6
-- +6993E0 uses +BE0, +BEC and +BF0, only on the host, only with co-op in game and the near flag +5BE4ABC set (+698E90). It runs when
-- that flag changes, so a change takes hold the next time you part and meet again. +69A210 hands out +BE4 and +BE8 on the same terms.
-- The flag: closer than notoriety_system_config's near distance sets it, further than far clears it (+6FE9A0). Solo reads none of this,
-- so all of it can be set before a partner arrives. What +BF0 does to damage is a reading (it scales a negative level), not measured.
local NUMBER = { { "Game's", false }, { "0.5", 0.5 }, { "0.7", 0.7 }, { "1", 1 }, { "1.25", 1.25 }, { "1.5", 1.5 }, { "2", 2 }, { "3", 3 } }
local TIMES = { { "Game's", 1 }, { "x0.5", 0.5 }, { "x0.75", 0.75 }, { "x1.25", 1.25 }, { "x1.5", 1.5 }, { "x2", 2 }, { "x3", 3 } }
local CONFIG = "difficulty_scaling_config"
local function bal(key, label, help, class, paths, options, int)
  return { kind = "coop_bal", key = key, save_key = "coop_" .. key, label = label, help = help, class = class, paths = paths, options = options, int = int, sel = 1 }
end
K.balance_rows = {
  { kind = "coop_bal", act = "preset", save_key = "coop_preset", label = "Balance preset", sel = 1,
    help = "Sets the rows below together. Works on the host, set it before or during a session. Left/Right picks, Enter sets it.",
    options = {
      { "Game's", {} },
      { "No co-op penalty", { damage = 1, taken = 1, grunts = 1, specialists = 1 } },
      { "Easier together", { damage = 1.5, taken = 0.7, grunts = 1, specialists = 1, close = 2, flow = 1.5, scores = 0.75, clocks = 1.5 } },
      { "Harder together", { taken = 2, grunts = 2, specialists = 2, calls = 1.5, limit = 1.5, scores = 1.25, clocks = 0.75 } },
      { "Mayhem", { damage = 2, taken = 1, calls = 2, limit = 3, close = 3, flow = 2 } },
    } },
  bal("damage", "Together: your damage", "How hard you both hit when you're close. Game's is 0.7, so being close costs you 30%. 1 is the same as solo. Takes hold when you next part and meet.", CONFIG, { "m_coop_avatar_damage_output_multiplier" }, NUMBER),
  bal("taken", "Together: damage taken", "The game's resistance scale when you're close. Game's is 1.6. Lower should hurt less, from reading the code, not measured. Takes hold when you next part and meet.", CONFIG, { "m_coop_avatar_damage_resistance_multiplier" }, NUMBER),
  bal("grunts", "Together: tough grunts", "How much tougher ordinary enemies are when you're close. Game's is 1.5. 1 is the same as solo.", CONFIG, { "m_coop_tough_grunt_multiplier" }, NUMBER),
  bal("specialists", "Together: tough specialists", "How much tougher specialist enemies are when you're close. Game's is 1.5. 1 is the same as solo.", CONFIG, { "m_coop_tough_specialist_multiplier" }, NUMBER),
  bal("calls", "Together: reinforcements", "How fast notoriety calls in reinforcements when you're close. Game's is 1. Takes hold when you next part and meet.", CONFIG, { "m_coop_notoriety_call_in_speed_multiplier" }, NUMBER),
  bal("limit", "Co-op enemy limit", "How many of each enemy type can be out at once in co-op. Types with no limit stay that way.", "enemy_type", { "m_max_units_coop" }, TIMES, true),
  bal("close", "What counts as close", "How near you have to be for the Together rows to count. Game's: within 60 m starts it, past 70 m ends it.", "notoriety_system_config", { "m_coop_near_distance", "m_coop_far_distance" }, TIMES),
  bal("flow", "Together: Flow bonus", "The extra Flow you earn when you're close. Game's is x1.25 on Flow, and this multiplies that.", "adrenaline_system_info", { "close_coop_multiplier" }, TIMES),
  bal("scores", "Co-op activity scores", "The score Mayhem and Insurance Fraud ask for in co-op. Set it before you start one.", false, { insurance_fraud_instance_info = { "m_coop_target_score" }, mayhem_instance_info = { "m_coop_target_score_completion" } }, TIMES),
  bal("clocks", "Co-op activity clocks", "The time Mayhem and Insurance Fraud give you in co-op. Set it before you start one.", false, { insurance_fraud_instance_info = { "m_coop_time_limit" }, mayhem_instance_info = { "m_coop_time_limit" } }, TIMES),
}

local addr_cache = {}
local function addresses(P, class, path)
  local key = class .. "." .. path
  if addr_cache[key] then return addr_cache[key] end
  local list = {}
  for _, rec in ipairs(P.engine_records(class)) do
    local a = P._engine_addr(class, rec, path)
    if a then list[#list + 1] = a end
  end
  if #list > 0 then addr_cache[key] = list end
  return list
end
-- Value by address, in the same table as Game data, so its undo and Everything back to normal cover these too.
-- A NUMBER row writes the number; a TIMES row multiplies what the game had, leaving none and "no limit" (negative) alone.
local function write_field(P, class, path, int, v, absolute)
  local read, write = P._engine_rw(int or false)
  local n = 0
  for _, a in ipairs(addresses(P, class, path)) do
    if SR5TM_ENGINE[a] == nil then SR5TM_ENGINE[a] = { int or false, read(a) } end
    local o = SR5TM_ENGINE[a][2]
    if v == false or (not absolute and v == 1) then
      write(a, o)
      SR5TM_ENGINE[a] = nil
    elseif absolute then
      write(a, v)
    elseif o > 0 and o < 0x80000000 then
      write(a, int and math.max(1, math.floor(o * v + 0.5)) or o * v)
    end
    n = n + 1
  end
  return n
end
local function apply_row(row, P)
  local v = row.options[row.sel][2]
  local absolute = row.options == NUMBER
  local n = 0
  if row.class then
    for _, path in ipairs(row.paths) do n = n + write_field(P, row.class, path, row.int, v, absolute) end
  else
    for class, paths in pairs(row.paths) do
      for _, path in ipairs(paths) do n = n + write_field(P, class, path, row.int, v, absolute) end
    end
  end
  return n
end
local function pick(row, value)
  for i, o in ipairs(row.options) do if o[2] == value then row.sel = i; return end end
  row.sel = 1
end

-- Enter on a balance row. Returns what to say.
function K.balance_press(row, P)
  local o = row.options[row.sel]
  if row.act == "preset" then
    local n = 0
    for _, r in ipairs(K.balance_rows) do
      if r.key then
        local was = r.sel
        local want = o[2][r.key]
        if want == nil then r.sel = 1 else pick(r, want) end
        if r.sel ~= was or r.sel ~= 1 then n = n + apply_row(r, P) end
      end
    end
    K.log("balance preset: " .. o[1] .. ", " .. n .. " values")
    return "Balance: " .. o[1]
  end
  local n = apply_row(row, P)
  K.log("balance: " .. row.label .. " = " .. o[1] .. ", " .. n .. " values")
  return n > 0 and (row.label .. ": " .. o[1]) or (row.label .. ": not found, load into the game first")
end
-- Saved choices, once the game's data is there. Only touches the game if something's set.
function K.balance_saved(P)
  for _, r in ipairs(K.balance_rows) do
    if r.key and r.sel ~= 1 then apply_row(r, P) end
  end
end

return K
