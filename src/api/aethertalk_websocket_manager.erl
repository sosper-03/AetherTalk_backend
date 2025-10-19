%%%-------------------------------------------------------------------
%% @doc AetherTalk WebSocket connection manager
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_websocket_manager).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    register_connection/3,
    unregister_connection/1,
    send_to_user/2,
    send_to_connection/2,
    broadcast_to_chat/3,
    broadcast_to_users/2,
    get_user_connections/1,
    get_connection_info/1,
    cleanup_stale_connections/0,
    subscribe_to_chat/2,
    unsubscribe_from_chat/2,
    update_connection_ping/1,
    get_connection_stats/0
]).

-include("aethertalk.hrl").

-record(state, {
    connections_table,    % ConnectionPid -> ConnectionInfo
    user_connections_table, % UserId -> [ConnectionPid]
    chat_subscriptions_table % ChatId -> [ConnectionPid]
}).

-record(connection_info, {
    pid,
    user_id,
    session_id,
    device_id,
    connected_at,
    last_ping,
    subscribed_chats = []
}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    % Create ETS tables for connection management
    ConnectionsTable = ets:new(websocket_connections, [set, public, named_table, {read_concurrency, true}]),
    UserConnectionsTable = ets:new(user_connections, [bag, public, named_table, {read_concurrency, true}]),
    ChatSubscriptionsTable = ets:new(chat_subscriptions, [bag, public, named_table, {read_concurrency, true}]),
    
    % Schedule periodic cleanup
    erlang:send_after(60000, self(), cleanup_stale_connections), % 1 minute
    
    lager:info("WebSocket manager started"),
    {ok, #state{
        connections_table = ConnectionsTable,
        user_connections_table = UserConnectionsTable,
        chat_subscriptions_table = ChatSubscriptionsTable
    }}.

handle_call({register_connection, ConnectionPid, UserId, SessionData}, _From, State) ->
    Result = do_register_connection(ConnectionPid, UserId, SessionData, State),
    {reply, Result, State};

handle_call({unregister_connection, ConnectionPid}, _From, State) ->
    Result = do_unregister_connection(ConnectionPid, State),
    {reply, Result, State};

handle_call({send_to_user, UserId, Message}, _From, State) ->
    Result = do_send_to_user(UserId, Message, State),
    {reply, Result, State};

handle_call({send_to_connection, ConnectionPid, Message}, _From, State) ->
    Result = do_send_to_connection(ConnectionPid, Message, State),
    {reply, Result, State};

handle_call({get_user_connections, UserId}, _From, State) ->
    Result = do_get_user_connections(UserId, State),
    {reply, Result, State};

handle_call({get_connection_info, ConnectionPid}, _From, State) ->
    Result = do_get_connection_info(ConnectionPid, State),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({broadcast_to_chat, ChatId, Message, ExcludeUserId}, State) ->
    do_broadcast_to_chat(ChatId, Message, ExcludeUserId, State),
    {noreply, State};

handle_cast({broadcast_to_users, UserIds, Message}, State) ->
    do_broadcast_to_users(UserIds, Message, State),
    {noreply, State};

handle_cast({subscribe_to_chat, ConnectionPid, ChatId}, State) ->
    do_subscribe_to_chat(ConnectionPid, ChatId, State),
    {noreply, State};

handle_cast({unsubscribe_from_chat, ConnectionPid, ChatId}, State) ->
    do_unsubscribe_from_chat(ConnectionPid, ChatId, State),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(cleanup_stale_connections, State) ->
    do_cleanup_stale_connections(State),
    % Schedule next cleanup
    erlang:send_after(60000, self(), cleanup_stale_connections),
    {noreply, State};

handle_info({'DOWN', _Ref, process, Pid, _Reason}, State) ->
    % Handle connection process death
    do_unregister_connection(Pid, State),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{connections_table = CT, user_connections_table = UCT, chat_subscriptions_table = CST}) ->
    ets:delete(CT),
    ets:delete(UCT),
    ets:delete(CST),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Public API functions

register_connection(ConnectionPid, UserId, SessionData) ->
    gen_server:call(?MODULE, {register_connection, ConnectionPid, UserId, SessionData}).

unregister_connection(ConnectionPid) ->
    gen_server:call(?MODULE, {unregister_connection, ConnectionPid}).

send_to_user(UserId, Message) ->
    gen_server:call(?MODULE, {send_to_user, UserId, Message}).

