%%%-------------------------------------------------------------------
%% @doc AetherTalk PostgreSQL database worker
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_db_worker).

-behaviour(gen_server).
-behaviour(poolboy_worker).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([query/4, transaction/2]).

-include("aethertalk.hrl").

-record(state, {
    connection
}).

start_link(Args) ->
    gen_server:start_link(?MODULE, Args, []).

init(Args) ->
    process_flag(trap_exit, true),
    
    Host = proplists:get_value(host, Args, "localhost"),
    _Port = proplists:get_value(port, Args, 5432),
    Database = proplists:get_value(database, Args, "aethertalk"),
    _Username = proplists:get_value(username, Args, "aethertalk"),
    _Password = proplists:get_value(password, Args, ""),
    _SSL = proplists:get_value(ssl, Args, false),
    
    % Temporary bypass for testing - create a mock connection
    io:format("Database worker starting (mock mode for testing) - Host: ~s, DB: ~s~n", [Host, Database]),
    {ok, #state{connection = undefined}}.

handle_call({query, SQL, Params, _Timeout}, _From, #state{connection = undefined} = State) ->
    % Mock response for testing
    io:format("Mock database query: ~s with params ~p~n", [SQL, Params]),
    {reply, {ok, {[], []}}, State};

handle_call({transaction, _Fun}, _From, #state{connection = undefined} = State) ->
    % Mock transaction for testing
    io:format("Mock database transaction~n"),
    {reply, {ok, mock_transaction_result}, State};

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
        _ -> epgsql:close(Conn)
    end,
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Public API

query(Worker, SQL, Params, Timeout) ->
    gen_server:call(Worker, {query, SQL, Params, Timeout}).

transaction(Worker, Fun) ->
    gen_server:call(Worker, {transaction, Fun}).