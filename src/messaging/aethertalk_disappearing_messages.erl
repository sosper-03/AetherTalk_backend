%%%-------------------------------------------------------------------
%%% @doc
%%% Disappearing Messages Service for AetherTalk
%%% Handles message auto-deletion and ephemeral messaging
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_disappearing_messages).
-behaviour(gen_server).

% OTP callbacks
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    set_chat_disappearing_timer/3,
    get_chat_disappearing_timer/1,
    disable_chat_disappearing/2,
    send_disappearing_message/4,
    mark_message_for_deletion/2,
    cleanup_expired_messages/0,
    get_disappearing_settings/1
]).

-include("aethertalk.hrl").

-record(state, {
    cleanup_timer :: timer:tref()
}).

%% Disappearing message timer options (in seconds)
-define(TIMER_OPTIONS, [
    {<<"off">>, 0},
    {<<"5_seconds">>, 5},
    {<<"10_seconds">>, 10},
    {<<"30_seconds">>, 30},
    {<<"1_minute">>, 60},
    {<<"5_minutes">>, 300},
    {<<"1_hour">>, 3600},
    {<<"1_day">>, 86400},
    {<<"1_week">>, 604800}
]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Set disappearing message timer for a chat
set_chat_disappearing_timer(ChatId, UserId, TimerSeconds) ->
    gen_server:call(?MODULE, {set_chat_disappearing_timer, ChatId, UserId, TimerSeconds}).

%% @doc Get disappearing message timer for a chat
get_chat_disappearing_timer(ChatId) ->
    gen_server:call(?MODULE, {get_chat_disappearing_timer, ChatId}).

%% @doc Disable disappearing messages for a chat
disable_chat_disappearing(ChatId, UserId) ->
    gen_server:call(?MODULE, {disable_chat_disappearing, ChatId, UserId}).

%% @doc Send a message with disappearing timer
send_disappearing_message(ChatId, SenderId, Content, TimerSeconds) ->
    gen_server:call(?MODULE, {send_disappearing_message, ChatId, SenderId, Content, TimerSeconds}).

%% @doc Mark a message for deletion after timer expires
mark_message_for_deletion(MessageId, TimerSeconds) ->
    gen_server:call(?MODULE, {mark_message_for_deletion, MessageId, TimerSeconds}).

%% @doc Clean up expired disappearing messages
cleanup_expired_messages() ->
    gen_server:cast(?MODULE, cleanup_expired_messages).

%% @doc Get disappearing message settings for a chat
get_disappearing_settings(ChatId) ->
    gen_server:call(?MODULE, {get_disappearing_settings, ChatId}).

%% ===================================================================
%% gen_server callbacks
%% ===================================================================

init([]) ->
    lager:info("Disappearing Messages service started"),
    
    % Set up cleanup timer (every 5 minutes)
    {ok, Timer} = timer:apply_interval(300000, ?MODULE, cleanup_expired_messages, []),
    
    {ok, #state{cleanup_timer = Timer}}.

handle_call({set_chat_disappearing_timer, ChatId, UserId, TimerSeconds}, _From, State) ->
    Result = do_set_chat_disappearing_timer(ChatId, UserId, TimerSeconds),
    {reply, Result, State};

handle_call({get_chat_disappearing_timer, ChatId}, _From, State) ->
    Result = do_get_chat_disappearing_timer(ChatId),
    {reply, Result, State};

handle_call({disable_chat_disappearing, ChatId, UserId}, _From, State) ->
    Result = do_disable_chat_disappearing(ChatId, UserId),
    {reply, Result, State};

handle_call({send_disappearing_message, ChatId, SenderId, Content, TimerSeconds}, _From, State) ->
    Result = do_send_disappearing_message(ChatId, SenderId, Content, TimerSeconds),
    {reply, Result, State};

handle_call({mark_message_for_deletion, MessageId, TimerSeconds}, _From, State) ->
    Result = do_mark_message_for_deletion(MessageId, TimerSeconds),
    {reply, Result, State};

handle_call({get_disappearing_settings, ChatId}, _From, State) ->
    Result = do_get_disappearing_settings(ChatId),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(cleanup_expired_messages, State) ->
    do_cleanup_expired_messages(),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{cleanup_timer = Timer}) ->
    timer:cancel(Timer),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ===================================================================
%% Internal functions
%% ===================================================================

do_set_chat_disappearing_timer(ChatId, UserId, TimerSeconds) ->
    % Validate timer value
    case is_valid_timer(TimerSeconds) of
        true ->
            % Check if user has permission to change settings
            case check_chat_permission(ChatId, UserId) of
                ok ->
                    % Update or insert chat disappearing settings
                    SQL = "INSERT INTO chat_disappearing_settings (chat_id, timer_seconds, set_by, updated_at) 
                           VALUES ($1, $2, $3, NOW())
                           ON CONFLICT (chat_id) 
                           DO UPDATE SET timer_seconds = $2, set_by = $3, updated_at = NOW()
                           RETURNING updated_at",
                    
                    case aethertalk_db:query(SQL, [ChatId, TimerSeconds, UserId]) of
                        {ok, {_Columns, [{UpdatedAt}]}} ->
                            Settings = #{
                                chat_id => ChatId,
                                timer_seconds => TimerSeconds,
                                set_by => UserId,
                                updated_at => UpdatedAt
                            },
                            
                            % Notify chat participants about the change
                            notify_disappearing_timer_changed(ChatId, UserId, TimerSeconds),
                            {ok, Settings};
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        false ->
            {error, invalid_timer_value}
    end.

