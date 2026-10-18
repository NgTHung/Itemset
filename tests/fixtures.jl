const TOY_DIR = joinpath(dirname(@__DIR__), "data", "toy")

const MINING_CASES = [
    (name="baskets", minsup=0.5, expected=SupportMap(
        (1,)=>3, (2,)=>3, (3,)=>3, (1,2)=>2, (1,3)=>2, (2,3)=>2)),
    (name="duplicates", minsup=2, expected=SupportMap((1,)=>2, (2,)=>3, (1,2)=>2)),
    (name="disjoint", minsup=2, expected=SupportMap()),
    (name="dense", minsup=2, expected=SupportMap(
        (1,)=>2, (2,)=>2, (3,)=>2, (1,2)=>2, (1,3)=>2, (2,3)=>2, (1,2,3)=>2)),
    (name="empty", minsup=1, expected=SupportMap()),
]
