use rex::io
use rex::thread
// Worker function 
fn work(id: i32) {
    println("worker: " + id)
}

fn main() {
    for i in 0..4 {
        let id = i
        spawn { work(id) }
    }
    thread.wait_all()
}
