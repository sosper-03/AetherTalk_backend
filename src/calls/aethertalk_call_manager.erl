%%%-------------------------------------------------------------------
%% @doc AetherTalk call management system
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_call_manager).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    initiate_call/3,
    join_call/2,
    leave_call/2,
    end_call/2,
    handle_signal/4,
    get_call_info/1,
    get_active_calls/1
]).

-include("aethertalk.hrl").

-record(state, {}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    lager:info("Call manager started"),
    {ok, #state{}}.

handle_call({initiate_call, InitiatorId, ChatId, CallType}, _From, State) ->
    Result = do_initiate_call(InitiatorId, ChatId, CallType),
    {reply, Result, State};

handle_call({join_call, CallId, UserId}, _From, State) ->
    Result = do_join_call(CallId, UserId),
    {reply, Result, State};

handle_call({leave_call, CallId, UserId}, _From, State) ->
    Result = do_leave_call(CallId, UserId),
    {reply, Result, State};

handle_call({end_call, CallId, UserId}, _From, State) ->
    Result = do_end_call(CallId, UserId),
    {reply, Result, State};

handle_call({handle_signal, CallId, UserId, SignalType, Signal}, _From, State) ->
    Result = do_handle_signal(CallId, UserId, SignalType, Signal),
    {reply, Result, State};

handle_call({get_call_info, CallId}, _From, State) ->
    Result = do_get_call_info(CallId),
    {reply, Result, State};

handle_call({get_active_calls, UserId}, _From, State) ->
    Result = do_get_active_calls(UserId),
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

initiate_call(InitiatorId, ChatId, CallType) ->
    gen_server:call(?MODULE, {initiate_call, InitiatorId, ChatId, CallType}).

join_call(CallId, UserId) ->
    gen_server:call(?MODULE, {join_call, CallId, UserId}).

leave_call(CallId, UserId) ->
    gen_server:call(?MODULE, {leave_call, CallId, UserId}).

end_call(CallId, UserId) ->
    gen_server:call(?MODULE, {end_call, CallId, UserId}).

handle_signal(CallId, UserId, SignalType, Signal) ->
    gen_server:call(?MODULE, {handle_signal, CallId, UserId, SignalType, Signal}).

get_call_info(CallId) ->
    gen_server:call(?MODULE, {get_call_info, CallId}).

get_active_calls(UserId) ->
    gen_server:call(?MODULE, {get_active_calls, UserId}).

%% Internal functions (stubs for now)

do_initiate_call(InitiatorId, ChatId, CallType) ->
    % Create call record
    SQL = "INSERT INTO calls (chat_id, initiator_id, call_type, status) 
           VALUES ($1, $2, $3, 'initiated') RETURNING id, started_at",
    case aethertalk_db:query(SQL, [ChatId, InitiatorId, CallType]) of
        {ok, {_Columns, [{CallId, StartedAt}]}} ->
            {ok, #{
                call_id => CallId,
                chat_id => ChatId,
                initiator_id => InitiatorId,
                call_type => CallType,
                status => initiated,
                started_at => StartedAt
            }};
        {error, Reason} ->
            {error, Reason}
    end.

do_join_call(CallId, UserId) ->
    % Add participant to call
    SQL = "INSERT INTO call_participants (call_id, user_id, status, joined_at) 
           VALUES ($1, $2, 'joined', NOW()) RETURNING id",
    case aethertalk_db:query(SQL, [CallId, UserId]) of
        {ok, {_Columns, [{ParticipantId}]}} ->
            {ok, #{participant_id => ParticipantId}};
        {error, Reason} ->
            {error, Reason}
    end.

do_leave_call(CallId, UserId) ->
    % Update participant status
    SQL = "UPDATE call_participants SET status = 'left', left_at = NOW() 
           WHERE call_id = $1 AND user_id = $2",
    case aethertalk_db:query(SQL, [CallId, UserId]) of
        {ok, 1} ->
            ok;
        {ok, 0} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_end_call(CallId, _UserId) ->
    % End the call
    SQL = "UPDATE calls SET status = 'ended', ended_at = NOW() WHERE id = $1",
    case aethertalk_db:query(SQL, [CallId]) of
        {ok, 1} ->
            ok;
        {ok, 0} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_handle_signal(CallId, UserId, SignalType, _Signal) ->
    % Handle WebRTC signaling (stub)
    lager:info("Handling signal ~p from user ~p for call ~p", [SignalType, UserId, CallId]),
    ok.

do_get_call_info(CallId) ->
    SQL = "SELECT id, chat_id, initiator_id, call_type, status, started_at, ended_at 
           FROM calls WHERE id = $1",
    case aethertalk_db:query(SQL, [CallId]) of
        {ok, {_Columns, []}} ->
            {error, not_found};
        {ok, {_Columns, [Row]}} ->
            {ok, row_to_call_map(Row)};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_active_calls(UserId) ->
    SQL = "SELECT DISTINCT c.id, c.chat_id, c.initiator_id, c.call_type, c.status, c.started_at
           FROM calls c
           JOIN call_participants cp ON c.id = cp.call_id
           WHERE (c.initiator_id = $1 OR cp.user_id = $1) AND c.status IN ('initiated', 'ringing', 'active')",
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, Rows}} ->
            Calls = [row_to_call_map(Row) || Row <- Rows],
            {ok, Calls};
        {error, Reason} ->
            {error, Reason}
    end.

row_to_call_map({Id, ChatId, InitiatorId, CallType, Status, StartedAt}) ->
    #{
        id => Id,
        chat_id => ChatId,
        initiator_id => InitiatorId,
        call_type => CallType,
        status => Status,
        started_at => StartedAt
    };
row_to_call_map({Id, ChatId, InitiatorId, CallType, Status, StartedAt, EndedAt}) ->
    #{
        id => Id,
        chat_id => ChatId,
        initiator_id => InitiatorId,
        call_type => CallType,
        status => Status,
        started_at => StartedAt,
        ended_at => EndedAt
    }.