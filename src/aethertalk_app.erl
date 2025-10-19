%%%-------------------------------------------------------------------
%% @doc AetherTalk application entry point
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_app).

-behaviour(application).

-export([start/2, stop/1]).
-export([get_env/1, get_env/2]).

start(_StartType, _StartArgs) ->
    lager:info("Starting AetherTalk application"),
    
    % Initialize database schema
    ok = aethertalk_db:init_schema(),
    
    % Initialize media storage directories
    ok = aethertalk_media:init_storage(),
    
    % Start the main supervisor
    case aethertalk_sup:start_link() of
        {ok, Pid} ->
            lager:info("AetherTalk application started successfully"),
            {ok, Pid};
        Error ->
            lager:error("Failed to start AetherTalk application: ~p", [Error]),
            Error
    end.

stop(_State) ->
    lager:info("Stopping AetherTalk application"),
    ok.

%% @doc Get application environment variable
get_env(Key) ->
    application:get_env(aethertalk, Key).

%% @doc Get application environment variable with default
get_env(Key, Default) ->
    application:get_env(aethertalk, Key, Default).

%% internal functions
