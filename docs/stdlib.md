# Rex Standard Library Guide

Rex exposes runtime functionality through modules imported with `use`.

Example:

```rex
use rex::io
use rex::time
```

Current module map:

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
- `pad_left(value, width, &fill) -> str`
- `pad_right(value, width, &fill) -> str`
- `join(&parts, &sep) -> str`
- `fixed(number, digits) -> str`
- `hex(number) -> str`
- `bin(number) -> str`

## 7. `rex::text`

- `initials(&text) -> str`
- `lower_ascii(&text) -> str`
- `pad_left(&text, width, &fill) -> str`
- `pad_right(&text, width, &fill) -> str`
- `trim(&text) -> str`
- `trim_start(&text) -> str`
- `trim_end(&text) -> str`
- `split_words(&text) -> Vec<str>`
- `starts_with(&text, &prefix) -> bool`
- `ends_with(&text, &suffix) -> bool`
- `contains(&text, &needle) -> bool`
- `replace(&text, &from, &to) -> str`
- `repeat(&text, count) -> str`
- `lines(&text) -> Vec<str>`
- `upper_ascii(&text) -> str`
- `is_empty(&text) -> bool`
- `len_bytes(&text) -> num`
- `index_of(&text, &needle) -> num`
- `last_index_of(&text, &needle) -> num`

## 8. `rex::mem`

- `alloc<T>()`, `free(ptr)`
- `box(value)`, `unbox(ptr)`
- `drop(value)`

## 9. `rex::math`

- `sqrt(x)`, `abs(x)`
- `eval(&expr) -> Result<num>`

## 10. `rex::collections`

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
- `vec_find(&v, value) -> index or -1`
- `vec_any(&v, value) -> bool`
- `vec_all(&v, value) -> bool`
- `vec_contains(&v, value) -> bool`
- `vec_remove_at(&mut v, index)`
- `vec_reverse(&mut v)`
- `vec_first(&v)`
- `vec_last(&v)`
- `vec_join(&v, &sep) -> str`

Map:
- `map_new<K, V>()`
- `map_put(&mut m, key, value)`
- `map_get(&m, key)`
- `map_remove(&mut m, key)`
- `map_has(&m, key)`
- `map_keys(&m)`
- `map_values(&m)`
- `map_items(&m)`
- `map_len(&m)`

Set:
- `set_new<T>()`
- `set_add(&mut s, value)`
- `set_has(&s, value)`
- `set_remove(&mut s, value)`
- `set_len(&s)`

## 11. `rex::os`

- `getenv(&key)`
- `cwd()`
- `platform()`
- `args()`
- `home()`
- `temp_dir()`

## 12. `rex::path`

- `join(&a, &b)`
- `basename(&path)`
- `dirname(&path)`
- `ext(&path)`
- `stem(&path)`
- `is_abs(&path)`

## 13. `rex::audio`

- `play(&path)`, `play_loop(&path)`, `stop()`
- `supports(&ext)`
- `set_volume(v)`, `volume()`

## 14. `rex::log`

- `debug(x)`, `info(x)`, `warn(x)`, `error(x)`
- `set_level(x)`, `level()`

## 15. `rex::net` and `rex::http`

Networking:
- `net.tcp_connect(&addr) -> Result<str>`
- `net.udp_socket() -> Result<str>`

HTTP:
- `http.get(&url) -> Result<str>`
- `http.get_status(&url) -> Result<Map<str, str>>`
- `http.get_json<T>(&url) -> Result<T>`

## 16. `rex::random`

- `seed(n)`
- `int(min, max)`, `float()`, `bool(probability)`
- `choice(&vec)`, `shuffle(&mut vec)`
- `range(min, max)`

## 17. `rex::json`

- `encode(value) -> Result<str>`
- `encode_pretty(value, indent) -> Result<str>`
- `decode<T>(&text) -> Result<T>`

## 18. `rex::result`

- `Ok(x)`
- `Err(e)`
- `is_ok(result) -> bool`
- `is_err(result) -> bool`
- `unwrap_or(result, fallback)`
- `unwrap_or_else(result, fallback)`
- `ok_or(value, err) -> Result`
- `expect(result, &message)`

## 19. `rex::ui`

UI module exposes window/input/widget helpers, including:
- lifecycle: `begin`, `end`, `redraw`, `clear`
- input: keyboard/mouse state helpers
- widgets: `label`, `button`, `checkbox`, `slider`, `textbox`, etc.
- layout helpers: `row`, `column`, `grid`, spacing, clipping, scrolling
- themes and image helpers

Check `docs/examples-index.md` and `rex/examples` for practical usage patterns,
including current language syntax such as struct literals, compound assignment,
and richer `match` forms used alongside these APIs.
