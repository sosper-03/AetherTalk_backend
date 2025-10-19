%%%-------------------------------------------------------------------
%%% @doc
%%% Security Headers and Middleware for AetherTalk
%%% Implements comprehensive security headers and request validation
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_security_headers).

% Public API
-export([
    add_security_headers/1,
    validate_request/1,
    check_csrf_token/1,
    generate_csrf_token/1,
    sanitize_input/1,
    check_content_type/2,
    validate_origin/1,
    log_security_event/3
]).

-include("aethertalk.hrl").

%% Security header configurations
-define(SECURITY_HEADERS, #{
    % Prevent XSS attacks
    <<"x-xss-protection">> => <<"1; mode=block">>,
    
    % Prevent MIME type sniffing
    <<"x-content-type-options">> => <<"nosniff">>,
    
    % Prevent clickjacking
    <<"x-frame-options">> => <<"DENY">>,
    
    % Strict Transport Security (HTTPS only)
    <<"strict-transport-security">> => <<"max-age=31536000; includeSubDomains; preload">>,
    
    % Content Security Policy
    <<"content-security-policy">> => <<"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' wss: https:; font-src 'self'; object-src 'none'; media-src 'self' https:; frame-src 'none'">>,
    
    % Referrer Policy
    <<"referrer-policy">> => <<"strict-origin-when-cross-origin">>,
    
    % Permissions Policy
    <<"permissions-policy">> => <<"geolocation=(self), microphone=(self), camera=(self), payment=(), usb=()">>,
    
    % Cross-Origin policies
    <<"cross-origin-embedder-policy">> => <<"require-corp">>,
    <<"cross-origin-opener-policy">> => <<"same-origin">>,
    <<"cross-origin-resource-policy">> => <<"same-origin">>
}).

%% Allowed origins for CORS
-define(ALLOWED_ORIGINS, [
    <<"https://aethertalk.com">>,
    <<"https://www.aethertalk.com">>,
    <<"https://app.aethertalk.com">>,
    <<"http://localhost:3000">>,  % Development only
    <<"http://localhost:8080">>   % Development only
]).

%% Content type whitelist
-define(ALLOWED_CONTENT_TYPES, [
    <<"application/json">>,
    <<"multipart/form-data">>,
    <<"application/x-www-form-urlencoded">>,
    <<"text/plain">>,
    <<"image/jpeg">>,
    <<"image/png">>,
    <<"image/gif">>,
    <<"image/webp">>,
    <<"video/mp4">>,
    <<"video/webm">>,
    <<"audio/mpeg">>,
    <<"audio/wav">>,
    <<"audio/ogg">>,
    <<"application/pdf">>,
    <<"application/msword">>,
    <<"application/vnd.openxmlformats-officedocument.wordprocessingml.document">>
]).

%% ===================================================================
%% API functions
%% ===================================================================