send_to_connection(ConnectionPid, Message) ->
    gen_server:call(?MODULE, {send_to_connection, ConnectionPid, Message}).

broadcast_to_chat(ChatId, Message, ExcludeUserId) ->
    gen_server:cast(?MODULE, {broadcast_to_chat, ChatId, Message, ExcludeUserId}).

broadcast_to_users(UserIds, Message) ->
    gen_server:cast(?MODULE, {broadcast_to_users, UserIds, Message}).

get_user_connections(UserId) ->
    gen_server:call(?MODULE, {get_user_connections, UserId}).

get_connection_info(ConnectionPid) ->
    gen_server:call(?MODULE, {get_connection_info, ConnectionPid}).

cleanup_stale_connections() ->
    gen_server:cast(?MODULE, cleanup_stale_connections).

%% Additional API functions for chat subscriptions
subscribe_to_chat(ConnectionPid, ChatId) ->
    gen_server:cast(?MODULE, {subscribe_to_chat, ConnectionPid, ChatId}).

unsubscribe_from_chat(ConnectionPid, ChatId) ->
    gen_server:cast(?MODULE, {unsubscribe_from_chat, ConnectionPid, ChatId}).

%% Internal functions

do_register_connection(ConnectionPid, UserId, SessionData, 
                      #state{connections_table = CT, user_connections_table = UCT}) ->
    SessionId = maps:get(session_id, SessionData, undefined),
    DeviceId = maps:get(device_id, SessionData, undefined),
    
    ConnectionInfo = #connection_info{
        pid = ConnectionPid,
        user_id = UserId,
        session_id = SessionId,
        device_id = DeviceId,
        connected_at = erlang:system_time(second),
        last_ping = erlang:system_time(second)
    },
    
    % Store connection info
    ets:insert(CT, {ConnectionPid, ConnectionInfo}),
    ets:insert(UCT, {UserId, ConnectionPid}),
    
    % Monitor the connection process
    erlang:monitor(process, ConnectionPid),
    
    % Update user presence
    aethertalk_presence_manager:update_presence(UserId, true),
    
    lager:info("Registered WebSocket connection for user ~p", [UserId]),
    ok.

do_unregister_connection(ConnectionPid, 
                        #state{connections_table = CT, user_connections_table = UCT, 
                               chat_subscriptions_table = CST}) ->
    case ets:lookup(CT, ConnectionPid) of
        [{ConnectionPid, ConnectionInfo}] ->
            UserId = ConnectionInfo#connection_info.user_id,
            
            % Remove from all tables
            ets:delete(CT, ConnectionPid),
            ets:delete_object(UCT, {UserId, ConnectionPid}),
            
            % Remove from all chat subscriptions
            ets:foldl(fun({ChatId, Pid}, Acc) ->
                case Pid of
                    ConnectionPid ->
                        ets:delete_object(CST, {ChatId, ConnectionPid});
                    _ ->
                        ok
                end,
                Acc
            end, ok, CST),
            
            % Check if user has other connections
            case ets:lookup(UCT, UserId) of
                [] ->
                    % No other connections, mark user as offline
                    aethertalk_presence_manager:update_presence(UserId, false);
                _ ->
                    % User still has other connections
                    ok
            end,
            
            lager:info("Unregistered WebSocket connection for user ~p", [UserId]),
            ok;
        [] ->
            ok
    end.

