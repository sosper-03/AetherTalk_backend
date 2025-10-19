%%%-------------------------------------------------------------------
%%% @doc
%%% Location Sharing Service for AetherTalk
%%% Handles location sharing, live location, and location-based features
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_location_service).
-behaviour(gen_server).

% OTP callbacks
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    share_location/5,
    share_live_location/6,
    update_live_location/3,
    stop_live_location/2,
    get_location_message/1,
    get_live_locations/1,
    get_nearby_users/4,
    cleanup_expired_live_locations/0
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

%% @doc Share a static location
share_location(ChatId, SenderId, Latitude, Longitude, Address) ->
    gen_server:call(?MODULE, {share_location, ChatId, SenderId, Latitude, Longitude, Address}).

%% @doc Start sharing live location
share_live_location(ChatId, SenderId, Latitude, Longitude, Address, DurationMinutes) ->
    gen_server:call(?MODULE, {share_live_location, ChatId, SenderId, Latitude, Longitude, Address, DurationMinutes}).

%% @doc Update live location coordinates
update_live_location(LiveLocationId, Latitude, Longitude) ->
    gen_server:call(?MODULE, {update_live_location, LiveLocationId, Latitude, Longitude}).

%% @doc Stop sharing live location
stop_live_location(LiveLocationId, UserId) ->
    gen_server:call(?MODULE, {stop_live_location, LiveLocationId, UserId}).

%% @doc Get location message details
get_location_message(MessageId) ->
    gen_server:call(?MODULE, {get_location_message, MessageId}).

%% @doc Get active live locations in a chat
get_live_locations(ChatId) ->
    gen_server:call(?MODULE, {get_live_locations, ChatId}).

%% @doc Get nearby users (within radius in meters)
get_nearby_users(UserId, Latitude, Longitude, RadiusMeters) ->
    gen_server:call(?MODULE, {get_nearby_users, UserId, Latitude, Longitude, RadiusMeters}).

%% @doc Clean up expired live locations
cleanup_expired_live_locations() ->
    gen_server:cast(?MODULE, cleanup_expired_live_locations).

%% ===================================================================
%% gen_server callbacks
%% ===================================================================

