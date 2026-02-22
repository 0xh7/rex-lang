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

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
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
    return true
  end
  local sep = package.config:sub(1, 1)
  local cmd
  if sep == "\\" then
    cmd = 'if not exist "' .. path .. '" mkdir "' .. path .. '" >nul 2>nul'
  else
    cmd = 'mkdir -p "' .. path .. '" >/dev/null 2>&1'
  end
  local ok = os.execute(cmd)
  if type(ok) == "number" then
    return ok == 0
  end
  if type(ok) == "boolean" then
    return ok
  end
  return false
end

local function split_dir(path)
  return path:match("^(.*)[/\\]")
end

local function join_path(a, b)
  if not a or a == "" then
    return b
  end
  if not b or b == "" then
    return a
  end
  local last = a:sub(-1)
  if last == "/" or last == "\\" then
    return a .. b
  end
  local sep = package.config:sub(1, 1)
  return a .. sep .. b
end

local function normalize_path(path)
  local normalized = (path or ""):gsub("\\", "/")
  return normalized
end

local function is_absolute_path(path)
  if not path or path == "" then
    return false
  end
  if path:sub(1, 1) == "/" then
    return true
  end
  if path:match("^%a:[/\\]") then
    return true
  end
  if path:match("^\\\\") then
    return true
  end
  return false
end

local function read_with_includes(path, seen, stack, deps)
  local key = normalize_path(path)
  seen = seen or {}
  stack = stack or {}
  deps = deps or {}
  if stack[key] then
    error("Include cycle detected: " .. key)
  end
  if seen[key] then
    return "", deps
  end
  seen[key] = true
  stack[key] = true
  table.insert(deps, key)

  local source, err = read_file(path)
  if not source then
    error("Failed to read " .. path .. ": " .. err)
  end
  local base = split_dir(path) or "."
  local out = {}
  for line in (source .. "\n"):gmatch("(.-)\n") do
    local inc = line:match("^%s*//%s*@include%s+(.+)%s*$")
    if inc then
      inc = inc:gsub("^\"", ""):gsub("\"$", "")
      local inc_path = inc
      if not is_absolute_path(inc_path) then
        inc_path = base .. "/" .. inc_path
      end
      inc_path = normalize_path(inc_path)
      table.insert(out, "// @include " .. inc)
      local include_src = read_with_includes(inc_path, seen, stack, deps)
      table.insert(out, include_src)
      table.insert(out, "// @endinclude " .. inc)
    else
      table.insert(out, line)
    end
  end
  stack[key] = nil
  return table.concat(out, "\n"), deps
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

local function write_probe_suffix()
  return tostring(os.time()) .. "_" .. tostring(math.floor((os.clock() or 0) * 1000000))
end

local function is_writable_dir(path)
  if not mkdir_p(path) then
    return false
  end
  local probe = join_path(path, ".rex_write_" .. write_probe_suffix() .. ".tmp")
  local f = io.open(probe, "wb")
  if not f then
    return false
  end
  f:write("ok")
  f:close()
  os.remove(probe)
  return true
end

local resolved_build_root = nil

local function resolve_build_root()
  if resolved_build_root then
    return resolved_build_root
  end

  local env_build_dir = os.getenv("REX_BUILD_DIR")
  if env_build_dir and env_build_dir ~= "" then
    if is_writable_dir(env_build_dir) then
      resolved_build_root = env_build_dir
      return resolved_build_root
    end
    error("REX_BUILD_DIR is not writable: " .. env_build_dir)
  end

  if is_writable_dir("build") then
    resolved_build_root = "build"
    return resolved_build_root
  end

  local candidates = {}
  if is_windows() then
    local local_app_data = os.getenv("LOCALAPPDATA")
    if local_app_data and local_app_data ~= "" then
      table.insert(candidates, join_path(join_path(local_app_data, "RexLang"), "build"))
    end
  else
    local xdg_cache_home = os.getenv("XDG_CACHE_HOME")
    if xdg_cache_home and xdg_cache_home ~= "" then
      table.insert(candidates, join_path(join_path(xdg_cache_home, "rex"), "build"))
    end
  end
  local tmp = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP")
  if tmp and tmp ~= "" then
    table.insert(candidates, join_path(tmp, "rex-build"))
  end
  if not is_windows() then
    table.insert(candidates, "/tmp/rex-build")
  end

  for _, candidate in ipairs(candidates) do
    if is_writable_dir(candidate) then
      resolved_build_root = candidate
      io.stderr:write("Rex: current directory is read-only; using build directory: " .. candidate .. "\n")
      return resolved_build_root
    end
  end

  error("No writable build directory found. Set REX_BUILD_DIR to a writable path.")
