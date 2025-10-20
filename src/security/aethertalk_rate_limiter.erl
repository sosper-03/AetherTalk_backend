%%%-------------------------------------------------------------------
%%% @doc
%%% Rate Limiting Service for AetherTalk
%%% Implements sliding window rate limiting with multiple strategies
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_rate_limiter).
-behaviour(gen_server).

% OTP callbacks
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    check_rate_limit/3,
    check_rate_limit/4,
    increment_counter/3,
    get_rate_limit_info/2,
    reset_rate_limit/2,
    set_custom_limit/4,
    get_blocked_users/0,
    cleanup_expired_entries/0,
    check_http_rate_limit/2,
    get_user_id_from_request/1,
    get_client_ip/1
]).

-include("aethertalk.hrl").

-record(state, {
    cleanup_timer :: timer:tref(),
    rate_limits :: ets:tab()
}).

%% Rate limit configurations (requests per time window)
-define(RATE_LIMITS, #{
    % Authentication limits
    login => #{limit => 5, window => 300},           % 5 attempts per 5 minutes
    register => #{limit => 3, window => 3600},       % 3 attempts per hour
    password_reset => #{limit => 3, window => 3600}, % 3 attempts per hour
    
    % Messaging limits
    send_message => #{limit => 100, window => 60},   % 100 messages per minute
    send_media => #{limit => 20, window => 60},      % 20 media files per minute
    create_group => #{limit => 5, window => 3600},   % 5 groups per hour
    
    % API limits
    api_call => #{limit => 1000, window => 3600},    % 1000 API calls per hour
    websocket_connect => #{limit => 10, window => 60}, % 10 connections per minute
    
    % Call limits
    voice_call => #{limit => 50, window => 3600},    % 50 calls per hour
    video_call => #{limit => 30, window => 3600},    % 30 video calls per hour
    
    % Advanced feature limits
    create_poll => #{limit => 10, window => 3600},   % 10 polls per hour
    share_location => #{limit => 20, window => 3600}, % 20 location shares per hour
    create_status => #{limit => 50, window => 86400}  % 50 status updates per day
}).

%% Cleanup interval (every 5 minutes)
-define(CLEANUP_INTERVAL, 300000).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Check if action is within rate limit
check_rate_limit(UserId, Action, ClientIP) ->
    gen_server:call(?MODULE, {check_rate_limit, UserId, Action, ClientIP}).

%% @doc Check rate limit with custom parameters
check_rate_limit(UserId, Action, ClientIP, CustomLimit) ->
    gen_server:call(?MODULE, {check_rate_limit, UserId, Action, ClientIP, CustomLimit}).

%% @doc Increment counter for an action
increment_counter(UserId, Action, ClientIP) ->
    gen_server:call(?MODULE, {increment_counter, UserId, Action, ClientIP}).

%% @doc Get rate limit information for user/action
get_rate_limit_info(UserId, Action) ->
    gen_server:call(?MODULE, {get_rate_limit_info, UserId, Action}).

%% @doc Reset rate limit for user/action
reset_rate_limit(UserId, Action) ->
    gen_server:call(?MODULE, {reset_rate_limit, UserId, Action}).

%% @doc Set custom rate limit for user/action
set_custom_limit(UserId, Action, Limit, Window) ->
    gen_server:call(?MODULE, {set_custom_limit, UserId, Action, Limit, Window}).

%% @doc Get list of currently blocked users
get_blocked_users() ->
    gen_server:call(?MODULE, get_blocked_users).

%% @doc Clean up expired rate limit entries
cleanup_expired_entries() ->
    gen_server:cast(?MODULE, cleanup_expired_entries).

%% ===================================================================
%% gen_server callbacks
%% ===================================================================

