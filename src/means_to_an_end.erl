%%%-------------------------------------------------------------------
%% @doc means_to_an_end gen server
%% @end
%%%-------------------------------------------------------------------

-module(means_to_an_end).

-behaviour(gen_server).

-export([start_link/2,init/1,handle_cast/2,handle_call/3,terminate/2,handle_continue/2]).

-import(gb_trees,[empty/0,insert/3,iterator_from/2,next/1]).

-include_lib("kernel/include/logger.hrl").

-define(READ_TIMEOUT_SECONDS, 60).

start_link(NextStep, State) ->
    gen_server:start_link(?MODULE, {NextStep, State}, []).

init({NextStep, State}=Args) ->
    ?LOG_DEBUG("starting gen_server ~p", [Args]),
    {ok, State, {continue, NextStep}}.

child_spec(NextStep, State, Restart) ->
    #{id => make_ref(),
      start => {?MODULE, start_link, [NextStep, State]},
      restart => Restart,
      type => worker}.

safe_avg(_Sum, 0) ->
    0;
safe_avg(Sum, Items) ->
    trunc( Sum / Items).

get_average(MaxTime, Iterator, Sum, Items) ->
    case next(Iterator) of
	{Key, Value, Iter2} ->
	    if Key =< MaxTime ->
		    get_average(MaxTime, Iter2, Sum + Value, Items + 1);
	       true ->
		    safe_avg(Sum, Items)
	    end;
	none ->
	    safe_avg(Sum, Items)
    end.

query(MinTime, MaxTime, _Tree) when MinTime > MaxTime ->
    0;
query(MinTime, MaxTime, Tree) ->
    get_average(MaxTime, iterator_from(MinTime, Tree), 0 , 0).

process_data(<<"I", Timestamp:32/big-signed-integer, Price:32/big-signed-integer, Rest/binary>>, Tree, Socket) ->
    process_data(Rest, insert(Timestamp, Price, Tree), Socket);
process_data(<<"Q", MinTime:32/big-signed-integer, MaxTime:32/big-signed-integer, Rest/binary>>, Tree, Socket) ->
    Average = query(MinTime, MaxTime, Tree),
    gen_tcp:send(Socket, <<Average:32/big-signed-integer>>),
    process_data(Rest, Tree, Socket);
process_data(<<_:72, Rest/binary>>, Tree, Socket) ->
    process_data(Rest, Tree, Socket);
process_data(<<Rest/binary>>, Tree, _Socket) ->
    {Rest, Tree}.

handle_continue(listen, PortNumber) ->
    ?LOG_DEBUG("listen ~p", [PortNumber]),
    Options = [binary, {active, false}, {reuseaddr, true}],
    case gen_tcp:listen(PortNumber, Options) of
	{ok, ListenSocket} ->
	    ChildSpec = child_spec(accept, {ListenSocket}, permanent),
	    {ok, _Child} = supervisor:start_child(protohackers_sup, ChildSpec),
    	    {noreply, {ListenSocket}, {continue, accept}};
	{error, Reason} ->
	    {stop, Reason}
    end;
handle_continue(accept, {ListenSocket}=S) ->
    case gen_tcp:accept(ListenSocket, 30000) of
	{ok, Socket} ->
	    ChildSpec = child_spec(read, {Socket, <<>>, empty()}, temporary),
	    case supervisor:start_child(protohackers_sup, ChildSpec) of
		{ok, Child} ->
		    ok = gen_tcp:controlling_process(Socket, Child),
		    {noreply, {ListenSocket}, {continue, accept}};
		{error, Reason} ->
		    {stop, Reason, S}
            end;
	{error, timeout} ->
	    {noreply, {ListenSocket}, {continue, accept}};
        {error, Reason} ->
	    {stop, Reason, S}
    end;
handle_continue(read, {Socket, Buffer, Tree}) ->
    ?LOG_DEBUG("read"),
    case gen_tcp:recv(Socket, 0, ?READ_TIMEOUT_SECONDS * 1000) of
	{ok, Data} ->
	    {NewBuffer, NewTree} = process_data(<<Buffer/binary,Data/binary>>, Tree, Socket),
	    {noreply, {Socket, NewBuffer, NewTree}, {continue, read}};
	{error, closed} ->
	    {noreply, {Socket}, {continue, close}};
	{error, timeout} ->
	    ?LOG_DEBUG("timeout"),
	    {noreply, {Socket}, {continue, close}}
    end;
handle_continue(close, {Socket}) ->
    ?LOG_DEBUG("close"),
    gen_tcp:close(Socket),
    {stop, {shutdown, "connection closed"}, Socket}.

terminate(Reason, _State) ->
    ?LOG_DEBUG("terminate ~p", [Reason]),
    ok.

handle_call(_Request, _From, State) ->
    {noreply,State}.

handle_cast(_Message, State) ->
    {noreply,State}.
