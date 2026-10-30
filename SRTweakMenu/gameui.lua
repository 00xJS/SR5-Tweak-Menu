-- SR5 Tweak Menu - drawing with the game's own interface (vint).
--
-- The menu is a column of text lines in one of the game's interface
-- documents (1920x1080 units, scaled to the screen; "fades" by default,
-- menu_document in mod.ini), made the way gml_lib.lua's audio debug display
-- makes its text: vint_object_create(name, "text", parent), then font,
-- anchor, tint. The parent is the document's root element; its global
-- anchor is taken off, so menu_x / menu_y are from the screen's top left.
--
-- Each line is a label and a value (two columns) with the text engine's own
-- shadow (as the HUD wallet's text). Tints are set in 0-255 (they read back
-- in 0-1). Text in [brackets] is read as markup
-- by the game, so the menu never shows square brackets.
--
-- The backing panel is a copy of a plain 16x16 bitmap from the same
-- document (the game scales and tints those into flat panels), stretched and
-- tinted black; its alpha is the menu opacity. It stays in its own document:
-- a copy moved into another document may have brought the game down once.
-- A bitmap's anchor is its centre. Creation order doesn't decide what's
-- drawn on top (the panel dimmed some lines and not others), so depth does:
-- the panel at +100, the text at -100 (lower depth is drawn in front).
-- Only lines whose text or colour changed are sent to the game, in one call
-- per frame.

local U = { lines = 0 }
local S = wml.setting
local X, Y = S("menu_x", 120), S("menu_y", 120)
local LINE_H, VALUE_X = S("menu_line", 34), S("menu_value_x", 560)
local WIDTH = S("menu_width", 1000)
local SCALE = S("menu_scale", 0.9)
local FONT = S("menu_font", "avant_garde_body")
local DOC = S("menu_document", "fades")
local PAD = 24
local handles = {}   -- [line] = { label, value }
local panel           -- the backing panel, or nil
local shown = {}     -- [line] = { key = }
local made = false
U.opacity = S("menu_opacity", 60)   -- percent

local function game(code)
  local r = table.pack(wml.game(code))
  if not r[1] then wml.log("gameui: game Lua error: " .. tostring(r[2])); return nil end
  return table.unpack(r, 2, r.n)
end

local function q(s) return string.format("%q", s) end

