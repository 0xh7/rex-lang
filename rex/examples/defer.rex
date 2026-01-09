use rex::io

fn main() {
    let v = [1, 2, 3]
    defer {
        println("cleanup")
        drop(v)
    }
    println(v[1])
}
