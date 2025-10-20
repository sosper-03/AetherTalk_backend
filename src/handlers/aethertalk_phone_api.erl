%% @doc Phone verification and calling API handlers
-module(aethertalk_phone_api).

-export([init/2]).

%% Cowboy handler callbacks
init(Req, State) ->
    Method = cowboy_req:method(Req),
    Path = cowboy_req:path(Req),
    
    try
        Response = handle_request(Method, Path, Req),
        {ok, Response, State}
    catch
        Error:Reason ->
            lager:error("Phone API error: ~p:~p", [Error, Reason]),
            ErrorResp = cowboy_req:reply(500, 
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"internal_server_error">>}),
                Req),
            {ok, ErrorResp, State}
    end.

%% Handle different API endpoints
handle_request(<<"POST">>, <<"/api/v1/phone/send-verification">>, Req) ->
    handle_send_verification(Req);

handle_request(<<"POST">>, <<"/api/v1/phone/verify-code">>, Req) ->
    handle_verify_code(Req);

handle_request(<<"POST">>, <<"/api/v1/phone/resend-code">>, Req) ->
    handle_resend_code(Req);

handle_request(<<"GET">>, <<"/api/v1/phone/verification-status">>, Req) ->
    handle_verification_status(Req);

handle_request(<<"POST">>, <<"/api/v1/phone/call">>, Req) ->
    handle_initiate_call(Req);

handle_request(Method, Path, Req) ->
    lager:warning("Unhandled phone API request: ~s ~s", [Method, Path]),
    cowboy_req:reply(404, 
        #{<<"content-type">> => <<"application/json">>},
        jsx:encode(#{error => <<"endpoint_not_found">>}),
        Req).

%%%===================================================================
%%% Phone Verification Handlers
%%%===================================================================

%% @private
handle_send_verification(Req) ->
    case get_json_body(Req) of
        {ok, #{<<"phone_number">> := PhoneNumber}} ->
            case aethertalk_phone_verification:send_verification_code(PhoneNumber) of
                {ok, MessageId} ->
                    cowboy_req:reply(200,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{
                            success => true,
                            message => <<"Verification code sent">>,
                            message_id => MessageId
                        }),
                        Req);
                {error, verification_disabled} ->
                    cowboy_req:reply(400,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"Phone verification is disabled">>}),
                        Req);
                {error, rate_limited} ->
                    cowboy_req:reply(429,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"Rate limited. Please wait before requesting another code.">>}),
                        Req);
                {error, send_failed} ->
                    cowboy_req:reply(500,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"Failed to send verification code">>}),
                        Req)
            end;
        {ok, _} ->
            cowboy_req:reply(400,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Missing phone_number field">>}),
                Req);
        {error, _} ->
            cowboy_req:reply(400,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Invalid JSON body">>}),
                Req)
    end.

%% @private
handle_verify_code(Req) ->
    case get_json_body(Req) of
        {ok, #{<<"phone_number">> := PhoneNumber, <<"code">> := Code}} ->
            case aethertalk_phone_verification:verify_code(PhoneNumber, Code) of
                {ok, verified} ->
                    cowboy_req:reply(200,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{
                            success => true,
                            message => <<"Phone number verified successfully">>,
                            verified => true
                        }),
                        Req);
                {error, code_not_found} ->
                    cowboy_req:reply(400,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"No verification code found for this phone number">>}),
                        Req);
                {error, code_expired} ->
                    cowboy_req:reply(400,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"Verification code has expired">>}),
                        Req);
                {error, max_attempts_exceeded} ->
                    cowboy_req:reply(400,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"Maximum verification attempts exceeded">>}),
                        Req);
                {error, {incorrect_code, RemainingAttempts}} ->
                    cowboy_req:reply(400,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{
                            error => <<"Incorrect verification code">>,
                            remaining_attempts => RemainingAttempts
                        }),
                        Req)
            end;
        {ok, _} ->
            cowboy_req:reply(400,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Missing phone_number or code field">>}),
                Req);
        {error, _} ->
            cowboy_req:reply(400,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Invalid JSON body">>}),
                Req)
    end.

%% @private
handle_resend_code(Req) ->
    case get_json_body(Req) of
        {ok, #{<<"phone_number">> := PhoneNumber}} ->
            case aethertalk_phone_verification:resend_code(PhoneNumber) of
                {ok, MessageId} ->
                    cowboy_req:reply(200,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{
                            success => true,
                            message => <<"Verification code resent">>,
                            message_id => MessageId
                        }),
                        Req);
                {error, no_pending_verification} ->
                    cowboy_req:reply(400,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"No pending verification for this phone number">>}),
                        Req);
                {error, {resend_too_soon, TimeRemaining}} ->
                    cowboy_req:reply(429,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{
                            error => <<"Please wait before requesting another code">>,
                            time_remaining => TimeRemaining
                        }),
                        Req);
                {error, send_failed} ->
                    cowboy_req:reply(500,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"Failed to resend verification code">>}),
                        Req)
            end;
        {ok, _} ->
            cowboy_req:reply(400,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Missing phone_number field">>}),
                Req);
        {error, _} ->
            cowboy_req:reply(400,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Invalid JSON body">>}),
                Req)
    end.

%% @private
handle_verification_status(Req) ->
    case cowboy_req:parse_qs(Req) of
        [{<<"phone_number">>, PhoneNumber}|_] ->
            case aethertalk_phone_verification:get_verification_status(PhoneNumber) of
                {ok, Status} ->
                    cowboy_req:reply(200,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(Status),
                        Req);
                {error, not_found} ->
                    cowboy_req:reply(404,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"Phone number not found">>}),
                        Req)
            end;
        _ ->
            cowboy_req:reply(400,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Missing phone_number parameter">>}),
                Req)
    end.

%% @private
handle_initiate_call(Req) ->
    % For demo purposes, return success
    case get_json_body(Req) of
        {ok, #{<<"phone_number">> := CalleePhone, <<"call_type">> := _CallType}} ->
            CallId = uuid:uuid4(),
            cowboy_req:reply(200,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{
                    success => true,
                    call_id => CallId,
                    status => <<"ringing">>,
                    message => <<"Call initiated to ", CalleePhone/binary>>
                }),
                Req);
        {ok, _} ->
            cowboy_req:reply(400,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Missing phone_number or call_type field">>}),
                Req);
        {error, _} ->
            cowboy_req:reply(400,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Invalid JSON body">>}),
                Req)
    end.

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @private
get_json_body(Req) ->
    case cowboy_req:has_body(Req) of
        true ->
            {ok, Body, _} = cowboy_req:read_body(Req),
            try
                {ok, jsx:decode(Body, [return_maps])}
            catch
                _:_ -> {error, invalid_json}
            end;
        false ->
            {error, no_body}
    end.