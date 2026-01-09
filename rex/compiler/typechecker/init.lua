

local Typechecker = {}

local report

local function type_new(kind, fields)
  local t = fields or {}
  t.kind = kind
  return t
end

local function type_any()
  return type_new("any")
end

local function type_unknown()
  return type_new("unknown")
end

local function type_num()
  return type_new("num")
end

local function type_bool()
  return type_new("bool")
end

local function type_str()
  return type_new("str")
end

local function type_nil()
  return type_new("nil")
end

local function type_void()
  return type_new("void")
end

local function type_vec(elem)
  return type_new("vec", { elem = elem })
end

local function type_map(key, value)
  return type_new("map", { key = key, value = value })
end

local function type_set(elem)
  return type_new("set", { elem = elem })
end

local function type_result(ok, err)
  return type_new("result", { ok = ok, err = err })
end

local function type_tuple(items)
  return type_new("tuple", { items = items })
end

local function type_ref(to, mutable)
  return type_new("ref", { to = to, mutable = mutable and true or false })
end

local function type_ptr(to)
  return type_new("ptr", { to = to })
end

local function type_sender(item)
  return type_new("sender", { item = item })
end

local function type_receiver(item)
  return type_new("receiver", { item = item })
end

local function type_struct(name, fields, args)
  return type_new("struct", { name = name, fields = fields, args = args })
end

local function type_enum(name, variants, args)
  return type_new("enum", { name = name, variants = variants, args = args })
end

local function type_fn(params, ret)
  return type_new("fn", { params = params, ret = ret })
end

local function type_var(name)
  return type_new("var", { name = name })
end

-- BOND STATE MACHINE HELPERS
local function bond_is_rolled_back(ctx, var_name)
  if not ctx.bonds then return false end
  for bond_id, bond in pairs(ctx.bonds) do
    if bond.status == "rolled_back" and bond.name == var_name then
      return true
    end
  end
  return false
end

local function type_is_copy(t)
  if not t then
    return false
  end
  if t.kind == "num" or t.kind == "bool" then
    return true
  end
  if t.kind == "nil" then
    return true
  end
  if t.kind == "ref" and not t.mutable then
    return true
  end
  if t.kind == "tuple" then
    for _, item in ipairs(t.items or {}) do
      if not type_is_copy(item) then
        return false
      end
    end
    return true
  end
  return false
end

local function unwrap_ref(t)
  local out = t
  while out and out.kind == "ref" do
    out = out.to
  end
  return out
end

local function bounds_has(bounds, name)
  if not bounds then
    return false
  end
  for _, bound in ipairs(bounds) do
    if bound == name then
      return true
    end
    if (name == "str" and bound == "string") or (name == "string" and bound == "str") then
      return true
    end
  end
  return false
end

local function type_var_bounds(ctx, name)
  if ctx and ctx.generic_bounds then
    return ctx.generic_bounds[name]
  end
  return nil
end

local function type_var_allows_add(ctx, t)
  if not t or t.kind ~= "var" then
    return false
  end
  local bounds = type_var_bounds(ctx, t.name)
  return bounds_has(bounds, "add") or bounds_has(bounds, "num") or bounds_has(bounds, "str") or bounds_has(bounds, "string")
end

local function type_to_string(t)
  if not t then
    return "unknown"
  end
  if t.kind == "any" then
    return "any"
  elseif t.kind == "unknown" then
    return "unknown"
  elseif t.kind == "num" then
    return "num"
  elseif t.kind == "bool" then
    return "bool"
  elseif t.kind == "str" then
    return "str"
  elseif t.kind == "nil" then
    return "nil"
  elseif t.kind == "void" then
    return "void"
  elseif t.kind == "vec" then
    return "Vec<" .. type_to_string(t.elem) .. ">"
  elseif t.kind == "map" then
    return "Map<" .. type_to_string(t.key) .. ", " .. type_to_string(t.value) .. ">"
  elseif t.kind == "set" then
    return "Set<" .. type_to_string(t.elem) .. ">"
  elseif t.kind == "result" then
    return "Result<" .. type_to_string(t.ok) .. ", " .. type_to_string(t.err) .. ">"
  elseif t.kind == "tuple" then
    local parts = {}
    for _, item in ipairs(t.items or {}) do
      table.insert(parts, type_to_string(item))
    end
    return "(" .. table.concat(parts, ", ") .. ")"
  elseif t.kind == "ref" then
    local prefix = t.mutable and "&mut " or "&"
    return prefix .. type_to_string(t.to)
  elseif t.kind == "ptr" then
    return "*" .. type_to_string(t.to)
  elseif t.kind == "sender" then
    return "Sender<" .. type_to_string(t.item) .. ">"
  elseif t.kind == "receiver" then
    return "Receiver<" .. type_to_string(t.item) .. ">"
  elseif t.kind == "struct" then
    if t.args and #t.args > 0 then
      local parts = {}
      for _, arg in ipairs(t.args) do
        table.insert(parts, type_to_string(arg))
      end
      return t.name .. "<" .. table.concat(parts, ", ") .. ">"
    end
    return t.name
  elseif t.kind == "enum" then
    if t.args and #t.args > 0 then
      local parts = {}
      for _, arg in ipairs(t.args) do
        table.insert(parts, type_to_string(arg))
      end
      return t.name .. "<" .. table.concat(parts, ", ") .. ">"
    end
    return t.name
  elseif t.kind == "fn" then
    local parts = {}
    for _, p in ipairs(t.params or {}) do
      table.insert(parts, type_to_string(p))
    end
    return "fn(" .. table.concat(parts, ", ") .. ") -> " .. type_to_string(t.ret)
  elseif t.kind == "var" then
    return t.name
  end
  return "unknown"
end

local function type_equal(a, b)
  if not a or not b then
    return false
  end
  if a.kind ~= b.kind then
    return false
  end
  if a.kind == "vec" then
    return type_equal(a.elem, b.elem)
  elseif a.kind == "map" then
    return type_equal(a.key, b.key) and type_equal(a.value, b.value)
  elseif a.kind == "set" then
    return type_equal(a.elem, b.elem)
  elseif a.kind == "result" then
    return type_equal(a.ok, b.ok) and type_equal(a.err, b.err)
  elseif a.kind == "tuple" then
    if #a.items ~= #b.items then
      return false
    end
    for i = 1, #a.items do
      if not type_equal(a.items[i], b.items[i]) then
        return false
      end
    end
    return true
  elseif a.kind == "ref" then
    return a.mutable == b.mutable and type_equal(a.to, b.to)
  elseif a.kind == "ptr" then
    return type_equal(a.to, b.to)
  elseif a.kind == "sender" then
    return type_equal(a.item, b.item)
  elseif a.kind == "receiver" then
    return type_equal(a.item, b.item)
  elseif a.kind == "struct" or a.kind == "enum" then
    if a.name ~= b.name then
      return false
    end
    if a.args and b.args then
      if #a.args ~= #b.args then
        return false
      end
      for i = 1, #a.args do
        if not type_equal(a.args[i], b.args[i]) then
          return false
        end
      end
    end
    return true
  elseif a.kind == "fn" then
    if #a.params ~= #b.params then
      return false
    end
    for i = 1, #a.params do
      if not type_equal(a.params[i], b.params[i]) then
        return false
      end
    end
    return type_equal(a.ret, b.ret)
  elseif a.kind == "var" then
    return a.name == b.name
  end
  return true
end

local function type_assignable(to, from)
  if not to or not from then
    return false
  end
  if to.kind == "any" or from.kind == "any" then
    return true
  end
  if to.kind == "unknown" or from.kind == "unknown" then
    return false
  end
  if to.kind ~= from.kind then
    return false
  end
  if to.kind == "vec" then
    return type_assignable(to.elem, from.elem)
  elseif to.kind == "map" then
    return type_assignable(to.key, from.key) and type_assignable(to.value, from.value)
  elseif to.kind == "set" then
    return type_assignable(to.elem, from.elem)
  elseif to.kind == "result" then
    return type_assignable(to.ok, from.ok) and type_assignable(to.err, from.err)
  elseif to.kind == "tuple" then
    if #to.items ~= #from.items then
      return false
    end
    for i = 1, #to.items do
      if not type_assignable(to.items[i], from.items[i]) then
        return false
      end
    end
    return true
  elseif to.kind == "ref" then
    if to.mutable and not from.mutable then
      return false
    end
    return type_assignable(to.to, from.to)
  elseif to.kind == "ptr" then
    return type_assignable(to.to, from.to)
  elseif to.kind == "sender" then
    return type_assignable(to.item, from.item)
  elseif to.kind == "receiver" then
    return type_assignable(to.item, from.item)
  elseif to.kind == "struct" or to.kind == "enum" then
    if to.name ~= from.name then
      return false
    end
    if to.args and from.args then
      if #to.args ~= #from.args then
        return false
      end
      for i = 1, #to.args do
        if not type_assignable(to.args[i], from.args[i]) then
          return false
        end
      end
    end
    return true
  elseif to.kind == "fn" then
    if #to.params ~= #from.params then
      return false
    end
    for i = 1, #to.params do
      if not type_assignable(to.params[i], from.params[i]) then
        return false
      end
    end
    return type_assignable(to.ret, from.ret)
  elseif to.kind == "var" then
    return to.name == from.name
  end
  return true
end

local function type_merge(ctx, a, b, where)
  if not a then
    return b
  end
  if not b then
    return a
  end
  if type_equal(a, b) then
    return a
  end
  report(ctx, (where or "value") .. " types mismatch: " .. type_to_string(a) .. " vs " .. type_to_string(b))
  return type_unknown()
end

local function tokenize_type(src)
  local tokens = {}
  local i = 1
  while i <= #src do
    local ch = src:sub(i, i)
    if ch:match("%s") then
      i = i + 1
    elseif ch == ":" and src:sub(i, i + 1) == "::" then
      table.insert(tokens, "::")
      i = i + 2
    elseif ch == "<" or ch == ">" or ch == "," or ch == "(" or ch == ")" or ch == "*" or ch == "&" then
      table.insert(tokens, ch)
      i = i + 1
    else
      local j = i
      while j <= #src and src:sub(j, j):match("[%w_]") do
        j = j + 1
      end
      local word = src:sub(i, j - 1)
      if word ~= "" then
        table.insert(tokens, word)
      else
        i = i + 1
      end
      i = j
    end
  end
  return tokens
end

local function parse_type_string(src)
  if not src or src == "" then
    return nil
  end
  local tokens = tokenize_type(src)
  local pos = 1

  local function peek()
    return tokens[pos]
  end

  local function next_tok()
    local t = tokens[pos]
    pos = pos + 1
    return t
  end

  local function parse_type()
    local tok = peek()
    if tok == "&" then
      next_tok()
      local mutable = false
      if peek() == "mut" then
        next_tok()
        mutable = true
      end
      return type_ref(parse_type(), mutable)
    end
    if tok == "mut" then
      next_tok()
      return type_ref(parse_type(), true)
    end
    if tok == "*" then
      next_tok()
      return type_ptr(parse_type())
    end
    if tok == "(" then
      next_tok()
      local items = {}
      if peek() ~= ")" then
        repeat
          table.insert(items, parse_type())
        until not (peek() == "," and next_tok())
      end
      if peek() == ")" then
        next_tok()
      end
      if #items == 1 then
        return items[1]
      end
      return type_tuple(items)
    end
    local name = next_tok()
    if not name then
      return type_unknown()
    end
    while peek() == "::" do
      next_tok()
      local seg = next_tok()
      if not seg then
        break
      end
      name = name .. "::" .. seg
    end
    local args = nil
    if peek() == "<" then
      next_tok()
      args = {}
      if peek() ~= ">" then
        repeat
          table.insert(args, parse_type())
        until not (peek() == "," and next_tok())
      end
      if peek() == ">" then
        next_tok()
      end
    end
    return type_new("named", { name = name, args = args })
  end

  return parse_type()
end

