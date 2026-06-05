# The high-level, native-feeling figure API: build a document, push data,
# style widgets — all thin wrappers over the daemon's doc.*/data.* methods.

"""
    Figure(; mode="graph", deterministic=false)

A live Veusz figure, backed by its own headless daemon. `mode` is the starting
document (`"graph"`, `"polar"`, `"ternary"`, `"graph3d"`). The daemon is shut
down automatically when the `Figure` is garbage-collected, or call [`close!`](@ref).
"""
mutable struct Figure
    client::Client
    counter::Base.RefValue{Int}
end

function Figure(; mode::AbstractString="graph", deterministic::Bool=false)
    c = spawn_daemon(; deterministic=deterministic)
    call(c, "doc.new"; mode=mode)
    f = Figure(c, Ref(0))
    finalizer(x -> (try; close!(x.client); catch; end), f)
    return f
end

close!(f::Figure) = close!(f.client)

"""
    call(fig, method; kwargs...)

Issue a raw RPC against the figure's daemon (escape hatch for methods without a
convenience wrapper). See `docs/daemon-protocol.md`.
"""
call(f::Figure, method::AbstractString; kwargs...) = call(f.client, method; kwargs...)

_uniqname(f::Figure, prefix) = (f.counter[] += 1; string(prefix, "_", f.counter[]))

# -- document tree -----------------------------------------------------------

"""    tree(fig) -> widget tree (nested name/path/type/children)."""
tree(f::Figure) = call(f, "doc.tree")

function _first_of_type(node, typ)
    String(get(node, "type", "")) == typ && return String(node["path"])
    for c in get(node, "children", ())
        r = _first_of_type(c, typ)
        r !== nothing && return r
    end
    return nothing
end

"""    first_graph(fig) -> path of the first graph (where plotters live)."""
function first_graph(f::Figure)
    g = _first_of_type(tree(f), "graph")
    g === nothing && error("document has no graph; add one with add_widget!(fig, \"/page1\", \"graph\")")
    return g
end

# -- widgets + settings ------------------------------------------------------

"""    add_widget!(fig, parent, type; name=nothing) -> path of the new widget."""
add_widget!(f::Figure, parent::AbstractString, type::AbstractString; name=nothing) =
    String(call(f, "doc.add"; parent=parent, type=type, name=name)["path"])

"""    remove_widget!(fig, path)"""
remove_widget!(f::Figure, path::AbstractString) = call(f, "doc.remove"; path=path)

"""
    set!(fig, path, value)

Set a widget setting by document path, e.g.
`set!(fig, "/page1/graph1/x/label", "time")`. Returns `value`.
"""
set!(f::Figure, path::AbstractString, value) = (call(f, "doc.set"; path=path, value=value); value)

"""    get_setting(fig, path) / get_setting(fig, [paths...])"""
get_setting(f::Figure, paths::AbstractVector) = call(f, "doc.get"; paths=paths)
get_setting(f::Figure, path::AbstractString) = get_setting(f, [path])[path]

undo!(f::Figure) = call(f, "doc.undo")
redo!(f::Figure) = call(f, "doc.redo")

# -- data --------------------------------------------------------------------

"""
    setdata!(fig, name, array)

Push a numeric `array` into the document as dataset `name`, using the efficient
base64 binary RPC. 1-D vectors and 2-D matrices are supported; matrices are sent
in row-major order so they match Veusz's grid layout.
"""
function setdata!(f::Figure, name::AbstractString, a::AbstractVector{<:Real})
    # write(io, ::Vector{Float64}) emits raw little-endian f64 bytes.
    b64 = base64encode(Vector{Float64}(a))
    call(f, "data.set_b64"; name=name, b64=b64, dtype="float64")
    return name
end

function setdata!(f::Figure, name::AbstractString, a::AbstractMatrix{<:Real})
    rowmajor = vec(permutedims(Float64.(a)))   # C-order, matching numpy reshape
    b64 = base64encode(rowmajor)
    call(f, "data.set_b64"; name=name, b64=b64,
         shape=[size(a, 1), size(a, 2)], dtype="float64")
    return name
end

# -- plotting convenience ----------------------------------------------------

"""
    plot!(fig, x, y; name=nothing, parent=nothing, marker="circle", kwargs...) -> path

Add an XY plotter bound to `x`/`y` (pushed as datasets) under a graph. Extra
keyword args set leaf settings on the plotter, e.g. `color="red",
PlotLine_style="dashed"` (use `_` for nested setting groups). Returns the
plotter's path.
"""
function plot!(f::Figure, x::AbstractVector{<:Real}, y::AbstractVector{<:Real};
               name=nothing, parent=nothing, marker::AbstractString="circle", kwargs...)
    g = parent === nothing ? first_graph(f) : String(parent)
    xn = setdata!(f, _uniqname(f, "x"), x)
    yn = setdata!(f, _uniqname(f, "y"), y)
    p = add_widget!(f, g, "xy"; name=name)
    set!(f, "$p/xData", xn)
    set!(f, "$p/yData", yn)
    set!(f, "$p/marker", marker)
    for (k, v) in kwargs
        set!(f, "$p/$(replace(String(k), '_' => '/'))", v)
    end
    return p
end

"""
    imageplot!(fig, grid; name=nothing, parent=nothing, colorMap="viridis", kwargs...) -> path

Add an image plotter bound to a 2-D `grid` (pushed as a dataset).
"""
function imageplot!(f::Figure, grid::AbstractMatrix{<:Real};
                    name=nothing, parent=nothing, colorMap::AbstractString="viridis", kwargs...)
    g = parent === nothing ? first_graph(f) : String(parent)
    dn = setdata!(f, _uniqname(f, "img"), grid)
    p = add_widget!(f, g, "image"; name=name)
    set!(f, "$p/data", dn)
    set!(f, "$p/colorMap", colorMap)
    for (k, v) in kwargs
        set!(f, "$p/$(replace(String(k), '_' => '/'))", v)
    end
    return p
end
