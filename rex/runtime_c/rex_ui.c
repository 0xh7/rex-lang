#include "rex_ui.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wincodec.h>
#include <mmsystem.h>
#include <wchar.h>
#define DR_MP3_IMPLEMENTATION
#include "dr_mp3.h"
#endif

#define UI_FONT_W 5
#define UI_FONT_H 7
#define UI_SCALE 2
#define UI_TEXT_MAX REX_UI_TEXT_MAX
#define UI_CLIP_STACK_MAX 8
#define UI_LAYOUT_STACK_MAX 8
#define UI_SCROLL_MAX 32
#define UI_KEY_REPEAT_DELAY 350.0
#define UI_KEY_REPEAT_RATE 50.0

#define UI_LAYOUT_COLUMN 0
#define UI_LAYOUT_ROW 1
#define UI_LAYOUT_GRID 2

typedef struct RexUIRect {
  int x;
  int y;
  int w;
  int h;
} RexUIRect;

typedef struct RexUITheme {
  uint32_t bg;
  uint32_t panel;
  uint32_t text;
  uint32_t muted;
  uint32_t button;
  uint32_t button_hover;
  uint32_t button_active;
  uint32_t accent;
  uint32_t select;
} RexUITheme;

typedef struct RexUIScrollEntry {
  int id;
  int offset;
} RexUIScrollEntry;

typedef struct RexUILayoutState {
  int layout_mode;
  int cursor_x;
  int cursor_y;
  int row_height;
  int item_height;
  int spacing;
  int padding;
  int grid_cols;
  int grid_cell_w;
  int grid_cell_h;
  int grid_index;
  int grid_origin_x;
  int grid_origin_y;
  int content_x;
  int content_w;
  int combo_open_id;
  int enabled;
  RexUIRect scroll_view;
  int scroll_id;
  int scroll_offset;
} RexUILayoutState;

typedef struct RexUIState {
  int width;
  int height;
  int running;
  uint32_t* pixels;

  int mouse_x;
  int mouse_y;
  int mouse_down;
  int mouse_pressed;
  int mouse_released;
  int prev_mouse_down;
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
  int key_tab_down;
  int key_enter_down;
  int key_space_down;
  int key_up_down;
  int key_down_down;
  int key_backspace_down;
  int key_delete_down;
  int key_left_down;
  int key_right_down;
  int key_home_down;
  int key_end_down;
  int key_tab_prev;
  int key_enter_prev;
  int key_space_prev;
  int key_home_prev;
  int key_end_prev;
  double key_up_next;
  double key_down_next;
  double key_left_next;
  double key_right_next;
  double key_backspace_next;
  double key_delete_next;
  char text[UI_TEXT_MAX];
  int text_len;

  int hot_id;
  int active_id;
  int next_id;
  int focus_id;
  int focus_request;
  int focus_first;
  int focus_last;
  int focus_prev;
  int focus_moved;
  int focus_set;

  int layout_mode;
  int cursor_x;
  int cursor_y;
  int row_height;
  int item_height;
  int spacing;
  int padding;
  int content_x;
  int content_w;

  int grid_cols;
  int grid_cell_w;
  int grid_cell_h;
  int grid_index;
  int grid_origin_x;
  int grid_origin_y;

  int combo_open_id;

  int enabled;
  int dirty;
  int draw_enabled;
  int invert;
  float dpi_scale;
  int scale;

  int text_focus_id;
  int text_cursor;
  int text_sel_start;
  int text_sel_end;
  int text_dragging;
  int text_scroll_x;

  RexUIRect clip;
  RexUIRect clip_stack[UI_CLIP_STACK_MAX];
  int clip_depth;

  RexUILayoutState layout_stack[UI_LAYOUT_STACK_MAX];
  int layout_depth;

  RexUIScrollEntry scrolls[UI_SCROLL_MAX];
  int scroll_count;

  RexUITheme theme;
} RexUIState;

static RexUIState ui = { 0 };

typedef struct RexUIImage {
  int w;
  int h;
  uint32_t pixels[];
} RexUIImage;

#ifdef _WIN32
static int ui_wic_inited = 0;
static IWICImagingFactory* ui_wic = NULL;
typedef struct RexUISound {
  HWAVEOUT handle;
  WAVEHDR header;
  drmp3_int16* data;
  size_t data_size;
} RexUISound;
static RexUISound ui_sound = { 0 };

static void ui_wic_init(void) {
  if (ui_wic_inited) {
    return;
  }
  ui_wic_inited = 1;
  HRESULT hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
  if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
    return;
  }
  hr = CoCreateInstance(&CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER, &IID_IWICImagingFactory, (void**)&ui_wic);
  if (FAILED(hr)) {
    ui_wic = NULL;
  }
}

static wchar_t* ui_widen_path(const char* path) {
  if (!path) {
    return NULL;
  }
  int len = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
  UINT cp = CP_UTF8;
  if (len <= 0) {
    cp = CP_ACP;
    len = MultiByteToWideChar(cp, 0, path, -1, NULL, 0);
  }
  if (len <= 0) {
    return NULL;
  }
  wchar_t* wpath = (wchar_t*)malloc((size_t)len * sizeof(wchar_t));
  if (!wpath) {
    return NULL;
  }
  if (MultiByteToWideChar(cp, 0, path, -1, wpath, len) <= 0) {
    free(wpath);
    return NULL;
  }
  return wpath;
}

static void ui_sound_stop(void) {
  if (ui_sound.handle) {
    waveOutReset(ui_sound.handle);
    if (ui_sound.header.dwFlags & WHDR_PREPARED) {
      waveOutUnprepareHeader(ui_sound.handle, &ui_sound.header, sizeof(ui_sound.header));
    }
    waveOutClose(ui_sound.handle);
    ui_sound.handle = NULL;
  }
  if (ui_sound.data) {
    free(ui_sound.data);
    ui_sound.data = NULL;
  }
  ui_sound.data_size = 0;
  memset(&ui_sound.header, 0, sizeof(ui_sound.header));
}

static int ui_play_mp3(const wchar_t* path) {
  if (!path) {
    return 0;
  }
  drmp3 mp3;
  if (!drmp3_init_file_w(&mp3, path, NULL)) {
    return 0;
  }
  drmp3_uint64 frame_count = drmp3_get_pcm_frame_count(&mp3);
  if (frame_count == 0) {
    drmp3_uninit(&mp3);
    return 0;
  }
  if (mp3.channels == 0 || mp3.sampleRate == 0) {
    drmp3_uninit(&mp3);
    return 0;
  }
  if (frame_count > (drmp3_uint64)(SIZE_MAX / (mp3.channels * sizeof(drmp3_int16)))) {
    drmp3_uninit(&mp3);
    return 0;
  }
  size_t total_samples = (size_t)frame_count * (size_t)mp3.channels;
  size_t total_bytes = total_samples * sizeof(drmp3_int16);
  drmp3_int16* data = (drmp3_int16*)malloc(total_bytes);
  if (!data) {
    drmp3_uninit(&mp3);
    return 0;
  }
  drmp3_uint64 frames_read = drmp3_read_pcm_frames_s16(&mp3, frame_count, data);
  drmp3_uninit(&mp3);
  if (frames_read == 0) {
    free(data);
    return 0;
  }
  size_t samples_read = (size_t)frames_read * (size_t)mp3.channels;
  size_t bytes_read = samples_read * sizeof(drmp3_int16);

  ui_sound_stop();

  WAVEFORMATEX wf;
  memset(&wf, 0, sizeof(wf));
  wf.wFormatTag = WAVE_FORMAT_PCM;
  wf.nChannels = (WORD)mp3.channels;
  wf.nSamplesPerSec = (DWORD)mp3.sampleRate;
  wf.wBitsPerSample = 16;
  wf.nBlockAlign = (wf.nChannels * wf.wBitsPerSample) / 8;
  wf.nAvgBytesPerSec = wf.nSamplesPerSec * wf.nBlockAlign;
  if (waveOutOpen(&ui_sound.handle, WAVE_MAPPER, &wf, 0, 0, CALLBACK_NULL) != MMSYSERR_NOERROR) {
    free(data);
    return 0;
  }
  ui_sound.data = data;
  ui_sound.data_size = bytes_read;
  memset(&ui_sound.header, 0, sizeof(ui_sound.header));
  ui_sound.header.lpData = (LPSTR)ui_sound.data;
  ui_sound.header.dwBufferLength = (DWORD)ui_sound.data_size;
  if (waveOutPrepareHeader(ui_sound.handle, &ui_sound.header, sizeof(ui_sound.header)) != MMSYSERR_NOERROR) {
    ui_sound_stop();
    return 0;
  }
  if (waveOutWrite(ui_sound.handle, &ui_sound.header, sizeof(ui_sound.header)) != MMSYSERR_NOERROR) {
    ui_sound_stop();
    return 0;
  }
  return 1;
}

static RexUIImage* ui_image_load_wic(const char* path) {
  ui_wic_init();
  if (!ui_wic) {
    return NULL;
  }

  wchar_t* wpath = ui_widen_path(path);
  if (!wpath) {
    return NULL;
  }

  IWICBitmapDecoder* decoder = NULL;
  IWICBitmapFrameDecode* frame = NULL;
  IWICFormatConverter* converter = NULL;
  BYTE* bgra = NULL;
  RexUIImage* out = NULL;

  HRESULT hr = ui_wic->lpVtbl->CreateDecoderFromFilename(
    ui_wic,
    wpath,
    NULL,
    GENERIC_READ,
    WICDecodeMetadataCacheOnLoad,
    &decoder
  );
  free(wpath);
  wpath = NULL;
  if (FAILED(hr) || !decoder) {
    goto done;
  }

  hr = decoder->lpVtbl->GetFrame(decoder, 0, &frame);
  if (FAILED(hr) || !frame) {
    goto done;
  }

  UINT w = 0;
  UINT h = 0;
  hr = frame->lpVtbl->GetSize(frame, &w, &h);
  if (FAILED(hr) || w == 0 || h == 0) {
    goto done;
  }

  hr = ui_wic->lpVtbl->CreateFormatConverter(ui_wic, &converter);
  if (FAILED(hr) || !converter) {
    goto done;
  }

  hr = converter->lpVtbl->Initialize(
    converter,
    (IWICBitmapSource*)frame,
    &GUID_WICPixelFormat32bppBGRA,
    WICBitmapDitherTypeNone,
    NULL,
    0.0,
    WICBitmapPaletteTypeCustom
  );
  if (FAILED(hr)) {
    goto done;
  }

  size_t count = (size_t)w * (size_t)h;
  if (count > (SIZE_MAX / 4u)) {
    goto done;
  }
  size_t bytes = count * 4u;
  bgra = (BYTE*)malloc(bytes);
  if (!bgra) {
    goto done;
  }

  hr = converter->lpVtbl->CopyPixels(converter, NULL, (UINT)(w * 4u), (UINT)bytes, bgra);
  if (FAILED(hr)) {
    goto done;
  }

  if (count > ((SIZE_MAX - sizeof(RexUIImage)) / sizeof(uint32_t))) {
    goto done;
  }
  out = (RexUIImage*)malloc(sizeof(RexUIImage) + count * sizeof(uint32_t));
  if (!out) {
    goto done;
  }
  out->w = (int)w;
  out->h = (int)h;

  for (size_t i = 0; i < count; i++) {
    uint8_t b = bgra[i * 4u + 0u];
    uint8_t g = bgra[i * 4u + 1u];
    uint8_t r = bgra[i * 4u + 2u];
    uint8_t a = bgra[i * 4u + 3u];
    out->pixels[i] = ((uint32_t)a << 24) | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
  }

done:
  free(bgra);
  if (converter) {
    converter->lpVtbl->Release(converter);
  }
  if (frame) {
    frame->lpVtbl->Release(frame);
  }
  if (decoder) {
    decoder->lpVtbl->Release(decoder);
  }
  return out;
}
#endif

static const RexUITheme ui_theme_dark = {
  0xFF1E1E1E,
  0xFF252526,
  0xFFE0E0E0,
  0xFF9E9E9E,
  0xFF3A3A3A,
  0xFF4A4A4A,
  0xFF2A2A2A,
  0xFF3EA6FF,
  0xFF2F5E9E
};

