-- C code generator for Rex language AST 
-- how about that rex team ? :D 
local Codegen = {}

local function indent_line(ctx, text)
  table.insert(ctx.lines, string.rep("  ", ctx.indent) .. text)
end

local function insert_lines(dest, index, lines)
  for i = #lines, 1, -1 do
    table.insert(dest, index, lines[i])
  end
end

local function c_string(text)
  local s = text
  s = s:gsub("\\", "\\\\")
  s = s:gsub("\"", "\\\"")
  s = s:gsub("\n", "\\n")
  s = s:gsub("\r", "\\r")
  s = s:gsub("\t", "\\t")
  return "\"" .. s .. "\""
end

local function type_base(type_str)
  if not type_str then
    return nil
  end
  local cleaned = type_str:gsub("&", ""):gsub("mut", ""):gsub("%s+", "")
  local base = cleaned:match("^([A-Za-z_][A-Za-z0-9_]*)")
  return base or cleaned
end

local function collect_defs(ast)
  local structs = {}
  local methods = {}
  local functions = {}
  local enums = {}

  for _, item in ipairs(ast.items) do
    if item.kind == "Struct" then
      structs[item.name] = item
    elseif item.kind == "Enum" then
      enums[item.name] = item
    elseif item.kind == "Impl" then
      methods[item.name] = methods[item.name] or {}
      for _, method in ipairs(item.methods) do
        methods[item.name][method.name] = true
      end
    elseif item.kind == "Function" then
      functions[item.name] = true
    end
  end

  return structs, methods, functions, enums
end

local function scope_get(ctx, name)
  for i = #ctx.scopes, 1, -1 do
    local v = ctx.scopes[i][name]
    if v then
      return v
    end
  end
  return nil
end

local function scope_has(ctx, name)
  for i = #ctx.scopes, 1, -1 do
    if ctx.scopes[i][name] then
      return true
    end
  end
  return false
end

