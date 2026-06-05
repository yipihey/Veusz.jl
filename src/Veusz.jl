"""
    Veusz

A native Julia interface to [Veusz](https://veusz.github.io), the scientific
plotting package — build publication-quality figures from Julia arrays and
**export them as editable, interactive HTML** (plus PDF / SVG / PNG / `.vsz`).

Veusz's compute is Python, but this package needs no Python *in* Julia: it
drives the headless `veuszd` daemon over its JSON-RPC socket protocol (see the
`docs/daemon-protocol.md` in the Veusz repo). Point it at a `veusz` install via
the `VEUSZ_PYTHON` or `VEUSZD` environment variable.

```julia
using Veusz
x = range(0, 2π; length=200); y = sin.(x)
fig = Figure()
plot!(fig, x, y; marker="circle", color="blue")
set!(fig, "/page1/graph1/x/label", "phase")
export_html(fig, "sine.html")   # editable + interactive in any browser
```
"""
module Veusz

using Sockets
using Base64
import JSON3

export Figure,
    plot!, set!, get_setting, setdata!, add_widget!, remove_widget!,
    undo!, redo!, first_graph, tree,
    render_svg, render_png, save_vsz, export_figure, export_html,
    live, close!

include("client.jl")
include("figure.jl")
include("io.jl")

"""
    live(fig; kwargs...)

Show `fig` as a **live, editable widget** in a Jupyter (IJulia) notebook: the
kernel relays JSON-RPC to the daemon over a WebSocket and the in-browser Veusz
editor (tree, inspector, toolbar, colormap + dataset pickers) drives it.

Requires `HTTP.jl` to be loaded (`using HTTP`) — it provides the relay via a
package extension. Falls back to a clear error otherwise. The figure renders in
the browser via WebGPU (Chrome / Safari 26+).
"""
function live end
live(args...; kwargs...) = error(
    "Veusz.live needs HTTP.jl — run `using HTTP` to enable the live IJulia widget. " *
    "(Static inline display via `display(fig)` works without it.)")

end # module Veusz
