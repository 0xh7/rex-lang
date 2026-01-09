#ifndef REX_UI_H
#define REX_UI_H

#include "rex_rt.h"

#include <stdint.h>

#define REX_UI_TEXT_MAX 1024

typedef struct RexUIPlatformInput {
  int mouse_x;
  int mouse_y;
  int mouse_down;
  int scroll_y;
  int key_tab;
  int key_enter;
  int key_space;
  int key_up;
  int key_down;
  int key_backspace;
  int key_delete;
  int key_left;
  int key_right;
  int key_home;
  int key_end;
  int key_ctrl;
  int key_shift;
  int key_copy;
  int key_paste;
  int key_cut;
  int key_select_all;
  int width;
  int height;
  float dpi_scale;
  char text[REX_UI_TEXT_MAX];
  int text_len;
  int closed;
  int redraw;
} RexUIPlatformInput;

int rex_ui_platform_init(const char* title, int width, int height);
void rex_ui_platform_shutdown(void);
int rex_ui_platform_poll(RexUIPlatformInput* input);
void rex_ui_platform_present(const uint32_t* pixels, int width, int height);
int rex_ui_platform_get_clipboard(char* buffer, int capacity);
void rex_ui_platform_set_clipboard(const char* text);
void rex_ui_platform_set_titlebar_dark(int dark);

#endif
