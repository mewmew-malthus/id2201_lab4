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
                % io:format("Missed Message to ~w~n", [Slave]),
                ok 
        end
    end, Slaves).

bcast_safe(Msg, Slaves) ->
    % io:format("Leader ~w Broadcasting: ~w ~n", [Id, Msg]),
    lists:foreach(fun(Slave) -> 
            Slave ! Msg 
    end, Slaves).

crash(Id) ->
    case rand:uniform(500) of
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
                    erlang:monitor(process, Peer),
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
                    io:format("Leader ~w :: ~w Received Join Message ~n", [Id, self()]),
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

rotate_last(NewMsg, Last, Length) ->
    Last2 = lists:append(Last, [NewMsg]),
    case length(Last2) > Length of
        false ->
            Last2;
        true ->
            lists:sublist(Last2, 1, length(Last2) - 1)
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
            % io:format("Node ~w Forwarding Join Message~n", [Id]),
            Leader ! {join, Wrk, Peer},
            % let's assume its safe to add the new Node to our list
            % Slaves2 = lists:uniq(lists:append(Slaves, [Peer])),
            % Group2 = lists:uniq(lists:append(Group, [Wrk])),
            erlang:monitor(process, Peer),
            % will this solve the errors? - no, it can be wildly out of sync during crash wave
            % Peer ! {view, N, [Leader | Slaves2], Group2},
            slave(Id, Master, Leader, Slaves, Group, N, Last);
        {msg, K, _Msg} when K > (N + 1) ->
            %missed message
            % io:format("Node ~w requests resync!~n", [Id]),
            bcast_safe(resync, Slaves),
            slave(Id, Master, Leader, Slaves, Group, N, Last);
        {view, K, _nodes, _group} when K > (N + 1) ->
            % missed message
            % io:format("Node ~w requests resync!~n", [Id]),
            bcast_safe(resync, Slaves),
            slave(Id, Master, Leader, Slaves, Group, N, Last);
        {msg, K, Msg} when K == (N + 1) ->
            Master ! Msg,
            % echo to group to avoid misses
            bcast_safe({msg, K, Msg}, Slaves),
            slave(Id, Master, Leader, Slaves, Group, K, rotate_last({msg, K, Msg}, Last, 10));
        {view, K, [Leader|Slaves2], Group2} when K == (N + 1) ->
            Master ! {view, Group2},
            % echo to group to avoid misses
            bcast_safe({view, K, [Leader|Slaves2], Group2}, Slaves2),
            slave(Id, Master, Leader, Slaves2, Group2, K, rotate_last({view, K, [Leader|Slaves2], Group2}, Last, 10));
        {msg, K, _} when K =< N ->
            %io:format("Node ~w received old msg num: ~w~n", [Id, K]),
            slave(Id, Master, Leader, Slaves, Group, N, Last);
        {view, K, _, _} when K =< N ->
            slave(Id, Master, Leader, Slaves, Group, N, Last);
        resync ->
           lists:foreach(fun(Msg) -> bcast(Id, Msg, Slaves) end, Last), 
           slave(Id, Master, Leader, Slaves, Group, N, Last);
        stop ->
            ok
        % Badmessage ->
            % io:format("Bad message received ~w~n", [Badmessage])
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
            io:format("Node ~w :: ~w starting with Leader :: ~w :: ~w~n", [Id, self(), Leader, Slaves]),
            init_loop(Id, Master, Leader, Slaves, Group, N, [], 0)
            % slave(Id, Master, Leader, Slaves, Group, N, {})
    after 500 ->
        % ok
        Master ! {error, "no reply from leader"}
    end.

init_loop(Id, Master, Leader, Slaves, Group, N, Last, Ref) ->
    receive
        % leader dead
        {'DOWN', _Ref, process, Leader, _Reason} ->
            exit("leader dead");
        % screen should be initialized here
        {msg, K, {state, Ref, Color}} ->
            io:format("Node ~w got gui init~n", [Id]),
            Master ! {state, Ref, Color},
            slave(Id, Master, Leader, Slaves, Group, K, Last);
        % we should receive our ref immediately from the worker
        {mcast, {state_request, Ref2}} when Ref == 0 ->
            io:format("Node ~w got new Ref~n", [Id]),
            % Master ! {state_request, Ref2},
            Leader ! {mcast, {state_request, Ref2}},
            init_loop(Id, Master, Leader, Slaves, Group, N, Last, Ref2);
        {msg, K, {state_request, Ref}} when K > N ->
            io:format("Node ~w got state request echo~n", [Id]),
            Master ! {state_request, Ref},
            init_loop(Id, Master, Leader, Slaves, Group, K, Last, Ref)
        % _Ignore ->
        %     io:format("Node ~w ignoring request~n", [Id]),
        %     init_loop(Id, Master, Leader, Slaves, Group, N, Last, Ref)
        after 500 ->
            io:format("Node ~w getting no reponse from leader, restarting~n", [Id])
    end.
% don't think this is needed but would rather comment than do git magic
% init_election(Id, Master, Slaves, Group, N, Last, Ref) ->
%     io:format("Node ~w init election!!~n", [Id]),
%     Self = self(),
%     case Slaves of
%         [Self, Slaves] ->
%             %oh god i'm in charge now - no need to rebroadcast, no one else has initialized
%             leader(Id, Master, Slaves, Group, N);
%         [Leader|Rest] ->
%             % ask new leader for state
%             Leader ! {mcast, {state_request, Ref}},
%             init_loop(Id, Master, Leader, Rest, Group, N, Last, Ref)
%     end.
