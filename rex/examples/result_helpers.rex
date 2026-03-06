use rex::io
use rex::math
use rex::result

fn main() {
    let good = "2 + 2"
    let bad = "bad"
    let answer = "7 * 6"
    let expected_math = "math expression failed"
    let missing_a = "missing"
    let missing_b = "missing"

    println(result.is_ok(math.eval(&good)))
    println(result.is_err(math.eval(&bad)))
    println(result.unwrap_or(math.eval(&answer), -1))
    println(result.unwrap_or(math.eval(&bad), -1))
    println(result.unwrap_or_else(math.eval(&bad), -2))
    println(result.expect(math.eval(&answer), &expected_math))
    println(result.is_ok(result.ok_or(42, missing_a)))
    println(result.is_err(result.ok_or(nil, missing_b)))
}
