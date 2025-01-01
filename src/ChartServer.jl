module ChartServer
using Oxygen; @oxidise
using HTTP
using HTTP: WebSockets
using Mustache
using JSON3

using Rocket
using UUIDs
using Dates

using CryptoMarketData
using OnlineTechnicalIndicators
using TechnicalIndicatorCharts

using MarketData # data for demo purposes

# aka the project root
const ROOT = dirname(dirname(@__FILE__))

# Setup a dictionary of rooms, and
# setup a default demo room.
"""
`ROOMS` is a Dict that maps Symbols to Sets of WebSockets.
The Symbols represent room names, and the WebSockets are the clients
who are currently in those rooms.

> I'm not sure if `Set` was the right container to put those `WebSocket`s in, but I wanted to enforce uniqueness.
"""
ROOMS = Dict{Symbol, Set{HTTP.WebSocket}}(:demo => Set{HTTP.WebSocket}())
include("rooms.jl") # room_join, room_broadcast

# every N seconds, filter out all the disconnected websockets
@repeat 30 "websocket cleanup" function()
    for key in eachindex(ROOMS)
        room = ROOMS[key]
        filter!(ws -> !ws.writeclosed, room)
    end
end

## Rocket setup
include("rocket.jl")

"""
`aapl_chart` is a `TechnicalIndicatorCharts.Chart` of the
`MarketData.AAPL` data aggregated into 1 week candles.  A weekly 50
SMA and 200 SMA are also calculated for this chart.
"""
aapl_chart = Chart(
    "AAPL", Week(1),
    indicators = [
        SMA{Float64}(period=50),          # Setup indicators
        SMA{Float64}(period=200),
    ],
    visuals = [
        Dict(
            :label_name => "SMA 50",      # Describe how to draw indicators
            :line_color => "#E072A4",
            :line_width => 2
        ),
        Dict(
            :label_name => "SMA 200",
            :line_color => "#3D3B8E",
            :line_width => 5
        )
    ]
)

"""
`chart_subject` consumes `Candle`s for 1 market and feeds them to the `Chart`s it has been asked to manage.
It emits change notifications as tuples when a value has been updated or added to a chart in its care.
"""
chart_subject = ChartSubject(charts = Dict(:aapl1w => aapl_chart))

"""
This is a Ref that you can manipulate to change the rate at which `candle_observable` emits candles.

# Example

```julia-repl
julia> CS.INTERVAL
Base.RefValue{Millisecond}(Millisecond(100))

julia> CS.INTERVAL[] = Millisecond(2000) # slow it down to 1 candle every 2 seconds
2000 milliseconds

julia> CS.INTERVAL
Base.RefValue{Millisecond}(Millisecond(2000))
```
"""
INTERVAL = Ref(Millisecond(100))

"""
This observable takes data from `MarketData.AAPL`
and emits each row as a `TechnicalIndicatorCharts.Candle`
at a rate of one candle per `CS.INTERVAL`.
"""
candle_observable = make_timearrays_candles(AAPL, INTERVAL)

# static files (but using dynamic during development)
# https://oxygenframework.github.io/Oxygen.jl/stable/#Mounting-Dynamic-Files
dynamicfiles(joinpath(ROOT, "www", "css"), "css")
dynamicfiles(joinpath(ROOT, "www", "js"), "js")
dynamicfiles(joinpath(ROOT, "www", "images"), "images")

# routes
@get "/" function(req::HTTP.Request)
    html("""<a href="/demo">demo</a>""")
end

@websocket "/demo-ws" function(ws::HTTP.WebSocket)
    @info :connect id=ws.id
    # make them a member of the :demo room on connect
    room_join(:demo, ws)
    # echo server for now
    # but what do we want this long-lived connection to do?
    for data in ws
        try
            msg = JSON3.read(data)
            if msg.type == "subscribe"
                @info :subscribe id=ws.id message="still figuring this part out"
            elseif msg.type == "id"
                @info :id id=ws.id
                WebSockets.send(ws, JSON3.write(Dict(:id => ws.id)))
            else
                WebSockets.send(ws, "unknown msg.type :: $(JSON3.write(msg))")
            end
        catch err
            @error :exception err
            WebSockets.send(ws, "[echo] $(data)")
        end
    end
    # When the connection closes, the @repeat task up top will clean them out of ROOMS eventually.
    # Doing it immediately caused errors that I didn't understand.
end

render_demo = Mustache.load(joinpath(ROOT, "tmpl", "demo.html"))
@get "/demo" function(req::HTTP.Request)
    render_demo()
end

# return the latest candles as JSON
@get "/demo/latest" function(req::HTTP.Request)
end

end
