using p7zip_jll: p7zip
using SHA: sha256

const MANIFEST_PATH = joinpath(dirname(@__DIR__), "data", "benchmark", "manifest.toml")

hex_sha256(bytes) = bytes2hex(sha256(bytes))

"""A fetch stand-in that serves `files[url]` and counts calls, so tests need no network."""
function fake_fetch(files::Dict{String,Vector{UInt8}}, calls::Ref{Int})
    return (url, path) -> begin
        calls[] += 1
        haskey(files, url) || error("unreachable $url")
        write(path, files[url])
        return path
    end
end

function toy_entry(text; sources)
    return Experiments.DatasetEntry(
        name="toy", version="test", file="toy.txt", sha256=hex_sha256(text),
        sources=sources, stats=Experiments.DatasetStats(
            transactions=4, items=3, total_items=9, max_width=3, min_item=1, max_item=3))
end

@testset "Benchmark data" begin
    baskets = read(joinpath(TOY_DIR, "baskets.txt"))
    text_source = Experiments.DatasetSource(url="https://example.org/toy.txt", format=:text)

    @testset "Statistics" begin
        stats = Experiments.dataset_stats(read_transactions(joinpath(TOY_DIR, "baskets.txt")))
        @test stats == Experiments.DatasetStats(
            transactions=4, items=3, total_items=9, max_width=3, min_item=1, max_item=3)
        @test Experiments.mean_width(stats) == 9 / 4
        empty_stats = Experiments.dataset_stats(Vector{Int}[])
        @test empty_stats.transactions == 0 && empty_stats.items == 0
        @test Experiments.mean_width(empty_stats) == 0.0
    end

    @testset "Committed manifest" begin
        manifest = Experiments.load_manifest(MANIFEST_PATH)
        @test sort!(collect(keys(manifest))) == ["T10I4D100K", "chess", "mushroom", "retail"]
        for entry in values(manifest)
            @test length(entry.sha256) == 64
            @test !isempty(entry.sources)
            @test all(s -> startswith(s.url, "https://"), entry.sources)
            # SPMF rejects item 0, so every benchmark must start its IDs at 1.
            @test entry.stats.min_item >= 1
        end
        @test manifest["chess"].stats.transactions == 3196
        @test manifest["retail"].stats.items == 16470
    end

    @testset "Invalid manifest" begin
        bad = """
        [toy]
        version = "x"
        file = "toy.txt"
        transactions = 1
        """
        err = try
            Experiments.parse_manifest(bad)
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("toy", err.msg) && occursin("sha256", err.msg)
        bad_format = replace(read(MANIFEST_PATH, String), "format = \"text\"" => "format = \"zip\"")
        @test_throws ArgumentError Experiments.parse_manifest(bad_format)
    end

    @testset "Raw files without transaction statistics" begin
        csv_sha = hex_sha256("a,b\n")
        raw = """
        [receipts]
        version = "x"
        file = "receipts.csv"
        sha256 = "$csv_sha"

        [[receipts.sources]]
        url = "https://example.org/receipts.csv"
        format = "text"
        """
        entry = Experiments.parse_manifest(raw)["receipts"]
        @test entry.stats === nothing
        partial = replace(raw, "sha256" => "transactions = 1\nsha256")
        @test_throws ArgumentError Experiments.parse_manifest(partial)
        mktempdir() do dir
            fetch = fake_fetch(Dict(entry.sources[1].url => Vector{UInt8}("a,b\n")), Ref(0))
            @test read(Experiments.prepare_dataset(entry, dir; fetch), String) == "a,b\n"
        end
    end

    @testset "Download, verify, and cache" begin
        mktempdir() do dir
            calls = Ref(0)
            fetch = fake_fetch(Dict(text_source.url => baskets), calls)
            entry = toy_entry(baskets; sources=[text_source])
            path = Experiments.prepare_dataset(entry, dir; fetch)
            @test read(path) == baskets
            @test calls[] == 1
            @test Experiments.prepare_dataset(entry, dir; fetch) == path
            @test calls[] == 1
        end
    end

    @testset "Fall back to the next source" begin
        mktempdir() do dir
            calls = Ref(0)
            backup = Experiments.DatasetSource(url="https://mirror.example.org/toy.txt", format=:text)
            fetch = fake_fetch(Dict(backup.url => baskets), calls)
            path = Experiments.prepare_dataset(toy_entry(baskets; sources=[text_source, backup]), dir; fetch)
            @test read(path) == baskets
            @test calls[] == 2
        end
    end

    @testset "Reject wrong bytes without leaving a file" begin
        mktempdir() do dir
            fetch = fake_fetch(Dict(text_source.url => Vector{UInt8}("1 2\n")), Ref(0))
            entry = toy_entry(baskets; sources=[text_source])
            err = try
                Experiments.prepare_dataset(entry, dir; fetch)
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin(text_source.url, err.msg) && occursin("SHA-256", err.msg)
            @test readdir(dir) == String[]
        end
    end

    @testset "Reject statistics that disagree with the manifest" begin
        mktempdir() do dir
            fetch = fake_fetch(Dict(text_source.url => baskets), Ref(0))
            good = toy_entry(baskets; sources=[text_source])
            wrong = Experiments.DatasetEntry(
                name=good.name, version=good.version, file=good.file, sha256=good.sha256,
                sources=good.sources, stats=Experiments.DatasetStats(
                    transactions=5, items=3, total_items=9, max_width=3, min_item=1, max_item=3))
            @test_throws ErrorException Experiments.prepare_dataset(wrong, dir; fetch)
            @test readdir(dir) == String[]
        end
    end

    @testset "Decompress gzip sources" begin
        mktempdir() do dir
            plain = joinpath(dir, "toy.dat")
            write(plain, baskets)
            archive = joinpath(dir, "toy.dat.gz")
            run(pipeline(`$(p7zip()) a -tgzip $archive $plain`; stdout=devnull))
            source = Experiments.DatasetSource(url="https://example.org/toy.dat.gz", format=:gzip)
            fetch = fake_fetch(Dict(source.url => read(archive)), Ref(0))
            out = mkpath(joinpath(dir, "out"))
            path = Experiments.prepare_dataset(toy_entry(baskets; sources=[source]), out; fetch)
            @test read(path) == baskets
            @test readdir(out) == ["toy.txt"]
        end
    end
end
