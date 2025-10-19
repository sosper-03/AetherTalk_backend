%%%-------------------------------------------------------------------
%% @doc AetherTalk notification service
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_notification_service).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    send_push_notification/2,
    send_email_notification/3,
    create_notification/2,
    mark_notification_read/2,
    get_user_notifications/2
]).

-include("aethertalk.hrl").

-record(state, {}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    lager:info("Notification service started"),
    {ok, #state{}}.

handle_call({send_push_notification, UserId, NotificationData}, _From, State) ->
    Result = do_send_push_notification(UserId, NotificationData),
    {reply, Result, State};

handle_call({send_email_notification, UserId, Subject, Body}, _From, State) ->
    Result = do_send_email_notification(UserId, Subject, Body),
    {reply, Result, State};

handle_call({create_notification, UserId, NotificationData}, _From, State) ->
    Result = do_create_notification(UserId, NotificationData),
    {reply, Result, State};

handle_call({mark_notification_read, NotificationId, UserId}, _From, State) ->
    Result = do_mark_notification_read(NotificationId, UserId),
    {reply, Result, State};

handle_call({get_user_notifications, UserId, Options}, _From, State) ->
    Result = do_get_user_notifications(UserId, Options),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Public API functions

send_push_notification(UserId, NotificationData) ->
    gen_server:call(?MODULE, {send_push_notification, UserId, NotificationData}).

send_email_notification(UserId, Subject, Body) ->
    gen_server:call(?MODULE, {send_email_notification, UserId, Subject, Body}).

create_notification(UserId, NotificationData) ->
    gen_server:call(?MODULE, {create_notification, UserId, NotificationData}).

mark_notification_read(NotificationId, UserId) ->
    gen_server:call(?MODULE, {mark_notification_read, NotificationId, UserId}).

get_user_notifications(UserId, Options) ->
    gen_server:call(?MODULE, {get_user_notifications, UserId, Options}).

%% Internal functions (stubs for now)

do_send_push_notification(UserId, NotificationData) ->
    % This is a stub - in production you'd integrate with FCM, APNS, etc.
    _Type = maps:get(type, NotificationData, <<"message">>),
    Title = maps:get(title, NotificationData, <<"New Message">>),
    _Body = maps:get(body, NotificationData, <<"You have a new message">>),
    
    % Create notification record
    case do_create_notification(UserId, NotificationData) of
        {ok, Notification} ->
            % Simulate push notification sending
            lager:info("Sending push notification to user ~p: ~p", [UserId, Title]),
            {ok, Notification};
        {error, Reason} ->
            {error, Reason}
    end.

do_send_email_notification(UserId, Subject, _Body) ->
    % This is a stub - in production you'd use SMTP or email service
    lager:info("Sending email notification to user ~p: ~p", [UserId, Subject]),
    {ok, #{sent_at => erlang:system_time(second)}}.

do_create_notification(UserId, NotificationData) ->
    Type = maps:get(type, NotificationData, <<"message">>),
    Title = maps:get(title, NotificationData, <<"Notification">>),
    Body = maps:get(body, NotificationData, <<"">>),
    Data = maps:get(data, NotificationData, #{}),
    
    SQL = "INSERT INTO notifications (user_id, type, title, body, data) 
           VALUES ($1, $2, $3, $4, $5) RETURNING id, created_at",
    case aethertalk_db:query(SQL, [UserId, Type, Title, Body, jsx:encode(Data)]) of
        {ok, {_Columns, [{NotificationId, CreatedAt}]}} ->
            {ok, #{
                id => NotificationId,
                user_id => UserId,
                type => Type,
                title => Title,
                body => Body,
                data => Data,
                is_read => false,
                created_at => CreatedAt
            }};
        {error, Reason} ->
            {error, Reason}
    end.

do_mark_notification_read(NotificationId, UserId) ->
    SQL = "UPDATE notifications SET is_read = TRUE 
           WHERE id = $1 AND user_id = $2",
    case aethertalk_db:query(SQL, [NotificationId, UserId]) of
        {ok, 1} ->
            ok;
        {ok, 0} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_user_notifications(UserId, Options) ->
    Limit = maps:get(limit, Options, 50),
    Offset = maps:get(offset, Options, 0),
    OnlyUnread = maps:get(only_unread, Options, false),
    
    WhereClause = case OnlyUnread of
        true -> "WHERE user_id = $1 AND is_read = FALSE";
        false -> "WHERE user_id = $1"
    end,
    
    SQL = "SELECT id, type, title, body, data, is_read, created_at 
           FROM notifications " ++ WhereClause ++ "
           ORDER BY created_at DESC LIMIT $2 OFFSET $3",
    
    case aethertalk_db:query(SQL, [UserId, Limit, Offset]) of
        {ok, {_Columns, Rows}} ->
            Notifications = [row_to_notification_map(Row) || Row <- Rows],
            {ok, Notifications};
        {error, Reason} ->
            {error, Reason}
    end.

row_to_notification_map({Id, Type, Title, Body, Data, IsRead, CreatedAt}) ->
    #{
        id => Id,
        type => Type,
        title => Title,
        body => Body,
        data => case Data of
            null -> #{};
            _ -> jsx:decode(Data)
        end,
        is_read => IsRead,
        created_at => CreatedAt
    }.