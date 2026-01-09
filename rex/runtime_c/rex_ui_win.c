#ifdef _WIN32

#include "rex_ui.h"

#include <windows.h>
#include <windowsx.h>
#include <string.h>

static HWND ui_hwnd = NULL;
static int ui_running = 0;
static int ui_mouse_x = 0;
static int ui_mouse_y = 0;
static int ui_mouse_down = 0;
static char ui_text[REX_UI_TEXT_MAX];
static int ui_text_len = 0;
static int ui_scroll_y = 0;
static int ui_key_tab = 0;
static int ui_key_enter = 0;
static int ui_key_space = 0;
static int ui_key_up = 0;
static int ui_key_down = 0;
static int ui_key_backspace = 0;
static int ui_key_delete = 0;
static int ui_key_left = 0;
static int ui_key_right = 0;
static int ui_key_home = 0;
static int ui_key_end = 0;
static int ui_key_copy = 0;
static int ui_key_paste = 0;
static int ui_key_cut = 0;
static int ui_key_select_all = 0;
static int ui_redraw = 0;
static int ui_width = 0;
static int ui_height = 0;
static float ui_dpi_scale = 1.0f;
static const uint32_t* ui_pixels = NULL;
static int ui_pix_w = 0;
static int ui_pix_h = 0;
static int ui_class_registered = 0;
static wchar_t ui_surrogate = 0;
static HMODULE ui_dwm = NULL;
typedef HRESULT (WINAPI *DwmSetWindowAttributeFn)(HWND, DWORD, LPCVOID, DWORD);
static DwmSetWindowAttributeFn ui_dwm_set_window_attribute = NULL;
static int ui_dwm_tried = 0;

static void ui_dwm_init(void) {
  if (ui_dwm_tried) {
    return;
  }
  ui_dwm_tried = 1;
  ui_dwm = LoadLibraryW(L"dwmapi.dll");
  if (!ui_dwm) {
    return;
  }
  ui_dwm_set_window_attribute = (DwmSetWindowAttributeFn)GetProcAddress(ui_dwm, "DwmSetWindowAttribute");
}

static void ui_text_push_bytes(const char* data, int len) {
  if (len <= 0) {
    return;
  }
  int space = REX_UI_TEXT_MAX - ui_text_len;
  if (space <= 0) {
    return;
  }
  if (len > space) {
    len = space;
  }
  memcpy(ui_text + ui_text_len, data, (size_t)len);
  ui_text_len += len;
}

static void ui_text_push_utf8(uint32_t codepoint) {
  if (codepoint < 32 || codepoint == 127) {
    return;
  }
  char buf[4];
  int len = 0;
  if (codepoint <= 0x7F) {
    buf[len++] = (char)codepoint;
  } else if (codepoint <= 0x7FF) {
    buf[len++] = (char)(0xC0 | ((codepoint >> 6) & 0x1F));
    buf[len++] = (char)(0x80 | (codepoint & 0x3F));
  } else if (codepoint <= 0xFFFF) {
    buf[len++] = (char)(0xE0 | ((codepoint >> 12) & 0x0F));
    buf[len++] = (char)(0x80 | ((codepoint >> 6) & 0x3F));
    buf[len++] = (char)(0x80 | (codepoint & 0x3F));
  } else {
    buf[len++] = (char)(0xF0 | ((codepoint >> 18) & 0x07));
    buf[len++] = (char)(0x80 | ((codepoint >> 12) & 0x3F));
    buf[len++] = (char)(0x80 | ((codepoint >> 6) & 0x3F));
    buf[len++] = (char)(0x80 | (codepoint & 0x3F));
  }
  ui_text_push_bytes(buf, len);
}

static void ui_clear_key_state(void) {
  ui_key_tab = 0;
  ui_key_enter = 0;
  ui_key_space = 0;
  ui_key_up = 0;
  ui_key_down = 0;
  ui_key_backspace = 0;
  ui_key_delete = 0;
  ui_key_left = 0;
  ui_key_right = 0;
  ui_key_home = 0;
  ui_key_end = 0;
}

