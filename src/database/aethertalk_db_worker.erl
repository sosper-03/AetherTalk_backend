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
    SSL = proplists:get_value(ssl, Args, false),
    
    io:format("Database worker starting - Host: ~s:~p, DB: ~s, User: ~s~n", [Host, Port, Database, Username]),
    
    % Connect to PostgreSQL
    ConnectOptions = case SSL of
        true ->
            % Supabase PostgreSQL with SSL
            [
                {host, Host},
                {port, Port},
                {database, Database},
                {username, Username},
                {password, Password},
                {ssl, true},
                {ssl_opts, [
                    {verify, verify_none}, % For cloud providers, we trust the certificate
                    {server_name_indication, disable}
                ]},
                {timeout, 5000} % 5 second timeout
            ];
        false ->
            % Local or non-SSL connection
            [
                {host, Host},
                {port, Port},
                {database, Database},
                {username, Username},
                {password, Password},
                {ssl, false},
                {timeout, 5000} % 5 second timeout
            ]
    end,
    
    io:format("Attempting to connect with options: ~p~n", [ConnectOptions]),
    
    case epgsql:connect(ConnectOptions) of
        {ok, Connection} ->
            io:format("Database connection established successfully~n"),
            {ok, #state{connection = Connection}};
        {error, Reason} ->
            io:format("Database connection failed: ~p~n", [Reason]),
            io:format("This is expected if you haven't set up your database yet.~n"),
            io:format("Please follow the AIVEN_SETUP.md guide to set up your database.~n"),
            {stop, {connection_failed, Reason}}
    end.

handle_call({query, SQL, Params, _Timeout}, _From, #state{connection = Connection} = State) ->
    io:format("Database query: ~s with params ~p~n", [SQL, Params]),
    
    Result = case Connection of
        undefined ->
            {error, no_connection};
        _ ->
            case epgsql:equery(Connection, SQL, Params) of
                {ok, Columns, Rows} ->
                    {ok, {Columns, Rows}};
                {ok, Count} when is_integer(Count) ->
                    {ok, Count};
                {error, Reason} ->
                    {error, Reason};
                Other ->
                    Other
            end
    end,
    
    {reply, Result, State};

handle_call({transaction, Fun}, _From, #state{connection = Connection} = State) ->
    io:format("Database transaction~n"),
    
    Result = case Connection of
        undefined ->
            {error, no_connection};
        _ ->
            try
                epgsql:with_transaction(Connection, Fun)
            catch
                Error:Reason ->
                    {error, {Error, Reason}}
            end
    end,
    
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