init([]) ->
    lager:info("Location Service started"),
    
    % Set up cleanup timer (every 5 minutes)
    {ok, Timer} = timer:apply_interval(300000, ?MODULE, cleanup_expired_live_locations, []),
    
    {ok, #state{cleanup_timer = Timer}}.

handle_call({share_location, ChatId, SenderId, Latitude, Longitude, Address}, _From, State) ->
    Result = do_share_location(ChatId, SenderId, Latitude, Longitude, Address),
    {reply, Result, State};

handle_call({share_live_location, ChatId, SenderId, Latitude, Longitude, Address, DurationMinutes}, _From, State) ->
    Result = do_share_live_location(ChatId, SenderId, Latitude, Longitude, Address, DurationMinutes),
    {reply, Result, State};

handle_call({update_live_location, LiveLocationId, Latitude, Longitude}, _From, State) ->
    Result = do_update_live_location(LiveLocationId, Latitude, Longitude),
    {reply, Result, State};

handle_call({stop_live_location, LiveLocationId, UserId}, _From, State) ->
    Result = do_stop_live_location(LiveLocationId, UserId),
    {reply, Result, State};

handle_call({get_location_message, MessageId}, _From, State) ->
    Result = do_get_location_message(MessageId),
    {reply, Result, State};

handle_call({get_live_locations, ChatId}, _From, State) ->
    Result = do_get_live_locations(ChatId),
    {reply, Result, State};

handle_call({get_nearby_users, UserId, Latitude, Longitude, RadiusMeters}, _From, State) ->
    Result = do_get_nearby_users(UserId, Latitude, Longitude, RadiusMeters),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(cleanup_expired_live_locations, State) ->
    do_cleanup_expired_live_locations(),
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

do_share_location(ChatId, SenderId, Latitude, Longitude, Address) ->
    % Create location data
    LocationData = #{
        latitude => Latitude,
        longitude => Longitude,
        address => Address,
        type => <<"static">>
    },
    
    % Send message with location content
    case aethertalk_message_router:send_message(SenderId, ChatId, #{
        content => jiffy:encode(LocationData),
        message_type => <<"location">>
    }) of
        {ok, Message} ->
            MessageId = maps:get(id, Message),
            
            % Store location details
            LocationId = aethertalk_utils:generate_uuid(),
            SQL = "INSERT INTO location_messages (id, message_id, latitude, longitude, address, location_type, created_at) 
                   VALUES ($1, $2, $3, $4, $5, 'static', NOW()) RETURNING created_at",
            
            case aethertalk_db:query(SQL, [LocationId, MessageId, Latitude, Longitude, Address]) of
                {ok, {_Columns, [{CreatedAt}]}} ->
                    LocationMessage = #{
                        id => LocationId,
                        message_id => MessageId,
                        latitude => Latitude,
                        longitude => Longitude,
                        address => Address,
                        location_type => <<"static">>,
                        created_at => CreatedAt
                    },
                    
                    % Notify about location share
                    notify_location_shared(ChatId, SenderId, LocationMessage),
                    {ok, LocationMessage};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_share_live_location(ChatId, SenderId, Latitude, Longitude, Address, DurationMinutes) ->
    % Create live location data
    ExpiresAt = calculate_expiry_time(DurationMinutes),
    LocationData = #{
        latitude => Latitude,
        longitude => Longitude,
        address => Address,
        type => <<"live">>,
        duration_minutes => DurationMinutes,
        expires_at => ExpiresAt
    },
    
    % Send message with live location content
    case aethertalk_message_router:send_message(SenderId, ChatId, #{
        content => jiffy:encode(LocationData),
        message_type => <<"location">>
    }) of
        {ok, Message} ->
            MessageId = maps:get(id, Message),
            
            % Store live location details
            LiveLocationId = aethertalk_utils:generate_uuid(),
            SQL = "INSERT INTO live_locations (id, message_id, user_id, chat_id, latitude, longitude, 
                                              address, expires_at, is_active, created_at) 
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8, TRUE, NOW()) RETURNING created_at",
            
            case aethertalk_db:query(SQL, [LiveLocationId, MessageId, SenderId, ChatId, 
                                          Latitude, Longitude, Address, ExpiresAt]) of
                {ok, {_Columns, [{CreatedAt}]}} ->
                    LiveLocation = #{
                        id => LiveLocationId,
                        message_id => MessageId,
                        user_id => SenderId,
                        chat_id => ChatId,
                        latitude => Latitude,
                        longitude => Longitude,
                        address => Address,
                        expires_at => ExpiresAt,
                        is_active => true,
                        created_at => CreatedAt,
                        duration_minutes => DurationMinutes
                    },
                    
                    % Notify about live location start
                    notify_live_location_started(ChatId, SenderId, LiveLocation),
                    {ok, LiveLocation};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_update_live_location(LiveLocationId, Latitude, Longitude) ->
    % Check if live location is still active
    CheckSQL = "SELECT user_id, chat_id, is_active, expires_at 
               FROM live_locations 
               WHERE id = $1",
    
    case aethertalk_db:query(CheckSQL, [LiveLocationId]) of
        {ok, {_Columns, [{UserId, ChatId, true, ExpiresAt}]}} ->
            Now = calendar:universal_time(),
            if ExpiresAt > Now ->
                % Update location coordinates
                SQL = "UPDATE live_locations 
                       SET latitude = $1, longitude = $2, updated_at = NOW() 
                       WHERE id = $3",
                
                case aethertalk_db:query(SQL, [Latitude, Longitude, LiveLocationId]) of
                    {ok, 1} ->
                        % Notify about location update
                        notify_live_location_updated(ChatId, UserId, LiveLocationId, Latitude, Longitude),
                        {ok, updated};
                    {ok, 0} ->
                        {error, not_found};
                    {error, Reason} ->
                        {error, Reason}
                end;
            true ->
                {error, expired}
            end;
        {ok, {_Columns, [{_, _, false, _}]}} ->
            {error, inactive};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_stop_live_location(LiveLocationId, UserId) ->
    % Check if user owns the live location
    CheckSQL = "SELECT user_id, chat_id FROM live_locations 
               WHERE id = $1 AND user_id = $2 AND is_active = TRUE",
    
    case aethertalk_db:query(CheckSQL, [LiveLocationId, UserId]) of
        {ok, {_Columns, [{UserId, ChatId}]}} ->
            % Stop live location
            SQL = "UPDATE live_locations 
                   SET is_active = FALSE, updated_at = NOW() 
                   WHERE id = $1",
            
            case aethertalk_db:query(SQL, [LiveLocationId]) of
                {ok, 1} ->
                    % Notify about live location stop
                    notify_live_location_stopped(ChatId, UserId, LiveLocationId),
                    ok;
                {ok, 0} ->
                    {error, not_found};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, {_Columns, []}} ->
            {error, not_found_or_not_owner};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_location_message(MessageId) ->
    SQL = "SELECT lm.id, lm.latitude, lm.longitude, lm.address, lm.location_type, lm.created_at,
                  m.sender_id, m.chat_id, m.created_at as message_created_at,
                  u.username, u.full_name, u.avatar_url
           FROM location_messages lm
           JOIN messages m ON lm.message_id = m.id
           JOIN users u ON m.sender_id = u.id
           WHERE lm.message_id = $1 AND m.is_deleted = FALSE",
    
    case aethertalk_db:query(SQL, [MessageId]) of
        {ok, {_Columns, [{Id, Latitude, Longitude, Address, LocationType, CreatedAt,
                         SenderId, ChatId, MessageCreatedAt, Username, FullName, AvatarUrl}]}} ->
            LocationMessage = #{
                id => Id,
                message_id => MessageId,
                latitude => Latitude,
                longitude => Longitude,
                address => Address,
                location_type => LocationType,
                created_at => CreatedAt,
                sender => #{
                    id => SenderId,
                    username => Username,
                    full_name => FullName,
                    avatar_url => AvatarUrl
                },
                chat_id => ChatId,
                message_created_at => MessageCreatedAt
            },
            {ok, LocationMessage};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_live_locations(ChatId) ->
    SQL = "SELECT ll.id, ll.message_id, ll.user_id, ll.latitude, ll.longitude, 
                  ll.address, ll.expires_at, ll.created_at, ll.updated_at,
                  u.username, u.full_name, u.avatar_url
           FROM live_locations ll
           JOIN users u ON ll.user_id = u.id
           WHERE ll.chat_id = $1 AND ll.is_active = TRUE AND ll.expires_at > NOW()
           ORDER BY ll.updated_at DESC",
    
    case aethertalk_db:query(SQL, [ChatId]) of
        {ok, {_Columns, Rows}} ->
            LiveLocations = lists:map(fun({Id, MessageId, UserId, Latitude, Longitude,
                                          Address, ExpiresAt, CreatedAt, UpdatedAt,
                                          Username, FullName, AvatarUrl}) ->
                #{
                    id => Id,
                    message_id => MessageId,
                    user_id => UserId,
                    latitude => Latitude,
                    longitude => Longitude,
                    address => Address,
                    expires_at => ExpiresAt,
                    created_at => CreatedAt,
                    updated_at => UpdatedAt,
                    user => #{
                        username => Username,
                        full_name => FullName,
                        avatar_url => AvatarUrl
                    }
                }
            end, Rows),
            {ok, LiveLocations};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_nearby_users(UserId, Latitude, Longitude, RadiusMeters) ->
    % Use Haversine formula to find nearby users
    % This is a simplified version - in production you'd use PostGIS
    SQL = "SELECT ll.user_id, ll.latitude, ll.longitude, ll.updated_at,
                  u.username, u.full_name, u.avatar_url,
                  (6371000 * acos(cos(radians($2)) * cos(radians(ll.latitude)) * 
                   cos(radians(ll.longitude) - radians($3)) + 
                   sin(radians($2)) * sin(radians(ll.latitude)))) AS distance
           FROM live_locations ll
           JOIN users u ON ll.user_id = u.id
           WHERE ll.user_id != $1 AND ll.is_active = TRUE AND ll.expires_at > NOW()
           HAVING distance <= $4
           ORDER BY distance",
    
    case aethertalk_db:query(SQL, [UserId, Latitude, Longitude, RadiusMeters]) of
        {ok, {_Columns, Rows}} ->
            NearbyUsers = lists:map(fun({NearbyUserId, NearbyLat, NearbyLng, UpdatedAt,
                                        Username, FullName, AvatarUrl, Distance}) ->
                #{
                    user_id => NearbyUserId,
                    latitude => NearbyLat,
                    longitude => NearbyLng,
                    updated_at => UpdatedAt,
                    distance_meters => round(Distance),
                    user => #{
                        username => Username,
                        full_name => FullName,
                        avatar_url => AvatarUrl
                    }
                }
            end, Rows),
            {ok, NearbyUsers};
        {error, Reason} ->
            {error, Reason}
    end.