do_get_chat_disappearing_timer(ChatId) ->
    SQL = "SELECT timer_seconds, set_by, updated_at 
           FROM chat_disappearing_settings 
           WHERE chat_id = $1",
    
    case aethertalk_db:query(SQL, [ChatId]) of
        {ok, {_Columns, [{TimerSeconds, SetBy, UpdatedAt}]}} ->
            Settings = #{
                chat_id => ChatId,
                timer_seconds => TimerSeconds,
                set_by => SetBy,
                updated_at => UpdatedAt
            },
            {ok, Settings};
        {ok, {_Columns, []}} ->
            {ok, #{
                chat_id => ChatId,
                timer_seconds => 0,
                set_by => null,
                updated_at => null
            }};
        {error, Reason} ->
            {error, Reason}
    end.

do_disable_chat_disappearing(ChatId, UserId) ->
    do_set_chat_disappearing_timer(ChatId, UserId, 0).

do_send_disappearing_message(ChatId, SenderId, Content, TimerSeconds) ->
    % Send regular message first
    case aethertalk_message_router:send_message(SenderId, ChatId, #{
        content => Content,
        message_type => <<"text">>,
        disappearing_timer => TimerSeconds
    }) of
        {ok, Message} ->
            MessageId = maps:get(id, Message),
            
            % Mark message for deletion if timer > 0
            if TimerSeconds > 0 ->
                do_mark_message_for_deletion(MessageId, TimerSeconds);
            true ->
                ok
            end,
            
            {ok, Message};
        {error, Reason} ->
            {error, Reason}
    end.

do_mark_message_for_deletion(MessageId, TimerSeconds) ->
    DeleteAt = calculate_delete_time(TimerSeconds),
    
    SQL = "INSERT INTO disappearing_messages (message_id, delete_at, created_at) 
           VALUES ($1, $2, NOW())
           ON CONFLICT (message_id) 
           DO UPDATE SET delete_at = $2, created_at = NOW()
           RETURNING id, created_at",
    
    case aethertalk_db:query(SQL, [MessageId, DeleteAt]) of
        {ok, {_Columns, [{Id, CreatedAt}]}} ->
            DeletionRecord = #{
                id => Id,
                message_id => MessageId,
                delete_at => DeleteAt,
                created_at => CreatedAt
            },
            {ok, DeletionRecord};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_disappearing_settings(ChatId) ->
    SQL = "SELECT cds.timer_seconds, cds.set_by, cds.updated_at,
                  u.username, u.full_name
           FROM chat_disappearing_settings cds
           LEFT JOIN users u ON cds.set_by = u.id
           WHERE cds.chat_id = $1",
    
    case aethertalk_db:query(SQL, [ChatId]) of
        {ok, {_Columns, [{TimerSeconds, SetBy, UpdatedAt, Username, FullName}]}} ->
            Settings = #{
                chat_id => ChatId,
                timer_seconds => TimerSeconds,
                timer_label => get_timer_label(TimerSeconds),
                set_by => SetBy,
                set_by_user => case SetBy of
                    null -> null;
                    _ -> #{username => Username, full_name => FullName}
                end,
                updated_at => UpdatedAt,
                available_timers => ?TIMER_OPTIONS
            },
            {ok, Settings};
        {ok, {_Columns, []}} ->
            {ok, #{
                chat_id => ChatId,
                timer_seconds => 0,
                timer_label => <<"off">>,
                set_by => null,
                set_by_user => null,
                updated_at => null,
                available_timers => ?TIMER_OPTIONS
            }};
        {error, Reason} ->
            {error, Reason}
    end.

