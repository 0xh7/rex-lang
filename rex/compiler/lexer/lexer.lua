-- Lexer for Rex language 
-- Tokenizes Rex source code into a stream of tokens 
-- Supports identifiers, keywords, numbers, strings, symbols, and comments 
-- made by rex team  
local Lexer = {}
Lexer.__index = Lexer

local keywords = {
  ["let"] = true,
  ["mut"] = true,
  ["fn"] = true,
  ["struct"] = true,
  ["impl"] = true,
  ["return"] = true,
  ["use"] = true,
  ["match"] = true,
  ["unsafe"] = true,
  ["spawn"] = true,
  ["if"] = true,
  ["else"] = true,
  ["while"] = true,
  ["break"] = true,
  ["continue"] = true,
  ["enum"] = true,
  ["for"] = true,
  ["in"] = true,
  ["defer"] = true,
  ["pub"] = true,
  ["type"] = true,
  ["as"] = true,
  ["true"] = true,
  ["false"] = true,
  ["nil"] = true,
  ["bond"] = true,
  ["commit"] = true,
  ["rollback"] = true,
  ["within"] = true,
  ["during"] = true,
  ["temporal"] = true,
  ["debug"] = true,
  ["ownership"] = true,

}

local function is_alpha(c)
  return c:match("[A-Za-z_]") ~= nil
end

local function is_alnum(c)
  return c:match("[A-Za-z0-9_]") ~= nil
end

local function is_digit(c)
  return c:match("%d") ~= nil
end

function Lexer.new(input)
  return setmetatable({
    input = input,
    pos = 1,
    len = #input,
    line = 1,
    col = 1,
  }, Lexer)
end

function Lexer:peek(offset)
  offset = offset or 0
  local idx = self.pos + offset
  if idx > self.len then
    return ""
  end
  return self.input:sub(idx, idx)
end

function Lexer:advance()
  local c = self:peek()
  if c == "" then
    return ""
  end
  self.pos = self.pos + 1
  if c == "\n" then
    self.line = self.line + 1
    self.col = 1
  else
    self.col = self.col + 1
  end
  return c
end

function Lexer:skip_whitespace_and_comments()
  while true do
    local c = self:peek()
    if c == "" then
      return
    end
    if c == " " or c == "\t" or c == "\r" or c == "\n" then
      self:advance()
    elseif c == "/" and self:peek(1) == "/" then
      self:advance()
      self:advance()
      while self:peek() ~= "" and self:peek() ~= "\n" do
        self:advance()
      end
    elseif c == "/" and self:peek(1) == "*" then
      local start_line, start_col = self.line, self.col
      self:advance()
      self:advance()
      while true do
        if self:peek() == "" then
          error("Unterminated block comment at " .. start_line .. ":" .. start_col)
        end
        if self:peek() == "*" and self:peek(1) == "/" then
          self:advance()
          self:advance()
          break
        end
        self:advance()
      end
    else
      return
    end
  end
end

function Lexer:next_token()
  self:skip_whitespace_and_comments()
  local c = self:peek()
  if c == "" then
    return { kind = "eof", value = "", line = self.line, col = self.col }
  end

  if is_alpha(c) then
    local start_line, start_col = self.line, self.col
    local buf = {}
    while true do
      local ch = self:peek()
      if is_alnum(ch) then
        table.insert(buf, self:advance())
      else
        break
      end
    end
    local text = table.concat(buf)
    if keywords[text] then
      return { kind = "keyword", value = text, line = start_line, col = start_col }
    end
    return { kind = "ident", value = text, line = start_line, col = start_col }
  end

  if is_digit(c) then
    local start_line, start_col = self.line, self.col
    local buf = {}
    while is_digit(self:peek()) do
      table.insert(buf, self:advance())
    end
    if self:peek() == "." and is_digit(self:peek(1)) then
      table.insert(buf, self:advance())
      while is_digit(self:peek()) do
        table.insert(buf, self:advance())
      end
    end
    return { kind = "number", value = table.concat(buf), line = start_line, col = start_col }
  end

  if c == '"' then
    local start_line, start_col = self.line, self.col
    self:advance()
    local buf = {}
    while true do
      local ch = self:peek()
      if ch == "" then
        error("Unterminated string at " .. start_line .. ":" .. start_col)
      end
      if ch == '"' then
        self:advance()
        break
      end
      if ch == "\\" then
        self:advance()
        local esc = self:advance()
        if esc == "n" then
          table.insert(buf, "\n")
        elseif esc == "t" then
          table.insert(buf, "\t")
        elseif esc == "r" then
          table.insert(buf, "\r")
        elseif esc == '"' then
          table.insert(buf, '"')
        elseif esc == "\\" then
          table.insert(buf, "\\")
        else
          table.insert(buf, esc)
        end
      else
        table.insert(buf, self:advance())
      end
    end
    return { kind = "string", value = table.concat(buf), line = start_line, col = start_col }
  end

  local start_line, start_col = self.line, self.col
  local two = c .. self:peek(1)
  local double_symbols = {
    ["::"] = true,
    ["->"] = true,
    ["=>"] = true,
    ["=="] = true,
    ["!="] = true,
    ["<="] = true,
    [">="] = true,
    ["&&"] = true,
    ["||"] = true,
    [".."] = true,
  }
  if double_symbols[two] then
    self:advance()
    self:advance()
    return { kind = "symbol", value = two, line = start_line, col = start_col }
  end

  self:advance()
  return { kind = "symbol", value = c, line = start_line, col = start_col }
end

function Lexer:tokenize()
  local tokens = {}
  while true do
    local tok = self:next_token()
    table.insert(tokens, tok)
    if tok.kind == "eof" then
      break
    end
  end
  return tokens
end

return Lexer
