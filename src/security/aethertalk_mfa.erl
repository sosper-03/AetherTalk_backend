%%%-------------------------------------------------------------------
%%% @doc
%%% Multi-Factor Authentication Service for AetherTalk
%%% Implements TOTP, SMS, and backup codes for enhanced security
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_mfa).
-behaviour(gen_server).

% OTP callbacks
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    enable_totp/1,
    verify_totp/2,
    disable_totp/2,
    generate_backup_codes/1,
    verify_backup_code/2,
    send_sms_code/1,
    verify_sms_code/2,
    get_mfa_status/1,
    require_mfa_setup/1,
    verify_mfa_challenge/3,
    cleanup_expired_sms_codes/0
]).

-include("aethertalk.hrl").

-record(state, {
    cleanup_timer :: timer:tref()
}).

%% TOTP configuration
-define(TOTP_WINDOW, 1).        % Allow 1 time step before/after
-define(TOTP_PERIOD, 30).       % 30 second periods
-define(TOTP_DIGITS, 6).        % 6 digit codes
-define(BACKUP_CODES_COUNT, 10). % Number of backup codes to generate

%% SMS code configuration
-define(SMS_CODE_LENGTH, 6).
-define(SMS_CODE_EXPIRY, 300).   % 5 minutes

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Enable TOTP for a user
enable_totp(UserId) ->
    gen_server:call(?MODULE, {enable_totp, UserId}).

%% @doc Verify TOTP code
verify_totp(UserId, Code) ->
    gen_server:call(?MODULE, {verify_totp, UserId, Code}).

%% @doc Disable TOTP for a user
disable_totp(UserId, Code) ->
    gen_server:call(?MODULE, {disable_totp, UserId, Code}).

%% @doc Generate backup codes for a user
generate_backup_codes(UserId) ->
    gen_server:call(?MODULE, {generate_backup_codes, UserId}).

%% @doc Verify backup code
verify_backup_code(UserId, Code) ->
    gen_server:call(?MODULE, {verify_backup_code, UserId, Code}).

%% @doc Send SMS verification code
send_sms_code(UserId) ->
    gen_server:call(?MODULE, {send_sms_code, UserId}).

%% @doc Verify SMS code
verify_sms_code(UserId, Code) ->
    gen_server:call(?MODULE, {verify_sms_code, UserId, Code}).

%% @doc Get MFA status for user
get_mfa_status(UserId) ->
    gen_server:call(?MODULE, {get_mfa_status, UserId}).

%% @doc Check if user needs to set up MFA
require_mfa_setup(UserId) ->
    gen_server:call(?MODULE, {require_mfa_setup, UserId}).

%% @doc Verify MFA challenge (any method)
verify_mfa_challenge(UserId, Method, Code) ->
    gen_server:call(?MODULE, {verify_mfa_challenge, UserId, Method, Code}).

%% ===================================================================
%% gen_server callbacks
%% ===================================================================