local function convert_type_vars(t, params)
  if not t then
    return nil
  end
  if t.kind == "named" and params and params[t.name] then
    return type_var(t.name)
  end
  if t.kind == "ref" then
    return type_ref(convert_type_vars(t.to, params), t.mutable)
  elseif t.kind == "ptr" then
    return type_ptr(convert_type_vars(t.to, params))
  elseif t.kind == "vec" then
    return type_vec(convert_type_vars(t.elem, params))
  elseif t.kind == "map" then
    return type_map(convert_type_vars(t.key, params), convert_type_vars(t.value, params))
  elseif t.kind == "set" then
    return type_set(convert_type_vars(t.elem, params))
  elseif t.kind == "result" then
    return type_result(convert_type_vars(t.ok, params), convert_type_vars(t.err, params))
  elseif t.kind == "tuple" then
    local items = {}
    for _, item in ipairs(t.items or {}) do
      table.insert(items, convert_type_vars(item, params))
    end
    return type_tuple(items)
  elseif t.kind == "named" then
    local args = nil
    if t.args then
      args = {}
      for _, arg in ipairs(t.args) do
        table.insert(args, convert_type_vars(arg, params))
      end
    end
    return type_new("named", { name = t.name, args = args })
  end
  return t
end
local resolve_type
local build_struct_type
local build_enum_type

local numeric_names = {
  i8 = true,
  i16 = true,
  i32 = true,
  i64 = true,
  u8 = true,
  u16 = true,
  u32 = true,
  u64 = true,
  f32 = true,
  f64 = true,
  int = true,
  float = true,
  isize = true,
  usize = true,
}

