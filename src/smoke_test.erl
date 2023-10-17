%%%-------------------------------------------------------------------
%% @doc smoke test gen server
%% @end
%%%-------------------------------------------------------------------

-module(smoke_test).

-behaviour(gen_server).

-export([start_link/2,init/1,handle_cast/2,handle_call/3,terminate/2,handle_continue/2]).

-include_lib("kernel/include/logger.hrl").

-define(BUFFER_SIZE_KB, 128).
-define(READ_TIMEOUT_SECONDS, 20).

start_link(NextStep, State) ->
    gen_server:start_link(?MODULE, {NextStep, State}, []).

init({NextStep, State}=Args) ->
    ?LOG_DEBUG("starting gen_server ~p", [Args]),
    {ok, State, {continue, NextStep}}.

child_spec(NextStep, State, Restart) ->
    #{id => make_ref(),
      start => {smoke_test, start_link, [NextStep, State]},
      restart => Restart,
      type => worker}.

handle_continue(listen, PortNumber) ->
    ?LOG_DEBUG("listen ~p", [PortNumber]),
    Options = [binary, {active, false}, {reuseaddr, true}, {exit_on_close, false}],
    case gen_tcp:listen(PortNumber, Options) of
	{ok, ListenSocket} ->
	    ChildSpec = child_spec(accept, {ListenSocket}, permanent),
	    {ok, _Child} = supervisor:start_child(protohackers_sup, ChildSpec),
    	    {noreply, {ListenSocket}, {continue, accept}};
	{error, Reason} ->
	    {stop, Reason}
    end;
handle_continue(accept, {ListenSocket}=S) ->
    ?LOG_DEBUG("accept"),
    case gen_tcp:accept(ListenSocket, 30000) of
	{ok, Socket} ->
	    ChildSpec = child_spec(read, {Socket, [], 0}, temporary),
	    case supervisor:start_child(protohackers_sup, ChildSpec) of
		{ok, Child} ->
		    ok = gen_tcp:controlling_process(Socket, Child),
		    {noreply, {ListenSocket}, {continue, accept}};
		{error, Reason} ->
		    {stop, Reason, S}
            end;
	{error, timeout} ->
	    ?LOG_DEBUG("timeout"),
	    {noreply, {ListenSocket}, {continue, accept}};
        {error, Reason} ->
	    {stop, Reason, S}
    end;
handle_continue(read, {Socket, Data, Size}) ->
    ?LOG_DEBUG("read"),
    case gen_tcp:recv(Socket, 0, ?READ_TIMEOUT_SECONDS * 1000) of
	{ok, Binary} ->
	    Bytes = byte_size(Binary),
	    if
		Bytes + Size > ?BUFFER_SIZE_KB * 1024 ->
		    ?LOG_DEBUG("buffer overflow"),
		    {noreply, {Socket, list_to_binary("buffer overflow")}, {continue, write}};
		true ->
		    {noreply, {Socket, [Data, Binary], Size + Bytes}, {continue, read}}
		end;
	{error, closed} ->
	    {noreply, {Socket, Data}, {continue, write}};
	{error, timeout} ->
	    {noreply, {Socket}, {continue, close}}
    end;

handle_continue(write, {Socket, Data}) ->
    ?LOG_DEBUG("write"),
    gen_tcp:send(Socket, Data),
    {noreply, {Socket}, {continue, close}};
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