-- Makes `n` lines (hidden) and the panel. Returns true when the lines exist.
function U.create(n)
  local r = table.pack(game([[
    local doc = vint_document_find(]] .. q(DOC) .. [[)
    if not doc then return nil end
    local parent = vint_document_get_root_element(doc)
    if not parent then return nil end
    local px, py = vint_get_global_anchor(parent)
    -- the panel: a plain 16x16 bitmap from this document
    local bg = 0
    local function find(h)
      if not h or h == 0 then return nil end
      if vint_object_get_type(h) == 5 then
        local w, hh = vint_get_local_size(h)
        local sx, sy = vint_get_scale(h)
        if w and sx and sx ~= 0 and sy ~= 0 and w / sx == 16 and hh / sy == 16 then return h end
      end
      local c = vint_object_first_child(h)
      while c and c ~= 0 do
        local f = find(c)
        if f then return f end
        c = vint_object_next_sibling(c)
      end
      return nil
    end
    local src = find(parent)
    if src then
      bg = vint_object_clone(src)
      if bg and bg ~= 0 then
        vint_object_set_parent(bg, parent)
        vint_set_anchor(bg, ]] .. (X - PAD + (WIDTH + 2 * PAD) / 2) .. [[ - px, ]] .. (Y - PAD + (n * LINE_H + 2 * PAD) / 2) .. [[ - py)
        vint_set_scale(bg, ]] .. ((WIDTH + 2 * PAD) / 16) .. [[, ]] .. ((n * LINE_H + 2 * PAD) / 16) .. [[)
        vint_set_tint(bg, 0, 0, 0)
        vint_set_depth(bg, 100)
        vint_set_alpha(bg, 0)
        vint_set_visible(bg, false)
      else
        bg = 0
      end
    end
    local o = { bg }
    for i = 1, ]] .. n .. [[ do
      for j = 1, 2 do
        local h = vint_object_create("sr5tm_" .. i .. "_" .. j, "text", parent)
        vint_set_font(h, ]] .. q(FONT) .. [[)
        vint_set_scale(h, ]] .. SCALE .. ", " .. SCALE .. [[)
        vint_set_anchor(h, ]] .. X .. [[ - px + (j == 2 and ]] .. VALUE_X .. [[ or 0), ]] .. Y .. [[ - py + (i - 1) * ]] .. LINE_H .. [[)
        vint_set_shadow_enabled(h, true)
        vint_set_depth(h, -100)
        vint_set_text(h, "")
        vint_set_visible(h, false)
        o[#o + 1] = h
      end
    end
    return unpack(o)
  ]]))
  if r.n < n * 2 + 1 or not r[2] then wml.log("gameui: couldn't make the menu's text"); return false end
  handles, shown = {}, {}
  for i = 1, n do handles[i] = { r[(i - 1) * 2 + 2], r[(i - 1) * 2 + 3] } end
  panel = (r[1] or 0) ~= 0 and r[1] or nil
  U.lines, made = n, true
  wml.log("gameui: " .. n .. " lines made" .. (panel and ", with a panel" or ", no panel (no bitmap to copy)"))
  return true
end

-- Are our objects still there? (Loading a save rebuilds the interface.)
function U.alive()
  if not made then return false end
  return game("return vint_object_exists(" .. handles[1][1] .. ") and true or false") == true
end

local COLOURS = {
  title = { 1, 0.80, 0.25 }, tabs = { 0.6, 0.8, 1 }, cursor = { 1, 0.80, 0.25 }, row = { 1, 1, 1 },
  off = { 0.65, 0.65, 0.65 }, help = { 0.85, 0.85, 0.85 }, status = { 0.5, 1, 0.5 }, warn = { 1, 0.55, 0.4 },
  on = { 0.5, 1, 0.5 },
}

local panel_shown, panel_alpha
local function panel_code(code, visible)
  if not panel then return end
  local a = math.max(0, math.min(100, U.opacity)) / 100
  if visible ~= panel_shown or (visible and a ~= panel_alpha) then
    code[#code + 1] = "vint_set_alpha(" .. panel .. ", " .. a .. ") vint_set_visible(" .. panel .. ", " .. tostring(visible and a > 0) .. ")"
    panel_shown, panel_alpha = visible, a
  end
end

-- Shows `rows`: { { label =, value =, colour =, value_colour = } ... }; nil hides everything.
function U.show(rows)
  if not made then return end
  local code = {}
  panel_code(code, rows ~= nil)
  for i = 1, U.lines do
    local want = rows and rows[i]
    local old = shown[i]
    local h = handles[i]
    if not want then
      if old then
        code[#code + 1] = "vint_set_visible(" .. h[1] .. ", false) vint_set_visible(" .. h[2] .. ", false)"
        shown[i] = nil
      end
    else
      local label, value = (want.label or ""):gsub("[%[%]]", ""), (want.value or ""):gsub("[%[%]]", "")
      local c = COLOURS[want.colour or "row"] or COLOURS.row
      local vc = COLOURS[want.value_colour or want.colour or "row"] or c
      -- vint_set_tint takes 0-255 (vint_get_tint gives back 0-1)
      c = { math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5) }
      vc = { math.floor(vc[1] * 255 + 0.5), math.floor(vc[2] * 255 + 0.5), math.floor(vc[3] * 255 + 0.5) }
      local key = label .. "\0" .. value .. "\0" .. (want.colour or "") .. "\0" .. (want.value_colour or "")
      if not old or old.key ~= key then
        code[#code + 1] = "vint_set_text(" .. h[1] .. ", " .. q(label) .. ") vint_set_text(" .. h[2] .. ", " .. q(value) .. ")"
        code[#code + 1] = "vint_set_tint(" .. h[1] .. ", " .. c[1] .. ", " .. c[2] .. ", " .. c[3] .. ")"
        code[#code + 1] = "vint_set_tint(" .. h[2] .. ", " .. vc[1] .. ", " .. vc[2] .. ", " .. vc[3] .. ")"
        if not old then code[#code + 1] = "vint_set_visible(" .. h[1] .. ", true) vint_set_visible(" .. h[2] .. ", true)" end
        shown[i] = { key = key }
      end
    end
  end
  if #code > 0 then game(table.concat(code, "\n")) end
end

function U.forget() made, handles, shown, panel, panel_shown, panel_alpha, U.lines = false, {}, {}, nil, nil, nil, 0 end

-- Removes our objects from the game's interface.
function U.destroy()
  if made then
    local code = {}
    for _, h in ipairs(handles) do
      for j = 1, 2 do code[#code + 1] = "if vint_object_exists(" .. h[j] .. ") then vint_object_destroy(" .. h[j] .. ") end" end
    end
    if panel then code[#code + 1] = "if vint_object_exists(" .. panel .. ") then vint_object_destroy(" .. panel .. ") end" end
    game(table.concat(code, "\n"))
  end
  U.forget()
end

return U