init([]) ->
    io:format("Rate Limiter started~n"),
    
    % Create ETS table for rate limiting data
    RateLimits = ets:new(rate_limits, [set, private, {keypos, 1}]),
    
    % Set up cleanup timer
    {ok, Timer} = timer:apply_interval(?CLEANUP_INTERVAL, ?MODULE, cleanup_expired_entries, []),
    
    {ok, #state{cleanup_timer = Timer, rate_limits = RateLimits}}.

handle_call({check_rate_limit, UserId, Action, ClientIP}, _From, State) ->
    Result = do_check_rate_limit(UserId, Action, ClientIP, State),
    {reply, Result, State};

handle_call({check_rate_limit, UserId, Action, ClientIP, CustomLimit}, _From, State) ->
    Result = do_check_rate_limit_custom(UserId, Action, ClientIP, CustomLimit, State),
    {reply, Result, State};

handle_call({increment_counter, UserId, Action, ClientIP}, _From, State) ->
    Result = do_increment_counter(UserId, Action, ClientIP, State),
    {reply, Result, State};

handle_call({get_rate_limit_info, UserId, Action}, _From, State) ->
    Result = do_get_rate_limit_info(UserId, Action, State),
    {reply, Result, State};

handle_call({reset_rate_limit, UserId, Action}, _From, State) ->
    Result = do_reset_rate_limit(UserId, Action, State),
    {reply, Result, State};

handle_call({set_custom_limit, UserId, Action, Limit, Window}, _From, State) ->
    Result = do_set_custom_limit(UserId, Action, Limit, Window, State),
    {reply, Result, State};

handle_call(get_blocked_users, _From, State) ->
    Result = do_get_blocked_users(State),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(cleanup_expired_entries, State) ->
    do_cleanup_expired_entries(State),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{cleanup_timer = Timer, rate_limits = RateLimits}) ->
    timer:cancel(Timer),
    ets:delete(RateLimits),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ===================================================================
%% Internal functions
%% ===================================================================

do_check_rate_limit(UserId, Action, ClientIP, State) ->
    case maps:get(Action, ?RATE_LIMITS, undefined) of
        undefined ->
            {error, unknown_action};
        #{limit := Limit, window := Window} ->
            check_limit(UserId, Action, ClientIP, Limit, Window, State)
    end.

do_check_rate_limit_custom(UserId, Action, ClientIP, #{limit := Limit, window := Window}, State) ->
    check_limit(UserId, Action, ClientIP, Limit, Window, State);
do_check_rate_limit_custom(_UserId, _Action, _ClientIP, _InvalidLimit, _State) ->
    {error, invalid_custom_limit}.

check_limit(UserId, Action, ClientIP, Limit, Window, #state{rate_limits = RateLimits}) ->
    Now = erlang:system_time(second),
    
    % Create keys for user-based and IP-based limiting
    UserKey = {user, UserId, Action},
    IPKey = {ip, ClientIP, Action},
    
    % Check both user and IP limits
    UserResult = check_single_limit(UserKey, Limit, Window, Now, RateLimits),
    IPResult = check_single_limit(IPKey, Limit * 2, Window, Now, RateLimits), % IP limit is 2x user limit
    
    case {UserResult, IPResult} of
        {{ok, UserInfo}, {ok, IPInfo}} ->
            {ok, #{
                user_limit => UserInfo,
                ip_limit => IPInfo,
                action => Action,
                limit => Limit,
                window => Window
            }};
        {{error, user_limit_exceeded}, _} ->
            log_rate_limit_violation(UserId, Action, ClientIP, user_limit),
            {error, user_limit_exceeded};
        {_, {error, ip_limit_exceeded}} ->
            log_rate_limit_violation(UserId, Action, ClientIP, ip_limit),
            {error, ip_limit_exceeded};
        {Error, _} ->
            Error
    end.

check_single_limit(Key, Limit, Window, Now, RateLimits) ->
    case ets:lookup(RateLimits, Key) of
        [] ->
            % First request
            Entry = {Key, [{Now, 1}], Now + Window},
            ets:insert(RateLimits, Entry),
            {ok, #{
                current_count => 1,
                limit => Limit,
                window_start => Now,
                window_end => Now + Window,
                remaining => Limit - 1
            }};
        [{Key, Requests, WindowEnd}] ->
            % Filter requests within current window
            WindowStart = Now - Window,
            ValidRequests = [{Time, Count} || {Time, Count} <- Requests, Time >= WindowStart],
            
            % Calculate current count
            CurrentCount = lists:sum([Count || {_Time, Count} <- ValidRequests]),
            
            if CurrentCount >= Limit ->
                {error, limit_exceeded};
            true ->
                % Add current request
                NewRequests = [{Now, 1} | ValidRequests],
                NewEntry = {Key, NewRequests, max(WindowEnd, Now + Window)},
                ets:insert(RateLimits, NewEntry),
                
                {ok, #{
                    current_count => CurrentCount + 1,
                    limit => Limit,
                    window_start => WindowStart,
                    window_end => Now + Window,
                    remaining => Limit - CurrentCount - 1
                }}
            end
    end.