static const RexUITheme ui_theme_light = {
  0xFFF3F3F3,
  0xFFFFFFFF,
  0xFF1E1E1E,
  0xFF666666,
  0xFFE0E0E0,
  0xFFD0D0D0,
  0xFFB8B8B8,
  0xFF2A7BD4,
  0xFF9CC5F2
};

static char ui_clipboard[UI_TEXT_MAX] = { 0 };

static RexValue ui_resolve(RexValue v) {
  while (v.tag == REX_REF || v.tag == REX_REF_MUT) {
    if (!v.as.ptr) {
      return rex_nil();
    }
    v = *(RexValue*)v.as.ptr;
  }
  return v;
}

static const uint8_t ui_font[96][5] = {
  {0x00, 0x00, 0x00, 0x00, 0x00},
  {0x00, 0x00, 0x5F, 0x00, 0x00},
  {0x00, 0x07, 0x00, 0x07, 0x00},
  {0x14, 0x7F, 0x14, 0x7F, 0x14},
  {0x24, 0x2A, 0x7F, 0x2A, 0x12},
  {0x23, 0x13, 0x08, 0x64, 0x62},
  {0x36, 0x49, 0x55, 0x22, 0x50},
  {0x00, 0x05, 0x03, 0x00, 0x00},
  {0x00, 0x1C, 0x22, 0x41, 0x00},
  {0x00, 0x41, 0x22, 0x1C, 0x00},
  {0x14, 0x08, 0x3E, 0x08, 0x14},
  {0x08, 0x08, 0x3E, 0x08, 0x08},
  {0x00, 0x50, 0x30, 0x00, 0x00},
  {0x08, 0x08, 0x08, 0x08, 0x08},
  {0x00, 0x60, 0x60, 0x00, 0x00},
  {0x20, 0x10, 0x08, 0x04, 0x02},
  {0x3E, 0x51, 0x49, 0x45, 0x3E},
  {0x00, 0x42, 0x7F, 0x40, 0x00},
  {0x42, 0x61, 0x51, 0x49, 0x46},
  {0x21, 0x41, 0x45, 0x4B, 0x31},
  {0x18, 0x14, 0x12, 0x7F, 0x10},
  {0x27, 0x45, 0x45, 0x45, 0x39},
  {0x3C, 0x4A, 0x49, 0x49, 0x30},
  {0x01, 0x71, 0x09, 0x05, 0x03},
  {0x36, 0x49, 0x49, 0x49, 0x36},
  {0x06, 0x49, 0x49, 0x29, 0x1E},
  {0x00, 0x36, 0x36, 0x00, 0x00},
  {0x00, 0x56, 0x36, 0x00, 0x00},
  {0x08, 0x14, 0x22, 0x41, 0x00},
  {0x14, 0x14, 0x14, 0x14, 0x14},
  {0x00, 0x41, 0x22, 0x14, 0x08},
  {0x02, 0x01, 0x51, 0x09, 0x06},
  {0x32, 0x49, 0x79, 0x41, 0x3E},
  {0x7E, 0x11, 0x11, 0x11, 0x7E},
  {0x7F, 0x49, 0x49, 0x49, 0x36},
  {0x3E, 0x41, 0x41, 0x41, 0x22},
  {0x7F, 0x41, 0x41, 0x22, 0x1C},
  {0x7F, 0x49, 0x49, 0x49, 0x41},
  {0x7F, 0x09, 0x09, 0x09, 0x01},
  {0x3E, 0x41, 0x49, 0x49, 0x7A},
  {0x7F, 0x08, 0x08, 0x08, 0x7F},
  {0x00, 0x41, 0x7F, 0x41, 0x00},
  {0x20, 0x40, 0x41, 0x3F, 0x01},
  {0x7F, 0x08, 0x14, 0x22, 0x41},
  {0x7F, 0x40, 0x40, 0x40, 0x40},
  {0x7F, 0x02, 0x0C, 0x02, 0x7F},
  {0x7F, 0x04, 0x08, 0x10, 0x7F},
  {0x3E, 0x41, 0x41, 0x41, 0x3E},
  {0x7F, 0x09, 0x09, 0x09, 0x06},
  {0x3E, 0x41, 0x51, 0x21, 0x5E},
  {0x7F, 0x09, 0x19, 0x29, 0x46},
  {0x46, 0x49, 0x49, 0x49, 0x31},
  {0x01, 0x01, 0x7F, 0x01, 0x01},
  {0x3F, 0x40, 0x40, 0x40, 0x3F},
  {0x1F, 0x20, 0x40, 0x20, 0x1F},
  {0x3F, 0x40, 0x38, 0x40, 0x3F},
  {0x63, 0x14, 0x08, 0x14, 0x63},
  {0x07, 0x08, 0x70, 0x08, 0x07},
  {0x61, 0x51, 0x49, 0x45, 0x43},
  {0x00, 0x7F, 0x41, 0x41, 0x00},
  {0x02, 0x04, 0x08, 0x10, 0x20},
  {0x00, 0x41, 0x41, 0x7F, 0x00},
  {0x04, 0x02, 0x01, 0x02, 0x04},
  {0x40, 0x40, 0x40, 0x40, 0x40},
  {0x00, 0x01, 0x02, 0x04, 0x00},
  {0x20, 0x54, 0x54, 0x54, 0x78},
  {0x7F, 0x48, 0x44, 0x44, 0x38},
  {0x38, 0x44, 0x44, 0x44, 0x20},
  {0x38, 0x44, 0x44, 0x48, 0x7F},
  {0x38, 0x54, 0x54, 0x54, 0x18},
  {0x08, 0x7E, 0x09, 0x01, 0x02},
  {0x0C, 0x52, 0x52, 0x52, 0x3E},
  {0x7F, 0x08, 0x04, 0x04, 0x78},
  {0x00, 0x44, 0x7D, 0x40, 0x00},
  {0x20, 0x40, 0x44, 0x3D, 0x00},
  {0x7F, 0x10, 0x28, 0x44, 0x00},
  {0x00, 0x41, 0x7F, 0x40, 0x00},
  {0x7C, 0x04, 0x18, 0x04, 0x78},
  {0x7C, 0x08, 0x04, 0x04, 0x78},
  {0x38, 0x44, 0x44, 0x44, 0x38},
  {0x7C, 0x14, 0x14, 0x14, 0x08},
  {0x08, 0x14, 0x14, 0x18, 0x7C},
  {0x7C, 0x08, 0x04, 0x04, 0x08},
  {0x48, 0x54, 0x54, 0x54, 0x20},
  {0x04, 0x3F, 0x44, 0x40, 0x20},
  {0x3C, 0x40, 0x40, 0x20, 0x7C},
  {0x1C, 0x20, 0x40, 0x20, 0x1C},
  {0x3C, 0x40, 0x30, 0x40, 0x3C},
  {0x44, 0x28, 0x10, 0x28, 0x44},
  {0x0C, 0x50, 0x50, 0x50, 0x3C},
  {0x44, 0x64, 0x54, 0x4C, 0x44},
  {0x00, 0x08, 0x36, 0x41, 0x00},
  {0x00, 0x00, 0x7F, 0x00, 0x00},
  {0x00, 0x41, 0x36, 0x08, 0x00},
  {0x10, 0x08, 0x08, 0x10, 0x08},
  {0x00, 0x06, 0x09, 0x09, 0x06}
};

static const char* ui_value_to_cstr(RexValue v) {
  v = ui_resolve(v);
  static char buffers[4][64];
  static int index = 0;
  char* buf = buffers[index];
  index = (index + 1) % 4;
  if (v.tag == REX_STR) {
    return v.as.str ? v.as.str : "";
  }
  if (v.tag == REX_NUM) {
    snprintf(buf, sizeof(buffers[0]), "%.14g", v.as.num);
    return buf;
  }
  if (v.tag == REX_BOOL) {
    return v.as.boolean ? "true" : "false";
  }
  if (v.tag == REX_NIL) {
    return "nil";
  }
  snprintf(buf, sizeof(buffers[0]), "<value>");
  return buf;
}

static int ui_font_scale(void) {
  return ui.scale > 0 ? ui.scale : UI_SCALE;
}

static void ui_clear(uint32_t color);

static void ui_mark_dirty(void) {
  if (!ui.draw_enabled) {
    ui.draw_enabled = 1;
    ui_clear(ui.theme.bg);
  }
  ui.dirty = 1;
}

static int ui_clamp(int v, int lo, int hi) {
  if (v < lo) {
    return lo;
  }
  if (v > hi) {
    return hi;
  }
  return v;
}

static double ui_now_ms(void) {
  RexValue v = rex_now_ms();
  if (v.tag == REX_NUM) {
    return v.as.num;
  }
  return 0.0;
}

static int ui_key_repeat(int down, double* next_time, double now) {
  if (!down) {
    *next_time = 0.0;
    return 0;
  }
  if (*next_time == 0.0) {
    *next_time = now + UI_KEY_REPEAT_DELAY;
    return 1;
  }
  if (now >= *next_time) {
    *next_time = now + UI_KEY_REPEAT_RATE;
    return 1;
  }
  return 0;
}

static uint32_t ui_color_mix(uint32_t a, uint32_t b, float t) {
  int ar = (int)((a >> 16) & 0xFF);
  int ag = (int)((a >> 8) & 0xFF);
  int ab = (int)(a & 0xFF);
  int br = (int)((b >> 16) & 0xFF);
  int bg = (int)((b >> 8) & 0xFF);
  int bb = (int)(b & 0xFF);
  int r = ar + (int)((br - ar) * t);
  int g = ag + (int)((bg - ag) * t);
  int bch = ab + (int)((bb - ab) * t);
  return 0xFF000000u | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)bch;
}

static uint32_t ui_color_disabled(uint32_t color) {
  return ui_color_mix(color, ui.theme.bg, 0.5f);
}

static uint32_t ui_apply_invert(uint32_t color) {
  if (!ui.invert) {
    return color;
  }
  return (color & 0xFF000000u) | (~color & 0x00FFFFFFu);
}

static int ui_hex_value(char c) {
  if (c >= '0' && c <= '9') {
    return c - '0';
  }
  if (c >= 'a' && c <= 'f') {
    return 10 + (c - 'a');
  }
  if (c >= 'A' && c <= 'F') {
    return 10 + (c - 'A');
  }
  return -1;
}

static uint32_t ui_color_from_value(RexValue v, uint32_t fallback) {
  v = ui_resolve(v);
  if (v.tag == REX_NUM) {
    uint32_t c = (uint32_t)v.as.num;
    if ((c & 0xFF000000u) == 0) {
      c |= 0xFF000000u;
    }
    return c;
  }
  if (v.tag == REX_STR && v.as.str) {
    const char* s = v.as.str;
    if (s[0] == '#') {
      s++;
    }
    size_t len = strlen(s);
    if (len == 6 || len == 8) {
      uint32_t c = 0;
      for (size_t i = 0; i < len; i++) {
        int vhex = ui_hex_value(s[i]);
        if (vhex < 0) {
          return fallback;
        }
        c = (c << 4) | (uint32_t)vhex;
      }
      if (len == 6) {
        c |= 0xFF000000u;
      }
      return c;
    }
  }
  return fallback;
}

static void ui_push_clip(RexUIRect r) {
  RexUIRect current = ui.clip;
  RexUIRect next;
  next.x = r.x > current.x ? r.x : current.x;
  next.y = r.y > current.y ? r.y : current.y;
  int r1 = r.x + r.w;
  int r2 = current.x + current.w;
  int b1 = r.y + r.h;
  int b2 = current.y + current.h;
  int right = r1 < r2 ? r1 : r2;
  int bottom = b1 < b2 ? b1 : b2;
  next.w = right - next.x;
  next.h = bottom - next.y;
  if (next.w < 0) {
    next.w = 0;
  }
  if (next.h < 0) {
    next.h = 0;
  }
  if (ui.clip_depth < UI_CLIP_STACK_MAX) {
    ui.clip_stack[ui.clip_depth++] = ui.clip;
  }
  ui.clip = next;
}

