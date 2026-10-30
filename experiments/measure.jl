# Runs in its own process so the measured command is its only child: on Unix,
# getrusage(RUSAGE_CHILDREN) then reports exactly that command's peak RSS.
using TOML: TOML

const USAGE = """
Usage:
  julia --startup-file=no experiments/measure.jl --timeout SECONDS
        --stdout PATH --stderr PATH --report PATH -- COMMAND [ARGS...]

Run COMMAND once, kill it after SECONDS, and write its status, exit code, wall
time, and OS-measured peak resident set size to the TOML report.
"""

const PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
const RUSAGE_CHILDREN = Cint(-1)

"""Windows PROCESS_MEMORY_COUNTERS."""
struct ProcessMemoryCounters
    cb::UInt32
    page_fault_count::UInt32
    peak_working_set_size::Csize_t
    working_set_size::Csize_t
    quota_peak_paged_pool_usage::Csize_t
    quota_paged_pool_usage::Csize_t
    quota_peak_non_paged_pool_usage::Csize_t
    quota_non_paged_pool_usage::Csize_t
    pagefile_usage::Csize_t
    peak_pagefile_usage::Csize_t
end

"""POSIX struct rusage: two timevals, then ru_maxrss and thirteen more longs."""
struct ResourceUsage
    time_fields::NTuple{4,Clong}
    maxrss::Clong
    other_fields::NTuple{13,Clong}
end

"""
Open the child on Windows right after the spawn. Holding the handle keeps the
process object alive after exit, so its peak working set is still readable.
"""
function open_peak_counter(process::Base.Process)
    Sys.iswindows() || return C_NULL
    return ccall((:OpenProcess, "kernel32"), stdcall, Ptr{Cvoid}, (UInt32, Cint, UInt32),
                 PROCESS_QUERY_LIMITED_INFORMATION, 0, getpid(process))
end

"""Return `(bytes, tool)`, or `(-1, tool)` when the platform gives no reading."""
function read_peak_rss(handle::Ptr{Cvoid})
    if Sys.iswindows()
        tool = "GetProcessMemoryInfo PeakWorkingSetSize"
        handle == C_NULL && return (-1, tool)
        counters = Ref(ProcessMemoryCounters(sizeof(ProcessMemoryCounters), zeros(Int, 9)...))
        ok = ccall((:K32GetProcessMemoryInfo, "kernel32"), stdcall, Cint,
                   (Ptr{Cvoid}, Ref{ProcessMemoryCounters}, UInt32),
                   handle, counters, sizeof(ProcessMemoryCounters))
        ccall((:CloseHandle, "kernel32"), stdcall, Cint, (Ptr{Cvoid},), handle)
        return (ok == 0 ? -1 : Int(counters[].peak_working_set_size), tool)
    end
    usage = Ref{ResourceUsage}()
    ccall(:getrusage, Cint, (Cint, Ref{ResourceUsage}), RUSAGE_CHILDREN, usage) == 0 ||
        return (-1, "getrusage RUSAGE_CHILDREN ru_maxrss")
    # Linux reports ru_maxrss in KiB, macOS in bytes.
    scale = Sys.isapple() ? 1 : 1024
    return (Int(usage[].maxrss) * scale, "getrusage RUSAGE_CHILDREN ru_maxrss")
end

"""
    measure(command; timeout, stdout_path, stderr_path) -> Dict

Run `command` to completion or until `timeout` seconds pass, then kill it.
Wall time runs from just before the spawn to the exit, so it includes process
startup. The status is `ok`, `error` for a nonzero exit, or `timeout`.
"""
function measure(command::Cmd; timeout::Real, stdout_path::AbstractString, stderr_path::AbstractString)
    open(stdout_path, "w") do out
        open(stderr_path, "w") do err
            start = time_ns()
            process = run(pipeline(ignorestatus(command); stdout=out, stderr=err); wait=false)
            handle = open_peak_counter(process)
            timed_out = Ref(false)
            timer = Timer(timeout) do _
                if process_running(process)
                    timed_out[] = true
                    kill(process, Base.SIGKILL)
                end
            end
            wait(process)
            elapsed = (time_ns() - start) / 1e9
            close(timer)
            peak, tool = read_peak_rss(handle)
            status = timed_out[] ? "timeout" : process.exitcode == 0 ? "ok" : "error"
            return Dict{String,Any}("status" => status, "exit_code" => process.exitcode,
                "elapsed_seconds" => elapsed, "peak_rss_bytes" => peak, "memory_tool" => tool)
        end
    end
end

function main(args)
    separator = findfirst(==("--"), args)
    separator === nothing && throw(ArgumentError("missing -- before the command\n$USAGE"))
    options = args[1:separator-1]
    command = args[separator+1:end]
    isempty(command) && throw(ArgumentError("missing command after --"))
    iseven(length(options)) || throw(ArgumentError("every option needs a value\n$USAGE"))
    values = Dict(options[i] => options[i+1] for i in 1:2:length(options))
    required = ("--timeout", "--stdout", "--stderr", "--report")
    for key in required
        haskey(values, key) || throw(ArgumentError("missing $key\n$USAGE"))
    end
    issubset(keys(values), required) || throw(ArgumentError("unknown option in $(options)"))
    timeout = parse(Float64, values["--timeout"])
    timeout > 0 || throw(ArgumentError("--timeout must be positive, got $timeout"))
    report = measure(Cmd(command); timeout, stdout_path=values["--stdout"], stderr_path=values["--stderr"])
    open(io -> TOML.print(io, report), values["--report"], "w")
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    code = try
        main(ARGS)
    catch exception
        println(stderr, "ERROR: ", sprint(showerror, exception))
        2
    end
    exit(code)
end
