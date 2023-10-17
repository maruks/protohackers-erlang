%%%-------------------------------------------------------------------
%% @doc protohackers public API
%% @end
%%%-------------------------------------------------------------------

-module(protohackers_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    protohackers_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
