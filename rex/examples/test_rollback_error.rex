fn test_rollback_error() {
    bond x = 10
    x = 20
    rollback

}

fn main() {
    test_rollback_error()
}
