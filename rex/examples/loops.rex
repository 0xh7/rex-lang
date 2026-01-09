use rex::io

fn main() {
    mut x: i32 = 0
    while x < 3 {
        println(x)
        x = x + 1
    }

    for i in 0..10 {
        if i == 3 {
            continue
        }
        if i == 7 {
            break
        }
        println(i)
    }

    let v = [10, 20, 30]
    let part = v[0..2]
    println(part[1])
    for n in v {
        println(n)
    }

    if x == 3 {
        println("done")
    } else {
        println("oops")
    }
}
