#ifndef REX_RT_H
#define REX_RT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum RexTag {
  REX_NIL,
  REX_NUM,
  REX_BOOL,
  REX_STR,
  REX_PTR,
  REX_REF,
  REX_REF_MUT,
  REX_STRUCT,
  REX_TUPLE,
  REX_RESULT,
  REX_SENDER,
  REX_RECEIVER,
  REX_VEC,
  REX_MAP,
  REX_SET
} RexTag;

typedef struct RexValue {
  RexTag tag;
  union {
    double num;
    int boolean;
    const char* str;
    void* ptr;
  } as;
} RexValue;

RexValue rex_nil(void);
RexValue rex_num(double n);
RexValue rex_bool(int b);
RexValue rex_str(const char* s);
RexValue rex_ptr(void* p);
RexValue rex_ref(RexValue* v);
RexValue rex_ref_mut(RexValue* v);
void rex_drop(RexValue v);

int rex_is_truthy(RexValue v);

RexValue rex_add(RexValue a, RexValue b);
RexValue rex_sub(RexValue a, RexValue b);
RexValue rex_mul(RexValue a, RexValue b);
RexValue rex_div(RexValue a, RexValue b);
RexValue rex_mod(RexValue a, RexValue b);
RexValue rex_eq(RexValue a, RexValue b);
RexValue rex_neq(RexValue a, RexValue b);
RexValue rex_lt(RexValue a, RexValue b);
RexValue rex_lte(RexValue a, RexValue b);
RexValue rex_gt(RexValue a, RexValue b);
RexValue rex_gte(RexValue a, RexValue b);
RexValue rex_neg(RexValue v);
RexValue rex_not(RexValue v);
RexValue rex_and(RexValue a, RexValue b);
RexValue rex_or(RexValue a, RexValue b);

void rex_println(RexValue v);
void rex_print(RexValue v);

RexValue rex_ok(RexValue v);
RexValue rex_err(RexValue v);
int rex_result_is(RexValue v, const char* tag);
RexValue rex_result_value(RexValue v);
RexValue rex_tag(const char* tag, RexValue v);
int rex_tag_is(RexValue v, const char* tag);
RexValue rex_tag_value(RexValue v);
RexValue rex_try(RexValue v);

RexValue rex_alloc(void);
void rex_free(RexValue p);
RexValue rex_box(RexValue v);
RexValue rex_unbox(RexValue p);
RexValue rex_deref(RexValue p);
void rex_deref_assign(RexValue p, RexValue v);

RexValue rex_struct_new(const char* name, const char** fields, RexValue* values, int count);
RexValue rex_struct_get(RexValue obj, const char* field);
void rex_struct_set(RexValue obj, const char* field, RexValue value);

RexValue rex_tuple_new(int count, RexValue* values);
RexValue rex_tuple_get(RexValue tuple, int index);

RexValue rex_channel(void);
void rex_sender_send(RexValue sender, RexValue value);
RexValue rex_receiver_recv(RexValue receiver);
typedef void (*RexSpawnFn)(void* ctx);
RexValue rex_spawn(RexSpawnFn fn, void* ctx);
RexValue rex_wait_all(void);

RexValue rex_sleep(RexValue ms);
RexValue rex_sleep_s(RexValue seconds);
RexValue rex_now_ms(void);
RexValue rex_now_s(void);
RexValue rex_now_ns(void);
RexValue rex_time_since(RexValue start);

RexValue rex_format(RexValue v);
RexValue rex_sqrt(RexValue v);
RexValue rex_abs(RexValue v);

RexValue rex_io_read_file(RexValue path);
RexValue rex_io_write_file(RexValue path, RexValue data);
RexValue rex_io_read_line(void);
RexValue rex_io_read_lines(RexValue path);
RexValue rex_io_write_lines(RexValue path, RexValue lines);

RexValue rex_fs_exists(RexValue path);
RexValue rex_fs_mkdir(RexValue path);
RexValue rex_fs_remove(RexValue path);

RexValue rex_os_getenv(RexValue key);
RexValue rex_os_cwd(void);

RexValue rex_collections_vec_new(void);
void rex_collections_vec_push(RexValue vec, RexValue value);
RexValue rex_collections_vec_get(RexValue vec, RexValue index);
void rex_collections_vec_set(RexValue vec, RexValue index, RexValue value);
RexValue rex_collections_vec_len(RexValue vec);
RexValue rex_collections_vec_insert(RexValue vec, RexValue index, RexValue value);
RexValue rex_collections_vec_slice(RexValue vec, RexValue start, RexValue finish);
RexValue rex_collections_vec_from(int count, RexValue* values);
RexValue rex_collections_vec_pop(RexValue vec);
RexValue rex_collections_vec_clear(RexValue vec);
RexValue rex_collections_vec_sort(RexValue vec);

