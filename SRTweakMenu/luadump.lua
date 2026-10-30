-- Reads a game Lua 5.1 function's constants (and its nested functions')
-- straight from memory: what it calls and which fields and names it uses.
-- Stock 5.1 layout on x64: LClosure +0x20 = Proto*; Proto +0x10 k,
-- +0x20 p, +0x40 source, +0x4C sizek, +0x58 sizep, +0x60 linedefined.
-- TValue 16 bytes (value, type at +8); TString text at +0x18, length +0x10.

local M = {}
local R64, R32, RF64 = wml.read_u64, wml.read_u32, wml.read_f64

local function tstring(ts)
  local len = R64(ts + 0x10)
  if len > 4096 then return "<?>" end
  return wml.read_string(ts + 0x18, len)
end

local function proto_consts(p, depth, out)
  local sizek, sizep = R32(p + 0x4C), R32(p + 0x58)
  if sizek > 5000 or sizep > 500 then out[#out + 1] = "<bad proto>"; return end
  local k, items = R64(p + 0x10), {}
  for i = 0, sizek - 1 do
    local tv = k + i * 16
    local t = R32(tv + 8)
    if t == 4 then items[#items + 1] = tstring(R64(tv))
    elseif t == 3 then items[#items + 1] = tostring(RF64(tv))
    elseif t == 1 then items[#items + 1] = R32(tv) ~= 0 and "true" or "false"
    end
  end
  out[#out + 1] = string.rep("  ", depth) .. "[line " .. R32(p + 0x60) .. "] " .. table.concat(items, " ")
  local pp = R64(p + 0x20)
  for i = 0, sizep - 1 do proto_consts(R64(pp + i * 8), depth + 1, out) end
end

-- dump(expr): expr is game Lua that evaluates to a function.
function M.dump(expr)
  local ok, s = game("return tostring(" .. expr .. ")")
  if not ok then return "error: " .. tostring(s) end
  local addr = tonumber((s or ""):match("function: (%x+)") or "", 16)
  if not addr then return "not a function: " .. tostring(s) end
  if wml.read_u8(addr + 0x0A) ~= 0 then return "C function" end
  local p = R64(addr + 0x20)
  local out = { "source " .. tstring(R64(p + 0x40)) }
  proto_consts(p, 0, out)
  return table.concat(out, "\n")
end

return M
