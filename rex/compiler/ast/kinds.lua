local groups = {
  item = {
    "Program",
    "Use",
    "Struct",
    "TypeAlias",
    "Enum",
    "Impl",
    "Function",
  },
  statement = {
    "Block",
    "Let",
    "Bond",
    "Commit",
    "Rollback",
    "Defer",
    "Return",
    "If",
    "While",
    "For",
    "Break",
    "Continue",
    "Match",
    "Unsafe",
    "Spawn",
    "Assign",
    "MemberAssign",
    "IndexAssign",
    "DerefAssign",
    "ExprStmt",
    "WithinBlock",
    "DuringBlock",
    "DebugOwnership",
  },
  expression = {
    "Bool",
    "Nil",
    "Number",
    "String",
    "Array",
    "Identifier",
    "Binary",
    "Unary",
    "Borrow",
    "Deref",
    "Call",
    "Member",
    "Index",
    "Slice",
    "Try",
    "Generic",
    "StructLit",
  },
  pattern = {
    "TuplePattern",
    "IdentPattern",
  },
  temporal = {
    "TemporalValue",
    "OwnershipTrace",
  },
}

local by_name = {}
for group_name, list in pairs(groups) do
  for _, kind in ipairs(list) do
    by_name[kind] = group_name
  end
end

return {
  groups = groups,
  by_name = by_name,
}
