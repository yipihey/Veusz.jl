using Veusz
using Test

# The live tests need a `veuszd` to talk to. They're skipped (not failed) when
# none is configured, so the suite is green on machines without Veusz installed.
# Set ENV["VEUSZ_PYTHON"] (a python with veusz) or ENV["VEUSZD"] to run them.
have_daemon = try
    Veusz.daemon_command()
    true
catch
    false
end

@testset "Veusz.jl" begin
    if !have_daemon
        @info "No veuszd found (set VEUSZ_PYTHON or VEUSZD) — skipping live tests"
        @test_skip "live tests need a veusz daemon"
    else
        fig = Figure(deterministic=true)
        try
            @testset "build from arrays" begin
                x = collect(range(0, 2π; length=128))
                y = sin.(x)
                p = plot!(fig, x, y; marker="circle")
                @test occursin("/page1/graph1", p)
                set!(fig, "/page1/graph1/x/label", "phase")
                @test get_setting(fig, "/page1/graph1/x/label") == "phase"
                names = [String(d["name"]) for d in Veusz.call(fig, "data.list")]
                @test length(names) >= 2
            end

            @testset "binary data round-trips exactly" begin
                Veusz.setdata!(fig, "z", Float64[1.0, 2.5, -3.0, 1e6])
                pk = Veusz.call(fig, "data.peek"; name="z")
                @test collect(Float64.(pk["values"])) == [1.0, 2.5, -3.0, 1e6]
            end

            @testset "2-D grid is row-major + Dataset2D" begin
                G = Float64[1 2 3; 4 5 6]          # 2 rows, 3 cols
                Veusz.setdata!(fig, "G", G)
                info = Dict(String(d["name"]) => d for d in Veusz.call(fig, "data.list"))
                @test String(info["G"]["type"]) == "Dataset2D"
                @test collect(Int.(info["G"]["shape"])) == [2, 3]
                pk = Veusz.call(fig, "data.peek"; name="G")  # rows as lists
                @test collect(Float64.(pk["values"][1])) == [1.0, 2.0, 3.0]
                @test collect(Float64.(pk["values"][2])) == [4.0, 5.0, 6.0]
            end

            @testset "undo / redo" begin
                undo!(fig)
                redo!(fig)
            end

            tmp = mktempdir()

            @testset "save .vsz (works on any backend)" begin
                save_vsz(fig, joinpath(tmp, "f.vsz"))
                @test isfile(joinpath(tmp, "f.vsz"))
            end

            @testset "interactive HTML export (any backend)" begin
                html = export_html(fig, joinpath(tmp, "f.html"))
                @test isfile(html)
                @test isfile(joinpath(tmp, "f.vsz"))
                @test occursin("veusz-figure", read(html, String))
            end

            @testset "SVG render (Qt-capable backend only)" begin
                try
                    svg = render_svg(fig; width=200, height=150)
                    s = strip(svg)
                    @test startswith(s, "<?xml") || startswith(s, "<svg")
                catch e
                    @info "render_svg unavailable (headless no-Qt backend) — skipping" exception = e
                    @test_skip "render_svg needs a Qt-capable veusz"
                end
            end

            @testset "live WebSocket relay (HTTP extension)" begin
                using HTTP
                using HTTP.WebSockets
                JSON3 = Veusz.JSON3
                session = Veusz.live(fig)
                try
                    @test session.port > 0
                    # the notebook view is an iframe pointing at the relay
                    view = sprint(show, MIME"text/html"(), session)
                    @test occursin("<iframe", view)
                    @test occursin("http://127.0.0.1:$(session.port)/", view)
                    # the served page wires the editor bundle, the WS relay, and
                    # the WASM base (so the renderer finds the bundle's wasm)
                    page = String(HTTP.get("http://127.0.0.1:$(session.port)/").body)
                    @test occursin("veusz-embed.js", page)
                    @test occursin("__VEUSZ_WASM_BASE__", page)
                    @test occursin("ws://127.0.0.1:$(session.port)/", page)
                    WebSockets.open("ws://127.0.0.1:$(session.port)/") do ws
                        # A background collector with a hard time budget, so a
                        # missing message can never hang the suite.
                        msgs = Vector{Any}()
                        msglock = ReentrantLock()
                        reader = @async try
                            while true
                                m = JSON3.read(WebSockets.receive(ws))
                                lock(() -> push!(msgs, m), msglock)
                            end
                        catch
                        end
                        seen(id) = lock(() -> any(m -> get(m, :id, nothing) == id, msgs), msglock)
                        notif(meth) = lock(() -> any(m -> String(get(m, :method, "")) == meth, msgs), msglock)
                        waitfor(cond; secs = 5.0) = begin
                            t0 = time()
                            while !cond() && time() - t0 < secs
                                sleep(0.05)
                            end
                            cond()
                        end

                        # version + doc.tree round-trip through the relay → daemon
                        WebSockets.send(ws, JSON3.write(Dict("id" => 1, "method" => "version")))
                        WebSockets.send(ws, JSON3.write(Dict("id" => 2, "method" => "doc.tree")))
                        @test waitfor(() -> seen(1) && seen(2))
                        r1 = lock(() -> first(m for m in msgs if get(m, :id, nothing) == 1), msglock)
                        r2 = lock(() -> first(m for m in msgs if get(m, :id, nothing) == 2), msglock)
                        @test haskey(r1.result, :api)
                        @test haskey(r2.result, :children)

                        # an edit returns a reply AND emits a doc.changed broadcast
                        WebSockets.send(ws, JSON3.write(Dict("id" => 3, "method" => "doc.set",
                            "params" => Dict("path" => "/page1/graph1/x/label", "value" => "live"))))
                        @test waitfor(() -> seen(3))
                        @test waitfor(() -> notif("doc.changed"))
                    end
                finally
                    Veusz.close!(session)
                end
            end
        finally
            close!(fig)
        end
    end
end
