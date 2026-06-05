# Live, editable Veusz widget for Jupyter (IJulia) — the implementation of
# `Veusz.live`. Loaded as a package extension when `HTTP` is available.
#
# The kernel hosts a tiny HTTP server that (a) serves a mount page (and,
# optionally, a local copy of the in-browser editor bundle) and (b) relays
# JSON-RPC between the page and the figure's daemon over a WebSocket. The page
# mounts the editor with `commTransport(websocketComm(ws))`, so the full editor
# (tree, inspector, toolbar, colormap + dataset pickers) drives the daemon. The
# figure itself renders in the browser (WebGPU).

module VeuszLiveExt

import Veusz
import Veusz: Figure, call, on_notify
import HTTP
import HTTP.WebSockets
import JSON3
import Sockets

const DEFAULT_BUNDLE_URL = "https://yipihey.github.io/veusz/embed/v4.5.0"

mutable struct LiveSession
    fig::Figure
    server::Any
    host::String
    port::Int
    bundle_dir::Union{String,Nothing}
    bundle_url::String
    width::Int
    height::Int
    sockets::Set{Any}
    lock::ReentrantLock
end

# -- JSON-RPC relay (browser WebSocket <-> figure daemon) --------------------

_kwparams(::Nothing) = ()
_kwparams(params) = (k => v for (k, v) in params)   # JSON3.Object iterates Symbol=>value

function _handle_call(session::LiveSession, ws, id, method, params)
    resp = try
        Dict("id" => id, "result" => call(session.fig.client, method; _kwparams(params)...))
    catch e
        Dict("id" => id, "error" => Dict("message" => sprint(showerror, e)))
    end
    try
        WebSockets.send(ws, JSON3.write(resp))
    catch
    end
end

function _ws_relay(session::LiveSession, ws)
    lock(() -> push!(session.sockets, ws), session.lock)
    try
        for raw in ws
            msg = JSON3.read(raw)
            haskey(msg, :method) || continue
            @async _handle_call(session, ws, get(msg, :id, nothing),
                                 String(msg[:method]), get(msg, :params, nothing))
        end
    catch
    finally
        lock(() -> delete!(session.sockets, ws), session.lock)
    end
end

function _broadcast(session::LiveSession, method::AbstractString, params)
    payload = JSON3.write(Dict("method" => method, "params" => params))
    lock(session.lock) do
        for ws in session.sockets
            try
                WebSockets.send(ws, payload)
            catch
            end
        end
    end
end

# -- static file + mount-page serving ----------------------------------------

function _ctype(file)
    e = lowercase(splitext(file)[2])
    e == ".js"   ? "text/javascript; charset=utf-8" :
    e == ".mjs"  ? "text/javascript; charset=utf-8" :
    e == ".wasm" ? "application/wasm" :
    e == ".css"  ? "text/css; charset=utf-8" :
    e == ".json" ? "application/json" :
    e == ".map"  ? "application/json" :
    e == ".html" ? "text/html; charset=utf-8" : "application/octet-stream"
end

function _route(session::LiveSession, path::AbstractString)
    if path == "/" || path == "/index.html"
        return (codeunits(_mount_html(session)), "text/html; charset=utf-8")
    elseif session.bundle_dir !== nothing
        root = normpath(abspath(session.bundle_dir))
        file = normpath(joinpath(root, lstrip(path, '/')))
        if startswith(file, root) && isfile(file)   # no path traversal
            return (read(file), _ctype(file))
        end
    end
    return (nothing, "text/plain")
end

function _http_handler(session::LiveSession)
    return function (stream::HTTP.Stream)
        if WebSockets.isupgrade(stream.message)
            WebSockets.upgrade(ws -> _ws_relay(session, ws), stream)
            return
        end
        path = HTTP.URIs.URI(stream.message.target).path
        body, ctype = _route(session, path)
        HTTP.setstatus(stream, body === nothing ? 404 : 200)
        HTTP.setheader(stream, "Access-Control-Allow-Origin" => "*")
        body === nothing || HTTP.setheader(stream, "Content-Type" => ctype)
        HTTP.startwrite(stream)
        write(stream, body === nothing ? codeunits("not found") : body)
    end
end

function _mount_html(session::LiveSession)
    base = session.bundle_dir !== nothing ? "" : session.bundle_url
    ws = "ws://$(session.host):$(session.port)/"
    return """
    <!doctype html><html><head><meta charset="utf-8"></head>
    <body style="margin:0">
    <div id="veusz-live" style="min-height:$(session.height)px"></div>
    <script type="module">
    import { mountRemoteEditorFromComm, websocketComm } from "$(base)/veusz-embed.js";
    mountRemoteEditorFromComm(
      document.getElementById("veusz-live"),
      websocketComm("$(ws)"),
      { width: $(session.width), height: $(session.height), initialEditing: true });
    </script>
    </body></html>
    """
end

# -- public entry ------------------------------------------------------------

function Veusz.live(fig::Figure; host::AbstractString="127.0.0.1",
                    bundle_dir=nothing, bundle_url::AbstractString=DEFAULT_BUNDLE_URL,
                    width::Integer=720, height::Integer=480)
    port = _free_port(host)
    session = LiveSession(fig, nothing, String(host), port,
                          bundle_dir === nothing ? nothing : String(bundle_dir),
                          String(bundle_url), Int(width), Int(height),
                          Set{Any}(), ReentrantLock())
    session.server = HTTP.listen!(_http_handler(session), host, port)
    on_notify(p -> _broadcast(session, "doc.changed", p), fig.client, "doc.changed")
    on_notify(p -> _broadcast(session, "data.changed", p), fig.client, "data.changed")
    return session
end

function _free_port(host)
    s = Sockets.listen(Sockets.getaddrinfo(host), 0)
    p = Int(Sockets.getsockname(s)[2])
    close(s)
    return p
end

"""Stop a live session's HTTP/WebSocket server (the figure stays alive)."""
function Veusz.close!(session::LiveSession)
    try
        close(session.server)
    catch
    end
    return nothing
end

# IJulia (and any notebook) renders this as the live editor.
Base.show(io::IO, ::MIME"text/html", session::LiveSession) = write(io, _mount_html(session))

# The URL of the live page (handy for opening in a browser outside a notebook).
url(session::LiveSession) = "http://$(session.host):$(session.port)/"

end # module VeuszLiveExt
