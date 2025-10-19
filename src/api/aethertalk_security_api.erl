%%%-------------------------------------------------------------------
%%% @doc
%%% Security API endpoints for AetherTalk
%%% Handles MFA, encryption, and security management
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_security_api).

% Cowboy REST handler behavior
-behaviour(cowboy_rest).

% Cowboy REST callbacks
-export([
    init/2,
    allowed_methods/2,
    content_types_provided/2,
    content_types_accepted/2,
    is_authorized/2,
    resource_exists/2
]).

% Content handlers
-export([
    handle_get/2,
    handle_post/2,
    handle_put/2,
    handle_delete/2
]).

-include("aethertalk.hrl").

-record(state, {
    user_id :: binary(),
    action :: atom(),
    resource_id :: binary()
}).

%% ===================================================================
%% Cowboy REST callbacks
%% ===================================================================

init(Req, _Opts) ->
    % Parse path to determine action
    Path = cowboy_req:path(Req),
    {Action, ResourceId} = parse_security_path(Path),
    
    State = #state{
        action = Action,
        resource_id = ResourceId
    },
    
    {cowboy_rest, Req, State}.

allowed_methods(Req, State) ->
    Methods = case State#state.action of
        mfa_status -> [<<"GET">>];
        mfa_enable -> [<<"POST">>];
        mfa_disable -> [<<"DELETE">>];
        mfa_verify -> [<<"POST">>];
        mfa_backup_codes -> [<<"GET">>, <<"POST">>];
        encryption_keys -> [<<"GET">>, <<"POST">>];
        encryption_session -> [<<"GET">>, <<"POST">>, <<"DELETE">>];
        security_events -> [<<"GET">>];
        rate_limits -> [<<"GET">>, <<"POST">>];
        _ -> [<<"GET">>, <<"POST">>, <<"PUT">>, <<"DELETE">>]
    end,
    {Methods, Req, State}.

content_types_provided(Req, State) ->
    {[
        {<<"application/json">>, handle_get}
    ], Req, State}.

content_types_accepted(Req, State) ->
    {[
        {<<"application/json">>, handle_post}
    ], Req, State}.

is_authorized(Req, State) ->
    case aethertalk_security_middleware:check_authentication(Req) of
        {ok, UserId, _Claims} ->
            NewState = State#state{user_id = UserId},
            {true, Req, NewState};
        {error, _Reason} ->
            {{false, <<"Bearer">>}, Req, State}
    end.

resource_exists(Req, State) ->
    % All security endpoints exist if user is authenticated
    {true, Req, State}.

%% ===================================================================
%% Content handlers
%% ===================================================================

handle_get(Req, #state{action = mfa_status, user_id = UserId} = State) ->
    case aethertalk_mfa:get_mfa_status(UserId) of
        {ok, Status} ->
            Response = jiffy:encode(#{
                status => <<"success">>,
                data => Status
            }),
            {Response, Req, State};
        {error, Reason} ->
            handle_error(Req, State, Reason)
    end;

handle_get(Req, #state{action = mfa_backup_codes, user_id = UserId} = State) ->
    case aethertalk_mfa:generate_backup_codes(UserId) of
        {ok, BackupCodes} ->
            Response = jiffy:encode(#{
                status => <<"success">>,
                data => #{
                    backup_codes => BackupCodes,
                    message => <<"Store these codes securely. They can only be used once.">>
                }
            }),
            {Response, Req, State};
        {error, Reason} ->
            handle_error(Req, State, Reason)
    end;

handle_get(Req, #state{action = encryption_keys, user_id = UserId} = State) ->
    case aethertalk_encryption:get_user_public_keys(UserId) of
        {ok, Keys} ->
            Response = jiffy:encode(#{
                status => <<"success">>,
                data => Keys
            }),
            {Response, Req, State};
        {error, Reason} ->
            handle_error(Req, State, Reason)
    end;

handle_get(Req, #state{action = encryption_session, user_id = UserId, resource_id = OtherUserId} = State) ->
    case aethertalk_encryption:get_session_info(UserId, OtherUserId) of
        {ok, SessionInfo} ->
            Response = jiffy:encode(#{
                status => <<"success">>,
                data => SessionInfo
            }),
            {Response, Req, State};
        {error, Reason} ->
            handle_error(Req, State, Reason)
    end;

handle_get(Req, #state{action = security_events, user_id = UserId} = State) ->
    case get_user_security_events(UserId) of
        {ok, Events} ->
            Response = jiffy:encode(#{
                status => <<"success">>,
                data => #{events => Events}
            }),
            {Response, Req, State};
        {error, Reason} ->
            handle_error(Req, State, Reason)
    end;