init([]) ->
    io:format("MFA service started~n"),
    
    % Set up cleanup timer for expired SMS codes
    {ok, Timer} = timer:apply_interval(300000, ?MODULE, cleanup_expired_sms_codes, []),
    
    {ok, #state{cleanup_timer = Timer}}.

handle_call({enable_totp, UserId}, _From, State) ->
    Result = do_enable_totp(UserId),
    {reply, Result, State};

handle_call({verify_totp, UserId, Code}, _From, State) ->
    Result = do_verify_totp(UserId, Code),
    {reply, Result, State};

handle_call({disable_totp, UserId, Code}, _From, State) ->
    Result = do_disable_totp(UserId, Code),
    {reply, Result, State};

handle_call({generate_backup_codes, UserId}, _From, State) ->
    Result = do_generate_backup_codes(UserId),
    {reply, Result, State};

handle_call({verify_backup_code, UserId, Code}, _From, State) ->
    Result = do_verify_backup_code(UserId, Code),
    {reply, Result, State};

handle_call({send_sms_code, UserId}, _From, State) ->
    Result = do_send_sms_code(UserId),
    {reply, Result, State};

handle_call({verify_sms_code, UserId, Code}, _From, State) ->
    Result = do_verify_sms_code(UserId, Code),
    {reply, Result, State};

handle_call({get_mfa_status, UserId}, _From, State) ->
    Result = do_get_mfa_status(UserId),
    {reply, Result, State};

handle_call({require_mfa_setup, UserId}, _From, State) ->
    Result = do_require_mfa_setup(UserId),
    {reply, Result, State};

handle_call({verify_mfa_challenge, UserId, Method, Code}, _From, State) ->
    Result = do_verify_mfa_challenge(UserId, Method, Code),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

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

do_enable_totp(UserId) ->
    % Generate TOTP secret
    Secret = crypto:strong_rand_bytes(20),
    Base32Secret = base32_encode(Secret),
    
    % Store secret in database
    SQL = "INSERT INTO user_mfa_settings (user_id, totp_secret, totp_enabled, created_at) 
           VALUES ($1, $2, FALSE, NOW())
           ON CONFLICT (user_id) 
           DO UPDATE SET totp_secret = $2, updated_at = NOW()
           RETURNING id",
    
    case aethertalk_db:query(SQL, [UserId, Secret]) of
        {ok, {_Columns, [{Id}]}} ->
            % Generate QR code data
            QRData = generate_qr_code_data(UserId, Base32Secret),
            
            {ok, #{
                id => Id,
                secret => Base32Secret,
                qr_code => QRData,
                backup_codes => []
            }};
        {error, Reason} ->
            {error, Reason}
    end.

