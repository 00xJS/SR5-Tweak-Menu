-- SR5 Tweak Menu - things one gun can borrow from another. A module of its own: player.lua's main chunk is at Lua's limit of locals.
-- Everything is keyed on the gun's id. A gun's component address is reused, and only read after the id is checked this pass.
-- Off: P._reequip_soon(), which rebuilds the gun from its record, one second later, once however many rows asked.
local P = require("player")
local loaded = P._loaded
local NAME = "sr5_tweak_menu"

local function crc(s)
  local ok, v = wml.game("return string_crc(" .. string.format("%q", s) .. ")")
  return ok and type(v) == "number" and (math.floor(v) & 0xFFFFFFFF) or 0
end
-- The gun in hand: id, object entry, weapon component.
local function gun()
  local B = wml.base
  local ok, s = wml.game("return tostring(gml_get_local_player_weapon())")
  local id = ok and tonumber((s or ""):match("object (%x+)") or "", 16)
  if not id or id == 0 then return nil end
  local buf = wml.buffer(10)
  wml.write_u32(buf, id)
  local entry = wml.call(B + 0x1C1F420, buf)
  local comp = entry ~= 0 and wml.call(B + 0x49F8A0, entry) or 0
  if comp == 0 then return nil end
  return id, entry, comp
end
-- All the models a choice needs: true, false if one failed, nil while waiting.
local function all_loaded(list)
  local out = true
  for _, path in ipairs(list or {}) do
    local r = loaded(path)
    if r == false then return false end
    if r == nil then out = nil end
  end
  return out
end

-- ------------------------------------------------------------------ signature from another gun
-- The game's own way (+996A20): an upgrade's "Script to Attach" (record +0x110 list, 0x268 each, +0x18 id) goes on the gun's object as a
-- named script component: +1847510(&out, entry, id, 1, &name hash), +193FD50(comp, script name), +1C3AB70 to commit. The scripts live
-- in the inventory tables' own containers, so they're there without the donor gun (M). +193FD50 refuses a script not at state 4.
-- Our own name per slot, so a gun's own "UltimateUpgrade" stays and two can run. The donor's upgrade tier doesn't matter.
P.sig_from, P.sig_from2 = false, false   -- false or { record = inventory record, loads = { paths }, keys = { {key, kind, value}... } }
local sig_gun, sig_done = nil, {}
local function record_of(name)
  local ok, ud = wml.game("return vlib_info_object:get_object(\"inventory_weapon_info\", " .. string.format("%q", name) .. ").m_reserve_size")
  local a = ok and ud and require("vdata").field_addr(ud)
  return a and a - 0x9C or nil
end
local function script_id(rec)
  local list, n = wml.read_u64(rec + 0x110), wml.read_u16(rec + 0x118)
  for i = n - 1, 0, -1 do
    local srid = wml.read_u64(list + i * 0x268 + 0x18)
    if srid ~= 0 then return srid end
  end
end
local function attach(entry, srid, slot_name)
  local B = wml.base
  if wml.call(B + 0xE715E0, srid) & 0xFFFFFFFF ~= 4 then return "not loaded" end
  local text = wml.call(B + 0xD82FA0, srid)
  if text == 0 then return "no name" end
  local mem = wml.buffer(10) + 0x100
  wml.write_u32(mem, crc(slot_name))
  if wml.call(B + 0x4BEC80, entry, mem) ~= 0 then return "name taken" end
  -- the object's kind allows it (+996C74)
  local v = wml.read_u32(entry + 0x5C) >> 10
  local d = wml.read_u64(B + 0x496B7A8) + (v & 0x3F) * 0x40
  local kind = wml.read_u64(d + 0x18) + wml.read_u64(d + 0x10) * ((v >> 6) & 0x3FFFFFF)
  if wml.read_u8(kind + 0x6D) ~= 0 then return "not this object" end
  local out = mem + 0x10
  wml.write_u64(out, 0)
  local count = wml.read_u64(B + 0x5CB42A0) + 1
  wml.write_u64(B + 0x5CB42A0, count)
  local comp = wml.call(B + 0x1847510, out, entry, count | (1 << 63), 1, mem)
  if comp == 0 then return "no component" end
  wml.call(B + 0x193FD50, comp, text)
  local h = wml.read_u32(out) & 0x1FFFFFF
  wml.write_u32(mem + 0x20, h)
  wml.write_u64(mem + 0x30, mem + 0x20)
  wml.write_u32(mem + 0x38, 1)
  if wml.call(B + 0x1C3AB70, mem + 0x30) & 0xFF == 0 then
    wml.call(B + 0x148F670, h)
    return "commit refused"
  end
  return true
