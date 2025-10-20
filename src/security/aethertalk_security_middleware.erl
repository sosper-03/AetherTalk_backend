%%%-------------------------------------------------------------------
%%% @doc
%%% Security Middleware for AetherTalk
%%% Integrates all security features into a comprehensive middleware
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_security_middleware).

% Cowboy middleware behavior
-behaviour(cowboy_middleware).

% Public API
-export([
    execute/2,
    init_security/0,
    check_authentication/1,
    check_authorization/2,
    apply_security_headers/1,
    validate_request_security/1
]).

-include("aethertalk.hrl").

%% Security configuration
-define(SECURITY_CONFIG, #{
    % Rate limiting enabled
    rate_limiting => true,
    
    % CSRF protection enabled for state-changing operations
    csrf_protection => true,
    
    % Content validation enabled
    content_validation => true,
    
    % Security headers enabled
    security_headers => true,
    
    % Request validation enabled
    request_validation => true,
    
    % Authentication required paths
    auth_required_paths => [
        <<"/api/messages">>,
        <<"/api/groups">>,
        <<"/api/calls">>,
        <<"/api/user">>,
        <<"/api/contacts">>,
        <<"/api/media">>,
        <<"/api/status">>,
        <<"/api/polls">>,
        <<"/api/location">>
    ],
    
    % Public paths (no authentication required)
    public_paths => [
        <<"/api/auth/login">>,
        <<"/api/auth/register">>,
        <<"/api/auth/forgot-password">>,
        <<"/api/health">>,
        <<"/api/version">>,
        <<"/static">>,
        <<"/ws">>
    ],
    
    % Admin-only paths
    admin_paths => [
        <<"/api/admin">>,
        <<"/api/analytics">>,
        <<"/api/moderation">>
    ]
}).

%% ===================================================================
%% Cowboy middleware callbacks
%% ===================================================================

execute(Req, Env) ->
    try
        case apply_security_middleware(Req) of
            {ok, SecureReq} ->
                {ok, SecureReq, Env};
            {error, Reason, ErrorReq} ->
                io:format("Security middleware blocked request: ~p~n", [Reason]),
                {stop, ErrorReq}
        end
    catch
        error:Error ->
            io:format("Security middleware error: ~p~n", [Error]),
            ErrorResp = jiffy:encode(#{
                error => <<"Internal security error">>,
                message => <<"Request could not be processed">>
            }),
            ErrorReq1 = cowboy_req:reply(500, 
                #{<<"content-type">> => <<"application/json">>}, 
                ErrorResp, Req),
            {stop, ErrorReq1}
    end.

%% ===================================================================
%% API functions
%% ===================================================================

%% @doc Initialize security subsystem
init_security() ->
    io:format("Initializing AetherTalk security middleware~n"),
    
    % Ensure all security services are running
    SecurityServices = [
        aethertalk_encryption,
        aethertalk_rate_limiter,
        aethertalk_mfa
    ],
    
    lists:foreach(fun(Service) ->
        case whereis(Service) of
            undefined ->
                io:format("Security service ~p not running~n", [Service]);
            _Pid ->
                io:format("Security service ~p is running~n", [Service])
        end
    end, SecurityServices),
    
    ok.

%% @doc Check if request is authenticated
check_authentication(Req) ->
    case cowboy_req:header(<<"authorization">>, Req) of
        undefined ->
            {error, missing_auth_header};
        AuthHeader ->
            case aethertalk_auth:decode_token(AuthHeader) of
                {ok, Claims} ->
                    UserId = maps:get(user_id, Claims),
                    {ok, UserId, Claims};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

%% @doc Check if user is authorized for the requested resource
check_authorization(Req, UserId) ->
    Path = cowboy_req:path(Req),
    Method = cowboy_req:method(Req),
    
    Config = ?SECURITY_CONFIG,
    AdminPaths = maps:get(admin_paths, Config),
    
    % Check if this is an admin-only path
    case is_admin_path(Path, AdminPaths) of
        true ->
            check_admin_authorization(UserId);
        false ->
            check_regular_authorization(UserId, Path, Method)
    end.

%% @doc Apply security headers to response
apply_security_headers(Req) ->
    aethertalk_security_headers:add_security_headers(Req).

%% @doc Validate request for security issues
validate_request_security(Req) ->
    Validations = [
        fun aethertalk_security_headers:validate_request/1,
        fun aethertalk_security_headers:validate_origin/1,
        fun validate_content_security/1
    ],
    
    run_security_validations(Req, Validations).

%% ===================================================================
%% Internal functions
%% ===================================================================

apply_security_middleware(Req) ->
    SecuritySteps = [
        fun apply_security_headers/1,
        fun validate_request_security/1,
        fun check_rate_limits/1,
        fun check_authentication_if_required/1,
        fun check_csrf_if_required/1,
        fun check_mfa_if_required/1
    ],
    
    run_security_steps(Req, SecuritySteps).

