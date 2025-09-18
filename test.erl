-module(test).

-compile(export_all).



% Used to create the first worker, try:
%
% W1 = test:first(1, gms1, 1000)

first(N, Module, Sleep) ->
   worker:start(N, Module, random:uniform(256), Sleep).

% Used to create additional workers, try:
%
%  test:add(2, gms1, W1, 1000) and 
%  test:add(3, gms1, W1, 1000) and ...

add(N, Module, Wrk, Sleep) ->
   worker:start(N, Module, random:uniform(256), Wrk, Sleep).

%% To create a number of workers in one go, 

more(N, Module, Sleep) when N > 1 ->
    Wrk = first(1, Module, Sleep),
    Ns = lists:seq(2,N),
    lists:map(fun(Id) -> add(Id, Module, Wrk, Sleep) end, Ns),
    Wrk.

add_monitor(N, Module, Wrk, Sleep) ->
    Node = worker:start(N, Module, random:uniform(256), Wrk, Sleep),
    erlang:monitor(process, Node),
    Node.
		      
continuous(N, Module, Sleep) when N > 1 ->
    Wrk = first(1, Module, Sleep),
    erlang:monitor(process, Wrk),
    Ns = lists:seq(2, N),
    Refs0 = #{Wrk => 1},
    Refs = lists:foldr(fun(Id, Accin) -> 
        Node = add_monitor(Id, Module, Wrk, Sleep),
        maps:put(Node, Id, Accin)
     end, Refs0, Ns),
    continue_loop(Refs, Module, Sleep).


continue_loop(Refs, Module, Sleep) ->
    receive
        {'DOWN', _Ref, process, Leader, _Reason} ->
            io:format("Test Detected Crash: ~w~n", [Leader]),
            Id = maps:get(Leader, Refs),
            Refs2 = maps:remove(Leader, Refs),
            {Nl, _, _} = maps:next(maps:iterator(Refs2)),
            Node = add_monitor(Id, Module, Nl, Sleep),
            Refs3 = maps:put(Node, Id, Refs2),
            continue_loop(Refs3, Module, Sleep)
    end.

% These are messages that we can send to one of the workers. It will
% multicast it to all workers. They should (if everything works)
% receive the message at the same (logical) time.

freeze(Wrk) ->
    Wrk ! {send, freeze}.

go(Wrk) ->
    Wrk ! {send, go}.

sleep(Wrk, Sleep) ->
    Wrk ! {send, {sleep, Sleep}}.

stop(Wrk) ->
    Wrk ! {send, stop}.


			  

















