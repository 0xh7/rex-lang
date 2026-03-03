use rex::io
use rex::fmt



fn main() {
    // += on a plain variable
    mut x: f64 = 10
    x += 5
    println(x)          // 15

    // -=
    x -= 3
    println(x)          // 12

    // *=
    x *= 2
    println(x)          // 24

    // /=
    x /= 4
    println(x)          // 6

    // %=
    mut r: f64 = 17
    r %= 5
    println(r)          // 2

    // += on an array element
    mut v = [1, 2, 3]
    v[0] += 10
    println(v[0])       // 11

    // += accumulator pattern (previously needed sum = sum + i)
    mut sum: f64 = 0
    for i in 0..5 {
        sum += i
    }
    println(sum)        // 10  (0+1+2+3+4)
}
