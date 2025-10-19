%%%-------------------------------------------------------------------
%%% @doc
%%% Status/Stories Management Service for AetherTalk
%%% Handles user status updates, stories, and viewing functionality
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_status_manager).
-behaviour(gen_server).

% OTP callbacks
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    create_status/4,
    get_status/1,
    get_user_statuses/1,
    get_contacts_statuses/1,
    view_status/2,
    delete_status/2,
    get_status_viewers/1,
    cleanup_expired_statuses/0
]).

-include("aethertalk.hrl").

-record(state, {
    cleanup_timer :: timer:tref()
}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Create a new status/story
create_status(UserId, Content, MediaUrl, MediaType) ->
    gen_server:call(?MODULE, {create_status, UserId, Content, MediaUrl, MediaType}).

%% @doc Get a specific status
get_status(StatusId) ->
    gen_server:call(?MODULE, {get_status, StatusId}).

%% @doc Get all statuses for a user
get_user_statuses(UserId) ->
    gen_server:call(?MODULE, {get_user_statuses, UserId}).

%% @doc Get statuses from user's contacts
get_contacts_statuses(UserId) ->
    gen_server:call(?MODULE, {get_contacts_statuses, UserId}).

%% @doc Mark status as viewed by user
view_status(StatusId, ViewerId) ->
    gen_server:call(?MODULE, {view_status, StatusId, ViewerId}).

%% @doc Delete a status
delete_status(StatusId, UserId) ->
    gen_server:call(?MODULE, {delete_status, StatusId, UserId}).

%% @doc Get viewers of a status
get_status_viewers(StatusId) ->
    gen_server:call(?MODULE, {get_status_viewers, StatusId}).

%% @doc Clean up expired statuses
cleanup_expired_statuses() ->
    gen_server:cast(?MODULE, cleanup_expired_statuses).

%% ===================================================================
%% gen_server callbacks
%% ===================================================================

init([]) ->
    lager:info("Status Manager started"),
    
    % Set up cleanup timer (every hour)
    {ok, Timer} = timer:apply_interval(3600000, ?MODULE, cleanup_expired_statuses, []),
    
    {ok, #state{cleanup_timer = Timer}}.

handle_call({create_status, UserId, Content, MediaUrl, MediaType}, _From, State) ->
    Result = do_create_status(UserId, Content, MediaUrl, MediaType),
    {reply, Result, State};

handle_call({get_status, StatusId}, _From, State) ->
    Result = do_get_status(StatusId),
    {reply, Result, State};

handle_call({get_user_statuses, UserId}, _From, State) ->
    Result = do_get_user_statuses(UserId),
    {reply, Result, State};

handle_call({get_contacts_statuses, UserId}, _From, State) ->
    Result = do_get_contacts_statuses(UserId),
    {reply, Result, State};

handle_call({view_status, StatusId, ViewerId}, _From, State) ->
    Result = do_view_status(StatusId, ViewerId),
    {reply, Result, State};

handle_call({delete_status, StatusId, UserId}, _From, State) ->
    Result = do_delete_status(StatusId, UserId),
    {reply, Result, State};

handle_call({get_status_viewers, StatusId}, _From, State) ->
    Result = do_get_status_viewers(StatusId),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(cleanup_expired_statuses, State) ->
    do_cleanup_expired_statuses(),
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

do_create_status(UserId, Content, MediaUrl, MediaType) ->
    StatusId = aethertalk_utils:generate_uuid(),
    ExpiresAt = calculate_expiry_time(),
    
    SQL = "INSERT INTO user_status (id, user_id, content, media_url, media_type, expires_at, created_at) 
           VALUES ($1, $2, $3, $4, $5, $6, NOW()) RETURNING created_at",
    
    case aethertalk_db:query(SQL, [StatusId, UserId, Content, MediaUrl, MediaType, ExpiresAt]) of
        {ok, {_Columns, [{CreatedAt}]}} ->
            Status = #{
                id => StatusId,
                user_id => UserId,
                content => Content,
                media_url => MediaUrl,
                media_type => MediaType,
                expires_at => ExpiresAt,
                created_at => CreatedAt,
                view_count => 0
            },
            
            % Notify contacts about new status
            notify_status_created(UserId, StatusId),
            {ok, Status};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_status(StatusId) ->
    SQL = "SELECT us.id, us.user_id, us.content, us.media_url, us.media_type, 
                  us.background_color, us.expires_at, us.created_at,
                  u.username, u.full_name, u.avatar_url,
                  COUNT(sv.viewer_id) as view_count
           FROM user_status us
           JOIN users u ON us.user_id = u.id
           LEFT JOIN status_views sv ON us.id = sv.status_id
           WHERE us.id = $1 AND us.is_deleted = FALSE AND us.expires_at > NOW()
           GROUP BY us.id, u.username, u.full_name, u.avatar_url",
    
    case aethertalk_db:query(SQL, [StatusId]) of
        {ok, {_Columns, [{Id, UserId, Content, MediaUrl, MediaType, BackgroundColor,
                         ExpiresAt, CreatedAt, Username, FullName, AvatarUrl, ViewCount}]}} ->
            Status = #{
                id => Id,
                user_id => UserId,
                content => Content,
                media_url => MediaUrl,
                media_type => MediaType,
                background_color => BackgroundColor,
                expires_at => ExpiresAt,
                created_at => CreatedAt,
                user => #{
                    username => Username,
                    full_name => FullName,
                    avatar_url => AvatarUrl
                },
                view_count => ViewCount
            },
            {ok, Status};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_user_statuses(UserId) ->
    SQL = "SELECT us.id, us.content, us.media_url, us.media_type, us.background_color,
                  us.expires_at, us.created_at,
                  COUNT(sv.viewer_id) as view_count
           FROM user_status us
           LEFT JOIN status_views sv ON us.id = sv.status_id
           WHERE us.user_id = $1 AND us.is_deleted = FALSE AND us.expires_at > NOW()
           GROUP BY us.id
           ORDER BY us.created_at DESC",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, Rows}} ->
            Statuses = lists:map(fun({Id, Content, MediaUrl, MediaType, BackgroundColor,
                                     ExpiresAt, CreatedAt, ViewCount}) ->
                #{
                    id => Id,
                    content => Content,
                    media_url => MediaUrl,
                    media_type => MediaType,
                    background_color => BackgroundColor,
                    expires_at => ExpiresAt,
                    created_at => CreatedAt,
                    view_count => ViewCount
                }
            end, Rows),
            {ok, Statuses};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_contacts_statuses(UserId) ->
    SQL = "SELECT us.id, us.user_id, us.content, us.media_url, us.media_type,
                  us.background_color, us.expires_at, us.created_at,
                  u.username, u.full_name, u.avatar_url,
                  COUNT(sv.viewer_id) as view_count,
                  CASE WHEN sv_user.viewer_id IS NOT NULL THEN TRUE ELSE FALSE END as viewed_by_user
           FROM user_status us
           JOIN users u ON us.user_id = u.id
           JOIN contacts c ON (c.contact_user_id = us.user_id AND c.user_id = $1)
           LEFT JOIN status_views sv ON us.id = sv.status_id
           LEFT JOIN status_views sv_user ON (us.id = sv_user.status_id AND sv_user.viewer_id = $1)
           WHERE us.is_deleted = FALSE AND us.expires_at > NOW()
           GROUP BY us.id, u.username, u.full_name, u.avatar_url, sv_user.viewer_id
           ORDER BY us.created_at DESC",
    
    case aethertalk_db:query(SQL, [UserId, UserId]) of
        {ok, {_Columns, Rows}} ->
            Statuses = lists:map(fun({Id, StatusUserId, Content, MediaUrl, MediaType,
                                     BackgroundColor, ExpiresAt, CreatedAt, Username,
                                     FullName, AvatarUrl, ViewCount, ViewedByUser}) ->
                #{
                    id => Id,
                    user_id => StatusUserId,
                    content => Content,
                    media_url => MediaUrl,
                    media_type => MediaType,
                    background_color => BackgroundColor,
                    expires_at => ExpiresAt,
                    created_at => CreatedAt,
                    user => #{
                        username => Username,
                        full_name => FullName,
                        avatar_url => AvatarUrl
                    },
                    view_count => ViewCount,
                    viewed_by_user => ViewedByUser
                }
            end, Rows),
            {ok, Statuses};
        {error, Reason} ->
            {error, Reason}
    end.