handle_get(Req, #state{action = rate_limits, user_id = UserId} = State) ->
    case get_user_rate_limits(UserId) of
        {ok, RateLimits} ->
            Response = jiffy:encode(#{
                status => <<"success">>,
                data => #{rate_limits => RateLimits}
            }),
            {Response, Req, State};
        {error, Reason} ->
            handle_error(Req, State, Reason)
    end;

handle_get(Req, State) ->
    handle_error(Req, State, not_found).

handle_post(Req, #state{action = mfa_enable, user_id = UserId} = State) ->
    case aethertalk_mfa:enable_totp(UserId) of
        {ok, TOTPData} ->
            Response = jiffy:encode(#{
                status => <<"success">>,
                data => TOTPData,
                message => <<"Scan the QR code with your authenticator app and verify with a code">>
            }),
            {Response, Req, State};
        {error, Reason} ->
            handle_error(Req, State, Reason)
    end;

handle_post(Req, #state{action = mfa_verify, user_id = UserId} = State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    
    try
        #{<<"method">> := Method, <<"code">> := Code} = jiffy:decode(Body, [return_maps]),
        
        case aethertalk_mfa:verify_mfa_challenge(UserId, Method, Code) of
            {ok, verified} ->
                % Generate MFA session token
                MFAToken = generate_mfa_session_token(UserId),
                
                Response = jiffy:encode(#{
                    status => <<"success">>,
                    data => #{
                        verified => true,
                        mfa_token => MFAToken
                    },
                    message => <<"MFA verification successful">>
                }),
                
                Req3 = cowboy_req:set_resp_header(<<"x-mfa-token">>, MFAToken, Req2),
                {Response, Req3, State};
            {error, Reason} ->
                handle_error(Req2, State, Reason)
        end
    catch
        _:_ ->
            handle_error(Req2, State, invalid_request)
    end;

handle_post(Req, #state{action = encryption_keys, user_id = UserId} = State) ->
    case aethertalk_encryption:generate_identity_key(UserId) of
        {ok, IdentityKey} ->
            case aethertalk_encryption:generate_prekeys(UserId, 100) of
                {ok, Prekeys} ->
                    Response = jiffy:encode(#{
                        status => <<"success">>,
                        data => #{
                            identity_key => IdentityKey,
                            prekeys_generated => length(Prekeys)
                        },
                        message => <<"Encryption keys generated successfully">>
                    }),
                    {Response, Req, State};
                {error, Reason} ->
                    handle_error(Req, State, Reason)
            end;
        {error, Reason} ->
            handle_error(Req, State, Reason)
    end;

handle_post(Req, #state{action = encryption_session, user_id = UserId} = State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    
    try
        #{<<"other_user_id">> := OtherUserId} = jiffy:decode(Body, [return_maps]),
        
        case aethertalk_encryption:create_session(UserId, OtherUserId, UserId) of
            {ok, Session} ->
                Response = jiffy:encode(#{
                    status => <<"success">>,
                    data => Session,
                    message => <<"Encryption session created">>
                }),
                {Response, Req2, State};
            {error, Reason} ->
                handle_error(Req2, State, Reason)
        end
    catch
        _:_ ->
            handle_error(Req2, State, invalid_request)
    end;

handle_post(Req, #state{action = rate_limits, user_id = UserId} = State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    
    try
        #{<<"action">> := ActionBin, <<"limit">> := Limit, <<"window">> := Window} = 
            jiffy:decode(Body, [return_maps]),
        
        Action = binary_to_atom(ActionBin, utf8),
        
        case aethertalk_rate_limiter:set_custom_limit(UserId, Action, Limit, Window) of
            {ok, CustomLimit} ->
                Response = jiffy:encode(#{
                    status => <<"success">>,
                    data => CustomLimit,
                    message => <<"Custom rate limit set">>
                }),
                {Response, Req2, State};
            {error, Reason} ->
                handle_error(Req2, State, Reason)
        end
    catch
        _:_ ->
            handle_error(Req2, State, invalid_request)
    end;

handle_post(Req, State) ->
    handle_error(Req, State, not_found).

handle_put(Req, State) ->
    handle_error(Req, State, method_not_allowed).

handle_delete(Req, #state{action = mfa_disable, user_id = UserId} = State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    
    try
        #{<<"code">> := Code} = jiffy:decode(Body, [return_maps]),
        
        case aethertalk_mfa:disable_totp(UserId, Code) of
            {ok, disabled} ->
                Response = jiffy:encode(#{
                    status => <<"success">>,
                    message => <<"MFA disabled successfully">>
                }),
                {Response, Req2, State};
            {error, Reason} ->
                handle_error(Req2, State, Reason)
        end
    catch
        _:_ ->
            handle_error(Req2, State, invalid_request)
    end;

