use rex::io
use rex::collections as col

fn main() {
    mut v = [10, 20, 30, 40]
    v[1] = 99
    println(v[1])

    let slice = v[0..2]
    println(col.vec_len(&slice))

    mut extra = col.vec_from(7, 8, 9)
    col.vec_push(&mut extra, 10)
    println(col.vec_len(&extra))
    col.vec_insert(&mut extra, 1, 99)
    col.vec_sort(&mut extra)
    println("pop: " + col.vec_pop(&mut extra))
    col.vec_clear(&mut extra)
    println("after clear: " + col.vec_len(&extra))

    mut m = col.map_new<str, i32>()
    col.map_put(&mut m, "a", 42)
    println(col.map_get(&m, "a"))
    println("has a: " + col.map_has(&m, "a"))
    let keys = col.map_keys(&m)
    for k in keys {
        println("key: " + k)
    }
    println("removed a: " + col.map_remove(&mut m, "a"))

    mut s = col.set_new<str>()
    col.set_add(&mut s, "x")
    println(col.set_has(&s, "x"))
    println("removed x: " + col.set_remove(&mut s, "x"))
}