do_view_status(StatusId, ViewerId) ->
    % Check if status exists and is not expired
    case do_get_status(StatusId) of
        {ok, Status} ->
            % Check if user already viewed this status
            CheckSQL = "SELECT id FROM status_views WHERE status_id = $1 AND viewer_id = $2",
            case aethertalk_db:query(CheckSQL, [StatusId, ViewerId]) of
                {ok, {_Columns, []}} ->
                    % Add new view record
                    InsertSQL = "INSERT INTO status_views (status_id, viewer_id, viewed_at) 
                                VALUES ($1, $2, NOW()) RETURNING id, viewed_at",
                    case aethertalk_db:query(InsertSQL, [StatusId, ViewerId]) of
                        {ok, {_Cols, [{ViewId, ViewedAt}]}} ->
                            View = #{
                                id => ViewId,
                                status_id => StatusId,
                                viewer_id => ViewerId,
                                viewed_at => ViewedAt
                            },
                            
                            % Notify status owner about view
                            notify_status_viewed(maps:get(user_id, Status), StatusId, ViewerId),
                            {ok, View};
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {ok, {_Columns, [_]}} ->
                    {error, already_viewed};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_delete_status(StatusId, UserId) ->
    % Check if user owns the status
    CheckSQL = "SELECT user_id FROM user_status WHERE id = $1 AND is_deleted = FALSE",
    case aethertalk_db:query(CheckSQL, [StatusId]) of
        {ok, {_Columns, [{UserId}]}} ->
            % Soft delete the status
            SQL = "UPDATE user_status SET is_deleted = TRUE WHERE id = $1",
            case aethertalk_db:query(SQL, [StatusId]) of
                {ok, 1} ->
                    % Notify about status deletion
                    notify_status_deleted(UserId, StatusId),
                    ok;
                {ok, 0} ->
                    {error, not_found};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, {_Columns, [{_OtherUserId}]}} ->
            {error, not_owner};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_status_viewers(StatusId) ->
    SQL = "SELECT sv.viewer_id, sv.viewed_at, u.username, u.full_name, u.avatar_url
           FROM status_views sv
           JOIN users u ON sv.viewer_id = u.id
           WHERE sv.status_id = $1
           ORDER BY sv.viewed_at DESC",
    
    case aethertalk_db:query(SQL, [StatusId]) of
        {ok, {_Columns, Rows}} ->
            Viewers = lists:map(fun({ViewerId, ViewedAt, Username, FullName, AvatarUrl}) ->
                #{
                    user_id => ViewerId,
                    viewed_at => ViewedAt,
                    username => Username,
                    full_name => FullName,
                    avatar_url => AvatarUrl
                }
            end, Rows),
            {ok, Viewers};
        {error, Reason} ->
            {error, Reason}
    end.

