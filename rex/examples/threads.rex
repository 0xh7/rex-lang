use rex::io
use rex::thread as th

fn main() {
    let (tx, rx) = th.channel<i32>()
    tx.send(1)
    tx.send(2)
    println(rx.recv())
    println(rx.recv())
}
