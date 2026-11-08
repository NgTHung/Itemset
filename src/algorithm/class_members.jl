"""How a class member stores its tidset; the join of two members dispatches on it."""
abstract type TidsetKind end

"""`⌈N/64⌉` words of `UInt64`, bit `t - 1` set when tid `t` is in the set."""
struct Bitsets <: TidsetKind end

"""An ascending list of `Int` tids."""
struct TidLists <: TidsetKind end

"""
An ascending list of the `Int` tids in the class prefix's tidset but not in the
member's (Zaki and Gouda 2003), so the member's support is the prefix's support
minus the list's length.
"""
struct Diffsets <: TidsetKind end

"""
One member of a prefix-based equivalence class: the last item of `prefix ∪ {item}`,
that itemset's support, and its tidset in the form `K` with elements of type `T`.
"""
struct ClassMember{K<:TidsetKind,T<:Union{UInt64,Int}}
    item::Int
    support::Int
    tidset::Vector{T}
end

const BitsetMember = ClassMember{Bitsets,UInt64}
const ListMember = ClassMember{TidLists,Int}
const DiffMember = ClassMember{Diffsets,Int}

tidset_eltype(::Type{ClassMember{K,T}}) where {K,T} = T

# One tid-list merge step costs about this many bitset-join words. A BBQ sweep of 2 to 16 found 8
# fastest on T10I4D100K 0.00025 (1.20 s to 0.90 s) with Retail and T10I4D100K 0.001 unchanged; see
# docs/eclat-optimized.md.
const LIST_STEP_COST = 8.0

# A member's children take diffsets when twice its support above minsup is below this many bitset
# words per join; see docs/eclat-optimized.md.
const DIFF_RATIO = 1.0

const SWITCH_RULES = (:cost, :always, :never)

"""
Spare tidsets of each element type, reused across joins, and the rules that move
classes to tid lists and to diffsets. A rule of `:cost` compares costs with
`prefer_lists` or `prefer_diffsets`, and `:always` or `:never` force the choice.
One state serves the whole search. Throws `ArgumentError` for any other rule.
"""
struct SearchState
    bitsets::Vector{Vector{UInt64}}
    lists::Vector{Vector{Int}}
    list_rule::Symbol
    list_step_cost::Float64
    diff_rule::Symbol
    diff_ratio::Float64

    function SearchState(list_rule::Symbol=:cost, list_step_cost::Real=LIST_STEP_COST,
                         diff_rule::Symbol=:cost, diff_ratio::Real=DIFF_RATIO)
        list_rule in SWITCH_RULES ||
            throw(ArgumentError("list_rule must be :cost, :always, or :never, got $(repr(list_rule))"))
        diff_rule in SWITCH_RULES ||
            throw(ArgumentError("diff_rule must be :cost, :always, or :never, got $(repr(diff_rule))"))
        return new(Vector{UInt64}[], Vector{Int}[], list_rule, Float64(list_step_cost), diff_rule, Float64(diff_ratio))
    end
end

spare_sets(state::SearchState, ::Type{UInt64}) = state.bitsets
spare_sets(state::SearchState, ::Type{Int}) = state.lists

spare_list(state::SearchState) = isempty(state.lists) ? Int[] : pop!(state.lists)

"""
    join_tidsets!(dest, a, b, minsup, C) -> Int

Write the tidset of the child of `a` and `b` into `dest`, in the form of member
type `C`, and return the child's support, or a value below `minsup` when the
child is infrequent. `a` and `b` belong to one class with prefix P; the child is
`P ∪ {a.item, b.item}`, stored as the member `b.item` of the class with prefix
`P ∪ {a.item}`.
"""
join_tidsets!(dest::Vector{UInt64}, a::BitsetMember, b::BitsetMember, minsup::Int, ::Type{BitsetMember}) =
    intersect_bitsets!(dest, a.tidset, b.tidset)

join_tidsets!(dest::Vector{Int}, a::ListMember, b::ListMember, minsup::Int, ::Type{ListMember}) =
    intersect_lists!(dest, a.tidset, b.tidset, minsup)

# At the switch, d(Pab) = t(Pa) \ t(Pb), and the child loses one support per tid in it.
function join_tidsets!(dest::Vector{Int}, a::BitsetMember, b::BitsetMember, minsup::Int, ::Type{DiffMember})
    missing_tids = bitset_difference!(dest, a.tidset, b.tidset, a.support - minsup)
    return missing_tids < 0 ? -1 : a.support - missing_tids
end

# Inside a diffset class with prefix Q, d(Qab) = d(Qb) \ d(Qa).
function join_tidsets!(dest::Vector{Int}, a::DiffMember, b::DiffMember, minsup::Int, ::Type{DiffMember})
    missing_tids = difference_lists!(dest, b.tidset, a.tidset, a.support - minsup)
    return missing_tids < 0 ? -1 : a.support - missing_tids
end

"""An empty tidset for a child of type `C` when no spare one is left."""
new_tidset(::Type{BitsetMember}, a::BitsetMember) = similar(a.tidset)
new_tidset(::Type{C}, a::ClassMember) where {C<:Union{ListMember,DiffMember}} = Int[]

"""
Whether a class of `k` bitset members costs less as tid lists, counting the
joins of this class only. As bitsets, its `k(k - 1)/2` joins read `W = ⌈N/64⌉`
words each. As lists, each member first costs one `W`-word scan to convert, and
the joins then merge `(k - 1)` times the sum of the supports, at
`list_step_cost` words per step. A class with few members cannot repay the
conversion, and long tidsets make each merge dearer than a bitset join.
"""
function prefer_lists(children::Vector{BitsetMember}, state::SearchState)
    state.list_rule === :cost || return state.list_rule === :always
    k, words = length(children), length(first(children).tidset)
    list_cost = k * words + state.list_step_cost * (k - 1) * sum(c -> c.support, children)
    return list_cost < words * k * (k - 1) / 2
end
prefer_lists(::Vector{<:ClassMember}, ::SearchState) = false

"""
Whether the children of bitset member `a` should take diffsets. A child's
diffset holds at most `a.support - minsup` tids, so a join of two reads at most
twice that, against `⌈N/64⌉` words for a bitset join. Members of tid-list and
diffset classes keep their form.
"""
function prefer_diffsets(a::BitsetMember, minsup::Int, state::SearchState)
    state.diff_rule === :cost || return state.diff_rule === :always
    return 2 * (a.support - minsup) < state.diff_ratio * length(a.tidset)
end
prefer_diffsets(::ClassMember, ::Int, ::SearchState) = false
