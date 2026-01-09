

fn process_data(id: i64) {
    debug ownership {
        trace: id
    }
 
    let x = id * 100
}

fn main() {
    println("Starting concurrent ownership tracing...")
    
   
    spawn {
        process_data(1)
    }
    
    spawn {
        process_data(2)
    }
    
    spawn {
        process_data(3)
    }
    
    println("All concurrent tasks spawned successfully")
}
