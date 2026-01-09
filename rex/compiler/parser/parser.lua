
local ast = require("compiler.ast")

local Parser = {}
Parser.__index = Parser

local PRECEDENCE = {
  ["||"] = 1,
  ["&&"] = 2,
  ["=="] = 3,
  ["!="] = 3,
  ["<"] = 4,
  [">"] = 4,
  ["<="] = 4,
  [">="] = 4,
  ["+"] = 5,
  ["-"] = 5,
  ["*"] = 6,
  ["/"] = 6,
  ["%"] = 6,
}

function Parser.new(tokens)
  return setmetatable({ tokens = tokens, pos = 1 }, Parser)
end

function Parser:current()
  return self.tokens[self.pos]
end

function Parser:peek(offset)
  offset = offset or 0
  return self.tokens[self.pos + offset] or { kind = "eof", value = "" }
end

function Parser:advance()
  self.pos = self.pos + 1
end

function Parser:match(value)
  local tok = self:current()
  if tok.kind == "symbol" and tok.value == value then
    self:advance()
    return true
  end
  return false
end

function Parser:match_kind(kind)
  local tok = self:current()
  if tok.kind == kind then
    self:advance()
    return tok
  end
  return nil
end

function Parser:match_keyword(word)
  local tok = self:current()
  if tok.kind == "keyword" and tok.value == word then
    self:advance()
    return true
  end
  return false
end

function Parser:expect(value)
  local tok = self:current()
  if tok.kind ~= "symbol" or tok.value ~= value then
    self:error("Expected '" .. value .. "', got '" .. tok.value .. "'")
  end
  self:advance()
end

function Parser:expect_kind(kind)
  local tok = self:current()
  if tok.kind ~= kind then
    self:error("Expected " .. kind .. ", got " .. tok.kind)
  end
  self:advance()
  return tok
end

function Parser:expect_keyword(word)
  if not self:match_keyword(word) then
    self:error("Expected keyword '" .. word .. "'")
  end
end

function Parser:error(msg)
  local tok = self:current()
  error(string.format("Parse error at %d:%d: %s", tok.line or 0, tok.col or 0, msg))
end

function Parser:parse_program()
  local items = {}
  while self:current().kind ~= "eof" do
    local is_pub = false
    if self:match_keyword("pub") then
      is_pub = true
    end
    local item = nil
    if self:match_keyword("use") then
      item = self:parse_use()
    elseif self:match_keyword("fn") then
      item = self:parse_function(false)
    elseif self:match_keyword("enum") then
      item = self:parse_enum()
    elseif self:match_keyword("struct") then
      item = self:parse_struct()
    elseif self:match_keyword("impl") then
      item = self:parse_impl()
    elseif self:match_keyword("type") then
      item = self:parse_type_alias()
    else
      if is_pub then
        self:error("pub can only be used on items")
      end
      item = self:parse_statement()
    end
    if item and is_pub then
      item.public = true
    end
    table.insert(items, item)
  end
  return ast.node("Program", { items = items })
end

function Parser:parse_use()
  local path = self:parse_path()
  local alias = nil
  if self:match_keyword("as") then
    alias = self:expect_kind("ident").value
  end
  self:match(";")
  return ast.node("Use", { path = path, alias = alias })
end

function Parser:parse_path()
  local parts = {}
  local first = self:expect_kind("ident")
  table.insert(parts, first.value)
  while self:match("::") do
    local seg = self:expect_kind("ident")
    table.insert(parts, seg.value)
  end
  return parts
end

function Parser:parse_type_params()
  if not self:match("<") then
    return nil
  end
  local params = {}
  if not self:match(">") then
    repeat
      local name = self:expect_kind("ident").value
      local bounds = nil
      if self:match(":") then
        bounds = {}
        repeat
          local path = self:parse_path()
          table.insert(bounds, table.concat(path, "::"))
        until not self:match("+")
      end
      table.insert(params, { name = name, bounds = bounds })
    until not self:match(",")
    self:expect(">")
  end
  return params
end

function Parser:parse_struct()
  local name = self:expect_kind("ident").value
  local params = self:parse_type_params()
  self:expect("{")
  local fields = {}
  while not self:match("}") do
    local field = self:expect_kind("ident").value
    local ftype = nil
    if self:match(":") then
      ftype = self:parse_type()
    end
    table.insert(fields, { name = field, type = ftype })
    self:match(",")
  end
  return ast.node("Struct", { name = name, params = params, fields = fields })
