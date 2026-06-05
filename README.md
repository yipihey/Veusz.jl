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

## Roadmap

- **Live editable widget in IJulia.** A figure displayed in a Jupyter (IJulia)
  notebook becomes a *live, editable* embed: the kernel relays JSON-RPC over a
  Jupyter comm to the daemon, and the in-browser editor (tree, inspector,
  toolbar, colormap + dataset pickers) drives it. The pieces exist on the Veusz
  side (`commTransport` + `mountRemoteEditor` in the embed); this is wired and
  shipped once the embed bundle with remote-mount is published and the comm
  relay is validated against IJulia. Today, IJulia shows a static SVG preview
  inline, and `export_html` gives a fully interactive standalone artifact.
- TCP transport option (already supported by the daemon) for remote/sandboxed
  setups.

## License

MIT (Veusz.jl is an independent client; it bundles no Veusz code). Veusz itself
is GPL.
