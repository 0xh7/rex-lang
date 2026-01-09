use rex::io

enum Option { Some(i32), None }

impl Option {
    fn is_some(&self) -> bool {
        match self {
            Some(x) => true,
            None => false,
        }
    }
}

fn show(v: Option) {
    match v {
        Some(x) => println("value = " + x),
        None => println("empty"),
    }
}

fn main() {
    let a = Option.Some(7)
    let b = Option.None
    println(a.is_some())
    println(b.is_some())
    show(a)
    show(b)
}
