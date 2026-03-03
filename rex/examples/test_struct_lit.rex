use rex::io
use rex::fmt



struct Vec2 { x: f64, y: f64 }

impl Vec2 {
    fn len(&self) -> f64 {
        return sqrt(self.x * self.x + self.y * self.y)
    }
}

struct Person { name: str, age: f64 }

fn greet(p: Person) {
    println("hello " + p.name)
}

fn main() {
    // Struct literal instead of Vec2.new(3, 4)
    let p = Vec2 { x: 3.0, y: 4.0 }
    println(fmt.format(p.len()))    // 5

    // Works as function argument
    greet(Person { name: "Alice", age: 30 })  // hello Alice

    // Works in let with explicit type
    let v: Vec2 = Vec2 { x: 0.0, y: 1.0 }
    println(fmt.format(v.y))        // 1

    // Fields may be given in declaration order or any order
    let q = Vec2 { y: 12.0, x: 5.0 }
    println(fmt.format(q.len()))    // 13
}