static LRESULT CALLBACK rex_ui_wndproc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  switch (msg) {
    case WM_CLOSE:
      ui_running = 0;
      DestroyWindow(hwnd);
      return 0;
    case WM_DESTROY:
      ui_running = 0;
      PostQuitMessage(0);
      return 0;
    case WM_SIZE:
      ui_width = LOWORD(lparam);
      ui_height = HIWORD(lparam);
      ui_redraw = 1;
      return 0;
    case WM_MOUSEMOVE:
      ui_mouse_x = GET_X_LPARAM(lparam);
      ui_mouse_y = GET_Y_LPARAM(lparam);
      return 0;
    case WM_LBUTTONDOWN:
      ui_mouse_down = 1;
      SetCapture(hwnd);
      return 0;
    case WM_LBUTTONUP:
      ui_mouse_down = 0;
      ReleaseCapture();
      return 0;
    case WM_MOUSEWHEEL: {
      int delta = GET_WHEEL_DELTA_WPARAM(wparam);
      ui_scroll_y += delta / WHEEL_DELTA;
      return 0;
    }
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN: {
      int ctrl = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
      switch (wparam) {
        case VK_TAB: ui_key_tab = 1; break;
        case VK_RETURN: ui_key_enter = 1; break;
        case VK_SPACE: ui_key_space = 1; break;
        case VK_UP: ui_key_up = 1; break;
        case VK_DOWN: ui_key_down = 1; break;
        case VK_BACK: ui_key_backspace = 1; break;
        case VK_DELETE: ui_key_delete = 1; break;
        case VK_LEFT: ui_key_left = 1; break;
        case VK_RIGHT: ui_key_right = 1; break;
        case VK_HOME: ui_key_home = 1; break;
        case VK_END: ui_key_end = 1; break;
        case 'C': if (ctrl) ui_key_copy = 1; break;
        case 'V': if (ctrl) ui_key_paste = 1; break;
        case 'X': if (ctrl) ui_key_cut = 1; break;
        case 'A': if (ctrl) ui_key_select_all = 1; break;
        default: break;
      }
      return 0;
    }
    case WM_KEYUP:
    case WM_SYSKEYUP:
      switch (wparam) {
        case VK_TAB: ui_key_tab = 0; break;
        case VK_RETURN: ui_key_enter = 0; break;
        case VK_SPACE: ui_key_space = 0; break;
        case VK_UP: ui_key_up = 0; break;
        case VK_DOWN: ui_key_down = 0; break;
        case VK_BACK: ui_key_backspace = 0; break;
        case VK_DELETE: ui_key_delete = 0; break;
        case VK_LEFT: ui_key_left = 0; break;
        case VK_RIGHT: ui_key_right = 0; break;
        case VK_HOME: ui_key_home = 0; break;
        case VK_END: ui_key_end = 0; break;
        default: break;
      }
      return 0;
    case WM_KILLFOCUS:
      ui_clear_key_state();
      return 0;
    case WM_CHAR: {
      wchar_t wc = (wchar_t)wparam;
      if (wc >= 0xD800 && wc <= 0xDBFF) {
        ui_surrogate = wc;
        return 0;
      }
      uint32_t codepoint = (uint32_t)wc;
      if (wc >= 0xDC00 && wc <= 0xDFFF) {
        if (ui_surrogate) {
          codepoint = 0x10000u + (((uint32_t)ui_surrogate - 0xD800u) << 10)
            + ((uint32_t)wc - 0xDC00u);
          ui_surrogate = 0;
        } else {
          codepoint = 0xFFFD;
        }
      } else if (ui_surrogate) {
        ui_surrogate = 0;
      }
      ui_text_push_utf8(codepoint);
      return 0;
    }
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC hdc = BeginPaint(hwnd, &ps);
      if (ui_pixels && ui_pix_w > 0 && ui_pix_h > 0) {
        BITMAPINFO bmi;
        memset(&bmi, 0, sizeof(bmi));
        bmi.bmiHeader.biSize = sizeof(bmi.bmiHeader);
        bmi.bmiHeader.biWidth = ui_pix_w;
        bmi.bmiHeader.biHeight = -ui_pix_h;
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 32;
        bmi.bmiHeader.biCompression = BI_RGB;
        StretchDIBits(
          hdc,
          0,
          0,
          ui_pix_w,
          ui_pix_h,
          0,
          0,
          ui_pix_w,
          ui_pix_h,
          ui_pixels,
          &bmi,
          DIB_RGB_COLORS,
          SRCCOPY
        );
      }
      EndPaint(hwnd, &ps);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    default:
      return DefWindowProc(hwnd, msg, wparam, lparam);
  }
}

int rex_ui_platform_init(const char* title, int width, int height) {
  SetProcessDPIAware();
  WNDCLASSA wc;
  memset(&wc, 0, sizeof(wc));
  wc.style = CS_HREDRAW | CS_VREDRAW;
  wc.lpfnWndProc = rex_ui_wndproc;
  wc.hInstance = GetModuleHandleA(NULL);
  wc.lpszClassName = "RexUIWindow";
  if (!ui_class_registered) {
    if (!RegisterClassA(&wc)) {
      DWORD err = GetLastError();
      if (err != ERROR_CLASS_ALREADY_EXISTS) {
        return 0;
      }
    }
    ui_class_registered = 1;
  }

  DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
  RECT rect = { 0, 0, width, height };
  AdjustWindowRect(&rect, style, 0);
  ui_hwnd = CreateWindowA(
    wc.lpszClassName,
    title ? title : "Rex",
    style,
    CW_USEDEFAULT,
    CW_USEDEFAULT,
    rect.right - rect.left,
    rect.bottom - rect.top,
    NULL,
    NULL,
    wc.hInstance,
    NULL
  );
  if (!ui_hwnd) {
    return 0;
  }
  ShowWindow(ui_hwnd, SW_SHOW);
  ui_running = 1;
  ui_width = width;
  ui_height = height;
  return 1;
}

