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
    Port = proplists:get_value(port, Args, 5432),
    Database = proplists:get_value(database, Args, "aethertalk"),
    Username = proplists:get_value(username, Args, "aethertalk"),
    Password = proplists:get_value(password, Args, ""),
    
    ConnectOptions = [
        {host, Host},
        {port, Port},
        {database, Database},
        {username, Username},
        {password, Password},
        {timeout, 5000},
        {ssl, false}
    ],
    
    case epgsql:connect(ConnectOptions) of
        {ok, Connection} ->
            io:format("Database worker connected successfully~n"),
            {ok, #state{connection = Connection}};
        {error, Reason} ->
            io:format("Failed to connect to database: ~p~n", [Reason]),
            {stop, Reason}
    end.

handle_call({query, SQL, Params, Timeout}, _From, #state{connection = Conn} = State) ->
    Result = case epgsql:equery(Conn, SQL, Params, Timeout) of
        {ok, Columns, Rows} ->
            {ok, {Columns, Rows}};
        {ok, Count} ->
            {ok, Count};
        {ok, Count, Columns, Rows} ->
            {ok, {Count, Columns, Rows}};
        {error, Error} ->
            io:format("Database query error: ~p~n", [Error]),
            {error, Error}
    end,
    {reply, Result, State};

handle_call({transaction, Fun}, _From, #state{connection = Conn} = State) ->
    Result = epgsql:with_transaction(Conn, Fun),
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