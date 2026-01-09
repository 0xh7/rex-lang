fn test_commit() {
    bond x = 42
    x = 100
    x = 200
    commit
    println("test_commit ok")
}

fn test_rollback() {
    bond y = 10
    y = 20
    rollback
    println("test_rollback ok")
}

fn test_copy_types() {
    bond count = 42
    count = 100
    count = 200
    commit
    println("test_copy_types ok")
}

fn test_sequential_bonds() {
    bond a = 1
    a = 2
    commit
    
    bond b = 10
    b = 20
    commit
    
    println("test_sequential ok")
}

fn test_conditional_bond() {
    bond val = 0
    val = 100
    commit
    println("test_conditional ok")
}

fn main() {
    println("Rex Bonds Test Suite")
    test_commit()
    test_rollback()
    test_copy_types()
    test_sequential_bonds()
    test_conditional_bond()
    println("All tests passed")
}