static void ui_pop_clip(void) {
  if (ui.clip_depth > 0) {
    ui.clip = ui.clip_stack[--ui.clip_depth];
  }
}

static void ui_clear(uint32_t color) {
  if (!ui.pixels || !ui.draw_enabled) {
    return;
  }
  color = ui_apply_invert(color);
  int total = ui.width * ui.height;
  for (int i = 0; i < total; i++) {
    ui.pixels[i] = color;
  }
}

static void ui_draw_rect(int x, int y, int w, int h, uint32_t color) {
  if (!ui.pixels || !ui.draw_enabled || w <= 0 || h <= 0) {
    return;
  }
  color = ui_apply_invert(color);
  int clip_x0 = ui.clip.x;
  int clip_y0 = ui.clip.y;
  int clip_x1 = ui.clip.x + ui.clip.w;
  int clip_y1 = ui.clip.y + ui.clip.h;
  int x0 = x < clip_x0 ? clip_x0 : x;
  int y0 = y < clip_y0 ? clip_y0 : y;
  int x1 = x + w;
  int y1 = y + h;
  if (x1 > clip_x1) {
    x1 = clip_x1;
  }
  if (y1 > clip_y1) {
    y1 = clip_y1;
  }
  if (x0 < 0) {
    x0 = 0;
  }
  if (y0 < 0) {
    y0 = 0;
  }
  if (x1 > ui.width) {
    x1 = ui.width;
  }
  if (y1 > ui.height) {
    y1 = ui.height;
  }
  if (x1 <= x0 || y1 <= y0) {
    return;
  }
  for (int yy = y0; yy < y1; yy++) {
    uint32_t* row = ui.pixels + yy * ui.width;
    for (int xx = x0; xx < x1; xx++) {
      row[xx] = color;
    }
  }
}

static void ui_draw_frame(RexUIRect r, uint32_t color) {
  ui_draw_rect(r.x, r.y, r.w, 1, color);
  ui_draw_rect(r.x, r.y + r.h - 1, r.w, 1, color);
  ui_draw_rect(r.x, r.y, 1, r.h, color);
  ui_draw_rect(r.x + r.w - 1, r.y, 1, r.h, color);
}

static void ui_draw_char(int x, int y, char c, uint32_t color) {
  if (c < 32 || c > 127) {
    c = '?';
  }
  const uint8_t* glyph = ui_font[c - 32];
  int scale = ui_font_scale();
  for (int col = 0; col < UI_FONT_W; col++) {
    uint8_t bits = glyph[col];
    for (int row = 0; row < UI_FONT_H; row++) {
      if (bits & (1 << row)) {
        int px = x + col * scale;
        int py = y + row * scale;
        ui_draw_rect(px, py, scale, scale, color);
      }
    }
  }
}

static int ui_text_width_n(int count) {
  if (count <= 0) {
    return 0;
  }
  int scale = ui_font_scale();
  return count * (UI_FONT_W * scale + scale);
}

static int ui_text_width(const char* text) {
  if (!text) {
    return 0;
  }
  int len = (int)strlen(text);
  return ui_text_width_n(len);
}

static int ui_text_height(void) {
  return UI_FONT_H * ui_font_scale();
}

static void ui_draw_text(int x, int y, const char* text, uint32_t color) {
  if (!text) {
    return;
  }
  int cx = x;
  int scale = ui_font_scale();
  for (const char* p = text; *p; p++) {
    ui_draw_char(cx, y, *p, color);
    cx += UI_FONT_W * scale + scale;
  }
}

static int ui_text_pos_from_x(const char* text, int x) {
  if (!text) {
    return 0;
  }
  int len = (int)strlen(text);
  int step = UI_FONT_W * ui_font_scale() + ui_font_scale();
  if (step <= 0) {
    return 0;
  }
  int pos = x / step;
  return ui_clamp(pos, 0, len);
}

static void ui_text_delete_range(char* buf, int* len, int start, int end) {
  if (!buf || !len) {
    return;
  }
  if (start > end) {
    int tmp = start;
    start = end;
    end = tmp;
  }
  start = ui_clamp(start, 0, *len);
  end = ui_clamp(end, 0, *len);
  if (start >= end) {
    return;
  }
  memmove(buf + start, buf + end, (size_t)(*len - end) + 1);
  *len -= (end - start);
}

static void ui_text_insert(char* buf, int* len, int pos, const char* text, int text_len) {
  if (!buf || !len || !text || text_len <= 0) {
    return;
  }
  pos = ui_clamp(pos, 0, *len);
  int space = (UI_TEXT_MAX - 1) - *len;
  if (space <= 0) {
    return;
  }
  if (text_len > space) {
    text_len = space;
  }
  memmove(buf + pos + text_len, buf + pos, (size_t)(*len - pos) + 1);
  memcpy(buf + pos, text, (size_t)text_len);
  *len += text_len;
}

static int ui_has_selection(void) {
  return ui.text_sel_start != ui.text_sel_end;
}

static void ui_clear_selection(void) {
  ui.text_sel_start = ui.text_cursor;
  ui.text_sel_end = ui.text_cursor;
}

static int ui_scroll_get(int id) {
  for (int i = 0; i < ui.scroll_count; i++) {
    if (ui.scrolls[i].id == id) {
      return ui.scrolls[i].offset;
    }
  }
  if (ui.scroll_count < UI_SCROLL_MAX) {
    ui.scrolls[ui.scroll_count].id = id;
    ui.scrolls[ui.scroll_count].offset = 0;
    ui.scroll_count += 1;
  }
  return 0;
}

static void ui_scroll_set(int id, int offset) {
  for (int i = 0; i < ui.scroll_count; i++) {
    if (ui.scrolls[i].id == id) {
      ui.scrolls[i].offset = offset;
      return;
    }
  }
  if (ui.scroll_count < UI_SCROLL_MAX) {
    ui.scrolls[ui.scroll_count].id = id;
    ui.scrolls[ui.scroll_count].offset = offset;
    ui.scroll_count += 1;
  }
}

static void ui_clipboard_set(const char* text) {
  if (!text) {
    text = "";
  }
  size_t len = strlen(text);
  if (len >= UI_TEXT_MAX) {
    len = UI_TEXT_MAX - 1;
  }
  memcpy(ui_clipboard, text, len);
  ui_clipboard[len] = '\0';
  rex_ui_platform_set_clipboard(ui_clipboard);
}

static const char* ui_clipboard_get(void) {
  static char buf[UI_TEXT_MAX];
  int len = rex_ui_platform_get_clipboard(buf, (int)sizeof(buf));
  if (len > 0) {
    if (len >= (int)sizeof(buf)) {
      len = (int)sizeof(buf) - 1;
    }
    buf[len] = '\0';
    return buf;
  }
  return ui_clipboard;
}

static int ui_next_id(void) {
  int id = ui.next_id;
  ui.next_id += 1;
  return id;
}

static int ui_rect_contains(RexUIRect r, int x, int y) {
  if (x < ui.clip.x || x >= (ui.clip.x + ui.clip.w)) {
    return 0;
  }
  if (y < ui.clip.y || y >= (ui.clip.y + ui.clip.h)) {
    return 0;
  }
  return x >= r.x && x < (r.x + r.w) && y >= r.y && y < (r.y + r.h);
}

static RexUIRect ui_next_rect(int w, int h) {
  int content_w = ui.content_w;
  if (content_w < 0) {
    content_w = 0;
  }
  RexUIRect r;
  r.w = w > 0 ? w : content_w;
  r.h = h > 0 ? h : ui.item_height;
  if (ui.layout_mode == UI_LAYOUT_ROW) {
    if (ui.cursor_x + r.w > ui.content_x + content_w) {
      ui.cursor_x = ui.content_x;
      ui.cursor_y += ui.row_height + ui.spacing;
    }
    r.x = ui.cursor_x;
    r.y = ui.cursor_y;
    r.h = ui.row_height > 0 ? ui.row_height : r.h;
    ui.cursor_x += r.w + ui.spacing;
    return r;
  }
  if (ui.layout_mode == UI_LAYOUT_GRID) {
    int col = ui.grid_index % ui.grid_cols;
    int row = ui.grid_index / ui.grid_cols;
    r.w = ui.grid_cell_w;
    r.h = ui.grid_cell_h;
    r.x = ui.grid_origin_x + col * (ui.grid_cell_w + ui.spacing);
    r.y = ui.grid_origin_y + row * (ui.grid_cell_h + ui.spacing);
    ui.grid_index += 1;
    return r;
  }
  r.x = ui.content_x;
  r.y = ui.cursor_y;
  ui.cursor_y += r.h + ui.spacing;
  return r;
}

static int ui_register_focusable(int id) {
  if (!ui.enabled) {
    return 0;
  }
  if (ui.focus_first == 0) {
    ui.focus_first = id;
  }
  ui.focus_last = id;
  if (ui.focus_request > 0 && !ui.focus_moved && id > ui.focus_id) {
    ui.focus_id = id;
    ui.focus_moved = 1;
    ui_mark_dirty();
  }
  if (ui.focus_request < 0 && id < ui.focus_id) {
    ui.focus_prev = id;
  }
  return ui.focus_id == id;
}

static void ui_set_focus(int id) {
  if (ui.focus_id != id) {
    ui.focus_id = id;
    ui_mark_dirty();
  }
  ui.focus_set = 1;
}

static void ui_resize_if_needed(int width, int height) {
  if (width <= 0 || height <= 0) {
    return;
  }
  if (ui.width != width || ui.height != height || !ui.pixels) {
    free(ui.pixels);
    ui.width = width;
    ui.height = height;
    ui.pixels = (uint32_t*)malloc((size_t)width * (size_t)height * sizeof(uint32_t));
    if (!ui.pixels) {
      rex_panic("ui out of memory");
      ui.running = 0;
      return;
    }
    ui_mark_dirty();
  }
}

static void ui_begin_frame(const char* title, int width, int height) {
  if (!ui.running) {
    ui.running = rex_ui_platform_init(title, width, height);
    ui.theme = ui_theme_dark;
    ui.enabled = 1;
    ui.dpi_scale = 1.0f;
    ui.scale = UI_SCALE;
    ui.spacing = 6;
    ui.padding = 12;
    ui.item_height = ui_text_height() + 10;
    ui.row_height = ui.item_height;
    ui.combo_open_id = 0;
  }
  if (!ui.running) {
    return;
  }
  if (ui.width == 0 || ui.height == 0) {
    ui_resize_if_needed(width, height);
  }
}

static void ui_start_frame(void) {
  ui.next_id = 1;
  ui.hot_id = 0;
  ui.focus_first = 0;
  ui.focus_last = 0;
  ui.focus_prev = 0;
  ui.focus_moved = 0;
  ui.focus_set = 0;
  ui.layout_mode = UI_LAYOUT_COLUMN;
  ui.content_x = ui.padding;
  ui.content_w = ui.width - ui.padding * 2;
  if (ui.content_w < 0) {
    ui.content_w = 0;
  }
  ui.cursor_x = ui.content_x;
  ui.cursor_y = ui.padding;
  ui.grid_index = 0;
  ui.grid_origin_x = ui.content_x;
  ui.grid_origin_y = ui.cursor_y;
  ui.clip.x = 0;
  ui.clip.y = 0;
  ui.clip.w = ui.width;
  ui.clip.h = ui.height;
  ui.clip_depth = 0;
  ui.layout_depth = 0;
  ui.draw_enabled = ui.dirty;
  if (ui.draw_enabled) {
    ui_clear(ui.theme.bg);
  }
}

static void ui_end_frame(void) {
  if (!ui.running) {
    return;
  }
  if (ui.focus_request != 0) {
    if (ui.focus_request > 0) {
      if (!ui.focus_moved) {
        ui.focus_id = ui.focus_first;
      }
    } else {
      if (ui.focus_prev != 0) {
        ui.focus_id = ui.focus_prev;
      } else {
        ui.focus_id = ui.focus_last;
      }
    }
    ui.focus_request = 0;
  }
  if (ui.mouse_pressed && !ui.focus_set) {
    if (ui.focus_id != 0) {
      ui.focus_id = 0;
      ui_mark_dirty();
    }
  }
  if (ui.text_focus_id != ui.focus_id) {
    ui.text_focus_id = 0;
    ui.text_dragging = 0;
    ui.text_sel_start = 0;
    ui.text_sel_end = 0;
  }
  if (ui.draw_enabled) {
    rex_ui_platform_present(ui.pixels, ui.width, ui.height);
  }

}

