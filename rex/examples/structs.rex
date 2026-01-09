use rex::io
use rex::math

type Vec2 = Point;

struct Point { x: f64, y: f64 }

impl Point {
    fn len(&self) -> f64 {
        return sqrt(self.x * self.x + self.y * self.y)
    }
}

fn main() {
    let p: Vec2 = Point.new(3, 4)
    mut q = Point.new(5, 12)
    q.x = 6
    println(p.len())
    println(q.len())
}