build_struct_type = function(ctx, name, args, outer_params)
  local def = ctx.structs[name]
  if not def then
    return type_unknown()
  end
  local param_map = {}
  if def.params and #def.params > 0 then
    if not args or #args < #def.params then
      report(ctx, "Struct " .. name .. " expects " .. #def.params .. " type argument(s)")
    end
    for i, p in ipairs(def.params) do
      if not args or not args[i] then
        param_map[p] = type_unknown()
      else
        param_map[p] = resolve_type(ctx, args[i], outer_params)
      end
    end
  end
  local fields = {}
  for _, field in ipairs(def.field_list) do
    fields[field.name] = resolve_type(ctx, field.type, param_map)
  end
  local resolved_args = {}
  if args then
    for _, arg in ipairs(args) do
      table.insert(resolved_args, resolve_type(ctx, arg, outer_params))
    end
  end
  return type_struct(name, fields, resolved_args)
end

build_enum_type = function(ctx, name, args, outer_params)
  local def = ctx.enums[name]
  if not def then
    return type_unknown()
  end
  local param_map = {}
  if def.params and #def.params > 0 then
    if not args or #args < #def.params then
      report(ctx, "Enum " .. name .. " expects " .. #def.params .. " type argument(s)")
    end
    for i, p in ipairs(def.params) do
      if not args or not args[i] then
        param_map[p] = type_unknown()
      else
        param_map[p] = resolve_type(ctx, args[i], outer_params)
      end
    end
  end
  local variants = {}
  for _, variant in ipairs(def.variants) do
    if variant.types and #variant.types > 0 then
      if #variant.types > 1 then
        report(ctx, "Enum variant " .. name .. "." .. variant.name .. " supports at most one payload")
        variants[variant.name] = type_unknown()
      else
        variants[variant.name] = resolve_type(ctx, variant.types[1], param_map)
      end
    else
      variants[variant.name] = false
    end
  end
  local resolved_args = {}
  if args then
    for _, arg in ipairs(args) do
      table.insert(resolved_args, resolve_type(ctx, arg, outer_params))
    end
  end
  return type_enum(name, variants, resolved_args)
end

resolve_type = function(ctx, t, type_params, depth)
  depth = depth or 0
  if depth > 32 then
    return type_unknown()
  end
  if not t then
    return type_unknown()
  end
  if t.kind == "var" then
    if type_params and type_params[t.name] then
      return type_params[t.name]
    end
    return t
  elseif t.kind == "ref" then
    return type_ref(resolve_type(ctx, t.to, type_params, depth + 1), t.mutable)
  elseif t.kind == "ptr" then
    return type_ptr(resolve_type(ctx, t.to, type_params, depth + 1))
  elseif t.kind == "tuple" then
    local items = {}
    for _, item in ipairs(t.items or {}) do
      table.insert(items, resolve_type(ctx, item, type_params, depth + 1))
    end
    return type_tuple(items)
  elseif t.kind == "vec" then
    return type_vec(resolve_type(ctx, t.elem, type_params, depth + 1))
  elseif t.kind == "map" then
    return type_map(resolve_type(ctx, t.key, type_params, depth + 1), resolve_type(ctx, t.value, type_params, depth + 1))
  elseif t.kind == "set" then
    return type_set(resolve_type(ctx, t.elem, type_params, depth + 1))
  elseif t.kind == "result" then
    return type_result(resolve_type(ctx, t.ok, type_params, depth + 1), resolve_type(ctx, t.err, type_params, depth + 1))
  elseif t.kind == "sender" then
    return type_sender(resolve_type(ctx, t.item, type_params, depth + 1))
  elseif t.kind == "receiver" then
    return type_receiver(resolve_type(ctx, t.item, type_params, depth + 1))
  elseif t.kind == "named" then
    local name = t.name
    if type_params and type_params[name] then
      return type_params[name]
    end
    if ctx.aliases[name] then
      return resolve_type(ctx, ctx.aliases[name], type_params, depth + 1)
    end
    if numeric_names[name] then
      return type_num()
    end
    if name == "bool" then
      return type_bool()
    end
    if name == "str" or name == "string" or name == "char" then
      return type_str()
    end
    if name == "nil" then
      return type_nil()
    end
    if name == "void" then
      return type_void()
    end
    if name == "any" then
      return type_any()
    end
    if name == "unknown" then
      return type_unknown()
    end
    if name == "Result" then
      if not t.args or #t.args == 0 then
        report(ctx, "Result expects type arguments")
        return type_unknown()
      end
      local ok = resolve_type(ctx, t.args[1], type_params, depth + 1)
      local err = nil
      if t.args[2] then
        err = resolve_type(ctx, t.args[2], type_params, depth + 1)
      else
        err = type_str()
      end
      return type_result(ok, err)
    end
    if name == "Vec" then
      if not t.args or not t.args[1] then
        report(ctx, "Vec expects 1 type argument")
        return type_vec(type_unknown())
      end
      local elem = resolve_type(ctx, t.args[1], type_params, depth + 1)
      return type_vec(elem)
    end
    if name == "Map" then
      if not t.args or not t.args[1] or not t.args[2] then
        report(ctx, "Map expects 2 type arguments")
        return type_map(type_unknown(), type_unknown())
      end
      local key = resolve_type(ctx, t.args[1], type_params, depth + 1)
      local value = resolve_type(ctx, t.args[2], type_params, depth + 1)
      return type_map(key, value)
    end
    if name == "Set" then
      if not t.args or not t.args[1] then
        report(ctx, "Set expects 1 type argument")
        return type_set(type_unknown())
      end
      local elem = resolve_type(ctx, t.args[1], type_params, depth + 1)
      return type_set(elem)
    end
    if name == "Sender" then
      if not t.args or not t.args[1] then
        report(ctx, "Sender expects 1 type argument")
        return type_sender(type_unknown())
      end
      local elem = resolve_type(ctx, t.args[1], type_params, depth + 1)
      return type_sender(elem)
    end
    if name == "Receiver" then
      if not t.args or not t.args[1] then
        report(ctx, "Receiver expects 1 type argument")
        return type_receiver(type_unknown())
      end
      local elem = resolve_type(ctx, t.args[1], type_params, depth + 1)
      return type_receiver(elem)
    end
    if name == "Ptr" or name == "Box" then
      if not t.args or not t.args[1] then
        report(ctx, "Ptr expects 1 type argument")
        return type_ptr(type_unknown())
      end
      local elem = resolve_type(ctx, t.args[1], type_params, depth + 1)
      return type_ptr(elem)
    end
    if ctx.structs[name] then
      return build_struct_type(ctx, name, t.args, type_params)
    end
    if ctx.enums[name] then
      return build_enum_type(ctx, name, t.args, type_params)
    end
    report(ctx, "Unknown type: " .. name)
    return type_unknown()
  end
  return t
end

local function sig(params, ret, generics)
  return { params = params, ret = ret, generics = generics }
end

local builtins = {
  println = sig({ type_var("T") }, type_void(), { "T" }),
  print = sig({ type_var("T") }, type_void(), { "T" }),
  channel = sig({}, type_tuple({ type_sender(type_var("T")), type_receiver(type_var("T")) }), { "T" }),
  sleep = sig({ type_num() }, type_void()),
  now_ms = sig({}, type_num()),
  format = sig({ type_var("T") }, type_str(), { "T" }),
  Ok = sig({ type_var("T") }, type_result(type_var("T"), type_var("E")), { "T", "E" }),
  Err = sig({ type_var("E") }, type_result(type_var("T"), type_var("E")), { "T", "E" }),
  alloc = sig({}, type_ptr(type_var("T")), { "T" }),
  free = sig({ type_ptr(type_var("T")) }, type_void(), { "T" }),
  box = sig({ type_var("T") }, type_ptr(type_var("T")), { "T" }),
  unbox = sig({ type_ptr(type_var("T")) }, type_var("T"), { "T" }),
  drop = sig({ type_var("T") }, type_void(), { "T" }),
  sqrt = sig({ type_num() }, type_num()),
  abs = sig({ type_num() }, type_num()),
}

local modules = {
  io = {
    println = builtins.println,
    print = builtins.print,
    read_file = sig({ type_ref(type_str(), false) }, type_result(type_str(), type_str())),
    write_file = sig({ type_ref(type_str(), false), type_var("T") }, type_result(type_bool(), type_str()), { "T" }),
    read_line = sig({}, type_result(type_str(), type_str())),
    read_lines = sig({ type_ref(type_str(), false) }, type_result(type_vec(type_str()), type_str())),
    write_lines = sig({ type_ref(type_str(), false), type_ref(type_vec(type_str()), false) }, type_result(type_bool(), type_str())),
  },
  fs = {
    exists = sig({ type_ref(type_str(), false) }, type_bool()),
    mkdir = sig({ type_ref(type_str(), false) }, type_result(type_bool(), type_str())),
    remove = sig({ type_ref(type_str(), false) }, type_result(type_bool(), type_str())),
  },
  thread = {
    channel = builtins.channel,
    wait_all = sig({}, type_void()),
  },
  time = {
    sleep = sig({ type_num() }, type_void()),
    sleep_s = sig({ type_num() }, type_void()),
    now_ms = sig({}, type_num()),
    now_s = sig({}, type_num()),
    now_ns = sig({}, type_num()),
    since = sig({ type_num() }, type_num()),
  },
  fmt = {
    format = builtins.format,
  },
  mem = {
    alloc = builtins.alloc,
    free = builtins.free,
    box = builtins.box,
    unbox = builtins.unbox,
    drop = builtins.drop,
  },
  math = {
    sqrt = sig({ type_num() }, type_num()),
    abs = sig({ type_num() }, type_num()),
  },
  collections = {
    vec_new = sig({}, type_vec(type_var("T")), { "T" }),
    vec_push = sig({ type_ref(type_vec(type_var("T")), true), type_var("T") }, type_void(), { "T" }),
    vec_get = sig({ type_ref(type_vec(type_var("T")), false), type_num() }, type_var("T"), { "T" }),
    vec_set = sig({ type_ref(type_vec(type_var("T")), true), type_num(), type_var("T") }, type_void(), { "T" }),
    vec_len = sig({ type_ref(type_vec(type_var("T")), false) }, type_num(), { "T" }),
    vec_insert = sig({ type_ref(type_vec(type_var("T")), true), type_num(), type_var("T") }, type_void(), { "T" }),
    vec_slice = sig({ type_ref(type_vec(type_var("T")), false), type_num(), type_num() }, type_vec(type_var("T")), { "T" }),
    vec_from = sig({}, type_vec(type_var("T")), { "T" }),
    vec_pop = sig({ type_ref(type_vec(type_var("T")), true) }, type_var("T"), { "T" }),
    vec_clear = sig({ type_ref(type_vec(type_var("T")), true) }, type_void(), { "T" }),
    vec_sort = sig({ type_ref(type_vec(type_var("T")), true) }, type_void(), { "T" }),
    map_new = sig({}, type_map(type_var("K"), type_var("V")), { "K", "V" }),
    map_put = sig({ type_ref(type_map(type_var("K"), type_var("V")), true), type_var("K"), type_var("V") }, type_void(), { "K", "V" }),
    map_get = sig({ type_ref(type_map(type_var("K"), type_var("V")), false), type_var("K") }, type_var("V"), { "K", "V" }),
    map_remove = sig({ type_ref(type_map(type_var("K"), type_var("V")), true), type_var("K") }, type_bool(), { "K", "V" }),
    map_has = sig({ type_ref(type_map(type_var("K"), type_var("V")), false), type_var("K") }, type_bool(), { "K", "V" }),
    map_keys = sig({ type_ref(type_map(type_var("K"), type_var("V")), false) }, type_vec(type_var("K")), { "K", "V" }),
    set_new = sig({}, type_set(type_var("T")), { "T" }),
    set_add = sig({ type_ref(type_set(type_var("T")), true), type_var("T") }, type_void(), { "T" }),
    set_has = sig({ type_ref(type_set(type_var("T")), false), type_var("T") }, type_bool(), { "T" }),
    set_remove = sig({ type_ref(type_set(type_var("T")), true), type_var("T") }, type_bool(), { "T" }),
  },
  os = {
    getenv = sig({ type_ref(type_str(), false) }, type_str()),
    cwd = sig({}, type_str()),
  },
  net = {
    tcp_connect = sig({ type_ref(type_str(), false) }, type_result(type_str(), type_str())),
    udp_socket = sig({}, type_result(type_str(), type_str())),
  },
  http = {
    get = sig({ type_ref(type_str(), false) }, type_result(type_str(), type_str())),
    get_status = sig({ type_ref(type_str(), false) }, type_result(type_map(type_str(), type_str()), type_str())),
    get_json = sig({ type_ref(type_str(), false) }, type_result(type_var("T"), type_str()), { "T" }),
  },
  random = {
    seed = sig({ type_num() }, type_void()),
    int = sig({ type_num(), type_num() }, type_num()),
    float = sig({}, type_num()),
    bool = sig({ type_num() }, type_bool()),
    choice = sig({ type_ref(type_vec(type_var("T")), false) }, type_var("T"), { "T" }),
    shuffle = sig({ type_ref(type_vec(type_var("T")), true) }, type_void(), { "T" }),
    range = sig({ type_num(), type_num() }, type_num()),
  },
  json = {
    encode = sig({ type_var("T") }, type_result(type_str(), type_str()), { "T" }),
    encode_pretty = sig({ type_var("T"), type_num() }, type_result(type_str(), type_str()), { "T" }),
    decode = sig({ type_ref(type_str(), false) }, type_result(type_var("T"), type_str()), { "T" }),
  },
  result = {
    Ok = builtins.Ok,
    Err = builtins.Err,
  },
  ui = {
    begin = sig({ type_any(), type_num(), type_num() }, type_bool()),
    ["end"] = sig({}, type_void()),
    redraw = sig({}, type_void()),
    clear = sig({ type_any() }, type_void()),
    key_space = sig({}, type_bool()),
    key_up = sig({}, type_bool()),
    key_down = sig({}, type_bool()),
    mouse_x = sig({}, type_num()),
    mouse_y = sig({}, type_num()),
    mouse_down = sig({}, type_bool()),
    mouse_pressed = sig({}, type_bool()),
    mouse_released = sig({}, type_bool()),
    label = sig({ type_any() }, type_void()),
    text = sig({ type_num(), type_num(), type_any(), type_any() }, type_void()),
    button = sig({ type_any() }, type_bool()),
    checkbox = sig({ type_any(), type_bool() }, type_bool()),
    radio = sig({ type_any(), type_bool() }, type_bool()),
    textbox = sig({ type_str(), type_num() }, type_str()),
    slider = sig({ type_any(), type_num(), type_num(), type_num() }, type_num()),
    progress = sig({ type_num(), type_num() }, type_void()),
    switch = sig({ type_any(), type_bool() }, type_bool()),
    select = sig({ type_ref(type_vec(type_var("T")), false), type_num() }, type_num(), { "T" }),
    combo = sig({ type_ref(type_vec(type_var("T")), false), type_num() }, type_num(), { "T" }),
    menu = sig({ type_ref(type_vec(type_var("T")), false), type_num() }, type_num(), { "T" }),
    tabs = sig({ type_ref(type_vec(type_var("T")), false), type_num() }, type_num(), { "T" }),
    row = sig({ type_num() }, type_void()),
    column = sig({ type_num() }, type_void()),
    grid = sig({ type_num(), type_num(), type_num() }, type_void()),
    newline = sig({}, type_void()),
    row_end = sig({}, type_void()),
    clip_begin = sig({ type_num(), type_num(), type_num(), type_num() }, type_void()),
    clip_end = sig({}, type_void()),
    spacing = sig({ type_num() }, type_void()),
    padding = sig({ type_num() }, type_void()),
    scroll_begin = sig({ type_num() }, type_void()),
    scroll_end = sig({}, type_void()),
    enabled = sig({ type_bool() }, type_void()),
    invert = sig({ type_bool() }, type_void()),
    titlebar_dark = sig({ type_bool() }, type_void()),
    theme_dark = sig({}, type_void()),
    theme_light = sig({}, type_void()),
    theme_custom = sig({ type_any(), type_any(), type_any(), type_any(), type_any(), type_any(), type_any(), type_any(), type_any() }, type_void()),
    image_load = sig({ type_any() }, type_any()),
    image_w = sig({ type_any() }, type_num()),
    image_h = sig({ type_any() }, type_num()),
    image = sig({ type_any(), type_num(), type_num() }, type_void()),
    image_region = sig({ type_any(), type_num(), type_num(), type_num(), type_num(), type_num(), type_num(), type_num(), type_num() }, type_void()),
    play_sound = sig({ type_any() }, type_bool()),
  },
}
local function scope_push(ctx)
  table.insert(ctx.scopes, {})
end

local function scope_pop(ctx)
  table.remove(ctx.scopes)
end

local function scope_set(ctx, name, info)
  ctx.scopes[#ctx.scopes][name] = info
end

local function scope_get(ctx, name)
  for i = #ctx.scopes, 1, -1 do
    local info = ctx.scopes[i][name]
    if info then
      return info
    end
  end
  return nil
end

local function own_scope_push(ctx)
  table.insert(ctx.ownership.scopes, {})
  if ctx.ownership.defer_stack then
    table.insert(ctx.ownership.defer_stack, {})
  end
end

local function own_scope_pop(ctx)
  local scope = table.remove(ctx.ownership.scopes)
  for _, id in pairs(scope) do
    local var = ctx.ownership.vars[id]
    if var and var.ref_target then
      local target = ctx.ownership.vars[var.ref_target]
      if target then
        if var.ref_mut then
          target.borrow_mut = (target.borrow_mut or 1) - 1
        else
          target.borrow_imm = (target.borrow_imm or 1) - 1
        end
      end
    end
  end
  local defers = ctx.ownership.defer_stack and table.remove(ctx.ownership.defer_stack) or nil
  if defers then
    for _, entry in ipairs(defers) do
      local var = ctx.ownership.vars[entry.id]
      if var then
        local count = entry.count or 1
        if entry.is_mut then
          var.borrow_mut = (var.borrow_mut or 0) - count
          if var.borrow_mut < 0 then
            var.borrow_mut = 0
          end
        else
          var.borrow_imm = (var.borrow_imm or 0) - count
          if var.borrow_imm < 0 then
            var.borrow_imm = 0
          end
        end
      end
    end
  end
end

local function own_resolve(ctx, name)
  for i = #ctx.ownership.scopes, 1, -1 do
    local id = ctx.ownership.scopes[i][name]
    if id then
      return id
    end
  end
  return nil
end

local function own_add_borrow(ctx, id, is_mut)
  local var = ctx.ownership.vars[id]
  if not var then
    return
  end
  if is_mut then
    var.borrow_mut = (var.borrow_mut or 0) + 1
  else
    var.borrow_imm = (var.borrow_imm or 0) + 1
  end
end

local function own_remove_borrow(ctx, id, is_mut)
  local var = ctx.ownership.vars[id]
  if not var then
    return
  end
  if is_mut then
    var.borrow_mut = (var.borrow_mut or 1) - 1
  else
    var.borrow_imm = (var.borrow_imm or 1) - 1
  end
end

local function own_check_lifetime(ctx, ref_target, dest_depth, where)
  if not ref_target or not dest_depth then
    return
  end
  local target = ctx.ownership.vars[ref_target]
  if not target or not target.scope_depth then
    return
  end
  if target.scope_depth > dest_depth then
    report(ctx, (where or "reference") .. " outlives value " .. target.name)
  end
end

local function own_bind(ctx, name, info, opts)
  local id = ctx.ownership.next_id
  ctx.ownership.next_id = id + 1
  local ref_target = opts and opts.ref_target or nil
  local ref_mut = opts and opts.ref_mut or false
  local transfer = opts and opts.transfer or false
  local transfer_from = opts and opts.transfer_from or nil
  local scope_depth = #ctx.ownership.scopes
  ctx.ownership.vars[id] = {
    name = name,
    type = info.type,
    mutable = info.mutable and true or false,
    moved = false,
    ref_target = ref_target,
    ref_mut = ref_mut,
    borrow_imm = 0,
    borrow_mut = 0,
    scope_depth = scope_depth,
  }
  ctx.ownership.scopes[#ctx.ownership.scopes][name] = id
  if ref_target then
    own_check_lifetime(ctx, ref_target, scope_depth, "Borrow")
  end
  if ref_target and not transfer then
    own_add_borrow(ctx, ref_target, ref_mut)
  end
  if transfer_from then
    local src = ctx.ownership.vars[transfer_from]
    if src then
      src.moved = true
      src.ref_target = nil
      src.ref_mut = false
    end
  end
  return id
end

local function own_mark_moved(ctx, id, where)
  local var = ctx.ownership.vars[id]
  if not var then
    return
  end
  if var.moved then
    report(ctx, (where or var.name) .. " was moved")
    return
  end
  if var.borrow_mut and var.borrow_mut > 0 then
    report(ctx, "Cannot move " .. var.name .. " while it is mutably borrowed")
    return
  end
  if var.borrow_imm and var.borrow_imm > 0 then
    report(ctx, "Cannot move " .. var.name .. " while it is borrowed")
    return
  end
  if var.ref_target then
    own_remove_borrow(ctx, var.ref_target, var.ref_mut)
    var.ref_target = nil
    var.ref_mut = false
  end
  var.moved = true
end

local function own_use_value(ctx, name, where)
  local id = own_resolve(ctx, name)
  if not id then
    return
  end
  local var = ctx.ownership.vars[id]
  if var.moved then
    report(ctx, (where or name) .. " was moved")
    return
  end
  if ctx.ownership.defer_mode then
    local entry = ctx.ownership.defer_use[id]
    if not entry then
      entry = { imm = 0, mut = 0 }
      ctx.ownership.defer_use[id] = entry
    end
    entry.imm = entry.imm + 1
    return
  end
  if type_is_copy(var.type) then
    return
  end
  own_mark_moved(ctx, id, where)
end

local function own_can_borrow(ctx, id, is_mut, where)
  local var = ctx.ownership.vars[id]
  if not var then
    return false
  end
  if var.moved then
    report(ctx, (where or var.name) .. " was moved")
    return false
  end
  if is_mut then
    if not var.mutable then
      report(ctx, "Cannot take &mut of immutable " .. var.name)
      return false
    end
    if (var.borrow_mut and var.borrow_mut > 0) or (var.borrow_imm and var.borrow_imm > 0) then
      report(ctx, "Cannot take &mut " .. var.name .. " while borrowed")
      return false
    end
  else
    if var.borrow_mut and var.borrow_mut > 0 then
      report(ctx, "Cannot take &" .. var.name .. " while mutably borrowed")
      return false
    end
  end
  return true
end

local function own_borrow_temp(ctx, id, is_mut)
  if not own_can_borrow(ctx, id, is_mut) then
    return
  end
  if ctx.ownership.defer_mode then
    local entry = ctx.ownership.defer_use[id]
    if not entry then
      entry = { imm = 0, mut = 0 }
      ctx.ownership.defer_use[id] = entry
    end
    if is_mut then
      entry.mut = entry.mut + 1
    else
      entry.imm = entry.imm + 1
    end
    return
  end
  own_add_borrow(ctx, id, is_mut)
  table.insert(ctx.ownership.temp_borrows, { id = id, is_mut = is_mut })
end

local function own_release_temp(ctx)
  if ctx.ownership.defer_mode then
    return
  end
  for i = #ctx.ownership.temp_borrows, 1, -1 do
    local b = ctx.ownership.temp_borrows[i]
    own_remove_borrow(ctx, b.id, b.is_mut)
  end
  ctx.ownership.temp_borrows = {}
end

local function own_clone(state)
  local vars = {}
  for id, var in pairs(state.vars or {}) do
    vars[id] = {
      name = var.name,
      type = var.type,
      mutable = var.mutable,
      moved = var.moved,
      ref_target = var.ref_target,
      ref_mut = var.ref_mut,
      borrow_imm = var.borrow_imm,
      borrow_mut = var.borrow_mut,
      scope_depth = var.scope_depth,
    }
  end
  local scopes = {}
  for i, scope in ipairs(state.scopes or {}) do
    local s = {}
    for name, id in pairs(scope) do
      s[name] = id
    end
    scopes[i] = s
  end
  local temp_borrows = {}
  for i, b in ipairs(state.temp_borrows or {}) do
    temp_borrows[i] = { id = b.id, is_mut = b.is_mut }
  end
  local defer_stack = {}
  for i, list in ipairs(state.defer_stack or {}) do
    local out = {}
    for j, entry in ipairs(list) do
      out[j] = { id = entry.id, is_mut = entry.is_mut, count = entry.count }
    end
    defer_stack[i] = out
  end
  return {
    next_id = state.next_id,
    scopes = scopes,
    vars = vars,
    temp_borrows = temp_borrows,
    defer_stack = defer_stack,
    defer_use = {},
  }
end

local function own_apply_defer_uses(base, uses)
  local list = base.defer_stack and base.defer_stack[#base.defer_stack] or nil
  if not list then
    return
  end
  for id, entry in pairs(uses or {}) do
    local var = base.vars[id]
    if var then
      local imm = entry.imm or 0
      local mut = entry.mut or 0
      if imm > 0 then
        var.borrow_imm = (var.borrow_imm or 0) + imm
        table.insert(list, { id = id, is_mut = false, count = imm })
      end
      if mut > 0 then
        var.borrow_mut = (var.borrow_mut or 0) + mut
        table.insert(list, { id = id, is_mut = true, count = mut })
      end
    end
  end
end

report = function(ctx, msg)
  local prefix = ctx.current_func or "<top>"
  table.insert(ctx.errors, prefix .. ": " .. msg)
end

local function expect_value(ctx, t, where)
  if t and t.kind == "void" then
    report(ctx, (where or "value") .. " cannot be void")
    return type_unknown()
  end
  return t
end

local function expect_numeric(ctx, t, where)
  if not t then
    return false
  end
  if t.kind == "num" then
    return true
  end
  if t.kind == "unknown" then
    report(ctx, (where or "value") .. " has unknown type; expected number")
    return false
  end
  if t.kind == "var" then
    report(ctx, (where or "value") .. " uses type parameter " .. t.name .. " without numeric constraint")
    return false
  end
  report(ctx, (where or "value") .. " expects number, got " .. type_to_string(t))
  return false
end

local function expect_bool(ctx, t, where)
  if not t then
    return false
  end
  if t.kind == "bool" then
    return true
  end
  if t.kind == "unknown" then
    report(ctx, (where or "value") .. " has unknown type; expected bool")
    return false
  end
  if t.kind == "var" then
    report(ctx, (where or "value") .. " uses type parameter " .. t.name .. " without bool constraint")
    return false
  end
  report(ctx, (where or "value") .. " expects bool, got " .. type_to_string(t))
  return false
end

local infer_expr
local infer_call
local infer_member
local check_block

local function resolve_type_args(ctx, list)
  local resolved = {}
  for _, raw in ipairs(list or {}) do
    local parsed = parse_type_string(raw)
    table.insert(resolved, resolve_type(ctx, parsed, nil))
  end
  return resolved
end

local function bind_type_var(ctx, name, actual, param_map, where)
  local bound = param_map[name]
  if bound then
    if not type_assignable(bound, actual) then
      report(ctx, (where or "value") .. " expects " .. type_to_string(bound) .. ", got " .. type_to_string(actual))
    end
    return bound
  end
  if actual.kind == "unknown" then
    report(ctx, "Cannot infer type parameter " .. name .. " from " .. (where or "value"))
    return type_unknown()
  end
  param_map[name] = actual
  return actual
end

local function unify_type(ctx, expected, actual, param_map, where)
  if not expected or not actual then
    return type_unknown()
  end
  if expected.kind == "var" then
    return bind_type_var(ctx, expected.name, actual, param_map, where)
  end
  if actual.kind == "var" then
    return bind_type_var(ctx, actual.name, expected, param_map, where)
  end
  if expected.kind == "any" then
    return actual
  end
  if actual.kind == "any" then
    return expected
  end
  if expected.kind ~= actual.kind then
    report(ctx, (where or "value") .. " expects " .. type_to_string(expected) .. ", got " .. type_to_string(actual))
    return type_unknown()
  end
  if expected.kind == "ref" then
    if expected.mutable and not actual.mutable then
      report(ctx, (where or "value") .. " expects " .. type_to_string(expected) .. ", got " .. type_to_string(actual))
      return type_unknown()
    end
    return type_ref(unify_type(ctx, expected.to, actual.to, param_map, where), expected.mutable)
  elseif expected.kind == "ptr" then
    return type_ptr(unify_type(ctx, expected.to, actual.to, param_map, where))
  elseif expected.kind == "vec" then
    return type_vec(unify_type(ctx, expected.elem, actual.elem, param_map, where))
  elseif expected.kind == "map" then
    return type_map(
      unify_type(ctx, expected.key, actual.key, param_map, where),
      unify_type(ctx, expected.value, actual.value, param_map, where)
    )
  elseif expected.kind == "set" then
    return type_set(unify_type(ctx, expected.elem, actual.elem, param_map, where))
  elseif expected.kind == "result" then
    return type_result(
      unify_type(ctx, expected.ok, actual.ok, param_map, where),
      unify_type(ctx, expected.err, actual.err, param_map, where)
    )
  elseif expected.kind == "tuple" then
    if #expected.items ~= #actual.items then
      report(ctx, (where or "value") .. " expects tuple size " .. #expected.items .. ", got " .. #actual.items)
      return type_unknown()
    end
    local items = {}
    for i = 1, #expected.items do
      table.insert(items, unify_type(ctx, expected.items[i], actual.items[i], param_map, where))
    end
    return type_tuple(items)
  elseif expected.kind == "sender" then
    return type_sender(unify_type(ctx, expected.item, actual.item, param_map, where))
  elseif expected.kind == "receiver" then
    return type_receiver(unify_type(ctx, expected.item, actual.item, param_map, where))
  elseif expected.kind == "struct" or expected.kind == "enum" then
    if expected.name ~= actual.name then
      report(ctx, (where or "value") .. " expects " .. expected.name .. ", got " .. actual.name)
      return type_unknown()
    end
    local args = {}
    local expected_args = expected.args or {}
    local actual_args = actual.args or {}
    if #expected_args ~= #actual_args then
      report(ctx, (where or "value") .. " expects " .. #expected_args .. " type argument(s), got " .. #actual_args)
      return type_unknown()
    end
    for i = 1, #expected_args do
      table.insert(args, unify_type(ctx, expected_args[i], actual_args[i], param_map, where))
    end
    if expected.kind == "struct" then
      return type_struct(expected.name, expected.fields, args)
    end
    return type_enum(expected.name, expected.variants, args)
  elseif expected.kind == "fn" then
    if #expected.params ~= #actual.params then
      report(ctx, (where or "value") .. " expects " .. #expected.params .. " parameter(s), got " .. #actual.params)
      return type_unknown()
    end
    local params = {}
    for i = 1, #expected.params do
      table.insert(params, unify_type(ctx, expected.params[i], actual.params[i], param_map, where))
    end
    local ret = unify_type(ctx, expected.ret, actual.ret, param_map, where)
    return type_fn(params, ret)
  end
  return expected
end

local function infer_arg_type(ctx, expected, arg, where)
  if expected and expected.kind == "ref" and arg.kind == "Identifier" then
    report(ctx, (where or "argument") .. " expects " .. type_to_string(expected) .. "; use &")
    local info = scope_get(ctx, arg.name)
    if info then
      return info.type
    end
    return type_unknown()
  end
  return expect_value(ctx, infer_expr(ctx, arg), where)
end

local function apply_signature(ctx, sig, args, type_args)
  local param_map = {}
  local generics = sig.generics or {}
  if type_args and #type_args > 0 and #generics == 0 then
    report(ctx, "Type arguments provided for non-generic function")
  end
  if #generics > 0 then
    if type_args and #type_args > 0 and #type_args ~= #generics then
      report(ctx, "Expected " .. #generics .. " type argument(s), got " .. #type_args)
    end
    for i, name in ipairs(generics) do
      if type_args and type_args[i] then
        param_map[name] = type_args[i]
      end
    end
  end
  if #args ~= #sig.params then
    report(ctx, "Expected " .. #sig.params .. " argument(s), got " .. #args)
  end
  local limit = math.min(#args, #sig.params)
  for i = 1, limit do
    local expected = resolve_type(ctx, sig.params[i], param_map)
    local actual = infer_arg_type(ctx, expected, args[i], "argument " .. i)
    unify_type(ctx, expected, actual, param_map, "argument " .. i)
  end
  if #generics > 0 then
    for _, name in ipairs(generics) do
      if not param_map[name] or param_map[name].kind == "unknown" then
        report(ctx, "Cannot infer type parameter " .. name .. "; provide explicit type arguments")
        param_map[name] = param_map[name] or type_unknown()
      end
    end
  end
  return resolve_type(ctx, sig.ret, param_map)
end

local function infer_result_literal(ctx, expr, expected, where)
  if not expr or expr.kind ~= "Call" then
    return nil
  end
  if not expected or expected.kind ~= "result" then
    return nil
  end
  local callee = expr.callee
  if callee.kind ~= "Identifier" then
    return nil
  end
  local name = callee.name
  if name ~= "Ok" and name ~= "Err" then
    return nil
  end
  if #expr.args ~= 1 then
    report(ctx, name .. " expects 1 argument")
    return expected
  end
  local payload_expected = name == "Ok" and expected.ok or expected.err
  local actual = expect_value(ctx, infer_expr(ctx, expr.args[1]), (where or name) .. " payload")
  if payload_expected and payload_expected.kind ~= "unknown" and not type_assignable(payload_expected, actual) then
    report(ctx, name .. " payload expects " .. type_to_string(payload_expected) .. ", got " .. type_to_string(actual))
  end
  return type_result(expected.ok or type_unknown(), expected.err or type_unknown())
end

infer_expr = function(ctx, expr)
  if not expr then
    return type_void()
  end
  if expr.kind == "Number" then
    return type_num()
  elseif expr.kind == "String" then
    return type_str()
  elseif expr.kind == "Bool" then
    return type_bool()
  elseif expr.kind == "Nil" then
    return type_nil()
  elseif expr.kind == "Identifier" then
    -- RULE 1 PRIORITY: Check if identifier was rolled back FIRST
    
    if bond_is_rolled_back(ctx, expr.name) then
      report(ctx, "use of rolled-back bond variable '" .. expr.name .. "'")
      return type_unknown()
    end
    
    local info = scope_get(ctx, expr.name)
    
    if info then
      own_use_value(ctx, expr.name, expr.name)
      return info.type
    end
    local sig = ctx.functions[expr.name] or ctx.builtins[expr.name]
    if sig then
      return type_fn(sig.params, sig.ret)
    end
    report(ctx, "Unknown identifier: " .. expr.name)
    return type_unknown()
  elseif expr.kind == "Array" then
    local elem = nil
    for _, e in ipairs(expr.elements or {}) do
      local t = expect_value(ctx, infer_expr(ctx, e), "array element")
      elem = elem and type_merge(ctx, elem, t, "array element") or t
    end
    if not elem then
      elem = type_unknown()
    end
    return type_vec(elem)
  elseif expr.kind == "Binary" then
    local left = expect_value(ctx, infer_expr(ctx, expr.left), "left operand")
    local right = expect_value(ctx, infer_expr(ctx, expr.right), "right operand")
    local op = expr.op
    if op == "+" then
      if left.kind == "unknown" or right.kind == "unknown" then
        report(ctx, "Operator + requires concrete types")
        return type_unknown()
      end
      if left.kind == "var" then
        report(ctx, "Operator + is not defined for type parameter " .. left.name)
        return type_unknown()
      end
      if right.kind == "var" then
        report(ctx, "Operator + is not defined for type parameter " .. right.name)
        return type_unknown()
      end
      if left.kind == "str" or right.kind == "str" then
        return type_str()
      end
      if left.kind == "num" and right.kind == "num" then
        return type_num()
      end
      report(ctx, "Operator + expects numbers or strings")
      return type_unknown()
    elseif op == "-" or op == "*" or op == "/" or op == "%" then
      expect_numeric(ctx, left, "Left operand")
      expect_numeric(ctx, right, "Right operand")
      return type_num()
    elseif op == "<" or op == "<=" or op == ">" or op == ">=" then
      expect_numeric(ctx, left, "Left operand")
      expect_numeric(ctx, right, "Right operand")
      return type_bool()
    elseif op == "==" or op == "!=" then
      return type_bool()
    elseif op == "&&" or op == "||" then
      expect_bool(ctx, left, "Left operand")
      expect_bool(ctx, right, "Right operand")
      return type_bool()
    end
    return type_unknown()
  elseif expr.kind == "Unary" then
    local inner = expect_value(ctx, infer_expr(ctx, expr.expr), "unary operand")
    if expr.op == "-" then
      expect_numeric(ctx, inner, "Unary - operand")
      return type_num()
    elseif expr.op == "!" then
      expect_bool(ctx, inner, "Unary ! operand")
      return type_bool()
    end
    return type_unknown()
  elseif expr.kind == "Deref" then
    local inner = nil
    if expr.expr.kind == "Identifier" then
      local info = scope_get(ctx, expr.expr.name)
      if info then
        local id = own_resolve(ctx, expr.expr.name)
        if id then
          own_borrow_temp(ctx, id, false)
        end
        inner = info.type
      end
    end
    if not inner then
      inner = expect_value(ctx, infer_expr(ctx, expr.expr), "deref")
    end
    if inner.kind == "ptr" or inner.kind == "ref" then
      return inner.to
    end
    if inner.kind == "unknown" or inner.kind == "any" then
      return type_unknown()
    end
    report(ctx, "Cannot dereference non-pointer")
    return type_unknown()
  elseif expr.kind == "Borrow" then
    local target = expr.expr
    if not target or target.kind ~= "Identifier" then
      report(ctx, "Borrow expects identifier")
      return type_ref(type_unknown(), expr.mutable)
    end
    local info = scope_get(ctx, target.name)
    if not info then
      report(ctx, "Unknown identifier: " .. target.name)
      return type_ref(type_unknown(), expr.mutable)
    end
    local id = own_resolve(ctx, target.name)
    if id then
      own_borrow_temp(ctx, id, expr.mutable)
    end
    return type_ref(info.type, expr.mutable)
  elseif expr.kind == "Try" then
    local inner = expect_value(ctx, infer_expr(ctx, expr.expr), "try")
    if inner.kind ~= "result" then
      report(ctx, "Operator ? expects Result")
      return type_unknown()
    end
    if ctx.return_type and ctx.return_type.kind ~= "result" and ctx.return_type.kind ~= "unknown" then
      report(ctx, "Operator ? requires function to return Result")
    end
    return inner.ok or type_unknown()
  elseif expr.kind == "Call" then
    return infer_call(ctx, expr)
  elseif expr.kind == "Member" then
    return infer_member(ctx, expr)
  elseif expr.kind == "Index" then
    local obj = nil
    if expr.object.kind == "Identifier" then
      local info = scope_get(ctx, expr.object.name)
      if info then
        local id = own_resolve(ctx, expr.object.name)
        if id then
          own_borrow_temp(ctx, id, false)
        end
        obj = info.type
      end
    end
    if not obj then
      obj = expect_value(ctx, infer_expr(ctx, expr.object), "index object")
    end
    local idx = expect_value(ctx, infer_expr(ctx, expr.index), "index")
    if obj.kind == "vec" then
      expect_numeric(ctx, idx, "Vector index")
      return obj.elem
    elseif obj.kind == "map" then
      return obj.value
    elseif obj.kind == "str" then
      return type_str()
    elseif obj.kind == "unknown" or obj.kind == "any" then
      return type_unknown()
    end
    report(ctx, "Indexing expects vector or map")
    return type_unknown()
  elseif expr.kind == "Slice" then
    local obj = nil
    if expr.object.kind == "Identifier" then
      local info = scope_get(ctx, expr.object.name)
      if info then
        local id = own_resolve(ctx, expr.object.name)
        if id then
          own_borrow_temp(ctx, id, false)
        end
        obj = info.type
      end
    end
    if not obj then
      obj = expect_value(ctx, infer_expr(ctx, expr.object), "slice object")
    end
    if obj.kind == "vec" then
      return type_vec(obj.elem)
    elseif obj.kind == "str" then
      return type_str()
    elseif obj.kind == "unknown" or obj.kind == "any" then
      return type_unknown()
    end
    report(ctx, "Slice expects vector or string")
    return type_unknown()
  elseif expr.kind == "Generic" then
    return infer_expr(ctx, expr.expr)
  end
  report(ctx, "Unknown expression kind: " .. tostring(expr.kind))
  return type_unknown()
end
infer_call = function(ctx, expr)
  local callee = expr.callee
  local args = expr.args or {}
  local type_args = resolve_type_args(ctx, expr.type_args)

  if callee.kind == "Identifier" then
    local sig = ctx.functions[callee.name] or ctx.builtins[callee.name]
    if sig then
      return apply_signature(ctx, sig, args, type_args)
    end
    report(ctx, "Unknown function: " .. callee.name)
    return type_unknown()
  elseif callee.kind == "Member" then
    local obj = callee.object
    local prop = callee.property
    local obj_info = nil
    local obj_id = nil
    if obj.kind == "Identifier" then
      local module = ctx.imports[obj.name]
      if module then
        if module == "collections" and prop == "vec_from" then
          local elem = nil
          for _, arg in ipairs(args) do
            local t = expect_value(ctx, infer_expr(ctx, arg), "vec_from argument")
            elem = elem and type_merge(ctx, elem, t, "vec_from element") or t
          end
          if type_args and type_args[1] then
            elem = type_args[1]
          end
          return type_vec(elem or type_unknown())
        end
        local sig = ctx.modules[module] and ctx.modules[module][prop]
        if sig then
          return apply_signature(ctx, sig, args, type_args)
        end
        report(ctx, "Unknown module function: " .. module .. "." .. prop)
        return type_unknown()
      end
      if ctx.enums[obj.name] then
        local enum_type = build_enum_type(ctx, obj.name, type_args)
        local payload = enum_type.variants[prop]
        if payload == nil then
          report(ctx, "Unknown enum variant: " .. obj.name .. "." .. prop)
          return type_unknown()
        end
        if payload == false then
          if #args ~= 0 then
            report(ctx, "Enum variant " .. obj.name .. "." .. prop .. " expects 0 arguments")
          end
          return enum_type
        end
        if #args ~= 1 then
          report(ctx, "Enum variant " .. obj.name .. "." .. prop .. " expects 1 argument")
        end
        local arg_type = args[1] and expect_value(ctx, infer_expr(ctx, args[1]), "enum payload") or type_unknown()
        if not type_assignable(payload, arg_type) then
          report(ctx, "Enum variant " .. obj.name .. "." .. prop .. " expects " .. type_to_string(payload))
        end
        return enum_type
      end
      if ctx.structs[obj.name] and prop == "new" then
        local struct_type = build_struct_type(ctx, obj.name, type_args)
        local fields = ctx.structs[obj.name].field_list
        if #args ~= #fields then
          report(ctx, "Constructor expects " .. #fields .. " argument(s), got " .. #args)
        end
        local limit = math.min(#args, #fields)
        for i = 1, limit do
          local expected = resolve_type(ctx, fields[i].type, nil)
          local actual = expect_value(ctx, infer_expr(ctx, args[i]), "constructor argument")
          if expected and not type_assignable(expected, actual) then
            report(ctx, "Constructor argument " .. i .. " expects " .. type_to_string(expected) .. ", got " .. type_to_string(actual))
          end
        end
        return struct_type
      end
      obj_info = scope_get(ctx, obj.name)
      if obj_info then
        obj_id = own_resolve(ctx, obj.name)
      end
    end
    local obj_type = obj_info and obj_info.type or nil
    if not obj_type then
      obj_type = infer_expr(ctx, obj)
    end
    if obj_id and (obj_type.kind == "sender" or obj_type.kind == "receiver") then
      own_borrow_temp(ctx, obj_id, false)
    end
    local sender_type = nil
    if obj_type.kind == "sender" then
      sender_type = obj_type
    elseif obj_type.kind == "ref" and obj_type.to.kind == "sender" then
      sender_type = obj_type.to
    end
    if sender_type and prop == "send" then
      if #args ~= 1 then
        report(ctx, "send expects 1 argument")
      end
      local actual = args[1] and expect_value(ctx, infer_expr(ctx, args[1]), "send argument") or type_unknown()
      local expected = sender_type.item or type_unknown()
      if not type_assignable(expected, actual) then
        report(ctx, "send expects " .. type_to_string(expected))
      end
      return type_void()
    end
    local receiver_type = nil
    if obj_type.kind == "receiver" then
      receiver_type = obj_type
    elseif obj_type.kind == "ref" and obj_type.to.kind == "receiver" then
      receiver_type = obj_type.to
    end
    if receiver_type and prop == "recv" then
      if #args ~= 0 then
        report(ctx, "recv expects 0 arguments")
      end
      return receiver_type.item or type_unknown()
    end
    local method_owner = unwrap_ref(obj_type)
    if method_owner.kind == "struct" or method_owner.kind == "enum" then
      local method_map = ctx.methods[method_owner.name]
      local method = method_map and method_map[prop]
      if method then
        local sig = method.sig
        local generics = sig.generics or {}
        local param_map = {}
        if type_args and #type_args > 0 and #generics == 0 then
          report(ctx, "Type arguments provided for non-generic method")
        end
        if #generics > 0 then
          if type_args and #type_args > 0 and #type_args ~= #generics then
            report(ctx, "Expected " .. #generics .. " type argument(s), got " .. #type_args)
          end
          for i, name in ipairs(generics) do
            if type_args and type_args[i] then
              param_map[name] = type_args[i]
            end
          end
        end
        local arg_offset = method.has_self and 1 or 0
        local expected_count = #sig.params - arg_offset
        if #args ~= expected_count then
          report(ctx, "Method " .. obj_type.name .. "." .. prop .. " expects " .. expected_count .. " argument(s), got " .. #args)
        end
        if method.has_self then
          local self_expected = resolve_type(ctx, sig.params[1], param_map)
          local self_actual = obj_type
          if self_expected.kind == "ref" then
            local base = unwrap_ref(obj_type)
            if self_actual.kind ~= "ref" then
              if obj_id then
                own_borrow_temp(ctx, obj_id, self_expected.mutable)
              end
            end
            self_actual = type_ref(base, self_expected.mutable)
          else
            local base = unwrap_ref(obj_type)
            if obj_id and obj.kind == "Identifier" and obj_type.kind ~= "ref" then
              own_use_value(ctx, obj.name, "self")
            end
            self_actual = base
          end
          unify_type(ctx, self_expected, self_actual, param_map, "self")
        end
        for i = 1, math.min(#args, expected_count) do
          local expected = resolve_type(ctx, sig.params[i + arg_offset], param_map)
          local actual = infer_arg_type(ctx, expected, args[i], "argument " .. i)
          unify_type(ctx, expected, actual, param_map, "argument " .. i)
        end
        if #generics > 0 then
          for _, name in ipairs(generics) do
            if not param_map[name] or param_map[name].kind == "unknown" then
              report(ctx, "Cannot infer type parameter " .. name .. "; provide explicit type arguments")
              param_map[name] = param_map[name] or type_unknown()
            end
          end
        end
        return resolve_type(ctx, sig.ret, param_map)
      end
    end
    report(ctx, "Unknown call target")
    return type_unknown()
  end

  report(ctx, "Unknown call target")
  return type_unknown()
end

infer_member = function(ctx, expr)
  local obj = expr.object
  local prop = expr.property
  local obj_type = nil
  if obj.kind == "Identifier" then
    local module = ctx.imports[obj.name]
    if module then
      local sig = ctx.modules[module] and ctx.modules[module][prop]
      if sig then
        return type_fn(sig.params, sig.ret)
      end
    end
    if ctx.enums[obj.name] then
      local enum_type = build_enum_type(ctx, obj.name, nil)
      local payload = enum_type.variants[prop]
      if payload == nil then
        report(ctx, "Unknown enum variant: " .. obj.name .. "." .. prop)
        return type_unknown()
      end
      if payload ~= false then
        report(ctx, "Enum variant " .. obj.name .. "." .. prop .. " requires payload")
      end
      return enum_type
    end
    if ctx.structs[obj.name] and prop == "new" then
      return type_fn({}, build_struct_type(ctx, obj.name, nil))
    end
    local info = scope_get(ctx, obj.name)
    if info then
      local id = own_resolve(ctx, obj.name)
      if id then
        own_borrow_temp(ctx, id, false)
      end
      obj_type = info.type
    end
  end
  if not obj_type then
    obj_type = infer_expr(ctx, obj)
  end
  local field_owner = unwrap_ref(obj_type)
  if field_owner.kind == "struct" then
    local field = field_owner.fields and field_owner.fields[prop]
    if field then
      return field
    end
    report(ctx, "Unknown field: " .. prop .. " on " .. type_to_string(field_owner))
    return type_unknown()
  end
  return type_unknown()
end

local function check_match(ctx, stmt)
  local expr_type = expect_value(ctx, infer_expr(ctx, stmt.expr), "match expression")
  own_release_temp(ctx)
  if expr_type.kind == "ref" then
    expr_type = expr_type.to
  end
  local allowed = {}
  local has_allowed = true
  if expr_type.kind == "enum" then
    for name, payload in pairs(expr_type.variants or {}) do
      allowed[name] = payload
    end
  elseif expr_type.kind == "result" then
    allowed.Ok = expr_type.ok or type_unknown()
    allowed.Err = expr_type.err or type_unknown()
  elseif expr_type.kind == "unknown" or expr_type.kind == "any" then
    has_allowed = false
  else
    report(ctx, "match expects enum or Result")
    has_allowed = false
  end
  local seen = {}
  for _, arm in ipairs(stmt.arms or {}) do
    if has_allowed then
      local payload = allowed[arm.tag]
      if payload == nil then
        report(ctx, "Unknown match arm tag: " .. arm.tag)
      elseif seen[arm.tag] then
        report(ctx, "Duplicate match arm tag: " .. arm.tag)
      end
      seen[arm.tag] = true
      scope_push(ctx)
      own_scope_push(ctx)
      if arm.binding then
        if payload == false then
          report(ctx, "Match arm " .. arm.tag .. " has no payload")
        else
          local info = { type = payload, mutable = false }
          scope_set(ctx, arm.binding, info)
          own_bind(ctx, arm.binding, info)
        end
      end
      if arm.body then
        check_block(ctx, arm.body, false)
      end
      own_scope_pop(ctx)
      scope_pop(ctx)
    else
      scope_push(ctx)
      own_scope_push(ctx)
      if arm.binding then
        local info = { type = type_unknown(), mutable = false }
        scope_set(ctx, arm.binding, info)
        own_bind(ctx, arm.binding, info)
      end
      if arm.body then
        check_block(ctx, arm.body, false)
      end
      own_scope_pop(ctx)
      scope_pop(ctx)
    end
  end
end



local function temporal_value_new(name, var_type, lifetime)
  return {
    name = name,
    type = var_type,
    lifetime = lifetime, 
    created_at = os.time() * 1000, 
    is_active = true
  }
end

local function temporal_check_scope_exit(ctx, var_name)
  if not ctx.temporal then
    ctx.temporal = { values = {}, traces = {} }
  end
  local tv = ctx.temporal.values[var_name]
  if tv and tv.is_active then
    local elapsed = (os.time() * 1000) - tv.created_at
    if elapsed >= tv.lifetime then
      report(ctx, "Temporal value '" .. var_name .. "' lifetime (" .. tv.lifetime .. "ms) has expired")
    end
    tv.is_active = false
  end
end

local function ownership_trace_record(ctx, variable, event)
  if not ctx.ownership_traces then
    ctx.ownership_traces = {}
  end
  table.insert(ctx.ownership_traces, {
    variable = variable,
    event = event,  -- "created", "moved", "borrowed", "used", "freed"
    timestamp = os.time()
  })
end

local function debug_ownership_enable(ctx, rules)
  ctx.debug_ownership_enabled = true
  ctx.ownership_debug_rules = rules or {}
  if not ctx.ownership_traces then
    ctx.ownership_traces = {}
  end
end

local function check_statement(ctx, stmt)
  if stmt.kind == "Let" then
    local explicit = stmt.type and resolve_type(ctx, parse_type_string(stmt.type), nil) or nil
    if stmt.pattern.kind == "IdentPattern" and stmt.value and stmt.value.kind == "Borrow" then
      local target = stmt.value.expr
      if not target or target.kind ~= "Identifier" then
        report(ctx, "Borrow expects identifier")
        local info = { type = type_ref(type_unknown(), stmt.value.mutable), mutable = stmt.mutable }
        scope_set(ctx, stmt.pattern.name, info)
        own_bind(ctx, stmt.pattern.name, info)
        return
      end
      local target_info = scope_get(ctx, target.name)
      if not target_info then
        report(ctx, "Unknown identifier: " .. target.name)
        local info = { type = type_ref(type_unknown(), stmt.value.mutable), mutable = stmt.mutable }
        scope_set(ctx, stmt.pattern.name, info)
        own_bind(ctx, stmt.pattern.name, info)
        return
      end
      local ref_type = type_ref(target_info.type, stmt.value.mutable)
      if explicit and not type_assignable(explicit, ref_type) then
        report(ctx, "Let expects " .. type_to_string(explicit) .. ", got " .. type_to_string(ref_type))
      end
      local final_type = explicit or ref_type
      local info = { type = final_type, mutable = stmt.mutable }
      scope_set(ctx, stmt.pattern.name, info)
      local ref_target = nil
      local target_id = own_resolve(ctx, target.name)
      if target_id and own_can_borrow(ctx, target_id, stmt.value.mutable) then
        ref_target = target_id
      end
      own_bind(ctx, stmt.pattern.name, info, { ref_target = ref_target, ref_mut = stmt.value.mutable })
      return
    end
    local value_type = nil
    local transfer_from = nil
    if explicit and explicit.kind == "result" and stmt.value and stmt.value.kind == "Call" then
      value_type = infer_result_literal(ctx, stmt.value, explicit, "let value")
    end
    if stmt.value and stmt.value.kind == "Identifier" then
      local src_info = scope_get(ctx, stmt.value.name)
      if src_info and src_info.type and src_info.type.kind == "ref" then
        value_type = src_info.type
        transfer_from = own_resolve(ctx, stmt.value.name)
      end
    end
    if not value_type then
      value_type = expect_value(ctx, infer_expr(ctx, stmt.value), "let value")
    end
    if stmt.pattern.kind == "TuplePattern" then
      local names = stmt.pattern.names or {}
      local tuple_type = explicit
      if tuple_type and tuple_type.kind ~= "tuple" then
        report(ctx, "Tuple pattern expects tuple type")
        tuple_type = nil
      end
      local value_tuple = value_type.kind == "tuple" and value_type or nil
      if value_tuple and #names ~= #value_tuple.items then
        report(ctx, "Tuple pattern count does not match value")
      end
      for i, name in ipairs(names) do
        local t = type_unknown()
        if tuple_type and tuple_type.items and tuple_type.items[i] then
          t = tuple_type.items[i]
        elseif value_tuple and value_tuple.items and value_tuple.items[i] then
          t = value_tuple.items[i]
        end
        local info = { type = t, mutable = stmt.mutable }
        scope_set(ctx, name, info)
        own_bind(ctx, name, info)
      end
    else
      if explicit and not type_assignable(explicit, value_type) then
        report(ctx, "Let expects " .. type_to_string(explicit) .. ", got " .. type_to_string(value_type))
      end
      local final_type = explicit or value_type
      
     
      if ctx.bonds then
        for bond_id, bond in pairs(ctx.bonds) do
          if bond.status == "rolled_back" and bond.name == stmt.pattern.name then
            ctx.bonds[bond_id] = nil  
          end
        end
      end
      
      local info = { type = final_type, mutable = stmt.mutable }
      scope_set(ctx, stmt.pattern.name, info)
      local opts = nil
      if transfer_from and final_type and final_type.kind == "ref" then
        local src_var = ctx.ownership.vars[transfer_from]
        if src_var and src_var.ref_target then
          opts = {
            ref_target = src_var.ref_target,
            ref_mut = src_var.ref_mut,
            transfer = true,
            transfer_from = transfer_from,
          }
        end
      end
      own_bind(ctx, stmt.pattern.name, info, opts)
    end
  elseif stmt.kind == "Bond" then
   
    local value_type = expect_value(ctx, infer_expr(ctx, stmt.value), "bond value")
    local info = { type = value_type, mutable = true } 
    
    ctx.current_bond_id = ctx.current_bond_id or 0
    ctx.current_bond_id = ctx.current_bond_id + 1
    local bond_id = ctx.current_bond_id
    
    ctx.bonds = ctx.bonds or {}
    ctx.bonds[bond_id] = {
      id = bond_id,
      name = stmt.name,
      type = value_type,
      scope_depth = ctx.scope_depth,
      status = "active",  -- "active" | "committed" | "rolled_back"
      actions = {},  
      line = stmt.line
    }
    

    ctx.bond_states = ctx.bond_states or {}
    ctx.bond_states[stmt.name] = bond_id
    
    scope_set(ctx, stmt.name, info)
    own_bind(ctx, stmt.name, info)
    
    ctx.active_bond = bond_id
  elseif stmt.kind == "Commit" then
    if not ctx.active_bond then
      report(ctx, "commit outside of bond")
      return
    end
    local bond = ctx.bonds[ctx.active_bond]
    if bond then
      bond.status = "committed"
    end
    ctx.active_bond = nil
  elseif stmt.kind == "Rollback" then
    if not ctx.active_bond then
      report(ctx, "rollback outside of bond")
      return
    end
    local bond = ctx.bonds[ctx.active_bond]
    if bond then
      bond.status = "rolled_back"
      
      if ctx.bond_states then
        ctx.bond_states[bond.name] = nil
      end
      scope_set(ctx, bond.name, nil)
    end
    ctx.active_bond = nil
  elseif stmt.kind == "Assign" then
    local info = scope_get(ctx, stmt.name)
    if not info then
      report(ctx, "Unknown variable: " .. stmt.name)
      return
    end
    if not info.mutable then
      report(ctx, "Cannot assign to immutable variable: " .. stmt.name)
    end
    
    -- RULE 2: Inside active bond  only allow assign (no move)
    if ctx.active_bond and ctx.bonds[ctx.active_bond] then
      local bond = ctx.bonds[ctx.active_bond]
      if bond.status == "active" and stmt.value then
       
        if stmt.value.kind == "Identifier" then
          local src_info = scope_get(ctx, stmt.value.name)
          if src_info and src_info.type then
         
            if not type_is_copy(src_info.type) then
              report(ctx, "cannot move value inside active bond (only Copy types allowed)")
            end
          end
        end
      end
    end
    
    local id = own_resolve(ctx, stmt.name)
    local var = id and ctx.ownership.vars[id] or nil
    if var and var.moved and not info.mutable then
      report(ctx, stmt.name .. " was moved")
    end
    if var and ((var.borrow_imm and var.borrow_imm > 0) or (var.borrow_mut and var.borrow_mut > 0)) then
      report(ctx, "Cannot assign to " .. stmt.name .. " while it is borrowed")
    end
    local value_type = nil
    local ref_target = nil
    local ref_mut = false
    local transfer_from = nil
    if stmt.value and stmt.value.kind == "Borrow" then
      local target = stmt.value.expr
      if not target or target.kind ~= "Identifier" then
        report(ctx, "Borrow expects identifier")
        value_type = type_ref(type_unknown(), stmt.value.mutable)
      else
        local target_info = scope_get(ctx, target.name)
        if not target_info then
          report(ctx, "Unknown identifier: " .. target.name)
          value_type = type_ref(type_unknown(), stmt.value.mutable)
        else
          value_type = type_ref(target_info.type, stmt.value.mutable)
          local target_id = own_resolve(ctx, target.name)
          if target_id and own_can_borrow(ctx, target_id, stmt.value.mutable) then
            ref_target = target_id
            ref_mut = stmt.value.mutable
          end
        end
      end
    elseif stmt.value and stmt.value.kind == "Identifier" then
      local src_info = scope_get(ctx, stmt.value.name)
      if src_info and src_info.type and src_info.type.kind == "ref" then
        value_type = src_info.type
        transfer_from = own_resolve(ctx, stmt.value.name)
        local src_var = transfer_from and ctx.ownership.vars[transfer_from]
        if src_var and src_var.moved then
          report(ctx, stmt.value.name .. " was moved")
        end
      end
    end
    if not value_type then
      value_type = expect_value(ctx, infer_expr(ctx, stmt.value), "assignment value")
    end
    local assign_ok = type_assignable(info.type, value_type)
    if not assign_ok then
      report(ctx, "Assignment expects " .. type_to_string(info.type) .. ", got " .. type_to_string(value_type))
    end
    if assign_ok and info.type.kind == "ref" and value_type and value_type.kind == "ref" then
      local dest_depth = var and var.scope_depth or #ctx.ownership.scopes
      if ref_target then
        own_check_lifetime(ctx, ref_target, dest_depth, "Borrow")
      elseif transfer_from then
        local src_var = ctx.ownership.vars[transfer_from]
        if src_var and src_var.ref_target then
          own_check_lifetime(ctx, src_var.ref_target, dest_depth, "Reference")
        end
      end
    end
    if var and info.mutable then
      var.moved = false
    end
    if var and info.type.kind == "ref" and value_type and value_type.kind == "ref" and assign_ok then
      if var.ref_target then
        own_remove_borrow(ctx, var.ref_target, var.ref_mut)
      end
      var.ref_target = nil
      var.ref_mut = false
      if transfer_from then
        local src = ctx.ownership.vars[transfer_from]
        if src and src.ref_target then
          var.ref_target = src.ref_target
          var.ref_mut = src.ref_mut
          src.moved = true
          src.ref_target = nil
          src.ref_mut = false
        end
      elseif ref_target then
        var.ref_target = ref_target
        var.ref_mut = ref_mut
        own_add_borrow(ctx, ref_target, ref_mut)
      end
    end
    
  
    if ctx.active_bond and ctx.bonds[ctx.active_bond] then
      table.insert(ctx.bonds[ctx.active_bond].actions, {
        kind = "assign",
        target = stmt.name,
        line = stmt.line,
        inverse = "undo_assign"
      })
    end
  elseif stmt.kind == "MemberAssign" then
    local obj_type = nil
    if stmt.object.kind == "Identifier" then
      local info = scope_get(ctx, stmt.object.name)
      if info then
        obj_type = info.type
      end
    end
    if not obj_type then
      obj_type = infer_expr(ctx, stmt.object)
    end
    local info = stmt.object.kind == "Identifier" and scope_get(ctx, stmt.object.name) or nil
    if info and not info.mutable then
      report(ctx, "Cannot assign to field of immutable variable: " .. stmt.object.name)
    end
    if stmt.object.kind == "Identifier" then
      local id = own_resolve(ctx, stmt.object.name)
      local var = id and ctx.ownership.vars[id]
      if var then
        if var.moved then
          report(ctx, stmt.object.name .. " was moved")
        end
        if (var.borrow_imm and var.borrow_imm > 0) or (var.borrow_mut and var.borrow_mut > 0) then
          report(ctx, "Cannot assign to " .. stmt.object.name .. " while it is borrowed")
        end
      end
    end
    if obj_type.kind == "struct" then
      local field_type = obj_type.fields and obj_type.fields[stmt.property]
      if not field_type then
        report(ctx, "Unknown field: " .. stmt.property .. " on " .. obj_type.name)
      else
        local value_type = expect_value(ctx, infer_expr(ctx, stmt.value), "field value")
        if not type_assignable(field_type, value_type) then
          report(ctx, "Field " .. stmt.property .. " expects " .. type_to_string(field_type) .. ", got " .. type_to_string(value_type))
        end
      end
    elseif obj_type.kind ~= "unknown" and obj_type.kind ~= "any" then
      report(ctx, "Member assignment expects struct")
    end
    
  
    if ctx.active_bond and ctx.bonds[ctx.active_bond] then
      table.insert(ctx.bonds[ctx.active_bond].actions, {
        kind = "member_assign",
        target = stmt.object.name,
        field = stmt.property,
        line = stmt.line,
        inverse = "undo_member_assign"
      })
    end
  elseif stmt.kind == "IndexAssign" then
    local obj_type = nil
    if stmt.object.kind == "Identifier" then
      local info = scope_get(ctx, stmt.object.name)
      if info then
        obj_type = info.type
      end
    end
    if not obj_type then
      obj_type = infer_expr(ctx, stmt.object)
    end
    local info = stmt.object.kind == "Identifier" and scope_get(ctx, stmt.object.name) or nil
    if info and not info.mutable then
      report(ctx, "Cannot assign to index of immutable variable: " .. stmt.object.name)
    end
    if stmt.object.kind == "Identifier" then
      local id = own_resolve(ctx, stmt.object.name)
      local var = id and ctx.ownership.vars[id]
      if var then
        if var.moved then
          report(ctx, stmt.object.name .. " was moved")
        end
        if (var.borrow_imm and var.borrow_imm > 0) or (var.borrow_mut and var.borrow_mut > 0) then
          report(ctx, "Cannot assign to " .. stmt.object.name .. " while it is borrowed")
        end
      end
    end
    local index_type = expect_value(ctx, infer_expr(ctx, stmt.index), "index")
    local value_type = expect_value(ctx, infer_expr(ctx, stmt.value), "index value")
    if obj_type.kind == "vec" then
      expect_numeric(ctx, index_type, "Vector index")
      if not type_assignable(obj_type.elem, value_type) then
        report(ctx, "Vector element expects " .. type_to_string(obj_type.elem) .. ", got " .. type_to_string(value_type))
      end
    elseif obj_type.kind == "map" then
      if not type_assignable(obj_type.key, index_type) then
        report(ctx, "Map key expects " .. type_to_string(obj_type.key) .. ", got " .. type_to_string(index_type))
      end
      if not type_assignable(obj_type.value, value_type) then
        report(ctx, "Map value expects " .. type_to_string(obj_type.value) .. ", got " .. type_to_string(value_type))
      end
    elseif obj_type.kind ~= "unknown" and obj_type.kind ~= "any" then
      report(ctx, "Index assignment expects vector or map")
    end
    
   
    if ctx.active_bond and ctx.bonds[ctx.active_bond] then
      table.insert(ctx.bonds[ctx.active_bond].actions, {
        kind = "index_assign",
        target = stmt.object.name,
        line = stmt.line,
        inverse = "undo_index_assign"
      })
    end
  elseif stmt.kind == "DerefAssign" then
    local info = scope_get(ctx, stmt.name)
    if not info then
      report(ctx, "Unknown pointer: " .. stmt.name)
      return
    end
    if info.type.kind == "ref" and not info.type.mutable then
      report(ctx, "Deref assignment expects mutable reference")
    elseif info.type.kind ~= "ptr" and info.type.kind ~= "ref" and info.type.kind ~= "unknown" then
      report(ctx, "Deref assignment expects pointer")
    end
    local id = own_resolve(ctx, stmt.name)
    if id then
      local var = ctx.ownership.vars[id]
      if var and var.moved then
        report(ctx, stmt.name .. " was moved")
      end
    end
    local value_type = expect_value(ctx, infer_expr(ctx, stmt.value), "deref value")
    if (info.type.kind == "ptr" or info.type.kind == "ref") and not type_assignable(info.type.to, value_type) then
      report(ctx, "Pointer expects " .. type_to_string(info.type.to) .. ", got " .. type_to_string(value_type))
    end
  elseif stmt.kind == "Return" then
    -- RULE 3: Cannot exit scope with active bond
    if ctx.active_bond and ctx.bonds[ctx.active_bond] then
      local bond = ctx.bonds[ctx.active_bond]
      if bond.status == "active" then
        report(ctx, "cannot exit scope with active bond (commit or rollback required)")
      end
    end
    
    if stmt.value then
      local value_type = nil
      if ctx.return_type and ctx.return_type.kind == "result" and stmt.value.kind == "Call" then
        value_type = infer_result_literal(ctx, stmt.value, ctx.return_type, "return value")
      end
      if not value_type then
        value_type = expect_value(ctx, infer_expr(ctx, stmt.value), "return value")
      end
      if ctx.return_type and ctx.return_type.kind == "void" then
        report(ctx, "Return value in void function")
      elseif ctx.return_type and not type_assignable(ctx.return_type, value_type) then
        report(ctx, "Return expects " .. type_to_string(ctx.return_type) .. ", got " .. type_to_string(value_type))
      end
    else
      if ctx.return_type and ctx.return_type.kind ~= "void" then
        report(ctx, "Return expects value of type " .. type_to_string(ctx.return_type))
      end
    end
  elseif stmt.kind == "ExprStmt" then
    infer_expr(ctx, stmt.expr)
  elseif stmt.kind == "If" then
    local cond_type = expect_value(ctx, infer_expr(ctx, stmt.cond), "if condition")
    expect_bool(ctx, cond_type, "If condition")
    own_release_temp(ctx)
    if stmt.then_block then
      check_block(ctx, stmt.then_block, true)
    end
    if stmt.else_block then
      check_block(ctx, stmt.else_block, true)
    end
  elseif stmt.kind == "While" then
    local cond_type = expect_value(ctx, infer_expr(ctx, stmt.cond), "while condition")
    expect_bool(ctx, cond_type, "While condition")
    own_release_temp(ctx)
    check_block(ctx, stmt.body, true)
  elseif stmt.kind == "For" then
    scope_push(ctx)
    own_scope_push(ctx)
    if stmt.range_start then
      local start_type = expect_value(ctx, infer_expr(ctx, stmt.range_start), "range start")
      local end_type = expect_value(ctx, infer_expr(ctx, stmt.range_end), "range end")
      expect_numeric(ctx, start_type, "Range start")
      expect_numeric(ctx, end_type, "Range end")
      own_release_temp(ctx)
      local info = { type = type_num(), mutable = true }
      scope_set(ctx, stmt.name, info)
      own_bind(ctx, stmt.name, info)
    else
      local iter_type = expect_value(ctx, infer_expr(ctx, stmt.iter), "iterable")
      own_release_temp(ctx)
      if iter_type.kind == "vec" then
        local info = { type = iter_type.elem, mutable = true }
        scope_set(ctx, stmt.name, info)
        own_bind(ctx, stmt.name, info)
      elseif iter_type.kind == "unknown" or iter_type.kind == "any" then
        local info = { type = type_unknown(), mutable = true }
        scope_set(ctx, stmt.name, info)
        own_bind(ctx, stmt.name, info)
      else
        report(ctx, "for-in expects vector")
        local info = { type = type_unknown(), mutable = true }
        scope_set(ctx, stmt.name, info)
        own_bind(ctx, stmt.name, info)
      end
    end
    check_block(ctx, stmt.body, false)
    own_scope_pop(ctx)
    scope_pop(ctx)
  elseif stmt.kind == "Match" then
    check_match(ctx, stmt)
  elseif stmt.kind == "Spawn" then
    check_block(ctx, stmt.block, true)
  elseif stmt.kind == "Unsafe" then
    check_block(ctx, stmt.block, true)
  elseif stmt.kind == "WithinBlock" then
  
    if not ctx.temporal then
      ctx.temporal = { values = {}, traces = {} }
    end
    
    
    scope_push(ctx)
    own_scope_push(ctx)
    
    if stmt.block then
      check_block(ctx, stmt.block, true)
    end
    
   
    local scope_vars = ctx.scopes[#ctx.scopes] or {}
    for var_name, _ in pairs(scope_vars) do
      temporal_check_scope_exit(ctx, var_name)
    end
    
    own_scope_pop(ctx)
    scope_pop(ctx)
  elseif stmt.kind == "DuringBlock" then
    
    if not ctx.temporal then
      ctx.temporal = { values = {}, traces = {} }
    end
    
    
    local cond_info = scope_get(ctx, stmt.condition)
    if not cond_info then
      report(ctx, "Unknown temporal condition: " .. stmt.condition)
      return
    end
    
 
    scope_push(ctx)
    own_scope_push(ctx)
    
    
    if stmt.block then
      check_block(ctx, stmt.block, true)
    end
    
    own_scope_pop(ctx)
    scope_pop(ctx)
  elseif stmt.kind == "DebugOwnership" then
    
    debug_ownership_enable(ctx, stmt.rules or {})
    
    
    for name, info in pairs(ctx.scopes[#ctx.scopes] or {}) do
      if info.type then
        ownership_trace_record(ctx, name, "created")
      end
    end
  elseif stmt.kind == "Defer" then
    local saved = ctx.ownership
    local defer_state = own_clone(saved)
    defer_state.defer_mode = true
    defer_state.defer_use = {}
    ctx.ownership = defer_state
    if stmt.block then
      check_block(ctx, stmt.block, true)
    else
      infer_expr(ctx, stmt.expr)
    end
    ctx.ownership = saved
    own_apply_defer_uses(saved, defer_state.defer_use)
  elseif stmt.kind == "Break" or stmt.kind == "Continue" then
    -- RULE 3: Cannot exit scope with active bond
    if ctx.active_bond and ctx.bonds[ctx.active_bond] then
      local bond = ctx.bonds[ctx.active_bond]
      if bond.status == "active" then
        report(ctx, "cannot exit scope with active bond (commit or rollback required)")
      end
    end
  else
    report(ctx, "Unknown statement kind: " .. tostring(stmt.kind))
  end
end

check_block = function(ctx, block, new_scope)
  if new_scope ~= false then
    scope_push(ctx)
    own_scope_push(ctx)
  end
  for _, stmt in ipairs(block.statements or {}) do
    check_statement(ctx, stmt)
    own_release_temp(ctx)
  end
  if new_scope ~= false then
    own_scope_pop(ctx)
    scope_pop(ctx)
  end
end

local function check_function(ctx, fn, self_type, generic_names)
  scope_push(ctx)
  own_scope_push(ctx)
  local prev_func = ctx.current_func
  local prev_ret = ctx.return_type
  ctx.current_func = fn.name or "<anon>"
  local generic_set = {}
  for _, name in ipairs(generic_names or {}) do
    generic_set[name] = true
  end
  local ret_type = fn.return_type and parse_type_string(fn.return_type) or nil
  ret_type = convert_type_vars(ret_type, generic_set)
  ctx.return_type = ret_type and resolve_type(ctx, ret_type, nil) or type_void()
  for _, p in ipairs(fn.params or {}) do
    local ptype = p.type and parse_type_string(p.type) or type_unknown()
    ptype = convert_type_vars(ptype, generic_set)
    if p.name == "self" and self_type then
      local base = self_type
      if p.ref == "ref" or p.ref == "ref_mut" then
        ptype = type_ref(base, p.ref == "ref_mut")
      else
        ptype = base
      end
    elseif p.ref == "ref" or p.ref == "ref_mut" then
      ptype = type_ref(resolve_type(ctx, ptype, nil), p.ref == "ref_mut")
    else
      ptype = resolve_type(ctx, ptype, nil)
    end
    local info = { type = ptype, mutable = false }
    scope_set(ctx, p.name, info)
    own_bind(ctx, p.name, info)
  end
  check_block(ctx, fn.body, false)
  ctx.current_func = prev_func
  ctx.return_type = prev_ret
  own_scope_pop(ctx)
  scope_pop(ctx)
end

local function merge_generics(ctx, a, b)
  local list = {}
  local seen = {}
  for _, name in ipairs(a or {}) do
    if seen[name] then
      report(ctx, "Duplicate generic parameter " .. name)
    end
    seen[name] = true
    table.insert(list, name)
  end
  for _, name in ipairs(b or {}) do
    if seen[name] then
      report(ctx, "Duplicate generic parameter " .. name)
    end
    seen[name] = true
    table.insert(list, name)
  end
  return list
end

local function build_self_type(ctx, item)
  local args = {}
  for _, name in ipairs(item.params or {}) do
    table.insert(args, type_var(name))
  end
  if ctx.structs[item.name] then
    return build_struct_type(ctx, item.name, args, nil)
  end
  if ctx.enums[item.name] then
    return build_enum_type(ctx, item.name, args, nil)
  end
  return nil
end
local function map_import(item)
  local alias = item.alias or item.path[#item.path]
  local module = alias
  if item.path[1] == "rex" then
    module = item.path[2] or alias
  end
  return alias, module
end

function Typechecker.check(ast)
  local ctx = {
    errors = {},
    structs = {},
    enums = {},
    aliases = {},
    functions = {},
    methods = {},
    imports = {},
    scopes = { {} },
    ownership = {
      next_id = 1,
      scopes = { {} },
      vars = {},
      temp_borrows = {},
      defer_stack = { {} },
      defer_use = {},
    },
    builtins = builtins,
    modules = modules,
    current_func = "<top>",
    return_type = type_void(),
  }

  for _, item in ipairs(ast.items or {}) do
    if item.kind == "Struct" then
      local param_set = {}
      for _, name in ipairs(item.params or {}) do
        param_set[name] = true
      end
      local field_list = {}
      for _, field in ipairs(item.fields or {}) do
        local ftype = field.type and parse_type_string(field.type) or type_unknown()
        ftype = convert_type_vars(ftype, param_set)
        table.insert(field_list, { name = field.name, type = ftype })
      end
      ctx.structs[item.name] = { params = item.params or {}, field_list = field_list }
    elseif item.kind == "Enum" then
      local param_set = {}
      for _, name in ipairs(item.params or {}) do
        param_set[name] = true
      end
      local variants = {}
      for _, variant in ipairs(item.variants or {}) do
        local types = {}
        for _, vtype in ipairs(variant.types or {}) do
          local parsed = parse_type_string(vtype)
          parsed = convert_type_vars(parsed, param_set)
          table.insert(types, parsed)
        end
        if #types > 1 then
          report(ctx, "Enum variant " .. item.name .. "." .. variant.name .. " supports at most one payload")
        end
        table.insert(variants, { name = variant.name, types = types })
      end
      ctx.enums[item.name] = { params = item.params or {}, variants = variants }
    elseif item.kind == "TypeAlias" then
      ctx.aliases[item.name] = parse_type_string(item.aliased)
    end
  end

  for _, item in ipairs(ast.items or {}) do
    if item.kind == "Use" then
      local alias, module = map_import(item)
      ctx.imports[alias] = module
    end
  end

  for _, item in ipairs(ast.items or {}) do
    if item.kind == "Function" then
      local generics = item.type_params or {}
      local generic_set = {}
      for _, name in ipairs(generics) do
        generic_set[name] = true
      end
      local params = {}
      for _, p in ipairs(item.params or {}) do
        local ptype = p.type and parse_type_string(p.type) or type_unknown()
        ptype = convert_type_vars(ptype, generic_set)
        if p.ref == "ref" or p.ref == "ref_mut" then
          ptype = type_ref(resolve_type(ctx, ptype, nil), p.ref == "ref_mut")
        else
          ptype = resolve_type(ctx, ptype, nil)
        end
        table.insert(params, ptype)
      end
      local ret = item.return_type and parse_type_string(item.return_type) or type_void()
      ret = convert_type_vars(ret, generic_set)
      ret = resolve_type(ctx, ret, nil)
      ctx.functions[item.name] = sig(params, ret, generics)
    elseif item.kind == "Impl" then
      ctx.methods[item.name] = ctx.methods[item.name] or {}
      local self_type = build_self_type(ctx, item)
      local impl_generics = item.params or {}
      for _, method in ipairs(item.methods or {}) do
        local generics = merge_generics(ctx, impl_generics, method.type_params or {})
        local generic_set = {}
        for _, name in ipairs(generics) do
          generic_set[name] = true
        end
        local params = {}
        local has_self = false
        for _, p in ipairs(method.params or {}) do
          local ptype = p.type and parse_type_string(p.type) or type_unknown()
          ptype = convert_type_vars(ptype, generic_set)
          if p.name == "self" and self_type then
            local base = self_type
            if p.ref == "ref" or p.ref == "ref_mut" then
              ptype = type_ref(base, p.ref == "ref_mut")
            else
              ptype = base
            end
            has_self = true
          elseif p.ref == "ref" or p.ref == "ref_mut" then
            ptype = type_ref(resolve_type(ctx, ptype, nil), p.ref == "ref_mut")
          else
            ptype = resolve_type(ctx, ptype, nil)
          end
          table.insert(params, ptype)
        end
        local ret = method.return_type and parse_type_string(method.return_type) or type_void()
        ret = convert_type_vars(ret, generic_set)
        ret = resolve_type(ctx, ret, nil)
        ctx.methods[item.name][method.name] = { sig = sig(params, ret, generics), has_self = has_self }
      end
    end
  end

  for _, item in ipairs(ast.items or {}) do
    if item.kind == "Function" then
      check_function(ctx, item, nil, item.type_params or {})
    elseif item.kind == "Impl" then
      local self_type = build_self_type(ctx, item)
      local impl_generics = item.params or {}
      for _, method in ipairs(item.methods or {}) do
        local generics = merge_generics(ctx, impl_generics, method.type_params or {})
        check_function(ctx, method, self_type, generics)
      end
    elseif item.kind == "Struct" or item.kind == "Enum" or item.kind == "Use" or item.kind == "TypeAlias" then
     
    else
      check_statement(ctx, item)
      own_release_temp(ctx)
    end
  end

  if #ctx.errors > 0 then
    error(table.concat(ctx.errors, "\n"))
  end
  return true
end

return Typechecker
