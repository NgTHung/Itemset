using SHA: sha256

const MANIFEST_PATH = joinpath(dirname(@__DIR__), "data", "benchmark", "manifest.toml")

"""A fetch stand-in that serves `files[url]` and counts calls, so tests need no network."""
function fake_fetch(files::Dict{String,Vector{UInt8}}, calls::Ref{Int})
    return (url, path) -> begin
        calls[] += 1
        haskey(files, url) || error("unreachable $url")
        write(path, files[url])
        return path
    end
end

function toy_entry(bytes; sources, transactions=4)
    return Experiments.DatasetEntry(
        name="toy", version="test", file="toy.txt", sha256=bytes2hex(sha256(bytes)),
        sources=sources, stats=Experiments.DatasetStats(
            transactions=transactions, items=3, total_items=9, max_width=3, min_item=1, max_item=3))
end

@testset "Benchmark data" begin
    baskets = read(joinpath(TOY_DIR, "baskets.txt"))
    text_source = Experiments.DatasetSource(url="https://example.org/toy.txt", format=:text)

    @testset "Committed manifest" begin
        manifest = Experiments.load_manifest(MANIFEST_PATH)
        @test sort!(collect(keys(manifest))) == ["T10I4D100K", "accidents", "chess", "mushroom", "retail"]
        for entry in values(manifest)
            @test length(entry.sha256) == 64
            # SPMF rejects item 0, so every benchmark must start its IDs at 1.
            @test entry.stats.min_item >= 1
        end
        @test_throws "sha256" Experiments.parse_manifest("[toy]\nversion = \"x\"\nfile = \"toy.txt\"\ntransactions = 1\n")
    end

    @testset "Download, verify, and cache" begin
        mktempdir() do dir
            calls = Ref(0)
            fetch = fake_fetch(Dict(text_source.url => baskets), calls)
            entry = toy_entry(baskets; sources=[text_source])
            path = Experiments.prepare_dataset(entry, dir; fetch)
            @test read(path) == baskets
            @test Experiments.prepare_dataset(entry, dir; fetch) == path
            @test calls[] == 1
        end
    end

    @testset "Reject wrong bytes or statistics without leaving a file" begin
        mktempdir() do dir
            fetch = fake_fetch(Dict(text_source.url => Vector{UInt8}("1 2\n")), Ref(0))
            @test_throws "SHA-256" Experiments.prepare_dataset(toy_entry(baskets; sources=[text_source]), dir; fetch)
            @test readdir(dir) == String[]
            fetch = fake_fetch(Dict(text_source.url => baskets), Ref(0))
            wrong_stats = toy_entry(baskets; sources=[text_source], transactions=5)
            @test_throws ErrorException Experiments.prepare_dataset(wrong_stats, dir; fetch)
            @test readdir(dir) == String[]
        end
    end

    @testset "ZIP mirror and source provenance" begin
        zip_source = Experiments.DatasetSource(url="https://example.org/toy.zip", format=:zip)
        entry = toy_entry(baskets; sources=[zip_source, text_source])
        mktempdir() do fixture
            mkpath(joinpath(fixture, "nested"))
            write(joinpath(fixture, "nested", "toy.txt"), baskets)
            write(joinpath(fixture, "README.txt"), "archive metadata")
            archive = joinpath(fixture, "toy.zip")
            run(pipeline(Cmd(`$(Experiments.p7zip()) a -tzip $archive nested README.txt`; dir=fixture);
                stdout=devnull, stderr=devnull))
            mktempdir() do dir
                calls = Ref(0)
                fetch = fake_fetch(Dict(zip_source.url => read(archive)), calls)
                downloaded = Experiments.prepare_dataset_with_source(entry, dir; fetch)
                @test downloaded == (; path=joinpath(dir, "toy.txt"), source_url=zip_source.url)
                @test read(downloaded.path) == baskets
                @test Experiments.prepare_dataset_with_source(entry, dir; fetch).source_url == ""
                @test calls[] == 1
                @test readdir(dir) == ["toy.txt"]
            end
            mktempdir() do dir
                missing_archive = joinpath(fixture, "missing.zip")
                run(pipeline(Cmd(`$(Experiments.p7zip()) a -tzip $missing_archive README.txt`; dir=fixture);
                    stdout=devnull, stderr=devnull))
                calls = Ref(0)
                fetch = fake_fetch(Dict(zip_source.url => read(missing_archive), text_source.url => baskets), calls)
                zip_only = toy_entry(baskets; sources=[zip_source])
                @test_throws "README.txt" Experiments.prepare_dataset(zip_only, dir; fetch)
                @test isempty(readdir(dir))
                @test Experiments.prepare_dataset_with_source(entry, dir; fetch).source_url == text_source.url
                @test calls[] == 3
            end
        end
    end
end
