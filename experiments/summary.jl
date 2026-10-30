const SUMMARY_KEYS = ["dataset", "minsup_count", "variant", "stage", "mode", "timing_scope"]
const SUMMARY_FIELDS = [SUMMARY_KEYS; "successful_samples"; "failed_samples"; "unverified_samples";
    "median_seconds"; "iqr_seconds"; "samples_seconds"; "max_peak_rss_bytes";
    "median_allocated_bytes"; "median_gc_seconds"; "gate_eligible"]

"""Linearly interpolated quantile of sorted samples, including one-sample series."""
function sample_quantile(values::Vector{Float64}, fraction::Float64)
    position = 1 + (length(values) - 1) * fraction
    lo, hi = floor(Int, position), ceil(Int, position)
    return values[lo] + (values[hi] - values[lo]) * (position - lo)
end

"""Summarize exact successful samples; count failures and unverified samples in every group."""
function summarize_rows(rows)
    groups = Dict{Tuple{Vararg{String}},Vector{Dict{String,String}}}()
    for row in rows
        push!(get!(groups, Tuple(row[k] for k in SUMMARY_KEYS), Dict{String,String}[]), row)
    end
    summaries = Dict{String,String}[]
    for key in sort!(collect(keys(groups)))
        group = groups[key]
        valid = filter(r -> r["status"] == "ok" && r["correctness_status"] == "exact", group)
        times = sort!([parse(Float64, r["elapsed_seconds"]) for r in valid])
        failed = count(r -> r["status"] != "ok", group)
        unverified = count(r -> r["status"] == "ok" && r["correctness_status"] != "exact", group)
        median_field(field) = begin
            values = sort!([parse(Float64, r[field]) for r in valid if !isempty(r[field])])
            isempty(values) ? "" : string(sample_quantile(values, 0.5))
        end
        peaks = [parse(Int, r["peak_rss_bytes"]) for r in valid if !isempty(r["peak_rss_bytes"])]
        push!(summaries, merge(Dict(zip(SUMMARY_KEYS, key)), Dict(
            "successful_samples" => string(length(valid)), "failed_samples" => string(failed),
            "unverified_samples" => string(unverified),
            "median_seconds" => isempty(times) ? "" : string(sample_quantile(times, 0.5)),
            "iqr_seconds" => isempty(times) ? "" : string(sample_quantile(times, 0.75) - sample_quantile(times, 0.25)),
            "samples_seconds" => join(times, ';'),
            "max_peak_rss_bytes" => isempty(peaks) ? "" : string(maximum(peaks)),
            "median_allocated_bytes" => median_field("allocated_bytes"),
            "median_gc_seconds" => median_field("gc_seconds"),
            "gate_eligible" => string(length(valid) >= 5 && failed == 0 && unverified == 0))))
    end
    return summaries
end

function write_summary(rows, path::AbstractString)
    open(path, "w") do io
        println(io, join(SUMMARY_FIELDS, ','))
        for row in summarize_rows(rows)
            println(io, join((csv_field(row[k]) for k in SUMMARY_FIELDS), ','))
        end
    end
end
