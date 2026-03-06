use rex::io
use rex::fmt
use rex::text
use rex::collections as col

fn main() {
    let title = "  Hello World Example  "
    let priority: i32 = 42
    let zero = "0"
    let dash = "-"
    let hello = "Hello"
    let example = "Example"
    let world = "World"
    let rex_name = "Rex"
    let equals = "="
    let space = " "
    let dots = "."
    let multi = "alpha\nbeta\r\ngamma"
    let padded_left = "   left"
    let padded_right = "right   "
    let empty = ""

    let trimmed = text.trim(&title)
    let id = text.initials(&trimmed)
    let padded = fmt.pad_left(priority, 4, &zero)
    let raw = id + ":" + padded
    let lower = text.lower_ascii(&raw)
    let upper = text.upper_ascii(&raw)
    let words = text.split_words(&trimmed)
    let lines = text.lines(&multi)

    println(lower)
    println(upper)
    println(text.starts_with(&trimmed, &hello))
    println(text.ends_with(&trimmed, &example))
    println(text.contains(&trimmed, &world))
    println(text.replace(&trimmed, &world, &rex_name))
    println(text.repeat(&equals, 5))
    println(col.vec_join(&words, &dash))
    println(fmt.join(&words, &space))
    println(col.vec_len(&lines))
    println(text.trim_start(&padded_left))
    println(text.trim_end(&padded_right))
    println(text.is_empty(&empty))
    println(text.len_bytes(&trimmed))
    println(text.index_of(&trimmed, &world))
    println(text.last_index_of(&trimmed, &world))
    println(fmt.fixed(3.14159, 2))
    println(fmt.hex(255))
    println(fmt.bin(10))
    println(text.pad_right(&rex_name, 6, &dots))
}
