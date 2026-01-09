use rex::io

fn read_text(path: str) -> Result<str> {
    let data = io.read_file(&path)?
    return Ok(data)
}

fn main() {
    match read_text("README.txt") {
        Ok(text) => println(text),
        Err(e) => println("error: " + e),
    }
}