end
local function put_key(comp, key, kind, value)
  local buf, name = wml.buffer(10), wml.buffer(11, NAME)
  wml.write_u32(buf + 0x10, key)
  for i = 0, 15, 4 do wml.write_u32(buf + 0x20 + i, 0) end
  if kind == 1 then wml.write_f32(buf + 0x20, value) else wml.write_u32(buf + 0x20, value) end
  wml.write_u32(buf + 0x28, kind)
  for section = 0, 1 do wml.call(wml.base + 0x1BFF510, comp, buf + 0x10, section, buf + 0x20, name) end
end
function P.sig_from_active() return P.sig_from or P.sig_from2 or next(sig_done) ~= nil end
function P.update_sig_from()
  local want = { P.sig_from or false, P.sig_from2 or false }
  if not want[1] and not want[2] then
    if next(sig_done) then sig_done, sig_gun = {}, nil; P._reequip_soon() end
    return
  end
  local id, entry, comp = gun()
  if not id then return end
  if id ~= sig_gun then sig_gun, sig_done = id, {} end
  for slot = 1, 2 do
    local w = want[slot]
    if sig_done[slot] and sig_done[slot] ~= w then
      sig_done, sig_gun = {}, nil
      P._reequip_soon()   -- a changed pick: a clean gun, then the new ones go on
      return
    end
    if w and not sig_done[slot] then
      local ready = all_loaded(w.loads)
      if ready == false then wml.log("signature: a model wouldn't load for " .. w.record); sig_done[slot] = w
      elseif ready then
        local rec = record_of(w.record)
        local srid = rec and script_id(rec)
        if srid then
          local r = attach(entry, srid, "sr5tm_sig" .. slot)
          if r ~= true then wml.log("signature " .. w.record .. ": " .. r) end
        end
        for _, k in ipairs(w.keys or {}) do put_key(comp, k[1], k[2], k[3]) end
        sig_done[slot] = w
      end
    end
  end
end

-- ------------------------------------------------------------------ blast on hit
-- Tracer hits read "explosion" from the gun's list and spawn it at the hit (+3FD04A, the Machine Pistol's Splattergun is this). No projectile.
P.bullet_blast = false   -- false or a path
local blast_gun, blast_on
function P.bullet_blast_active() return P.bullet_blast or blast_on end
function P.update_bullet_blast()
  local path = P.bullet_blast
  if not path then blast_gun = nil; if blast_on then blast_on = nil; P._reequip_soon() end; return end
  if not loaded(path) then return end
  local id, _, comp = gun()
  if not id or (id == blast_gun and blast_on == path) then return end
  local buf, name = wml.buffer(10), wml.buffer(11, NAME)
  wml.write_u32(buf + 0x10, 0x979E75B2)   -- explosion
  local srid = P._prefab_id(path .. ".cprefab_pc")
  for section = 0, 1 do wml.call(wml.base + 0x1C001E0, comp, buf + 0x10, section, srid, name) end
  blast_gun, blast_on = id, path
end

-- ------------------------------------------------------------------ fire mode
-- Run from here, no script swap: the fire loop won't fire before the section's +0x7BC, against the clock at +2E80878, and +0x7C4 bit 1 means the
-- trigger's held (+1BFD880). Nothing here outlasts the row: every value is the timer, which the game overwrites.
P.fire_mode = false   -- false or { "burst", n, gap ms } / { "charge", ms } / { "spin", ms }
local fm = {}
function P.update_fire_mode()
  local mode = P.fire_mode
  if not mode then fm = {}; return end
  local id, _, comp = gun()
  if not id then return end
  if fm.id ~= id then fm = { id = id, n0 = wml.read_u32(comp + 0x1CE8) } end
  local now, n = wml.read_u32(wml.base + 0x2E80878), wml.read_u32(comp + 0x1CE8)
  local held = wml.read_u8(comp + 0x7C4) & 1 == 1
  if mode[1] == "burst" then
    if not held then fm.n0 = n
    elseif n - fm.n0 >= mode[2] then
      wml.write_u32(comp + 0x7BC, now + mode[3])
      fm.n0 = n
    end
  else
    if not held then
      fm.t0, fm.n1 = nil, nil
      wml.write_u32(comp + 0x7BC, now + 2000)   -- so the first pull can't fire at once
    elseif not fm.t0 then
      fm.t0, fm.n1 = now, n
      wml.write_u32(comp + 0x7BC, now + mode[2])
    elseif mode[1] == "charge" and n ~= fm.n1 then
      fm.t0, fm.n1 = now, n
      wml.write_u32(comp + 0x7BC, now + mode[2])
    end
  end
