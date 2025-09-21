-module(gms4).
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
            bcast(Id, {msg, N, Msg}, Slaves),
            Master ! Msg,
            leader(Id, Master, Slaves, Group, N+1);
        {join, Wrk, Peer} ->
            case lists:member(Peer, Slaves) of 
                false ->
                    io:format("Leader ~w :: ~w Received Join Message ~n", [Id, self()]),
                    Slaves2 = lists:append(Slaves, [Peer]),
                    Group2 = lists:append(Group, [Wrk]),
                    bcast(Id, {view, N, [self()|Slaves2], Group2}, Slaves2),
                    Master ! {view, Group2},
                    leader(Id, Master, Slaves2, Group2, N+1);
                true ->
                    leader(Id, Master, Slaves, Group, N)
            end;
        stop ->
            ok
    end.

leader_safe(Id, Master, Slaves, Group, N) ->
    receive
        {mcast, Msg} ->
            bcast_safe({msg, N, Msg}, Slaves),
            Master ! Msg,
            leader_safe(Id, Master, Slaves, Group, N+1);
        {join, Wrk, Peer} ->
            case lists:member(Peer, Slaves) of 
                false ->
                    Slaves2 = lists:append(Slaves, [Peer]),
                    Group2 = lists:append(Group, [Wrk]),
                    bcast_safe({view, N, [self()|Slaves2], Group2}, Slaves2),
                    Master ! {view, Group2},
                    leader_safe(Id, Master, Slaves2, Group2, N+1);
                true ->
                    leader_safe(Id, Master, Slaves, Group, N)
            end;
        unsafe ->
            leader(Id, Master, Slaves, Group, N);
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
            % Peer ! {view, N, [Leader | lists:append(Slaves, [Peer])], lists:append(Group, [Wrk])},
            io:format("Node ~w Forwarding Join Message~n", [Id]),
            Leader ! {join, Wrk, Peer},
            slave(Id, Master, Leader, Slaves, Group, N, Last);
        {msg, K, _Msg} when K > (N + 1) ->
            %missed message
            % io:format("Node ~w Missed Message~n", [Id]),
            %bcast(Id, {resync, self()}, [Leader | Slaves]),
            slave(Id, Master, Leader, Slaves, Group, N, Last);
        {view, K, _nodes, _group} when K > (N + 1) ->
            % missed message
            % io:format("Node ~w missed message~n", [Id]),
            %bcast(Id, {resync, self()}, [Leader | Slaves]),
            slave(Id, Master, Leader, Slaves, Group, N, Last);
        {msg, K, Msg} when K == (N + 1) ->
            Master ! Msg,
            % echo to group to avoid misses
            spawn(fun() -> bcast_safe({msg, K, Msg}, Slaves) end),
            slave(Id, Master, Leader, Slaves, Group, K, {msg, K, Msg});
        {view, K, [Leader|Slaves2], Group2} when K == (N + 1) ->
            Master ! {view, Group2},
            % echo to group to avoid misses
            spawn(fun() -> bcast_safe({view, K, [Leader|Slaves2], Group2}, Slaves2) end),
            slave(Id, Master, Leader, Slaves2, Group2, K, {view, K, [Leader|Slaves2], Group2});
        {msg, K, _} when K =< N ->
            %io:format("Node ~w received old msg num: ~w~n", [Id, K]),
            slave(Id, Master, Leader, Slaves, Group, N, Last);
        {view, K, _, _} when K =< N ->
            slave(Id, Master, Leader, Slaves, Group, N, Last);
        {resync, K, Color, [Leader|Nodes], Group2} ->
            case K > N of
                true ->
                    Master ! {color_sync, Color},
                    slave(Id, Master, Leader, Nodes, Group2, K, Last);
                false ->
                    slave(Id, Master, Leader, Slaves, Group, N, Last)
            end;
        stop ->
            ok;
        Badmessage ->
            io:format("Bad message received ~w~n", [Badmessage])
    end.

election(Id, Master, Slaves, [_|Group], N, Last) ->
    Self = self(),
    case Slaves of
        [Self|Rest] ->
            io:format("Node ~w now Leader~n", [Id]),
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
    Rnd = rand:uniform(10000),
    {ok, spawn_link(fun()-> init(Id, Self, Rnd) end)}.

init(Id, Master, Rnd) ->
    %io:format("rand val is ~w~n", [Rnd]),
    rand:seed(default, {Rnd, Rnd, Rnd}),
    leader_safe(Id, Master, [], [Master], 0).

% slave start and init
start(Id, Grp) ->
    Self = self(),
    Rnd = rand:uniform(10000),
    {ok, spawn_link(fun()-> init(Id, Grp, Self, Rnd) end)}.

init(Id, Grp, Master, Rnd) ->
    %io:format("rand val is ~w~n", [Rnd]),
    rand:seed(default, {Rnd, Rnd, Rnd}),
    Self = self(),
    lists:foreach(fun(Groupee) -> Groupee ! {join, Master, Self} end, Grp),
    %Grp ! {join, Master, Self},
    receive
        {view, N, [Leader|Slaves], Group} ->
        Master ! {view, Group},
        erlang:monitor(process, Leader),
        io:format("Worker ~w :: ~w starting with Leader :: ~w~n", [Id, self(), Leader]),
        slave(Id, Master, Leader, Slaves, Group, N, {})
    after 500 ->
        % ok
        Master ! {error, "no reply from leader"}
    end.