do_cleanup_expired_live_locations() ->
    % Deactivate expired live locations
    SQL = "UPDATE live_locations 
           SET is_active = FALSE, updated_at = NOW() 
           WHERE is_active = TRUE AND expires_at <= NOW()",
    
    case aethertalk_db:query(SQL, []) of
        {ok, Count} ->
            lager:info("Deactivated ~p expired live locations", [Count]),
            {ok, Count};
        {error, Reason} ->
            lager:error("Failed to cleanup expired live locations: ~p", [Reason]),
            {error, Reason}
    end.

%% Helper functions

calculate_expiry_time(DurationMinutes) ->
    Now = calendar:universal_time(),
    NowSeconds = calendar:datetime_to_gregorian_seconds(Now),
    ExpirySeconds = NowSeconds + (DurationMinutes * 60),
    calendar:gregorian_seconds_to_datetime(ExpirySeconds).

%% Notification functions

notify_location_shared(ChatId, SenderId, LocationMessage) ->
    lager:info("Location shared in chat ~p by user ~p", [ChatId, SenderId]),
    spawn(fun() ->
        Notification = #{
            type => <<"location_shared">>,
            chat_id => ChatId,
            sender_id => SenderId,
            location => LocationMessage,
            timestamp => erlang:system_time(millisecond)
        },
        aethertalk_websocket_manager:broadcast_to_chat(ChatId, Notification)
    end).

