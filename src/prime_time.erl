%%%-------------------------------------------------------------------
%% @doc prime time gen server
%% @end
%%%-------------------------------------------------------------------

-module(prime_time).

-behaviour(gen_server).

-import(jsone, [try_decode/1,encode/1]).

-export([start_link/2,init/1,handle_cast/2,handle_call/3,terminate/2,handle_continue/2]).

-export([is_prime/1]).

-include_lib("kernel/include/logger.hrl").

-define(BUFFER_SIZE_KB, 64).
-define(READ_TIMEOUT_SECONDS, 10).

start_link(NextStep, State) ->
    gen_server:start_link(?MODULE, {NextStep, State}, []).

init({NextStep, State}=Args) ->
    ?LOG_DEBUG("starting gen_server ~p", [Args]),
    {ok, State, {continue, NextStep}}.

child_spec(NextStep, State, Restart) ->
    #{id => make_ref(),
      start => {prime_time, start_link, [NextStep, State]},
      restart => Restart,
      type => worker}.

decode(Binary) ->
    case try_decode(Binary) of
	{ok, #{<<"method">> := <<"isPrime">>,<<"number">> := Number}, _} when is_number(Number) ->
	    {ok, Number};
	_ ->
	    {error}
    end.

test_numbers(I, MaxI, _N) when I > MaxI ->
    true;
test_numbers(I, _MaxI, N) when N rem I =:= 0 ; N rem (I + 2) =:= 0 ->
    false;
test_numbers(I, MaxI, N) ->
    test_numbers(I + 6, MaxI, N).

is_prime(N) when is_integer(N), N > 1 ->
    if
	N =:= 2 orelse N =:= 3 ->
	    true;
	N rem 2 =:= 0 orelse N rem 3 =:= 0 ->
	    false;
	true -> test_numbers(5, trunc(math:sqrt(N)), N)
    end;
is_prime(_) ->
    false.

get_reply(Binary) ->
    case decode(Binary) of
	{ok, Number} ->
	    IsPrime = is_prime(Number),
	    encode(#{method => <<"isPrime">>, prime => IsPrime});
	{error} ->
	    <<"malformed">>
    end.

process_parts(_Socket,[Last]) ->
    Last;
process_parts(Socket,[H|T]) ->
    Reply = get_reply(H),
    gen_tcp:send(Socket, <<Reply/binary,10>>),
    process_parts(Socket,T).

process_buffer(Socket, Buffer) ->
    Parts = binary:split(Buffer,<<10>>,[global]),
    process_parts(Socket,Parts).

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
	    ?LOG_DEBUG("accept"),
	    ChildSpec = child_spec(read, {Socket, <<>>}, temporary),
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
handle_continue(read, {Socket, Buffer}) ->
    ?LOG_DEBUG("read"),
    case gen_tcp:recv(Socket, 0, ?READ_TIMEOUT_SECONDS * 1000) of
	{ok, Data} ->
	    NewBuffer = process_buffer(Socket, <<Buffer/binary,Data/binary>>),
	    if
		byte_size(NewBuffer) > ?BUFFER_SIZE_KB * 1024 ->
		    ?LOG_DEBUG("buffer overflow"),
		    {noreply, {Socket}, {continue, close}};
		true ->
		    {noreply, {Socket, NewBuffer}, {continue, read}}
		end;
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
