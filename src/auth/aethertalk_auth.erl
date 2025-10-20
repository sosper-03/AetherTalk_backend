%%%-------------------------------------------------------------------
%% @doc AetherTalk authentication utilities
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_auth).

-export([
    register/1,
    login/1,
    logout/1,
    generate_token/2,
    validate_token/1,
    refresh_token/1,
    revoke_token/1
]).

-include("aethertalk.hrl").

%% @doc Register a new user
register(UserData) ->
    case aethertalk_user_manager:register_user(UserData) of
        {ok, UserId} ->
            % Get the created user data
            case aethertalk_user_manager:get_user(UserId) of
                {ok, User} ->
                    {ok, User};
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

%% @doc Login user and generate token
login(LoginData) ->
    Username = maps:get(<<"username">>, LoginData, undefined),
    Password = maps:get(<<"password">>, LoginData, undefined),
    
    case {Username, Password} of
        {undefined, _} ->
            {error, <<"Username required">>};
        {_, undefined} ->
            {error, <<"Password required">>};
        {Username, Password} ->
            % Try to authenticate with username (could be phone number)
            case aethertalk_user_manager:authenticate_user(Username, Password) of
                {ok, UserId} ->
                    % Generate session ID
                    SessionId = generate_session_id(),
                    
                    % Generate token
                    case generate_token(UserId, SessionId) of
                        {ok, Token} ->
                            % Get user data
                            case aethertalk_user_manager:get_user(UserId) of
                                {ok, User} ->
                                    {ok, Token, User};
                                Error ->
                                    Error
                            end;
                        Error ->
                            Error
                    end;
                Error ->
                    Error
            end
    end.

%% @doc Logout user (revoke token)
logout(AuthHeader) ->
    case extract_token_from_header(AuthHeader) of
        {ok, Token} ->
            revoke_token(Token);
        Error ->
            Error
    end.

%% @doc Generate JWT token for user
generate_token(UserId, SessionId) ->
    JwtSecret = aethertalk_app:get_env(jwt_secret, <<"default_secret">>),
    
    Claims = #{
        <<"user_id">> => UserId,
        <<"session_id">> => SessionId,
        <<"iat">> => erlang:system_time(second),
        <<"exp">> => erlang:system_time(second) + ?SESSION_TIMEOUT
    },
    
    case jose_jwt:sign(jose_jwk:from_oct(JwtSecret), Claims) of
        {_JWS, Token} ->
            {ok, Token};
        Error ->
            io:format("Failed to generate token: ~p~n", [Error]),
            {error, token_generation_failed}
    end.

%% @doc Validate JWT token
validate_token(Token) ->
    JwtSecret = aethertalk_app:get_env(jwt_secret, <<"default_secret">>),
    
    try
        case jose_jwt:verify(jose_jwk:from_oct(JwtSecret), Token) of
            {true, Claims, _JWS} ->
                % Check expiration
                Now = erlang:system_time(second),
                Exp = maps:get(<<"exp">>, Claims, 0),
                case Now < Exp of
                    true ->
                        {ok, Claims};
                    false ->
                        {error, token_expired}
                end;
            {false, _Claims, _JWS} ->
                {error, invalid_token}
        end
    catch
        _:_ ->
            {error, invalid_token}
    end.

%% @doc Refresh JWT token
refresh_token(_RefreshToken) ->
    % This is a stub - in production you'd validate the refresh token
    % and generate a new access token
    {error, not_implemented}.

%% @doc Revoke JWT token
revoke_token(_Token) ->
    % This is a stub - in production you'd add the token to a blacklist
    ok.

%% Helper functions

%% @doc Generate a unique session ID
generate_session_id() ->
    list_to_binary(uuid:uuid_to_string(uuid:get_v4())).

%% @doc Extract token from Authorization header
extract_token_from_header(AuthHeader) ->
    case binary:split(AuthHeader, <<" ">>) of
        [<<"Bearer">>, Token] ->
            {ok, Token};
        _ ->
            {error, <<"Invalid authorization header format">>}
    end.