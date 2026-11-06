function pattern_evidence_svg(encoding, evidence, rows)
    io = IOBuffer()
    svg_start!(io, max(300, length(rows) * 150), 130 + 75 * length(evidence.itemset))
    println(io, "<text x=\"8\" y=\"16\" font-size=\"13\">words $(join(evidence.itemset, ',')); support $(length(evidence.supporting))</text>")
    for (index, row) in enumerate(rows)
        image = encoding.images[row.position]
        x = 8 + 150 * (index - 1)
        color = row.kind == "support" ? "green" : "red"
        println(io, "<text x=\"$x\" y=\"32\" fill=\"$color\" font-size=\"11\">$(row.kind): image $(image.id)</text>")
        println(io, "<text x=\"$x\" y=\"46\" font-size=\"10\">digit $(image.label)</text>")
        svg_digit!(io, image.pixels, x, 52)
        for patch in row.patches
            px, py = x + 4 * (patch.ref.col - 1), 52 + 4 * (patch.ref.row - 1)
            println(io, "<rect x=\"$px\" y=\"$py\" width=\"16\" height=\"16\" fill=\"none\" stroke=\"blue\"/>")
        end
        for (word_index, word) in enumerate(evidence.itemset)
            y = 135 + 75 * (word_index - 1)
            patch_index = findfirst(patch -> patch.word == word, row.patches)
            if patch_index === nothing
                println(io, "<text x=\"$x\" y=\"$y\" fill=\"red\" font-size=\"11\">missing word $word</text>")
            else
                patch = row.patches[patch_index]
                println(io, "<text x=\"$x\" y=\"$y\" font-size=\"10\">word $word: r$(patch.ref.row),c$(patch.ref.col)</text>")
                svg_patch!(io, patch.patch, x, y + 5)
            end
        end
    end
    println(io, "</svg>")
    String(take!(io))
end