end

-- ------------------------------------------------------------------ one round in n
-- Special rounds on every nth shot only. The round's keys go on once; "shot" and "shot_type" flip each time the counter moves. Both are read per shot (+982340).
P.nth_round, P.nth_every = false, 5
local nth = {}
function P.nth_active() return P.nth_round or nth.on end
function P.update_nth()
  local r = P.nth_round
  if not r then
    local was = nth.on
    nth = {}
    if was then P._reequip_soon() end
    return
  end
  local ready = all_loaded({ r[1], r[2] })
  if ready and r.loads then ready = all_loaded(r.loads) end
  if not ready then return end
  local id, _, comp = gun()
  if not id then return end
  local buf, name = wml.buffer(10), wml.buffer(11, NAME)
  if nth.id ~= id or nth.for_r ~= r then
    -- the gun's own shot and type, section 0, before we touch them: { key, section, id } at +0x600, { key, value, type } at +0x138
    local own, own_type = nil, 0xD57E1B94
    local list, cnt = wml.read_u64(comp + 0x600), wml.read_u16(comp + 0x608)
    for i = 0, cnt - 1 do
      if wml.read_u32(list + i * 16) == 0x8A4357A7 and wml.read_u32(list + i * 16 + 4) == 0 then own = wml.read_u64(list + i * 16 + 8) end
    end
    list, cnt = wml.read_u64(comp + 0x138), wml.read_u16(comp + 0x140)
    for i = 0, cnt - 1 do
      if wml.read_u32(list + i * 24) == 0x30B4E7EA then own_type = wml.read_u32(list + i * 24 + 8) end
    end
    if not own then return end
    nth = { id = id, for_r = r, own = own, own_type = own_type, on = true, n = wml.read_u32(comp + 0x1CE8), rare = P._prefab_id(r[1] .. ".cprefab_pc") }
    put_key(comp, 0x30B4E7EA, 3, own_type)   -- first: a section's list holds 50 keys and drops what comes after
    for _, k in ipairs(r.keys or {}) do
      local v = type(k[3]) == "string" and crc(k[3]) or k[3]
      put_key(comp, k[1], k[2], v)
    end
    wml.write_u32(buf + 0x10, 0x979E75B2)
    local blast = P._prefab_id(r[2] .. ".cprefab_pc")
    for section = 0, 1 do wml.call(wml.base + 0x1C001E0, comp, buf + 0x10, section, blast, name) end
  end
  local n = wml.read_u32(comp + 0x1CE8)
  local rare = (n + 1) % (P.nth_every or 5) == 0
  if rare == nth.flip then return end
  nth.flip = rare
  put_key(comp, 0x30B4E7EA, 3, rare and 0xDF712A1B or nth.own_type)   -- shot_type: projectile, or the gun's own
  wml.write_u32(buf + 0x10, 0x8A4357A7)
  for section = 0, 1 do wml.call(wml.base + 0x1C001E0, comp, buf + 0x10, section, rare and nth.rare or nth.own, name) end
end

-- ------------------------------------------------------------------ fire sound
-- comp + section * 0x6A0 + 0x134, a gml_weapon_fire_audio name hash, turned into a bank at spawn (+1BFE820). Whether the shot reads it again: not known.
P.fire_sound = false
local snd = {}
function P.fire_sound_active() return P.fire_sound or snd.id end
function P.update_fire_sound()
  local id, _, comp = gun()
  if not id then return end
  if snd.id == id and snd.want == P.fire_sound then return end
  if snd.id == id and not P.fire_sound then
    wml.write_u32(comp + 0x134, snd.orig)
    snd = {}
    wml.call(wml.base + 0x1BFE820, comp)
    return
  end
  if not P.fire_sound then snd = {}; return end
  if snd.id ~= id then snd = { id = id, orig = wml.read_u32(comp + 0x134) } end
  snd.want = P.fire_sound
  wml.write_u32(comp + 0x134, P.fire_sound)
  wml.call(wml.base + 0x1BFE820, comp)
