%%%-------------------------------------------------------------------
%% @doc protohackers top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(protohackers_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    Port = application:get_env(protohackers, smoke_test_port, 5000),
    SupFlags = #{strategy => one_for_one,
                 intensity => 1,
                 period => 5},
    SmokeTest = #{id => smoke_test,
		  start => {smoke_test, start_link, [listen, Port]},
                  restart => permanent,
		  type => worker},
    PrimeTime = #{id => prime_time,
		  start => {prime_time, start_link, [listen, Port + 1]},
                  restart => permanent,
		  type => worker},
    {ok, {SupFlags, [SmokeTest, PrimeTime]}}.

%% internal functions
