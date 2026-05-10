extends RefCounted

# Damage element types. Shared by player attacks and dummy resistances.
# Values are also reused for Dummy.weakness via @export_enum (order matters).
const NEUTRAL := 0
const FIRE := 1
const WATER := 2
const WIND := 3
const EARTH := 4
