%% @doc Phone-based calling service for AetherTalk
%% Enables users to call each other using their registered phone numbers
-module(aethertalk_phone_calls).

-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([initiate_call/3, answer_call/2, reject_call/2, end_call/2]).
-export([find_user_by_phone/1, get_user_phone/1]).
-export([get_active_calls/1, get_call_history/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
    active_calls = #{} :: map(),
    call_history = [] :: list()
}).

-record(phone_call, {
    call_id :: binary(),
    caller_phone :: binary(),
    callee_phone :: binary(),
    caller_user_id :: binary(),
    callee_user_id :: binary(),
    call_type :: voice | video,
    status :: ringing | active | ended | rejected,
    started_at :: integer(),
    answered_at :: integer() | undefined,
    ended_at :: integer() | undefined,
    duration :: integer() | undefined
}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Starts the phone calls server
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Initiate a call to a phone number
-spec initiate_call(binary(), binary(), voice | video) -> {ok, binary()} | {error, term()}.
initiate_call(CallerUserId, CalleePhone, CallType) ->
    gen_server:call(?SERVER, {initiate_call, CallerUserId, CalleePhone, CallType}, 10000).

%% @doc Answer an incoming call
-spec answer_call(binary(), binary()) -> ok | {error, term()}.
answer_call(CallId, UserId) ->
    gen_server:call(?SERVER, {answer_call, CallId, UserId}, 5000).

%% @doc Reject an incoming call
-spec reject_call(binary(), binary()) -> ok | {error, term()}.
reject_call(CallId, UserId) ->
    gen_server:call(?SERVER, {reject_call, CallId, UserId}, 5000).

%% @doc End an active call
-spec end_call(binary(), binary()) -> ok | {error, term()}.
end_call(CallId, UserId) ->
    gen_server:call(?SERVER, {end_call, CallId, UserId}, 5000).

%% @doc Find user by phone number
-spec find_user_by_phone(binary()) -> {ok, binary()} | {error, not_found}.
find_user_by_phone(PhoneNumber) ->
    gen_server:call(?SERVER, {find_user_by_phone, PhoneNumber}, 5000).

%% @doc Get user's phone number
-spec get_user_phone(binary()) -> {ok, binary()} | {error, not_found}.
get_user_phone(UserId) ->
    gen_server:call(?SERVER, {get_user_phone, UserId}, 5000).

%% @doc Get active calls for a user
-spec get_active_calls(binary()) -> {ok, [map()]}.
get_active_calls(UserId) ->
    gen_server:call(?SERVER, {get_active_calls, UserId}, 5000).

%% @doc Get call history for a user
-spec get_call_history(binary(), integer()) -> {ok, [map()]}.
get_call_history(UserId, Limit) ->
    gen_server:call(?SERVER, {get_call_history, UserId, Limit}, 5000).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    lager:info("Phone calls service started"),
    {ok, #state{}}.

handle_call({initiate_call, CallerUserId, CalleePhone, CallType}, _From, State) ->
    {Result, NewState} = do_initiate_call(CallerUserId, CalleePhone, CallType, State),
    {reply, Result, NewState};

handle_call({answer_call, CallId, UserId}, _From, State) ->
    {Result, NewState} = do_answer_call(CallId, UserId, State),
    {reply, Result, NewState};

handle_call({reject_call, CallId, UserId}, _From, State) ->
    {Result, NewState} = do_reject_call(CallId, UserId, State),
    {reply, Result, NewState};

handle_call({end_call, CallId, UserId}, _From, State) ->
    {Result, NewState} = do_end_call(CallId, UserId, State),
    {reply, Result, NewState};

handle_call({find_user_by_phone, PhoneNumber}, _From, State) ->
    Result = do_find_user_by_phone(PhoneNumber),
    {reply, Result, State};

handle_call({get_user_phone, UserId}, _From, State) ->
    Result = do_get_user_phone(UserId),
    {reply, Result, State};

handle_call({get_active_calls, UserId}, _From, State) ->
    Result = do_get_active_calls(UserId, State),
    {reply, Result, State};

handle_call({get_call_history, UserId, Limit}, _From, State) ->
    Result = do_get_call_history(UserId, Limit),
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

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @private
do_initiate_call(CallerUserId, CalleePhone, CallType, State) ->
    try
        % Normalize phone number
        NormalizedPhone = aethertalk_phone_verification:normalize_phone_number(CalleePhone),
        
        % Find callee user by phone number
        case do_find_user_by_phone(NormalizedPhone) of
            {error, not_found} ->
                {{error, user_not_found}, State};
            {ok, CalleeUserId} ->
                % Check if callee is the same as caller
                if CallerUserId =:= CalleeUserId ->
                    {{error, cannot_call_self}, State};
                true ->
                    % Get caller's phone number
                    case do_get_user_phone(CallerUserId) of
                        {error, not_found} ->
                            {{error, caller_phone_not_found}, State};
                        {ok, CallerPhone} ->
                            % Generate call ID
                            CallId = generate_call_id(),
                            
                            % Create call record
                            Call = #phone_call{
                                call_id = CallId,
                                caller_phone = CallerPhone,
                                callee_phone = NormalizedPhone,
                                caller_user_id = CallerUserId,
                                callee_user_id = CalleeUserId,
                                call_type = CallType,
                                status = ringing,
                                started_at = erlang:system_time(second)
                            },
                            
                            % Store call in active calls
                            NewActiveCalls = maps:put(CallId, Call, State#state.active_calls),
                            NewState = State#state{active_calls = NewActiveCalls},
                            
                            % Store call in database
                            store_call_in_db(Call),
                            
                            % Notify callee about incoming call
                            notify_incoming_call(Call),
                            
                            % Start call timeout timer (30 seconds)
                            start_call_timeout_timer(CallId, 30000),
                            
                            lager:info("Call initiated: ~s calling ~s (Call ID: ~s)", 
                                      [CallerPhone, NormalizedPhone, CallId]),
                            
                            {{ok, CallId}, NewState}
                    end
                end
        end
    catch
        Error:Reason ->
            lager:error("Error initiating call: ~p:~p", [Error, Reason]),
            {{error, internal_error}, State}
    end.

%% @private
do_answer_call(CallId, UserId, State) ->
    case maps:get(CallId, State#state.active_calls, undefined) of
        undefined ->
            {{error, call_not_found}, State};
        Call ->
            % Check if user is the callee
            if Call#phone_call.callee_user_id =/= UserId ->
                {{error, not_authorized}, State};
            true ->
                % Update call status
                UpdatedCall = Call#phone_call{
                    status = active,
                    answered_at = erlang:system_time(second)
                },
                
                NewActiveCalls = maps:put(CallId, UpdatedCall, State#state.active_calls),
                NewState = State#state{active_calls = NewActiveCalls},
                
                % Update call in database
                update_call_in_db(UpdatedCall),
                
                % Notify caller that call was answered
                notify_call_answered(UpdatedCall),
                
                % Start WebRTC signaling
                start_webrtc_signaling(UpdatedCall),
                
                lager:info("Call answered: ~s (Call ID: ~s)", 
                          [Call#phone_call.callee_phone, CallId]),
                
                {ok, NewState}
            end
    end.

%% @private
do_reject_call(CallId, UserId, State) ->
    case maps:get(CallId, State#state.active_calls, undefined) of
        undefined ->
            {{error, call_not_found}, State};
        Call ->
            % Check if user is the callee
            if Call#phone_call.callee_user_id =/= UserId ->
                {{error, not_authorized}, State};
            true ->
                % Update call status
                UpdatedCall = Call#phone_call{
                    status = rejected,
                    ended_at = erlang:system_time(second)
                },
                
                % Remove from active calls
                NewActiveCalls = maps:remove(CallId, State#state.active_calls),
                NewState = State#state{active_calls = NewActiveCalls},
                
                % Update call in database
                update_call_in_db(UpdatedCall),
                
                % Notify caller that call was rejected
                notify_call_rejected(UpdatedCall),
                
                lager:info("Call rejected: ~s (Call ID: ~s)", 
                          [Call#phone_call.callee_phone, CallId]),
                
                {ok, NewState}
            end
    end.

%% @private
do_end_call(CallId, UserId, State) ->
    case maps:get(CallId, State#state.active_calls, undefined) of
        undefined ->
            {{error, call_not_found}, State};
        Call ->
            % Check if user is participant in the call
            if Call#phone_call.caller_user_id =/= UserId andalso 
               Call#phone_call.callee_user_id =/= UserId ->
                {{error, not_authorized}, State};
            true ->
                Now = erlang:system_time(second),
                Duration = case Call#phone_call.answered_at of
                    undefined -> 0;
                    AnsweredAt -> Now - AnsweredAt
                end,
                
                % Update call status
                UpdatedCall = Call#phone_call{
                    status = ended,
                    ended_at = Now,
                    duration = Duration
                },
                
                % Remove from active calls
                NewActiveCalls = maps:remove(CallId, State#state.active_calls),
                NewState = State#state{active_calls = NewActiveCalls},
                
                % Update call in database
                update_call_in_db(UpdatedCall),
                
                % Notify other participant that call ended
                notify_call_ended(UpdatedCall, UserId),
                
                lager:info("Call ended: ~s (Call ID: ~s, Duration: ~p seconds)", 
                          [Call#phone_call.caller_phone, CallId, Duration]),
                
                {ok, NewState}
            end
    end.

%% @private
do_find_user_by_phone(PhoneNumber) ->
    NormalizedPhone = aethertalk_phone_verification:normalize_phone_number(PhoneNumber),
    
    Query = "SELECT user_id FROM users WHERE phone_number = $1 AND phone_verified = true",
    case aethertalk_db:query(Query, [NormalizedPhone]) of
        {ok, []} ->
            {error, not_found};
        {ok, [{UserId}]} ->
            {ok, UserId};
        {error, Reason} ->
            lager:error("Database error finding user by phone ~s: ~p", [NormalizedPhone, Reason]),
            {error, database_error}
    end.

%% @private
do_get_user_phone(UserId) ->
    Query = "SELECT phone_number FROM users WHERE user_id = $1",
    case aethertalk_db:query(Query, [UserId]) of
        {ok, []} ->
            {error, not_found};
        {ok, [{PhoneNumber}]} ->
            {ok, PhoneNumber};
        {error, Reason} ->
            lager:error("Database error getting phone for user ~s: ~p", [UserId, Reason]),
            {error, database_error}
    end.

%% @private
do_get_active_calls(UserId, State) ->
    ActiveCalls = maps:fold(
        fun(_CallId, Call, Acc) ->
            if Call#phone_call.caller_user_id =:= UserId orelse 
               Call#phone_call.callee_user_id =:= UserId ->
                [call_to_map(Call) | Acc];
            true ->
                Acc
            end
        end,
        [],
        State#state.active_calls
    ),
    {ok, ActiveCalls}.

%% @private
do_get_call_history(UserId, Limit) ->
    Query = "SELECT call_id, caller_phone, callee_phone, call_type, status, 
                    started_at, answered_at, ended_at, duration 
             FROM phone_calls 
             WHERE caller_user_id = $1 OR callee_user_id = $1 
             ORDER BY started_at DESC 
             LIMIT $2",
    
    case aethertalk_db:query(Query, [UserId, Limit]) of
        {ok, Rows} ->
            CallHistory = lists:map(fun row_to_call_map/1, Rows),
            {ok, CallHistory};
        {error, Reason} ->
            lager:error("Database error getting call history for user ~s: ~p", [UserId, Reason]),
            {ok, []}
    end.

%% @private
generate_call_id() ->
    uuid:uuid4().

%% @private
store_call_in_db(Call) ->
    Query = "INSERT INTO phone_calls (call_id, caller_phone, callee_phone, 
                                     caller_user_id, callee_user_id, call_type, 
                                     status, started_at) 
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    
    Params = [
        Call#phone_call.call_id,
        Call#phone_call.caller_phone,
        Call#phone_call.callee_phone,
        Call#phone_call.caller_user_id,
        Call#phone_call.callee_user_id,
        atom_to_binary(Call#phone_call.call_type, utf8),
        atom_to_binary(Call#phone_call.status, utf8),
        Call#phone_call.started_at
    ],
    
    case aethertalk_db:query(Query, Params) of
        {ok, _} ->
            ok;
        {error, Reason} ->
            lager:error("Failed to store call in database: ~p", [Reason])
    end.

%% @private
update_call_in_db(Call) ->
    Query = "UPDATE phone_calls 
             SET status = $1, answered_at = $2, ended_at = $3, duration = $4 
             WHERE call_id = $5",
    
    Params = [
        atom_to_binary(Call#phone_call.status, utf8),
        Call#phone_call.answered_at,
        Call#phone_call.ended_at,
        Call#phone_call.duration,
        Call#phone_call.call_id
    ],
    
    case aethertalk_db:query(Query, Params) of
        {ok, _} ->
            ok;
        {error, Reason} ->
            lager:error("Failed to update call in database: ~p", [Reason])
    end.

%% @private
notify_incoming_call(Call) ->
    % Send push notification and WebSocket message to callee
    CallData = #{
        call_id => Call#phone_call.call_id,
        caller_phone => Call#phone_call.caller_phone,
        call_type => Call#phone_call.call_type,
        status => ringing
    },
    
    % WebSocket notification
    aethertalk_websocket_manager:send_to_user(
        Call#phone_call.callee_user_id,
        #{
            type => incoming_call,
            data => CallData
        }
    ),
    
    % Push notification
    aethertalk_push_notifications:send_call_notification(
        Call#phone_call.callee_user_id,
        <<"Incoming call">>,
        <<"Call from ", (Call#phone_call.caller_phone)/binary>>,
        CallData
    ).

%% @private
notify_call_answered(Call) ->
    % Notify caller that call was answered
    aethertalk_websocket_manager:send_to_user(
        Call#phone_call.caller_user_id,
        #{
            type => call_answered,
            data => #{
                call_id => Call#phone_call.call_id,
                status => active
            }
        }
    ).

%% @private
notify_call_rejected(Call) ->
    % Notify caller that call was rejected
    aethertalk_websocket_manager:send_to_user(
        Call#phone_call.caller_user_id,
        #{
            type => call_rejected,
            data => #{
                call_id => Call#phone_call.call_id,
                status => rejected
            }
        }
    ).

%% @private
notify_call_ended(Call, EndedByUserId) ->
    % Notify the other participant
    OtherUserId = if 
        Call#phone_call.caller_user_id =:= EndedByUserId ->
            Call#phone_call.callee_user_id;
        true ->
            Call#phone_call.caller_user_id
    end,
    
    aethertalk_websocket_manager:send_to_user(
        OtherUserId,
        #{
            type => call_ended,
            data => #{
                call_id => Call#phone_call.call_id,
                status => ended,
                duration => Call#phone_call.duration
            }
        }
    ).

%% @private
start_webrtc_signaling(Call) ->
    % Initialize WebRTC signaling for the call
    aethertalk_webrtc_manager:start_call_signaling(
        Call#phone_call.call_id,
        Call#phone_call.caller_user_id,
        Call#phone_call.callee_user_id,
        Call#phone_call.call_type
    ).

%% @private
start_call_timeout_timer(CallId, Timeout) ->
    % Start timer to automatically end call if not answered
    erlang:send_after(Timeout, self(), {call_timeout, CallId}).

%% @private
call_to_map(Call) ->
    #{
        call_id => Call#phone_call.call_id,
        caller_phone => Call#phone_call.caller_phone,
        callee_phone => Call#phone_call.callee_phone,
        caller_user_id => Call#phone_call.caller_user_id,
        callee_user_id => Call#phone_call.callee_user_id,
        call_type => Call#phone_call.call_type,
        status => Call#phone_call.status,
        started_at => Call#phone_call.started_at,
        answered_at => Call#phone_call.answered_at,
        ended_at => Call#phone_call.ended_at,
        duration => Call#phone_call.duration
    }.

%% @private
row_to_call_map({CallId, CallerPhone, CalleePhone, CallType, Status, 
                 StartedAt, AnsweredAt, EndedAt, Duration}) ->
    #{
        call_id => CallId,
        caller_phone => CallerPhone,
        callee_phone => CalleePhone,
        call_type => binary_to_atom(CallType, utf8),
        status => binary_to_atom(Status, utf8),
        started_at => StartedAt,
        answered_at => AnsweredAt,
        ended_at => EndedAt,
        duration => Duration
    }.