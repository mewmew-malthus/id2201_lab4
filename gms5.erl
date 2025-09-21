-module(gms5).
-export([start/1, start/2]).

bcast(Id, Msg, Slaves) ->
    % io:format("Leader ~w Broadcasting: ~w ~n", [Id, Msg]),
    lists:foreach(fun(Slave) -> 
        case miss_msg(10, Msg) of
            Msg ->
                Slave ! Msg, 
                crash(Id);
            miss ->
                io:format("Missed Message to ~w~n", [Slave]),
                ok 
        end
    end, Slaves).

bcast_safe(Msg, Slaves) ->
    % io:format("Leader ~w Broadcasting: ~w ~n", [Id, Msg]),
    lists:foreach(fun(Slave) -> 
            Slave ! Msg 
    end, Slaves).

crash(Id) ->
    case rand:uniform(100) of
        42 ->
            io:format("Node ~w :: ~w crash~n", [Id, self()]),
            exit(no_luck);
        _ ->
            ok
    end.

miss_msg(Chance, Message) ->
    case rand:uniform(100) < Chance of
        true ->
            miss;
        false -> 
            Message
    end.

leader(Id, Master, Slaves, Group, N) ->
    receive
        {mcast, Msg} ->
            case Msg of
                {change, Num} ->

                Msg ->
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

slave(Id, Master, Leader, Slaves, Group, N, Last, Color) ->
    receive
        {'DOWN', _Ref, process, Leader, _Reason} ->
            election(Id, Master, Slaves, Group, N, Last, Color);
        {mcast, Msg} ->
            Leader ! {mcast, Msg},
            slave(Id, Master, Leader, Slaves, Group, N, Last, Color);
        {join, Wrk, Peer} ->
            Leader ! {join, Wrk, Peer},
            slave(Id, Master, Leader, Slaves, Group, N, Last, Color);
        {msg, K, Msg} when K >= (N + 1) ->
            Master ! Msg,
            slave(Id, Master, Leader, Slaves, Group, K, {msg, K, Msg}, Color);
        {view, K, [Leader|Slaves2], Group2} when K >= (N + 1) ->
            Master ! {view, Group2},
            slave(Id, Master, Leader, Slaves2, Group2, K, {view, K, [Leader|Slaves2], Group2}, Color);
        {msg, K, _} when K =< N ->
            io:format("Node ~w received old msg num: ~w~n", [Id, K]),
            slave(Id, Master, Leader, Slaves, Group, N, Last, Color);
        {view, K, _, _} when K =< N ->
            slave(Id, Master, Leader, Slaves, Group, N, Last, Color);
        stop ->
            ok
    end.

election(Id, Master, Slaves, [_|Group], N, Last, Color) ->
    Self = self(),
    case Slaves of
        [Self|Rest] ->
            bcast(Id, Last, Rest),
            bcast(Id, {view, N+1, Slaves, Group}, Rest),
            Master ! {view, Group},
            leader(Id, Master, Rest, Group, N+2, Color);
        [Leader|Rest] ->
            erlang:monitor(process, Leader),
            slave(Id, Master, Leader, Rest, Group, N, Last, Color)
    end.

% master start and init
start(Id) ->
    Self = self(),
    Rnd = rand:uniform(1000),
    {ok, spawn_link(fun()-> init(Id, Self, Rnd) end)}.

init(Id, Master, Rnd) ->
    % io:format("rand val is ~w~n", [Rnd]),
    rand:seed(default, {123, 1234, 12345}),
    leader(Id, Master, [], [Master], 0).

% slave start and init
start(Id, Grp) ->
    Self = self(),
    Rnd = rand:uniform(1000),
    {ok, spawn_link(fun()-> init(Id, Grp, Self, Rnd) end)}.

init(Id, Grp, Master, Rnd) ->
    io:format("rand val is ~w~n", [Rnd]),
    rand:seed(default, {123, 1234, 12345}),
    Self = self(),
    Grp ! {join, Master, Self},
    receive
        {view, N, [Leader|Slaves], Group} ->
        Master ! {view, Group},
        erlang:monitor(process, Leader),
        slave(Id, Master, Leader, Slaves, Group, N, {}, Color)
    after 5000 ->
        % ok
        Master ! {error, "no reply from leader"}
    end.