end

function Parser:parse_type_alias()
  local name = self:expect_kind("ident").value
  self:expect("=")
  local aliased = self:parse_type()
  self:match(";")
  return ast.node("TypeAlias", { name = name, aliased = aliased })
end

function Parser:parse_enum()
  local name = self:expect_kind("ident").value
  local params = self:parse_type_params()
  self:expect("{")
  local variants = {}
  while not self:match("}") do
    local vname = self:expect_kind("ident").value
    local payload = nil
    if self:match("(") then
      payload = {}
      if not self:match(")") then
        repeat
          table.insert(payload, self:parse_type())
        until not self:match(",")
        self:expect(")")
      end
    end
    table.insert(variants, { name = vname, types = payload })
    self:match(",")
  end
  if #variants == 0 then
    self:error("Enum must have at least one variant")
  end
  return ast.node("Enum", { name = name, params = params, variants = variants })
end

function Parser:parse_impl()
  local name = self:expect_kind("ident").value
  local params = self:parse_type_params()
  self:expect("{")
  local methods = {}
  while not self:match("}") do
    if self:match_keyword("fn") then
      table.insert(methods, self:parse_function(true))
    else
      self:error("Expected fn in impl block")
    end
  end
  return ast.node("Impl", { name = name, params = params, methods = methods })
end

function Parser:parse_function(is_method)
  local name = self:expect_kind("ident").value
  local type_params = self:parse_type_params()
  self:expect("(")
  local params = {}
  if not self:match(")") then
    repeat
      table.insert(params, self:parse_param())
    until not self:match(",")
    self:expect(")")
  end
  local return_type = nil
  if self:match("->") then
    return_type = self:parse_type()
  end
  local body = self:parse_block()
  return ast.node("Function", {
    name = name,
    type_params = type_params,
    params = params,
    return_type = return_type,
    body = body,
    is_method = is_method,
  })
end

function Parser:parse_param()
  local ref = nil
  if self:match("&") then
    ref = "ref"
    if self:match_keyword("mut") then
      ref = "ref_mut"
    end
  end
  local name = self:expect_kind("ident").value
  local ptype = nil
  if self:match(":") then
    ptype = self:parse_type()
  end
  return { name = name, type = ptype, ref = ref }
end


local function is_word(tok)
  return tok:match("^[A-Za-z0-9_]+$") ~= nil
end

local function join_type(parts)
  local out = {}
  local prev = nil
  for _, tok in ipairs(parts) do
    local need_space = false
    if prev then
      if tok == "," or tok == ")" or tok == "]" or tok == ">" then
        need_space = false
      elseif tok == "::" or tok == "<" or tok == "(" or tok == "[" then
        need_space = false
      elseif prev == "::" or prev == "<" or prev == "(" or prev == "[" or prev == "&" or prev == "*" then
        need_space = false
      elseif prev == "," then
        need_space = true
      elseif is_word(prev) and is_word(tok) then
        need_space = true
      end
    end
    if need_space then
      table.insert(out, " ")
    end
    table.insert(out, tok)
    prev = tok
  end
  return table.concat(out)
end

function Parser:parse_type()
  local parts = {}
  local depth = 0
  while true do
    local tok = self:current()
    if tok.kind == "eof" then
      break
    end
    if depth == 0 and (tok.value == "," or tok.value == ")" or tok.value == "{" or tok.value == "}" or tok.value == "=" or tok.value == ";") then
      break
    end
    if tok.value == "<" then
      depth = depth + 1
    elseif tok.value == ">" then
      depth = depth - 1
    end
    table.insert(parts, tok.value)
    self:advance()
  end
  return join_type(parts)
end

function Parser:parse_block()
  self:expect("{")
  local statements = {}
  while not self:match("}") do
    if self:current().kind == "eof" then
      self:error("Unterminated block")
    end
    table.insert(statements, self:parse_statement())
  end
  return ast.node("Block", { statements = statements })
end