end

local function default_c_out()
  return join_path(resolve_build_root(), "main.c")
end

local function default_exe_path(out)
  local base = out:gsub("%.c$", "")
  if is_windows() then
    return base .. ".exe"
  end
  return base
end

local function path_stem(path)
  local p = normalize_path(path or "")
  local name = p:match("([^/]+)$") or p
  local stem = name:gsub("%.rex$", "")
  if stem == "" then
    return "app"
  end
  return stem
end

local function unique_suffix()
  local tmp = os.tmpname()
  if type(tmp) == "string" and tmp ~= "" then
    local cleaned = tmp:gsub("[^%w]+", "")
    if cleaned ~= "" then
      return cleaned
    end
  end
  return tostring(os.time())
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
  local cmd = sep == "\\"
    and 'dir /s /b "examples\\*.rex"'
    or 'find "examples" -type f -name "*.rex"'
  local p = io.popen(cmd)
  if not p then
    return {}
  end
  local files = {}
  for line in p:lines() do
    line = line:gsub("\r", "")
    if line ~= "" then
      line = normalize_path(line)
      table.insert(files, line)
    end
  end
  p:close()
  table.sort(files)
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

local function sleep_short()
  if is_windows() then
    os.execute("timeout /t 1 /nobreak >nul 2>nul")
  else
    os.execute("sleep 1 >/dev/null 2>&1")
  end
end

local function run_exec(path)
  local run_path = cmd_path(path)
  local cmd = '"' .. run_path .. '"'
  if not is_windows() then
    return exec_ok(cmd)
  end
  -- On Windows, newly generated binaries can be transiently locked.
  local attempts = 4
  for i = 1, attempts do
    if exec_ok(cmd) then
      return true
    end
    if i < attempts then
      sleep_short()
    end
  end
  return false
end

local function first_command_token(command)
  local raw = tostring(command or ""):gsub("^%s+", "")
  if raw == "" then
    return nil
  end
  if raw:sub(1, 1) == '"' then
    return raw:match('^"([^"]+)"')
  end
  return raw:match("^([^%s]+)")
end

local function command_exists(command)
  local token = first_command_token(command)
  if not token or token == "" then
    return false
  end
  if token:match("[/\\]") or is_absolute_path(token) then
    return file_exists(token)
  end
  if is_windows() then
    return exec_ok('where "' .. token .. '" >nul 2>nul')
  end
  return exec_ok('command -v "' .. token .. '" >/dev/null 2>&1')
end

local function detect_default_cc()
  local env_cc = os.getenv("CC")
  if env_cc and env_cc ~= "" then
    return env_cc
  end
  local candidates
  if detect_platform() == "windows" then
    candidates = { "clang", "gcc", "zig cc", "cc" }
  else
    candidates = { "cc", "clang", "gcc", "zig cc" }
  end
  for _, c in ipairs(candidates) do
    if command_exists(c) then
      return c
    end
  end
  return nil
end

local function missing_compiler_message(cc)
  local lines = {}
  if cc and cc ~= "" then
    table.insert(lines, "C compiler not found: " .. cc)
  else
    table.insert(lines, "No supported C compiler found (tried clang, gcc, zig cc, cc).")
  end
  if detect_platform() == "windows" then
    table.insert(lines, "Install a compiler (recommended): winget install -e --id LLVM.LLVM")
    table.insert(lines, "Then reopen terminal and run: setx CC clang")
  elseif detect_platform() == "mac" then
    table.insert(lines, "Install Xcode Command Line Tools: xcode-select --install")
  else
    table.insert(lines, "Install build tools (for example: gcc or clang).")
  end
  return table.concat(lines, "\n")
end

local function normalize_build_mode(mode)
  local m = mode
  if not m or m == "" then
    m = os.getenv("REX_BUILD_MODE") or os.getenv("REX_MODE") or "release"
  end
  m = tostring(m):lower()
  if m == "release" or m == "debug" then
    return m
  end
  error("Invalid build mode: " .. tostring(mode) .. " (expected 'release' or 'debug')")
end

local function parse_elapsed_ms(output)
  if not output then
    return nil
  end
  local ms = output:match("elapsed:%s*([%+%-]?[%d%.]+)%s*ms")
  if not ms then
    ms = output:match("elapsed_ms%s*=%s*([%+%-]?[%d%.]+)")
  end
  if not ms then
    return nil
  end
  return tonumber(ms)
end

local BUILD_CACHE_VERSION = "2026-02-09-v1"

