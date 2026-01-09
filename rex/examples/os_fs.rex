use rex::io
use rex::os
use rex::fs

fn main() {
    println("cwd: " + os.cwd())
    let path = "rex_data"
    if fs.exists(&path) {
        println("exists: rex_data")
    } else {
        match fs.mkdir(&path) {
            Ok(done) => println("created: rex_data"),
            Err(e) => println("mkdir error: " + e),
        }
    }
    let key = "PATH"
    let env = os.getenv(&key)
    if env != nil {
        println("PATH set")
    } else {
        println("PATH missing")
    }
}
