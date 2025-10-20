%%%-------------------------------------------------------------------
%% @doc AetherTalk environment variable loader
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_env).

-export([
    load_env_file/1,
    get_env/2,
    get_env/3,
    get_database_config/0,
    get_redis_config/0,
    get_firebase_config/0
]).

%% @doc Load environment variables from .env file
load_env_file(FilePath) ->
    case file:read_file(FilePath) of
        {ok, Content} ->
            Lines = binary:split(Content, <<"\n">>, [global]),
            lists:foreach(fun parse_env_line/1, Lines),
            ok;
        {error, Reason} ->
            io:format("Warning: Could not load .env file ~s: ~p~n", [FilePath, Reason]),
            ok
    end.

%% @doc Parse a single environment variable line
parse_env_line(Line) ->
    case binary:split(Line, <<"=">>, []) of
        [Key, Value] ->
            CleanKey = string:trim(binary_to_list(Key)),
            CleanValue = string:trim(binary_to_list(Value)),
            case {CleanKey, CleanValue} of
                {[$# | _], _} -> ok; % Skip comments
                {"", _} -> ok; % Skip empty keys
                {_, ""} -> ok; % Skip empty values
                _ ->
                    os:putenv(CleanKey, CleanValue)
            end;
        _ ->
            ok % Skip malformed lines
    end.

%% @doc Get environment variable with default
get_env(Key, Default) ->
    case os:getenv(Key) of
        false -> Default;
        Value -> Value
    end.

%% @doc Get environment variable with type conversion
get_env(Key, Default, Type) ->
    Value = get_env(Key, Default),
    convert_type(Value, Type).

%% @doc Convert string value to specified type
convert_type(Value, string) -> Value;
convert_type(Value, binary) -> list_to_binary(Value);
convert_type(Value, integer) when is_list(Value) ->
    try list_to_integer(Value)
    catch _:_ -> 0
    end;
convert_type(Value, integer) -> Value;
convert_type("true", boolean) -> true;
convert_type("false", boolean) -> false;
convert_type(Value, boolean) when is_boolean(Value) -> Value;
convert_type(_, boolean) -> false.

%% @doc Get database configuration from environment
get_database_config() ->
    [
        {host, get_env("AETHERTALK_DB_HOST", "localhost")},
        {port, get_env("AETHERTALK_DB_PORT", 5432, integer)},
        {database, get_env("AETHERTALK_DB_NAME", "aethertalk")},
        {username, get_env("AETHERTALK_DB_USER", "aethertalk")},
        {password, get_env("AETHERTALK_DB_PASS", "")},
        {ssl, get_env("AETHERTALK_DB_SSL", false, boolean)},
        {pool_size, 1},
        {max_overflow, 1}
    ].

%% @doc Get Redis configuration from environment
get_redis_config() ->
    [
        {host, get_env("AETHERTALK_REDIS_HOST", "localhost")},
        {port, get_env("AETHERTALK_REDIS_PORT", 6379, integer)},
        {password, get_env("AETHERTALK_REDIS_PASSWORD", undefined)},
        {database, 0},
        {pool_size, 3}
    ].

%% @doc Get Firebase configuration from environment
get_firebase_config() ->
    [
        {project_id, get_env("FIREBASE_PROJECT_ID", "")},
        {api_key, get_env("FIREBASE_API_KEY", "")},
        {auth_domain, get_env("FIREBASE_AUTH_DOMAIN", "")},
        {storage_bucket, get_env("FIREBASE_STORAGE_BUCKET", "")},
        {messaging_sender_id, get_env("FIREBASE_MESSAGING_SENDER_ID", "")},
        {app_id, get_env("FIREBASE_APP_ID", "")},
        {measurement_id, get_env("FIREBASE_MEASUREMENT_ID", "")},
        {admin_sdk_path, get_env("FIREBASE_ADMIN_SDK_PATH", "config/firebase-admin-sdk.json")},
        {web_api_key, get_env("FIREBASE_WEB_API_KEY", "")}
    ].