run_security_steps(Req, []) ->
    {ok, Req};
run_security_steps(Req, [Step | Rest]) ->
    case Step(Req) of
        {ok, NewReq} ->
            run_security_steps(NewReq, Rest);
        {error, Reason} ->
            ErrorReq = create_security_error_response(Req, Reason),
            {error, Reason, ErrorReq}
    end.

run_security_validations(Req, []) ->
    {ok, Req};
run_security_validations(Req, [Validation | Rest]) ->
    case Validation(Req) of
        {ok, NewReq} ->
            run_security_validations(NewReq, Rest);
        {error, Reason} ->
            {error, Reason}
    end.

check_rate_limits(Req) ->
    Config = ?SECURITY_CONFIG,
    case maps:get(rate_limiting, Config, true) of
        false ->
            {ok, Req};
        true ->
            Path = cowboy_req:path(Req),
            Action = path_to_action(Path),
            
            case aethertalk_rate_limiter:check_http_rate_limit(Req, Action) of
                {ok, NewReq} ->
                    {ok, NewReq};
                {error, ErrorReq} ->
                    {error, rate_limit_exceeded, ErrorReq}
            end
    end.

check_authentication_if_required(Req) ->
    Path = cowboy_req:path(Req),
    Config = ?SECURITY_CONFIG,
    
    AuthRequiredPaths = maps:get(auth_required_paths, Config),
    PublicPaths = maps:get(public_paths, Config),
    
    case {is_auth_required(Path, AuthRequiredPaths), is_public_path(Path, PublicPaths)} of
        {false, _} ->
            {ok, Req};
        {true, true} ->
            {ok, Req};
        {true, false} ->
            case check_authentication(Req) of
                {ok, UserId, Claims} ->
                    % Store user info in request for later use
                    NewReq = cowboy_req:set_resp_header(<<"x-user-id">>, UserId, Req),
                    NewReq2 = cowboy_req:set_resp_header(<<"x-user-claims">>, 
                                                        jiffy:encode(Claims), NewReq),
                    {ok, NewReq2};
                {error, _Reason} ->
                    {error, authentication_required}
            end
    end.

check_csrf_if_required(Req) ->
    Config = ?SECURITY_CONFIG,
    case maps:get(csrf_protection, Config, true) of
        false ->
            {ok, Req};
        true ->
            Method = cowboy_req:method(Req),
            case Method of
                <<"GET">> -> {ok, Req};
                <<"HEAD">> -> {ok, Req};
                <<"OPTIONS">> -> {ok, Req};
                _ ->
                    case aethertalk_security_headers:check_csrf_token(Req) of
                        {ok, NewReq} ->
                            {ok, NewReq};
                        {error, _Reason} ->
                            {error, csrf_validation_failed}
                    end
            end
    end.

check_mfa_if_required(Req) ->
    % Check if user needs MFA for this action
    case cowboy_req:header(<<"x-user-id">>, Req) of
        undefined ->
            {ok, Req}; % No user, skip MFA check
        UserId ->
            Path = cowboy_req:path(Req),
            case is_mfa_required_path(Path) of
                false ->
                    {ok, Req};
                true ->
                    case check_mfa_session(UserId, Req) of
                        {ok, verified} ->
                            {ok, Req};
                        {error, mfa_required} ->
                            {error, mfa_required};
                        {error, _Reason} ->
                            {error, mfa_verification_failed}
                    end
            end
    end.

validate_content_security(Req) ->
    Method = cowboy_req:method(Req),
    case Method of
        <<"POST">> ->
            validate_post_content(Req);
        <<"PUT">> ->
            validate_put_content(Req);
        _ ->
            {ok, Req}
    end.

validate_post_content(Req) ->
    case cowboy_req:header(<<"content-type">>, Req) of
        undefined ->
            {ok, Req};
        _ContentType ->
            AllowedTypes = [
                <<"application/json">>,
                <<"multipart/form-data">>,
                <<"application/x-www-form-urlencoded">>
            ],
            aethertalk_security_headers:check_content_type(Req, AllowedTypes)
    end.

validate_put_content(Req) ->
    validate_post_content(Req).

is_auth_required(Path, AuthRequiredPaths) ->
    lists:any(fun(RequiredPath) ->
        binary:match(Path, RequiredPath) =/= nomatch
    end, AuthRequiredPaths).

is_public_path(Path, PublicPaths) ->
    lists:any(fun(PublicPath) ->
        binary:match(Path, PublicPath) =/= nomatch
    end, PublicPaths).

is_admin_path(Path, AdminPaths) ->
    lists:any(fun(AdminPath) ->
        binary:match(Path, AdminPath) =/= nomatch
    end, AdminPaths).

