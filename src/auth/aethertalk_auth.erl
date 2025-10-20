%%%-------------------------------------------------------------------
%% @doc AetherTalk authentication utilities
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_auth).

-export([
    generate_token/2,
    validate_token/1,
    refresh_token/1,
    revoke_token/1
]).

-include("aethertalk.hrl").

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
    {error, not_implemented}.