static int ui_poll_input(void) {
  RexUIPlatformInput input;
  memset(&input, 0, sizeof(input));
  int ok = rex_ui_platform_poll(&input);
  if (!ok || input.closed) {
    rex_ui_platform_shutdown();
    ui.running = 0;
    free(ui.pixels);
    ui.pixels = NULL;
    return 0;
  }
  ui.dirty = 0;
  if (input.width > 0 && input.height > 0) {
    if (input.width != ui.width || input.height != ui.height) {
      ui_resize_if_needed(input.width, input.height);
      ui.dirty = 1;
    }
  }
  if (input.dpi_scale > 0.0f && ui.dpi_scale != input.dpi_scale) {
    ui.dpi_scale = input.dpi_scale;
    int scale = (int)(UI_SCALE * ui.dpi_scale + 0.5f);
    if (scale < 1) {
      scale = 1;
    }
    if (ui.scale != scale) {
      ui.scale = scale;
      ui.dirty = 1;
    }
  }
  if (input.scroll_y != 0) {
    ui.dirty = 1;
  }
  if (input.redraw) {
    ui.dirty = 1;
  }
  if (input.mouse_x != ui.mouse_x || input.mouse_y != ui.mouse_y) {
    ui.dirty = 1;
  }
  ui.mouse_x = input.mouse_x;
  ui.mouse_y = input.mouse_y;
  ui.mouse_down = input.mouse_down;
  ui.mouse_pressed = (!ui.prev_mouse_down && ui.mouse_down);
  ui.mouse_released = (ui.prev_mouse_down && !ui.mouse_down);
  ui.prev_mouse_down = ui.mouse_down;
  if (ui.mouse_pressed || ui.mouse_released) {
    ui.dirty = 1;
  }
  ui.scroll_y = input.scroll_y;
  ui.key_tab_down = input.key_tab;
  ui.key_enter_down = input.key_enter;
  ui.key_space_down = input.key_space;
  ui.key_up_down = input.key_up;
  ui.key_down_down = input.key_down;
  ui.key_backspace_down = input.key_backspace;
  ui.key_delete_down = input.key_delete;
  ui.key_left_down = input.key_left;
  ui.key_right_down = input.key_right;
  ui.key_home_down = input.key_home;
  ui.key_end_down = input.key_end;
  ui.key_ctrl = input.key_ctrl;
  ui.key_shift = input.key_shift;
  double now = ui_now_ms();
  ui.key_tab = ui.key_tab_down && !ui.key_tab_prev;
  ui.key_enter = ui.key_enter_down && !ui.key_enter_prev;
  ui.key_space = ui.key_space_down && !ui.key_space_prev;
  ui.key_home = ui.key_home_down && !ui.key_home_prev;
  ui.key_end = ui.key_end_down && !ui.key_end_prev;
  ui.key_up = ui.key_up_down;
  ui.key_down = ui.key_down_down;
  ui.key_left = ui_key_repeat(ui.key_left_down, &ui.key_left_next, now);
  ui.key_right = ui_key_repeat(ui.key_right_down, &ui.key_right_next, now);
  ui.key_backspace = ui_key_repeat(ui.key_backspace_down, &ui.key_backspace_next, now);
  ui.key_delete = ui_key_repeat(ui.key_delete_down, &ui.key_delete_next, now);
  ui.key_tab_prev = ui.key_tab_down;
  ui.key_enter_prev = ui.key_enter_down;
  ui.key_space_prev = ui.key_space_down;
  ui.key_home_prev = ui.key_home_down;
  ui.key_end_prev = ui.key_end_down;
  ui.key_copy = input.key_copy;
  ui.key_paste = input.key_paste;
  ui.key_cut = input.key_cut;
  ui.key_select_all = input.key_select_all;
  if (ui.key_tab || ui.key_enter || ui.key_space || ui.key_up || ui.key_down || ui.key_backspace || ui.key_delete || ui.key_left || ui.key_right || ui.key_home || ui.key_end || ui.key_copy || ui.key_paste || ui.key_cut || ui.key_select_all) {
    ui.dirty = 1;
  }
  ui.text_len = input.text_len;
  if (ui.text_len > 0) {
    if (ui.text_len > (int)sizeof(ui.text)) {
      ui.text_len = (int)sizeof(ui.text);
    }
    memcpy(ui.text, input.text, (size_t)ui.text_len);
    ui.dirty = 1;
  }
  if (ui.key_tab) {
    ui.focus_request = ui.key_shift ? -1 : 1;
  } else {
    ui.focus_request = 0;
  }
  ui.item_height = ui_text_height() + 10 * ui_font_scale() / UI_SCALE;
  ui.row_height = ui.item_height;
  return 1;
}

static void ui_draw_image(RexUIImage* img, int x, int y) {
  if (!img || !ui.pixels || !ui.draw_enabled) {
    return;
  }
  int iw = img->w;
  int ih = img->h;
  if (iw <= 0 || ih <= 0) {
    return;
  }

  RexUIRect clip = ui.clip;
  int x0 = x;
  int y0 = y;
  int x1 = x + iw;
  int y1 = y + ih;

  int clip_x1 = clip.x + clip.w;
  int clip_y1 = clip.y + clip.h;
  if (x0 < clip.x) {
    x0 = clip.x;
  }
  if (y0 < clip.y) {
    y0 = clip.y;
  }
  if (x1 > clip_x1) {
    x1 = clip_x1;
  }
  if (y1 > clip_y1) {
    y1 = clip_y1;
  }
  if (x0 < 0) {
    x0 = 0;
  }
  if (y0 < 0) {
    y0 = 0;
  }
  if (x1 > ui.width) {
    x1 = ui.width;
  }
  if (y1 > ui.height) {
    y1 = ui.height;
  }
  if (x1 <= x0 || y1 <= y0) {
    return;
  }

  int sx0 = x0 - x;
  int sy0 = y0 - y;
  int w = x1 - x0;
  int h = y1 - y0;

  for (int yy = 0; yy < h; yy++) {
    uint32_t* dst = ui.pixels + (y0 + yy) * ui.width + x0;
    uint32_t* src = img->pixels + (sy0 + yy) * iw + sx0;
    for (int xx = 0; xx < w; xx++) {
      uint32_t s = src[xx];
      if (ui.invert) {
        s = (s & 0xFF000000u) | (~s & 0x00FFFFFFu);
      }
      uint32_t a = (s >> 24) & 0xFFu;
      if (a == 0) {
        continue;
      }
      if (a == 255) {
        dst[xx] = s;
        continue;
      }
      uint32_t d = dst[xx];
      uint32_t sr = (s >> 16) & 0xFFu;
      uint32_t sg = (s >> 8) & 0xFFu;
      uint32_t sb = s & 0xFFu;
      uint32_t dr = (d >> 16) & 0xFFu;
      uint32_t dg = (d >> 8) & 0xFFu;
      uint32_t db = d & 0xFFu;
      uint32_t inv = 255u - a;
      uint32_t r = (sr * a + dr * inv) / 255u;
      uint32_t g = (sg * a + dg * inv) / 255u;
      uint32_t b = (sb * a + db * inv) / 255u;
      dst[xx] = 0xFF000000u | (r << 16) | (g << 8) | b;
    }
  }
}

static void ui_draw_image_region(RexUIImage* img, int sx, int sy, int sw, int sh, int x, int y, int w, int h) {
  if (!img || !ui.pixels || !ui.draw_enabled) {
    return;
  }
  if (sw <= 0 || sh <= 0 || w <= 0 || h <= 0) {
    return;
  }

  RexUIRect clip = ui.clip;
  int x0 = x;
  int y0 = y;
  int x1 = x + w;
  int y1 = y + h;

  int clip_x1 = clip.x + clip.w;
  int clip_y1 = clip.y + clip.h;
  if (x0 < clip.x) {
    x0 = clip.x;
  }
  if (y0 < clip.y) {
    y0 = clip.y;
  }
  if (x1 > clip_x1) {
    x1 = clip_x1;
  }
  if (y1 > clip_y1) {
    y1 = clip_y1;
  }
  if (x0 < 0) {
    x0 = 0;
  }
  if (y0 < 0) {
    y0 = 0;
  }
  if (x1 > ui.width) {
    x1 = ui.width;
  }
  if (y1 > ui.height) {
    y1 = ui.height;
  }
  if (x1 <= x0 || y1 <= y0) {
    return;
  }

  int64_t step_x = ((int64_t)sw << 16) / w;
  int64_t step_y = ((int64_t)sh << 16) / h;
  int64_t src_y_fixed = (int64_t)(y0 - y) * step_y;
  for (int yy = y0; yy < y1; yy++) {
    int src_y = sy + (int)(src_y_fixed >> 16);
    src_y_fixed += step_y;
    if (src_y < 0 || src_y >= img->h) {
      continue;
    }
    uint32_t* dst = ui.pixels + yy * ui.width + x0;
    int64_t src_x_fixed = (int64_t)(x0 - x) * step_x;
    for (int xx = x0; xx < x1; xx++) {
      int src_x = sx + (int)(src_x_fixed >> 16);
      src_x_fixed += step_x;
      if (src_x < 0 || src_x >= img->w) {
        continue;
      }
      uint32_t s = img->pixels[src_y * img->w + src_x];
      if (ui.invert) {
        s = (s & 0xFF000000u) | (~s & 0x00FFFFFFu);
      }
      uint32_t a = (s >> 24) & 0xFFu;
      if (a == 0) {
        continue;
      }
      if (a == 255) {
        dst[xx - x0] = s;
        continue;
      }
      uint32_t d = dst[xx - x0];
      uint32_t sr = (s >> 16) & 0xFFu;
      uint32_t sg = (s >> 8) & 0xFFu;
      uint32_t sb = s & 0xFFu;
      uint32_t dr = (d >> 16) & 0xFFu;
      uint32_t dg = (d >> 8) & 0xFFu;
      uint32_t db = d & 0xFFu;
      uint32_t inv = 255u - a;
      uint32_t r = (sr * a + dr * inv) / 255u;
      uint32_t g = (sg * a + dg * inv) / 255u;
      uint32_t b = (sb * a + db * inv) / 255u;
      dst[xx - x0] = 0xFF000000u | (r << 16) | (g << 8) | b;
    }
  }
}

RexValue rex_ui_begin(RexValue title, RexValue width, RexValue height) {
  title = ui_resolve(title);
  width = ui_resolve(width);
  height = ui_resolve(height);
  if (title.tag != REX_STR || width.tag != REX_NUM || height.tag != REX_NUM) {
    rex_panic("ui.begin expects (string, number, number)");
    return rex_bool(0);
  }
  int w = (int)width.as.num;
  int h = (int)height.as.num;
  if (w <= 0 || h <= 0) {
    rex_panic("ui.begin expects positive size");
    return rex_bool(0);
  }
  ui_begin_frame(title.as.str ? title.as.str : "Rex", w, h);
  if (!ui.running) {
    return rex_bool(0);
  }
  if (!ui_poll_input()) {
    return rex_bool(0);
  }
  ui_start_frame();
  return rex_bool(1);
}

RexValue rex_ui_end(void) {
  ui_end_frame();
  return rex_nil();
}

RexValue rex_ui_redraw(void) {
  ui_mark_dirty();
  return rex_nil();
}

RexValue rex_ui_clear(RexValue color) {
  uint32_t c = ui_color_from_value(color, ui.theme.bg);
  ui_mark_dirty();
  ui_clear(c);
  return rex_nil();
}

RexValue rex_ui_key_space(void) {
  return rex_bool(ui.key_space != 0);
}

RexValue rex_ui_key_up(void) {
  return rex_bool(ui.key_up != 0);
}

RexValue rex_ui_key_down(void) {
  return rex_bool(ui.key_down != 0);
}

RexValue rex_ui_mouse_x(void) {
  return rex_num((double)ui.mouse_x);
}

