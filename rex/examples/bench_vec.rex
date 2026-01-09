use rex::io
use rex::fmt
use rex::time
use rex::collections as col

fn main() {
    let count = 200000
    let start = time.now_ms()
    mut v = col.vec_new<i32>()
    for i in 0..count {
        col.vec_push(&mut v, i)
    }
    let end = time.now_ms()
    println("vec_len: " + fmt.format(col.vec_len(&v)))
    println("elapsed: " + fmt.format(end - start) + "ms")
}
