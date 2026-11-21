@testset "Image pattern analysis" begin
    pixels = zeros(UInt8, 16, 16)
    images = [SemeionPilot.DigitImage(42, 3, pixels),
              SemeionPilot.DigitImage(7, 3, pixels),
              SemeionPilot.DigitImage(90, 4, pixels),
              SemeionPilot.DigitImage(2, 4, pixels)]
    transactions = [[8, 13], [13], Int[], [4, 8, 13]]
    rows = SemeionPilot.pattern_label_summary(images, transactions, (8, 13))
    @test rows[4] == (; label=3, total=2, support=1, fraction=0.5, image_ids=[42])
    @test rows[5] == (; label=4, total=2, support=1, fraction=0.5, image_ids=[2])
    @test rows[1].fraction === nothing
    @test sum(row.support for row in rows) == 2
    @test_throws ArgumentError SemeionPilot.pattern_label_summary(images[1:2], transactions, (13,))
    @test_throws ArgumentError SemeionPilot.pattern_label_summary([images[1], images[1]], [[13], [13]], (13,))
    patterns = [(13,), (8, 13), (4, 8, 13)]
    features = SemeionPilot.itemset_features(transactions, patterns)
    @test features == Bool[1 1 0; 1 0 0; 0 0 0; 1 1 1]
    @test SemeionPilot.itemset_features([[13, 8, 8]], patterns) == features[1:1, :]
    @test size(SemeionPilot.itemset_features(Vector{Int}[], patterns)) == (0, 3)
    @test size(SemeionPilot.itemset_features(transactions, Tuple{Int}[])) == (4, 0)
    for bad in ([()], [(13, 8)], [(8, 8)], [(0,)], [(true,)], [(13,), (13,)])
        @test_throws ArgumentError SemeionPilot.itemset_features(transactions, bad)
    end
    @test_throws ArgumentError SemeionPilot.itemset_features([[-1]], patterns)
end
