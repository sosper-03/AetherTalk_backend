%%%-------------------------------------------------------------------
%% @doc Authentication handler
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_auth_handler).

-export([init/2]).

init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Path = cowboy_req:path(Req0),
    handle_request(Method, Path, Req0, State).

handle_request(<<"POST">>, <<"/api/v1/auth/register">>, Req0, State) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    
    % Debug logging
    io:format("Received registration request body: ~p~n", [Body]),
    
    Result = try
        Data = jsx:decode(Body, [return_maps]),
        io:format("Parsed JSON data: ~p~n", [Data]),
        case aethertalk_auth:register(Data) of
            {ok, User} ->
                Response = #{
                    success => true,
                    user => User,
                    message => <<"User registered successfully">>
                },
                {201, jsx:encode(Response)};
            {error, Reason} ->
                io:format("Registration error: ~p~n", [Reason]),
                Response = #{
                    success => false,
                    error => Reason
                },
                {400, jsx:encode(Response)}
        end
    catch
        Error:ErrorReason ->
            io:format("JSON parsing error: ~p:~p~n", [Error, ErrorReason]),
            {400, jsx:encode(#{error => <<"Invalid JSON">>})}
    end,
    
    {StatusCode, ResponseBody} = Result,
    Req2 = cowboy_req:reply(StatusCode,
        #{<<"content-type">> => <<"application/json">>},
        ResponseBody,
        Req1),
    {ok, Req2, State};

handle_request(<<"POST">>, <<"/api/v1/auth/login">>, Req0, State) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    
    Result = try
        Data = jsx:decode(Body, [return_maps]),
        case aethertalk_auth:login(Data) of
            {ok, Token, User} ->
                Response = #{
                    success => true,
                    token => Token,
                    user => User
                },
                {200, jsx:encode(Response)};
            {error, Reason} ->
                Response = #{
                    success => false,
                    error => Reason
                },
                {401, jsx:encode(Response)}
        end
    catch
        _:_ ->
            {400, jsx:encode(#{error => <<"Invalid JSON">>})}
    end,
    
    {StatusCode, ResponseBody} = Result,
    Req2 = cowboy_req:reply(StatusCode,
        #{<<"content-type">> => <<"application/json">>},
        ResponseBody,
        Req1),
    {ok, Req2, State};

handle_request(<<"POST">>, <<"/api/v1/auth/logout">>, Req0, State) ->
    case cowboy_req:header(<<"authorization">>, Req0) of
        undefined ->
            Req = cowboy_req:reply(401,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Authorization header required">>}),
                Req0),
            {ok, Req, State};
        AuthHeader ->
            case aethertalk_auth:logout(AuthHeader) of
                ok ->
                    Response = #{
                        success => true,
                        message => <<"Logged out successfully">>
                    },
                    Req = cowboy_req:reply(200,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(Response),
                        Req0),
                    {ok, Req, State};
                {error, Reason} ->
                    Response = #{
                        success => false,
                        error => Reason
                    },
                    Req = cowboy_req:reply(401,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(Response),
                        Req0),
                    {ok, Req, State}
            end
    end;

handle_request(_, _, Req0, State) ->
    Req = cowboy_req:reply(405,
        #{<<"content-type">> => <<"application/json">>},
        jsx:encode(#{error => <<"Method not allowed">>}),
        Req0),
    {ok, Req, State}.