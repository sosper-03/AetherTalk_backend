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
    
    % Database schema will be initialized by the database supervisor
    
    % Initialize media storage directories
    ok = aethertalk_media:init_storage(),
    
    % Start the minimal supervisor for testing
    case aethertalk_sup_minimal:start_link() of
        {ok, Pid} ->
            io:format("AetherTalk application started successfully (minimal mode)~n"),
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