end

-- ------------------------------------------------------------------ perks that need a model, and what their number means
-- Not Rated and Enemy drop on death keep a prefab from the params (their apply slot, +6CB800), and with none they do nothing: +6CB840 checks for null,
-- and +6D23B0 hands it to +B42DA0 as the blast. It's the same id P._prefab_id gives. A dropped grenade may go off as the round it also is, so load what that round loads.
local perk = P._perk
local NOT_RATED, DROP = "passive_mod_class_not_rated", "object_mod_class_enemy_drop_on_death"
local BOOT_HILL = [[data\dlc_boothill\spawnables\weapons\]]
local function with_round(path)
  local out = { path }
  for _, r in ipairs(require("rounds").rounds) do
    if r[2] == path then
      out[#out + 1] = r[3]
      for _, l in ipairs(r[4] or {}) do out[#out + 1] = l end
    end
  end
  return out
end
-- The first path's id once all are in; nil and why if not.
local function model_id(list)
  local ready = all_loaded(list)
  if ready == false then return nil, "A model wouldn't load" end
  if not ready then return nil, "Loading: press again" end
  return P._prefab_id(list[1] .. ".cprefab_pc")
end
local PERK_MODELS = { [NOT_RATED] = { BOOT_HILL .. "perk_headshot_explosion" }, [DROP] = with_round(BOOT_HILL .. "encounter_mod_frag_grenade") }
function P._perk_prefab(class)
  local list = PERK_MODELS[class]
  if list then return model_id(list) end
end
-- Any perk says this when one goes on. Fire and Taser's number is a cooldown (value x 1000 ms to +0x20: +6D2840, +6D0620).
local PERK_NOTES = {
  [NOT_RATED] = ". Headshot kills blow up, and the number is the chance",
  [DROP] = ". A grenade drops when you die, and the number is the chance",
  passive_mod_class_besties = ". The number is the chance per hit, and 1 is always",
  passive_mod_class_fire_on_enemy_melee_damage = ". The number is seconds between burns: lower is stronger",
  passive_mod_class_taser_on_enemy_melee_damage = ". The number is seconds between shocks: lower is stronger",
}
function P.perk_note(class) return PERK_NOTES[class] or "" end

-- ------------------------------------------------------------------ perks as rows of their own
-- Each row's value is its list of { class, number }, or a blast's path for Headshot kill blast. What went on is kept, so off takes away exactly that: the value is additive.
-- Numbers (research_dlc_mix.md section 0): Besties, the enemy_damage classes and Not Rated are a chance per event, +1E0F90 tests random <= value. Fire and Taser: a cooldown, seconds.
P.hits_recruit, P.all_my_damage, P.melee_backfire, P.headshot_blast = false, false, false, false
local PERK_ROWS = { hits_recruit = "Hits recruit", all_my_damage = "All my damage", melee_backfire = "Melee backfire", headshot_blast = "Headshot kill blast" }
local held = {}
local function stats_of(e)
  local c = wml.call(wml.base + 0x4A17C0, e)
  return c ~= 0 and wml.read_u64(c + 0x1050) or 0
end
function P.perk_rows_active() return P.hits_recruit or P.all_my_damage or P.melee_backfire or P.headshot_blast or next(held) end
-- Returns a line for the player if the game refused one.
function P.update_perk_rows()
  if SR5TM_MY_ID then return end   -- in someone else's body: these stay on yours
  local e = P.object()
  local stats = e and stats_of(e) or 0
  if stats == 0 then return end
  local why
  for key, label in pairs(PERK_ROWS) do
    local want, h = P[key] or false, held[key]
    if h and h.stats ~= stats then h = nil; held[key] = nil end   -- a new stats object, a respawn or a load, has none of it
    if h and h.want ~= want then
      for _, a in ipairs(h.list) do perk(a[1], a[2], false) end
      h = nil; held[key] = nil
    end
    if want and not h then
      local list, ready, prefab = want, true, nil
      if key == "headshot_blast" then
        if P.perk_dial[NOT_RATED] then P.toggle_perk(NOT_RATED) end   -- one owner: taking either off clears the model (+6CB800)
        list, ready = { { NOT_RATED, 1.0 } }, loaded(want)
        if ready then prefab = P._prefab_id(want .. ".cprefab_pc") end
      end
      if ready ~= nil then
        local done = {}
        if ready == false then why = label .. ": that blast wouldn't load" end
        if ready then
          for _, a in ipairs(list) do
            if perk(a[1], a[2], true, prefab) then done[#done + 1] = a else why = label .. ": the game refused it" end
          end
        end
        held[key] = { want = want, stats = stats, list = done }
      end
    end
  end
  return why
end

-- ------------------------------------------------------------------ perks and Boot Hill's rules on other people
-- The same call on their stats object. Numbers and classes are dlc_boothill_mod_config's twelve; drops as its three prefabs. +6EA430 refuses a class the person's stats have no category for,
-- so a refusal is counted, not assumed. Pressed, so no game calls unless it's pressed. What went on is kept by id and stats object, so off can't take it from whoever gets that id next.
P.rule_people = {}
local RULES = {
  { "Hit harder", "object_mod_class_damage_output", 1.5 }, { "Take less damage", "object_mod_class_damage_resistance", 0.5 }, { "More health", "object_mod_class_max_health", 1.5 },
  { "Can't be staggered", "object_mod_class_stagger_immunity", 1 }, { "No reloading", "object_mod_class_enemy_infinite_ammo", 2 }, { "Shields", "object_mod_class_enemy_tough", 1 },
  { "Their hits shock", "object_mod_class_enemy_damage_electrification", 0.1 }, { "Their hits burn", "object_mod_class_enemy_damage_conflagration", 0.1 }, { "Their hits bleed", "object_mod_class_enemy_damage_bleed", 0.1 },
  { "Drop a molotov when they die", DROP, 0.25, BOOT_HILL .. "encounter_mod_molotov" }, { "Drop a grenade when they die", DROP, 0.25, BOOT_HILL .. "encounter_mod_frag_grenade" }, { "Drop a flashbang when they die", DROP, 0.25, BOOT_HILL .. "encounter_mod_flash_grenade" },
}
function P.rule_options(perks)
  local out, who = { { "Take rules off", "off" } }, { { "Near", false }, { "Homies", true } }
  for _, w in ipairs(who) do
    for _, r in ipairs(RULES) do out[#out + 1] = { w[1] .. ": " .. r[1], { homies = w[2], class = r[2], m = r[3], path = r[4] } } end
  end
  for _, w in ipairs(who) do
    for _, c in ipairs(perks) do out[#out + 1] = { w[1] .. ", perk: " .. c[1], { homies = w[2], class = c[2] } } end
  end
  return out
end
function P.rule_near(v)
  local n, buf = 0, wml.buffer(10)
  for key, a in pairs(P.rule_people) do
    wml.write_u32(buf, a.id)
    local e = wml.call(wml.base + 0x1C1F420, buf)
    local alive = e ~= 0 and stats_of(e) == a.stats
    if alive and v == "off" then perk(a.class, a.m, false, nil, e); n = n + 1 end
    if v == "off" or not alive then P.rule_people[key] = nil end   -- it died with them
  end
  if v == "off" then return n > 0 and (n .. " taken off") or "Nothing on" end
  local prefab, why
  if v.path then prefab, why = model_id(with_round(v.path)) else prefab, why = P._perk_prefab(v.class) end
  if why then return why end
  local m, took, had, refused = v.m or P.perk_strength or 1, 0, 0, 0
  local function put(p)
    local id = wml.read_u32(p.entry + 0x58)
    local key = id .. v.class
    if P.rule_people[key] then had = had + 1
    elseif perk(v.class, m, true, prefab, p.entry) then
      P.rule_people[key] = { id = id, stats = stats_of(p.entry), class = v.class, m = m }
      took = took + 1
    else refused = refused + 1 end
  end
  if v.homies then
    for _, p in ipairs(P.people_near(100)) do
      if P.component(0xDD, p.entry) and wml.read_u8(p.health + 0x104) == 0 then put(p) end   -- 0xDD: homies have it (research_static_ai.md)
    end
  else
    P._each_near(40, put)
  end
  if took + had + refused == 0 then return "Nobody there" end
  return took .. " took it" .. (had > 0 and (", " .. had .. " already had it") or "") .. (refused > 0 and (", the game refused " .. refused) or "")
end

-- ------------------------------------------------------------------ what the back-to-normal rows ask
function P.mix_off()
  P.sig_from, P.sig_from2, P.bullet_blast, P.fire_mode, P.nth_round, P.fire_sound = false, false, false, false, false, false
  P.hits_recruit, P.all_my_damage, P.headshot_blast = false, false, false
end
return P
