use rex::io

struct Leaf { value: f64 }
struct Mid { leaf: Leaf }
struct Top { mid: Mid }

fn main() {
    mut t = Top.new(Mid.new(Leaf.new(1)))

    t.mid.leaf.value = 5
    println(t.mid.leaf.value)

    t.mid.leaf.value += 2
    println(t.mid.leaf.value)

    mut items = [Top.new(Mid.new(Leaf.new(3))), Top.new(Mid.new(Leaf.new(8)))]

    items[0].mid.leaf.value = 11
    println(items[0].mid.leaf.value)

    items[1].mid.leaf.value += 4
    println(items[1].mid.leaf.value)

    mut nums = [1, 2, 3]
    nums[1] = 9
    println(nums[1])

    nums[1] += 5
    println(nums[1])
}
