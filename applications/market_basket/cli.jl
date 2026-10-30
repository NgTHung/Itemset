"""True for exactly `-h` or `--help`, the only arguments the scripts treat as a request for usage."""
is_help(args::AbstractVector{<:AbstractString}) = args == ["--help"] || args == ["-h"]

"""
    output_folder(args, default, usage) -> String

The one optional output folder a script accepts, or `default` without arguments.
Throws `ArgumentError` with `usage` for a second argument or for any argument
that starts with `-`. Without that check a mistyped option such as `--hepl`
would become a folder name, and the script would run for minutes before anyone
saw the mistake.
"""
function output_folder(args::AbstractVector{<:AbstractString}, default::AbstractString, usage::AbstractString)
    length(args) <= 1 || throw(ArgumentError("expected at most one output folder\n$usage"))
    isempty(args) && return String(default)
    folder = only(args)
    startswith(folder, '-') && throw(ArgumentError("unknown option $folder\n$usage"))
    return String(folder)
end
