use rex::io
use rex::json
use rex::collections as col

fn main() {
    let scores = [1, 2, 3]
    mut obj = col.map_new<str, any>()
    col.map_put(&mut obj, "name", "rex")
    col.map_put(&mut obj, "scores", scores)
    col.map_put(&mut obj, "active", true)

    match json.encode_pretty(obj, 2) {
        Ok(text) => println(text),
        Err(e) => println("encode error: " + e),
    }

    let raw = "{\"ok\":true,\"nums\":[10,20,30],\"emoji\":\"\\uD83D\\uDE00\",\"nil\":null}"
    match json.decode<any>(&raw) {
        Ok(v) => {
            match json.encode_pretty(v, 2) {
                Ok(text) => println(text),
                Err(e) => println("encode error: " + e),
            }
        },
        Err(e) => println("decode error: " + e),
    }
}