handle_delete(Req, #state{action = encryption_session, user_id = UserId, resource_id = OtherUserId} = State) ->
    case aethertalk_encryption:delete_session(UserId, OtherUserId) of
        ok ->
            Response = jiffy:encode(#{
                status => <<"success">>,
                message => <<"Encryption session deleted">>
            }),
            {Response, Req, State};
        {error, Reason} ->
            handle_error(Req, State, Reason)
    end;

handle_delete(Req, State) ->
    handle_error(Req, State, not_found).

%% ===================================================================
%% Internal functions
%% ===================================================================

parse_security_path(<<"/api/security/mfa/status">>) ->
    {mfa_status, undefined};
parse_security_path(<<"/api/security/mfa/enable">>) ->
    {mfa_enable, undefined};
parse_security_path(<<"/api/security/mfa/disable">>) ->
    {mfa_disable, undefined};
parse_security_path(<<"/api/security/mfa/verify">>) ->
    {mfa_verify, undefined};
parse_security_path(<<"/api/security/mfa/backup-codes">>) ->
    {mfa_backup_codes, undefined};
parse_security_path(<<"/api/security/encryption/keys">>) ->
    {encryption_keys, undefined};
parse_security_path(<<"/api/security/encryption/session">>) ->
    {encryption_session, undefined};
parse_security_path(<<"/api/security/encryption/session/", UserId/binary>>) ->
    {encryption_session, UserId};
parse_security_path(<<"/api/security/events">>) ->
    {security_events, undefined};
parse_security_path(<<"/api/security/rate-limits">>) ->
    {rate_limits, undefined};
parse_security_path(_) ->
    {unknown, undefined}.

get_user_security_events(UserId) ->
    SQL = "SELECT event_type, client_ip, user_agent, path, method, event_data, created_at 
           FROM security_events 
           WHERE event_data->>'user_id' = $1 
           ORDER BY created_at DESC 
           LIMIT 50",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, Rows}} ->
            Events = lists:map(fun({EventType, ClientIP, UserAgent, Path, Method, EventData, CreatedAt}) ->
                #{
                    event_type => EventType,
                    client_ip => ClientIP,
                    user_agent => UserAgent,
                    path => Path,
                    method => Method,
                    event_data => jiffy:decode(EventData, [return_maps]),
                    created_at => CreatedAt
                }
            end, Rows),
            {ok, Events};
        {error, Reason} ->
            {error, Reason}
    end.

get_user_rate_limits(UserId) ->
    % Get current rate limit status for various actions
    Actions = [send_message, send_media, create_group, voice_call, create_poll, create_status],
    
    RateLimits = lists:map(fun(Action) ->
        case aethertalk_rate_limiter:get_rate_limit_info(UserId, Action) of
            {ok, Info} ->
                Info;
            {error, _} ->
                #{
                    action => Action,
                    current_count => 0,
                    limit => 0,
                    remaining => 0,
                    error => <<"Unable to get rate limit info">>
                }
        end
    end, Actions),
    
    {ok, RateLimits}.

generate_mfa_session_token(UserId) ->
    Timestamp = integer_to_binary(erlang:system_time(second)),
    UserIdBin = list_to_binary(UserId),
    
    % Simple signature (in production, use proper JWT)
    Signature = crypto:hash(sha256, <<UserIdBin/binary, ":", Timestamp/binary>>),
    
    Token = <<UserIdBin/binary, ":", Timestamp/binary, ":", Signature/binary>>,
    base64:encode(Token).

handle_error(Req, State, Reason) ->
    {StatusCode, ErrorMessage} = case Reason of
        not_found ->
            {404, <<"Resource not found">>};
        method_not_allowed ->
            {405, <<"Method not allowed">>};
        invalid_request ->
            {400, <<"Invalid request format">>};
        invalid_code ->
            {400, <<"Invalid verification code">>};
        no_totp_secret ->
            {400, <<"TOTP not enabled for user">>};
        user_not_found ->
            {404, <<"User not found">>};
        session_not_found ->
            {404, <<"Encryption session not found">>};
        no_session ->
            {404, <<"No encryption session exists">>};
        _ ->
            {500, <<"Internal server error">>}
    end,
    
    ErrorResp = jiffy:encode(#{
        status => <<"error">>,
        error => ErrorMessage,
        code => Reason
    }),
    
    Req2 = cowboy_req:reply(StatusCode, 
        #{<<"content-type">> => <<"application/json">>}, 
        ErrorResp, Req),
    
    {stop, Req2, State}.