%%%-------------------------------------------------------------------
%% @doc AetherTalk application entry point
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_app).

-behaviour(application).

-export([start/2, stop/1]).
-export([get_env/1, get_env/2]).

start(_StartType, _StartArgs) ->
    io:format("Starting AetherTalk application~n"),
    
    % Load environment variables from .env file
    aethertalk_env:load_env_file(".env"),
    
    % Override application environment with loaded environment variables
    application:set_env(aethertalk, database, aethertalk_env:get_database_config()),
    application:set_env(aethertalk, redis, aethertalk_env:get_redis_config()),
    application:set_env(aethertalk, firebase, aethertalk_env:get_firebase_config()),
    
    % Set HTTP port from environment
    HttpPort = aethertalk_env:get_env("AETHERTALK_HTTP_PORT", 12000, integer),
    application:set_env(aethertalk, http_port, HttpPort),
    
    % Initialize media storage directories
    ok = aethertalk_media:init_storage(),
    
    % Start the full supervisor for complete functionality
    case aethertalk_sup:start_link() of
        {ok, Pid} ->
            io:format("AetherTalk application started successfully (full mode)~n"),
            {ok, Pid};
        Error ->
            io:format("Failed to start AetherTalk application: ~p~n", [Error]),
            Error
    end.

stop(_State) ->
    io:format("Stopping AetherTalk application~n"),
    ok.

%% @doc Get application environment variable
get_env(Key) ->
    application:get_env(aethertalk, Key).

%% @doc Get application environment variable with default
get_env(Key, Default) ->
    application:get_env(aethertalk, Key, Default).

%% internal functions