local function hash_data(data)
  local h = 5381
  for i = 1, #data do
    h = (h * 33 + data:byte(i)) % 4294967296
  end
  return string.format("%08x", h)
end

local function make_fingerprint(parts)
  return hash_data(table.concat(parts, "\0"))
end

local function read_cache(path)
  local text = read_file(path)
  if not text then
    return {}
  end
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local k, v = line:match("^([^=]+)=(.*)$")
    if k then
      out[k] = v
    end
  end
  return out
end

local function write_cache(path, data)
  local keys = {}
  for k, _ in pairs(data) do
    table.insert(keys, k)
  end
  table.sort(keys)
  local lines = {}
  for _, k in ipairs(keys) do
    table.insert(lines, k .. "=" .. tostring(data[k]))
  end
  return write_file(path, table.concat(lines, "\n") .. "\n")
end

local function has_alsa()
  if exec_ok("pkg-config --exists alsa 2>/dev/null") then
    return true
  end
  local headers = {
    "/usr/include/alsa/asoundlib.h",
    "/usr/local/include/alsa/asoundlib.h",
  }
  local header_ok = false
  for _, path in ipairs(headers) do
    if file_exists(path) then
      header_ok = true
      break
    end
  end
  if not header_ok then
    return false
  end
  local libs = {
    "/lib/libasound.so",
    "/lib/libasound.so.2",
    "/lib64/libasound.so",
    "/lib64/libasound.so.2",
    "/lib/x86_64-linux-gnu/libasound.so",
    "/lib/x86_64-linux-gnu/libasound.so.2",
    "/usr/lib/libasound.so",
    "/usr/lib/libasound.so.2",
    "/usr/lib64/libasound.so",
    "/usr/lib64/libasound.so.2",
    "/usr/lib/x86_64-linux-gnu/libasound.so",
    "/usr/lib/x86_64-linux-gnu/libasound.so.2",
    "/usr/local/lib/libasound.so",
    "/usr/local/lib/libasound.so.2",
  }
  for _, path in ipairs(libs) do
    if file_exists(path) then
      return true
    end
  end
  return false
end

local function compile_c(source, output, cc, mode)
  if not cc or cc == "" then
    error(missing_compiler_message(nil))
  end
  if not command_exists(cc) then
    error(missing_compiler_message(cc))
  end
  local root = script_root()
  local runtime_dir = root .. "/runtime_c"
  local runtime_c = runtime_dir .. "/rex_rt.c"
  local ui_common = runtime_dir .. "/rex_ui.c"
  local audio_common = runtime_dir .. "/rex_audio.c"
  local audio_mac = runtime_dir .. "/rex_audio_mac.m"
  local platform = detect_platform()
  local sources = { source, runtime_c, ui_common }
  mode = normalize_build_mode(mode)
  local cflags = ""
  if mode == "debug" then
    cflags = cflags .. " -O0 -g3 -DREX_DEBUG=1"
  else
    cflags = cflags .. " -O3 -DNDEBUG"
  end
  local opt_flag = os.getenv("REX_OPT_FLAG")
  if opt_flag and opt_flag ~= "" then
    local lowered = opt_flag:lower()
    if lowered == "0" or lowered == "off" or lowered == "none" then
      cflags = cflags:gsub("%s%-O%d%s", " ")
      cflags = cflags:gsub("%s%-O%d$", "")
      cflags = cflags:gsub("^%-O%d%s", "")
    else
      cflags = cflags .. " " .. opt_flag
    end
  end
  local extra_cflags = os.getenv("REX_CFLAGS")
  if extra_cflags and extra_cflags ~= "" then
    cflags = cflags .. " " .. extra_cflags
  end
  local libs = ""
  if platform == "windows" then
    table.insert(sources, audio_common)
    table.insert(sources, runtime_dir .. "/rex_ui_win.c")
    libs = " -lgdi32 -luser32 -lws2_32 -lwinhttp -lcrypt32 -lwinmm -lole32 -luuid -lwindowscodecs"
  elseif platform == "linux" then
    table.insert(sources, audio_common)
    table.insert(sources, runtime_dir .. "/rex_ui_x11.c")
    libs = " -lX11 -pthread -lssl -lcrypto -lm"
    if has_alsa() then
      libs = libs .. " -lasound"
      cflags = cflags .. " -DREX_AUDIO_HAS_ALSA=1"
    else
      cflags = cflags .. " -DREX_AUDIO_HAS_ALSA=0"
    end
  elseif platform == "mac" then
    table.insert(sources, audio_mac)
    table.insert(sources, runtime_dir .. "/rex_ui_mac.m")
    libs = " -framework Cocoa -lssl -lcrypto"
  end
  mkdir_p(split_dir(output))
  local quoted = {}
  for _, path in ipairs(sources) do
    table.insert(quoted, "\"" .. path .. "\"")
  end
  local native_key_parts = {
    BUILD_CACHE_VERSION,
    "native",
    platform,
    cc or "",
    mode or "",
    cflags,
    libs,
  }
  for _, path in ipairs(sources) do
    local data, err = read_file(path)
    if not data then
      error("Failed to read " .. path .. ": " .. err)
    end
    table.insert(native_key_parts, normalize_path(path))
    table.insert(native_key_parts, hash_data(data))
  end
  local runtime_headers = {
    runtime_dir .. "/rex_rt.h",
    runtime_dir .. "/rex_ui.h",
    runtime_dir .. "/rex_audio.h",
  }
  for _, path in ipairs(runtime_headers) do
    local data = read_file(path)
    if data then
      table.insert(native_key_parts, normalize_path(path))
      table.insert(native_key_parts, hash_data(data))
    end
  end
  local native_hash = make_fingerprint(native_key_parts)
  local native_cache_path = output .. ".native.cache"
  local native_cache = read_cache(native_cache_path)
  if file_exists(output) and native_cache.version == BUILD_CACHE_VERSION and native_cache.native_hash == native_hash then
    return { cached = true, hash = native_hash, cache_path = native_cache_path }
  end

  local cmd = string.format('%s %s%s -I \"%s\" -o \"%s\"%s', cc, table.concat(quoted, " "), cflags, runtime_dir, output, libs)
  if not exec_ok(cmd) then
    error("C compile failed. Check that your compiler is available.")
  end
  local ok, werr = write_cache(native_cache_path, {
    version = BUILD_CACHE_VERSION,
    native_hash = native_hash,
  })
  if not ok then
    error("Failed to write cache " .. native_cache_path .. ": " .. werr)
  end
  return { cached = false, hash = native_hash, cache_path = native_cache_path }
