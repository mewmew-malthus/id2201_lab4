-module(gms3).
-export([start/1, start/2]).

bcast(Id, Msg, Slaves) ->
    % io:format("Leader ~w Broadcasting: ~w ~n", [Id, Msg]),
    lists:foreach(fun(Slave) -> Slave ! Msg, crash(Id) end, Slaves).

crash(Id) ->
    case random:uniform(1000) of
        42 ->
            io:format("leader ~w: crash~n", [Id]),
            exit(no_luck);
        _ ->
            ok
    end.

leader(Id, Master, Slaves, Group, N) ->
    receive
        {mcast, Msg} ->
            bcast(Id, {msg, N, Msg}, Slaves),
            Master ! Msg,
            leader(Id, Master, Slaves, Group, N+1);
        {join, Wrk, Peer} ->
            Slaves2 = lists:append(Slaves, [Peer]),
            Group2 = lists:append(Group, [Wrk]),
            bcast(Id, {view, N, [self()|Slaves2], Group2}, Slaves2),
            Master ! {view, Group2},
            leader(Id, Master, Slaves2, Group2, N+1);
        stop ->
            ok
    end.

slave(Id, Master, Leader, Slaves, Group, N, Last) ->
    receive
        {'DOWN', _Ref, process, Leader, _Reason} ->
            election(Id, Master, Slaves, Group, N, Last);
        {mcast, Msg} ->
            Leader ! {mcast, Msg},
            slave(Id, Master, Leader, Slaves, Group, N, Last);
        {join, Wrk, Peer} ->
            Leader ! {join, Wrk, Peer},
            slave(Id, Master, Leader, Slaves, Group, N, Last);
        {msg, K, Msg} when K == (N + 1) ->
            Master ! Msg,
            slave(Id, Master, Leader, Slaves, Group, K, {msg, K, Msg});
        {view, K, [Leader|Slaves2], Group2} when K == (N + 1) ->
            Master ! {view, Group2},
            slave(Id, Master, Leader, Slaves2, Group2, K, {view, K, [Leader|Slaves2], Group2});
        {msg, K, _} when K =< N ->
            io:format("Node ~w received old msg num: ~w~n", [Id, K]),
            slave(Id, Master, Leader, Slaves, Group, N, Last);
        {view, K, _, _} when K =< N ->
            slave(Id, Master, Leader, Slaves, Group, N, Last);
        stop ->
            ok
    end.

election(Id, Master, Slaves, [_|Group], N, Last) ->
    Self = self(),
    case Slaves of
        [Self|Rest] ->
            bcast(Id, Last, Rest),
            bcast(Id, {view, N+1, Slaves, Group}, Rest),
            Master ! {view, Group},
            leader(Id, Master, Rest, Group, N+2);
        [Leader|Rest] ->
            erlang:monitor(process, Leader),
            slave(Id, Master, Leader, Rest, Group, N, Last)
    end.

% master start and init
start(Id) ->
    Self = self(),
    Rnd = random:uniform(1000),
    {ok, spawn_link(fun()-> init(Id, Self, Rnd) end)}.

init(Id, Master, Rnd) ->
    io:format("random val is ~w~n", [Rnd]),
    random:seed(Rnd, Rnd, Rnd),
    leader(Id, Master, [], [Master], 0).

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
        {view, N, [Leader|Slaves], Group} ->
        Master ! {view, Group},
        erlang:monitor(process, Leader),
        slave(Id, Master, Leader, Slaves, Group, N, {})
    after 5000 ->
        % ok
        Master ! {error, "no reply from leader"}
    end.