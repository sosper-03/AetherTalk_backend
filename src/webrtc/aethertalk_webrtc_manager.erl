%%%-------------------------------------------------------------------
%%% @doc
%%% WebRTC Manager for AetherTalk
%%% Handles HD voice and video calling with STUN/TURN servers
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_webrtc_manager).
-behaviour(gen_server).

% OTP callbacks
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    initiate_call/4,
    answer_call/2,
    decline_call/2,
    end_call/2,
    get_call_status/1,
    join_group_call/2,
    leave_group_call/2,
    mute_audio/2,
    unmute_audio/2,
    enable_video/2,
    disable_video/2,
    get_ice_servers/0,
    handle_ice_candidate/3,
    handle_sdp_offer/3,
    handle_sdp_answer/3,
    get_active_calls/0,
    get_user_calls/1
]).

-include("aethertalk.hrl").

-record(state, {
    active_calls :: map(),
    ice_servers :: list()
}).

-record(call_info, {
    call_id :: binary(),
    type :: voice | video | group_voice | group_video,
    caller_id :: binary(),
    participants :: list(),
    status :: initiated | ringing | connected | ended,
    started_at :: integer(),
    ended_at :: integer() | undefined,
    metadata :: #{atom() => term()}
}).

-record(participant, {
    user_id :: binary(),
    audio_enabled :: boolean(),
    video_enabled :: boolean(),
    joined_at :: integer(),
    left_at :: integer() | undefined,
    connection_state :: new | connecting | connected | disconnected | failed | closed
}).

-record(ice_server, {
    urls :: [string()],
    username :: string() | undefined,
    credential :: string() | undefined
}).

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

initiate_call(CallerId, CalleeId, Type, Options) ->
    gen_server:call(?MODULE, {initiate_call, CallerId, CalleeId, Type, Options}).

answer_call(CallId, UserId) ->
    gen_server:call(?MODULE, {answer_call, CallId, UserId}).

decline_call(CallId, UserId) ->
    gen_server:call(?MODULE, {decline_call, CallId, UserId}).

end_call(CallId, UserId) ->
    gen_server:call(?MODULE, {end_call, CallId, UserId}).

get_call_status(CallId) ->
    gen_server:call(?MODULE, {get_call_status, CallId}).

join_group_call(CallId, UserId) ->
    gen_server:call(?MODULE, {join_group_call, CallId, UserId}).

leave_group_call(CallId, UserId) ->
    gen_server:call(?MODULE, {leave_group_call, CallId, UserId}).

mute_audio(CallId, UserId) ->
    gen_server:call(?MODULE, {mute_audio, CallId, UserId}).

unmute_audio(CallId, UserId) ->
    gen_server:call(?MODULE, {unmute_audio, CallId, UserId}).

enable_video(CallId, UserId) ->
    gen_server:call(?MODULE, {enable_video, CallId, UserId}).

disable_video(CallId, UserId) ->
    gen_server:call(?MODULE, {disable_video, CallId, UserId}).

get_ice_servers() ->
    gen_server:call(?MODULE, get_ice_servers).

handle_ice_candidate(CallId, UserId, Candidate) ->
    gen_server:cast(?MODULE, {ice_candidate, CallId, UserId, Candidate}).

handle_sdp_offer(CallId, UserId, Offer) ->
    gen_server:cast(?MODULE, {sdp_offer, CallId, UserId, Offer}).

handle_sdp_answer(CallId, UserId, Answer) ->
    gen_server:cast(?MODULE, {sdp_answer, CallId, UserId, Answer}).

get_active_calls() ->
    gen_server:call(?MODULE, get_active_calls).

get_user_calls(UserId) ->
    gen_server:call(?MODULE, {get_user_calls, UserId}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    % Initialize ICE servers configuration
    IceServers = get_ice_servers_config(),
    
    % Start call cleanup timer
    timer:send_interval(60000, cleanup_ended_calls), % Every minute
    
    io:format("WebRTC manager started with ~p ICE servers~n", [length(IceServers)]),
    {ok, #state{
        active_calls = #{},
        ice_servers = IceServers
    }}.

