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
    SupFlags = #{strategy => one_for_one,
                 intensity => 1,
                 period => 5},
    SmokeTest = #{id => smoke_test,
		  start => {smoke_test, start_link, [listen, 5600]},
                  restart => permanent,
		  type => worker},
    {ok, {SupFlags, [SmokeTest]}}.

%% internal functions