RexValue rex_collections_map_new(void);
void rex_collections_map_put(RexValue map, RexValue key, RexValue value);
RexValue rex_collections_map_get(RexValue map, RexValue key);
RexValue rex_collections_map_remove(RexValue map, RexValue key);
RexValue rex_collections_map_has(RexValue map, RexValue key);
RexValue rex_collections_map_keys(RexValue map);

RexValue rex_collections_set_new(void);
void rex_collections_set_add(RexValue set, RexValue value);
RexValue rex_collections_set_has(RexValue set, RexValue value);
RexValue rex_collections_set_remove(RexValue set, RexValue value);

RexValue rex_net_tcp_connect(RexValue addr);
RexValue rex_net_udp_socket(void);
RexValue rex_http_get(RexValue url);
RexValue rex_http_get_status(RexValue url);
RexValue rex_http_get_json(RexValue url);

RexValue rex_random_seed(RexValue seed);
RexValue rex_random_int(RexValue min, RexValue max);
RexValue rex_random_float(void);
RexValue rex_random_bool(RexValue probability);
RexValue rex_random_choice(RexValue vec);
RexValue rex_random_shuffle(RexValue vec);
RexValue rex_random_range(RexValue min, RexValue max);

RexValue rex_json_encode(RexValue v);
RexValue rex_json_encode_pretty(RexValue v, RexValue indent);
RexValue rex_json_decode(RexValue s);

RexValue rex_ui_begin(RexValue title, RexValue width, RexValue height);
RexValue rex_ui_end(void);
RexValue rex_ui_redraw(void);
RexValue rex_ui_clear(RexValue color);
RexValue rex_ui_key_space(void);
RexValue rex_ui_key_up(void);
RexValue rex_ui_key_down(void);
RexValue rex_ui_mouse_x(void);
RexValue rex_ui_mouse_y(void);
RexValue rex_ui_mouse_down(void);
RexValue rex_ui_mouse_pressed(void);
RexValue rex_ui_mouse_released(void);
RexValue rex_ui_label(RexValue text);
RexValue rex_ui_text(RexValue x, RexValue y, RexValue text, RexValue color);
RexValue rex_ui_button(RexValue label);
RexValue rex_ui_checkbox(RexValue label, RexValue checked);
RexValue rex_ui_radio(RexValue label, RexValue active);
RexValue rex_ui_textbox(RexValue value, RexValue width);
RexValue rex_ui_slider(RexValue label, RexValue value, RexValue min, RexValue max);
RexValue rex_ui_progress(RexValue value, RexValue max);
RexValue rex_ui_switch(RexValue label, RexValue active);
RexValue rex_ui_select(RexValue items, RexValue selected);
RexValue rex_ui_combo(RexValue items, RexValue selected);
RexValue rex_ui_menu(RexValue items, RexValue selected);
RexValue rex_ui_tabs(RexValue items, RexValue selected);
RexValue rex_ui_layout_row(RexValue height);
RexValue rex_ui_layout_column(RexValue height);
RexValue rex_ui_layout_grid(RexValue cols, RexValue cell_w, RexValue cell_h);
RexValue rex_ui_newline(void);
RexValue rex_ui_row_end(void);
RexValue rex_ui_clip_begin(RexValue x, RexValue y, RexValue w, RexValue h);
RexValue rex_ui_clip_end(void);
RexValue rex_ui_spacing(RexValue px);
RexValue rex_ui_padding(RexValue px);
RexValue rex_ui_scroll_begin(RexValue height);
RexValue rex_ui_scroll_end(void);
RexValue rex_ui_enabled(RexValue enabled);
RexValue rex_ui_invert(RexValue enabled);
RexValue rex_ui_titlebar_dark(RexValue enabled);
RexValue rex_ui_theme_dark(void);
RexValue rex_ui_theme_light(void);
RexValue rex_ui_theme_custom(
  RexValue bg,
  RexValue panel,
  RexValue text,
  RexValue muted,
  RexValue button,
  RexValue button_hover,
  RexValue button_active,
  RexValue accent,
  RexValue select
);
RexValue rex_ui_image_load(RexValue path);
RexValue rex_ui_image_w(RexValue img);
RexValue rex_ui_image_h(RexValue img);
RexValue rex_ui_image(RexValue img, RexValue x, RexValue y);
RexValue rex_ui_image_region(RexValue img, RexValue sx, RexValue sy, RexValue sw, RexValue sh, RexValue x, RexValue y, RexValue w, RexValue h);
RexValue rex_ui_play_sound(RexValue path);

void rex_panic(const char* msg);


void rex_ownership_debug_enable(void);
void rex_ownership_debug_disable(void);
void rex_ownership_trace(const char* variable, const char* event);
void rex_ownership_check(const char* variable);
void rex_ownership_cleanup(void);


uint64_t rex_temporal_now_ms(void);
int rex_temporal_is_expired(uint64_t start_time, uint64_t lifetime_ms);

#ifdef __cplusplus
}
#endif

#endif
