# Rendering, inline display, and export.
#
# NOTE on backends: render_svg/render_png and export_figure (PDF/SVG/PNG) use
# Veusz's Qt paint engine, so they need a Qt-capable veusz (`pip install veusz`).
# The pure-Python "headless" wheel (no Qt) can still build documents, push data,
# save `.vsz`, and — crucially — export the interactive HTML below (the browser
# renders it). save_vsz and export_html therefore work with either backend.

"""
    render_svg(fig; page=0, width=600, height=400, dpi=96) -> String

Render a page to an SVG document string (needs a Qt-capable veusz).
"""
render_svg(f::Figure; page::Integer=0, width::Integer=600, height::Integer=400, dpi::Integer=96) =
    String(call(f, "render.svg"; page=page, w=width, h=height, dpi=dpi)["svg"])

"""
    render_png(fig; page=0, width=600, height=400, dpi=96) -> Vector{UInt8}

Render a page to PNG bytes (needs a Qt-capable veusz).
"""
render_png(f::Figure; page::Integer=0, width::Integer=600, height::Integer=400, dpi::Integer=96) =
    base64decode(String(call(f, "render.png"; page=page, w=width, h=height, dpi=dpi)["png"]))

# Inline display: SVG preferred (vector); PNG also offered.
Base.show(io::IO, ::MIME"image/svg+xml", f::Figure) = write(io, render_svg(f))
Base.show(io::IO, ::MIME"image/png", f::Figure) = write(io, render_png(f))

"""
    save_vsz(fig, path) -> info

Save the document as a self-contained `.vsz` (datasets embedded). Works with the
headless (no-Qt) wheel too.
"""
save_vsz(f::Figure, path::AbstractString) = call(f, "file.save_as"; path=abspath(path))

"""
    export_figure(fig, path; pages=[0])

Export to PDF / SVG / PNG / EPS / PS (by extension). Needs a Qt-capable veusz.
"""
export_figure(f::Figure, path::AbstractString; pages=[0]) =
    call(f, "file.export"; path=abspath(path), pages=pages)

"""
    export_html(fig, path; embed_version="v4.5.0", width=700, height=500) -> path

Write an **editable, interactive** standalone figure: a self-contained `.vsz`
(saved next to `path`) plus an HTML page that mounts the in-browser Veusz embed
against it. The reader can zoom, edit settings, and re-export — no server, no
Julia, no Python. Works with the headless (no-Qt) wheel.
"""
function export_html(f::Figure, path::AbstractString;
                     embed_version::AbstractString="v4.5.0",
                     width::Integer=700, height::Integer=500)
    stem = splitext(path)[1]
    vsz = stem * ".vsz"
    save_vsz(f, vsz)
    base = "https://yipihey.github.io/veusz/embed/$(embed_version)"
    html = """
    <!doctype html>
    <html><head><meta charset="utf-8">
    <title>$(basename(stem)) — Veusz</title>
    <script type="module" src="$(base)/veusz-embed.js"></script>
    </head>
    <body style="margin:0">
    <veusz-figure src="./$(basename(vsz))" width="$(width)" height="$(height)"></veusz-figure>
    </body></html>
    """
    write(path, html)
    return path
end