do_verify_totp(UserId, Code) ->
    case get_totp_secret(UserId) of
        {ok, Secret} ->
            case verify_totp_code(Secret, Code) of
                true ->
                    % Enable TOTP if this is first successful verification
                    enable_totp_if_needed(UserId),
                    log_mfa_event(UserId, totp_verified, success),
                    {ok, verified};
                false ->
                    log_mfa_event(UserId, totp_verified, failed),
                    {error, invalid_code}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_disable_totp(UserId, Code) ->
    case do_verify_totp(UserId, Code) of
        {ok, verified} ->
            SQL = "UPDATE user_mfa_settings 
                   SET totp_enabled = FALSE, totp_secret = NULL, updated_at = NOW() 
                   WHERE user_id = $1",
            
            case aethertalk_db:query(SQL, [UserId]) of
                {ok, 1} ->
                    log_mfa_event(UserId, totp_disabled, success),
                    {ok, disabled};
                {ok, 0} ->
                    {error, not_found};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_generate_backup_codes(UserId) ->
    % Generate random backup codes
    BackupCodes = [generate_backup_code() || _ <- lists:seq(1, ?BACKUP_CODES_COUNT)],
    
    % Hash codes for storage
    HashedCodes = [crypto:hash(sha256, Code) || Code <- BackupCodes],
    
    % Store in database
    SQL = "UPDATE user_mfa_settings 
           SET backup_codes = $1, updated_at = NOW() 
           WHERE user_id = $2",
    
    case aethertalk_db:query(SQL, [jiffy:encode(HashedCodes), UserId]) of
        {ok, 1} ->
            log_mfa_event(UserId, backup_codes_generated, success),
            {ok, BackupCodes};
        {ok, 0} ->
            {error, user_not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_verify_backup_code(UserId, Code) ->
    case get_backup_codes(UserId) of
        {ok, HashedCodes} ->
            CodeHash = crypto:hash(sha256, Code),
            
            case lists:member(CodeHash, HashedCodes) of
                true ->
                    % Remove used code
                    RemainingCodes = lists:delete(CodeHash, HashedCodes),
                    update_backup_codes(UserId, RemainingCodes),
                    log_mfa_event(UserId, backup_code_used, success),
                    {ok, verified};
                false ->
                    log_mfa_event(UserId, backup_code_used, failed),
                    {error, invalid_code}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_send_sms_code(UserId) ->
    % Get user's phone number
    case get_user_phone(UserId) of
        {ok, PhoneNumber} ->
            % Generate SMS code
            Code = generate_sms_code(),
            ExpiresAt = erlang:system_time(second) + ?SMS_CODE_EXPIRY,
            
            % Store code in database
            SQL = "INSERT INTO sms_verification_codes (user_id, code, expires_at, created_at) 
                   VALUES ($1, $2, to_timestamp($3), NOW())
                   ON CONFLICT (user_id) 
                   DO UPDATE SET code = $2, expires_at = to_timestamp($3), 
                                 attempts = 0, updated_at = NOW()
                   RETURNING id",
            
            case aethertalk_db:query(SQL, [UserId, Code, ExpiresAt]) of
                {ok, {_Columns, [{Id}]}} ->
                    % Send SMS (integrate with SMS service)
                    case send_sms_message(PhoneNumber, Code) of
                        ok ->
                            log_mfa_event(UserId, sms_code_sent, success),
                            {ok, #{
                                id => Id,
                                phone_number => mask_phone_number(PhoneNumber),
                                expires_at => ExpiresAt
                            }};
                        {error, Reason} ->
                            io:format("Failed to send SMS to ~p: ~p~n", [PhoneNumber, Reason]),
                            {error, sms_send_failed}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_verify_sms_code(UserId, Code) ->
    SQL = "SELECT code, expires_at, attempts FROM sms_verification_codes 
           WHERE user_id = $1 AND expires_at > NOW()",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, [{StoredCode, _ExpiresAt, Attempts}]}} ->
            if Attempts >= 3 ->
                log_mfa_event(UserId, sms_code_verified, too_many_attempts),
                {error, too_many_attempts};
            true ->
                case Code =:= StoredCode of
                    true ->
                        % Delete used code
                        DeleteSQL = "DELETE FROM sms_verification_codes WHERE user_id = $1",
                        aethertalk_db:query(DeleteSQL, [UserId]),
                        log_mfa_event(UserId, sms_code_verified, success),
                        {ok, verified};
                    false ->
                        % Increment attempts
                        UpdateSQL = "UPDATE sms_verification_codes 
                                    SET attempts = attempts + 1 
                                    WHERE user_id = $1",
                        aethertalk_db:query(UpdateSQL, [UserId]),
                        log_mfa_event(UserId, sms_code_verified, failed),
                        {error, invalid_code}
                end
            end;
        {ok, {_Columns, []}} ->
            {error, no_code_sent};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_mfa_status(UserId) ->
    SQL = "SELECT totp_enabled, backup_codes, created_at, updated_at 
           FROM user_mfa_settings WHERE user_id = $1",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, [{TotpEnabled, BackupCodes, CreatedAt, UpdatedAt}]}} ->
            BackupCodesList = case BackupCodes of
                null -> [];
                _ -> jiffy:decode(BackupCodes, [return_maps])
            end,
            
            {ok, #{
                user_id => UserId,
                totp_enabled => TotpEnabled,
                backup_codes_count => length(BackupCodesList),
                sms_available => has_phone_number(UserId),
                created_at => CreatedAt,
                updated_at => UpdatedAt
            }};
        {ok, {_Columns, []}} ->
            {ok, #{
                user_id => UserId,
                totp_enabled => false,
                backup_codes_count => 0,
                sms_available => has_phone_number(UserId),
                created_at => null,
                updated_at => null
            }};
        {error, Reason} ->
            {error, Reason}
    end.