RexValue rex_ui_mouse_y(void) {
  return rex_num((double)ui.mouse_y);
}

RexValue rex_ui_mouse_down(void) {
  return rex_bool(ui.mouse_down != 0);
}

RexValue rex_ui_mouse_pressed(void) {
  return rex_bool(ui.mouse_pressed != 0);
}

RexValue rex_ui_mouse_released(void) {
  return rex_bool(ui.mouse_released != 0);
}

RexValue rex_ui_label(RexValue text) {
  text = ui_resolve(text);
  const char* t = ui_value_to_cstr(text);
  int w = (ui.layout_mode == UI_LAYOUT_COLUMN) ? 0 : ui_text_width(t) + ui.padding;
  RexUIRect r = ui_next_rect(w, ui.item_height);
  int ty = r.y + (r.h - ui_text_height()) / 2;
  uint32_t color = ui.enabled ? ui.theme.text : ui.theme.muted;
  ui_draw_text(r.x, ty, t, color);
  return rex_nil();
}

RexValue rex_ui_text(RexValue x, RexValue y, RexValue text, RexValue color) {
  x = ui_resolve(x);
  y = ui_resolve(y);
  const char* t = ui_value_to_cstr(text);
  uint32_t c = ui_color_from_value(color, ui.theme.text);
  if (x.tag != REX_NUM || y.tag != REX_NUM) {
    rex_panic("ui.text expects (number, number, value, color)");
    return rex_nil();
  }
  ui_draw_text((int)x.as.num, (int)y.as.num, t, c);
  return rex_nil();
}

RexValue rex_ui_button(RexValue label) {
  label = ui_resolve(label);
  const char* t = ui_value_to_cstr(label);
  int w = ui_text_width(t) + ui.padding * 2;
  if (w < 80) {
    w = 80;
  }
  RexUIRect r = ui_next_rect(w, ui.item_height);
  int id = ui_next_id();
  int focused = ui_register_focusable(id);
  int hot = ui.enabled && ui_rect_contains(r, ui.mouse_x, ui.mouse_y);
  if (hot) {
    ui.hot_id = id;
    if (ui.mouse_pressed) {
      ui.active_id = id;
      ui_set_focus(id);
    }
  }
  int clicked = 0;
  if (ui.enabled) {
    if (ui.mouse_released && ui.active_id == id) {
      if (hot) {
        clicked = 1;
      }
      ui.active_id = 0;
    }
    if (focused && ui.key_enter) {
      clicked = 1;
    }
  }
  if (clicked) {
    ui_mark_dirty();
  }
  uint32_t color = ui.theme.button;
  if (!ui.enabled) {
    color = ui_color_disabled(color);
  } else if (ui.active_id == id) {
    color = ui.theme.button_active;
  } else if (hot) {
    color = ui.theme.button_hover;
  }
  ui_draw_rect(r.x, r.y, r.w, r.h, color);
  int tx = r.x + (r.w - ui_text_width(t)) / 2;
  int ty = r.y + (r.h - ui_text_height()) / 2;
  ui_draw_text(tx, ty, t, ui.enabled ? ui.theme.text : ui.theme.muted);
  if (focused) {
    ui_draw_frame(r, ui.theme.accent);
  }
  return rex_bool(clicked);
}

RexValue rex_ui_checkbox(RexValue label, RexValue checked) {
  label = ui_resolve(label);
  checked = ui_resolve(checked);
  const char* t = ui_value_to_cstr(label);
  int box = ui_text_height();
  int w = box + ui.spacing + ui_text_width(t) + ui.padding;
  RexUIRect r = ui_next_rect(w, ui.item_height);
  RexUIRect box_r = { r.x, r.y + (r.h - box) / 2, box, box };
  int id = ui_next_id();
  int focused = ui_register_focusable(id);
  int hot = ui.enabled && ui_rect_contains(r, ui.mouse_x, ui.mouse_y);
  if (hot) {
    ui.hot_id = id;
    if (ui.mouse_pressed) {
      ui.active_id = id;
      ui_set_focus(id);
    }
  }
  int value = checked.tag == REX_BOOL && checked.as.boolean;
  if (ui.enabled) {
    if (ui.mouse_released && ui.active_id == id) {
      if (hot) {
        value = !value;
        ui_mark_dirty();
      }
      ui.active_id = 0;
    }
    if (focused && ui.key_enter) {
      value = !value;
      ui_mark_dirty();
    }
  }
  uint32_t box_color = ui.enabled ? ui.theme.button : ui_color_disabled(ui.theme.button);
  ui_draw_rect(box_r.x, box_r.y, box_r.w, box_r.h, box_color);
  if (value) {
    ui_draw_rect(box_r.x + 4, box_r.y + 4, box_r.w - 8, box_r.h - 8, ui.theme.accent);
  }
  ui_draw_text(box_r.x + box_r.w + ui.spacing, r.y + (r.h - ui_text_height()) / 2, t, ui.enabled ? ui.theme.text : ui.theme.muted);
  if (focused) {
    ui_draw_frame(r, ui.theme.accent);
  }
  return rex_bool(value);
}

RexValue rex_ui_radio(RexValue label, RexValue active) {
  label = ui_resolve(label);
  active = ui_resolve(active);
  const char* t = ui_value_to_cstr(label);
  int box = ui_text_height();
  int w = box + ui.spacing + ui_text_width(t) + ui.padding;
  RexUIRect r = ui_next_rect(w, ui.item_height);
  RexUIRect box_r = { r.x, r.y + (r.h - box) / 2, box, box };
  int id = ui_next_id();
  int focused = ui_register_focusable(id);
  int hot = ui.enabled && ui_rect_contains(r, ui.mouse_x, ui.mouse_y);
  if (hot) {
    ui.hot_id = id;
    if (ui.mouse_pressed) {
      ui.active_id = id;
      ui_set_focus(id);
    }
  }
  int value = active.tag == REX_BOOL && active.as.boolean;
  if (ui.enabled) {
    if (ui.mouse_released && ui.active_id == id) {
      if (hot) {
        value = 1;
        ui_mark_dirty();
      }
      ui.active_id = 0;
    }
    if (focused && ui.key_enter) {
      value = 1;
      ui_mark_dirty();
    }
  }
  uint32_t box_color = ui.enabled ? ui.theme.button : ui_color_disabled(ui.theme.button);
  ui_draw_rect(box_r.x, box_r.y, box_r.w, box_r.h, box_color);
  if (value) {
    ui_draw_rect(box_r.x + 4, box_r.y + 4, box_r.w - 8, box_r.h - 8, ui.theme.accent);
  }
  ui_draw_text(box_r.x + box_r.w + ui.spacing, r.y + (r.h - ui_text_height()) / 2, t, ui.enabled ? ui.theme.text : ui.theme.muted);
  if (focused) {
    ui_draw_frame(r, ui.theme.accent);
  }
  return rex_bool(value);
}

RexValue rex_ui_textbox(RexValue value, RexValue width) {
  value = ui_resolve(value);
  width = ui_resolve(width);
  if (value.tag != REX_STR) {
    rex_panic("ui.textbox expects string");
    return value;
  }
  int w = 0;
  if (width.tag == REX_NUM) {
    w = (int)width.as.num;
  }
  if (w <= 0) {
    w = 200;
  }
  RexUIRect r = ui_next_rect(w, ui.item_height);
  int id = ui_next_id();
  int focused = ui_register_focusable(id);
  int hot = ui.enabled && ui_rect_contains(r, ui.mouse_x, ui.mouse_y);
  if (hot && ui.mouse_pressed) {
    ui.active_id = id;
    ui_set_focus(id);
  }

  char buf[UI_TEXT_MAX];
  int len = 0;
  if (value.as.str) {
    len = (int)strlen(value.as.str);
    if (len >= UI_TEXT_MAX) {
      len = UI_TEXT_MAX - 1;
    }
    memcpy(buf, value.as.str, (size_t)len);
  }
  buf[len] = '\0';

  int changed = 0;
  int inner_pad = 6 * ui_font_scale() / UI_SCALE;
  if (inner_pad < 4) {
    inner_pad = 4;
  }
  if (ui.focus_id == id && ui.enabled) {
    if (ui.text_focus_id != id) {
      ui.text_focus_id = id;
      ui.text_cursor = len;
      ui.text_sel_start = ui.text_cursor;
      ui.text_sel_end = ui.text_cursor;
      ui.text_dragging = 0;
      ui.text_scroll_x = 0;
    }
    ui.text_cursor = ui_clamp(ui.text_cursor, 0, len);

    if (hot && ui.mouse_pressed) {
      int rel_x = ui.mouse_x - (r.x + inner_pad) + ui.text_scroll_x;
      int pos = ui_text_pos_from_x(buf, rel_x);
      ui.text_cursor = pos;
      ui.text_sel_start = pos;
      ui.text_sel_end = pos;
      ui.text_dragging = 1;
    }
    if (ui.text_dragging) {
      if (ui.mouse_down) {
        int rel_x = ui.mouse_x - (r.x + inner_pad) + ui.text_scroll_x;
        int pos = ui_text_pos_from_x(buf, rel_x);
        ui.text_cursor = pos;
        ui.text_sel_end = pos;
      } else {
        ui.text_dragging = 0;
      }
    }

    if (ui.key_select_all) {
      ui.text_sel_start = 0;
      ui.text_sel_end = len;
      ui.text_cursor = len;
    }
    if (ui.key_copy && ui_has_selection()) {
      int s = ui.text_sel_start;
      int e = ui.text_sel_end;
      if (s > e) {
        int tmp = s;
        s = e;
        e = tmp;
      }
      int sel_len = e - s;
      if (sel_len > 0) {
        char tmp[UI_TEXT_MAX];
        if (sel_len >= (int)sizeof(tmp)) {
          sel_len = (int)sizeof(tmp) - 1;
        }
        memcpy(tmp, buf + s, (size_t)sel_len);
        tmp[sel_len] = '\0';
        ui_clipboard_set(tmp);
      }
    }
    if (ui.key_cut && ui_has_selection()) {
      int s = ui.text_sel_start;
      int e = ui.text_sel_end;
      if (s > e) {
        int tmp = s;
        s = e;
        e = tmp;
      }
      int sel_len = e - s;
      if (sel_len > 0) {
        char tmp[UI_TEXT_MAX];
        if (sel_len >= (int)sizeof(tmp)) {
          sel_len = (int)sizeof(tmp) - 1;
        }
        memcpy(tmp, buf + s, (size_t)sel_len);
        tmp[sel_len] = '\0';
        ui_clipboard_set(tmp);
        ui_text_delete_range(buf, &len, s, e);
        ui.text_cursor = s;
        ui_clear_selection();
        changed = 1;
      }
    }
    if (ui.key_paste) {
      const char* clip = ui_clipboard_get();
      if (clip && clip[0]) {
        if (ui_has_selection()) {
          ui_text_delete_range(buf, &len, ui.text_sel_start, ui.text_sel_end);
          ui.text_cursor = ui.text_sel_start < ui.text_sel_end ? ui.text_sel_start : ui.text_sel_end;
          ui_clear_selection();
        }
        ui_text_insert(buf, &len, ui.text_cursor, clip, (int)strlen(clip));
        ui.text_cursor += (int)strlen(clip);
        ui_clear_selection();
        changed = 1;
      }
    }
    if (ui.key_backspace) {
      if (ui_has_selection()) {
        ui_text_delete_range(buf, &len, ui.text_sel_start, ui.text_sel_end);
        ui.text_cursor = ui.text_sel_start < ui.text_sel_end ? ui.text_sel_start : ui.text_sel_end;
        ui_clear_selection();
        changed = 1;
      } else if (ui.text_cursor > 0) {
        ui_text_delete_range(buf, &len, ui.text_cursor - 1, ui.text_cursor);
        ui.text_cursor -= 1;
        ui_clear_selection();
        changed = 1;
      }
    }
    if (ui.key_delete) {
      if (ui_has_selection()) {
        ui_text_delete_range(buf, &len, ui.text_sel_start, ui.text_sel_end);
        ui.text_cursor = ui.text_sel_start < ui.text_sel_end ? ui.text_sel_start : ui.text_sel_end;
        ui_clear_selection();
        changed = 1;
      } else if (ui.text_cursor < len) {
        ui_text_delete_range(buf, &len, ui.text_cursor, ui.text_cursor + 1);
        ui_clear_selection();
        changed = 1;
      }
    }
    if (ui.key_left) {
      if (ui.text_cursor > 0) {
        ui.text_cursor -= 1;
      }
      if (ui.key_shift) {
        ui.text_sel_end = ui.text_cursor;
      } else {
        ui_clear_selection();
      }
    }
    if (ui.key_right) {
      if (ui.text_cursor < len) {
        ui.text_cursor += 1;
      }
      if (ui.key_shift) {
        ui.text_sel_end = ui.text_cursor;
      } else {
        ui_clear_selection();
      }
    }
    if (ui.key_home) {
      ui.text_cursor = 0;
      if (ui.key_shift) {
        ui.text_sel_end = ui.text_cursor;
      } else {
        ui_clear_selection();
      }
    }
    if (ui.key_end) {
      ui.text_cursor = len;
      if (ui.key_shift) {
        ui.text_sel_end = ui.text_cursor;
      } else {
        ui_clear_selection();
      }
    }

    if (ui.text_len > 0) {
      if (ui_has_selection()) {
        ui_text_delete_range(buf, &len, ui.text_sel_start, ui.text_sel_end);
        ui.text_cursor = ui.text_sel_start < ui.text_sel_end ? ui.text_sel_start : ui.text_sel_end;
        ui_clear_selection();
      }
      for (int i = 0; i < ui.text_len; i++) {
        char ch = ui.text[i];
        if (isprint((unsigned char)ch)) {
          ui_text_insert(buf, &len, ui.text_cursor, &ch, 1);
          ui.text_cursor += 1;
          changed = 1;
        }
      }
      ui_clear_selection();
    }
  }

  uint32_t bg = ui.enabled ? ui.theme.panel : ui_color_disabled(ui.theme.panel);
  uint32_t border = ui.enabled ? ui.theme.button : ui_color_disabled(ui.theme.button);
  ui_draw_rect(r.x, r.y, r.w, r.h, bg);
  ui_draw_frame(r, border);
  if (focused) {
    ui_draw_frame(r, ui.theme.accent);
  }
  int text_x = r.x + inner_pad;
  int text_y = r.y + (r.h - ui_text_height()) / 2;
  int visible_w = r.w - inner_pad * 2;
  if (visible_w < 0) {
    visible_w = 0;
  }
  int cursor_px = ui_text_width_n(ui.text_cursor);
  if (ui.text_focus_id == id) {
    if (cursor_px - ui.text_scroll_x > visible_w) {
      ui.text_scroll_x = cursor_px - visible_w;
    } else if (cursor_px - ui.text_scroll_x < 0) {
      ui.text_scroll_x = cursor_px;
    }
  } else {
    ui.text_scroll_x = 0;
  }
  RexUIRect clip = { r.x + 2, r.y + 2, r.w - 4, r.h - 4 };
  ui_push_clip(clip);
  if (ui_has_selection() && ui.text_focus_id == id) {
    int s = ui.text_sel_start;
    int e = ui.text_sel_end;
    if (s > e) {
      int tmp = s;
      s = e;
      e = tmp;
    }
    int sel_x = text_x - ui.text_scroll_x + ui_text_width_n(s);
    int sel_w = ui_text_width_n(e - s);
    ui_draw_rect(sel_x, r.y + 2, sel_w, r.h - 4, ui.theme.select);
  }
  ui_draw_text(text_x - ui.text_scroll_x, text_y, buf, ui.enabled ? ui.theme.text : ui.theme.muted);
  if (ui.text_focus_id == id) {
    int caret_x = text_x - ui.text_scroll_x + ui_text_width_n(ui.text_cursor);
    ui_draw_rect(caret_x, r.y + 4, 2, r.h - 8, ui.theme.accent);
  }
  ui_pop_clip();

  if (changed) {
    ui_mark_dirty();
  }
  if (!value.as.str || strcmp(buf, value.as.str) != 0) {
    return rex_str(buf);
  }
  return value;
}

