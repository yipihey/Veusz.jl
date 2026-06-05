# Low-level JSON-RPC 2.0 client for the Veusz daemon (`veuszd`).
#
# Wire protocol: LSP-style Content-Length framing over a Unix socket (or TCP).
# A monotonic request id multiplexes concurrent calls; the background reader
# routes replies (have `id`) to their waiting channel and notifications
# (no `id`) to per-method subscribers. See docs/daemon-protocol.md in the
# Veusz repository.

"""
    Client

A connection to a running `veuszd`. Usually created indirectly by [`Figure`](@ref);
use [`call`](@ref) to issue raw RPC methods.
"""
mutable struct Client
    io::IO
    proc::Union{Base.Process,Nothing}
    sockpath::Union{String,Nothing}
    nextid::Int
    pending::Dict{Int,Channel{Any}}
    notifs::Dict{String,Vector{Function}}
    lock::ReentrantLock
    open::Bool
    reader::Union{Task,Nothing}
end

function Client(io::IO; proc=nothing, sockpath=nothing)
    c = Client(io, proc, sockpath, 0, Dict{Int,Channel{Any}}(),
               Dict{String,Vector{Function}}(), ReentrantLock(), true, nothing)
    c.reader = @async _read_loop(c)
    return c
end

# -- framing -----------------------------------------------------------------

function _read_message(io::IO)
    len = -1
    while true
        line = rstrip(readline(io), ['\r'])
        isempty(line) && break
        m = match(r"^Content-Length:\s*(\d+)$"i, line)
        m !== nothing && (len = parse(Int, m.captures[1]))
    end
    len < 0 && error("missing Content-Length header")
    body = read(io, len)
    length(body) == len || error("short read: $(length(body))/$len bytes")
    return JSON3.read(body)
end

function _write_message(io::IO, obj)
    body = JSON3.write(obj)
    write(io, "Content-Length: ", string(ncodeunits(body)), "\r\n\r\n", body)
    flush(io)
end

function _read_loop(c::Client)
    try
        while c.open && !eof(c.io)
            msg = _read_message(c.io)
            id = get(msg, "id", nothing)
            if id !== nothing
                ch = lock(() -> pop!(c.pending, id, nothing), c.lock)
                ch !== nothing && put!(ch, msg)
            elseif haskey(msg, "method")
                params = get(msg, "params", nothing)
                for fn in get(c.notifs, String(msg["method"]), Function[])
                    @async try
                        fn(params)
                    catch
                    end
                end
            end
        end
    catch
        # socket closed or framing error — fall through to cleanup
    finally
        c.open = false
        lock(c.lock) do
            for (_, ch) in c.pending
                put!(ch, Dict("error" => Dict("message" => "connection closed")))
            end
            empty!(c.pending)
        end
    end
end

# -- requests ----------------------------------------------------------------

"""
    call(client, method; kwargs...) -> result

Issue RPC `method` with keyword params and return its `result`, throwing on an
RPC error. `kwargs` map to the JSON `params` object.
"""
function call(c::Client, method::AbstractString; kwargs...)
    c.open || error("Veusz client is closed")
    ch = Channel{Any}(1)
    lock(c.lock) do
        c.nextid += 1
        c.pending[c.nextid] = ch
        _write_message(c.io, Dict("jsonrpc" => "2.0", "id" => c.nextid,
                                  "method" => method, "params" => Dict(kwargs)))
    end
    msg = take!(ch)
    if haskey(msg, "error")
        e = msg["error"]
        m = e isa AbstractDict || e isa JSON3.Object ? get(e, "message", string(e)) : string(e)
        error("veuszd $method: $m")
    end
    return get(msg, "result", nothing)
end

"""
    on_notify(f, client, method)

Register `f(params)` to run on each `method` notification (`doc.changed`,
`data.changed`).
"""
on_notify(f::Function, c::Client, method::AbstractString) =
    (push!(get!(c.notifs, method, Function[]), f); nothing)

# -- daemon lifecycle --------------------------------------------------------

"""
    daemon_command() -> Cmd

Resolve the command that launches `veuszd`, in order:
`ENV["VEUSZD"]` → `ENV["VEUSZ_PYTHON"] -m veusz.daemon.cli` → `veuszd` on PATH
→ `python3 -m veusz.daemon.cli`.
"""
function daemon_command()
    haskey(ENV, "VEUSZD") && return Cmd([ENV["VEUSZD"]])
    haskey(ENV, "VEUSZ_PYTHON") && return `$(ENV["VEUSZ_PYTHON"]) -m veusz.daemon.cli`
    let p = Sys.which("veuszd"); p !== nothing && return Cmd([p]); end
    let py = Sys.which("python3"); py !== nothing && return `$py -m veusz.daemon.cli`; end
    error("""Could not find the Veusz daemon. Install Veusz (`pip install veusz`;
          the headless wheel needs no Qt) and either put `veuszd` on PATH, set
          ENV["VEUSZD"] to its path, or set ENV["VEUSZ_PYTHON"] to a python that
          has veusz installed.""")
end

"""
    spawn_daemon(; deterministic=false) -> Client

Launch a private `veuszd` over a temporary Unix socket and connect to it.
"""
function spawn_daemon(; deterministic::Bool=false)
    base = daemon_command()
    sockpath = tempname() * ".sock"
    args = String["--socket", sockpath]
    deterministic && push!(args, "--deterministic")
    proc = run(pipeline(`$base $args`; stdout=devnull, stderr=devnull); wait=false)
    for _ in 1:800                              # up to ~20 s for first boot
        ispath(sockpath) && break
        process_exited(proc) && error("veuszd exited before opening its socket")
        sleep(0.025)
    end
    if !ispath(sockpath)
        try; kill(proc); catch; end
        error("veuszd did not open a socket in time")
    end
    return Client(connect(sockpath); proc=proc, sockpath=sockpath)
end

"""
    close!(client)

Ask the daemon to shut down, close the socket, and clean up the process.
"""
function close!(c::Client)
    c.open || return nothing
    try; call(c, "shutdown"); catch; end
    c.open = false
    try; close(c.io); catch; end
    c.proc === nothing || (try; wait(c.proc); catch; end)
    c.sockpath !== nothing && ispath(c.sockpath) && (try; rm(c.sockpath; force=true); catch; end)
    return nothing
end
