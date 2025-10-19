%%%-------------------------------------------------------------------
%% @doc AetherTalk presence management system
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_presence_manager).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    update_presence/2,
    get_user_presence/1,
    get_contacts_presence/1,
    set_typing/3,
    stop_typing/2,
    get_typing_users/1,
    subscribe_presence/2,
    unsubscribe_presence/2,
    broadcast_presence_update/2
]).

-include("aethertalk.hrl").

-record(state, {
    presence_table,
    typing_table,
    subscriptions_table
}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    % Create ETS tables for fast lookups
    PresenceTable = ets:new(user_presence, [set, public, named_table, {read_concurrency, true}]),
    TypingTable = ets:new(typing_status, [set, public, named_table, {read_concurrency, true}]),
    SubscriptionsTable = ets:new(presence_subscriptions, [bag, public, named_table, {read_concurrency, true}]),
    
    lager:info("Presence manager started"),
    {ok, #state{
        presence_table = PresenceTable,
        typing_table = TypingTable,
        subscriptions_table = SubscriptionsTable
    }}.

handle_call({update_presence, UserId, IsOnline}, _From, State) ->
    Result = do_update_presence(UserId, IsOnline, State),
    {reply, Result, State};

handle_call({get_user_presence, UserId}, _From, State) ->
    Result = do_get_user_presence(UserId, State),
    {reply, Result, State};

handle_call({get_contacts_presence, UserId}, _From, State) ->
    Result = do_get_contacts_presence(UserId, State),
    {reply, Result, State};

handle_call({set_typing, UserId, ChatId, IsTyping}, _From, State) ->
    Result = do_set_typing(UserId, ChatId, IsTyping, State),
    {reply, Result, State};

handle_call({stop_typing, UserId, ChatId}, _From, State) ->
    Result = do_stop_typing(UserId, ChatId, State),
    {reply, Result, State};

handle_call({get_typing_users, ChatId}, _From, State) ->
    Result = do_get_typing_users(ChatId, State),
    {reply, Result, State};

handle_call({subscribe_presence, SubscriberId, UserId}, _From, State) ->
    Result = do_subscribe_presence(SubscriberId, UserId, State),
    {reply, Result, State};

handle_call({unsubscribe_presence, SubscriberId, UserId}, _From, State) ->
    Result = do_unsubscribe_presence(SubscriberId, UserId, State),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({broadcast_presence_update, UserId, PresenceData}, State) ->
    do_broadcast_presence_update(UserId, PresenceData, State),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({typing_timeout, UserId, ChatId}, State) ->
    % Auto-stop typing after timeout
    do_stop_typing(UserId, ChatId, State),
    {noreply, State};

handle_info({presence_cleanup}, State) ->
    % Periodic cleanup of stale presence data
    do_presence_cleanup(State),
    % Schedule next cleanup
    erlang:send_after(300000, self(), {presence_cleanup}), % 5 minutes
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{presence_table = PT, typing_table = TT, subscriptions_table = ST}) ->
    ets:delete(PT),
    ets:delete(TT),
    ets:delete(ST),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Public API functions

update_presence(UserId, IsOnline) ->
    gen_server:call(?MODULE, {update_presence, UserId, IsOnline}).

get_user_presence(UserId) ->
    gen_server:call(?MODULE, {get_user_presence, UserId}).

get_contacts_presence(UserId) ->
    gen_server:call(?MODULE, {get_contacts_presence, UserId}).

set_typing(UserId, ChatId, IsTyping) ->
    gen_server:call(?MODULE, {set_typing, UserId, ChatId, IsTyping}).

stop_typing(UserId, ChatId) ->
    gen_server:call(?MODULE, {stop_typing, UserId, ChatId}).

get_typing_users(ChatId) ->
    gen_server:call(?MODULE, {get_typing_users, ChatId}).

subscribe_presence(SubscriberId, UserId) ->
    gen_server:call(?MODULE, {subscribe_presence, SubscriberId, UserId}).

unsubscribe_presence(SubscriberId, UserId) ->
    gen_server:call(?MODULE, {unsubscribe_presence, SubscriberId, UserId}).

broadcast_presence_update(UserId, PresenceData) ->
    gen_server:cast(?MODULE, {broadcast_presence_update, UserId, PresenceData}).

%% Internal functions

do_update_presence(UserId, IsOnline, #state{presence_table = PT}) ->
    Timestamp = erlang:system_time(second),
    PresenceData = #{
        user_id => UserId,
        is_online => IsOnline,
        last_seen => Timestamp,
        updated_at => Timestamp
    },
    
    % Store in ETS for fast access
    ets:insert(PT, {UserId, PresenceData}),
    
    % Update in Redis for persistence and clustering
    update_presence_in_redis(UserId, PresenceData),
    
    % Update database
    update_presence_in_db(UserId, IsOnline),
    
    % Broadcast to subscribers
    broadcast_presence_update(UserId, PresenceData),
    
    lager:debug("Updated presence for user ~p: ~p", [UserId, IsOnline]),
    ok.

