const TOY_DIR = joinpath(dirname(@__DIR__), "data", "toy")

const MINING_CASES = [
    (name="baskets", minsup=0.5, expected=SupportMap(
        (1,)=>3, (2,)=>3, (3,)=>3, (1,2)=>2, (1,3)=>2, (2,3)=>2)),
    (name="duplicates", minsup=2, expected=SupportMap((1,)=>2, (2,)=>3, (1,2)=>2)),
    (name="disjoint", minsup=2, expected=SupportMap()),
    (name="dense", minsup=2, expected=SupportMap(
        (1,)=>2, (2,)=>2, (3,)=>2, (1,2)=>2, (1,3)=>2, (2,3)=>2, (1,2,3)=>2)),
    (name="empty", minsup=1, expected=SupportMap()),
    (name="groceries", minsup=0.4, expected=SupportMap(
        (2,)=>4, (3,)=>3, (4,)=>3, (2,3)=>3, (2,4)=>2)),
]

const GROCERY_ROWS = [
    ["bread", "milk"],
    ["bread", "butter"],
    ["bread", "butter", "milk"],
    ["beer", "milk"],
    ["bread", "butter"],
]

# Every rule from the groceries map, with exact measures so tests need no float tolerance.
const GROCERY_RULES = [
    (antecedent=(2,), consequent=(3,), support=3, confidence=3//4, lift=5//4),
    (antecedent=(3,), consequent=(2,), support=3, confidence=1//1, lift=5//4),
    (antecedent=(2,), consequent=(4,), support=2, confidence=1//2, lift=5//6),
    (antecedent=(4,), consequent=(2,), support=2, confidence=2//3, lift=5//6),
]