function Parser:parse_statement()
  if self:match_keyword("let") then
    return self:parse_let(false)
  end
  if self:match_keyword("mut") then
    return self:parse_let(true)
  end
  if self:match_keyword("bond") then
    return self:parse_bond()
  end
  if self:match_keyword("commit") then
    self:match(";")
    return ast.node("Commit", {})
  end
  if self:match_keyword("rollback") then
    self:match(";")
    return ast.node("Rollback", {})
  end
  if self:match_keyword("defer") then
    return self:parse_defer()
  end
  if self:match_keyword("within") then
    return self:parse_within()
  end
  if self:match_keyword("during") then
    return self:parse_during()
  end
  if self:match_keyword("debug") then
    if self:match_keyword("ownership") then
      return self:parse_debug_ownership()
    else
      self:error("Expected 'ownership' after 'debug'")
    end
  end
  if self:match_keyword("return") then
    local value = nil
    if not self:match(";") then
      value = self:parse_expression()
      self:match(";")
    end
    return ast.node("Return", { value = value })
  end
  if self:match_keyword("if") then
    return self:parse_if()
  end
  if self:match_keyword("while") then
    return self:parse_while()
  end
  if self:match_keyword("for") then
    return self:parse_for()
  end
  if self:match_keyword("break") then
    self:match(";")
    return ast.node("Break", {})
  end
  if self:match_keyword("continue") then
    self:match(";")
    return ast.node("Continue", {})
  end
  if self:match_keyword("match") then
    return self:parse_match()
  end
  if self:match_keyword("unsafe") then
    local block = self:parse_block()
    return ast.node("Unsafe", { block = block })
  end
  if self:match_keyword("spawn") then
    local block = self:parse_block()
    return ast.node("Spawn", { block = block })
  end

  if self:is_index_assign_ahead() then
    local name = self:expect_kind("ident").value
    self:expect("[")
    local index = self:parse_expression()
    if self:match("..") then
      self:error("Slice assignment is not supported")
    end
    self:expect("]")
    self:expect("=")
    local value = self:parse_expression()
    self:match(";")
    return ast.node("IndexAssign", {
      object = ast.node("Identifier", { name = name }),
      index = index,
      value = value,
    })
  end

  if self:current().kind == "ident" and self:peek(1).value == "=" then
    local name = self:expect_kind("ident").value
    self:expect("=")
    local value = self:parse_expression()
    self:match(";")
    return ast.node("Assign", { name = name, value = value })
  end

  if self:current().kind == "ident"
    and self:peek(1).value == "."
    and self:peek(2).kind == "ident"
    and self:peek(3).value == "="
  then
    local name = self:expect_kind("ident").value
    self:expect(".")
    local prop = self:expect_kind("ident").value
    self:expect("=")
    local value = self:parse_expression()
    self:match(";")
    return ast.node("MemberAssign", {
      object = ast.node("Identifier", { name = name }),
      property = prop,
      value = value,
    })
  end

  if self:current().value == "*" and self:peek(1).kind == "ident" and self:peek(2).value == "=" then
    self:advance()
    local name = self:expect_kind("ident").value
    self:expect("=")
    local value = self:parse_expression()
    self:match(";")
    return ast.node("DerefAssign", { name = name, value = value })
  end

  local expr = self:parse_expression()
  self:match(";")
  return ast.node("ExprStmt", { expr = expr })
end

function Parser:is_index_assign_ahead()
  if self:current().kind ~= "ident" or self:peek(1).value ~= "[" then
    return false
  end
  local depth = 0
  local i = 1
  while true do
    local tok = self:peek(i)
    if not tok or tok.kind == "eof" then
      return false
    end
    if tok.value == "[" then
      depth = depth + 1
    elseif tok.value == "]" then
      depth = depth - 1
      if depth == 0 then
        return self:peek(i + 1).value == "="
      end
    end
    i = i + 1
  end
end

function Parser:parse_let(already_mut)
  local mutable = already_mut
  if not mutable and self:match_keyword("mut") then
    mutable = true
  end
  local pattern = self:parse_pattern()
  local ptype = nil
  if self:match(":") then
    ptype = self:parse_type()
  end
  self:expect("=")
  local value = self:parse_expression()
  self:match(";")
  return ast.node("Let", {
    mutable = mutable,
    pattern = pattern,
    type = ptype,
    value = value,
  })
end

