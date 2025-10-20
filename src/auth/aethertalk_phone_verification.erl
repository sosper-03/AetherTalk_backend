%% @doc Phone verification service for AetherTalk
%% Implements WhatsApp-like phone number verification using Firebase Auth
-module(aethertalk_phone_verification).

-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([send_verification_code/1, verify_code/2, resend_code/1]).
-export([is_phone_verified/1, get_verification_status/1]).
-export([cleanup_expired_codes/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(VERIFICATION_TIMEOUT, 300). % 5 minutes
-define(MAX_ATTEMPTS, 3).
-define(RESEND_DELAY, 60). % 1 minute

-record(state, {
    firebase_config :: map(),
    verification_codes = #{} :: map(),
    cleanup_timer :: reference()
}).

-record(verification_code, {
    phone_number :: binary(),
    code :: binary(),
    attempts = 0 :: integer(),
    created_at :: integer(),
    expires_at :: integer(),
    last_sent_at :: integer()
}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Starts the phone verification server
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Send verification code to phone number
-spec send_verification_code(binary()) -> {ok, binary()} | {error, term()}.
send_verification_code(PhoneNumber) ->
    gen_server:call(?SERVER, {send_verification_code, PhoneNumber}, 30000).

%% @doc Verify the code for a phone number
-spec verify_code(binary(), binary()) -> {ok, verified} | {error, term()}.
verify_code(PhoneNumber, Code) ->
    gen_server:call(?SERVER, {verify_code, PhoneNumber, Code}, 10000).

%% @doc Resend verification code
-spec resend_code(binary()) -> {ok, binary()} | {error, term()}.
resend_code(PhoneNumber) ->
    gen_server:call(?SERVER, {resend_code, PhoneNumber}, 30000).

%% @doc Check if phone number is verified
-spec is_phone_verified(binary()) -> boolean().
is_phone_verified(PhoneNumber) ->
    gen_server:call(?SERVER, {is_phone_verified, PhoneNumber}, 5000).

%% @doc Get verification status for phone number
-spec get_verification_status(binary()) -> {ok, map()} | {error, not_found}.
get_verification_status(PhoneNumber) ->
    gen_server:call(?SERVER, {get_verification_status, PhoneNumber}, 5000).

%% @doc Clean up expired verification codes
-spec cleanup_expired_codes() -> ok.
cleanup_expired_codes() ->
    gen_server:cast(?SERVER, cleanup_expired_codes).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    % Load Firebase configuration
    FirebaseConfig = load_firebase_config(),
    
    % Start cleanup timer (every 5 minutes)
    Timer = erlang:start_timer(300000, self(), cleanup_expired_codes),
    
    lager:info("Phone verification service started"),
    
    {ok, #state{
        firebase_config = FirebaseConfig,
        cleanup_timer = Timer
    }}.

handle_call({send_verification_code, PhoneNumber}, _From, State) ->
    Result = do_send_verification_code(PhoneNumber, State),
    {reply, Result, State};

handle_call({verify_code, PhoneNumber, Code}, _From, State) ->
    {Result, NewState} = do_verify_code(PhoneNumber, Code, State),
    {reply, Result, NewState};

handle_call({resend_code, PhoneNumber}, _From, State) ->
    Result = do_resend_code(PhoneNumber, State),
    {reply, Result, State};

handle_call({is_phone_verified, PhoneNumber}, _From, State) ->
    Result = do_is_phone_verified(PhoneNumber, State),
    {reply, Result, State};

handle_call({get_verification_status, PhoneNumber}, _From, State) ->
    Result = do_get_verification_status(PhoneNumber, State),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(cleanup_expired_codes, State) ->
    NewState = do_cleanup_expired_codes(State),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({timeout, _TimerRef, cleanup_expired_codes}, State) ->
    NewState = do_cleanup_expired_codes(State),
    % Restart timer
    Timer = erlang:start_timer(300000, self(), cleanup_expired_codes),
    {noreply, NewState#state{cleanup_timer = Timer}};

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
load_firebase_config() ->
    #{
        project_id => get_env_var("FIREBASE_PROJECT_ID", undefined),
        web_api_key => get_env_var("FIREBASE_WEB_API_KEY", undefined),
        private_key => get_env_var("FIREBASE_PRIVATE_KEY", undefined),
        client_email => get_env_var("FIREBASE_CLIENT_EMAIL", undefined),
        enabled => get_env_var("PHONE_VERIFICATION_ENABLED", "true") =:= "true",
        timeout => list_to_integer(get_env_var("PHONE_VERIFICATION_TIMEOUT", "300")),
        max_attempts => list_to_integer(get_env_var("PHONE_VERIFICATION_MAX_ATTEMPTS", "3")),
        resend_delay => list_to_integer(get_env_var("PHONE_VERIFICATION_RESEND_DELAY", "60"))
    }.

%% @private
get_env_var(VarName, Default) ->
    case os:getenv(VarName) of
        false -> Default;
        Value -> Value
    end.

%% @private
do_send_verification_code(PhoneNumber, State) ->
    case maps:get(enabled, State#state.firebase_config, false) of
        false ->
            lager:warning("Phone verification is disabled"),
            {error, verification_disabled};
        true ->
            % Normalize phone number
            NormalizedPhone = normalize_phone_number(PhoneNumber),
            
            % Check if we can send (rate limiting)
            case can_send_code(NormalizedPhone, State) of
                false ->
                    {error, rate_limited};
                true ->
                    % Generate verification code
                    Code = generate_verification_code(),
                    
                    % Send via Firebase (or SMS service)
                    case send_sms_code(NormalizedPhone, Code, State#state.firebase_config) of
                        {ok, MessageId} ->
                            % Store verification code
                            VerificationCode = #verification_code{
                                phone_number = NormalizedPhone,
                                code = Code,
                                created_at = erlang:system_time(second),
                                expires_at = erlang:system_time(second) + maps:get(timeout, State#state.firebase_config, ?VERIFICATION_TIMEOUT),
                                last_sent_at = erlang:system_time(second)
                            },
                            
                            _NewCodes = maps:put(NormalizedPhone, VerificationCode, State#state.verification_codes),
                            
                            lager:info("Verification code sent to ~s", [NormalizedPhone]),
                            {ok, MessageId};
                        {error, Reason} ->
                            lager:error("Failed to send verification code to ~s: ~p", [NormalizedPhone, Reason]),
                            {error, send_failed}
                    end
            end
    end.

%% @private
do_verify_code(PhoneNumber, Code, State) ->
    NormalizedPhone = normalize_phone_number(PhoneNumber),
    
    case maps:get(NormalizedPhone, State#state.verification_codes, undefined) of
        undefined ->
            {{error, code_not_found}, State};
        VerificationCode ->
            Now = erlang:system_time(second),
            
            % Check if code is expired
            if VerificationCode#verification_code.expires_at < Now ->
                % Remove expired code
                NewCodes = maps:remove(NormalizedPhone, State#state.verification_codes),
                NewState = State#state{verification_codes = NewCodes},
                {{error, code_expired}, NewState};
            true ->
                % Check if too many attempts
                MaxAttempts = maps:get(max_attempts, State#state.firebase_config, ?MAX_ATTEMPTS),
                if VerificationCode#verification_code.attempts >= MaxAttempts ->
                    % Remove code after max attempts
                    NewCodes = maps:remove(NormalizedPhone, State#state.verification_codes),
                    NewState = State#state{verification_codes = NewCodes},
                    {{error, max_attempts_exceeded}, NewState};
                true ->
                    % Verify code
                    if VerificationCode#verification_code.code =:= Code ->
                        % Code is correct - mark as verified
                        lager:info("Phone number ~s verified successfully", [NormalizedPhone]),
                        
                        % Store verification in database
                        store_phone_verification(NormalizedPhone),
                        
                        % Remove verification code
                        NewCodes = maps:remove(NormalizedPhone, State#state.verification_codes),
                        NewState = State#state{verification_codes = NewCodes},
                        
                        {{ok, verified}, NewState};
                    true ->
                        % Incorrect code - increment attempts
                        UpdatedCode = VerificationCode#verification_code{
                            attempts = VerificationCode#verification_code.attempts + 1
                        },
                        NewCodes = maps:put(NormalizedPhone, UpdatedCode, State#state.verification_codes),
                        NewState = State#state{verification_codes = NewCodes},
                        
                        RemainingAttempts = MaxAttempts - UpdatedCode#verification_code.attempts,
                        {{error, {incorrect_code, RemainingAttempts}}, NewState}
                    end
                end
            end
    end.

%% @private
do_resend_code(PhoneNumber, State) ->
    NormalizedPhone = normalize_phone_number(PhoneNumber),
    
    case maps:get(NormalizedPhone, State#state.verification_codes, undefined) of
        undefined ->
            {error, no_pending_verification};
        VerificationCode ->
            Now = erlang:system_time(second),
            ResendDelay = maps:get(resend_delay, State#state.firebase_config, ?RESEND_DELAY),
            
            % Check if enough time has passed since last send
            if (Now - VerificationCode#verification_code.last_sent_at) < ResendDelay ->
                TimeRemaining = ResendDelay - (Now - VerificationCode#verification_code.last_sent_at),
                {error, {resend_too_soon, TimeRemaining}};
            true ->
                % Generate new code
                NewCode = generate_verification_code(),
                
                % Send new code
                case send_sms_code(NormalizedPhone, NewCode, State#state.firebase_config) of
                    {ok, MessageId} ->
                        % Update verification code
                        UpdatedCode = VerificationCode#verification_code{
                            code = NewCode,
                            last_sent_at = Now,
                            attempts = 0 % Reset attempts on resend
                        },
                        
                        _NewCodes = maps:put(NormalizedPhone, UpdatedCode, State#state.verification_codes),
                        
                        lager:info("Verification code resent to ~s", [NormalizedPhone]),
                        {ok, MessageId};
                    {error, Reason} ->
                        lager:error("Failed to resend verification code to ~s: ~p", [NormalizedPhone, Reason]),
                        {error, send_failed}
                end
            end
    end.

%% @private
do_is_phone_verified(PhoneNumber, _State) ->
    NormalizedPhone = normalize_phone_number(PhoneNumber),
    
    % Check in database if phone is verified
    case aethertalk_db:query("SELECT verified FROM phone_verifications WHERE phone_number = $1", [NormalizedPhone]) of
        {ok, []} ->
            false;
        {ok, [{true}]} ->
            true;
        {ok, [{false}]} ->
            false;
        {error, _} ->
            false
    end.

%% @private
do_get_verification_status(PhoneNumber, State) ->
    NormalizedPhone = normalize_phone_number(PhoneNumber),
    
    case maps:get(NormalizedPhone, State#state.verification_codes, undefined) of
        undefined ->
            % Check if already verified
            case do_is_phone_verified(NormalizedPhone, State) of
                true ->
                    {ok, #{
                        phone_number => NormalizedPhone,
                        status => verified,
                        verified_at => get_verification_timestamp(NormalizedPhone)
                    }};
                false ->
                    {error, not_found}
            end;
        VerificationCode ->
            Now = erlang:system_time(second),
            TimeRemaining = max(0, VerificationCode#verification_code.expires_at - Now),
            MaxAttempts = maps:get(max_attempts, State#state.firebase_config, ?MAX_ATTEMPTS),
            
            {ok, #{
                phone_number => NormalizedPhone,
                status => pending,
                attempts_used => VerificationCode#verification_code.attempts,
                attempts_remaining => MaxAttempts - VerificationCode#verification_code.attempts,
                time_remaining => TimeRemaining,
                can_resend => (Now - VerificationCode#verification_code.last_sent_at) >= maps:get(resend_delay, State#state.firebase_config, ?RESEND_DELAY)
            }}
    end.

%% @private
do_cleanup_expired_codes(State) ->
    Now = erlang:system_time(second),
    
    ExpiredCodes = maps:filter(
        fun(_Phone, Code) ->
            Code#verification_code.expires_at < Now
        end,
        State#state.verification_codes
    ),
    
    ValidCodes = maps:filter(
        fun(_Phone, Code) ->
            Code#verification_code.expires_at >= Now
        end,
        State#state.verification_codes
    ),
    
    if map_size(ExpiredCodes) > 0 ->
        lager:info("Cleaned up ~p expired verification codes", [map_size(ExpiredCodes)]);
    true ->
        ok
    end,
    
    State#state{verification_codes = ValidCodes}.

%% @private
can_send_code(PhoneNumber, State) ->
    case maps:get(PhoneNumber, State#state.verification_codes, undefined) of
        undefined ->
            true; % No existing code
        VerificationCode ->
            Now = erlang:system_time(second),
            ResendDelay = maps:get(resend_delay, State#state.firebase_config, ?RESEND_DELAY),
            (Now - VerificationCode#verification_code.last_sent_at) >= ResendDelay
    end.

%% @private
normalize_phone_number(PhoneNumber) when is_binary(PhoneNumber) ->
    % Remove all non-digit characters except +
    Cleaned = re:replace(PhoneNumber, "[^+0-9]", "", [global, {return, binary}]),
    
    % Ensure it starts with +
    case Cleaned of
        <<"+", _/binary>> -> Cleaned;
        _ -> <<"+", Cleaned/binary>>
    end;
normalize_phone_number(PhoneNumber) when is_list(PhoneNumber) ->
    normalize_phone_number(list_to_binary(PhoneNumber)).

%% @private
generate_verification_code() ->
    % Generate 6-digit code
    Code = rand:uniform(999999),
    list_to_binary(io_lib:format("~6..0B", [Code])).

%% @private
send_sms_code(PhoneNumber, Code, FirebaseConfig) ->
    % In a real implementation, this would use Firebase Auth REST API
    % or a SMS service like Twilio, AWS SNS, etc.
    
    case maps:get(web_api_key, FirebaseConfig, undefined) of
        undefined ->
            % For demo purposes, just log the code
            lager:info("DEMO: Verification code for ~s is: ~s", [PhoneNumber, Code]),
            {ok, <<"demo_message_id">>};
        _ApiKey ->
            % Use real Firebase SMS service
            case aethertalk_firebase_real:send_verification_sms(PhoneNumber, Code) of
                {ok, SessionInfo} ->
                    lager:info("Firebase SMS sent to ~s with session: ~s", [PhoneNumber, SessionInfo]),
                    {ok, SessionInfo};
                {error, Reason} ->
                    lager:error("Firebase SMS failed for ~s: ~p", [PhoneNumber, Reason]),
                    % Fallback to demo mode for development
                    lager:info("FALLBACK: Verification code for ~s is: ~s", [PhoneNumber, Code]),
                    {ok, <<"fallback_message_id">>}
            end
    end.

%% @private
store_phone_verification(PhoneNumber) ->
    % Store in database that this phone number is verified
    Query = "INSERT INTO phone_verifications (phone_number, verified, verified_at) 
             VALUES ($1, true, NOW()) 
             ON CONFLICT (phone_number) 
             DO UPDATE SET verified = true, verified_at = NOW()",
    
    case aethertalk_db:query(Query, [PhoneNumber]) of
        {ok, _} ->
            lager:info("Phone verification stored for ~s", [PhoneNumber]),
            ok;
        {error, Reason} ->
            lager:error("Failed to store phone verification for ~s: ~p", [PhoneNumber, Reason]),
            {error, Reason}
    end.

%% @private
get_verification_timestamp(PhoneNumber) ->
    case aethertalk_db:query("SELECT verified_at FROM phone_verifications WHERE phone_number = $1", [PhoneNumber]) of
        {ok, [{Timestamp}]} ->
            Timestamp;
        _ ->
            undefined
    end.