RexValue rex_ui_slider(RexValue label, RexValue value, RexValue min, RexValue max) {
  label = ui_resolve(label);
  value = ui_resolve(value);
  min = ui_resolve(min);
  max = ui_resolve(max);
  if (value.tag != REX_NUM || min.tag != REX_NUM || max.tag != REX_NUM) {
    rex_panic("ui.slider expects (string, number, number, number)");
    return value;
  }
  double v = value.as.num;
  double minv = min.as.num;
  double maxv = max.as.num;
  if (maxv <= minv) {
    maxv = minv + 1.0;
  }
  if (v < minv) {
    v = minv;
  }
  if (v > maxv) {
    v = maxv;
  }
  const char* t = ui_value_to_cstr(label);
  RexUIRect r = ui_next_rect(0, ui.item_height);
  int id = ui_next_id();
  int focused = ui_register_focusable(id);
  int hot = ui.enabled && ui_rect_contains(r, ui.mouse_x, ui.mouse_y);
  if (hot && ui.mouse_pressed) {
    ui.active_id = id;
    ui_set_focus(id);
  }
  int changed = 0;
  int label_w = ui_text_width(t);
  int track_x = r.x + label_w + ui.spacing;
  int track_w = r.w - label_w - ui.spacing;
  if (track_w < 60) {
    track_w = 60;
  }
  int track_y = r.y + (r.h / 2) - 4;
  int track_h = 8;
  uint32_t track_color = ui.enabled ? ui.theme.button : ui_color_disabled(ui.theme.button);
  ui_draw_rect(track_x, track_y, track_w, track_h, track_color);

  double ratio = (v - minv) / (maxv - minv);
  if (ratio < 0.0) {
    ratio = 0.0;
  }
  if (ratio > 1.0) {
    ratio = 1.0;
  }
  int knob_w = 12;
  int knob_x = track_x + (int)((track_w - knob_w) * ratio);
  int knob_y = track_y - 4;
  uint32_t knob_color = ui.enabled ? ui.theme.accent : ui_color_disabled(ui.theme.accent);
  ui_draw_rect(knob_x, knob_y, knob_w, track_h + 8, knob_color);

  if (ui.enabled) {
    if (ui.active_id == id) {
      if (ui.mouse_down) {
        int mx = ui.mouse_x;
        int pos = ui_clamp(mx - track_x, 0, track_w);
        double new_ratio = (double)pos / (double)track_w;
        v = minv + (maxv - minv) * new_ratio;
        changed = 1;
      } else if (ui.mouse_released) {
        ui.active_id = 0;
      }
    }
    if (focused) {
      if (ui.key_left) {
        v -= (maxv - minv) / 100.0;
        changed = 1;
      }
      if (ui.key_right) {
        v += (maxv - minv) / 100.0;
        changed = 1;
      }
      if (v < minv) {
        v = minv;
      }
      if (v > maxv) {
        v = maxv;
      }
    }
  }

  ui_draw_text(r.x, r.y + (r.h - ui_text_height()) / 2, t, ui.enabled ? ui.theme.text : ui.theme.muted);
  if (focused) {
    ui_draw_frame(r, ui.theme.accent);
  }
  if (changed) {
    ui_mark_dirty();
  }
  return rex_num(v);
}

RexValue rex_ui_progress(RexValue value, RexValue max) {
  value = ui_resolve(value);
  max = ui_resolve(max);
  if (value.tag != REX_NUM || max.tag != REX_NUM) {
    rex_panic("ui.progress expects (number, number)");
    return rex_nil();
  }
  double v = value.as.num;
  double mv = max.as.num;
  if (mv <= 0.0) {
    mv = 1.0;
  }
  if (v < 0.0) {
    v = 0.0;
  }
  if (v > mv) {
    v = mv;
  }
  RexUIRect r = ui_next_rect(0, ui.item_height);
  uint32_t bg = ui.enabled ? ui.theme.panel : ui_color_disabled(ui.theme.panel);
  ui_draw_rect(r.x, r.y, r.w, r.h, bg);
  double ratio = v / mv;
  int fill_w = (int)(r.w * ratio);
  ui_draw_rect(r.x, r.y, fill_w, r.h, ui.theme.accent);
  return rex_nil();
}

RexValue rex_ui_switch(RexValue label, RexValue active) {
  label = ui_resolve(label);
  active = ui_resolve(active);
  const char* t = ui_value_to_cstr(label);
  int sw = ui.item_height + 8;
  if (sw < 36) {
    sw = 36;
  }
  RexUIRect r = ui_next_rect(sw + ui.spacing + ui_text_width(t), ui.item_height);
  RexUIRect sw_r = { r.x, r.y + (r.h / 2) - 8, sw, 16 };
  int id = ui_next_id();
  int focused = ui_register_focusable(id);
  int hot = ui.enabled && ui_rect_contains(r, ui.mouse_x, ui.mouse_y);
  if (hot && ui.mouse_pressed) {
    ui.active_id = id;
    ui_set_focus(id);
  }
  int value = active.tag == REX_BOOL && active.as.boolean;
  if (ui.enabled) {
    if (ui.mouse_released && ui.active_id == id) {
      if (hot) {
        value = !value;
        ui_mark_dirty();
      }
      ui.active_id = 0;
    }
    if (focused && ui.key_enter) {
      value = !value;
      ui_mark_dirty();
    }
  }
  uint32_t track = value ? ui.theme.accent : ui.theme.button;
  if (!ui.enabled) {
    track = ui_color_disabled(track);
  }
  ui_draw_rect(sw_r.x, sw_r.y, sw_r.w, sw_r.h, track);
  int knob = sw_r.h - 4;
  int knob_x = value ? (sw_r.x + sw_r.w - knob - 2) : (sw_r.x + 2);
  ui_draw_rect(knob_x, sw_r.y + 2, knob, knob, ui.theme.panel);
  ui_draw_text(sw_r.x + sw_r.w + ui.spacing, r.y + (r.h - ui_text_height()) / 2, t, ui.enabled ? ui.theme.text : ui.theme.muted);
  if (focused) {
    ui_draw_frame(r, ui.theme.accent);
  }
  return rex_bool(value);
}

static int ui_vec_len(RexValue items) {
  RexValue len = rex_collections_vec_len(items);
  if (len.tag != REX_NUM) {
    return 0;
  }
  return (int)len.as.num;
}

static RexValue ui_vec_get(RexValue items, int index) {
  RexValue idx = rex_num((double)index);
  return rex_collections_vec_get(items, idx);
}

RexValue rex_ui_select(RexValue items, RexValue selected) {
  items = ui_resolve(items);
  selected = ui_resolve(selected);
  if (items.tag != REX_VEC) {
    rex_panic("ui.select expects vector");
    return selected;
  }
  int count = ui_vec_len(items);
  int sel = (selected.tag == REX_NUM) ? (int)selected.as.num : -1;
  int list_h = count * ui.item_height + (count > 0 ? (count - 1) * ui.spacing : 0);
  RexUIRect r = ui_next_rect(0, list_h);
  ui_draw_rect(r.x, r.y, r.w, r.h, ui.enabled ? ui.theme.panel : ui_color_disabled(ui.theme.panel));
  for (int i = 0; i < count; i++) {
    RexUIRect item_r = { r.x, r.y + i * (ui.item_height + ui.spacing), r.w, ui.item_height };
    int hot = ui.enabled && ui_rect_contains(item_r, ui.mouse_x, ui.mouse_y);
    if (hot && ui.mouse_pressed) {
      sel = i;
      ui_mark_dirty();
    }
    if (i == sel) {
      ui_draw_rect(item_r.x, item_r.y, item_r.w, item_r.h, ui.theme.select);
    } else if (hot) {
      ui_draw_rect(item_r.x, item_r.y, item_r.w, item_r.h, ui.theme.button_hover);
    }
    RexValue item = ui_vec_get(items, i);
    const char* t = ui_value_to_cstr(item);
    int ty = item_r.y + (item_r.h - ui_text_height()) / 2;
    ui_draw_text(item_r.x + ui.padding, ty, t, ui.enabled ? ui.theme.text : ui.theme.muted);
  }
  return rex_num((double)sel);
}