is_mfa_required_path(Path) ->
    % MFA required for sensitive operations
    MFARequiredPaths = [
        <<"/api/admin">>,
        <<"/api/user/settings">>,
        <<"/api/user/delete">>,
        <<"/api/groups/create">>,
        <<"/api/calls/conference">>
    ],
    
    lists:any(fun(MFAPath) ->
        binary:match(Path, MFAPath) =/= nomatch
    end, MFARequiredPaths).

check_admin_authorization(UserId) ->
    % Check if user has admin role
    SQL = "SELECT role FROM user_roles WHERE user_id = $1 AND role = 'admin' AND 
           (expires_at IS NULL OR expires_at > NOW())",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, [_]}} ->
            {ok, authorized};
        {ok, {_Columns, []}} ->
            {error, insufficient_privileges};
        {error, Reason} ->
            {error, Reason}
    end.

check_regular_authorization(_UserId, Path, Method) ->
    % Regular authorization checks
    case {Path, Method} of
        {<<"/api/user/", _/binary>>, _} ->
            % Users can access their own user endpoints
            {ok, authorized};
        {<<"/api/messages/", _/binary>>, <<"GET">>} ->
            % Users can read messages they have access to
            {ok, authorized};
        {<<"/api/messages">>, <<"POST">>} ->
            % Users can send messages
            {ok, authorized};
        _ ->
            % Default allow for now (implement more specific rules as needed)
            {ok, authorized}
    end.

check_mfa_session(UserId, Req) ->
    % Check if user has completed MFA for this session
    case cowboy_req:header(<<"x-mfa-token">>, Req) of
        undefined ->
            case aethertalk_mfa:require_mfa_setup(UserId) of
                {ok, required} ->
                    {error, mfa_required};
                {ok, not_required} ->
                    {ok, verified};
                {error, Reason} ->
                    {error, Reason}
            end;
        MFAToken ->
            % Verify MFA token (implement token validation)
            verify_mfa_token(UserId, MFAToken)
    end.

verify_mfa_token(UserId, Token) ->
    % Simple MFA token verification (in production, use proper JWT or session tokens)
    try
        DecodedToken = base64:decode(Token),
        [UserIdBin, Timestamp, Signature] = binary:split(DecodedToken, <<":">>, [global]),
        
        case binary_to_list(UserIdBin) =:= UserId of
            true ->
                % Check if token is not expired (1 hour)
                TokenTime = binary_to_integer(Timestamp),
                CurrentTime = erlang:system_time(second),
                
                if CurrentTime - TokenTime < 3600 ->
                    % Verify signature (simplified)
                    ExpectedSig = crypto:hash(sha256, <<UserIdBin/binary, ":", Timestamp/binary>>),
                    case crypto:hash_equals(Signature, ExpectedSig) of
                        true -> {ok, verified};
                        false -> {error, invalid_token}
                    end;
                true ->
                    {error, token_expired}
                end;
            false ->
                {error, invalid_token}
        end
    catch
        _:_ ->
            {error, invalid_token}
    end.

path_to_action(Path) ->
    case Path of
        <<"/api/auth/login">> -> login;
        <<"/api/auth/register">> -> register;
        <<"/api/messages", _/binary>> -> send_message;
        <<"/api/media", _/binary>> -> send_media;
        <<"/api/groups", _/binary>> -> create_group;
        <<"/api/calls", _/binary>> -> voice_call;
        <<"/api/polls", _/binary>> -> create_poll;
        <<"/api/status", _/binary>> -> create_status;
        <<"/api/location", _/binary>> -> share_location;
        _ -> api_call
    end.

create_security_error_response(Req, Reason) ->
    {StatusCode, ErrorMessage} = case Reason of
        authentication_required ->
            {401, <<"Authentication required">>};
        insufficient_privileges ->
            {403, <<"Insufficient privileges">>};
        rate_limit_exceeded ->
            {429, <<"Rate limit exceeded">>};
        csrf_validation_failed ->
            {403, <<"CSRF validation failed">>};
        mfa_required ->
            {403, <<"Multi-factor authentication required">>};
        mfa_verification_failed ->
            {403, <<"MFA verification failed">>};
        invalid_content_type ->
            {400, <<"Invalid content type">>};
        invalid_origin ->
            {403, <<"Invalid origin">>};
        suspicious_pattern ->
            {400, <<"Suspicious request pattern detected">>};
        _ ->
            {400, <<"Security validation failed">>}
    end,
    
    ErrorResp = jiffy:encode(#{
        error => ErrorMessage,
        code => Reason,
        timestamp => erlang:system_time(millisecond)
    }),
    
    Headers = #{
        <<"content-type">> => <<"application/json">>,
        <<"x-security-error">> => atom_to_binary(Reason, utf8)
    },
    
    cowboy_req:reply(StatusCode, Headers, ErrorResp, Req).