do_require_mfa_setup(UserId) ->
    % Check if user is in a role that requires MFA
    case get_user_role(UserId) of
        {ok, Role} when Role =:= <<"admin">>; Role =:= <<"moderator">> ->
            case do_get_mfa_status(UserId) of
                {ok, #{totp_enabled := false}} ->
                    {ok, required};
                {ok, #{totp_enabled := true}} ->
                    {ok, not_required};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, _Role} ->
            {ok, not_required};
        {error, Reason} ->
            {error, Reason}
    end.

do_verify_mfa_challenge(UserId, Method, Code) ->
    case Method of
        <<"totp">> ->
            do_verify_totp(UserId, Code);
        <<"sms">> ->
            do_verify_sms_code(UserId, Code);
        <<"backup">> ->
            do_verify_backup_code(UserId, Code);
        _ ->
            {error, invalid_method}
    end.

%% Helper functions

get_totp_secret(UserId) ->
    SQL = "SELECT totp_secret FROM user_mfa_settings 
           WHERE user_id = $1 AND totp_secret IS NOT NULL",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, [{Secret}]}} ->
            {ok, Secret};
        {ok, {_Columns, []}} ->
            {error, no_totp_secret};
        {error, Reason} ->
            {error, Reason}
    end.

verify_totp_code(Secret, Code) ->
    try
        CodeInt = binary_to_integer(Code),
        CurrentTime = erlang:system_time(second),
        TimeStep = CurrentTime div ?TOTP_PERIOD,
        
        % Check current time step and adjacent ones
        lists:any(fun(Step) ->
            ExpectedCode = generate_totp_code(Secret, Step),
            ExpectedCode =:= CodeInt
        end, [TimeStep - ?TOTP_WINDOW, TimeStep, TimeStep + ?TOTP_WINDOW])
    catch
        _:_ ->
            false
    end.

generate_totp_code(Secret, TimeStep) ->
    % Convert time step to 8-byte big-endian binary
    TimeBytes = <<TimeStep:64/big>>,
    
    % Generate HMAC-SHA1
    HMAC = crypto:mac(hmac, sha, Secret, TimeBytes),
    
    % Dynamic truncation
    <<_:19/binary, LastByte:8>> = HMAC,
    Offset = LastByte band 16#0F,
    <<_:Offset/binary, Code:32/big, _/binary>> = HMAC,
    
    % Generate 6-digit code
    (Code band 16#7FFFFFFF) rem trunc(math:pow(10, ?TOTP_DIGITS)).

enable_totp_if_needed(UserId) ->
    SQL = "UPDATE user_mfa_settings 
           SET totp_enabled = TRUE, updated_at = NOW() 
           WHERE user_id = $1 AND totp_enabled = FALSE",
    aethertalk_db:query(SQL, [UserId]).

generate_qr_code_data(UserId, Secret) ->
    % Get user info
    case aethertalk_user_manager:get_user(UserId) of
        {ok, User} ->
            Username = maps:get(username, User),
            Issuer = <<"AetherTalk">>,
            
            % Generate TOTP URI
            URI = iolist_to_binary([
                <<"otpauth://totp/">>, Issuer, <<":", Username>>,
                <<"?secret=">>, Secret,
                <<"&issuer=">>, Issuer,
                <<"&digits=">>, integer_to_binary(?TOTP_DIGITS),
                <<"&period=">>, integer_to_binary(?TOTP_PERIOD)
            ]),
            
            URI;
        {error, _} ->
            <<"otpauth://totp/AetherTalk?secret=", Secret/binary>>
    end.

generate_backup_code() ->
    % Generate 8-character alphanumeric code
    Chars = <<"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789">>,
    Length = byte_size(Chars),
    
    list_to_binary([
        binary:at(Chars, rand:uniform(Length) - 1) || _ <- lists:seq(1, 8)
    ]).

get_backup_codes(UserId) ->
    SQL = "SELECT backup_codes FROM user_mfa_settings WHERE user_id = $1",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, [{null}]}} ->
            {ok, []};
        {ok, {_Columns, [{BackupCodes}]}} ->
            {ok, jiffy:decode(BackupCodes, [return_maps])};
        {ok, {_Columns, []}} ->
            {error, user_not_found};
        {error, Reason} ->
            {error, Reason}
    end.

update_backup_codes(UserId, HashedCodes) ->
    SQL = "UPDATE user_mfa_settings 
           SET backup_codes = $1, updated_at = NOW() 
           WHERE user_id = $2",
    aethertalk_db:query(SQL, [jiffy:encode(HashedCodes), UserId]).

generate_sms_code() ->
    % Generate 6-digit numeric code
    Code = rand:uniform(999999),
    iolist_to_binary(io_lib:format("~6..0B", [Code])).

get_user_phone(UserId) ->
    SQL = "SELECT phone_number FROM users WHERE id = $1 AND phone_number IS NOT NULL",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, [{PhoneNumber}]}} ->
            {ok, PhoneNumber};
        {ok, {_Columns, []}} ->
            {error, no_phone_number};
        {error, Reason} ->
            {error, Reason}
    end.

