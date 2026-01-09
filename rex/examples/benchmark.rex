use rex::io
use rex::fmt
use rex::time

fn main() {
    let start_time = time.now_ms()

    mut sum: f64 = 0
    for i in 0..10000000 {
        sum = sum + i
    }

    let end_time = time.now_ms()
    let elapsed = end_time - start_time

    println("sum: " + fmt.format(sum))
    println("elapsed: " + fmt.format(elapsed) + "ms")
}
