-- C code generator for Rex language AST 

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
    bonds = {},
    active_bond_stack = {},
    active_bond = nil,
    structs = structs,
    methods = methods,
    enums = enums,
    functions = {},
    struct_ctors = {},
    method_map = {},
    imports = {},
    external_modules = opts.external_modules or {},
    name_counters = {},
    current_bindings = { {} },
    block_tail_stack = {},
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
        is_dir = "rex_fs_is_dir",
        read_dir = "rex_fs_read_dir",
        copy = "rex_fs_copy",
        move = "rex_fs_move",
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
      fmt = {
        format = "rex_format",
        pad_left = "rex_fmt_pad_left",
        pad_right = "rex_fmt_pad_right",
        join = "rex_fmt_join",
        fixed = "rex_fmt_fixed",
        hex = "rex_fmt_hex",
        bin = "rex_fmt_bin",
      },
      text = {
        initials = "rex_text_initials",
        lower_ascii = "rex_text_lower_ascii",
        pad_left = "rex_text_pad_left",
        pad_right = "rex_text_pad_right",
        trim = "rex_text_trim",
        trim_start = "rex_text_trim_start",
        trim_end = "rex_text_trim_end",
        split_words = "rex_text_split_words",
        starts_with = "rex_text_starts_with",
        ends_with = "rex_text_ends_with",
        contains = "rex_text_contains",
        replace = "rex_text_replace",
        ["repeat"] = "rex_text_repeat",
        lines = "rex_text_lines",
        upper_ascii = "rex_text_upper_ascii",
        is_empty = "rex_text_is_empty",
        len_bytes = "rex_text_len_bytes",
        index_of = "rex_text_index_of",
        last_index_of = "rex_text_last_index_of",
      },
      mem = {
        alloc = "rex_alloc",
        free = "rex_free",
        box = "rex_box",
        unbox = "rex_unbox",
        drop = "rex_drop",
      },
      math = { sqrt = "rex_sqrt", abs = "rex_abs", eval = "rex_math_eval" },
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
        vec_find = "rex_collections_vec_find",
        vec_any = "rex_collections_vec_any",
        vec_all = "rex_collections_vec_all",
        vec_contains = "rex_collections_vec_contains",
        vec_remove_at = "rex_collections_vec_remove_at",
        vec_reverse = "rex_collections_vec_reverse",
        vec_first = "rex_collections_vec_first",
        vec_last = "rex_collections_vec_last",
        vec_join = "rex_collections_vec_join",
        map_new = "rex_collections_map_new",
        map_put = "rex_collections_map_put",
        map_get = "rex_collections_map_get",
        map_remove = "rex_collections_map_remove",
        map_has = "rex_collections_map_has",
        map_keys = "rex_collections_map_keys",
        map_values = "rex_collections_map_values",
        map_items = "rex_collections_map_items",
        map_len = "rex_collections_map_len",
        set_new = "rex_collections_set_new",
        set_add = "rex_collections_set_add",
        set_has = "rex_collections_set_has",
        set_remove = "rex_collections_set_remove",
        set_len = "rex_collections_set_len",
      },
      os = {
        getenv = "rex_os_getenv",
        cwd = "rex_os_cwd",
        platform = "rex_os_platform",
        args = "rex_os_args",
        home = "rex_os_home",
        temp_dir = "rex_os_temp_dir",
      },
      path = {
        join = "rex_path_join",
        basename = "rex_path_basename",
        dirname = "rex_path_dirname",
        ext = "rex_path_ext",
        stem = "rex_path_stem",
        is_abs = "rex_path_is_abs",
      },
      audio = {
        play = "rex_audio_play",
        play_loop = "rex_audio_play_loop",
        stop = "rex_audio_stop",
        supports = "rex_audio_supports",
        set_volume = "rex_audio_set_volume",
        volume = "rex_audio_get_volume",
      },
      log = {
        debug = "rex_log_debug",
        info = "rex_log_info",
        warn = "rex_log_warn",
        error = "rex_log_error",
        set_level = "rex_log_set_level",
        level = "rex_log_get_level",
      },
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
      result = {
        Ok = "rex_ok",
        Err = "rex_err",
        is_ok = "rex_result_is_ok",
        is_err = "rex_result_is_err",
        unwrap_or = "rex_result_unwrap_or",
        unwrap_or_else = "rex_result_unwrap_or_else",
        ok_or = "rex_result_ok_or",
        expect = "rex_result_expect",
      },
      ui = {
        begin = "rex_ui_begin",
        ["end"] = "rex_ui_end",
        redraw = "rex_ui_redraw",
        clear = "rex_ui_clear",
        key_space = "rex_ui_key_space",
        key_up = "rex_ui_key_up",
        key_down = "rex_ui_key_down",
        key_code = "rex_ui_key_code",
        key_is_down = "rex_ui_key_is_down",
        key_pressed = "rex_ui_key_pressed",
        key_released = "rex_ui_key_released",
        mouse_x = "rex_ui_mouse_x",
        mouse_y = "rex_ui_mouse_y",
        mouse_down = "rex_ui_mouse_down",
        mouse_pressed = "rex_ui_mouse_pressed",
        mouse_released = "rex_ui_mouse_released",
        mouse_is_down = "rex_ui_mouse_is_down",
        mouse_pressed_btn = "rex_ui_mouse_pressed_btn",
        mouse_released_btn = "rex_ui_mouse_released_btn",
        scroll_x = "rex_ui_scroll_x",
        scroll_y = "rex_ui_scroll_y",
        label = "rex_ui_label",
        text = "rex_ui_text",
        rect = "rex_ui_rect",
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
        image_rot = "rex_ui_image_rot",
        image_region = "rex_ui_image_region",
        play_sound = "rex_ui_play_sound",
      },
    },
  }
  local resolve_package_member_export


  
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

  local numeric_types = {
    num = true,
    f32 = true,
    f64 = true,
    i8 = true,
    i16 = true,
    i32 = true,
    i64 = true,
    u8 = true,
    u16 = true,
    u32 = true,
    u64 = true,
  }

  local function normalize_codegen_type(t)
    if not t then
      return "unknown"
    end
    if numeric_types[t] then
      return "num"
    end
    if t == "string" then
      return "str"
    end
    return t
  end

  local infer_expr_type

  local function emit_binary_fallback(op, left, right)
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
  end

  local function emit_binary_typed(op, left, right, left_type, right_type)
    if left_type == "num" and right_type == "num" then
      if op == "+" then
        return "rex_num((" .. left .. ").as.num + (" .. right .. ").as.num)"
      elseif op == "-" then
        return "rex_num((" .. left .. ").as.num - (" .. right .. ").as.num)"
      elseif op == "*" then
        return "rex_num((" .. left .. ").as.num * (" .. right .. ").as.num)"
      elseif op == "/" then
        return "rex_num((" .. left .. ").as.num / (" .. right .. ").as.num)"
      elseif op == "%" then
        return "rex_num(fmod((" .. left .. ").as.num, (" .. right .. ").as.num))"
      elseif op == "==" then
        return "rex_bool((" .. left .. ").as.num == (" .. right .. ").as.num)"
      elseif op == "!=" then
        return "rex_bool((" .. left .. ").as.num != (" .. right .. ").as.num)"
      elseif op == "<" then
        return "rex_bool((" .. left .. ").as.num < (" .. right .. ").as.num)"
      elseif op == "<=" then
        return "rex_bool((" .. left .. ").as.num <= (" .. right .. ").as.num)"
      elseif op == ">" then
        return "rex_bool((" .. left .. ").as.num > (" .. right .. ").as.num)"
      elseif op == ">=" then
        return "rex_bool((" .. left .. ").as.num >= (" .. right .. ").as.num)"
      end
    end
    if left_type == "bool" and right_type == "bool" then
      if op == "&&" then
        return "rex_bool((" .. left .. ").as.boolean && (" .. right .. ").as.boolean)"
      elseif op == "||" then
        return "rex_bool((" .. left .. ").as.boolean || (" .. right .. ").as.boolean)"
      elseif op == "==" then
        return "rex_bool((" .. left .. ").as.boolean == (" .. right .. ").as.boolean)"
      elseif op == "!=" then
        return "rex_bool((" .. left .. ").as.boolean != (" .. right .. ").as.boolean)"
      end
    end
    return emit_binary_fallback(op, left, right)
  end

  infer_expr_type = function(expr)
    if not expr then
      return "unknown"
    end
    if expr.kind == "Number" then
      return "num"
    elseif expr.kind == "Bool" then
      return "bool"
    elseif expr.kind == "String" then
      return "str"
    elseif expr.kind == "Identifier" then
      return normalize_codegen_type(scope_get(ctx, expr.name))
    elseif expr.kind == "Borrow" then
      return "unknown"
    elseif expr.kind == "Unary" then
      if expr.op == "-" and infer_expr_type(expr.expr) == "num" then
        return "num"
      elseif expr.op == "!" then
        return "bool"
      end
      return "unknown"
    elseif expr.kind == "Binary" then
      local lt = infer_expr_type(expr.left)
      local rt = infer_expr_type(expr.right)
      if expr.op == "+" then
        if lt == "num" and rt == "num" then
          return "num"
        end
        if lt == "str" or rt == "str" then
          return "str"
        end
      elseif expr.op == "-" or expr.op == "*" or expr.op == "/" or expr.op == "%" then
        if lt == "num" and rt == "num" then
          return "num"
        end
      elseif expr.op == "==" or expr.op == "!=" or expr.op == "<" or expr.op == "<=" or expr.op == ">" or expr.op == ">=" then
        return "bool"
      elseif expr.op == "&&" or expr.op == "||" then
        return "bool"
      end
      return "unknown"
    end
    return "unknown"
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
      else
        module = item.path[1] or alias
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
      elseif expr.kind == "StructLit" then
        for _, f in ipairs(expr.fields or {}) do
          collect_expr(f.value)
        end
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

  local function can_emit_tail_return()
    local frame = ctx.block_tail_stack[#ctx.block_tail_stack]
    if not frame then
      return false
    end
    return frame.allow_tail_return and frame.index == frame.count
  end

 
  local function infer_member_struct_name(expr)
    if expr.kind == "Identifier" then
      local vtype = scope_get(ctx, expr.name)
      if vtype and type(vtype) == "string" and vtype:match("^struct:") then
        return vtype:sub(8)
      end
      return nil
    elseif expr.kind == "Member" then
      local parent_struct = infer_member_struct_name(expr.object)
      if not parent_struct then return nil end
      local def = ctx.structs[parent_struct]
      if not def then return nil end
      for _, field in ipairs(def.fields) do
        if field.name == expr.property then
          local base = type_base(field.type)
          if base and ctx.structs[base] then
            return base
          end
          return nil
        end
      end
      return nil
    end
    return nil
  end

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
      local left_type = infer_expr_type(expr.left)
      local right_type = infer_expr_type(expr.right)
      return emit_binary_typed(expr.op, left, right, left_type, right_type)
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
        local package_module, package_export, package_internal_name = resolve_package_member_export(obj)
        local package_export_kind = package_export and (package_export.kind or (package_export.item and package_export.item.kind))
        if package_export then
          if package_export_kind == "Struct" and prop == "new" then
            local ctor = ctx.struct_ctors[package_internal_name]
            if ctor then
              return ctor .. "(" .. table.concat(args, ", ") .. ")"
            end
          elseif package_export_kind == "Enum" then
            local variant = find_enum_variant(package_internal_name, prop)
            if not variant then
              error("Unknown enum variant: " .. package_module .. "::" .. obj.property .. "." .. prop)
            end
            local expected = variant.types and #variant.types or 0
            if expected > 1 then
              error("Enum variant payload supports at most one value")
            end
            if #args ~= expected then
              error("Enum variant " .. package_module .. "::" .. obj.property .. "." .. prop .. " expects " .. expected .. " value(s)")
            end
            local payload = (#args == 1) and args[1] or "rex_nil()"
            return "rex_tag(" .. c_string(prop) .. ", " .. payload .. ")"
          end
          error("Package export " .. package_module .. "::" .. obj.property .. " does not support member call ." .. prop)
        end
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
            if map and map[prop] then
              return map[prop] .. "(" .. table.concat(args, ", ") .. ")"
            end
            local export = ctx.external_modules[module] and ctx.external_modules[module][prop]
            if export then
              local func = ctx.functions[export.internal_name] or export.internal_name
              return func .. "(" .. table.concat(args, ", ") .. ")"
            end
            local func = "rex_" .. module .. "_" .. prop
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
     
        local nested_struct = infer_member_struct_name(obj)
        if nested_struct then
          local method_map = ctx.method_map[nested_struct] or {}
          local method = method_map[prop]
          if method then
            local call_args = { obj_expr }
            for _, arg in ipairs(args) do
              table.insert(call_args, arg)
            end
            return method .. "(" .. table.concat(call_args, ", ") .. ")"
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
      local package_module, package_export, package_internal_name = resolve_package_member_export(expr.object)
      local package_export_kind = package_export and (package_export.kind or (package_export.item and package_export.item.kind))
      if package_export then
        if package_export_kind == "Enum" then
          local variant = find_enum_variant(package_internal_name, expr.property)
          if not variant then
            error("Unknown enum variant: " .. package_module .. "::" .. expr.object.property .. "." .. expr.property)
          end
          local expected = variant.types and #variant.types or 0
          if expected > 0 then
            error("Enum variant " .. package_module .. "::" .. expr.object.property .. "." .. expr.property .. " requires payload")
          end
          return "rex_tag(" .. c_string(expr.property) .. ", rex_nil())"
        end
      end
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
      return "rex_collections_get(" .. emit_expr_raw(expr.object) .. ", " .. emit_expr_raw(expr.index) .. ")"
    elseif expr.kind == "Slice" then
      local finish = "rex_nil()"
      if expr.finish then
        finish = emit_expr_raw(expr.finish)
      end
      return "rex_collections_slice(" .. emit_expr_raw(expr.object) .. ", " .. emit_expr_raw(expr.start) .. ", " .. finish .. ")"
    elseif expr.kind == "Try" then
      return "rex_try(" .. emit_expr_raw(expr.expr) .. ")"
    elseif expr.kind == "Generic" then
      return emit_expr_raw(expr.expr)
    elseif expr.kind == "StructLit" then
    
      local struct_def = ctx.structs[expr.name]
      if not struct_def then
        error("Unknown struct in literal: " .. expr.name)
      end
      local ctor = ctx.struct_ctors[expr.name]
      local by_name = {}
      for _, f in ipairs(expr.fields) do
        by_name[f.name] = f.value
      end
      local args = {}
      for _, field in ipairs(struct_def.fields) do
        local val_node = by_name[field.name]
        table.insert(args, val_node and emit_expr_raw(val_node) or "rex_nil()")
      end
      return ctor .. "(" .. table.concat(args, ", ") .. ")"
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
      local left_type = infer_expr_type(expr.left)
      local right_type = infer_expr_type(expr.right)
      return emit_binary_typed(expr.op, left, right, left_type, right_type)
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
        local package_module, package_export, package_internal_name = resolve_package_member_export(obj)
        local package_export_kind = package_export and (package_export.kind or (package_export.item and package_export.item.kind))
        if package_export then
          if package_export_kind == "Struct" and prop == "new" then
            local ctor = ctx.struct_ctors[package_internal_name]
            if ctor then
              return ctor .. "(" .. table.concat(args, ", ") .. ")"
            end
          elseif package_export_kind == "Enum" then
            local variant = find_enum_variant(package_internal_name, prop)
            if not variant then
              error("Unknown enum variant: " .. package_module .. "::" .. obj.property .. "." .. prop)
            end
            local expected = variant.types and #variant.types or 0
            if expected > 1 then
              error("Enum variant payload supports at most one value")
            end
            if #args ~= expected then
              error("Enum variant " .. package_module .. "::" .. obj.property .. "." .. prop .. " expects " .. expected .. " value(s)")
            end
            local payload = (#args == 1) and args[1] or "rex_nil()"
            return "rex_tag(" .. c_string(prop) .. ", " .. payload .. ")"
          end
          error("Package export " .. package_module .. "::" .. obj.property .. " does not support member call ." .. prop)
        end
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
            if map and map[prop] then
              return map[prop] .. "(" .. table.concat(args, ", ") .. ")"
            end
            local export = ctx.external_modules[module] and ctx.external_modules[module][prop]
            if export then
              local func = ctx.functions[export.internal_name] or export.internal_name
              return func .. "(" .. table.concat(args, ", ") .. ")"
            end
            local func = "rex_" .. module .. "_" .. prop
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
     
        local nested_struct = infer_member_struct_name(obj)
        if nested_struct then
          local method_map = ctx.method_map[nested_struct] or {}
          local method = method_map[prop]
          if method then
            local call_args = { obj_expr }
            for _, arg in ipairs(args) do
              table.insert(call_args, arg)
            end
            return method .. "(" .. table.concat(call_args, ", ") .. ")"
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
      local package_module, package_export, package_internal_name = resolve_package_member_export(expr.object)
      local package_export_kind = package_export and (package_export.kind or (package_export.item and package_export.item.kind))
      if package_export then
        if package_export_kind == "Enum" then
          local variant = find_enum_variant(package_internal_name, expr.property)
          if not variant then
            error("Unknown enum variant: " .. package_module .. "::" .. expr.object.property .. "." .. expr.property)
          end
          local expected = variant.types and #variant.types or 0
          if expected > 0 then
            error("Enum variant " .. package_module .. "::" .. expr.object.property .. "." .. expr.property .. " requires payload")
          end
          return "rex_tag(" .. c_string(expr.property) .. ", rex_nil())"
        end
      end
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
      return "rex_collections_get(" .. emit_expr(expr.object) .. ", " .. emit_expr(expr.index) .. ")"
    elseif expr.kind == "Slice" then
      local finish = "rex_nil()"
      if expr.finish then
        finish = emit_expr(expr.finish)
      end
      return "rex_collections_slice(" .. emit_expr(expr.object) .. ", " .. emit_expr(expr.start) .. ", " .. finish .. ")"
    elseif expr.kind == "Generic" then
      return emit_expr(expr.expr)
    elseif expr.kind == "StructLit" then
     
      local struct_def = ctx.structs[expr.name]
      if not struct_def then
        error("Unknown struct in literal: " .. expr.name)
      end
      local ctor = ctx.struct_ctors[expr.name]
      local by_name = {}
      for _, f in ipairs(expr.fields) do
        by_name[f.name] = f.value
      end
      local args = {}
      for _, field in ipairs(struct_def.fields) do
        local val_node = by_name[field.name]
        table.insert(args, val_node and emit_expr(val_node) or "rex_nil()")
      end
      return ctor .. "(" .. table.concat(args, ", ") .. ")"
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

  emit_block = function(block, new_scope, prelude, allow_tail_return)
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
    local statements = block.statements or {}
    table.insert(ctx.block_tail_stack, {
      allow_tail_return = allow_tail_return and true or false,
      index = 0,
      count = #statements,
    })
    for i, stmt in ipairs(statements) do
      ctx.block_tail_stack[#ctx.block_tail_stack].index = i
      ctx.emit_stmt(stmt)
    end
    table.remove(ctx.block_tail_stack)
    if new_scope then
      local active_id = ctx.active_bond_stack[#ctx.active_bond_stack]
      if active_id then
        local active_bond = ctx.bonds[active_id]
        if active_bond and active_bond.scope_depth == #ctx.current_bindings then
          error("Bond '" .. (active_bond.name or tostring(active_id)) .. "' left scope without commit/rollback")
        end
      end
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
    if expr.kind == "Member" and expr.object.kind == "Member" and expr.object.object.kind == "Identifier" then
      local module = ctx.imports[expr.object.object.name]
      local export = module and ctx.external_modules[module] and ctx.external_modules[module][expr.object.property]
      local export_kind = export and (export.kind or (export.item and export.item.kind))
      if export_kind == "Enum" then
        return export.internal_name or (export.item and export.item.name) or expr.object.property
      end
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
      if callee.kind == "Member" and callee.object.kind == "Member" and callee.object.object.kind == "Identifier" then
        local module = ctx.imports[callee.object.object.name]
        local export = module and ctx.external_modules[module] and ctx.external_modules[module][callee.object.property]
        local export_kind = export and (export.kind or (export.item and export.item.kind))
        if export_kind == "Enum" then
          return export.internal_name or (export.item and export.item.name) or callee.object.property
        end
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
    
    if expr.kind == "StructLit" and ctx.structs[expr.name] then
      return expr.name
    end
    if expr.kind == "Call" then
      local callee = expr.callee
      if callee.kind == "Generic" then
        callee = callee.expr
      end
      if callee.kind == "Member" and callee.object.kind == "Member" and callee.object.object.kind == "Identifier" then
        local module = ctx.imports[callee.object.object.name]
        local export = module and ctx.external_modules[module] and ctx.external_modules[module][callee.object.property]
        local export_kind = export and (export.kind or (export.item and export.item.kind))
        if callee.property == "new" and export_kind == "Struct" then
          return export.internal_name or (export.item and export.item.name) or callee.object.property
        end
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

  resolve_package_member_export = function(expr)
    if not expr or expr.kind ~= "Member" then
      return nil, nil, nil
    end
    if not expr.object or expr.object.kind ~= "Identifier" then
      return nil, nil, nil
    end
    local module = ctx.imports[expr.object.name]
    if not module then
      return nil, nil, nil
    end
    local export = ctx.external_modules[module] and ctx.external_modules[module][expr.property]
    if not export then
      return module, nil, nil
    end
    local internal_name = export.internal_name or (export.item and export.item.name) or expr.property
    return module, export, internal_name
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
        if base and numeric_types[base] then
          type_annotation = "num"
        elseif base == "bool" then
          type_annotation = "bool"
        elseif base == "str" or base == "string" then
          type_annotation = "str"
        elseif base and ctx.structs[base] then
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
            else
              type_annotation = infer_expr_type(stmt.value)
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
      local actions_var = "__rex_bond_actions_" .. bid
      local count_var = "__rex_bond_count_" .. bid
      local cap_var = "__rex_bond_cap_" .. bid
      indent_line(ctx, "RexBondAction* " .. actions_var .. " = NULL;")
      indent_line(ctx, "int " .. count_var .. " = 0;")
      indent_line(ctx, "int " .. cap_var .. " = 0;")
      local value = emit_expr(stmt.value)
      local c_name = get_c_name(ctx, stmt.name)
      indent_line(ctx, "RexValue " .. c_name .. " = " .. value .. ";")
      
      scope_set_binding(ctx, stmt.name, c_name, "bond:" .. bid)
      ctx.bonds[bid] = {
        id = bid,
        name = stmt.name,
        c_name = c_name,
        actions_var = actions_var,
        count_var = count_var,
        cap_var = cap_var,
        scope_depth = #ctx.current_bindings,
      }
      table.insert(ctx.active_bond_stack, bid)
      ctx.active_bond = bid
    elseif stmt.kind == "Commit" then
   
      if ctx.active_bond then
        local bond = ctx.bonds[ctx.active_bond]
        if bond then
          indent_line(ctx, "__rex_bond_reset(&" .. bond.actions_var .. ", &" .. bond.count_var .. ", &" .. bond.cap_var .. ");")
        end
        table.remove(ctx.active_bond_stack)
        ctx.active_bond = ctx.active_bond_stack[#ctx.active_bond_stack]
      end
    elseif stmt.kind == "Rollback" then
      --  undo all changes in bond
      if ctx.active_bond then
        local bond = ctx.bonds[ctx.active_bond]
        if bond then
          indent_line(ctx, "__rex_bond_apply_rollback(" .. bond.actions_var .. ", " .. bond.count_var .. ");")
          indent_line(ctx, "__rex_bond_reset(&" .. bond.actions_var .. ", &" .. bond.count_var .. ", &" .. bond.cap_var .. ");")
          indent_line(ctx, bond.c_name .. " = rex_nil();")
        end
        table.remove(ctx.active_bond_stack)
        ctx.active_bond = ctx.active_bond_stack[#ctx.active_bond_stack]
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
      local target = get_c_ident(ctx, stmt.name)
      if ctx.active_bond then
        local bond = ctx.bonds[ctx.active_bond]
        if bond then
          indent_line(
            ctx,
            "__rex_bond_push_assign(&" .. bond.actions_var .. ", &" .. bond.count_var .. ", &" .. bond.cap_var .. ", &" .. target .. ", " .. target .. ");"
          )
        end
      end
      indent_line(ctx, target .. " = " .. emit_expr(stmt.value) .. ";")
    elseif stmt.kind == "MemberAssign" then
      local obj_expr = emit_expr(stmt.object)
      local field_lit = c_string(stmt.property)
      if ctx.active_bond then
        local bond = ctx.bonds[ctx.active_bond]
        if bond then
          indent_line(
            ctx,
            "__rex_bond_push_member(&" .. bond.actions_var .. ", &" .. bond.count_var .. ", &" .. bond.cap_var .. ", "
              .. obj_expr .. ", " .. field_lit .. ", rex_struct_get(" .. obj_expr .. ", " .. field_lit .. "));"
          )
        end
      end
      indent_line(ctx, "rex_struct_set(" .. obj_expr .. ", " .. field_lit .. ", " .. emit_expr(stmt.value) .. ");")
    elseif stmt.kind == "IndexAssign" then
      local obj_expr = emit_expr(stmt.object)
      if ctx.active_bond then
        local bond = ctx.bonds[ctx.active_bond]
        if bond then
          ctx.tmp_id = ctx.tmp_id + 1
          local idx_tmp = "__bond_idx_" .. ctx.tmp_id
          indent_line(ctx, "RexValue " .. idx_tmp .. " = " .. emit_expr(stmt.index) .. ";")
          indent_line(
            ctx,
            "__rex_bond_push_index(&" .. bond.actions_var .. ", &" .. bond.count_var .. ", &" .. bond.cap_var .. ", "
              .. obj_expr .. ", " .. idx_tmp .. ", rex_collections_get(" .. obj_expr .. ", " .. idx_tmp .. "));"
          )
          indent_line(ctx, "rex_collections_set(" .. obj_expr .. ", " .. idx_tmp .. ", " .. emit_expr(stmt.value) .. ");")
        else
          indent_line(ctx, "rex_collections_set(" .. obj_expr .. ", " .. emit_expr(stmt.index) .. ", " .. emit_expr(stmt.value) .. ");")
        end
      else
        indent_line(ctx, "rex_collections_set(" .. obj_expr .. ", " .. emit_expr(stmt.index) .. ", " .. emit_expr(stmt.value) .. ");")
      end
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
        local start_num = "__start_num" .. id
        local end_num = "__end_num" .. id
        local idx_num = "__idx_num" .. id
        indent_line(ctx, "RexValue " .. start_var .. " = " .. emit_expr(stmt.range_start) .. ";")
        indent_line(ctx, "RexValue " .. end_var .. " = " .. emit_expr(stmt.range_end) .. ";")
        indent_line(ctx, "if (" .. start_var .. ".tag != REX_NUM || " .. end_var .. ".tag != REX_NUM) { rex_panic(\"for range expects numbers\"); }")
        indent_line(ctx, "double " .. start_num .. " = " .. start_var .. ".as.num;")
        indent_line(ctx, "double " .. end_num .. " = " .. end_var .. ".as.num;")
        indent_line(ctx, "for (double " .. idx_num .. " = " .. start_num .. "; " .. idx_num .. " < " .. end_num .. "; " .. idx_num .. " += 1.0) {")
        ctx.indent = ctx.indent + 1
        indent_line(ctx, "RexValue " .. loop_var .. " = rex_num(" .. idx_num .. ");")
        emit_block(stmt.body, true, function()
          scope_set_binding(ctx, stmt.name, loop_var, "num")
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

      
      local has_wildcard = false
      for _, arm in ipairs(stmt.arms) do
        if arm.wildcard then has_wildcard = true end
      end

      local first_arm = true
      for _, arm in ipairs(stmt.arms) do
        if arm.wildcard then
          indent_line(ctx, first_arm and "{" or "else {")
        else
          local tags = arm.tags or { arm.tag }
          local parts = {}
          for _, tag in ipairs(tags) do
            table.insert(parts, "rex_tag_is(" .. tmp .. ", " .. c_string(tag) .. ")")
          end
          local cond = table.concat(parts, " || ")
          indent_line(ctx, (first_arm and "if" or "else if") .. " (" .. cond .. ") {")
        end
        first_arm = false

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
              if can_emit_tail_return() then
                indent_line(ctx, "return " .. emit_expr(last_stmt.expr) .. ";")
              else
                indent_line(ctx, emit_expr(last_stmt.expr) .. ";")
              end
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

      if not has_wildcard then
        indent_line(ctx, "else {")
        ctx.indent = ctx.indent + 1
        indent_line(ctx, "rex_panic(\"non-exhaustive match\");")
        ctx.indent = ctx.indent - 1
        indent_line(ctx, "}")
      end
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
  indent_line(ctx, "#include <math.h>")
  indent_line(ctx, "#include \"rex_rt.h\"")
  indent_line(ctx, "")
  indent_line(ctx, "typedef enum RexBondActionKind {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "REX_BOND_ASSIGN = 0,")
  indent_line(ctx, "REX_BOND_MEMBER = 1,")
  indent_line(ctx, "REX_BOND_INDEX = 2")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "} RexBondActionKind;")
  indent_line(ctx, "")
  indent_line(ctx, "typedef struct RexBondAction {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "RexBondActionKind kind;")
  indent_line(ctx, "RexValue* slot;")
  indent_line(ctx, "RexValue object;")
  indent_line(ctx, "RexValue key;")
  indent_line(ctx, "const char* field;")
  indent_line(ctx, "RexValue old_value;")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "} RexBondAction;")
  indent_line(ctx, "")
  indent_line(ctx, "static void __rex_bond_push(RexBondAction** actions, int* count, int* cap, RexBondAction action) {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "if (!actions || !count || !cap) {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "rex_panic(\"invalid bond state\");")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "}")
  indent_line(ctx, "if (*count >= *cap) {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "int next = (*cap == 0) ? 8 : (*cap * 2);")
  indent_line(ctx, "RexBondAction* resized = (RexBondAction*)realloc(*actions, (size_t)next * sizeof(RexBondAction));")
  indent_line(ctx, "if (!resized) {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "rex_panic(\"bond out of memory\");")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "}")
  indent_line(ctx, "*actions = resized;")
  indent_line(ctx, "*cap = next;")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "}")
  indent_line(ctx, "(*actions)[*count] = action;")
  indent_line(ctx, "*count = *count + 1;")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "}")
  indent_line(ctx, "")
  indent_line(ctx, "static void __rex_bond_push_assign(RexBondAction** actions, int* count, int* cap, RexValue* slot, RexValue old_value) {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "RexBondAction action;")
  indent_line(ctx, "memset(&action, 0, sizeof(action));")
  indent_line(ctx, "action.kind = REX_BOND_ASSIGN;")
  indent_line(ctx, "action.slot = slot;")
  indent_line(ctx, "action.old_value = old_value;")
  indent_line(ctx, "__rex_bond_push(actions, count, cap, action);")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "}")
  indent_line(ctx, "")
  indent_line(ctx, "static void __rex_bond_push_member(RexBondAction** actions, int* count, int* cap, RexValue object, const char* field, RexValue old_value) {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "RexBondAction action;")
  indent_line(ctx, "memset(&action, 0, sizeof(action));")
  indent_line(ctx, "action.kind = REX_BOND_MEMBER;")
  indent_line(ctx, "action.object = object;")
  indent_line(ctx, "action.field = field;")
  indent_line(ctx, "action.old_value = old_value;")
  indent_line(ctx, "__rex_bond_push(actions, count, cap, action);")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "}")
  indent_line(ctx, "")
  indent_line(ctx, "static void __rex_bond_push_index(RexBondAction** actions, int* count, int* cap, RexValue object, RexValue key, RexValue old_value) {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "RexBondAction action;")
  indent_line(ctx, "memset(&action, 0, sizeof(action));")
  indent_line(ctx, "action.kind = REX_BOND_INDEX;")
  indent_line(ctx, "action.object = object;")
  indent_line(ctx, "action.key = key;")
  indent_line(ctx, "action.old_value = old_value;")
  indent_line(ctx, "__rex_bond_push(actions, count, cap, action);")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "}")
  indent_line(ctx, "")
  indent_line(ctx, "static void __rex_bond_apply_rollback(RexBondAction* actions, int count) {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "for (int i = count - 1; i >= 0; --i) {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "RexBondAction* action = &actions[i];")
  indent_line(ctx, "if (action->kind == REX_BOND_ASSIGN) {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "if (action->slot) {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "*(action->slot) = action->old_value;")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "}")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "} else if (action->kind == REX_BOND_MEMBER) {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "rex_struct_set(action->object, action->field, action->old_value);")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "} else if (action->kind == REX_BOND_INDEX) {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "rex_collections_set(action->object, action->key, action->old_value);")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "}")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "}")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "}")
  indent_line(ctx, "")
  indent_line(ctx, "static void __rex_bond_reset(RexBondAction** actions, int* count, int* cap) {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "if (actions && *actions) {")
  ctx.indent = ctx.indent + 1
  indent_line(ctx, "free(*actions);")
  indent_line(ctx, "*actions = NULL;")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "}")
  indent_line(ctx, "if (count) { *count = 0; }")
  indent_line(ctx, "if (cap) { *cap = 0; }")
  ctx.indent = ctx.indent - 1
  indent_line(ctx, "}")
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
        emit_block(method.body, true, nil, true)
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
      emit_block(item.body, true, nil, true)
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
    indent_line(ctx, "int main(int argc, char** argv) {")
    ctx.indent = ctx.indent + 1
    indent_line(ctx, "rex_os_set_args(argc, argv);")
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