end

local function build(input, c_out, emit_entry)
  local source, deps = read_with_includes(input)
  local source_hash = make_fingerprint({
    BUILD_CACHE_VERSION,
    "rex-codegen",
    tostring(emit_entry ~= false),
    source,
  })
  local build_cache_path = c_out .. ".build.cache"
  local build_cache = read_cache(build_cache_path)
  if file_exists(c_out)
    and build_cache.version == BUILD_CACHE_VERSION
    and build_cache.source_hash == source_hash
    and build_cache.emit_entry == tostring(emit_entry ~= false)
  then
    return {
      cached = true,
      hash = source_hash,
      cache_path = build_cache_path,
      deps = deps or {},
    }
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
  local wrote, cerr = write_cache(build_cache_path, {
    version = BUILD_CACHE_VERSION,
    source_hash = source_hash,
    emit_entry = tostring(emit_entry ~= false),
  })
  if not wrote then
    error("Failed to write cache " .. build_cache_path .. ": " .. cerr)
  end
  return {
    cached = false,
    hash = source_hash,
    cache_path = build_cache_path,
    deps = deps or {},
  }
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
  print("  rex build [input] [--out path] [--c-out path] [--no-entry] [--no-native] [--cc compiler] [--mode release|debug]")
  print("  rex run [input] [--cc compiler] [--mode release|debug]")
  print("  rex bench [input] [--runs n] [--cc compiler] [--mode release|debug]")
  print("  rex test (builds examples to C)")
  print("  rex fmt [input]")
  print("  rex lint [input]")
  print("  rex check [input]")
  print("  note: native build/run need a C compiler (clang, gcc, or zig cc)")
  print("  env: REX_BUILD_DIR=<writable path> (optional)")
end

local args = { ... }
local cmd = args[1] or "help"

if cmd == "init" then
  local path = args[2] or "rex-app"
  init_project(path)
  print("Initialized " .. path)
elseif cmd == "build" then
  local input = args[2] or "src/main.rex"
  local c_out = default_c_out()
  local out = default_exe_path(c_out)
  local out_set = false
  local c_out_set = false
  local emit_entry = true
  local native = true
  local cc = detect_default_cc()
  local mode = normalize_build_mode(nil)
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
    elseif a == "--mode" then
      if not args[i + 1] then
        error("--mode requires a value")
      end
      mode = normalize_build_mode(args[i + 1])
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
  local build_info = build(input, c_out, emit_entry)
  if native then
    local native_info = compile_c(c_out, out, cc, mode)
    if native_info.cached then
      print("Native (cached) " .. out)
    else
      print("Native " .. out)
    end
  end
  if build_info.cached then
    print("Built (cached) " .. c_out)
  else
    print("Built " .. c_out)
  end
