# Rex Standard Library Guide

Rex exposes runtime functionality through modules imported with `use`.

Example:

```rex
use rex::io
use rex::time
```

Below is a practical map of the current modules.

## 1. Core Built-ins

Available without module prefix:
- `println(x)`, `print(x)`
- `channel<T>()`
- `sleep(ms)`, `now_ms()`
- `format(x)`
- `Ok(x)`, `Err(e)`
- `alloc<T>()`, `free(ptr)`, `box(x)`, `unbox(ptr)`, `drop(x)`
- `sqrt(x)`, `abs(x)`

## 2. `rex::io`

Common I/O operations:
- `println`, `print`
- `read_file(&path) -> Result<str>`
- `write_file(&path, data) -> Result<bool>`
- `read_line() -> Result<str>`
- `read_lines(&path) -> Result<Vec<str>>`
- `write_lines(&path, &lines) -> Result<bool>`

## 3. `rex::fs`

Filesystem helpers:
- `exists(&path) -> bool`
- `mkdir(&path) -> Result<bool>`
- `remove(&path) -> Result<bool>`
- `is_dir(&path) -> bool`
- `read_dir(&path) -> Result<Vec<str>>`
- `copy(&src, &dst) -> Result<bool>`
- `move(&src, &dst) -> Result<bool>`

## 4. `rex::thread`

- `channel<T>() -> (Sender<T>, Receiver<T>)`
- `wait_all()`

## 5. `rex::time`

- `sleep(ms)`, `sleep_s(seconds)`
- `now_ms()`, `now_s()`, `now_ns()`
- `since(start)`

## 6. `rex::fmt`

- `format(value) -> str`

## 7. `rex::mem`

- `alloc<T>()`, `free(ptr)`
- `box(value)`, `unbox(ptr)`
- `drop(value)`

## 8. `rex::math`

- `sqrt(x)`, `abs(x)`
- `eval(&expr) -> Result<num>`

## 9. `rex::collections`

Vector:
- `vec_new<T>()`
- `vec_from(a, b, c, ...)`
- `vec_push(&mut v, x)`
- `vec_get(&v, i)`
- `vec_set(&mut v, i, x)`
- `vec_len(&v)`
- `vec_insert(&mut v, i, x)`
- `vec_pop(&mut v)`
- `vec_clear(&mut v)`
- `vec_sort(&mut v)`
- `vec_slice(&v, start, end)`

Map:
- `map_new<K, V>()`
- `map_put(&mut m, key, value)`
- `map_get(&m, key)`
- `map_remove(&mut m, key)`
- `map_has(&m, key)`
- `map_keys(&m)`

Set:
- `set_new<T>()`
- `set_add(&mut s, value)`
- `set_has(&s, value)`
- `set_remove(&mut s, value)`

## 10. `rex::os`

- `getenv(&key)`
- `cwd()`
- `platform()`
- `args()`
- `home()`
- `temp_dir()`

## 11. `rex::path`

- `join(&a, &b)`
- `basename(&path)`
- `dirname(&path)`
- `ext(&path)`
- `stem(&path)`
- `is_abs(&path)`

## 12. `rex::audio`

- `play(&path)`, `play_loop(&path)`, `stop()`
- `supports(&ext)`
- `set_volume(v)`, `volume()`

## 13. `rex::log`

- `debug(x)`, `info(x)`, `warn(x)`, `error(x)`
- `set_level(x)`, `level()`

## 14. `rex::net` and `rex::http`

Networking:
- `net.tcp_connect(&addr) -> Result<str>`
- `net.udp_socket() -> Result<str>`

HTTP:
- `http.get(&url) -> Result<str>`
- `http.get_status(&url) -> Result<Map<str, str>>`
- `http.get_json<T>(&url) -> Result<T>`

## 15. `rex::random`

- `seed(n)`
- `int(min, max)`, `float()`, `bool(probability)`
- `choice(&vec)`, `shuffle(&mut vec)`
- `range(min, max)`

## 16. `rex::json`

- `encode(value) -> Result<str>`
- `encode_pretty(value, indent) -> Result<str>`
- `decode<T>(&text) -> Result<T>`

## 17. `rex::result`

- `Ok(x)`
- `Err(e)`

## 18. `rex::ui`

UI module exposes window/input/widget helpers, including:
- lifecycle: `begin`, `end`, `redraw`, `clear`
- input: keyboard/mouse state helpers
- widgets: `label`, `button`, `checkbox`, `slider`, `textbox`, etc.
- layout helpers: `row`, `column`, `grid`, spacing, clipping, scrolling
- themes and image helpers

Check `docs/examples-index.md` and `rex/examples` for practical usage patterns,
including current language syntax such as struct literals, compound assignment,
and richer `match` forms used alongside these APIs.
