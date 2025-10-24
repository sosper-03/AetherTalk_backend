-module(aethertalk_utils).

-export([
    generate_uuid/0,
    format_timestamp/1,
    validate_email/1,
    validate_phone/1,
    sanitize_input/1,
    hash_password/1,
    verify_password/2,
    encode_base64/1,
    decode_base64/1,
    get_current_timestamp/0,
    format_error/1
]).

%% Generate a UUID v4
generate_uuid() ->
    uuid:uuid4().

%% Format timestamp to ISO 8601
format_timestamp(Timestamp) when is_integer(Timestamp) ->
    {{Year, Month, Day}, {Hour, Min, Sec}} = calendar:gregorian_seconds_to_datetime(Timestamp + 62167219200),
    io_lib:format("~4..0w-~2..0w-~2..0wT~2..0w:~2..0w:~2..0wZ", 
                  [Year, Month, Day, Hour, Min, Sec]);
format_timestamp(_) ->
    "Invalid timestamp".

%% Validate email format
validate_email(Email) when is_binary(Email) ->
    validate_email(binary_to_list(Email));
validate_email(Email) when is_list(Email) ->
    case re:run(Email, "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$") of
        {match, _} -> true;
        nomatch -> false
    end;
validate_email(_) ->
    false.

%% Validate phone number format (basic validation)
validate_phone(Phone) when is_binary(Phone) ->
    validate_phone(binary_to_list(Phone));
validate_phone(Phone) when is_list(Phone) ->
    case re:run(Phone, "^\\+?[1-9]\\d{1,14}$") of
        {match, _} -> true;
        nomatch -> false
    end;
validate_phone(_) ->
    false.

%% Sanitize input to prevent XSS and injection attacks
sanitize_input(Input) when is_binary(Input) ->
    sanitize_input(binary_to_list(Input));
sanitize_input(Input) when is_list(Input) ->
    % Remove potentially dangerous characters
    re:replace(Input, "[<>\"'&]", "", [global, {return, list}]);
sanitize_input(Input) ->
    Input.

%% Hash password using bcrypt
hash_password(Password) when is_binary(Password) ->
    hash_password(binary_to_list(Password));
hash_password(Password) when is_list(Password) ->
    {ok, Salt} = bcrypt:gen_salt(),
    {ok, Hash} = bcrypt:hashpw(Password, Salt),
    Hash;
hash_password(_) ->
    error.

%% Verify password against hash
verify_password(Password, Hash) when is_binary(Password) ->
    verify_password(binary_to_list(Password), Hash);
verify_password(Password, Hash) when is_list(Password), is_list(Hash) ->
    bcrypt:checkpw(Password, Hash);
verify_password(_, _) ->
    false.

%% Base64 encoding
encode_base64(Data) when is_binary(Data) ->
    base64:encode(Data);
encode_base64(Data) when is_list(Data) ->
    base64:encode(list_to_binary(Data));
encode_base64(_) ->
    error.

%% Base64 decoding
decode_base64(Data) when is_binary(Data) ->
    try
        base64:decode(Data)
    catch
        _:_ -> error
    end;
decode_base64(Data) when is_list(Data) ->
    decode_base64(list_to_binary(Data));
decode_base64(_) ->
    error.

%% Get current timestamp in seconds
get_current_timestamp() ->
    {MegaSecs, Secs, _MicroSecs} = os:timestamp(),
    MegaSecs * 1000000 + Secs.

%% Format error for consistent error responses
format_error(Error) when is_atom(Error) ->
    #{error => Error, message => atom_to_list(Error)};
format_error(Error) when is_binary(Error) ->
    #{error => Error, message => binary_to_list(Error)};
format_error(Error) when is_list(Error) ->
    #{error => list_to_binary(Error), message => Error};
format_error(Error) ->
    #{error => <<"unknown_error">>, message => io_lib:format("~p", [Error])}.