%% @doc Add security headers to HTTP response
add_security_headers(Req) ->
    Headers = maps:fold(fun(Key, Value, Acc) ->
        maps:put(Key, Value, Acc)
    end, #{}, ?SECURITY_HEADERS),
    
    % Add CORS headers if needed
    CorsHeaders = add_cors_headers(Req),
    AllHeaders = maps:merge(Headers, CorsHeaders),
    
    cowboy_req:set_resp_headers(AllHeaders, Req).

%% @doc Validate incoming request for security
validate_request(Req) ->
    Validations = [
        fun validate_method/1,
        fun validate_headers/1,
        fun validate_content_length/1,
        fun validate_user_agent/1,
        fun check_suspicious_patterns/1
    ],
    
    run_validations(Req, Validations).

%% @doc Check CSRF token validity
check_csrf_token(Req) ->
    case cowboy_req:method(Req) of
        Method when Method =:= <<"GET">>; Method =:= <<"HEAD">>; Method =:= <<"OPTIONS">> ->
            {ok, Req};
        _ ->
            case get_csrf_token_from_request(Req) of
                {ok, Token} ->
                    case validate_csrf_token(Token, Req) of
                        true ->
                            {ok, Req};
                        false ->
                            log_security_event(csrf_validation_failed, Req, #{}),
                            {error, invalid_csrf_token}
                    end;
                {error, missing_token} ->
                    log_security_event(csrf_token_missing, Req, #{}),
                    {error, missing_csrf_token}
            end
    end.

%% @doc Generate CSRF token for user session
generate_csrf_token(UserId) ->
    Timestamp = erlang:system_time(second),
    Nonce = crypto:strong_rand_bytes(16),
    
    % Create token payload
    Payload = #{
        user_id => UserId,
        timestamp => Timestamp,
        nonce => base64:encode(Nonce)
    },
    
    % Sign the token
    Secret = get_csrf_secret(),
    TokenData = jiffy:encode(Payload),
    Signature = crypto:mac(hmac, sha256, Secret, TokenData),
    
    Token = base64:encode(<<TokenData/binary, ".", Signature/binary>>),
    
    % Store token in database with expiry
    ExpiresAt = Timestamp + 3600, % 1 hour expiry
    SQL = "INSERT INTO csrf_tokens (user_id, token, expires_at, created_at) 
           VALUES ($1, $2, to_timestamp($3), NOW())
           ON CONFLICT (user_id) 
           DO UPDATE SET token = $2, expires_at = to_timestamp($3), updated_at = NOW()",
    
    case aethertalk_db:query(SQL, [UserId, Token, ExpiresAt]) of
        {ok, _} ->
            {ok, Token};
        {error, Reason} ->
            lager:error("Failed to store CSRF token: ~p", [Reason]),
            {error, token_storage_failed}
    end.

%% @doc Sanitize user input to prevent injection attacks
sanitize_input(Input) when is_binary(Input) ->
    % Remove potentially dangerous characters and patterns
    Cleaned = re:replace(Input, <<"[<>\"'&]">>, <<"">>, [global, {return, binary}]),
    
    % Limit length to prevent DoS
    MaxLength = 10000,
    case byte_size(Cleaned) > MaxLength of
        true ->
            binary:part(Cleaned, 0, MaxLength);
        false ->
            Cleaned
    end;
sanitize_input(Input) when is_list(Input) ->
    [sanitize_input(Item) || Item <- Input];
sanitize_input(Input) when is_map(Input) ->
    maps:map(fun(_Key, Value) -> sanitize_input(Value) end, Input);
sanitize_input(Input) ->
    Input.

%% @doc Check if content type is allowed
check_content_type(Req, AllowedTypes) ->
    case cowboy_req:header(<<"content-type">>, Req) of
        undefined ->
            {ok, Req};
        ContentType ->
            % Extract main content type (ignore charset, boundary, etc.)
            MainType = hd(binary:split(ContentType, <<";">>)),
            CleanType = string:trim(MainType),
            
            case lists:member(CleanType, AllowedTypes) of
                true ->
                    {ok, Req};
                false ->
                    log_security_event(invalid_content_type, Req, #{content_type => CleanType}),
                    {error, invalid_content_type}
            end
    end.

%% @doc Validate request origin
validate_origin(Req) ->
    case cowboy_req:header(<<"origin">>, Req) of
        undefined ->
            {ok, Req};
        Origin ->
            case lists:member(Origin, ?ALLOWED_ORIGINS) of
                true ->
                    {ok, Req};
                false ->
                    log_security_event(invalid_origin, Req, #{origin => Origin}),
                    {error, invalid_origin}
            end
    end.

%% @doc Log security events
log_security_event(Event, Req, ExtraData) ->
    ClientIP = get_client_ip(Req),
    UserAgent = cowboy_req:header(<<"user-agent">>, Req, <<"unknown">>),
    Path = cowboy_req:path(Req),
    Method = cowboy_req:method(Req),
    
    EventData = maps:merge(#{
        event => Event,
        client_ip => inet:ntoa(ClientIP),
        user_agent => UserAgent,
        path => Path,
        method => Method,
        timestamp => erlang:system_time(millisecond)
    }, ExtraData),
    
    lager:warning("Security event: ~p", [EventData]),
    
    % Store in database for analysis
    SQL = "INSERT INTO security_events (event_type, client_ip, user_agent, path, method, 
                                       event_data, created_at) 
           VALUES ($1, $2, $3, $4, $5, $6, NOW())",
    
    spawn(fun() ->
        aethertalk_db:query(SQL, [
            atom_to_binary(Event, utf8),
            inet:ntoa(ClientIP),
            UserAgent,
            Path,
            Method,
            jiffy:encode(EventData)
        ])
    end).

%% ===================================================================
%% Internal functions
%% ===================================================================

add_cors_headers(Req) ->
    Origin = cowboy_req:header(<<"origin">>, Req),
    
    case Origin of
        undefined ->
            #{};
        _ ->
            case lists:member(Origin, ?ALLOWED_ORIGINS) of
                true ->
                    #{
                        <<"access-control-allow-origin">> => Origin,
                        <<"access-control-allow-methods">> => <<"GET, POST, PUT, DELETE, OPTIONS">>,
                        <<"access-control-allow-headers">> => <<"Content-Type, Authorization, X-CSRF-Token">>,
                        <<"access-control-allow-credentials">> => <<"true">>,
                        <<"access-control-max-age">> => <<"86400">>
                    };
                false ->
                    #{}
            end
    end.

run_validations(Req, []) ->
    {ok, Req};
run_validations(Req, [Validation | Rest]) ->
    case Validation(Req) of
        {ok, NewReq} ->
            run_validations(NewReq, Rest);
        {error, Reason} ->
            {error, Reason}
    end.

validate_method(Req) ->
    Method = cowboy_req:method(Req),
    AllowedMethods = [<<"GET">>, <<"POST">>, <<"PUT">>, <<"DELETE">>, <<"OPTIONS">>, <<"HEAD">>],
    
    case lists:member(Method, AllowedMethods) of
        true ->
            {ok, Req};
        false ->
            log_security_event(invalid_method, Req, #{method => Method}),
            {error, invalid_method}
    end.

validate_headers(Req) ->
    % Check for suspicious headers
    SuspiciousHeaders = [
        <<"x-forwarded-host">>,
        <<"x-original-url">>,
        <<"x-rewrite-url">>
    ],
    
    case check_suspicious_headers(Req, SuspiciousHeaders) of
        ok ->
            {ok, Req};
        {error, Reason} ->
            {error, Reason}
    end.

check_suspicious_headers(_Req, []) ->
    ok;
check_suspicious_headers(Req, [Header | Rest]) ->
    case cowboy_req:header(Header, Req) of
        undefined ->
            check_suspicious_headers(Req, Rest);
        Value ->
            log_security_event(suspicious_header, Req, #{header => Header, value => Value}),
            {error, suspicious_header}
    end.

validate_content_length(Req) ->
    case cowboy_req:header(<<"content-length">>, Req) of
        undefined ->
            {ok, Req};
        LengthBin ->
            try
                Length = binary_to_integer(LengthBin),
                MaxLength = 100 * 1024 * 1024, % 100MB max
                
                if Length > MaxLength ->
                    log_security_event(content_too_large, Req, #{content_length => Length}),
                    {error, content_too_large};
                true ->
                    {ok, Req}
                end
            catch
                error:badarg ->
                    log_security_event(invalid_content_length, Req, #{content_length => LengthBin}),
                    {error, invalid_content_length}
            end
    end.

validate_user_agent(Req) ->
    case cowboy_req:header(<<"user-agent">>, Req) of
        undefined ->
            log_security_event(missing_user_agent, Req, #{}),
            {ok, Req}; % Allow but log
        UserAgent ->
            % Check for suspicious patterns
            SuspiciousPatterns = [
                <<"sqlmap">>,
                <<"nikto">>,
                <<"nmap">>,
                <<"masscan">>,
                <<"curl">>, % Be careful with this in production
                <<"wget">>,
                <<"python-requests">>,
                <<"bot">>
            ],
            
            case check_suspicious_user_agent(UserAgent, SuspiciousPatterns) of
                ok ->
                    {ok, Req};
                suspicious ->
                    log_security_event(suspicious_user_agent, Req, #{user_agent => UserAgent}),
                    {ok, Req} % Allow but log
            end
    end.

check_suspicious_user_agent(_UserAgent, []) ->
    ok;
check_suspicious_user_agent(UserAgent, [Pattern | Rest]) ->
    case binary:match(string:lowercase(UserAgent), string:lowercase(Pattern)) of
        nomatch ->
            check_suspicious_user_agent(UserAgent, Rest);
        _ ->
            suspicious
    end.

check_suspicious_patterns(Req) ->
    Path = cowboy_req:path(Req),
    QueryString = cowboy_req:qs(Req),
    
    % Check for common attack patterns
    SuspiciousPatterns = [
        <<"../">>,
        <<"..\\">>,
        <<"<script">>,
        <<"javascript:">>,
        <<"vbscript:">>,
        <<"onload=">>,
        <<"onerror=">>,
        <<"eval(">>,
        <<"union select">>,
        <<"drop table">>,
        <<"insert into">>,
        <<"delete from">>,
        <<"update set">>,
        <<"exec(">>,
        <<"system(">>,
        <<"cmd.exe">>,
        <<"/bin/sh">>,
        <<"passwd">>,
        <<"shadow">>,
        <<"etc/passwd">>
    ],
    
    CombinedInput = <<Path/binary, "?", QueryString/binary>>,
    
    case check_patterns(string:lowercase(CombinedInput), SuspiciousPatterns) of
        ok ->
            {ok, Req};
        {suspicious, Pattern} ->
            log_security_event(suspicious_pattern, Req, #{
                pattern => Pattern,
                path => Path,
                query_string => QueryString
            }),
            {error, suspicious_pattern}
    end.

check_patterns(_Input, []) ->
    ok;
check_patterns(Input, [Pattern | Rest]) ->
    case binary:match(Input, Pattern) of
        nomatch ->
            check_patterns(Input, Rest);
        _ ->
            {suspicious, Pattern}
    end.

get_csrf_token_from_request(Req) ->
    % Try header first
    case cowboy_req:header(<<"x-csrf-token">>, Req) of
        undefined ->
            % Try query parameter
            case cowboy_req:match_qs([{csrf_token, [], undefined}], Req) of
                #{csrf_token := undefined} ->
                    {error, missing_token};
                #{csrf_token := Token} ->
                    {ok, Token}
            end;
        Token ->
            {ok, Token}
    end.

validate_csrf_token(Token, _Req) ->
    try
        % Decode token
        DecodedToken = base64:decode(Token),
        [TokenData, Signature] = binary:split(DecodedToken, <<".">>),
        
        % Verify signature
        Secret = get_csrf_secret(),
        ExpectedSignature = crypto:mac(hmac, sha256, Secret, TokenData),
        
        case crypto:hash_equals(Signature, ExpectedSignature) of
            true ->
                % Check token in database
                Payload = jiffy:decode(TokenData, [return_maps]),
                UserId = maps:get(<<"user_id">>, Payload),
                
                SQL = "SELECT expires_at FROM csrf_tokens 
                       WHERE user_id = $1 AND token = $2 AND expires_at > NOW()",
                
                case aethertalk_db:query(SQL, [UserId, Token]) of
                    {ok, {_Columns, [_]}} ->
                        true;
                    _ ->
                        false
                end;
            false ->
                false
        end
    catch
        _:_ ->
            false
    end.

get_csrf_secret() ->
    % In production, this should be loaded from environment or secure storage
    case application:get_env(aethertalk, csrf_secret) of
        {ok, Secret} ->
            Secret;
        undefined ->
            % Generate and store a secret (for development only)
            Secret = crypto:strong_rand_bytes(32),
            application:set_env(aethertalk, csrf_secret, Secret),
            Secret
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