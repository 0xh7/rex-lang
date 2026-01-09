use rex::io
use rex::fmt
use rex::time

fn main() {
    println("Hello from Rex")
    let start = time.now_ms()
    time.sleep(20)
    let elapsed = time.now_ms() - start
    println("elapsed: " + fmt.format(elapsed) + "ms")
}
