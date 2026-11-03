-- SR5 Tweak Menu - a clone of you. A second copy of the player's own avatar prefab, the only body with a look component
-- (0x5C, research_clone.md), dressed with your look by the game's own capture and apply, then optionally a bodyguard.
-- The game has room for one: the look component pool has a single free slot, the one a co-op partner would use.
-- Offline only. Your saved character is guarded: each look component copies its look into the save when a weight
-- changes, and the clone's byte +0x34EE7 blocks that; your own look is captured back into the save after each step.
local P = require("player")

local AVATAR = [[data\sr_vanguard\spawnables\avatar\avatar.cprefab_pc]]
SR5TM_CLONE = SR5TM_CLONE or {}
local S = SR5TM_CLONE
P.clone_guard = false   -- bodyguard: follows you, gets in your car, fights

local function crc(s)
  local _, v = wml.game("return string_crc(" .. string.format("%q", s) .. ")")
  return math.floor(v) & 0xFFFFFFFF
end
local function cust(e) local c = wml.call(wml.base + 0x496100, e); return c ~= 0 and c or nil end
local function free_slots()
  local pool = wml.read_u64(wml.read_u64(wml.base + 0x5CB3F70) + 0x4AC0 + 8)
  local n = 0
  while pool ~= 0 and n < 64 do n = n + 1; pool = wml.read_u64(pool) end
  return n
end
-- coop.lua's own reading of the session. The "multiplayer on" byte alone is set solo too (seen 2026-11-02).
local function in_coop()
  local B = wml.base
  local s = wml.read_u64(B + 0x5CB4D10)
  if s == 0 then return false end
  local count, pending = wml.read_u32(s + 0xD80), wml.read_u32(s + 0xD90)
  if wml.read_u64(s + 0xDA0) ~= wml.read_u64(s + 0xDA8) then return true end
  return count > 1 or (wml.read_u8(B + 0x5CB4558) ~= 0 and count + pending > 1)
end
local function saving(on) if not (on and P.no_autosave) then P.node(0xAD8B70, 0x2A17718, { { u = on and 1 or 0 } }) end end

function P.clone_active() return S.rec ~= nil end
function P.clone_me()
  if S.rec then return "You already have a clone: the game has room for one" end
  if in_coop() then return "Not in co-op: the game would take the clone's look for yours" end
  local me = P.object()
  if not me or not cust(me) then return "Not now" end
  if P.vehicle_object() then return "Get out of the vehicle first" end
  if free_slots() == 0 then return "No room for another body: a co-op partner or something else has the slot" end
  P.look_first()   -- Undo my look keeps your look from before
  saving(false)
  -- 1.2 m to your right, facing as you do: placed by its spawn, never moved after (a moved avatar is a suspect in the
  -- +1842726 crash of 2026-11-02 22:38). spawn_prefab's offsets are world x and z.
  local rx, rz = wml.read_f32(me), wml.read_f32(me + 8)
  S.rec = P.spawn_prefab(AVATAR, 0, rx * 1.2, rz * 1.2)
  if not S.rec then saving(true); return "The game refused it" end
  S.t, S.id, S.dressed, S.guarding, S.car = 0, nil, false, false, nil
  return "Making your clone"
end
function P.clone_remove()
  if not S.rec then return "No clone" end
  local id = S.id or wml.read_u32(S.rec + 0x70)
  if id ~= 0 then P._remove_safe("id", id) end
  local me = P.object()
  local mc = me and cust(me)
  if mc then wml.call(wml.base + 0x1424500, mc, 0) end   -- your own look back in the save
  S.rec, S.id, S.dressed, S.guarding, S.car = nil, nil, false, false, nil
  saving(true)
  return "Clone removed"
end

-- Called about 4 times a second while there's a clone.
function P.update_clone()
  if not S.rec then return end
  local B = wml.base
  S.t = S.t + 1
  local me = P.object()
  if not me then return end
  if not S.id then
    local id = wml.read_u32(S.rec + 0x70)
    local e = id ~= 0 and P.entry_of(id)
    local c = e and cust(e)
    if c and wml.read_u32(c + 0x65C8) > 0 and wml.call(B + 0x48A760, e) ~= 0 then
      S.id = id
      P._born[id] = P._born[S.rec]
    elseif S.t > 40 then
      wml.log("clone: never got a body")
      S.rec = nil; saving(true)
    end
    return
  end
  local e = P.entry_of(S.id)
  if not e or wml.read_u32(e + 0x58) ~= S.id then   -- gone with a load or a respawn
    S.rec, S.id = nil, nil; saving(true)
    return
  end
  local c, mc = cust(e), cust(me)
  if not c or not mc then return end
  if not S.dressed then
    if not S.buf then
      local p = wml.call(wml.read_u64(B + 0x25832C0), 0, 0x10000, 0x3000, 4)   -- VirtualAlloc
      if p == 0 then return end
      wml.call(B + 0x4289E0, p)
      S.buf = p
    end
    wml.call(B + 0x1424500, mc, S.buf)
    wml.call(B + 0x1422DF0, c, S.buf, 1, 1, 0x10)
    wml.write_u8(c + 0x34EE7, 1)
    wml.call(B + 0x1424500, mc, 0)
    P.node(0x697590, 0x29D1E20, { { u = S.id }, { u = 1 } })   -- can't be killed: a second avatar's death isn't known
    S.dressed = true
  end
  wml.write_u8(c + 0x34EE7, 1)
  if P.clone_guard and not S.guarding then
    P.node(0xAE2210, 0x29E7BA8, { { u = S.id } })   -- avatar AI on
    P.make_follower(S.id)
    P.node(0xAE86F0, 0x29FB6D0, { { u = S.id }, { u = crc("saints") }, { u = crc("homie") } })
    S.guarding = true
  elseif not P.clone_guard and S.guarding then
    P.node(0xAE22F0, 0x29F37E8, { { u = S.id } })   -- stands where it is
    S.guarding = false
  end
  if S.guarding then
    local v = P.vehicle_object()
    local vid = v and wml.read_u32(v + 0x58)
    if vid ~= S.car then
      if vid then P.node(0xAE6180, 0x29DDC80, { { u = S.id }, { u = vid }, { u = 0xFFFFFFFF }, { u = 0xFFFFFFFF }, { u = 8 } })
      else P.make_follower(S.id) end
      S.car = vid
    end
  end
end
return P
