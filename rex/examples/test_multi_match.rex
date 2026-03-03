use rex::io


enum Direction { North, South, East, West }

fn axis(d: Direction) {
    match d {
        North | South => println("vertical"),
        East  | West  => println("horizontal"),
    }
}

enum Status { Ok, Warn, Error, Fatal }

fn severity(s: Status) {
    match s {
        Ok           => println("fine"),
        Warn         => println("warning"),
        Error | Fatal => println("bad"),
    }
}

fn main() {
    axis(Direction.North)   // vertical
    axis(Direction.East)    // horizontal
    axis(Direction.South)   // vertical
    axis(Direction.West)    // horizontal

    severity(Status.Ok)     // fine
    severity(Status.Warn)   // warning
    severity(Status.Error)  // bad
    severity(Status.Fatal)  // bad

    // Multi-tag combined with wildcard (Features 2 + 5)
    let x = Status.Warn
    match x {
        Ok | Warn => println("acceptable"),
        _         => println("not acceptable"),
    }
}