notify_live_location_started(ChatId, SenderId, LiveLocation) ->
    lager:info("Live location started in chat ~p by user ~p", [ChatId, SenderId]),
    spawn(fun() ->
        Notification = #{
            type => <<"live_location_started">>,
            chat_id => ChatId,
            sender_id => SenderId,
            live_location => LiveLocation,
            timestamp => erlang:system_time(millisecond)
        },
        aethertalk_websocket_manager:broadcast_to_chat(ChatId, Notification)
    end).

notify_live_location_updated(ChatId, UserId, LiveLocationId, Latitude, Longitude) ->
    spawn(fun() ->
        Notification = #{
            type => <<"live_location_updated">>,
            chat_id => ChatId,
            user_id => UserId,
            live_location_id => LiveLocationId,
            latitude => Latitude,
            longitude => Longitude,
            timestamp => erlang:system_time(millisecond)
        },
        aethertalk_websocket_manager:broadcast_to_chat(ChatId, Notification)
    end).

notify_live_location_stopped(ChatId, UserId, LiveLocationId) ->
    lager:info("Live location stopped in chat ~p by user ~p", [ChatId, UserId]),
    spawn(fun() ->
        Notification = #{
            type => <<"live_location_stopped">>,
            chat_id => ChatId,
            user_id => UserId,
            live_location_id => LiveLocationId,
            timestamp => erlang:system_time(millisecond)
        },
        aethertalk_websocket_manager:broadcast_to_chat(ChatId, Notification)
    end).