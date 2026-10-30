-- SR5 Tweak Menu - the game's reflection data (vlib), shared helpers.
--
-- Any field of a vlib info object (including nested ones, `m_contents.m_x`)
-- has an address the game's own lookup gives: +17D4660(field payload, &desc,
-- &index) returns the containing data, and the last descriptor's bit offset
-- is at desc+0x38. A field object is a game userdata (payload at +0x28).

local V = {}
local RESOLVE = 0x17D4660

local function ptr(v) return tonumber(tostring(v):match("(%x+)>$") or "", 16) end
local function s32(v) return v >= 0x80000000 and v - 0x100000000 or v end
V.ptr, V.s32 = ptr, s32

local buf
function V.field_addr(ud)
  local p = ptr(ud)
  if not p then return nil end
  buf = buf or wml.buffer(2)
  local base = wml.call(wml.base + RESOLVE, p + 0x28, buf, buf + 16)
  if base == 0 then return nil end
  local desc = wml.read_u64(buf)
  if desc == 0 or s32(wml.read_u32(buf + 16)) >= 0 then return nil end
  return base + (wml.read_u32(desc + 0x38) >> 3)
end

-- "f" or "i": which reading of the address matches the game's own number.
function V.typed(addr, number)
  local f = wml.read_f32(addr)
  if f == number or (number ~= 0 and math.abs(f - number) <= 1e-4 * math.abs(number)) then return "f" end
  if s32(wml.read_u32(addr)) == number then return "i" end
  return nil
end

function V.read(addr, t) if t == "i" then return s32(wml.read_u32(addr)) end return wml.read_f32(addr) end
function V.write(addr, t, v) if t == "i" then wml.write_u32(addr, math.floor(v) & 0xFFFFFFFF) else wml.write_f32(addr, v) end end

-- Every object of `class`, every field in `fields` ({ path =, what = }):
-- returns entries { addr, t, what, orig, object }. One game call per object.
function V.collect(class, fields)
  local entries = {}
  local ok, count = wml.game('local n = 0 for _ in vlib_info_object:ipairs("' .. class .. '") do n = n + 1 end return n')
  if not ok or type(count) ~= "number" then return entries end
  local exprs = {}
  for _, f in ipairs(fields) do exprs[#exprs + 1] = "o." .. f.path .. ", o." .. f.path .. ":get_number()" end
  for i = 1, count do
    local r = table.pack(wml.game('local i = 0 for _, o in vlib_info_object:ipairs("' .. class .. '") do i = i + 1 if i == ' .. i ..
      ' then return tostring(o), ' .. table.concat(exprs, ", ") .. ' end end'))
    if r[1] then
      local name = tostring(r[2]):match('"(.*)"')
      -- resolve at once, while the game still holds the field objects
      for j, f in ipairs(fields) do
        local ud, number = r[1 + 2 * j], r[2 + 2 * j]
        local a = V.field_addr(ud)
        local t = a and type(number) == "number" and V.typed(a, number)
        if t then entries[#entries + 1] = { addr = a, t = t, what = f.what, path = f.path, orig = V.read(a, t), object = name } end
      end
    end
  end
  return entries
end

return V