do_get_user_presence(UserId, #state{presence_table = PT}) ->
    case ets:lookup(PT, UserId) of
        [{UserId, PresenceData}] ->
            {ok, PresenceData};
        [] ->
            % Try to get from Redis
            case get_presence_from_redis(UserId) of
                {ok, PresenceData} ->
                    % Cache in ETS
                    ets:insert(PT, {UserId, PresenceData}),
                    {ok, PresenceData};
                {error, not_found} ->
                    % Get from database
                    case get_presence_from_db(UserId) of
                        {ok, PresenceData} ->
                            % Cache in ETS and Redis
                            ets:insert(PT, {UserId, PresenceData}),
                            update_presence_in_redis(UserId, PresenceData),
                            {ok, PresenceData};
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end
    end.

do_get_contacts_presence(UserId, State) ->
    % Get user's contacts
    case aethertalk_user_manager:get_user_contacts(UserId) of
        {ok, Contacts} ->
            ContactIds = [maps:get(contact_user_id, Contact) || Contact <- Contacts],
            PresenceList = lists:foldl(fun(ContactId, Acc) ->
                case do_get_user_presence(ContactId, State) of
                    {ok, PresenceData} ->
                        [PresenceData | Acc];
                    {error, _} ->
                        Acc
                end
            end, [], ContactIds),
            {ok, PresenceList};
        {error, Reason} ->
            {error, Reason}
    end.

do_set_typing(UserId, ChatId, IsTyping, #state{typing_table = TT}) ->
    Key = {UserId, ChatId},
    Timestamp = erlang:system_time(second),
    
    case IsTyping of
        true ->
            TypingData = #{
                user_id => UserId,
                chat_id => ChatId,
                is_typing => true,
                started_at => Timestamp
            },
            ets:insert(TT, {Key, TypingData}),
            
            % Set timeout to auto-stop typing
            erlang:send_after(10000, self(), {typing_timeout, UserId, ChatId}), % 10 seconds
            
            % Broadcast typing status
            broadcast_typing_status(ChatId, UserId, true),
            ok;
        false ->
            do_stop_typing(UserId, ChatId, #state{typing_table = TT})
    end.

do_stop_typing(UserId, ChatId, #state{typing_table = TT}) ->
    Key = {UserId, ChatId},
    case ets:lookup(TT, Key) of
        [{Key, _TypingData}] ->
            ets:delete(TT, Key),
            broadcast_typing_status(ChatId, UserId, false),
            ok;
        [] ->
            ok
    end.

do_get_typing_users(ChatId, #state{typing_table = TT}) ->
    TypingUsers = ets:foldl(fun({{_UserId, ChatIdKey}, TypingData}, Acc) ->
        case ChatIdKey of
            ChatId ->
                [TypingData | Acc];
            _ ->
                Acc
        end
    end, [], TT),
    {ok, TypingUsers}.

do_subscribe_presence(SubscriberId, UserId, #state{subscriptions_table = ST}) ->
    ets:insert(ST, {UserId, SubscriberId}),
    ok.

do_unsubscribe_presence(SubscriberId, UserId, #state{subscriptions_table = ST}) ->
    ets:delete_object(ST, {UserId, SubscriberId}),
    ok.

do_broadcast_presence_update(UserId, PresenceData, #state{subscriptions_table = ST}) ->
    % Get all subscribers for this user
    Subscribers = ets:lookup(ST, UserId),
    
    % Send presence update to each subscriber
    lists:foreach(fun({_, SubscriberId}) ->
        aethertalk_websocket_manager:send_to_user(SubscriberId, #{
            type => ?WS_MSG_PRESENCE,
            data => PresenceData
        })
    end, Subscribers).

do_presence_cleanup(#state{presence_table = PT}) ->
    CurrentTime = erlang:system_time(second),
    StaleThreshold = CurrentTime - 3600, % 1 hour
    
    % Remove stale presence data
    ets:foldl(fun({UserId, PresenceData}, Acc) ->
        LastSeen = maps:get(last_seen, PresenceData, 0),
        case LastSeen < StaleThreshold of
            true ->
                ets:delete(PT, UserId),
                % Mark user as offline in database
                update_presence_in_db(UserId, false);
            false ->
                ok
        end,
        Acc
    end, ok, PT).

%% Helper functions

update_presence_in_redis(UserId, PresenceData) ->
    Key = <<"presence:", UserId/binary>>,
    Value = jsx:encode(PresenceData),
    poolboy:transaction(redis_pool, fun(Worker) ->
        aethertalk_redis_worker:command(Worker, ["SETEX", Key, "3600", Value])
    end).

get_presence_from_redis(UserId) ->
    Key = <<"presence:", UserId/binary>>,
    case poolboy:transaction(redis_pool, fun(Worker) ->
        aethertalk_redis_worker:command(Worker, ["GET", Key])
    end) of
        {ok, undefined} ->
            {error, not_found};
        {ok, Value} ->
            try
                PresenceData = jsx:decode(Value),
                {ok, PresenceData}
            catch
                _:_ ->
                    {error, invalid_data}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

update_presence_in_db(UserId, IsOnline) ->
    SQL = "UPDATE users SET is_online = $1, last_seen = NOW(), updated_at = NOW() WHERE id = $2",
    aethertalk_db:query(SQL, [IsOnline, UserId]).

get_presence_from_db(UserId) ->
    SQL = "SELECT is_online, last_seen FROM users WHERE id = $1",
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, [{IsOnline, LastSeen}]}} ->
            PresenceData = #{
                user_id => UserId,
                is_online => IsOnline,
                last_seen => calendar:datetime_to_gregorian_seconds(LastSeen),
                updated_at => erlang:system_time(second)
            },
            {ok, PresenceData};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

broadcast_typing_status(ChatId, UserId, IsTyping) ->
    aethertalk_websocket_manager:broadcast_to_chat(ChatId, #{
        type => ?WS_MSG_TYPING,
        data => #{
            user_id => UserId,
            chat_id => ChatId,
            is_typing => IsTyping
        }
    }, UserId).