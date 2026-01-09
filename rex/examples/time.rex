use rex::io
use rex::fmt
use rex::time

fn main() {
    println("now_ms: " + fmt.format(time.now_ms()))
    println("now_s: " + fmt.format(time.now_s()))
    println("now_ns: " + fmt.format(time.now_ns()))
    let start = time.now_ms()
    time.sleep_s(0.05)
    println("since: " + fmt.format(time.since(start)) + "ms")
}