do_increment_counter(UserId, Action, ClientIP, #state{rate_limits = RateLimits}) ->
    Now = erlang:system_time(second),
    UserKey = {user, UserId, Action},
    IPKey = {ip, ClientIP, Action},
    
    % Increment both user and IP counters
    increment_single_counter(UserKey, Now, RateLimits),
    increment_single_counter(IPKey, Now, RateLimits),
    
    {ok, incremented}.

increment_single_counter(Key, Now, RateLimits) ->
    case ets:lookup(RateLimits, Key) of
        [] ->
            Entry = {Key, [{Now, 1}], Now + 3600}, % Default 1 hour window
            ets:insert(RateLimits, Entry);
        [{Key, Requests, WindowEnd}] ->
            NewRequests = [{Now, 1} | Requests],
            NewEntry = {Key, NewRequests, WindowEnd},
            ets:insert(RateLimits, NewEntry)
    end.

do_get_rate_limit_info(UserId, Action, #state{rate_limits = RateLimits}) ->
    case maps:get(Action, ?RATE_LIMITS, undefined) of
        undefined ->
            {error, unknown_action};
        #{limit := Limit, window := Window} ->
            Now = erlang:system_time(second),
            UserKey = {user, UserId, Action},
            
            case ets:lookup(RateLimits, UserKey) of
                [] ->
                    {ok, #{
                        action => Action,
                        current_count => 0,
                        limit => Limit,
                        window => Window,
                        remaining => Limit,
                        reset_time => Now + Window
                    }};
                [{UserKey, Requests, WindowEnd}] ->
                    WindowStart = Now - Window,
                    ValidRequests = [{Time, Count} || {Time, Count} <- Requests, Time >= WindowStart],
                    CurrentCount = lists:sum([Count || {_Time, Count} <- ValidRequests]),
                    
                    {ok, #{
                        action => Action,
                        current_count => CurrentCount,
                        limit => Limit,
                        window => Window,
                        remaining => max(0, Limit - CurrentCount),
                        reset_time => WindowEnd
                    }}
            end
    end.

do_reset_rate_limit(UserId, Action, #state{rate_limits = RateLimits}) ->
    UserKey = {user, UserId, Action},
    ets:delete(RateLimits, UserKey),
    
    io:format("Reset rate limit for user ~p, action ~p~n", [UserId, Action]),
    {ok, reset}.

do_set_custom_limit(UserId, Action, Limit, Window, _State) ->
    % Store custom limit in database for persistence
    SQL = "INSERT INTO custom_rate_limits (user_id, action, limit_count, window_seconds, created_at) 
           VALUES ($1, $2, $3, $4, NOW())
           ON CONFLICT (user_id, action) 
           DO UPDATE SET limit_count = $3, window_seconds = $4, updated_at = NOW()
           RETURNING id, created_at",
    
    case aethertalk_db:query(SQL, [UserId, atom_to_binary(Action, utf8), Limit, Window]) of
        {ok, {_Columns, [{Id, CreatedAt}]}} ->
            io:format("Set custom rate limit for user ~p, action ~p: ~p/~ps~n", 
                      [UserId, Action, Limit, Window]),
            {ok, #{
                id => Id,
                user_id => UserId,
                action => Action,
                limit => Limit,
                window => Window,
                created_at => CreatedAt
            }};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_blocked_users(#state{rate_limits = RateLimits}) ->
    Now = erlang:system_time(second),
    AllEntries = ets:tab2list(RateLimits),
    
    BlockedUsers = lists:foldl(fun
        ({{user, UserId, Action}, Requests, _WindowEnd}, Acc) ->
            case maps:get(Action, ?RATE_LIMITS, undefined) of
                #{limit := Limit, window := Window} ->
                    WindowStart = Now - Window,
                    ValidRequests = [{Time, Count} || {Time, Count} <- Requests, Time >= WindowStart],
                    CurrentCount = lists:sum([Count || {_Time, Count} <- ValidRequests]),
                    
                    if CurrentCount >= Limit ->
                        [#{
                            user_id => UserId,
                            action => Action,
                            current_count => CurrentCount,
                            limit => Limit,
                            blocked_until => Now + Window
                        } | Acc];
                    true ->
                        Acc
                    end;
                undefined ->
                    Acc
            end;
        (_, Acc) ->
            Acc
    end, [], AllEntries),
    
    {ok, BlockedUsers}.