RexValue rex_ui_combo(RexValue items, RexValue selected) {
  items = ui_resolve(items);
  selected = ui_resolve(selected);
  if (items.tag != REX_VEC) {
    rex_panic("ui.combo expects vector");
    return selected;
  }
  int count = ui_vec_len(items);
  int sel = (selected.tag == REX_NUM) ? (int)selected.as.num : -1;
  const char* current = "";
  if (sel >= 0 && sel < count) {
    current = ui_value_to_cstr(ui_vec_get(items, sel));
  }
  int w = ui_text_width(current) + ui.padding * 2;
  if (w < 120) {
    w = 120;
  }
  RexUIRect button_r = ui_next_rect(w, ui.item_height);
  int id = ui_next_id();
  int focused = ui_register_focusable(id);
  int hot = ui.enabled && ui_rect_contains(button_r, ui.mouse_x, ui.mouse_y);
  if (hot && ui.mouse_pressed) {
    ui.active_id = id;
    ui_set_focus(id);
  }
  if (ui.enabled) {
    if (ui.mouse_released && ui.active_id == id) {
      if (hot) {
        if (ui.combo_open_id == id) {
          ui.combo_open_id = 0;
        } else {
          ui.combo_open_id = id;
        }
        ui_mark_dirty();
      }
      ui.active_id = 0;
    }
    if (focused && ui.key_enter) {
      if (ui.combo_open_id == id) {
        ui.combo_open_id = 0;
      } else {
        ui.combo_open_id = id;
      }
      ui_mark_dirty();
    }
  }
  uint32_t button_color = ui.enabled ? ui.theme.button : ui_color_disabled(ui.theme.button);
  if (ui.enabled && hot) {
    button_color = ui.theme.button_hover;
  }
  ui_draw_rect(button_r.x, button_r.y, button_r.w, button_r.h, button_color);
  ui_draw_text(button_r.x + ui.padding, button_r.y + (button_r.h - ui_text_height()) / 2, current, ui.enabled ? ui.theme.text : ui.theme.muted);
  if (focused) {
    ui_draw_frame(button_r, ui.theme.accent);
  }

  if (ui.combo_open_id == id) {
    int list_h = count * ui.item_height + (count > 0 ? (count - 1) * ui.spacing : 0);
    RexUIRect list_r = { button_r.x, button_r.y + button_r.h + ui.spacing, button_r.w, list_h };
    ui_draw_rect(list_r.x, list_r.y, list_r.w, list_r.h, ui.theme.panel);
    int clicked_outside = ui.mouse_pressed && !ui_rect_contains(list_r, ui.mouse_x, ui.mouse_y) && !ui_rect_contains(button_r, ui.mouse_x, ui.mouse_y);
    if (clicked_outside) {
      ui.combo_open_id = 0;
    }
    for (int i = 0; i < count; i++) {
      RexUIRect item_r = { list_r.x, list_r.y + i * (ui.item_height + ui.spacing), list_r.w, ui.item_height };
      int hot_item = ui_rect_contains(item_r, ui.mouse_x, ui.mouse_y);
      if (hot_item && ui.mouse_pressed) {
        sel = i;
        ui.combo_open_id = 0;
        ui_mark_dirty();
      }
      if (i == sel) {
        ui_draw_rect(item_r.x, item_r.y, item_r.w, item_r.h, ui.theme.select);
      } else if (hot_item) {
        ui_draw_rect(item_r.x, item_r.y, item_r.w, item_r.h, ui.theme.button_hover);
      }
      RexValue item = ui_vec_get(items, i);
      const char* t = ui_value_to_cstr(item);
      int ty = item_r.y + (item_r.h - ui_text_height()) / 2;
      ui_draw_text(item_r.x + ui.padding, ty, t, ui.theme.text);
    }
  }
  return rex_num((double)sel);
}

RexValue rex_ui_menu(RexValue items, RexValue selected) {
  items = ui_resolve(items);
  selected = ui_resolve(selected);
  if (items.tag != REX_VEC) {
    rex_panic("ui.menu expects vector");
    return selected;
  }
  int count = ui_vec_len(items);
  int sel = (selected.tag == REX_NUM) ? (int)selected.as.num : -1;
  RexUIRect r = ui_next_rect(0, ui.item_height);
  ui_draw_rect(r.x, r.y, r.w, r.h, ui.enabled ? ui.theme.panel : ui_color_disabled(ui.theme.panel));
  int x = r.x + ui.padding;
  for (int i = 0; i < count; i++) {
    RexValue item = ui_vec_get(items, i);
    const char* t = ui_value_to_cstr(item);
    int w = ui_text_width(t) + ui.padding;
    RexUIRect item_r = { x, r.y, w, r.h };
    int id = ui_next_id();
    int focused = ui_register_focusable(id);
    int hot = ui.enabled && ui_rect_contains(item_r, ui.mouse_x, ui.mouse_y);
    if (hot && ui.mouse_pressed) {
      ui.active_id = id;
      ui_set_focus(id);
    }
    if (ui.enabled) {
      if (ui.mouse_released && ui.active_id == id) {
        if (hot) {
          sel = i;
          ui_mark_dirty();
        }
        ui.active_id = 0;
      }
      if (focused && ui.key_enter) {
        sel = i;
        ui_mark_dirty();
      }
    }
    if (i == sel) {
      ui_draw_rect(item_r.x, item_r.y, item_r.w, item_r.h, ui.theme.select);
    } else if (hot) {
      ui_draw_rect(item_r.x, item_r.y, item_r.w, item_r.h, ui.theme.button_hover);
    }
    ui_draw_text(item_r.x + (ui.padding / 2), item_r.y + (item_r.h - ui_text_height()) / 2, t, ui.enabled ? ui.theme.text : ui.theme.muted);
    if (focused) {
      ui_draw_frame(item_r, ui.theme.accent);
    }
    x += w + ui.spacing;
  }
  return rex_num((double)sel);
}

RexValue rex_ui_tabs(RexValue items, RexValue selected) {
  items = ui_resolve(items);
  selected = ui_resolve(selected);
  if (items.tag != REX_VEC) {
    rex_panic("ui.tabs expects vector");
    return selected;
  }
  int count = ui_vec_len(items);
  int sel = (selected.tag == REX_NUM) ? (int)selected.as.num : -1;
  RexUIRect r = ui_next_rect(0, ui.item_height);
  int x = r.x;
  for (int i = 0; i < count; i++) {
    RexValue item = ui_vec_get(items, i);
    const char* t = ui_value_to_cstr(item);
    int w = ui_text_width(t) + ui.padding * 2;
    RexUIRect tab_r = { x, r.y, w, r.h };
    int id = ui_next_id();
    int focused = ui_register_focusable(id);
    int hot = ui.enabled && ui_rect_contains(tab_r, ui.mouse_x, ui.mouse_y);
    if (hot && ui.mouse_pressed) {
      ui.active_id = id;
      ui_set_focus(id);
    }
    if (ui.enabled) {
      if (ui.mouse_released && ui.active_id == id) {
        if (hot) {
          sel = i;
          ui_mark_dirty();
        }
        ui.active_id = 0;
      }
      if (focused && ui.key_enter) {
        sel = i;
        ui_mark_dirty();
      }
    }
    uint32_t bg = ui.enabled ? ui.theme.button : ui_color_disabled(ui.theme.button);
    if (i == sel) {
      bg = ui.theme.accent;
    } else if (hot) {
      bg = ui.theme.button_hover;
    }
    ui_draw_rect(tab_r.x, tab_r.y, tab_r.w, tab_r.h, bg);
    ui_draw_text(tab_r.x + (tab_r.w - ui_text_width(t)) / 2, tab_r.y + (tab_r.h - ui_text_height()) / 2, t, ui.enabled ? ui.theme.text : ui.theme.muted);
    if (focused) {
      ui_draw_frame(tab_r, ui.theme.accent);
    }
    x += w + ui.spacing;
  }
  return rex_num((double)sel);
}

RexValue rex_ui_layout_row(RexValue height) {
  height = ui_resolve(height);
  if (height.tag != REX_NUM) {
    rex_panic("ui.row expects number");
    return rex_nil();
  }
  ui.layout_mode = UI_LAYOUT_ROW;
  int next_height = (int)height.as.num;
  if (next_height != ui.row_height) {
    ui_mark_dirty();
  }
  ui.row_height = next_height;
  if (ui.row_height <= 0) {
    ui.row_height = ui.item_height;
  }
  ui.cursor_x = ui.content_x;
  return rex_nil();
}

RexValue rex_ui_layout_column(RexValue height) {
  height = ui_resolve(height);
  if (height.tag != REX_NUM) {
    rex_panic("ui.column expects number");
    return rex_nil();
  }
  ui.layout_mode = UI_LAYOUT_COLUMN;
  int h = (int)height.as.num;
  if (h > 0) {
    if (ui.item_height != h) {
      ui_mark_dirty();
    }
    ui.item_height = h;
    ui.row_height = h;
  }
  ui.cursor_x = ui.content_x;
  return rex_nil();
}

RexValue rex_ui_layout_grid(RexValue cols, RexValue cell_w, RexValue cell_h) {
  cols = ui_resolve(cols);
  cell_w = ui_resolve(cell_w);
  cell_h = ui_resolve(cell_h);
  if (cols.tag != REX_NUM || cell_w.tag != REX_NUM || cell_h.tag != REX_NUM) {
    rex_panic("ui.grid expects numbers");
    return rex_nil();
  }
  ui.layout_mode = UI_LAYOUT_GRID;
  int next_cols = (int)cols.as.num;
  int next_w = (int)cell_w.as.num;
  int next_h = (int)cell_h.as.num;
  if (next_cols != ui.grid_cols || next_w != ui.grid_cell_w || next_h != ui.grid_cell_h) {
    ui_mark_dirty();
  }
  ui.grid_cols = next_cols;
  ui.grid_cell_w = next_w;
  ui.grid_cell_h = next_h;
  if (ui.grid_cols <= 0) {
    ui.grid_cols = 1;
  }
  if (ui.grid_cell_w <= 0) {
    ui.grid_cell_w = 80;
  }
  if (ui.grid_cell_h <= 0) {
    ui.grid_cell_h = ui.item_height;
  }
  ui.grid_index = 0;
  ui.grid_origin_x = ui.content_x;
  ui.grid_origin_y = ui.cursor_y;
  return rex_nil();
}

static void ui_newline_internal(void) {
  if (ui.layout_mode == UI_LAYOUT_ROW) {
    ui.cursor_x = ui.content_x;
    ui.cursor_y += ui.row_height + ui.spacing;
  } else if (ui.layout_mode == UI_LAYOUT_GRID) {
    int row = ui.grid_index / ui.grid_cols;
    ui.grid_index = (row + 1) * ui.grid_cols;
  } else {
    ui.cursor_y += ui.item_height + ui.spacing;
  }
  ui_mark_dirty();
}

RexValue rex_ui_newline(void) {
  ui_newline_internal();
  return rex_nil();
}

RexValue rex_ui_row_end(void) {
  ui_newline_internal();
  return rex_nil();
}

RexValue rex_ui_clip_begin(RexValue x, RexValue y, RexValue w, RexValue h) {
  x = ui_resolve(x);
  y = ui_resolve(y);
  w = ui_resolve(w);
  h = ui_resolve(h);
  if (x.tag != REX_NUM || y.tag != REX_NUM || w.tag != REX_NUM || h.tag != REX_NUM) {
    rex_panic("ui.clip_begin expects numbers");
    return rex_nil();
  }
  RexUIRect r;
  r.x = (int)x.as.num;
  r.y = (int)y.as.num;
  r.w = (int)w.as.num;
  r.h = (int)h.as.num;
  ui_push_clip(r);
  return rex_nil();
}

RexValue rex_ui_clip_end(void) {
  ui_pop_clip();
  return rex_nil();
}

RexValue rex_ui_spacing(RexValue px) {
  px = ui_resolve(px);
  if (px.tag != REX_NUM) {
    rex_panic("ui.spacing expects number");
    return rex_nil();
  }
  int next = (int)px.as.num;
  if (next != ui.spacing) {
    ui_mark_dirty();
  }
  ui.spacing = next;
  if (ui.spacing < 0) {
    ui.spacing = 0;
  }
  return rex_nil();
}

