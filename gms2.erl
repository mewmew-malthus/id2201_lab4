-module(gms2).
-export([start/1, start/2]).

bcast(Id, Msg, Slaves) ->
    io:format("Leader ~w Broadcasting ~n", [Id]),
    lists:foreach(fun(Slave) -> Slave ! Msg, crash(Id) end, Slaves).

crash(Id) ->
    case random:uniform(42) of
        42 ->
            io:format("leader ~w: crash~n", [Id]),
            exit(no_luck);
        _ ->
            ok
    end.

leader(Id, Master, Slaves, Group) ->
    receive
        {mcast, Msg} ->
            bcast(Id, {msg, Msg}, Slaves),
            Master ! Msg,
            leader(Id, Master, Slaves, Group);
        {join, Wrk, Peer} ->
            Slaves2 = lists:append(Slaves, [Peer]),
            Group2 = lists:append(Group, [Wrk]),
            bcast(Id, {view, [self()|Slaves2], Group2}, Slaves2),
            Master ! {view, Group2},
            leader(Id, Master, Slaves2, Group2);
        stop ->
            ok
    end.

slave(Id, Master, Leader, Slaves, Group) ->
    receive
        {'DOWN', _Ref, process, Leader, _Reason} ->
            election(Id, Master, Slaves, Group);
        {mcast, Msg} ->
            Leader ! {mcast, Msg},
            slave(Id, Master, Leader, Slaves, Group);
        {join, Wrk, Peer} ->
            Leader ! {join, Wrk, Peer},
            slave(Id, Master, Leader, Slaves, Group);
        {msg, Msg} ->
            Master ! Msg,
            slave(Id, Master, Leader, Slaves, Group);
        {view, [Leader|Slaves2], Group2} ->
            Master ! {view, Group2},
            slave(Id, Master, Leader, Slaves2, Group2);
        stop ->
            ok
    end.

election(Id, Master, Slaves, [_|Group]) ->
    Self = self(),
    case Slaves of
        [Self|Rest] ->
            bcast(Id, {view, Slaves, Group}, Rest),
            Master ! {view, Group},
            leader(Id, Master, Rest, Group);
        [Leader|Rest] ->
            erlang:monitor(process, Leader),
            slave(Id, Master, Leader, Rest, Group)
    end.

% master start and init
start(Id) ->
    Self = self(),
    Rnd = random:uniform(1000),
    {ok, spawn_link(fun()-> init(Id, Self, Rnd) end)}.

init(Id, Master, Rnd) ->
    io:format("random val is ~w~n", [Rnd]),
    random:seed(Rnd, Rnd, Rnd),
    leader(Id, Master, [], [Master]).

% slave start and init
start(Id, Grp) ->
    Self = self(),
    Rnd = random:uniform(1000),
    {ok, spawn_link(fun()-> init(Id, Grp, Self, Rnd) end)}.

init(Id, Grp, Master, Rnd) ->
    io:format("random val is ~w~n", [Rnd]),
    random:seed(Rnd, Rnd, Rnd),
    Self = self(),
    Grp ! {join, Master, Self},
    receive
        {view, [Leader|Slaves], Group} ->
        Master ! {view, Group},
        erlang:monitor(process, Leader),
        slave(Id, Master, Leader, Slaves, Group)
    after 5000 ->
        % ok
        Master ! {error, "no reply from leader"}
    end.