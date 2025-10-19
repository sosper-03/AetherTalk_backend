%%%-------------------------------------------------------------------
%% @doc AetherTalk core infrastructure supervisor
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_core_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 60
    },
    
    ChildSpecs = [
        % Configuration manager
        #{
            id => aethertalk_config,
            start => {aethertalk_config, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_config]
        },
        
        % Metrics collector
        #{
            id => aethertalk_metrics,
            start => {aethertalk_metrics, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_metrics]
        },
        
        % Health check service
        #{
            id => aethertalk_health,
            start => {aethertalk_health, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_health]
        },
        
        % Rate limiter
        #{
            id => aethertalk_rate_limiter,
            start => {aethertalk_rate_limiter, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_rate_limiter]
        }
    ],
    
    {ok, {SupFlags, ChildSpecs}}.