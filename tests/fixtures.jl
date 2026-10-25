import TOML

const TOY_DIR = joinpath(dirname(@__DIR__), "data", "toy")
const SPMF_TOY_DIR = joinpath(TOY_DIR, "spmf")
const SPMF_TOY_RUNS = [(input=r["input"], minsup=r["minsup"], count=r["count"], output=r["output"])
                       for r in TOML.parsefile(joinpath(SPMF_TOY_DIR, "runs.toml"))["run"]]

const MINING_CASES = [
    (name="baskets", minsup=0.5, expected=SupportMap(
        (1,)=>3, (2,)=>3, (3,)=>3, (1,2)=>2, (1,3)=>2, (2,3)=>2)),
    (name="duplicates", minsup=2, expected=SupportMap((1,)=>2, (2,)=>3, (1,2)=>2)),
    (name="disjoint", minsup=2, expected=SupportMap()),
    (name="dense", minsup=2, expected=SupportMap(
        (1,)=>2, (2,)=>2, (3,)=>2, (1,2)=>2, (1,3)=>2, (2,3)=>2, (1,2,3)=>2)),
    (name="boundary", minsup=2, expected=SupportMap((1,)=>2, (2,)=>2)),
    (name="nested", minsup=2, expected=SupportMap((1,)=>3, (2,)=>2, (1,2)=>2)),
    (name="empty", minsup=1, expected=SupportMap()),
    (name="groceries", minsup=0.4, expected=SupportMap(
        (2,)=>4, (3,)=>3, (4,)=>3, (2,3)=>3, (2,4)=>2)),
]

const BOUNDARY_LOW_EXPECTED = SupportMap((1,)=>2, (2,)=>2, (3,)=>1, (1,2)=>1)

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

# In memory because image 3 has no visual words, and SPMF text cannot encode an
# empty transaction.
const IMAGE_CASE = (
    words = ["corner", "edge", "texture"],
    # Rows are images, columns are visual-word IDs.
    presence = Bool[1 1 0; 1 1 1; 0 0 0; 0 1 1],
    transactions = [[1, 2], [1, 2, 3], Int[], [2, 3]],
    minsup = 0.5,
    expected = SupportMap((1,)=>2, (2,)=>3, (3,)=>2, (1,2)=>2, (2,3)=>2),
    supporting_images = Dict((1,)=>[1, 2], (2,)=>[1, 2, 4], (3,)=>[2, 4], (1,2)=>[1, 2], (2,3)=>[2, 4]),
    # At 0.6 the empty image decides the threshold: 3 of 4 images, or 2 of 3 without it.
    sensitive_minsup = 0.6,
    sensitive_expected = SupportMap((2,)=>3),
)

# Raw receipts in the Online Retail II layout. Each cleaning step removes the
# rows its comment names, so a reordered or missing step changes a count.
const RECEIPT_CASE = (
    file = "receipts.csv",
    steps = [
        (name="raw", removed=0, rows=14, invoices=6),
        (name="duplicate rows", removed=1, rows=13, invoices=6),          # row 3
        (name="cancelled invoices", removed=1, rows=12, invoices=5),      # C1004
        (name="adjustment invoices", removed=1, rows=11, invoices=4),     # A1005
        (name="nonpositive quantity", removed=1, rows=10, invoices=4),    # 21232 check
        (name="nonpositive price", removed=1, rows=9, invoices=4),        # 22728 at 0.0
        (name="non-product codes", removed=2, rows=7, invoices=3),        # POST, M
    ],
    invoices = ["1001", "1002", "1006"],
    # 85123a and 85123A are one product; IDs follow sorted stock codes.
    codes = ["22728", "71053", "85099B", "85123A"],
    descriptions = ["ALARM CLOCK BAKELIKE PINK", "WHITE METAL LANTERN",
                    "JUMBO BAG \"RED\" RETROSPOT", "WHITE HANGING HEART T-LIGHT HOLDER"],
    transactions = [[2, 4], [1, 4], [1, 2, 3]],
)
