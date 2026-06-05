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
    close!

include("client.jl")
include("figure.jl")
include("io.jl")

end # module Veusz
