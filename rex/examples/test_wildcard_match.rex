use rex::io


enum Color { Red, Green, Blue, Yellow }

fn describe(c: Color) {
    match c {
        Red   => println("red"),
        Green => println("green"),
        _     => println("other"),   // catches Blue and Yellow
    }
}

fn first_or_zero(opt: Option) -> i32 {
    match opt {
        Some(x) => x,
        _       => 0,
    }
}

enum Option { Some(i32), None }

fn main() {
    describe(Color.Red)     // red
    describe(Color.Green)   // green
    describe(Color.Blue)    // other
    describe(Color.Yellow)  // other

    println(first_or_zero(Option.Some(42)))   // 42
    println(first_or_zero(Option.None))       // 0
}
