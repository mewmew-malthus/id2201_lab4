-module(gui).
-define(width, 200).
-define(height, 200).
-export([start/3]).
-include_lib("wx/include/wx.hrl").

start(Title, Master, Position) ->
    spawn_link(fun() -> init(Title, Master, Position) end).

init(Title, Master, Position) ->
    Window = make_window(Title, Position),
    loop(Window, Master).

make_window(Title, Position) ->
    Server = wx:new(),  %Server will be the parent for the Frame
    io:format("Position: ~w~n", [Position]),
    Frame = wxFrame:new(Server, -1, Title, [{size,{?width, ?height}}, {pos, Position}]),
    wxFrame:setBackgroundColour(Frame, ?wxBLACK),
    Window = wxWindow:new(Frame, ?wxID_ANY),
    wxFrame:show(Frame),
    wxWindow:setBackgroundColour(Window, ?wxBLACK),
    wxWindow:show(Window),
    %% monitor closing window event
    wxFrame:connect(Frame, close_window),
    Window.

loop(Window, Master)->
    receive
	%% check if the window was closed by the user
	#wx{event=#wxClose{}} ->
	    wxWindow:destroy(Window),  
	    Master ! stop,
	    ok;
	{color, Color} ->
	    color(Window, Color),
	    loop(Window, Master);
	stop ->
	    ok;
	Error ->
	    io:format("gui: strange message ~w ~n", [Error]),
	    loop(Window, Master)
    end.

color(Window, Color) ->
    wxWindow:setBackgroundColour(Window, Color),
    wxWindow:refresh(Window).
