"""Forty distinct transactions, so a wrong subset or order changes the bytes written."""
synthetic_database() = [[1 + i % 3, 4 + i % 5, 9 + i % 7, 16 + i] for i in 1:40]

@testset "Scalability subsets" begin
    @testset "Nested seeded indices" begin
        fractions = [0.1, 0.25, 0.5, 0.75, 1.0]
        subsets = Experiments.nested_subset_indices(40, fractions; seed=DEFAULT_SEED)
        @test length.(subsets) == [4, 10, 20, 30, 40]
        @test all(issorted, subsets)
        @test all(issubset(subsets[k], subsets[k+1]) for k in 1:4)
        @test subsets[end] == 1:40
        @test Experiments.nested_subset_indices(40, fractions; seed=DEFAULT_SEED) == subsets
        @test Experiments.nested_subset_indices(40, fractions; seed=7) != subsets
        # Fraction order in the call does not change which transactions a fraction gets.
        @test Experiments.nested_subset_indices(40, reverse(fractions); seed=DEFAULT_SEED) == reverse(subsets)
        @test Experiments.nested_subset_indices(340_183, [0.25]; seed=DEFAULT_SEED)[1] |> length == 85_046
    end

    @testset "Reject unusable fractions" begin
        @test_throws "0.0" Experiments.nested_subset_indices(40, [0.0])
        @test_throws "1.5" Experiments.nested_subset_indices(40, [1.5])
        @test_throws "distinct" Experiments.nested_subset_indices(40, [0.5, 0.5])
        @test_throws "no transaction" Experiments.nested_subset_indices(40, [0.01])
    end

    @testset "Subset names" begin
        @test Experiments.subset_name("accidents", 0.1) == "accidents-p10"
        @test Experiments.subset_name("accidents", 1.0) == "accidents-p100"
        @test Experiments.subset_name("retail", 0.125) == "retail-p12.5"
    end

    @testset "Write, verify, and reload subsets" begin
        mktempdir() do dir
            database = synthetic_database()
            source = joinpath(dir, "toy.txt")
            write_transactions(source, database)
            base = Experiments.DatasetEntry(name="toy", version="test", file="toy.txt",
                sha256=Experiments.file_sha256(source), sources=Experiments.DatasetSource[],
                stats=Experiments.dataset_stats(database))
            fractions = [0.25, 1.0]
            entries = Experiments.prepare_subsets(base, source, dir, fractions; seed=DEFAULT_SEED)
            indices = Experiments.nested_subset_indices(40, fractions; seed=DEFAULT_SEED)
            @test [e.name for e in entries] == ["toy-p25", "toy-p100"]
            for (entry, kept) in zip(entries, indices)
                path = joinpath(dir, entry.file)
                @test read_transactions(path) == database[kept]
                @test entry.sha256 == Experiments.file_sha256(path)
                @test entry.stats == Experiments.dataset_stats(database[kept])
                @test occursin(base.sha256, entry.version) && occursin("seed $DEFAULT_SEED", entry.version)
            end

            manifest_path = joinpath(dir, "subsets.toml")
            Experiments.write_subset_manifest(manifest_path, entries)
            reloaded = Experiments.load_manifest(manifest_path)
            @test sort!(collect(keys(reloaded))) == ["toy-p100", "toy-p25"]
            @test reloaded["toy-p25"].sha256 == entries[1].sha256
            @test reloaded["toy-p25"].stats == entries[1].stats
            @test Experiments.prepare_dataset(reloaded["toy-p25"], dir) == joinpath(dir, "toy-p25.txt")

            # Regenerating against the recorded manifest proves the bytes are reproducible.
            again = Experiments.prepare_subsets(base, source, dir, fractions; seed=DEFAULT_SEED,
                                                recorded=reloaded)
            @test [e.sha256 for e in again] == [e.sha256 for e in entries]
            @test_throws "toy-p25" Experiments.prepare_subsets(base, source, dir, fractions; seed=7,
                                                               recorded=reloaded)
        end
    end

    @testset "Merge manifests without shadowing a dataset" begin
        mktempdir() do dir
            entry(name) = "[$name]\nversion = \"v\"\nfile = \"$name.txt\"\nsha256 = \"$(repeat("0", 64))\"\nsources = []\n"
            first_path, second_path = joinpath(dir, "a.toml"), joinpath(dir, "b.toml")
            write(first_path, entry("chess"))
            write(second_path, entry("chess-p10"))
            merged = Experiments.load_manifests([first_path, second_path])
            @test sort!(collect(keys(merged))) == ["chess", "chess-p10"]
            write(second_path, entry("chess"))
            @test_throws "chess" Experiments.load_manifests([first_path, second_path])
        end
    end

    @testset "A generated dataset names its generator when missing" begin
        mktempdir() do dir
            entry = Experiments.DatasetEntry(name="toy-p25", version="test", file="toy-p25.txt",
                sha256=repeat("0", 64), sources=Experiments.DatasetSource[], stats=nothing)
            @test_throws "prepare_subsets.jl" Experiments.prepare_dataset(entry, dir)
        end
    end
end
