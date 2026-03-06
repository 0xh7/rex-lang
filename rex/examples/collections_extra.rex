use rex::io
use rex::collections as col

fn main() {
    let nums = [1, 2, 3, 2]
    let twos = [2, 2, 2]
    let words = ["rex", "lang", "native"]
    let dash = "-"

    println(col.vec_find(&nums, 2))
    println(col.vec_any(&nums, 3))
    println(col.vec_all(&twos, 2))
    println(col.vec_contains(&nums, 1))
    println(col.vec_first(&nums))
    println(col.vec_last(&nums))
    println(col.vec_join(&words, &dash))

    mut changed = [5, 6, 7, 8]
    println(col.vec_remove_at(&mut changed, 1))
    col.vec_reverse(&mut changed)
    println(col.vec_first(&changed))
    println(col.vec_last(&changed))

    mut m = col.map_new<str, i32>()
    col.map_put(&mut m, "a", 10)
    col.map_put(&mut m, "b", 20)

    let values = col.map_values(&m)
    let items = col.map_items(&m)

    println(col.vec_len(&values))
    println(col.vec_len(&items))
    println(col.map_len(&m))

    mut s = col.set_new<str>()
    col.set_add(&mut s, "x")
    col.set_add(&mut s, "y")
    println(col.set_len(&s))
}