handle_call({initiate_call, CallerId, CalleeId, Type, Options}, _From, State) ->
    Result = do_initiate_call(CallerId, CalleeId, Type, Options, State),
    case Result of
        {ok, CallId, NewState} ->
            {reply, {ok, CallId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({answer_call, CallId, UserId}, _From, State) ->
    Result = do_answer_call(CallId, UserId, State),
    case Result of
        {ok, NewState} ->
            {reply, ok, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({decline_call, CallId, UserId}, _From, State) ->
    Result = do_decline_call(CallId, UserId, State),
    case Result of
        {ok, NewState} ->
            {reply, ok, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({end_call, CallId, UserId}, _From, State) ->
    Result = do_end_call(CallId, UserId, State),
    case Result of
        {ok, NewState} ->
            {reply, ok, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({get_call_status, CallId}, _From, State) ->
    Result = do_get_call_status(CallId, State),
    {reply, Result, State};

handle_call(get_ice_servers, _From, State) ->
    IceServersJson = format_ice_servers_for_client(State#state.ice_servers),
    {reply, {ok, IceServersJson}, State};

handle_call(get_active_calls, _From, State) ->
    ActiveCalls = maps:values(State#state.active_calls),
    CallSummaries = [format_call_summary(Call) || Call <- ActiveCalls],
    {reply, {ok, CallSummaries}, State};

handle_call({get_user_calls, UserId}, _From, State) ->
    UserCalls = get_user_active_calls(UserId, State),
    {reply, {ok, UserCalls}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({ice_candidate, CallId, UserId, Candidate}, State) ->
    % Forward ICE candidate to other participants
    broadcast_to_call_participants(CallId, UserId, {ice_candidate, UserId, Candidate}, State),
    {noreply, State};

handle_cast({sdp_offer, CallId, UserId, Offer}, State) ->
    % Forward SDP offer to other participants
    broadcast_to_call_participants(CallId, UserId, {sdp_offer, UserId, Offer}, State),
    {noreply, State};

handle_cast({sdp_answer, CallId, UserId, Answer}, State) ->
    % Forward SDP answer to other participants
    broadcast_to_call_participants(CallId, UserId, {sdp_answer, UserId, Answer}, State),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(cleanup_ended_calls, State) ->
    NewState = do_cleanup_ended_calls(State),
    {noreply, NewState};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

do_initiate_call(CallerId, CalleeId, Type, Options, State) ->
    CallId = generate_call_id(),
    Now = erlang:system_time(millisecond),
    
    % Create initial participant for caller
    CallerParticipant = #participant{
        user_id = CallerId,
        audio_enabled = true,
        video_enabled = (Type =:= video orelse Type =:= group_video),
        joined_at = Now,
        connection_state = new
    },
    
    % Create call info
    CallInfo = #call_info{
        call_id = CallId,
        type = Type,
        caller_id = CallerId,
        participants = [CallerParticipant],
        status = initiated,
        started_at = Now,
        metadata = Options
    },
    
    % Store call in database
    case store_call_in_db(CallInfo) of
        ok ->
            % Add to active calls
            NewActiveCalls = maps:put(CallId, CallInfo, State#state.active_calls),
            NewState = State#state{active_calls = NewActiveCalls},
            
            % Notify callee(s)
            case Type of
                voice -> notify_incoming_call(CalleeId, CallId, voice, CallerId);
                video -> notify_incoming_call(CalleeId, CallId, video, CallerId);
                group_voice -> notify_group_call(maps:get(participants, Options, []), CallId, group_voice, CallerId);
                group_video -> notify_group_call(maps:get(participants, Options, []), CallId, group_video, CallerId)
            end,
            
            io:format("Initiated ~p call ~s from ~s~n", [Type, CallId, CallerId]),
            {ok, CallId, NewState};
        {error, Reason} ->
            io:format("Failed to store call in database: ~p~n", [Reason]),
            {error, database_error}
    end.

do_answer_call(CallId, UserId, State) ->
    case maps:get(CallId, State#state.active_calls, undefined) of
        undefined ->
            {error, call_not_found};
        CallInfo ->
            % Update call status
            Now = erlang:system_time(millisecond),
            
            % Add answering user as participant
            NewParticipant = #participant{
                user_id = UserId,
                audio_enabled = true,
                video_enabled = (CallInfo#call_info.type =:= video orelse CallInfo#call_info.type =:= group_video),
                joined_at = Now,
                connection_state = connecting
            },
            
            UpdatedParticipants = [NewParticipant | CallInfo#call_info.participants],
            UpdatedCallInfo = CallInfo#call_info{
                participants = UpdatedParticipants,
                status = connected
            },
            
            % Update in database
            update_call_in_db(UpdatedCallInfo),
            
            % Update state
            NewActiveCalls = maps:put(CallId, UpdatedCallInfo, State#state.active_calls),
            NewState = State#state{active_calls = NewActiveCalls},
            
            % Notify all participants that call was answered
            broadcast_to_call_participants(CallId, UserId, {call_answered, UserId}, State),
            
            io:format("User ~s answered call ~s~n", [UserId, CallId]),
            {ok, NewState}
    end.

do_decline_call(CallId, UserId, State) ->
    case maps:get(CallId, State#state.active_calls, undefined) of
        undefined ->
            {error, call_not_found};
        CallInfo ->
            % Update call status to ended
            UpdatedCallInfo = CallInfo#call_info{
                status = ended,
                ended_at = erlang:system_time(millisecond)
            },
            
            % Update in database
            update_call_in_db(UpdatedCallInfo),
            
            % Remove from active calls
            NewActiveCalls = maps:remove(CallId, State#state.active_calls),
            NewState = State#state{active_calls = NewActiveCalls},
            
            % Notify caller that call was declined
            notify_call_declined(CallInfo#call_info.caller_id, CallId, UserId),
            
            io:format("User ~s declined call ~s~n", [UserId, CallId]),
            {ok, NewState}
    end.

do_end_call(CallId, UserId, State) ->
    case maps:get(CallId, State#state.active_calls, undefined) of
        undefined ->
            {error, call_not_found};
        CallInfo ->
            Now = erlang:system_time(millisecond),
            
            % Update call status
            UpdatedCallInfo = CallInfo#call_info{
                status = ended,
                ended_at = Now
            },
            
            % Update in database
            update_call_in_db(UpdatedCallInfo),
            
            % Remove from active calls
            NewActiveCalls = maps:remove(CallId, State#state.active_calls),
            NewState = State#state{active_calls = NewActiveCalls},
            
            % Notify all participants that call ended
            broadcast_to_call_participants(CallId, UserId, {call_ended, UserId}, State),
            
            % Calculate call duration and log
            Duration = Now - CallInfo#call_info.started_at,
            io:format("Call ~s ended by ~s, duration: ~p ms~n", [CallId, UserId, Duration]),
            
            {ok, NewState}
    end.

do_get_call_status(CallId, State) ->
    case maps:get(CallId, State#state.active_calls, undefined) of
        undefined ->
            % Check database for historical call
            case get_call_from_db(CallId) of
                {ok, CallInfo} -> {ok, format_call_info(CallInfo)};
                {error, not_found} -> {error, call_not_found}
            end;
        CallInfo ->
            {ok, format_call_info(CallInfo)}
    end.

do_cleanup_ended_calls(State) ->
    Now = erlang:system_time(millisecond),
    Cutoff = Now - (5 * 60 * 1000), % 5 minutes ago
    
    % Remove calls that ended more than 5 minutes ago
    NewActiveCalls = maps:filter(fun(_CallId, CallInfo) ->
        case CallInfo#call_info.status of
            ended ->
                case CallInfo#call_info.ended_at of
                    undefined -> true; % Keep if no end time
                    EndTime -> EndTime > Cutoff
                end;
            _ -> true % Keep active calls
        end
    end, State#state.active_calls),
    
    RemovedCount = maps:size(State#state.active_calls) - maps:size(NewActiveCalls),
    if
        RemovedCount > 0 ->
            io:format("Cleaned up ~p ended calls~n", [RemovedCount]);
        true -> ok
    end,
    
    State#state{active_calls = NewActiveCalls}.

%% Helper functions

broadcast_to_call_participants(CallId, ExcludeUserId, Message, State) ->
    case maps:get(CallId, State#state.active_calls, undefined) of
        undefined -> ok;
        CallInfo ->
            Participants = [P#participant.user_id || P <- CallInfo#call_info.participants, 
                           P#participant.user_id =/= ExcludeUserId,
                           P#participant.left_at =:= undefined],
            
            lists:foreach(fun(UserId) ->
                % Would send via WebSocket - simplified for now
                io:format("Sending message to user ~s: ~p~n", [UserId, Message])
            end, Participants)
    end.

get_user_active_calls(UserId, State) ->
    UserCalls = maps:fold(fun(_CallId, CallInfo, Acc) ->
        IsParticipant = lists:any(fun(P) -> 
            P#participant.user_id =:= UserId andalso P#participant.left_at =:= undefined
        end, CallInfo#call_info.participants),
        
        case IsParticipant of
            true -> [format_call_summary(CallInfo) | Acc];
            false -> Acc
        end
    end, [], State#state.active_calls),
    
    UserCalls.

format_call_info(CallInfo) ->
    #{
        call_id => CallInfo#call_info.call_id,
        type => CallInfo#call_info.type,
        caller_id => CallInfo#call_info.caller_id,
        status => CallInfo#call_info.status,
        started_at => CallInfo#call_info.started_at,
        ended_at => CallInfo#call_info.ended_at,
        participants => [format_participant(P) || P <- CallInfo#call_info.participants]
    }.

format_participant(Participant) ->
    #{
        user_id => Participant#participant.user_id,
        audio_enabled => Participant#participant.audio_enabled,
        video_enabled => Participant#participant.video_enabled,
        joined_at => Participant#participant.joined_at,
        left_at => Participant#participant.left_at,
        connection_state => Participant#participant.connection_state
    }.

format_call_summary(CallInfo) ->
    #{
        call_id => CallInfo#call_info.call_id,
        type => CallInfo#call_info.type,
        caller_id => CallInfo#call_info.caller_id,
        status => CallInfo#call_info.status,
        participant_count => length([P || P <- CallInfo#call_info.participants, P#participant.left_at =:= undefined]),
        started_at => CallInfo#call_info.started_at
    }.

format_ice_servers_for_client(IceServers) ->
    [#{
        urls => Server#ice_server.urls,
        username => Server#ice_server.username,
        credential => Server#ice_server.credential
    } || Server <- IceServers].

generate_call_id() ->
    uuid:uuid4().

get_ice_servers_config() ->
    % Default ICE servers configuration
    [
        #ice_server{
            urls = ["stun:stun.l.google.com:19302"],
            username = undefined,
            credential = undefined
        },
        #ice_server{
            urls = ["stun:stun1.l.google.com:19302"],
            username = undefined,
            credential = undefined
        }
    ].

notify_incoming_call(CalleeId, CallId, Type, CallerId) ->
    _Message = #{
        type => incoming_call,
        call_id => CallId,
        call_type => Type,
        caller_id => CallerId,
        timestamp => erlang:system_time(millisecond)
    },
    io:format("Notifying user ~s of incoming ~p call from ~s~n", [CalleeId, Type, CallerId]).

notify_group_call(Participants, CallId, Type, CallerId) ->
    _Message = #{
        type => group_call_invitation,
        call_id => CallId,
        call_type => Type,
        caller_id => CallerId,
        timestamp => erlang:system_time(millisecond)
    },
    lists:foreach(fun(UserId) ->
        io:format("Notifying user ~s of group ~p call from ~s~n", [UserId, Type, CallerId])
    end, Participants).

notify_call_declined(CallerId, CallId, DeclinedBy) ->
    _Message = #{
        type => call_declined,
        call_id => CallId,
        declined_by => DeclinedBy,
        timestamp => erlang:system_time(millisecond)
    },
    io:format("Notifying user ~s that call was declined by ~s~n", [CallerId, DeclinedBy]).

%% Database operations (simplified - would use actual database module)
store_call_in_db(CallInfo) ->
    % Store call information in database
    SQL = "INSERT INTO voice_calls (id, caller_id, status, started_at, call_type, metadata) 
           VALUES ($1, $2, $3, $4, $5, $6)",
    
    CallType = case CallInfo#call_info.type of
        voice -> <<"voice">>;
        video -> <<"video">>;
        group_voice -> <<"group_voice">>;
        group_video -> <<"group_video">>
    end,
    
    case aethertalk_db:query(SQL, [
        CallInfo#call_info.call_id,
        CallInfo#call_info.caller_id,
        atom_to_binary(CallInfo#call_info.status, utf8),
        CallInfo#call_info.started_at,
        CallType,
        jsx:encode(CallInfo#call_info.metadata)
    ]) of
        {ok, _} -> ok;
        {error, Reason} -> {error, Reason}
    end.

update_call_in_db(CallInfo) ->
    SQL = "UPDATE voice_calls SET status = $1, ended_at = $2, duration_seconds = $3 
           WHERE id = $4",
    
    Duration = case CallInfo#call_info.ended_at of
        undefined -> 0;
        EndTime -> (EndTime - CallInfo#call_info.started_at) div 1000
    end,
    
    aethertalk_db:query(SQL, [
        atom_to_binary(CallInfo#call_info.status, utf8),
        CallInfo#call_info.ended_at,
        Duration,
        CallInfo#call_info.call_id
    ]).

get_call_from_db(CallId) ->
    SQL = "SELECT id, caller_id, status, started_at, ended_at, call_type, metadata 
           FROM voice_calls WHERE id = $1",
    
    case aethertalk_db:query(SQL, [CallId]) of
        {ok, {_Columns, [{Id, CallerId, Status, StartedAt, EndedAt, CallType, Metadata}]}} ->
            CallInfo = #call_info{
                call_id = Id,
                caller_id = CallerId,
                status = binary_to_atom(Status, utf8),
                started_at = StartedAt,
                ended_at = EndedAt,
                type = binary_to_atom(CallType, utf8),
                participants = [],
                metadata = jsx:decode(Metadata, [return_maps])
            },
            {ok, CallInfo};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.