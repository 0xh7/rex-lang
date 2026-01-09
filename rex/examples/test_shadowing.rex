fn test_basic_shadowing() {
  let x = 10
  println(x)
  if true {
    let x = 20
    println(x)
  }
  println(x)
}

fn test_multiple_shadows() {
  let x = 1
  println(x)
  if true {
    let x = 2
    println(x)
    if true {
      let x = 3
      println(x)
    }
    println(x)
  }
  println(x)
}

fn test_reassign_in_scope() {
  let x = 100
  println(x)
  if true {
    let x = 300
    println(x)
  }
  println(x)
}

fn main() {
  test_basic_shadowing()
  test_multiple_shadows()
  test_reassign_in_scope()
}