do_cleanup_expired_messages() ->
    % Get expired messages
    SQL = "SELECT dm.message_id, m.chat_id
           FROM disappearing_messages dm
           JOIN messages m ON dm.message_id = m.id
           WHERE dm.delete_at <= NOW() AND m.is_deleted = FALSE",
    
    case aethertalk_db:query(SQL, []) of
        {ok, {_Columns, Rows}} ->
            ExpiredMessages = [{MessageId, ChatId} || {MessageId, ChatId} <- Rows],
            
            % Delete expired messages
            lists:foreach(fun({MessageId, ChatId}) ->
                delete_expired_message(MessageId, ChatId)
            end, ExpiredMessages),
            
            lager:info("Cleaned up ~p expired disappearing messages", [length(ExpiredMessages)]),
            {ok, length(ExpiredMessages)};
        {error, Reason} ->
            lager:error("Failed to cleanup expired messages: ~p", [Reason]),
            {error, Reason}
    end.

%% Helper functions

is_valid_timer(TimerSeconds) ->
    ValidTimers = [Seconds || {_Label, Seconds} <- ?TIMER_OPTIONS],
    lists:member(TimerSeconds, ValidTimers).

get_timer_label(TimerSeconds) ->
    case lists:keyfind(TimerSeconds, 2, ?TIMER_OPTIONS) of
        {Label, _} -> Label;
        false -> <<"custom">>
    end.

check_chat_permission(ChatId, UserId) ->
    % Check if user is a participant in the chat
    SQL = "SELECT role FROM chat_participants 
           WHERE chat_id = $1 AND user_id = $2 AND left_at IS NULL",
    
    case aethertalk_db:query(SQL, [ChatId, UserId]) of
        {ok, {_Columns, [_]}} ->
            ok;
        {ok, {_Columns, []}} ->
            {error, not_participant};
        {error, Reason} ->
            {error, Reason}
    end.

calculate_delete_time(TimerSeconds) ->
    Now = calendar:universal_time(),
    NowSeconds = calendar:datetime_to_gregorian_seconds(Now),
    DeleteSeconds = NowSeconds + TimerSeconds,
    calendar:gregorian_seconds_to_datetime(DeleteSeconds).

delete_expired_message(MessageId, ChatId) ->
    % Soft delete the message
    SQL = "UPDATE messages SET is_deleted = TRUE, updated_at = NOW() 
           WHERE id = $1",
    
    case aethertalk_db:query(SQL, [MessageId]) of
        {ok, 1} ->
            % Remove from disappearing messages table
            DeleteSQL = "DELETE FROM disappearing_messages WHERE message_id = $1",
            aethertalk_db:query(DeleteSQL, [MessageId]),
            
            % Notify chat participants about message deletion
            notify_message_disappeared(ChatId, MessageId),
            ok;
        {ok, 0} ->
            lager:warning("Message ~p already deleted", [MessageId]),
            ok;
        {error, Reason} ->
            lager:error("Failed to delete expired message ~p: ~p", [MessageId, Reason]),
            {error, Reason}
    end.

%% Notification functions

notify_disappearing_timer_changed(ChatId, UserId, TimerSeconds) ->
    lager:info("Disappearing timer changed in chat ~p by user ~p to ~p seconds", 
               [ChatId, UserId, TimerSeconds]),
    
    spawn(fun() ->
        Notification = #{
            type => <<"disappearing_timer_changed">>,
            chat_id => ChatId,
            changed_by => UserId,
            timer_seconds => TimerSeconds,
            timer_label => get_timer_label(TimerSeconds),
            timestamp => erlang:system_time(millisecond)
        },
        aethertalk_websocket_manager:broadcast_to_chat(ChatId, Notification)
    end).

notify_message_disappeared(ChatId, MessageId) ->
    lager:info("Message ~p disappeared from chat ~p", [MessageId, ChatId]),
    
    spawn(fun() ->
        Notification = #{
            type => <<"message_disappeared">>,
            chat_id => ChatId,
            message_id => MessageId,
            timestamp => erlang:system_time(millisecond)
        },
        aethertalk_websocket_manager:broadcast_to_chat(ChatId, Notification)
    end).