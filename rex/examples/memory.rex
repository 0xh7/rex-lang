use rex::io

fn main() {
    unsafe {
        let p = alloc<i32>();
        *p = 9
        println(*p)
        free(p)
    }
    let b = box(7)
    println(*b)
    drop(b)
}
