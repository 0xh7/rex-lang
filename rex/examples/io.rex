use rex::io
use rex::fmt
use rex::fs
use rex::collections as col

fn main() {
    let path = "rex_io_demo.txt"
    let lines_path = "rex_io_lines.txt"
    let data = "hello from rex"

    match io.write_file(&path, data) {
        Ok(done) => println("write ok: " + fmt.format(done)),
        Err(e) => println("write error: " + e),
    }

    match io.read_file(&path) {
        Ok(text) => println("read: " + text),
        Err(e) => println("read error: " + e),
    }

    let lines = col.vec_from("one", "two", "three")
    match io.write_lines(&lines_path, &lines) {
        Ok(done) => println("write lines ok: " + fmt.format(done)),
        Err(e) => println("write lines error: " + e),
    }
    match io.read_lines(&lines_path) {
        Ok(items) => {
            for line in items {
                println("line: " + line)
            }
        },
        Err(e) => println("read lines error: " + e),
    }
    match fs.remove(&path) {
        Ok(done) => println("remove ok: " + fmt.format(done)),
        Err(e) => println("remove error: " + e),
    }
    match fs.remove(&lines_path) {
        Ok(done) => println("remove ok: " + fmt.format(done)),
        Err(e) => println("remove error: " + e),
    }
}