function Parser:parse_pattern()
  if self:match("(") then
    local names = {}
    if not self:match(")") then
      repeat
        local name = self:expect_kind("ident").value
        table.insert(names, name)
      until not self:match(",")
      self:expect(")")
    end
    return ast.node("TuplePattern", { names = names })
  end
  local name = self:expect_kind("ident").value
  return ast.node("IdentPattern", { name = name })
end

function Parser:parse_match()
  local expr = self:parse_expression()
  self:expect("{")
  local arms = {}
  while not self:match("}") do
    local tag = self:expect_kind("ident").value
    local binding = nil
    if self:match("(") then
      binding = self:expect_kind("ident").value
      self:expect(")")
    end
    self:expect("=>")
    local body = nil
    if self:current().value == "{" then
      body = self:parse_block()
    else
      local expr_body = self:parse_expression()
      body = ast.node("Block", { statements = { ast.node("ExprStmt", { expr = expr_body }) } })
    end
    table.insert(arms, { tag = tag, binding = binding, body = body })
    self:match(",")
  end
  if #arms == 0 then
    self:error("Match must have at least one arm")
  end
  return ast.node("Match", { expr = expr, arms = arms })
end

function Parser:parse_defer()
  if self:current().value == "{" then
    local block = self:parse_block()
    return ast.node("Defer", { block = block })
  end
  local expr = self:parse_expression()
  self:match(";")
  return ast.node("Defer", { expr = expr })
end

function Parser:parse_bond()
  local name = self:expect_kind("ident").value
  self:expect("=")
  local value = self:parse_expression()
  self:match(";")
  return ast.node("Bond", { name = name, value = value })
end

function Parser:parse_for()
  local name = self:expect_kind("ident").value
  self:expect_keyword("in")
  local start = self:parse_expression()
  if self:match("..") then
    local finish = self:parse_expression()
    local body = self:parse_block()
    return ast.node("For", { name = name, range_start = start, range_end = finish, body = body })
  end
  local body = self:parse_block()
  return ast.node("For", { name = name, iter = start, body = body })
end

function Parser:parse_if()
  local cond = self:parse_expression()
  local then_block = self:parse_block()
  local else_block = nil
  if self:match_keyword("else") then
    if self:match_keyword("if") then
      local nested = self:parse_if()
      else_block = ast.node("Block", { statements = { nested } })
    else
      else_block = self:parse_block()
    end
  end
  return ast.node("If", { cond = cond, then_block = then_block, else_block = else_block })
end

function Parser:parse_while()
  local cond = self:parse_expression()
  local body = self:parse_block()
  return ast.node("While", { cond = cond, body = body })
end

function Parser:parse_expression()
  return self:parse_binary(1)
end

function Parser:parse_binary(min_prec)
  local left = self:parse_unary()
  while true do
    local op = self:current().value
    local prec = PRECEDENCE[op]
    if not prec or prec < min_prec then
      break
    end
    self:advance()
    local right = self:parse_binary(prec + 1)
    left = ast.node("Binary", { op = op, left = left, right = right })
  end
  return left
end

function Parser:parse_unary()
  if self:match("&") then
    local mutable = false
    if self:match_keyword("mut") then
      mutable = true
    end
    return ast.node("Borrow", { expr = self:parse_unary(), mutable = mutable })
  end
  if self:match("-") then
    return ast.node("Unary", { op = "-", expr = self:parse_unary() })
  end
  if self:match("!") then
    return ast.node("Unary", { op = "!", expr = self:parse_unary() })
  end
  if self:match("*") then
    return ast.node("Deref", { expr = self:parse_unary() })
  end
  return self:parse_postfix()
end

