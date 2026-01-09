-- Thanks for the Rex team; I swear they make me happy.
-- Rex CLI
-- Usage: rex <command> [options]

local Lexer = require("compiler.lexer")
local Parser = require("compiler.parser")
local Codegen = require("compiler.codegen")
local Typechecker = require("compiler.typechecker")

local function read_file(path)
  local f, err = io.open(path, "rb")
  if not f then
    return nil, err
  end
  local data = f:read("*a")
  f:close()
  return data
end

local function write_file(path, data)
  local f, err = io.open(path, "wb")
  if not f then
    return nil, err
  end
  f:write(data)
  f:close()
  return true
end

local function format_source(src)
  local out = {}
  for line in (src .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("%s+$", "")
    table.insert(out, line)
  end
  local formatted = table.concat(out, "\n")
  if formatted:sub(-1) ~= "\n" then
    formatted = formatted .. "\n"
  end
  return formatted
end

local function mkdir_p(path)
  if not path or path == "" then
    return
  end
  local sep = package.config:sub(1, 1)
  if sep == "\\" then
    os.execute('if not exist "' .. path .. '" mkdir "' .. path .. '"')
  else
    os.execute('mkdir -p "' .. path .. '"')
  end
end

local function split_dir(path)
  return path:match("^(.*)[/\\]")
end

local function script_root()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  local dir = split_dir(src) or "."
  local parent = split_dir(dir) or "."
  return split_dir(parent) or "."
end

local function is_windows()
  return package.config:sub(1, 1) == "\\"
end

local function cmd_path(path)
  if not is_windows() or not path then
    return path
  end
  local p = path:gsub("/", "\\")
  if not p:match("^%a:[/\\]") and not p:match("^\\\\") and not p:match("^%.") then
    p = ".\\" .. p
  end
  return p
end

local function default_c_out()
  return "build/main.c"
end

local function default_exe_path(out)
  local base = out:gsub("%.c$", "")
  if is_windows() then
    return base .. ".exe"
  end
  return base
end

local function detect_platform()
  if is_windows() then
    return "windows"
  end
  local p = io.popen("uname -s")
  if not p then
    return "unix"
  end
  local name = p:read("*l") or ""
  p:close()
  if name:match("Darwin") then
    return "mac"
  end
  if name:match("Linux") then
    return "linux"
  end
  return "linux"
end

local function list_example_files()
  local sep = package.config:sub(1, 1)
  local cmd = sep == "\\" and 'dir /b "examples\\*.rex"' or "ls examples/*.rex"
  local p = io.popen(cmd)
  if not p then
    return {}
  end
  local files = {}
  for line in p:lines() do
    line = line:gsub("\r", "")
    if line ~= "" then
      if sep == "\\" then
        table.insert(files, "examples/" .. line)
      else
        table.insert(files, line)
      end
    end
  end
  p:close()
  return files
end

local function exec_ok(cmd)
  local ok, why, code = os.execute(cmd)
  if type(ok) == "number" then
    return ok == 0
  end
  if type(ok) == "boolean" then
    if ok then
      return true
    end
    if why == "exit" and type(code) == "number" then
      return code == 0
    end
    return false
  end
  return false
end

local function compile_c(source, output, cc)
  local root = script_root()
  local runtime_dir = root .. "/runtime_c"
  local runtime_c = runtime_dir .. "/rex_rt.c"
  local ui_common = runtime_dir .. "/rex_ui.c"
  local platform = detect_platform()
  local sources = { source, runtime_c, ui_common }
  local libs = ""
  if platform == "windows" then
    table.insert(sources, runtime_dir .. "/rex_ui_win.c")
    libs = " -lgdi32 -luser32 -lws2_32 -lwinhttp -lcrypt32 -lwinmm -lole32 -luuid -lwindowscodecs"
  elseif platform == "linux" then
    table.insert(sources, runtime_dir .. "/rex_ui_x11.c")
    libs = " -lX11 -pthread -lssl -lcrypto"
  elseif platform == "mac" then
    table.insert(sources, runtime_dir .. "/rex_ui_mac.m")
    libs = " -framework Cocoa -lssl -lcrypto"
  end
  mkdir_p(split_dir(output))
  local quoted = {}
  for _, path in ipairs(sources) do
    table.insert(quoted, "\"" .. path .. "\"")
  end
  local cmd = string.format('%s %s -I \"%s\" -o \"%s\"%s', cc, table.concat(quoted, " "), runtime_dir, output, libs)
  if not exec_ok(cmd) then
    error("C compile failed. Check that your compiler is available.")
  end
end

local function build(input, c_out, emit_entry)
  local source, err = read_file(input)
  if not source then
    error("Failed to read " .. input .. ": " .. err)
  end
  local lexer = Lexer.new(source)
  local tokens = lexer:tokenize()
  local parser = Parser.new(tokens)
  local ast = parser:parse_program()
  Typechecker.check(ast)
  local output = Codegen.generate(ast, { emit_entry = emit_entry })
  mkdir_p(split_dir(c_out))
  local ok, werr = write_file(c_out, output)
  if not ok then
    error("Failed to write " .. c_out .. ": " .. werr)
  end
end

local function init_project(path)
  mkdir_p(path)
  mkdir_p(path .. "/src")
  local manifest = "name = 'app'\nversion = '0.1.0'\n"
  write_file(path .. "/rex.toml", manifest)
  local main = table.concat({
    "use rex::io",
    "use rex::thread",
    "",
    "fn main() {",
    "    println(\"Hello from Rex\")",
    "    let (tx, rx) = channel<i32>()",
    "    spawn { tx.send(7) }",
    "    println(\"=> \" + rx.recv())",
    "}",
    "",
  }, "\n")
  write_file(path .. "/src/main.rex", main)
end

local function usage()
  print("Rex CLI")
  print("  rex init <dir>")
  print("  rex build [input] [--out path] [--c-out path] [--no-entry] [--no-native] [--cc compiler]")
  print("  rex run [input] [--cc compiler]")
  print("  rex test (builds examples to C)")
  print("  rex fmt [input]")
  print("  rex lint [input]")
end

local args = { ... }
local cmd = args[1] or "help"

if cmd == "init" then
  local path = args[2] or "rex-app"
  init_project(path)
  print("Initialized " .. path)
elseif cmd == "build" then
  local input = args[2] or "src/main.rex"
  local out = default_exe_path(default_c_out())
  local c_out = default_c_out()
  local out_set = false
  local c_out_set = false
  local emit_entry = true
  local native = true
  local cc = os.getenv("CC") or "cc"
  local i = 3
  while i <= #args do
    local a = args[i]
    if a == "--out" then
      if not args[i + 1] then
        error("--out requires a value")
      end
      out = args[i + 1]
      out_set = true
      i = i + 1
    elseif a == "--c-out" then
      if not args[i + 1] then
        error("--c-out requires a value")
      end
      c_out = args[i + 1]
      c_out_set = true
      i = i + 1
    elseif a == "--no-entry" then
      emit_entry = false
    elseif a == "--no-native" then
      native = false
    elseif a == "--cc" then
      if not args[i + 1] then
        error("--cc requires a value")
      end
      cc = args[i + 1]
      i = i + 1
    end
    i = i + 1
  end
  if not c_out_set then
    c_out = default_c_out()
  end
  if c_out_set and not out_set then
    out = default_exe_path(c_out)
  end
  build(input, c_out, emit_entry)
  if native then
    compile_c(c_out, out, cc)
    print("Native " .. out)
  end
  print("Built " .. c_out)
elseif cmd == "run" then
  local input = args[2] or "src/main.rex"
  local c_out = default_c_out()
  local out = default_exe_path(c_out)
  local out_set = false
  local c_out_set = false
  local cc = os.getenv("CC") or "cc"
  local i = 3
  while i <= #args do
    local a = args[i]
    if a == "--cc" then
      if not args[i + 1] then
        error("--cc requires a value")
      end
      cc = args[i + 1]
      i = i + 1
    elseif a == "--out" then
      if not args[i + 1] then
        error("--out requires a value")
      end
      out = args[i + 1]
      out_set = true
      i = i + 1
    elseif a == "--c-out" then
      if not args[i + 1] then
        error("--c-out requires a value")
      end
      c_out = args[i + 1]
      c_out_set = true
      i = i + 1
    end
    i = i + 1
  end
  if c_out_set and not out_set then
    out = default_exe_path(c_out)
  end
  build(input, c_out, true)
  compile_c(c_out, out, cc)
  local run_path = cmd_path(out)
  if not exec_ok('"' .. run_path .. '"') then
    error("Run failed")
  end
elseif cmd == "test" then
  local files = list_example_files()
  if #files == 0 then
    print("No examples found")
  else
    mkdir_p("build/tests")
    for _, file in ipairs(files) do
      local base = file:match("([^/\\]+)%.rex$") or "example"
      local c_out = "build/tests/" .. base .. ".c"
      build(file, c_out, true)
    end
    print("Built " .. #files .. " example(s)")
  end
elseif cmd == "fmt" then
  local input = args[2] or "src/main.rex"
  local source, err = read_file(input)
  if not source then
    error("Failed to read " .. input .. ": " .. err)
  end
  local formatted = format_source(source)
  local ok, werr = write_file(input, formatted)
  if not ok then
    error("Failed to write " .. input .. ": " .. werr)
  end
  print("Formatted " .. input)
elseif cmd == "lint" then
  local input = args[2] or "src/main.rex"
  local source, err = read_file(input)
  if not source then
    error("Failed to read " .. input .. ": " .. err)
  end
  local lexer = Lexer.new(source)
  local tokens = lexer:tokenize()
  local parser = Parser.new(tokens)
  local ast = parser:parse_program()
  Typechecker.check(ast)
  print("OK " .. input)
else
  usage()
end