void rex_ui_platform_shutdown(void) {
  if (ui_hwnd) {
    DestroyWindow(ui_hwnd);
    ui_hwnd = NULL;
  }
  ui_running = 0;
}

int rex_ui_platform_poll(RexUIPlatformInput* input) {
  ui_text_len = 0;
  ui_scroll_y = 0;
  ui_key_copy = 0;
  ui_key_paste = 0;
  ui_key_cut = 0;
  ui_key_select_all = 0;
  ui_redraw = 0;
  MSG msg;
  while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
    if (msg.message == WM_QUIT) {
      ui_running = 0;
    }
    TranslateMessage(&msg);
    DispatchMessage(&msg);
  }
  if (!ui_running) {
    input->closed = 1;
    return 0;
  }
  if (ui_hwnd) {
    RECT rect;
    if (GetClientRect(ui_hwnd, &rect)) {
      ui_width = rect.right - rect.left;
      ui_height = rect.bottom - rect.top;
    }
    HDC hdc = GetDC(ui_hwnd);
    if (hdc) {
      int dpi = GetDeviceCaps(hdc, LOGPIXELSX);
      if (dpi > 0) {
        ui_dpi_scale = (float)dpi / 96.0f;
      }
      ReleaseDC(ui_hwnd, hdc);
    }
  }
  input->mouse_x = ui_mouse_x;
  input->mouse_y = ui_mouse_y;
  input->mouse_down = ui_mouse_down;
  input->scroll_y = ui_scroll_y;
  input->key_tab = ui_key_tab;
  input->key_enter = ui_key_enter;
  input->key_space = ui_key_space;
  input->key_up = ui_key_up;
  input->key_down = ui_key_down;
  input->key_backspace = ui_key_backspace;
  input->key_delete = ui_key_delete;
  input->key_left = ui_key_left;
  input->key_right = ui_key_right;
  input->key_home = ui_key_home;
  input->key_end = ui_key_end;
  input->key_ctrl = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
  input->key_shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
  input->key_copy = ui_key_copy;
  input->key_paste = ui_key_paste;
  input->key_cut = ui_key_cut;
  input->key_select_all = ui_key_select_all;
  input->text_len = ui_text_len;
  if (ui_text_len > 0) {
    memcpy(input->text, ui_text, (size_t)ui_text_len);
  }
  input->width = ui_width;
  input->height = ui_height;
  input->dpi_scale = ui_dpi_scale;
  input->redraw = ui_redraw;
  input->closed = 0;
  return 1;
}

void rex_ui_platform_present(const uint32_t* pixels, int width, int height) {
  if (!ui_hwnd || !pixels) {
    return;
  }
  ui_pixels = pixels;
  ui_pix_w = width;
  ui_pix_h = height;
  InvalidateRect(ui_hwnd, NULL, FALSE);
  UpdateWindow(ui_hwnd);
}

int rex_ui_platform_get_clipboard(char* buffer, int capacity) {
  if (!buffer || capacity <= 0) {
    return 0;
  }
  if (!OpenClipboard(ui_hwnd)) {
    return 0;
  }
  HANDLE data = GetClipboardData(CF_TEXT);
  if (!data) {
    CloseClipboard();
    return 0;
  }
  char* text = (char*)GlobalLock(data);
  if (!text) {
    CloseClipboard();
    return 0;
  }
  int len = (int)strlen(text);
  if (len >= capacity) {
    len = capacity - 1;
  }
  memcpy(buffer, text, (size_t)len);
  buffer[len] = '\0';
  GlobalUnlock(data);
  CloseClipboard();
  return len;
}

void rex_ui_platform_set_clipboard(const char* text) {
  if (!text) {
    text = "";
  }
  if (!OpenClipboard(ui_hwnd)) {
    return;
  }
  EmptyClipboard();
  size_t len = strlen(text) + 1;
  HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE, len);
  if (mem) {
    char* dst = (char*)GlobalLock(mem);
    if (dst) {
      memcpy(dst, text, len);
      GlobalUnlock(mem);
      SetClipboardData(CF_TEXT, mem);
    }
  }
  CloseClipboard();
}

void rex_ui_platform_set_titlebar_dark(int dark) {
  if (!ui_hwnd) {
    return;
  }
  ui_dwm_init();
  if (!ui_dwm_set_window_attribute) {
    return;
  }
  BOOL value = dark ? TRUE : FALSE;
  const DWORD DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
  HRESULT hr = ui_dwm_set_window_attribute(ui_hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &value, sizeof(value));
  if (FAILED(hr)) {
    const DWORD DWMWA_USE_IMMERSIVE_DARK_MODE_OLD = 19;
    ui_dwm_set_window_attribute(ui_hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE_OLD, &value, sizeof(value));
  }
}

#endif
