# Rex language specification

## English

Rex is a low-level language design inspired by C/C++, Rust, and Go. This repo includes a compiler front-end written in Lua with a tiny C runtime.


## العربية

ريكس هي لغة منخفضة المستوى مستوحاة من C/C++ و Rust و Go. هذا المشروع يحتوي على مترجم مكتوب بلوا مع وقت تشغيل صغير بلغة C.

ملاحظات المنصات:
- الواجهة الرسومية تعمل عبر Win32 على ويندوز و X11 على لينكس و Cocoa على ماك
- دعم HTTPS يستخدم WinHTTP على ويندوز و OpenSSL على لينكس/ماك (يحتاج libssl و libcrypto)