has_phone_number(UserId) ->
    case get_user_phone(UserId) of
        {ok, _} -> true;
        {error, _} -> false
    end.

get_user_role(UserId) ->
    % This would integrate with your user role system
    SQL = "SELECT role FROM user_roles WHERE user_id = $1",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, [{Role}]}} ->
            {ok, Role};
        {ok, {_Columns, []}} ->
            {ok, <<"user">>}; % Default role
        {error, Reason} ->
            {error, Reason}
    end.

send_sms_message(PhoneNumber, Code) ->
    % Integrate with SMS service (Twilio, AWS SNS, etc.)
    Message = iolist_to_binary([
        <<"Your AetherTalk verification code is: ">>, Code,
        <<". This code expires in 5 minutes.">>
    ]),
    
    % For now, just log the message (replace with actual SMS service)
    io:format("SMS to ~p: ~p~n", [PhoneNumber, Message]),
    ok.

mask_phone_number(PhoneNumber) ->
    % Mask phone number for security (show only last 4 digits)
    case byte_size(PhoneNumber) of
        Size when Size > 4 ->
            Masked = binary:copy(<<"*">>, Size - 4),
            Last4 = binary:part(PhoneNumber, Size - 4, 4),
            <<Masked/binary, Last4/binary>>;
        _ ->
            binary:copy(<<"*">>, byte_size(PhoneNumber))
    end.

log_mfa_event(UserId, Event, Result) ->
    io:format("MFA event - User: ~p, Event: ~p, Result: ~p~n", [UserId, Event, Result]),
    
    % Store in database for audit
    SQL = "INSERT INTO mfa_audit_log (user_id, event_type, result, created_at) 
           VALUES ($1, $2, $3, NOW())",
    
    spawn(fun() ->
        aethertalk_db:query(SQL, [UserId, atom_to_binary(Event, utf8), atom_to_binary(Result, utf8)])
    end).

%% Cleanup function for expired SMS codes
cleanup_expired_sms_codes() ->
    SQL = "DELETE FROM sms_verification_codes WHERE expires_at <= NOW()",
    
    case aethertalk_db:query(SQL, []) of
        {ok, Count} when Count > 0 ->
            io:format("Cleaned up ~p expired SMS codes~n", [Count]);
        _ ->
            ok
    end.

%% Base32 encoding implementation
base32_encode(Data) ->
    base32_encode(Data, <<>>).

base32_encode(<<>>, Acc) ->
    Acc;
base32_encode(<<A:5, B:5, C:5, D:5, E:5, F:5, G:5, H:5, Rest/binary>>, Acc) ->
    Chars = <<"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567">>,
    Encoded = <<(binary:at(Chars, A)), (binary:at(Chars, B)), (binary:at(Chars, C)), 
               (binary:at(Chars, D)), (binary:at(Chars, E)), (binary:at(Chars, F)),
               (binary:at(Chars, G)), (binary:at(Chars, H))>>,
    base32_encode(Rest, <<Acc/binary, Encoded/binary>>);
base32_encode(Data, Acc) ->
    % Handle remaining bits with padding
    PaddedData = pad_for_base32(Data),
    base32_encode(PaddedData, Acc).

pad_for_base32(<<A:5, B:3>>) ->
    <<A:5, B:3, 0:2>>;
pad_for_base32(<<A:5, B:5, C:1>>) ->
    <<A:5, B:5, C:1, 0:4>>;
pad_for_base32(<<A:5, B:5, C:5, D:4>>) ->
    <<A:5, B:5, C:5, D:4, 0:1>>;
pad_for_base32(<<A:5, B:5, C:5, D:5, E:2>>) ->
    <<A:5, B:5, C:5, D:5, E:2, 0:3>>;
pad_for_base32(<<A:5, B:5, C:5, D:5, E:5, F:5, G:5>>) ->
    <<A:5, B:5, C:5, D:5, E:5, F:5, G:5, 0:0>>;
pad_for_base32(Data) ->
    Data.