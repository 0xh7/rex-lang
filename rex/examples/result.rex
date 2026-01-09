use rex::io
use rex::fmt

fn read_or_default(path: str) -> str {
    mut out: str = "default"
    match io.read_file(&path) {
        Ok(text) => { out = text },
        Err(e) => { println("read failed: " + e) },
    }
    return out
}

fn main() {
    let v = read_or_default("missing.txt")
    println("value: " + v)
    println("marker: " + fmt.format(123))
}