do_send_to_user(UserId, Message, #state{user_connections_table = UCT}) ->
    Connections = ets:lookup(UCT, UserId),
    Results = lists:map(fun({_, ConnectionPid}) ->
        do_send_to_connection(ConnectionPid, Message, undefined)
    end, Connections),
    
    case Results of
        [] ->
            {error, user_not_connected};
        _ ->
            SuccessCount = length([ok || ok <- Results]),
            {ok, SuccessCount}
    end.

do_send_to_connection(ConnectionPid, Message, _State) ->
    case is_process_alive(ConnectionPid) of
        true ->
            ConnectionPid ! {send_message, Message},
            ok;
        false ->
            {error, connection_dead}
    end.

do_broadcast_to_chat(ChatId, Message, ExcludeUserId, #state{chat_subscriptions_table = CST}) ->
    Subscribers = ets:lookup(CST, ChatId),
    
    lists:foreach(fun({_, ConnectionPid}) ->
        % Get connection info to check if we should exclude this user
        case do_get_connection_info(ConnectionPid, undefined) of
            {ok, ConnectionInfo} ->
                UserId = ConnectionInfo#connection_info.user_id,
                case UserId of
                    ExcludeUserId ->
                        ok; % Skip this connection
                    _ ->
                        do_send_to_connection(ConnectionPid, Message, undefined)
                end;
            {error, _} ->
                ok
        end
    end, Subscribers).

do_broadcast_to_users(UserIds, Message, State) ->
    lists:foreach(fun(UserId) ->
        do_send_to_user(UserId, Message, State)
    end, UserIds).

do_get_user_connections(UserId, #state{user_connections_table = UCT}) ->
    Connections = ets:lookup(UCT, UserId),
    ConnectionPids = [Pid || {_, Pid} <- Connections],
    {ok, ConnectionPids}.

do_get_connection_info(ConnectionPid, #state{connections_table = CT}) ->
    case ets:lookup(CT, ConnectionPid) of
        [{ConnectionPid, ConnectionInfo}] ->
            {ok, ConnectionInfo};
        [] ->
            {error, not_found}
    end.

do_subscribe_to_chat(ConnectionPid, ChatId, #state{chat_subscriptions_table = CST, connections_table = CT}) ->
    % Verify connection exists
    case ets:lookup(CT, ConnectionPid) of
        [{ConnectionPid, ConnectionInfo}] ->
            % Add to chat subscriptions
            ets:insert(CST, {ChatId, ConnectionPid}),
            
            % Update connection info
            UpdatedInfo = ConnectionInfo#connection_info{
                subscribed_chats = [ChatId | ConnectionInfo#connection_info.subscribed_chats]
            },
            ets:insert(CT, {ConnectionPid, UpdatedInfo}),
            ok;
        [] ->
            {error, connection_not_found}
    end.

do_unsubscribe_from_chat(ConnectionPid, ChatId, #state{chat_subscriptions_table = CST, connections_table = CT}) ->
    % Remove from chat subscriptions
    ets:delete_object(CST, {ChatId, ConnectionPid}),
    
    % Update connection info
    case ets:lookup(CT, ConnectionPid) of
        [{ConnectionPid, ConnectionInfo}] ->
            UpdatedChats = lists:delete(ChatId, ConnectionInfo#connection_info.subscribed_chats),
            UpdatedInfo = ConnectionInfo#connection_info{subscribed_chats = UpdatedChats},
            ets:insert(CT, {ConnectionPid, UpdatedInfo}),
            ok;
        [] ->
            ok
    end.

do_cleanup_stale_connections(#state{connections_table = CT}) ->
    CurrentTime = erlang:system_time(second),
    StaleThreshold = CurrentTime - 300, % 5 minutes
    
    StaleConnections = ets:foldl(fun({ConnectionPid, ConnectionInfo}, Acc) ->
        LastPing = ConnectionInfo#connection_info.last_ping,
        case LastPing < StaleThreshold of
            true ->
                case is_process_alive(ConnectionPid) of
                    false ->
                        [ConnectionPid | Acc];
                    true ->
                        % Send ping to check if connection is still alive
                        ConnectionPid ! {ping},
                        Acc
                end;
            false ->
                Acc
        end
    end, [], CT),
    
    % Remove stale connections
    lists:foreach(fun(ConnectionPid) ->
        do_unregister_connection(ConnectionPid, 
                                #state{connections_table = CT, 
                                       user_connections_table = user_connections,
                                       chat_subscriptions_table = chat_subscriptions})
    end, StaleConnections),
    
    case length(StaleConnections) of
        0 -> ok;
        Count -> lager:info("Cleaned up ~p stale WebSocket connections", [Count])
    end.

%% Helper functions for connection management

update_connection_ping(ConnectionPid) ->
    case ets:lookup(websocket_connections, ConnectionPid) of
        [{ConnectionPid, ConnectionInfo}] ->
            UpdatedInfo = ConnectionInfo#connection_info{
                last_ping = erlang:system_time(second)
            },
            ets:insert(websocket_connections, {ConnectionPid, UpdatedInfo}),
            ok;
        [] ->
            {error, not_found}
    end.

get_connection_stats() ->
    ConnectionCount = ets:info(websocket_connections, size),
    UserCount = length(ets:tab2list(user_connections)),
    ChatSubscriptionCount = ets:info(chat_subscriptions, size),
    
    #{
        total_connections => ConnectionCount,
        unique_users => UserCount,
        chat_subscriptions => ChatSubscriptionCount
    }.