function Parser:parse_postfix()
  local expr = self:parse_primary()
  while true do
    if self:current().value == "<" and self:is_generic_ahead() then
      local type_args = self:parse_type_args()
      expr = ast.node("Generic", { expr = expr, type_args = type_args })
    elseif self:match("(") then
      local args = {}
      if not self:match(")") then
        repeat
          table.insert(args, self:parse_expression())
        until not self:match(",")
        self:expect(")")
      end
      local callee = expr
      local type_args = nil
      if callee.kind == "Generic" then
        type_args = callee.type_args
        callee = callee.expr
      end
      expr = ast.node("Call", { callee = callee, args = args, type_args = type_args })
    elseif self:match(".") then
      local prop = self:expect_kind("ident").value
      expr = ast.node("Member", { object = expr, property = prop })
    elseif self:match("[") then
      local first = nil
      if not self:match("]") then
        first = self:parse_expression()
        if self:match("..") then
          local finish = nil
          if not self:match("]") then
            finish = self:parse_expression()
            self:expect("]")
          end
          expr = ast.node("Slice", { object = expr, start = first, finish = finish })
        else
          self:expect("]")
          expr = ast.node("Index", { object = expr, index = first })
        end
      else
        self:error("Empty index")
      end
    elseif self:match("?") then
      expr = ast.node("Try", { expr = expr })
    else
      break
    end
  end
  return expr
end

function Parser:is_generic_ahead()
  if self:current().value ~= "<" then
    return false
  end
  local depth = 0
  local i = 0
  while true do
    local tok = self:peek(i)
    if not tok or tok.kind == "eof" then
      return false
    end
    if tok.kind == "keyword" or tok.kind == "string" then
      return false
    end
    if tok.value == "{" or tok.value == "}" or tok.value == ";" or tok.value == ")" then
      return false
    end
    if tok.value == "=" or tok.value == "==" or tok.value == "!=" or tok.value == "=>" then
      return false
    end
    if tok.value == "&&" or tok.value == "||" then
      return false
    end
    if tok.value == "<" then
      depth = depth + 1
    elseif tok.value == ">" then
      depth = depth - 1
      if depth == 0 then
        return self:peek(i + 1).value == "("
      end
    end
    i = i + 1
  end
end

function Parser:parse_type_args()
  local args = {}
  self:expect("<")
  local parts = {}
  local depth = 1
  while true do
    local tok = self:current()
    if tok.kind == "eof" then
      self:error("Unterminated type args")
    end
    if tok.value == "<" then
      depth = depth + 1
    elseif tok.value == ">" then
      depth = depth - 1
      if depth == 0 then
        if #parts > 0 then
          table.insert(args, join_type(parts))
        end
        self:advance()
        break
      end
    elseif tok.value == "," and depth == 1 then
      table.insert(args, join_type(parts))
      parts = {}
      self:advance()
      goto continue
    end
    table.insert(parts, tok.value)
    self:advance()
    ::continue::
  end
  return args
end

function Parser:parse_primary()
  local tok = self:current()
  if tok.kind == "keyword" then
    if tok.value == "true" then
      self:advance()
      return ast.node("Bool", { value = true })
    elseif tok.value == "false" then
      self:advance()
      return ast.node("Bool", { value = false })
    elseif tok.value == "nil" then
      self:advance()
      return ast.node("Nil", {})
    end
  end
  if tok.kind == "number" then
    self:advance()
    return ast.node("Number", { value = tok.value })
  end
  if tok.kind == "string" then
    self:advance()
    return ast.node("String", { value = tok.value })
  end
  if self:match("[") then
    local elements = {}
    if not self:match("]") then
      repeat
        table.insert(elements, self:parse_expression())
      until not self:match(",")
      self:expect("]")
    end
    return ast.node("Array", { elements = elements })
  end
  if tok.kind == "ident" then
    self:advance()
    return ast.node("Identifier", { name = tok.value })
  end
  if self:match("(") then
    local expr = self:parse_expression()
    self:expect(")")
    return expr
  end
  self:error("Unexpected token: " .. tok.value)
end

function Parser:parse_within()
  local duration = self:expect_kind("number").value
  local block = self:parse_block()
  return ast.node("WithinBlock", {
    duration = tonumber(duration),
    block = block
  })
end

function Parser:parse_during()
  local condition = self:expect_kind("ident").value
  local block = self:parse_block()
  return ast.node("DuringBlock", {
    condition = condition,
    block = block
  })
end

function Parser:parse_debug_ownership()
  if self:match("{") then
    local rules = {}
    while not self:match("}") do
      local rule_type = self:expect_kind("ident").value
      local variable = nil
      if self:match(":") then
        variable = self:expect_kind("ident").value
      end
      table.insert(rules, { type = rule_type, variable = variable })
      self:match(";")
    end
    return ast.node("DebugOwnership", { rules = rules })
  else
    return ast.node("DebugOwnership", { rules = {} })
  end
end

return Parser