do_cleanup_expired_entries(#state{rate_limits = RateLimits}) ->
    Now = erlang:system_time(second),
    AllKeys = ets:select(RateLimits, [{{{'$1', '$2', '$3'}, '$4', '$5'}, 
                                      [{'<', '$5', Now}], 
                                      ['$1']}]),
    
    CleanedCount = length(AllKeys),
    lists:foreach(fun(Key) -> ets:delete(RateLimits, Key) end, AllKeys),
    
    if CleanedCount > 0 ->
        io:format("Cleaned up ~p expired rate limit entries~n", [CleanedCount]);
    true ->
        ok
    end.

%% Helper functions

log_rate_limit_violation(UserId, Action, ClientIP, LimitType) ->
    io:format("Rate limit violation - User: ~p, Action: ~p, IP: ~p, Type: ~p~n", 
                  [UserId, Action, ClientIP, LimitType]),
    
    % Store violation in database for analysis
    SQL = "INSERT INTO rate_limit_violations (user_id, action, client_ip, limit_type, created_at) 
           VALUES ($1, $2, $3, $4, NOW())",
    
    spawn(fun() ->
        aethertalk_db:query(SQL, [UserId, atom_to_binary(Action, utf8), 
                                 inet:ntoa(ClientIP), atom_to_binary(LimitType, utf8)])
    end).

%% Public helper functions for middleware

%% @doc Middleware function for HTTP requests
check_http_rate_limit(Req, Action) ->
    UserId = get_user_id_from_request(Req),
    ClientIP = get_client_ip(Req),
    
    case check_rate_limit(UserId, Action, ClientIP) of
        {ok, _Info} ->
            {ok, Req};
        {error, user_limit_exceeded} ->
            ErrorResp = jiffy:encode(#{
                error => <<"Rate limit exceeded">>,
                message => <<"Too many requests from user">>,
                retry_after => 60
            }),
            Req1 = cowboy_req:reply(429, 
                #{<<"content-type">> => <<"application/json">>,
                  <<"retry-after">> => <<"60">>}, 
                ErrorResp, Req),
            {error, Req1};
        {error, ip_limit_exceeded} ->
            ErrorResp = jiffy:encode(#{
                error => <<"Rate limit exceeded">>,
                message => <<"Too many requests from IP address">>,
                retry_after => 60
            }),
            Req1 = cowboy_req:reply(429, 
                #{<<"content-type">> => <<"application/json">>,
                  <<"retry-after">> => <<"60">>}, 
                ErrorResp, Req),
            {error, Req1}
    end.

get_user_id_from_request(Req) ->
    case cowboy_req:header(<<"authorization">>, Req) of
        undefined ->
            <<"anonymous">>;
        AuthHeader ->
            % Extract user ID from JWT token
            case aethertalk_auth:decode_token(AuthHeader) of
                {ok, #{user_id := UserId}} ->
                    UserId;
                _ ->
                    <<"anonymous">>
            end
    end.

get_client_ip(Req) ->
    % Check for X-Forwarded-For header first (for load balancers)
    case cowboy_req:header(<<"x-forwarded-for">>, Req) of
        undefined ->
            {IP, _Port} = cowboy_req:peer(Req),
            IP;
        ForwardedFor ->
            % Take the first IP from the comma-separated list
            FirstIP = hd(binary:split(ForwardedFor, <<",">>)),
            case inet:parse_address(binary_to_list(string:trim(FirstIP))) of
                {ok, IP} -> IP;
                {error, _} -> 
                    {IP, _Port} = cowboy_req:peer(Req),
                    IP
            end
    end.