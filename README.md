# Veusz.jl

A native Julia interface to [Veusz](https://veusz.github.io) — build
publication-quality scientific figures from Julia arrays and **export them as
editable, interactive HTML** (plus PDF / SVG / PNG / `.vsz`).

Veusz's engine is Python, but Veusz.jl needs no Python *inside* Julia: it drives
the headless `veuszd` daemon over its language-neutral JSON-RPC socket protocol.
Julia stays a thin, fast client.

```julia
using Veusz

x = range(0, 2π; length=200); y = sin.(x)

fig = Figure()
plot!(fig, x, y; marker="circle", color="blue")
set!(fig, "/page1/graph1/x/label", "phase")
set!(fig, "/page1/graph1/y/label", "amplitude")

fig                                  # inline SVG preview (REPL/IJulia/Pluto)
export_html(fig, "sine.html")        # editable + interactive in any browser
export_figure(fig, "sine.pdf")       # vector PDF
```

## Install

```julia
] add Veusz
```

You also need a Veusz install for the daemon. Either is fine:

- **Full (recommended):** `pip install veusz` — enables everything, including
  inline `render_svg`/`render_png` and PDF/SVG/PNG export (uses Veusz's Qt
  engine).
- **Headless (no Qt build):** the pure-Python wheel — can build documents, push
  data, save `.vsz`, and export the **interactive HTML** (the browser renders
  it), but not the Qt-based static raster/vector export.

Point Veusz.jl at it via an environment variable (checked in this order):

```julia
ENV["VEUSZD"]        = "/path/to/veuszd"                 # the console script, or…
ENV["VEUSZ_PYTHON"] = "/path/to/python"                  # a python with veusz (runs `python -m veusz.daemon.cli`)
```

If neither is set, Veusz.jl looks for `veuszd` on your `PATH`, then a `python3`
with veusz.

## What you get

| Function | Does | Backend |
|---|---|---|
| `Figure(; mode="graph")` | start a figure (its own daemon) | any |
| `plot!(fig, x, y; …)` | add an XY plotter bound to arrays | any |
| `imageplot!(fig, grid; …)` | add an image of a 2-D array | any |
| `setdata!(fig, name, array)` | push a 1-D/2-D array (efficient binary) | any |
| `add_widget!`, `remove_widget!` | insert/remove any widget (page, graph, axis, contour, fit, key, label, …) | any |
| `set!`, `get_setting` | edit/read any setting by path | any |
| `undo!`, `redo!` | document history | any |
| `save_vsz(fig, "f.vsz")` | save a self-contained `.vsz` | any |
| `export_html(fig, "f.html")` | **editable interactive** standalone HTML | any |
| `render_svg`, `render_png` | inline static render | Qt-capable |
| `export_figure(fig, "f.pdf")` | PDF / SVG / PNG / EPS / PS | Qt-capable |

The figure is the full Veusz document: build pages, graphs, axes, and the whole
plotter set (XY, function, bar, histogram, boxplot, fit, image, density,
contour, vector field, …), keys, labels and colorbars, and edit any setting by
its document path. Anything without a convenience wrapper is one `call` away:

```julia
ax = add_widget!(fig, "/page1/graph1", "axis"; name="y2")
set!(fig, "$ax/direction", "vertical")
Veusz.call(fig, "doc.colormaps")          # raw RPC escape hatch
```

## Editable interactive figures

`export_html` writes two files — a self-contained `.vsz` (datasets embedded) and
an `index.html` that mounts the in-browser Veusz embed against it. Open the HTML
anywhere: the reader can pan/zoom, change settings, pick colormaps, and
re-export — no server, no Julia, no Python. This is the headline workflow for
sharing results from a Julia pipeline.

## How it works

```
Veusz.jl  ──JSON-RPC over a Unix socket──▶  veuszd (headless Python)
   │                                              │  document model · Scene-IR
   ├─ plot!/set!/setdata!  → doc.*/data.*         │  · save .vsz · export
   ├─ render_svg           → render.svg           ▼
   └─ export_html          → file.save_as + <veusz-figure>  (browser renders via WASM)
```

The protocol is documented in the Veusz repository
(`docs/daemon-protocol.md`) and is language-agnostic — Veusz.jl is its first
native non-Python client.

## Live editable widget in IJulia

In a Jupyter (IJulia) notebook a figure can be shown as a **live, editable**
embed — the full in-browser Veusz editor (tree, inspector, toolbar, colormap +
dataset pickers) driving the kernel's daemon in real time:

```julia
using Veusz, HTTP          # HTTP enables the live extension
fig = Figure()
plot!(fig, x, y)
live(fig)                  # renders the editable editor inline
```

`live(fig)` starts a tiny per-kernel HTTP/WebSocket relay: the browser editor
sends JSON-RPC over a WebSocket, the kernel forwards it to the figure's daemon,
and daemon notifications stream back so the editor stays in sync. Edits in the
browser mutate the same in-kernel document.

The editor renders in the browser via **WebGPU** (Chrome / Safari 26+). It loads
the embed bundle from the Veusz CDN by default; for offline use or a custom
build, point it at a local `dist-embed`:

```julia
live(fig; bundle_dir="/path/to/veusz/veusz-tauri/dist-embed")
```

The editor is embedded as an `<iframe>` pointing at the relay, so it works in
**JupyterLab, classic Notebook, and VS Code** (which strip inline `<script>`
from cell output — the iframe loads a full document and runs its own scripts).

Notes: the relay listens on `127.0.0.1`, so this targets a **locally-run**
Jupyter over `http://localhost` (the browser must reach the kernel host, and an
`http` page can iframe an `http://localhost` relay without mixed-content
issues); a comm-based transport for remote hubs is future work. Without `HTTP`
loaded, `display(fig)` still shows a static SVG preview, and `export_html`
always gives a fully interactive standalone artifact.

## Roadmap

- Comm-based transport (Jupyter widget protocol) so the live widget also works
  over remote JupyterHub, not just local Jupyter.
- TCP transport option (already supported by the daemon) for remote/sandboxed
  setups.

## License

MIT (Veusz.jl is an independent client; it bundles no Veusz code). Veusz itself
is GPL.
