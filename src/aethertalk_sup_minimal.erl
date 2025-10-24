%%%-------------------------------------------------------------------
%% @doc AetherTalk minimal supervisor for testing
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_sup_minimal).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 10,
        period => 60
    },
    
    ChildSpecs = [
        % Database connection pools
        #{
            id => aethertalk_db_sup,
            start => {aethertalk_db_sup, start_link, []},
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [aethertalk_db_sup]
        },
        
        % User management system
        #{
            id => aethertalk_user_manager,
            start => {aethertalk_user_manager, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_user_manager]
        },
        
        % HTTP/WebSocket API supervisor
        #{
            id => aethertalk_api_sup,
            start => {aethertalk_api_sup, start_link, []},
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [aethertalk_api_sup]
        }
    ],
    
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions