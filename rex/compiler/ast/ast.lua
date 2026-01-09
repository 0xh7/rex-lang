local ast = {}

function ast.node(kind, fields)
  fields.kind = kind
  return fields
end


function ast.temporal_value(name, value, lifetime)
  return ast.node("TemporalValue", {
    name = name,
    value = value,
    lifetime = lifetime  
  })
end

function ast.within_block(duration, block)
  return ast.node("WithinBlock", {
    duration = duration,
    block = block
  })
end

function ast.during_block(condition, block)
  return ast.node("DuringBlock", {
    condition = condition,
    block = block
  })
end


function ast.ownership_trace(variable, event)
  return ast.node("OwnershipTrace", {
    variable = variable,
    event = event 
  })
end

return ast