RexValue rex_ui_padding(RexValue px) {
  px = ui_resolve(px);
  if (px.tag != REX_NUM) {
    rex_panic("ui.padding expects number");
    return rex_nil();
  }
  int next = (int)px.as.num;
  if (next != ui.padding) {
    ui_mark_dirty();
  }
  ui.padding = next;
  if (ui.padding < 0) {
    ui.padding = 0;
  }
  ui.content_x = ui.padding;
  ui.content_w = ui.width - ui.padding * 2;
  if (ui.content_w < 0) {
    ui.content_w = 0;
  }
  ui.cursor_x = ui.content_x;
  ui.cursor_y = ui.padding;
  return rex_nil();
}

RexValue rex_ui_scroll_begin(RexValue height) {
  height = ui_resolve(height);
  if (height.tag != REX_NUM) {
    rex_panic("ui.scroll_begin expects number");
    return rex_nil();
  }
  int h = (int)height.as.num;
  if (h <= 0) {
    h = ui.item_height * 4;
  }
  RexUIRect view = ui_next_rect(0, h);
  int id = ui_next_id();
  int offset = ui_scroll_get(id);
  if (ui.enabled && ui.scroll_y != 0 && ui_rect_contains(view, ui.mouse_x, ui.mouse_y)) {
    int prev = offset;
    offset -= ui.scroll_y * 24;
    if (offset != prev) {
      ui_mark_dirty();
    }
  }

  if (ui.layout_depth < UI_LAYOUT_STACK_MAX) {
    RexUILayoutState* s = &ui.layout_stack[ui.layout_depth++];
    s->layout_mode = ui.layout_mode;
    s->cursor_x = ui.cursor_x;
    s->cursor_y = ui.cursor_y;
    s->row_height = ui.row_height;
    s->item_height = ui.item_height;
    s->spacing = ui.spacing;
    s->padding = ui.padding;
    s->grid_cols = ui.grid_cols;
    s->grid_cell_w = ui.grid_cell_w;
    s->grid_cell_h = ui.grid_cell_h;
    s->grid_index = ui.grid_index;
    s->grid_origin_x = ui.grid_origin_x;
    s->grid_origin_y = ui.grid_origin_y;
    s->content_x = ui.content_x;
    s->content_w = ui.content_w;
    s->combo_open_id = ui.combo_open_id;
    s->enabled = ui.enabled;
    s->scroll_view = view;
    s->scroll_id = id;
    s->scroll_offset = offset;
  }

  ui_push_clip(view);
  ui.layout_mode = UI_LAYOUT_COLUMN;
  ui.content_x = view.x + ui.padding;
  ui.content_w = view.w - ui.padding * 2;
  if (ui.content_w < 0) {
    ui.content_w = 0;
  }
  ui.cursor_x = ui.content_x;
  ui.cursor_y = view.y + ui.padding - offset;
  ui.grid_origin_x = ui.content_x;
  ui.grid_origin_y = ui.cursor_y;
  ui.grid_index = 0;
  return rex_nil();
}

RexValue rex_ui_scroll_end(void) {
  if (ui.layout_depth <= 0) {
    return rex_nil();
  }
  RexUILayoutState s = ui.layout_stack[--ui.layout_depth];
  RexUIRect view = s.scroll_view;
  int offset = s.scroll_offset;
  int content_height = (ui.cursor_y + offset) - (view.y + ui.padding);
  if (content_height < 0) {
    content_height = 0;
  }
  int max_offset = content_height - view.h + ui.padding * 2;
  if (max_offset < 0) {
    max_offset = 0;
  }
  offset = ui_clamp(offset, 0, max_offset);
  if (offset != s.scroll_offset) {
    ui_mark_dirty();
  }
  ui_scroll_set(s.scroll_id, offset);

  if (content_height > view.h) {
    double ratio = (double)view.h / (double)content_height;
    int bar_h = (int)(view.h * ratio);
    if (bar_h < 16) {
      bar_h = 16;
    }
    int bar_y = view.y + (int)((double)(offset) / (double)max_offset * (view.h - bar_h));
    RexUIRect bar = { view.x + view.w - 6, bar_y, 4, bar_h };
    ui_draw_rect(bar.x, bar.y, bar.w, bar.h, ui.theme.muted);
  }

  ui_pop_clip();
  ui.layout_mode = s.layout_mode;
  ui.cursor_x = s.cursor_x;
  ui.cursor_y = s.cursor_y;
  ui.row_height = s.row_height;
  ui.item_height = s.item_height;
  ui.spacing = s.spacing;
  ui.padding = s.padding;
  ui.grid_cols = s.grid_cols;
  ui.grid_cell_w = s.grid_cell_w;
  ui.grid_cell_h = s.grid_cell_h;
  ui.grid_index = s.grid_index;
  ui.grid_origin_x = s.grid_origin_x;
  ui.grid_origin_y = s.grid_origin_y;
  ui.content_x = s.content_x;
  ui.content_w = s.content_w;
  ui.combo_open_id = s.combo_open_id;
  ui.enabled = s.enabled;
  return rex_nil();
}

RexValue rex_ui_enabled(RexValue enabled) {
  enabled = ui_resolve(enabled);
  if (enabled.tag != REX_BOOL) {
    rex_panic("ui.enabled expects bool");
    return rex_nil();
  }
  int next = enabled.as.boolean ? 1 : 0;
  if (next != ui.enabled) {
    ui.enabled = next;
    ui_mark_dirty();
  }
  return rex_nil();
}

RexValue rex_ui_invert(RexValue enabled) {
  enabled = ui_resolve(enabled);
  if (enabled.tag != REX_BOOL) {
    rex_panic("ui.invert expects bool");
    return rex_nil();
  }
  int next = enabled.as.boolean ? 1 : 0;
  if (next != ui.invert) {
    ui.invert = next;
    ui_mark_dirty();
  }
  return rex_nil();
}

RexValue rex_ui_titlebar_dark(RexValue enabled) {
  enabled = ui_resolve(enabled);
  if (enabled.tag != REX_BOOL) {
    rex_panic("ui.titlebar_dark expects bool");
    return rex_nil();
  }
  rex_ui_platform_set_titlebar_dark(enabled.as.boolean ? 1 : 0);
  return rex_nil();
}

RexValue rex_ui_theme_dark(void) {
  ui.theme = ui_theme_dark;
  ui_mark_dirty();
  return rex_nil();
}

RexValue rex_ui_theme_light(void) {
  ui.theme = ui_theme_light;
  ui_mark_dirty();
  return rex_nil();
}

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
) {
  ui.theme.bg = ui_color_from_value(bg, ui.theme.bg);
  ui.theme.panel = ui_color_from_value(panel, ui.theme.panel);
  ui.theme.text = ui_color_from_value(text, ui.theme.text);
  ui.theme.muted = ui_color_from_value(muted, ui.theme.muted);
  ui.theme.button = ui_color_from_value(button, ui.theme.button);
  ui.theme.button_hover = ui_color_from_value(button_hover, ui.theme.button_hover);
  ui.theme.button_active = ui_color_from_value(button_active, ui.theme.button_active);
  ui.theme.accent = ui_color_from_value(accent, ui.theme.accent);
  ui.theme.select = ui_color_from_value(select, ui.theme.select);
  ui_mark_dirty();
  return rex_nil();
}

RexValue rex_ui_image_load(RexValue path) {
  path = ui_resolve(path);
  if (path.tag != REX_STR || !path.as.str) {
    rex_panic("ui.image_load expects string path");
    return rex_nil();
  }
  RexUIImage* img = NULL;
#ifdef _WIN32
  img = ui_image_load_wic(path.as.str);
#endif
  if (!img) {
    char buf[256];
    snprintf(buf, sizeof(buf), "ui.image_load failed: %s", path.as.str);
    rex_panic(buf);
    return rex_nil();
  }
  return rex_ptr(img);
}

RexValue rex_ui_image_w(RexValue img) {
  img = ui_resolve(img);
  if (img.tag != REX_PTR || !img.as.ptr) {
    rex_panic("ui.image_w expects image handle");
    return rex_num(0);
  }
  RexUIImage* i = (RexUIImage*)img.as.ptr;
  return rex_num((double)i->w);
}

RexValue rex_ui_image_h(RexValue img) {
  img = ui_resolve(img);
  if (img.tag != REX_PTR || !img.as.ptr) {
    rex_panic("ui.image_h expects image handle");
    return rex_num(0);
  }
  RexUIImage* i = (RexUIImage*)img.as.ptr;
  return rex_num((double)i->h);
}

RexValue rex_ui_image(RexValue img, RexValue x, RexValue y) {
  img = ui_resolve(img);
  x = ui_resolve(x);
  y = ui_resolve(y);
  if (img.tag != REX_PTR || !img.as.ptr || x.tag != REX_NUM || y.tag != REX_NUM) {
    rex_panic("ui.image expects (image, number, number)");
    return rex_nil();
  }
  ui_draw_image((RexUIImage*)img.as.ptr, (int)x.as.num, (int)y.as.num);
  return rex_nil();
}

RexValue rex_ui_image_region(RexValue img, RexValue sx, RexValue sy, RexValue sw, RexValue sh, RexValue x, RexValue y, RexValue w, RexValue h) {
  img = ui_resolve(img);
  sx = ui_resolve(sx);
  sy = ui_resolve(sy);
  sw = ui_resolve(sw);
  sh = ui_resolve(sh);
  x = ui_resolve(x);
  y = ui_resolve(y);
  w = ui_resolve(w);
  h = ui_resolve(h);
  if (img.tag != REX_PTR || sx.tag != REX_NUM || sy.tag != REX_NUM || sw.tag != REX_NUM || sh.tag != REX_NUM || x.tag != REX_NUM || y.tag != REX_NUM || w.tag != REX_NUM || h.tag != REX_NUM) {
    rex_panic("ui.image_region expects (image, number, number, number, number, number, number, number, number)");
    return rex_nil();
  }
  ui_draw_image_region((RexUIImage*)img.as.ptr, (int)sx.as.num, (int)sy.as.num, (int)sw.as.num, (int)sh.as.num, (int)x.as.num, (int)y.as.num, (int)w.as.num, (int)h.as.num);
  return rex_nil();
}

RexValue rex_ui_play_sound(RexValue path) {
  path = ui_resolve(path);
  if (path.tag != REX_STR || !path.as.str) {
    rex_panic("ui.play_sound expects string path");
    return rex_bool(0);
  }
#ifdef _WIN32
  const char* p = path.as.str;
  size_t len = strlen(p);
  const char* ext = len >= 4 ? p + (len - 4) : NULL;
  int is_mp3 = 0;
  if (ext) {
    is_mp3 =
      (tolower((unsigned char)ext[0]) == '.' &&
       tolower((unsigned char)ext[1]) == 'm' &&
       tolower((unsigned char)ext[2]) == 'p' &&
       tolower((unsigned char)ext[3]) == '3');
  }
  wchar_t* wpath = ui_widen_path(p);
  if (!wpath) {
    return rex_bool(0);
  }
  wchar_t fullbuf[MAX_PATH];
  wchar_t* fullpath = wpath;
  wchar_t* fullalloc = NULL;
  DWORD full_len = GetFullPathNameW(wpath, MAX_PATH, fullbuf, NULL);
  if (full_len > 0 && full_len < MAX_PATH) {
    fullpath = fullbuf;
  } else if (full_len >= MAX_PATH) {
    fullalloc = (wchar_t*)malloc((full_len + 1) * sizeof(wchar_t));
    if (fullalloc && GetFullPathNameW(wpath, full_len + 1, fullalloc, NULL) > 0) {
      fullpath = fullalloc;
    }
  }
  int ok = 0;
  if (is_mp3) {
    ok = ui_play_mp3(fullpath);
  } else {
    ui_sound_stop();
    ok = PlaySoundW(fullpath, NULL, SND_FILENAME | SND_ASYNC | SND_NODEFAULT) != FALSE;
  }
  free(wpath);
  free(fullalloc);
  return rex_bool(ok != 0);
#else
  (void)path;
  return rex_bool(0);
#endif
}
