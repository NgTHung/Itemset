"""
Benchmark tooling shared by every experiment owner. It sits outside the
`ItemsetMining` package and uses only its public API, so measuring the miner
never depends on algorithm internals.
"""
module Experiments

using ItemsetMining
using Downloads: Downloads
using p7zip_jll: p7zip
using SHA: sha256
using TOML: TOML

include("datasets.jl")

end
