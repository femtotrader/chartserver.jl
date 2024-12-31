module ChartServer
using Oxygen; @oxidise
using HTTP
using HTTP: WebSockets
using Mustache
using JSON3

using Rocket
using UUIDs

using CryptoMarketData
using OnlineTechnicalIndicators
using TechnicalIndicatorCharts

using MarketData # data for demo purposes

# aka the project root
const ROOT = dirname(dirname(@__FILE__))

# Setup a dictionary of rooms, and
# setup a default demo room.
ROOMS = Dict{Symbol, Set{HTTP.WebSocket}}(:demo => Set{HTTP.WebSocket}())
include("rooms.jl") # room_join, room_broadcast

# every N seconds, filter out all the disconnected websockets
@repeat 30 "websocket cleanup" function()
    for key in eachindex(ROOMS)
        room = ROOMS[key]
        filter!(ws -> !ws.writeclosed, room)
    end
end

# static files (but using dynamic during development)
# https://oxygenframework.github.io/Oxygen.jl/stable/#Mounting-Dynamic-Files
dynamicfiles(joinpath(ROOT, "www", "css"), "css")
dynamicfiles(joinpath(ROOT, "www", "js"), "js")
dynamicfiles(joinpath(ROOT, "www", "images"), "images")
@info :paths ROOT joinpath(ROOT, "www", "js")

# routes
@get "/" function(req::HTTP.Request)
    html("<a href=\"/demo\">demo</a>")
end

@websocket "/demo-ws" function(ws::HTTP.WebSocket)
    @info "demo-ws" message="connect" uuid=ws.id
    # make them a member of the :demo room on connect
    room_join(:demo, ws)
    # echo server for now
    # but what do we want this long-lived connection to do?
    for data in ws
        try
            msg = JSON3.read(data)
            if msg.type == "subscribe"
                @info :subscribe message="still figuring this part out"
            else
                WebSockets.send(ws, "unknown msg.type :: $(JSON3.write(msg))")
            end
        catch err
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

end
