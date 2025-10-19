%%%-------------------------------------------------------------------
%% @doc AetherTalk database supervisor
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_db_sup).

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
    
    % Get database configuration
    {ok, DbConfig} = aethertalk_app:get_env(database),
    {ok, RedisConfig} = aethertalk_app:get_env(redis),
    
    ChildSpecs = [
        % PostgreSQL connection pool
        poolboy:child_spec(
            postgres_pool,
            [
                {name, {local, postgres_pool}},
                {worker_module, aethertalk_db_worker},
                {size, proplists:get_value(pool_size, DbConfig, 10)},
                {max_overflow, proplists:get_value(max_overflow, DbConfig, 5)}
            ],
            DbConfig
        ),
        
        % Redis connection pool
        poolboy:child_spec(
            redis_pool,
            [
                {name, {local, redis_pool}},
                {worker_module, aethertalk_redis_worker},
                {size, proplists:get_value(pool_size, RedisConfig, 5)},
                {max_overflow, 5}
            ],
            RedisConfig
        ),
        
        % Database schema manager
        #{
            id => aethertalk_db_schema,
            start => {aethertalk_db_schema, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_db_schema]
        },
        
        % Database migration manager
        #{
            id => aethertalk_db_migration,
            start => {aethertalk_db_migration, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_db_migration]
        }
    ],
    
    {ok, {SupFlags, ChildSpecs}}.