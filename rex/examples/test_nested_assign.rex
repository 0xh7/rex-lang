use rex::io
use rex::fmt


struct Inner { value: f64 }
struct Outer { inner: Inner, label: str }

impl Inner {
    fn get(&self) -> f64 {
        return self.value
    }
}

fn main() {
    mut o = Outer.new(Inner.new(0), "test")

    o.label = "hello"
    println(o.label)            // hello

    // two-level nested assign (new)
    o.inner.value = 99
    println(o.inner.get())      // 99

    // compound nested assign (Features 1 + 3)
    o.inner.value += 1
    println(fmt.format(o.inner.get()))  // 100
}