local function scope_set(ctx, name, value)
  ctx.scopes[#ctx.scopes][name] = value
end

function Codegen.generate(ast, opts)
  opts = opts or {}
  local structs, methods, functions, enums = collect_defs(ast)

  local ctx = {
    lines = {},
    indent = 0,
    tmp_id = 0,
    match_id = 0,
    spawn_id = 0,
    bond_id = 0,
    spawn_helpers = {},
    spawn_used = false,
    scopes = { {} },
    defer_stack = { {} },
    bond_stack = { {} },
    active_bond = nil,
    structs = structs,
    methods = methods,
    enums = enums,
    functions = {},
    struct_ctors = {},
    method_map = {},
    imports = {},
    name_counters = {},
    current_bindings = { {} },
    builtins = {
      println = "rex_println",
      print = "rex_print",
      channel = "rex_channel",
      spawn = "rex_spawn",
      sleep = "rex_sleep",
      now_ms = "rex_now_ms",
      format = "rex_format",
      Ok = "rex_ok",
      Err = "rex_err",
      alloc = "rex_alloc",
      free = "rex_free",
      box = "rex_box",
      unbox = "rex_unbox",
      drop = "rex_drop",
      sqrt = "rex_sqrt",
      abs = "rex_abs",
    },
    module_builtins = {
      io = {
        println = "rex_println",
        print = "rex_print",
        read_file = "rex_io_read_file",
        write_file = "rex_io_write_file",
        read_line = "rex_io_read_line",
        read_lines = "rex_io_read_lines",
        write_lines = "rex_io_write_lines",
      },
      fs = {
        exists = "rex_fs_exists",
        mkdir = "rex_fs_mkdir",
        remove = "rex_fs_remove",
      },
      thread = { channel = "rex_channel", wait_all = "rex_wait_all" },
      time = {
        sleep = "rex_sleep",
        sleep_s = "rex_sleep_s",
        now_ms = "rex_now_ms",
        now_s = "rex_now_s",
        now_ns = "rex_now_ns",
        since = "rex_time_since",
      },
      fmt = { format = "rex_format" },
      mem = {
        alloc = "rex_alloc",
        free = "rex_free",
        box = "rex_box",
        unbox = "rex_unbox",
        drop = "rex_drop",
      },
      math = { sqrt = "rex_sqrt", abs = "rex_abs" },
      collections = {
        vec_new = "rex_collections_vec_new",
        vec_push = "rex_collections_vec_push",
        vec_get = "rex_collections_vec_get",
        vec_set = "rex_collections_vec_set",
        vec_len = "rex_collections_vec_len",
        vec_insert = "rex_collections_vec_insert",
        vec_pop = "rex_collections_vec_pop",
        vec_clear = "rex_collections_vec_clear",
        vec_sort = "rex_collections_vec_sort",
        vec_slice = "rex_collections_vec_slice",
        vec_from = "rex_collections_vec_from",
        map_new = "rex_collections_map_new",
        map_put = "rex_collections_map_put",
        map_get = "rex_collections_map_get",
        map_remove = "rex_collections_map_remove",
        map_has = "rex_collections_map_has",
        map_keys = "rex_collections_map_keys",
        set_new = "rex_collections_set_new",
        set_add = "rex_collections_set_add",
        set_has = "rex_collections_set_has",
        set_remove = "rex_collections_set_remove",
      },
      os = { getenv = "rex_os_getenv", cwd = "rex_os_cwd" },
      net = { tcp_connect = "rex_net_tcp_connect", udp_socket = "rex_net_udp_socket" },
      http = { get = "rex_http_get", get_status = "rex_http_get_status", get_json = "rex_http_get_json" },
      random = {
        seed = "rex_random_seed",
        int = "rex_random_int",
        float = "rex_random_float",
        bool = "rex_random_bool",
        choice = "rex_random_choice",
        shuffle = "rex_random_shuffle",
        range = "rex_random_range",
      },
      json = { encode = "rex_json_encode", encode_pretty = "rex_json_encode_pretty", decode = "rex_json_decode" },
      result = { Ok = "rex_ok", Err = "rex_err" },
      ui = {
        begin = "rex_ui_begin",
        ["end"] = "rex_ui_end",
        redraw = "rex_ui_redraw",
        clear = "rex_ui_clear",
        key_space = "rex_ui_key_space",
        key_up = "rex_ui_key_up",
        key_down = "rex_ui_key_down",
        mouse_x = "rex_ui_mouse_x",
        mouse_y = "rex_ui_mouse_y",
        mouse_down = "rex_ui_mouse_down",
        mouse_pressed = "rex_ui_mouse_pressed",
        mouse_released = "rex_ui_mouse_released",
        label = "rex_ui_label",
        text = "rex_ui_text",
        button = "rex_ui_button",
        checkbox = "rex_ui_checkbox",
        radio = "rex_ui_radio",
        textbox = "rex_ui_textbox",
        slider = "rex_ui_slider",
        progress = "rex_ui_progress",
        switch = "rex_ui_switch",
        select = "rex_ui_select",
        combo = "rex_ui_combo",
        menu = "rex_ui_menu",
        tabs = "rex_ui_tabs",
        row = "rex_ui_layout_row",
        column = "rex_ui_layout_column",
        grid = "rex_ui_layout_grid",
        newline = "rex_ui_newline",
        row_end = "rex_ui_row_end",
        clip_begin = "rex_ui_clip_begin",
        clip_end = "rex_ui_clip_end",
        spacing = "rex_ui_spacing",
        padding = "rex_ui_padding",
        scroll_begin = "rex_ui_scroll_begin",
        scroll_end = "rex_ui_scroll_end",
        enabled = "rex_ui_enabled",
        invert = "rex_ui_invert",
        titlebar_dark = "rex_ui_titlebar_dark",
        theme_dark = "rex_ui_theme_dark",
        theme_light = "rex_ui_theme_light",
        theme_custom = "rex_ui_theme_custom",
        image_load = "rex_ui_image_load",
        image_w = "rex_ui_image_w",
        image_h = "rex_ui_image_h",
        image = "rex_ui_image",
        image_region = "rex_ui_image_region",
        play_sound = "rex_ui_play_sound",
      },
    },
  }


  
  local function get_c_name(ctx, rex_name)
   
    ctx.name_counters[rex_name] = (ctx.name_counters[rex_name] or 0) + 1
    return rex_name .. "_" .. ctx.name_counters[rex_name]
  end
  
  local function scope_get_binding(ctx, rex_name)
   
    for i = #ctx.current_bindings, 1, -1 do
      local binding = ctx.current_bindings[i][rex_name]
      if binding then
        return binding
      end
    end
    return nil
  end
  
  local function scope_set_binding(ctx, rex_name, c_name, value_type)
 
    ctx.current_bindings[#ctx.current_bindings][rex_name] = {
      c_name = c_name,
      type = value_type
    }
  end

 
  local original_scope_get = scope_get
  scope_get = function(ctx, rex_name)
    local binding = scope_get_binding(ctx, rex_name)
    if binding then
      return binding.type
    end
    return original_scope_get(ctx, rex_name)
  end

 
  local original_scope_set = scope_set
  scope_set = function(ctx, rex_name, value_type)

    local binding = scope_get_binding(ctx, rex_name)
    if binding then
      binding.type = value_type
    else
     
      original_scope_set(ctx, rex_name, value_type)
    end
  end

  
  local original_scope_has = scope_has
  scope_has = function(ctx, rex_name)
    if scope_get_binding(ctx, rex_name) then
      return true
    end
    return original_scope_has(ctx, rex_name)
  end

  local function get_c_ident(ctx, rex_name)

    local binding = scope_get_binding(ctx, rex_name)
    if binding then
      return binding.c_name
    end
    return rex_name  
  end

  for name, _ in pairs(functions) do
    ctx.functions[name] = "rex_user_" .. name
  end

  for name, _ in pairs(structs) do
    ctx.struct_ctors[name] = "rex_" .. name .. "_new"
  end

  for struct_name, method_set in pairs(methods) do
    ctx.method_map[struct_name] = {}
    for method_name, _ in pairs(method_set) do
      ctx.method_map[struct_name][method_name] = "rex_" .. struct_name .. "_" .. method_name
    end
  end

  for _, item in ipairs(ast.items) do
    if item.kind == "Use" then
      local alias = item.alias or item.path[#item.path]
      local module = alias
      if item.path[1] == "rex" then
        module = item.path[2] or alias
      end
      ctx.imports[alias] = module
    end
  end

  local function find_enum_variant(enum_name, variant_name)
    local enum_def = ctx.enums[enum_name]
    if not enum_def then
      return nil
    end
    for _, v in ipairs(enum_def.variants or {}) do
      if v.name == variant_name then
        return v
      end
    end
    return nil
  end

  local function collect_spawn_captures(block)
    local used = {}
    local declared = {}

    local function mark_declared(name, scope_declared)
      scope_declared[name] = true
      declared[name] = true
    end

    local function collect_pattern(pattern, scope_declared)
      if pattern.kind == "IdentPattern" then
        mark_declared(pattern.name, scope_declared)
      elseif pattern.kind == "TuplePattern" then
        for _, name in ipairs(pattern.names) do
          mark_declared(name, scope_declared)
        end
      end
    end

    local function collect_expr(expr)
      if not expr then
        return
      end
      if expr.kind == "Identifier" then
        used[expr.name] = true
      elseif expr.kind == "Binary" then
        collect_expr(expr.left)
        collect_expr(expr.right)
      elseif expr.kind == "Unary" or expr.kind == "Deref" or expr.kind == "Try" or expr.kind == "Borrow" then
        collect_expr(expr.expr)
      elseif expr.kind == "Call" then
        if expr.callee.kind ~= "Identifier" then
          collect_expr(expr.callee)
        end
        for _, arg in ipairs(expr.args or {}) do
          collect_expr(arg)
        end
      elseif expr.kind == "Member" then
        collect_expr(expr.object)
      elseif expr.kind == "Array" then
        for _, el in ipairs(expr.elements or {}) do
          collect_expr(el)
        end
      elseif expr.kind == "Index" then
        collect_expr(expr.object)
        collect_expr(expr.index)
      elseif expr.kind == "Slice" then
        collect_expr(expr.object)
        collect_expr(expr.start)
        collect_expr(expr.finish)
      elseif expr.kind == "Generic" then
        collect_expr(expr.expr)
      end
    end

    local function collect_block(block, scope_declared)
      local local_declared = {}
      for k, v in pairs(scope_declared) do
        local_declared[k] = v
      end
      for _, stmt in ipairs(block.statements or {}) do
        if stmt.kind == "Let" then
          collect_expr(stmt.value)
          collect_pattern(stmt.pattern, local_declared)
        elseif stmt.kind == "Assign" then
          used[stmt.name] = true
          collect_expr(stmt.value)
        elseif stmt.kind == "MemberAssign" then
          collect_expr(stmt.object)
          collect_expr(stmt.value)
        elseif stmt.kind == "IndexAssign" then
          collect_expr(stmt.object)
          collect_expr(stmt.index)
          collect_expr(stmt.value)
        elseif stmt.kind == "DerefAssign" then
          used[stmt.name] = true
          collect_expr(stmt.value)
        elseif stmt.kind == "Return" then
          collect_expr(stmt.value)
        elseif stmt.kind == "ExprStmt" then
          collect_expr(stmt.expr)
        elseif stmt.kind == "If" then
          collect_expr(stmt.cond)
          collect_block(stmt.then_block, local_declared)
          if stmt.else_block then
            collect_block(stmt.else_block, local_declared)
          end
        elseif stmt.kind == "While" then
          collect_expr(stmt.cond)
          collect_block(stmt.body, local_declared)
        elseif stmt.kind == "For" then
          if stmt.range_start then
            collect_expr(stmt.range_start)
            collect_expr(stmt.range_end)
          else
            collect_expr(stmt.iter)
          end
          local inner_declared = {}
          for k, v in pairs(local_declared) do
            inner_declared[k] = v
          end
          mark_declared(stmt.name, inner_declared)
          collect_block(stmt.body, inner_declared)
        elseif stmt.kind == "Match" then
          collect_expr(stmt.expr)
          for _, arm in ipairs(stmt.arms or {}) do
            local inner_declared = {}
            for k, v in pairs(local_declared) do
              inner_declared[k] = v
            end
            if arm.binding then
              mark_declared(arm.binding, inner_declared)
            end
            collect_block(arm.body, inner_declared)
          end
        elseif stmt.kind == "Spawn" then
          collect_block(stmt.block, local_declared)
        elseif stmt.kind == "Unsafe" then
          collect_block(stmt.block, local_declared)
        elseif stmt.kind == "Defer" then
          if stmt.block then
            collect_block(stmt.block, local_declared)
          else
            collect_expr(stmt.expr)
          end
        end
      end
    end

    collect_block(block, {})
    local captures = {}
    for name, _ in pairs(used) do
      if not declared[name] and scope_has(ctx, name) then
        table.insert(captures, name)
      end
    end
    table.sort(captures)
    return captures
  end

  local emit_block

  local emit_all_defers
  local emit_expr

  local function emit_expr_raw(expr)
    if expr.kind == "Bool" then
      return expr.value and "rex_bool(1)" or "rex_bool(0)"
    elseif expr.kind == "Nil" then
      return "rex_nil()"
    elseif expr.kind == "Number" then
      return "rex_num(" .. expr.value .. ")"
    elseif expr.kind == "String" then
      return "rex_str(" .. c_string(expr.value) .. ")"
    elseif expr.kind == "Identifier" then
      return get_c_ident(ctx, expr.name)
    elseif expr.kind == "Borrow" then
      if expr.expr.kind ~= "Identifier" then
        error("borrow expects identifier")
      end
      if expr.mutable then
        return "rex_ref_mut(&" .. get_c_ident(ctx, expr.expr.name) .. ")"
      end
      return "rex_ref(&" .. get_c_ident(ctx, expr.expr.name) .. ")"
    elseif expr.kind == "Binary" then
      local left = emit_expr_raw(expr.left)
      local right = emit_expr_raw(expr.right)
      local op = expr.op
      if op == "+" then
        return "rex_add(" .. left .. ", " .. right .. ")"
      elseif op == "-" then
        return "rex_sub(" .. left .. ", " .. right .. ")"
      elseif op == "*" then
        return "rex_mul(" .. left .. ", " .. right .. ")"
      elseif op == "/" then
        return "rex_div(" .. left .. ", " .. right .. ")"
      elseif op == "%" then
        return "rex_mod(" .. left .. ", " .. right .. ")"
      elseif op == "==" then
        return "rex_eq(" .. left .. ", " .. right .. ")"
      elseif op == "!=" then
        return "rex_neq(" .. left .. ", " .. right .. ")"
      elseif op == "<" then
        return "rex_lt(" .. left .. ", " .. right .. ")"
      elseif op == "<=" then
        return "rex_lte(" .. left .. ", " .. right .. ")"
      elseif op == ">" then
        return "rex_gt(" .. left .. ", " .. right .. ")"
      elseif op == ">=" then
        return "rex_gte(" .. left .. ", " .. right .. ")"
      elseif op == "&&" then
        return "rex_and(" .. left .. ", " .. right .. ")"
      elseif op == "||" then
        return "rex_or(" .. left .. ", " .. right .. ")"
      end
      error("Unknown binary op: " .. op)
    elseif expr.kind == "Unary" then
      if expr.op == "-" then
        return "rex_neg(" .. emit_expr_raw(expr.expr) .. ")"
      elseif expr.op == "!" then
        return "rex_not(" .. emit_expr_raw(expr.expr) .. ")"
      end
    elseif expr.kind == "Deref" then
      return "rex_deref(" .. emit_expr_raw(expr.expr) .. ")"
    elseif expr.kind == "Array" then
      if #expr.elements == 0 then
        return "rex_collections_vec_new()"
      end
      local elements = {}
      for _, el in ipairs(expr.elements) do
        table.insert(elements, emit_expr_raw(el))
      end
      return "rex_collections_vec_from(" .. #elements .. ", (RexValue[]){" .. table.concat(elements, ", ") .. "})"
    elseif expr.kind == "Call" then
      local args = {}
      for _, arg in ipairs(expr.args) do
        table.insert(args, emit_expr_raw(arg))
      end
      local callee = expr.callee
      if callee.kind == "Generic" then
        callee = callee.expr
      end
      if callee.kind == "Member" then
        local obj = callee.object
        local prop = callee.property
        local obj_expr = emit_expr(obj)
        if obj.kind == "Identifier" then
          local module = ctx.imports[obj.name]
          if module then
            if module == "collections" and prop == "vec_from" then
              if #args == 0 then
                return "rex_collections_vec_new()"
              end
              return "rex_collections_vec_from(" .. #args .. ", (RexValue[]){" .. table.concat(args, ", ") .. "})"
            end
            local map = ctx.module_builtins[module]
            local func = map and map[prop] or ("rex_" .. module .. "_" .. prop)
            return func .. "(" .. table.concat(args, ", ") .. ")"
          end
          if prop == "new" then
            local ctor = ctx.struct_ctors[obj.name]
            if ctor then
              return ctor .. "(" .. table.concat(args, ", ") .. ")"
            end
          end
          if ctx.enums[obj.name] then
            local variant = find_enum_variant(obj.name, prop)
            if not variant then
              error("Unknown enum variant: " .. obj.name .. "." .. prop)
            end
            local expected = variant.types and #variant.types or 0
            if expected > 1 then
              error("Enum variant payload supports at most one value")
            end
            if #args ~= expected then
              error("Enum variant " .. obj.name .. "." .. prop .. " expects " .. expected .. " value(s)")
            end
            local payload = (#args == 1) and args[1] or "rex_nil()"
            return "rex_tag(" .. c_string(prop) .. ", " .. payload .. ")"
          end
          local vtype = scope_get(ctx, obj.name)
          if vtype == "sender" and prop == "send" then
            local call_args = { emit_expr_raw(obj) }
            for _, arg in ipairs(args) do
              table.insert(call_args, arg)
            end
            return "rex_sender_send(" .. table.concat(call_args, ", ") .. ")"
          elseif vtype == "receiver" and prop == "recv" then
            return "rex_receiver_recv(" .. emit_expr_raw(obj) .. ")"
          end
          if prop == "send" then
            local call_args = { emit_expr_raw(obj) }
            for _, arg in ipairs(args) do
              table.insert(call_args, arg)
            end
            return "rex_sender_send(" .. table.concat(call_args, ", ") .. ")"
          elseif prop == "recv" then
            return "rex_receiver_recv(" .. emit_expr_raw(obj) .. ")"
          end
          if vtype and vtype:match("^struct:") then
            local struct_name = vtype:sub(8)
            local method_map = ctx.method_map[struct_name] or {}
            local method = method_map[prop]
            if method then
              local call_args = { emit_expr_raw(obj) }
              for _, arg in ipairs(args) do
                table.insert(call_args, arg)
              end
              return method .. "(" .. table.concat(call_args, ", ") .. ")"
            end
          end
          if vtype and vtype:match("^enum:") then
            local enum_name = vtype:sub(6)
            local method_map = ctx.method_map[enum_name] or {}
            local method = method_map[prop]
            if method then
              local call_args = { emit_expr_raw(obj) }
              for _, arg in ipairs(args) do
                table.insert(call_args, arg)
              end
              return method .. "(" .. table.concat(call_args, ", ") .. ")"
            end
          end
        end
        return "(rex_panic(\"unknown member call\"), rex_nil())"
      end

      if callee.kind == "Identifier" then
        local name = callee.name
        local target = ctx.functions[name] or ctx.builtins[name] or name
        return target .. "(" .. table.concat(args, ", ") .. ")"
      end

      return "(rex_panic(\"unsupported call\"), rex_nil())"
    elseif expr.kind == "Member" then
      if expr.object.kind == "Identifier" and ctx.enums[expr.object.name] then
        local variant = find_enum_variant(expr.object.name, expr.property)
        if not variant then
          error("Unknown enum variant: " .. expr.object.name .. "." .. expr.property)
        end
        local expected = variant.types and #variant.types or 0
        if expected > 0 then
          error("Enum variant " .. expr.object.name .. "." .. expr.property .. " requires payload")
        end
        return "rex_tag(" .. c_string(expr.property) .. ", rex_nil())"
      end
      return "rex_struct_get(" .. emit_expr_raw(expr.object) .. ", " .. c_string(expr.property) .. ")"
    elseif expr.kind == "Index" then
      return "rex_collections_vec_get(" .. emit_expr_raw(expr.object) .. ", " .. emit_expr_raw(expr.index) .. ")"
    elseif expr.kind == "Slice" then
      local finish = "rex_nil()"
      if expr.finish then
        finish = emit_expr_raw(expr.finish)
      end
      return "rex_collections_vec_slice(" .. emit_expr_raw(expr.object) .. ", " .. emit_expr_raw(expr.start) .. ", " .. finish .. ")"
    elseif expr.kind == "Try" then
      return "rex_try(" .. emit_expr_raw(expr.expr) .. ")"
    elseif expr.kind == "Generic" then
      return emit_expr_raw(expr.expr)
    end
    error("Unhandled expression kind: " .. tostring(expr.kind))
  end

  local function emit_try(expr)
    local inner = emit_expr(expr.expr)
    ctx.tmp_id = ctx.tmp_id + 1
    local tmp = "__try" .. ctx.tmp_id
    indent_line(ctx, "RexValue " .. tmp .. " = " .. inner .. ";")
    indent_line(ctx, "if (rex_result_is(" .. tmp .. ", " .. c_string("Err") .. ")) {")
    ctx.indent = ctx.indent + 1
    emit_all_defers()
    indent_line(ctx, "return " .. tmp .. ";")
    ctx.indent = ctx.indent - 1
    indent_line(ctx, "}")
    indent_line(ctx, "if (rex_result_is(" .. tmp .. ", " .. c_string("Ok") .. ")) {")
    ctx.indent = ctx.indent + 1
    indent_line(ctx, tmp .. " = rex_result_value(" .. tmp .. ");")
    ctx.indent = ctx.indent - 1
    indent_line(ctx, "}")
    return tmp
  end

  emit_expr = function(expr)
    if expr.kind == "Try" then
      return emit_try(expr)
    elseif expr.kind == "Bool" then
      return expr.value and "rex_bool(1)" or "rex_bool(0)"
    elseif expr.kind == "Nil" then
      return "rex_nil()"
    elseif expr.kind == "Number" then
      return "rex_num(" .. expr.value .. ")"
    elseif expr.kind == "String" then
      return "rex_str(" .. c_string(expr.value) .. ")"
    elseif expr.kind == "Identifier" then
      return get_c_ident(ctx, expr.name)
    elseif expr.kind == "Borrow" then
      if expr.expr.kind ~= "Identifier" then
        error("borrow expects identifier")
      end
      if expr.mutable then
        return "rex_ref_mut(&" .. get_c_ident(ctx, expr.expr.name) .. ")"
      end
      return "rex_ref(&" .. get_c_ident(ctx, expr.expr.name) .. ")"
    elseif expr.kind == "Binary" then
      local left = emit_expr(expr.left)
      local right = emit_expr(expr.right)
      local op = expr.op
      if op == "+" then
        return "rex_add(" .. left .. ", " .. right .. ")"
      elseif op == "-" then
        return "rex_sub(" .. left .. ", " .. right .. ")"
      elseif op == "*" then
        return "rex_mul(" .. left .. ", " .. right .. ")"
      elseif op == "/" then
        return "rex_div(" .. left .. ", " .. right .. ")"
      elseif op == "%" then
        return "rex_mod(" .. left .. ", " .. right .. ")"
      elseif op == "==" then
        return "rex_eq(" .. left .. ", " .. right .. ")"
      elseif op == "!=" then
        return "rex_neq(" .. left .. ", " .. right .. ")"
      elseif op == "<" then
        return "rex_lt(" .. left .. ", " .. right .. ")"
      elseif op == "<=" then
        return "rex_lte(" .. left .. ", " .. right .. ")"
      elseif op == ">" then
        return "rex_gt(" .. left .. ", " .. right .. ")"
      elseif op == ">=" then
        return "rex_gte(" .. left .. ", " .. right .. ")"
      elseif op == "&&" then
        return "rex_and(" .. left .. ", " .. right .. ")"
      elseif op == "||" then
        return "rex_or(" .. left .. ", " .. right .. ")"
      end
      error("Unknown binary op: " .. op)
    elseif expr.kind == "Unary" then
      if expr.op == "-" then
        return "rex_neg(" .. emit_expr(expr.expr) .. ")"
      elseif expr.op == "!" then
        return "rex_not(" .. emit_expr(expr.expr) .. ")"
      end
    elseif expr.kind == "Deref" then
      return "rex_deref(" .. emit_expr(expr.expr) .. ")"
    elseif expr.kind == "Array" then
      if #expr.elements == 0 then
        return "rex_collections_vec_new()"
      end
      local elements = {}
      for _, el in ipairs(expr.elements) do
        table.insert(elements, emit_expr(el))
      end
      return "rex_collections_vec_from(" .. #elements .. ", (RexValue[]){" .. table.concat(elements, ", ") .. "})"
    elseif expr.kind == "Call" then
      local args = {}
      for _, arg in ipairs(expr.args) do
        table.insert(args, emit_expr(arg))
      end
      local callee = expr.callee
      if callee.kind == "Generic" then
        callee = callee.expr
      end
      if callee.kind == "Member" then
        local obj = callee.object
        local prop = callee.property
        local obj_expr = emit_expr(obj)
        if obj.kind == "Identifier" then
          local module = ctx.imports[obj.name]
          if module then
            if module == "collections" and prop == "vec_from" then
              if #args == 0 then
                return "rex_collections_vec_new()"
              end
              return "rex_collections_vec_from(" .. #args .. ", (RexValue[]){" .. table.concat(args, ", ") .. "})"
            end
            local map = ctx.module_builtins[module]
            local func = map and map[prop] or ("rex_" .. module .. "_" .. prop)
            return func .. "(" .. table.concat(args, ", ") .. ")"
          end
          if prop == "new" then
            local ctor = ctx.struct_ctors[obj.name]
            if ctor then
              return ctor .. "(" .. table.concat(args, ", ") .. ")"
            end
          end
          if ctx.enums[obj.name] then
            local variant = find_enum_variant(obj.name, prop)
            if not variant then
              error("Unknown enum variant: " .. obj.name .. "." .. prop)
            end
            local expected = variant.types and #variant.types or 0
            if expected > 1 then
              error("Enum variant payload supports at most one value")
            end
            if #args ~= expected then
              error("Enum variant " .. obj.name .. "." .. prop .. " expects " .. expected .. " value(s)")
            end
            local payload = (#args == 1) and args[1] or "rex_nil()"
            return "rex_tag(" .. c_string(prop) .. ", " .. payload .. ")"
          end
          local vtype = scope_get(ctx, obj.name)
          if vtype == "sender" and prop == "send" then
            local call_args = { obj_expr }
            for _, arg in ipairs(args) do
              table.insert(call_args, arg)
            end
            return "rex_sender_send(" .. table.concat(call_args, ", ") .. ")"
          elseif vtype == "receiver" and prop == "recv" then
            return "rex_receiver_recv(" .. obj_expr .. ")"
          end
          if prop == "send" then
            local call_args = { obj_expr }
            for _, arg in ipairs(args) do
              table.insert(call_args, arg)
            end
            return "rex_sender_send(" .. table.concat(call_args, ", ") .. ")"
          elseif prop == "recv" then
            return "rex_receiver_recv(" .. obj_expr .. ")"
          end
          if vtype and vtype:match("^struct:") then
            local struct_name = vtype:sub(8)
            local method_map = ctx.method_map[struct_name] or {}
            local method = method_map[prop]
            if method then
              local call_args = { obj_expr }
              for _, arg in ipairs(args) do
                table.insert(call_args, arg)
              end
              return method .. "(" .. table.concat(call_args, ", ") .. ")"
            end
          end
          if vtype and vtype:match("^enum:") then
            local enum_name = vtype:sub(6)
            local method_map = ctx.method_map[enum_name] or {}
            local method = method_map[prop]
            if method then
              local call_args = { obj_expr }
              for _, arg in ipairs(args) do
                table.insert(call_args, arg)
              end
              return method .. "(" .. table.concat(call_args, ", ") .. ")"
            end
          end
        end
        return "(rex_panic(\"unknown member call\"), rex_nil())"
      end

      if callee.kind == "Identifier" then
        local name = callee.name
        local target = ctx.functions[name] or ctx.builtins[name] or name
        return target .. "(" .. table.concat(args, ", ") .. ")"
      end

      return "(rex_panic(\"unsupported call\"), rex_nil())"
    elseif expr.kind == "Member" then
      if expr.object.kind == "Identifier" and ctx.enums[expr.object.name] then
        local variant = find_enum_variant(expr.object.name, expr.property)
        if not variant then
          error("Unknown enum variant: " .. expr.object.name .. "." .. expr.property)
        end
        local expected = variant.types and #variant.types or 0
        if expected > 0 then
          error("Enum variant " .. expr.object.name .. "." .. expr.property .. " requires payload")
        end
        return "rex_tag(" .. c_string(expr.property) .. ", rex_nil())"
      end
      return "rex_struct_get(" .. emit_expr(expr.object) .. ", " .. c_string(expr.property) .. ")"
    elseif expr.kind == "Index" then
      return "rex_collections_vec_get(" .. emit_expr(expr.object) .. ", " .. emit_expr(expr.index) .. ")"
    elseif expr.kind == "Slice" then
      local finish = "rex_nil()"
      if expr.finish then
        finish = emit_expr(expr.finish)
      end
      return "rex_collections_vec_slice(" .. emit_expr(expr.object) .. ", " .. emit_expr(expr.start) .. ", " .. finish .. ")"
    elseif expr.kind == "Generic" then
      return emit_expr(expr.expr)
    end
    error("Unhandled expression kind: " .. tostring(expr.kind))
  end

  local function emit_defer(node)
    if node.block then
      emit_block(node.block, true)
    else
      indent_line(ctx, emit_expr_raw(node.expr) .. ";")
    end
  end

  local function emit_defer_list(list)
    for i = #list, 1, -1 do
      emit_defer(list[i])
    end
  end

  emit_all_defers = function()
    for i = #ctx.defer_stack, 1, -1 do
      emit_defer_list(ctx.defer_stack[i])
    end
  end

  emit_block = function(block, new_scope, prelude)
    if new_scope then
      table.insert(ctx.scopes, {})
      table.insert(ctx.defer_stack, {})
      table.insert(ctx.current_bindings, {})
      if prelude then
        prelude()
      end
    elseif prelude then
      prelude()
    end
    for _, stmt in ipairs(block.statements) do
      ctx.emit_stmt(stmt)
    end
    if new_scope then
      emit_defer_list(ctx.defer_stack[#ctx.defer_stack])
      table.remove(ctx.defer_stack)
      table.remove(ctx.scopes)
      table.remove(ctx.current_bindings)
    end
  end

  local function emit_spawn_helper(captures, block)
    ctx.spawn_id = ctx.spawn_id + 1
    local id = ctx.spawn_id
    local ctx_type = "__RexSpawnCtx" .. id
    local fn_name = "__rex_spawn_fn_" .. id

    local saved_lines = ctx.lines
    local saved_indent = ctx.indent
    ctx.lines = {}
    ctx.indent = 0

    if #captures > 0 then
      indent_line(ctx, "typedef struct " .. ctx_type .. " {")
      ctx.indent = ctx.indent + 1
      for _, name in ipairs(captures) do
        indent_line(ctx, "RexValue " .. name .. ";")
      end
      ctx.indent = ctx.indent - 1
      indent_line(ctx, "} " .. ctx_type .. ";")
    end

    indent_line(ctx, "static void " .. fn_name .. "(void* __ctx) {")
    ctx.indent = ctx.indent + 1
    if #captures > 0 then
      indent_line(ctx, ctx_type .. "* __rex_ctx = (" .. ctx_type .. "*)__ctx;")
      for _, name in ipairs(captures) do
        indent_line(ctx, "RexValue " .. name .. " = __rex_ctx->" .. name .. ";")
      end
    else
      indent_line(ctx, "(void)__ctx;")
    end
    if #captures > 0 then
      indent_line(ctx, "free(__rex_ctx);")
    end
    emit_block(block, true, function()
      for _, name in ipairs(captures) do
        scope_set_binding(ctx, name, name, scope_get(ctx, name) or "unknown")
      end
    end)
    ctx.indent = ctx.indent - 1
    indent_line(ctx, "}")

    local helper_lines = ctx.lines
    ctx.lines = saved_lines
    ctx.indent = saved_indent
    table.insert(ctx.spawn_helpers, helper_lines)
    return fn_name, ctx_type
  end

  local function is_channel_call(expr)
    if expr.kind ~= "Call" then
      return false
    end
    local callee = expr.callee
    if callee.kind == "Generic" then
      callee = callee.expr
    end
    if callee.kind == "Identifier" then
      return callee.name == "channel"
    end
    if callee.kind == "Member" and callee.object.kind == "Identifier" then
      local module = ctx.imports[callee.object.name]
      return module == "thread" and callee.property == "channel"
    end
    return false
  end

  local function infer_enum_name(expr)
    if not expr then
      return nil
    end
    if expr.kind == "Member" and expr.object.kind == "Identifier" then
      if ctx.enums[expr.object.name] then
        return expr.object.name
      end
    end
    if expr.kind == "Call" then
      local callee = expr.callee
      if callee.kind == "Generic" then
        callee = callee.expr
      end
      if callee.kind == "Member" and callee.object.kind == "Identifier" then
        if ctx.enums[callee.object.name] then
          return callee.object.name
        end
      end
    end
    return nil
  end

  local function infer_struct_name(expr)
    if not expr then
      return nil
    end
    if expr.kind == "Call" then
      local callee = expr.callee
      if callee.kind == "Generic" then
        callee = callee.expr
      end
      if callee.kind == "Member" and callee.object.kind == "Identifier" then
        local struct_name = callee.object.name
        if callee.property == "new" and ctx.structs[struct_name] then
          return struct_name
        end
      end
    end
    return nil
  end

  local function emit_stmt(stmt)
    if stmt.kind == "Let" then
      local value = emit_expr(stmt.value)
      if stmt.pattern.kind == "TuplePattern" then
        ctx.tmp_id = ctx.tmp_id + 1
        local tmp = "__tmp" .. ctx.tmp_id
        indent_line(ctx, "RexValue " .. tmp .. " = " .. value .. ";")
        for i, name in ipairs(stmt.pattern.names) do
        
          if ctx.current_bindings[#ctx.current_bindings][name] then
            error("variable '" .. name .. "' already defined in this scope")
          end
          local c_name = get_c_name(ctx, name)
          indent_line(ctx, "RexValue " .. c_name .. " = rex_tuple_get(" .. tmp .. ", " .. (i - 1) .. ");")
          scope_set_binding(ctx, name, c_name, "unknown")
        end
        if is_channel_call(stmt.value) and #stmt.pattern.names >= 2 then
          scope_set_binding(ctx, stmt.pattern.names[1], get_c_ident(ctx, stmt.pattern.names[1]), "sender")
          scope_set_binding(ctx, stmt.pattern.names[2], get_c_ident(ctx, stmt.pattern.names[2]), "receiver")
        end
      else
     
        if ctx.current_bindings[#ctx.current_bindings][stmt.pattern.name] then
          error("variable '" .. stmt.pattern.name .. "' already defined in this scope")
        end
        local c_name = get_c_name(ctx, stmt.pattern.name)
        indent_line(ctx, "RexValue " .. c_name .. " = " .. value .. ";")
        local base = type_base(stmt.type)
        local type_annotation = "unknown"
        if base and ctx.structs[base] then
          type_annotation = "struct:" .. base
        elseif base and ctx.enums[base] then
          type_annotation = "enum:" .. base
        else
          local inferred_struct = infer_struct_name(stmt.value)
          if inferred_struct then
            type_annotation = "struct:" .. inferred_struct
          else
            local inferred = infer_enum_name(stmt.value)
            if inferred then
              type_annotation = "enum:" .. inferred
            end
          end
        end
        scope_set_binding(ctx, stmt.pattern.name, c_name, type_annotation)
      end
    elseif stmt.kind == "Defer" then
      table.insert(ctx.defer_stack[#ctx.defer_stack], stmt)
    elseif stmt.kind == "WithinBlock" then
   
      if stmt.block then
        local start_time_var = "__temporal_start_" .. ctx.tmp_id
        ctx.tmp_id = ctx.tmp_id + 1
        indent_line(ctx, "uint64_t " .. start_time_var .. " = rex_temporal_now_ms();")
        indent_line(ctx, "{")
        ctx.indent = ctx.indent + 1
        emit_block(stmt.block, true, function()
          indent_line(ctx, "// within block: " .. tostring(stmt.duration) .. "ms")
        end)
        ctx.indent = ctx.indent - 1
        indent_line(ctx, "}")
        indent_line(ctx, "// end temporal scope")
      end
    elseif stmt.kind == "DuringBlock" then
    
      if stmt.block then
        indent_line(ctx, "{ // during " .. stmt.condition)
        ctx.indent = ctx.indent + 1
        emit_block(stmt.block, true)
        ctx.indent = ctx.indent - 1
        indent_line(ctx, "}")
      end
    elseif stmt.kind == "DebugOwnership" then
      
      indent_line(ctx, "rex_ownership_debug_enable(); // Enable ownership debug mode")
    
      if stmt.rules and #stmt.rules > 0 then
        for _, rule in ipairs(stmt.rules) do
          if rule.type == "trace" and rule.variable then
            indent_line(ctx, "rex_ownership_trace(\"" .. rule.variable .. "\", \"traced\");")
          elseif rule.type == "check" and rule.variable then
            indent_line(ctx, "rex_ownership_check(\"" .. rule.variable .. "\");")
          end
        end
      end
    elseif stmt.kind == "Bond" then
      -- bond x = value;
      -- Check for shadowing in same scope
      if ctx.current_bindings[#ctx.current_bindings][stmt.name] then
        error("bond '" .. stmt.name .. "' already defined in this scope")
      end
      ctx.bond_id = ctx.bond_id + 1
      local bid = ctx.bond_id
      local value = emit_expr(stmt.value)
      local c_name = get_c_name(ctx, stmt.name)
      indent_line(ctx, "RexValue " .. c_name .. " = " .. value .. ";")
      
      scope_set_binding(ctx, stmt.name, c_name, "bond:" .. bid)
      table.insert(ctx.bond_stack[#ctx.bond_stack], bid)
      ctx.active_bond = bid
    elseif stmt.kind == "Commit" then
   
      if ctx.active_bond then
        indent_line(ctx, "// bond " .. ctx.active_bond .. " committed")
        table.remove(ctx.bond_stack[#ctx.bond_stack])
        ctx.active_bond = nil
      end
    elseif stmt.kind == "Rollback" then
      --  undo all changes in bond
      if ctx.active_bond then
        indent_line(ctx, "// bond " .. ctx.active_bond .. " rolled back")
        table.remove(ctx.bond_stack[#ctx.bond_stack])
        ctx.active_bond = nil
      end
    elseif stmt.kind == "Return" then
      emit_all_defers()
      if stmt.value then
        indent_line(ctx, "return " .. emit_expr(stmt.value) .. ";")
      else
        indent_line(ctx, "return rex_nil();")
      end
    elseif stmt.kind == "ExprStmt" then
      indent_line(ctx, emit_expr(stmt.expr) .. ";")
    elseif stmt.kind == "Assign" then
      indent_line(ctx, get_c_ident(ctx, stmt.name) .. " = " .. emit_expr(stmt.value) .. ";")
    elseif stmt.kind == "MemberAssign" then
      indent_line(ctx, "rex_struct_set(" .. emit_expr(stmt.object) .. ", " .. c_string(stmt.property) .. ", " .. emit_expr(stmt.value) .. ");")
    elseif stmt.kind == "IndexAssign" then
      indent_line(ctx, "rex_collections_vec_set(" .. emit_expr(stmt.object) .. ", " .. emit_expr(stmt.index) .. ", " .. emit_expr(stmt.value) .. ");")
    elseif stmt.kind == "DerefAssign" then
      indent_line(ctx, "rex_deref_assign(" .. get_c_ident(ctx, stmt.name) .. ", " .. emit_expr(stmt.value) .. ");")
    elseif stmt.kind == "Unsafe" then
      indent_line(ctx, "{")
      ctx.indent = ctx.indent + 1
      emit_block(stmt.block, true)
      ctx.indent = ctx.indent - 1
      indent_line(ctx, "}")
    elseif stmt.kind == "Spawn" then
      ctx.spawn_used = true
      local captures = collect_spawn_captures(stmt.block)
      local fn_name, ctx_type = emit_spawn_helper(captures, stmt.block)
      if #captures == 0 then
        indent_line(ctx, "rex_spawn(" .. fn_name .. ", NULL);")
      else
        indent_line(ctx, "{")
        ctx.indent = ctx.indent + 1
        indent_line(ctx, ctx_type .. "* __rex_ctx = (" .. ctx_type .. "*)malloc(sizeof(" .. ctx_type .. "));")
        indent_line(ctx, "if (!__rex_ctx) { rex_panic(\"spawn out of memory\"); }")
        for _, name in ipairs(captures) do
          indent_line(ctx, "__rex_ctx->" .. name .. " = " .. get_c_ident(ctx, name) .. ";")
        end
        indent_line(ctx, "rex_spawn(" .. fn_name .. ", __rex_ctx);")
        ctx.indent = ctx.indent - 1
        indent_line(ctx, "}")
      end
    elseif stmt.kind == "If" then
      indent_line(ctx, "if (rex_is_truthy(" .. emit_expr(stmt.cond) .. ")) {")
      ctx.indent = ctx.indent + 1
      emit_block(stmt.then_block, true)
      ctx.indent = ctx.indent - 1
      if stmt.else_block then
        indent_line(ctx, "} else {")
        ctx.indent = ctx.indent + 1
        emit_block(stmt.else_block, true)
        ctx.indent = ctx.indent - 1
        indent_line(ctx, "}")
      else
        indent_line(ctx, "}")
      end
    elseif stmt.kind == "For" then
      ctx.tmp_id = ctx.tmp_id + 1
      local id = ctx.tmp_id
     
      table.insert(ctx.current_bindings, {})
      local loop_var = get_c_name(ctx, stmt.name)
      table.remove(ctx.current_bindings)
      
      if stmt.range_start then
        local start_var = "__start" .. id
        local end_var = "__end" .. id
        indent_line(ctx, "RexValue " .. start_var .. " = " .. emit_expr(stmt.range_start) .. ";")
        indent_line(ctx, "RexValue " .. end_var .. " = " .. emit_expr(stmt.range_end) .. ";")
        indent_line(ctx, "for (RexValue " .. loop_var .. " = " .. start_var .. "; rex_is_truthy(rex_lt(" .. loop_var .. ", " .. end_var .. ")); " .. loop_var .. " = rex_add(" .. loop_var .. ", rex_num(1))) {")
        ctx.indent = ctx.indent + 1
        emit_block(stmt.body, true, function()
          scope_set_binding(ctx, stmt.name, loop_var, "unknown")
        end)
        ctx.indent = ctx.indent - 1
        indent_line(ctx, "}")
      else
        local iter_var = "__iter" .. id
        local len_var = "__len" .. id
        local idx_var = "__idx" .. id
        indent_line(ctx, "RexValue " .. iter_var .. " = " .. emit_expr(stmt.iter) .. ";")
        indent_line(ctx, "RexValue " .. len_var .. " = rex_collections_vec_len(" .. iter_var .. ");")
        indent_line(ctx, "for (RexValue " .. idx_var .. " = rex_num(0); rex_is_truthy(rex_lt(" .. idx_var .. ", " .. len_var .. ")); " .. idx_var .. " = rex_add(" .. idx_var .. ", rex_num(1))) {")
        ctx.indent = ctx.indent + 1
        indent_line(ctx, "RexValue " .. loop_var .. " = rex_collections_vec_get(" .. iter_var .. ", " .. idx_var .. ");")
        emit_block(stmt.body, true, function()
          scope_set_binding(ctx, stmt.name, loop_var, "unknown")
        end)
        ctx.indent = ctx.indent - 1
        indent_line(ctx, "}")
      end
    elseif stmt.kind == "While" then
      indent_line(ctx, "while (rex_is_truthy(" .. emit_expr(stmt.cond) .. ")) {")
      ctx.indent = ctx.indent + 1
      emit_block(stmt.body, true)
      ctx.indent = ctx.indent - 1
      indent_line(ctx, "}")
    elseif stmt.kind == "Break" then
      emit_defer_list(ctx.defer_stack[#ctx.defer_stack])
      indent_line(ctx, "break;")
    elseif stmt.kind == "Continue" then
      emit_defer_list(ctx.defer_stack[#ctx.defer_stack])
      indent_line(ctx, "continue;")
    elseif stmt.kind == "Match" then
      ctx.match_id = ctx.match_id + 1
      local tmp = "__match" .. ctx.match_id
      indent_line(ctx, "{")
      ctx.indent = ctx.indent + 1
      indent_line(ctx, "RexValue " .. tmp .. " = " .. emit_expr(stmt.expr) .. ";")
      for i, arm in ipairs(stmt.arms) do
        local cond = "rex_tag_is(" .. tmp .. ", " .. c_string(arm.tag) .. ")"
        if i == 1 then
          indent_line(ctx, "if (" .. cond .. ") {")
        else
          indent_line(ctx, "else if (" .. cond .. ") {")
        end
        ctx.indent = ctx.indent + 1
        if arm.binding then
          local c_name = get_c_name(ctx, arm.binding)
          indent_line(ctx, "RexValue " .. c_name .. " = rex_tag_value(" .. tmp .. ");")
          scope_set_binding(ctx, arm.binding, c_name, "unknown")
        end
        if arm.body and arm.body.statements and #arm.body.statements > 0 then
          local last_stmt = arm.body.statements[#arm.body.statements]
          if last_stmt.kind == "ExprStmt" then
            for j = 1, #arm.body.statements - 1 do
              ctx.emit_stmt(arm.body.statements[j])
            end
            local expr = last_stmt.expr
            local is_void_call = false
            if expr.kind == "Call" then
              local callee = expr.callee
              if callee.kind == "Generic" then
                callee = callee.expr
              end
              if callee.kind == "Identifier" then
                if callee.name == "print" or callee.name == "println" then
                  is_void_call = true
                end
              elseif callee.kind == "Member" and callee.object.kind == "Identifier" then
                local module = ctx.imports[callee.object.name]
                if module == "io" and (callee.property == "print" or callee.property == "println") then
                  is_void_call = true
                end
              end
            end
            if is_void_call then
              indent_line(ctx, emit_expr(last_stmt.expr) .. ";")
            else
              indent_line(ctx, "return " .. emit_expr(last_stmt.expr) .. ";")
            end
          else
            emit_block(arm.body, true)
          end
        else
          emit_block(arm.body, true)
        end
        ctx.indent = ctx.indent - 1
        indent_line(ctx, "}")
      end
      indent_line(ctx, "else {")
      ctx.indent = ctx.indent + 1
      indent_line(ctx, "rex_panic(\"non-exhaustive match\");")
      ctx.indent = ctx.indent - 1
      indent_line(ctx, "}")
      ctx.indent = ctx.indent - 1
      indent_line(ctx, "}")

    else
      error("Unhandled statement kind: " .. tostring(stmt.kind))
    end
  end

  ctx.emit_stmt = emit_stmt

  indent_line(ctx, "#include <stdint.h>")
  indent_line(ctx, "#include <stdlib.h>")
  indent_line(ctx, "#include <string.h>")
  indent_line(ctx, "#include \"rex_rt.h\"")
  indent_line(ctx, "")

  for struct_name, def in pairs(ctx.structs) do
    local ctor = ctx.struct_ctors[struct_name]
    local params = {}
    for _, field in ipairs(def.fields) do
      table.insert(params, "RexValue " .. field.name)
    end
    indent_line(ctx, "static RexValue " .. ctor .. "(" .. table.concat(params, ", ") .. ");")
  end

  local function param_list(params, add_self)
    local out = {}
    if add_self then
      table.insert(out, "RexValue self")
    end
    for _, p in ipairs(params or {}) do
      if not (add_self and p.name == "self") then
        table.insert(out, "RexValue " .. p.name)
      end
    end
    return out
  end

  for _, item in ipairs(ast.items) do
    if item.kind == "Impl" then
      for _, method in ipairs(item.methods) do
        local c_name = ctx.method_map[item.name][method.name]
        indent_line(ctx, "static RexValue " .. c_name .. "(" .. table.concat(param_list(method.params, true), ", ") .. ");")
      end
    end
  end

  for _, item in ipairs(ast.items) do
    if item.kind == "Function" then
      local c_name = ctx.functions[item.name]
      if c_name then
        indent_line(ctx, "static RexValue " .. c_name .. "(" .. table.concat(param_list(item.params, false), ", ") .. ");")
      end
    end
  end

  local has_top_level = false
  for _, item in ipairs(ast.items) do
    if item.kind ~= "Use"
      and item.kind ~= "Struct"
      and item.kind ~= "Enum"
      and item.kind ~= "TypeAlias"
      and item.kind ~= "Impl"
      and item.kind ~= "Function"
    then
      has_top_level = true
      break
    end
  end
  if has_top_level then
    indent_line(ctx, "static RexValue rex_init(void);")
  end

  local spawn_helper_index = #ctx.lines + 1
  indent_line(ctx, "")

  for struct_name, def in pairs(ctx.structs) do
    local field_names = {}
    for _, field in ipairs(def.fields) do
      table.insert(field_names, c_string(field.name))
    end
    indent_line(ctx, "static const char* rex_fields_" .. struct_name .. "[] = {" .. table.concat(field_names, ", ") .. "};")
    local ctor = ctx.struct_ctors[struct_name]
    local params = {}
    local values = {}
    for _, field in ipairs(def.fields) do
      table.insert(params, "RexValue " .. field.name)
      table.insert(values, field.name)
    end
    indent_line(ctx, "static RexValue " .. ctor .. "(" .. table.concat(params, ", ") .. ") {")
    ctx.indent = ctx.indent + 1
    indent_line(ctx, "RexValue values[] = {" .. table.concat(values, ", ") .. "};")
    indent_line(ctx, "return rex_struct_new(" .. c_string(struct_name) .. ", rex_fields_" .. struct_name .. ", values, " .. #def.fields .. ");")
    ctx.indent = ctx.indent - 1
    indent_line(ctx, "}")
    indent_line(ctx, "")
  end

  for _, item in ipairs(ast.items) do
    if item.kind == "Impl" then
      for _, method in ipairs(item.methods) do
        local c_name = ctx.method_map[item.name][method.name]
        local params = param_list(method.params, true)
        indent_line(ctx, "static RexValue " .. c_name .. "(" .. table.concat(params, ", ") .. ") {")
        ctx.indent = ctx.indent + 1
        table.insert(ctx.scopes, {})
        table.insert(ctx.current_bindings, {})
        if ctx.structs[item.name] then
          scope_set_binding(ctx, "self", "self", "struct:" .. item.name)
        elseif ctx.enums[item.name] then
          scope_set_binding(ctx, "self", "self", "enum:" .. item.name)
        else
          scope_set_binding(ctx, "self", "self", "unknown")
        end
        for _, p in ipairs(method.params) do
          if p.name ~= "self" then
            scope_set_binding(ctx, p.name, p.name, "unknown")
          end
        end
        emit_block(method.body, true)
        indent_line(ctx, "return rex_nil();")
        table.remove(ctx.scopes)
        table.remove(ctx.current_bindings)
        ctx.indent = ctx.indent - 1
        indent_line(ctx, "}")
        indent_line(ctx, "")
      end
    end
  end

  for _, item in ipairs(ast.items) do
    if item.kind == "Function" then
      local c_name = ctx.functions[item.name]
      if not c_name then
        goto skip_function
      end
      local params = param_list(item.params, false)
      indent_line(ctx, "static RexValue " .. c_name .. "(" .. table.concat(params, ", ") .. ") {")
      ctx.indent = ctx.indent + 1
      table.insert(ctx.scopes, {})
      table.insert(ctx.current_bindings, {})
      for _, p in ipairs(item.params) do
        local base = type_base(p.type)
        local type_annotation = "unknown"
        if base and ctx.structs[base] then
          type_annotation = "struct:" .. base
        elseif base and ctx.enums[base] then
          type_annotation = "enum:" .. base
        end
        scope_set_binding(ctx, p.name, p.name, type_annotation)
      end
      emit_block(item.body, true)
      indent_line(ctx, "return rex_nil();")
      table.remove(ctx.scopes)
      table.remove(ctx.current_bindings)
      ctx.indent = ctx.indent - 1
      indent_line(ctx, "}")
      indent_line(ctx, "")
      ::skip_function::
    end
  end

  if has_top_level then
    indent_line(ctx, "static RexValue rex_init(void) {")
    ctx.indent = ctx.indent + 1
    emit_block({ statements = (function()
      local items = {}
      for _, item in ipairs(ast.items) do
        if item.kind ~= "Use"
          and item.kind ~= "Struct"
          and item.kind ~= "Enum"
          and item.kind ~= "TypeAlias"
          and item.kind ~= "Impl"
          and item.kind ~= "Function"
        then
          table.insert(items, item)
        end
      end
      return items
    end)() }, true)
    indent_line(ctx, "return rex_nil();")
    ctx.indent = ctx.indent - 1
    indent_line(ctx, "}")
    indent_line(ctx, "")
  end

  if opts.emit_entry ~= false then
    indent_line(ctx, "int main(void) {")
    ctx.indent = ctx.indent + 1
    if has_top_level then
      indent_line(ctx, "rex_init();")
    end
    if ctx.functions["main"] then
      indent_line(ctx, ctx.functions["main"] .. "();")
    end
    if ctx.spawn_used then
      indent_line(ctx, "rex_wait_all();")
    end
    indent_line(ctx, "return 0;")
    ctx.indent = ctx.indent - 1
    indent_line(ctx, "}")
  end

  if #ctx.spawn_helpers > 0 then
    local insert = {}
    for _, helper in ipairs(ctx.spawn_helpers) do
      for _, line in ipairs(helper) do
        table.insert(insert, line)
      end
      table.insert(insert, "")
    end
    insert_lines(ctx.lines, spawn_helper_index, insert)
  end

  return table.concat(ctx.lines, "\n")
end

return Codegen