elseif cmd == "run" then
  local input = args[2] or "src/main.rex"
  local run_base = path_stem(input)
  local run_id = unique_suffix()
  local run_dir = join_path(resolve_build_root(), "run")
  local c_out = join_path(run_dir, run_base .. "_" .. run_id .. ".c")
  local out = default_exe_path(c_out)
  local out_set = false
  local c_out_set = false
  local cc = detect_default_cc()
  local mode = normalize_build_mode(nil)
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
    elseif a == "--mode" then
      if not args[i + 1] then
        error("--mode requires a value")
      end
      mode = normalize_build_mode(args[i + 1])
      i = i + 1
    end
    i = i + 1
  end
  if c_out_set and not out_set then
    out = default_exe_path(c_out)
  end
  build(input, c_out, true)
  compile_c(c_out, out, cc, mode)
  if not run_exec(out) then
    error("Run failed")
  end
elseif cmd == "bench" then
  local input = args[2] or "examples/benchmark.rex"
  local runs = 5
  local cc = detect_default_cc()
  local mode = normalize_build_mode(nil)
  local i = 3
  if input:sub(1, 2) == "--" then
    input = "examples/benchmark.rex"
    i = 2
  end
  while i <= #args do
    local a = args[i]
    if a == "--runs" then
      if not args[i + 1] then
        error("--runs requires a value")
      end
      runs = tonumber(args[i + 1]) or 0
      i = i + 1
    elseif a == "--cc" then
      if not args[i + 1] then
        error("--cc requires a value")
      end
      cc = args[i + 1]
      i = i + 1
    elseif a == "--mode" then
      if not args[i + 1] then
        error("--mode requires a value")
      end
      mode = normalize_build_mode(args[i + 1])
      i = i + 1
    end
    i = i + 1
  end
  if runs < 1 then
    error("--runs must be >= 1")
  end
  local bench_base = path_stem(input)
  local bench_id = unique_suffix()
  local bench_dir = join_path(resolve_build_root(), "bench")
  local c_out = join_path(bench_dir, bench_base .. "_" .. bench_id .. ".c")
  local out = default_exe_path(join_path(bench_dir, bench_base .. "_" .. bench_id))
  build(input, c_out, true)
  compile_c(c_out, out, cc, mode)
  local run_path = cmd_path(out)
  local count = 0
  local sum = 0.0
  local min_ms = nil
  local max_ms = nil
  for r = 1, runs do
    local p = io.popen('"' .. run_path .. '"')
    if not p then
      error("Failed to run benchmark executable")
    end
    local output = p:read("*a") or ""
    local ok = p:close()
    if ok == false then
      error("Benchmark run failed")
    end
    local elapsed = parse_elapsed_ms(output)
    if elapsed then
      count = count + 1
      sum = sum + elapsed
      if not min_ms or elapsed < min_ms then
        min_ms = elapsed
      end
      if not max_ms or elapsed > max_ms then
        max_ms = elapsed
      end
      print(string.format("run#%d elapsed_ms=%.6f", r, elapsed))
    else
      print("run#" .. r .. " elapsed_ms=NA")
    end
  end
  if count > 0 then
    print(string.format("avg_ms=%.6f", sum / count))
    print(string.format("min_ms=%.6f", min_ms))
    print(string.format("max_ms=%.6f", max_ms))
  else
    print("No elapsed values parsed from output.")
  end
elseif cmd == "test" then
  local files = list_example_files()
  if #files == 0 then
    print("No examples found")
  else
    local tests_dir = join_path(resolve_build_root(), "tests")
    mkdir_p(tests_dir)
    for _, file in ipairs(files) do
      local base = file:match("([^/\\]+)%.rex$") or "example"
      local c_out = join_path(tests_dir, base .. ".c")
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
  local source = read_with_includes(input)
  local lexer = Lexer.new(source)
  local tokens = lexer:tokenize()
  local parser = Parser.new(tokens)
  local ast = parser:parse_program()
  Typechecker.check(ast)
  print("OK " .. input)
elseif cmd == "check" then
  local input = args[2] or "src/main.rex"
  local source = read_with_includes(input)
  local lexer = Lexer.new(source)
  local tokens = lexer:tokenize()
  local parser = Parser.new(tokens)
  local ast = parser:parse_program()
  Typechecker.check(ast)
  print("OK " .. input)
else
  usage()
end
