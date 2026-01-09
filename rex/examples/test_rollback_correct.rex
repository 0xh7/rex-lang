fn test_rollback_correct() {
    bond x = 10
    x = 20
    rollback
    let y = 30
    println(y)
}

fn main() {
    test_rollback_correct()
}