do_cleanup_expired_statuses() ->
    SQL = "UPDATE user_status SET is_deleted = TRUE 
           WHERE expires_at <= NOW() AND is_deleted = FALSE",
    
    case aethertalk_db:query(SQL, []) of
        {ok, Count} ->
            lager:info("Cleaned up ~p expired statuses", [Count]),
            ok;
        {error, Reason} ->
            lager:error("Failed to cleanup expired statuses: ~p", [Reason]),
            {error, Reason}
    end.

%% Helper functions

calculate_expiry_time() ->
    % Status expires after 24 hours
    {{Year, Month, Day}, {Hour, Minute, Second}} = calendar:universal_time(),
    Seconds = calendar:datetime_to_gregorian_seconds({{Year, Month, Day}, {Hour, Minute, Second}}),
    ExpirySeconds = Seconds + (24 * 60 * 60), % 24 hours
    calendar:gregorian_seconds_to_datetime(ExpirySeconds).

%% Notification functions

notify_status_created(UserId, StatusId) ->
    lager:info("Status created by user ~p: ~p", [UserId, StatusId]),
    % Here you would integrate with WebSocket manager to notify contacts
    spawn(fun() ->
        case aethertalk_user_manager:get_user_contacts(UserId) of
            {ok, Contacts} ->
                ContactIds = [maps:get(contact_user_id, Contact) || Contact <- Contacts],
                Notification = #{
                    type => <<"status_created">>,
                    user_id => UserId,
                    status_id => StatusId,
                    timestamp => erlang:system_time(millisecond)
                },
                lists:foreach(fun(ContactId) ->
                    aethertalk_websocket_manager:send_to_user(ContactId, Notification)
                end, ContactIds);
            {error, _} ->
                ok
        end
    end).

notify_status_viewed(StatusOwnerId, StatusId, ViewerId) ->
    lager:info("Status ~p viewed by user ~p", [StatusId, ViewerId]),
    % Notify status owner about the view
    spawn(fun() ->
        Notification = #{
            type => <<"status_viewed">>,
            status_id => StatusId,
            viewer_id => ViewerId,
            timestamp => erlang:system_time(millisecond)
        },
        aethertalk_websocket_manager:send_to_user(StatusOwnerId, Notification)
    end).

notify_status_deleted(UserId, StatusId) ->
    lager:info("Status deleted by user ~p: ~p", [UserId, StatusId]).