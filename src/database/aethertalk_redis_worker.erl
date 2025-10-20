%%%-------------------------------------------------------------------
%% @doc AetherTalk Redis worker
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_redis_worker).

-behaviour(gen_server).
-behaviour(poolboy_worker).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([command/2, pipeline/2, health_check/0]).

-include("aethertalk.hrl").

-record(state, {
    connection
}).

start_link(Args) ->
    gen_server:start_link(?MODULE, Args, []).

init(Args) ->
    process_flag(trap_exit, true),
    
    Host = proplists:get_value(host, Args, "localhost"),
    Port = proplists:get_value(port, Args, 6379),
    Database = proplists:get_value(database, Args, 0),
    Password = proplists:get_value(password, Args, ""),
    
    ConnectOptions = [
        {host, Host},
        {port, Port},
        {database, Database},
        {password, Password},
        {reconnect_sleep, 100}
    ],
    
    case eredis:start_link(ConnectOptions) of
        {ok, Connection} ->
            io:format("Redis worker connected successfully~n"),
            {ok, #state{connection = Connection}};
        {error, Reason} ->
            io:format("Failed to connect to Redis: ~p~n", [Reason]),
            {stop, Reason}
    end.

handle_call({command, Command}, _From, #state{connection = Conn} = State) ->
    Result = eredis:q(Conn, Command),
    {reply, Result, State};

handle_call({pipeline, Commands}, _From, #state{connection = Conn} = State) ->
    Result = eredis:qp(Conn, Commands),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'EXIT', _Pid, _Reason}, State) ->
    {stop, normal, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{connection = Conn}) ->
    case Conn of
        undefined -> ok;
        _ -> eredis:stop(Conn)
    end,
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Public API

command(Worker, Command) ->
    gen_server:call(Worker, {command, Command}).

pipeline(Worker, Commands) ->
    gen_server:call(Worker, {pipeline, Commands}).

%% @doc Health check for Redis connectivity
health_check() ->
    try
        case poolboy:transaction(redis_pool, fun(Worker) ->
            command(Worker, ["PING"])
        end) of
            {ok, <<"PONG">>} -> ok;
            _ -> error
        end
    catch
        _:_ -> error
    end.