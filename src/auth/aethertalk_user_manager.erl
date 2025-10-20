%%%-------------------------------------------------------------------
%% @doc AetherTalk user management system
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_user_manager).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    register_user/1,
    authenticate_user/2,
    get_user/1,
    get_user_by_phone/1,
    update_user/2,
    delete_user/1,
    change_password/3,
    verify_user/1,
    set_user_online/2,
    get_user_contacts/1,
    add_contact/2,
    remove_contact/2,
    block_user/2,
    unblock_user/2,
    is_user_blocked/2,
    update_user_settings/2,
    get_user_settings/1
]).

-include("aethertalk.hrl").

-record(state, {}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    io:format("User manager started~n"),
    {ok, #state{}}.

handle_call({register_user, UserData}, _From, State) ->
    Result = do_register_user(UserData),
    {reply, Result, State};

handle_call({authenticate_user, PhoneNumber, Password}, _From, State) ->
    Result = do_authenticate_user(PhoneNumber, Password),
    {reply, Result, State};

handle_call({get_user, UserId}, _From, State) ->
    Result = do_get_user(UserId),
    {reply, Result, State};

handle_call({get_user_by_phone, PhoneNumber}, _From, State) ->
    Result = do_get_user_by_phone(PhoneNumber),
    {reply, Result, State};

handle_call({update_user, UserId, Updates}, _From, State) ->
    Result = do_update_user(UserId, Updates),
    {reply, Result, State};

handle_call({delete_user, UserId}, _From, State) ->
    Result = do_delete_user(UserId),
    {reply, Result, State};

handle_call({change_password, UserId, OldPassword, NewPassword}, _From, State) ->
    Result = do_change_password(UserId, OldPassword, NewPassword),
    {reply, Result, State};

handle_call({verify_user, UserId}, _From, State) ->
    Result = do_verify_user(UserId),
    {reply, Result, State};

handle_call({set_user_online, UserId, IsOnline}, _From, State) ->
    Result = do_set_user_online(UserId, IsOnline),
    {reply, Result, State};

handle_call({get_user_contacts, UserId}, _From, State) ->
    Result = do_get_user_contacts(UserId),
    {reply, Result, State};

handle_call({add_contact, UserId, ContactUserId}, _From, State) ->
    Result = do_add_contact(UserId, ContactUserId),
    {reply, Result, State};

handle_call({remove_contact, UserId, ContactUserId}, _From, State) ->
    Result = do_remove_contact(UserId, ContactUserId),
    {reply, Result, State};

handle_call({block_user, BlockerId, BlockedId}, _From, State) ->
    Result = do_block_user(BlockerId, BlockedId),
    {reply, Result, State};

handle_call({unblock_user, BlockerId, BlockedId}, _From, State) ->
    Result = do_unblock_user(BlockerId, BlockedId),
    {reply, Result, State};

handle_call({is_user_blocked, UserId1, UserId2}, _From, State) ->
    Result = do_is_user_blocked(UserId1, UserId2),
    {reply, Result, State};

handle_call({update_user_settings, UserId, Settings}, _From, State) ->
    Result = do_update_user_settings(UserId, Settings),
    {reply, Result, State};

handle_call({get_user_settings, UserId}, _From, State) ->
    Result = do_get_user_settings(UserId),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Public API functions

register_user(UserData) ->
    gen_server:call(?MODULE, {register_user, UserData}).

authenticate_user(PhoneNumber, Password) ->
    gen_server:call(?MODULE, {authenticate_user, PhoneNumber, Password}).

get_user(UserId) ->
    gen_server:call(?MODULE, {get_user, UserId}).

get_user_by_phone(PhoneNumber) ->
    gen_server:call(?MODULE, {get_user_by_phone, PhoneNumber}).

update_user(UserId, Updates) ->
    gen_server:call(?MODULE, {update_user, UserId, Updates}).

delete_user(UserId) ->
    gen_server:call(?MODULE, {delete_user, UserId}).

change_password(UserId, OldPassword, NewPassword) ->
    gen_server:call(?MODULE, {change_password, UserId, OldPassword, NewPassword}).

verify_user(UserId) ->
    gen_server:call(?MODULE, {verify_user, UserId}).

set_user_online(UserId, IsOnline) ->
    gen_server:call(?MODULE, {set_user_online, UserId, IsOnline}).

get_user_contacts(UserId) ->
    gen_server:call(?MODULE, {get_user_contacts, UserId}).

add_contact(UserId, ContactUserId) ->
    gen_server:call(?MODULE, {add_contact, UserId, ContactUserId}).

remove_contact(UserId, ContactUserId) ->
    gen_server:call(?MODULE, {remove_contact, UserId, ContactUserId}).

block_user(BlockerId, BlockedId) ->
    gen_server:call(?MODULE, {block_user, BlockerId, BlockedId}).

unblock_user(BlockerId, BlockedId) ->
    gen_server:call(?MODULE, {unblock_user, BlockerId, BlockedId}).

is_user_blocked(UserId1, UserId2) ->
    gen_server:call(?MODULE, {is_user_blocked, UserId1, UserId2}).

update_user_settings(UserId, Settings) ->
    gen_server:call(?MODULE, {update_user_settings, UserId, Settings}).

get_user_settings(UserId) ->
    gen_server:call(?MODULE, {get_user_settings, UserId}).

%% Internal functions

do_register_user(UserData) ->
    PhoneNumber = maps:get(phone_number, UserData),
    Password = maps:get(password, UserData),
    
    % Validate input
    case validate_registration_data(UserData) of
        ok ->
            % Check if user already exists
            case do_get_user_by_phone(PhoneNumber) of
                {error, not_found} ->
                    % Hash password
                    {ok, PasswordHash} = bcrypt:hashpw(Password, bcrypt:gen_salt()),
                    
                    % Prepare user data
                    UserRecord = #{
                        phone_number => PhoneNumber,
                        username => maps:get(username, UserData, null),
                        display_name => maps:get(display_name, UserData, null),
                        email => maps:get(email, UserData, null),
                        password_hash => PasswordHash,
                        language => maps:get(language, UserData, "en"),
                        timezone => maps:get(timezone, UserData, "UTC")
                    },
                    
                    % Insert user into database
                    SQL = "INSERT INTO users (phone_number, username, display_name, email, password_hash, language, timezone) 
                           VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id, created_at",
                    Params = [
                        maps:get(phone_number, UserRecord),
                        maps:get(username, UserRecord),
                        maps:get(display_name, UserRecord),
                        maps:get(email, UserRecord),
                        maps:get(password_hash, UserRecord),
                        maps:get(language, UserRecord),
                        maps:get(timezone, UserRecord)
                    ],
                    
                    case aethertalk_db:query(SQL, Params) of
                        {ok, {_Columns, [{UserId, CreatedAt}]}} ->
                            io:format("User registered successfully: ~p~n", [UserId]),
                            {ok, #{
                                id => UserId,
                                phone_number => PhoneNumber,
                                username => maps:get(username, UserRecord),
                                display_name => maps:get(display_name, UserRecord),
                                email => maps:get(email, UserRecord),
                                language => maps:get(language, UserRecord),
                                timezone => maps:get(timezone, UserRecord),
                                created_at => CreatedAt
                            }};
                        {error, Reason} ->
                            io:format("Failed to register user: ~p~n", [Reason]),
                            {error, registration_failed}
                    end;
                {ok, _ExistingUser} ->
                    {error, user_already_exists};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, ValidationError} ->
            {error, ValidationError}
    end.

do_authenticate_user(PhoneNumber, Password) ->
    case do_get_user_by_phone(PhoneNumber) of
        {ok, User} ->
            PasswordHash = maps:get(password_hash, User),
            case bcrypt:checkpw(Password, PasswordHash) of
                true ->
                    UserId = maps:get(id, User),
                    % Update last seen
                    do_set_user_online(UserId, true),
                    {ok, User};
                false ->
                    {error, invalid_credentials}
            end;
        {error, not_found} ->
            {error, invalid_credentials};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_user(UserId) ->
    SQL = "SELECT id, phone_number, username, display_name, email, profile_picture_url, 
                  status, is_online, last_seen, is_verified, is_business, language, timezone,
                  privacy_settings, notification_settings, created_at, updated_at
           FROM users WHERE id = $1",
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, []}} ->
            {error, not_found};
        {ok, {_Columns, [Row]}} ->
            {ok, row_to_user_map(Row)};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_user_by_phone(PhoneNumber) ->
    SQL = "SELECT id, phone_number, username, display_name, email, password_hash,
                  profile_picture_url, status, is_online, last_seen, is_verified, 
                  is_business, language, timezone, privacy_settings, notification_settings,
                  created_at, updated_at
           FROM users WHERE phone_number = $1",
    case aethertalk_db:query(SQL, [PhoneNumber]) of
        {ok, {_Columns, []}} ->
            {error, not_found};
        {ok, {_Columns, [Row]}} ->
            {ok, row_to_user_map_with_password(Row)};
        {error, Reason} ->
            {error, Reason}
    end.

do_update_user(UserId, Updates) ->
    % Build dynamic update query
    {SetClause, Params} = build_update_clause(Updates, 2),
    SQL = "UPDATE users SET " ++ SetClause ++ ", updated_at = NOW() WHERE id = $1 RETURNING updated_at",
    
    case aethertalk_db:query(SQL, [UserId | Params]) of
        {ok, {_Columns, [{UpdatedAt}]}} ->
            {ok, #{updated_at => UpdatedAt}};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_delete_user(UserId) ->
    SQL = "DELETE FROM users WHERE id = $1",
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, 1} ->
            ok;
        {ok, 0} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_change_password(UserId, OldPassword, NewPassword) ->
    case do_get_user(UserId) of
        {ok, _User} ->
            % Get current password hash
            SQL = "SELECT password_hash FROM users WHERE id = $1",
            case aethertalk_db:query(SQL, [UserId]) of
                {ok, {_Columns, [{PasswordHash}]}} ->
                    case bcrypt:checkpw(OldPassword, PasswordHash) of
                        true ->
                            % Hash new password
                            {ok, NewPasswordHash} = bcrypt:hashpw(NewPassword, bcrypt:gen_salt()),
                            UpdateSQL = "UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2",
                            case aethertalk_db:query(UpdateSQL, [NewPasswordHash, UserId]) of
                                {ok, 1} ->
                                    ok;
                                {error, Reason} ->
                                    {error, Reason}
                            end;
                        false ->
                            {error, invalid_old_password}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_verify_user(UserId) ->
    SQL = "UPDATE users SET is_verified = TRUE, updated_at = NOW() WHERE id = $1",
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, 1} ->
            ok;
        {ok, 0} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_set_user_online(UserId, IsOnline) ->
    SQL = "UPDATE users SET is_online = $1, last_seen = NOW(), updated_at = NOW() WHERE id = $2",
    case aethertalk_db:query(SQL, [IsOnline, UserId]) of
        {ok, 1} ->
            % Update presence in Redis for real-time updates
            aethertalk_presence_manager:update_presence(UserId, IsOnline),
            ok;
        {ok, 0} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_user_contacts(UserId) ->
    SQL = "SELECT c.id, c.contact_user_id, c.display_name, c.is_blocked, c.is_favorite, c.added_at,
                  u.username, u.display_name as user_display_name, u.profile_picture_url, 
                  u.status, u.is_online, u.last_seen
           FROM contacts c
           JOIN users u ON c.contact_user_id = u.id
           WHERE c.user_id = $1 AND c.is_blocked = FALSE
           ORDER BY c.display_name, u.display_name",
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, Rows}} ->
            Contacts = [row_to_contact_map(Row) || Row <- Rows],
            {ok, Contacts};
        {error, Reason} ->
            {error, Reason}
    end.

do_add_contact(UserId, ContactUserId) ->
    % Check if contact already exists
    CheckSQL = "SELECT id FROM contacts WHERE user_id = $1 AND contact_user_id = $2",
    case aethertalk_db:query(CheckSQL, [UserId, ContactUserId]) of
        {ok, {_Columns, []}} ->
            % Add new contact
            InsertSQL = "INSERT INTO contacts (user_id, contact_user_id) VALUES ($1, $2) RETURNING id, added_at",
            case aethertalk_db:query(InsertSQL, [UserId, ContactUserId]) of
                {ok, {_Cols, [{ContactId, AddedAt}]}} ->
                    {ok, #{id => ContactId, added_at => AddedAt}};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, {_Columns, _}} ->
            {error, contact_already_exists};
        {error, Reason} ->
            {error, Reason}
    end.

do_remove_contact(UserId, ContactUserId) ->
    SQL = "DELETE FROM contacts WHERE user_id = $1 AND contact_user_id = $2",
    case aethertalk_db:query(SQL, [UserId, ContactUserId]) of
        {ok, 1} ->
            ok;
        {ok, 0} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_block_user(BlockerId, BlockedId) ->
    SQL = "INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2) 
           ON CONFLICT (blocker_id, blocked_id) DO NOTHING RETURNING id",
    case aethertalk_db:query(SQL, [BlockerId, BlockedId]) of
        {ok, {_Columns, [{BlockId}]}} ->
            {ok, #{id => BlockId}};
        {ok, {_Columns, []}} ->
            {error, already_blocked};
        {error, Reason} ->
            {error, Reason}
    end.

do_unblock_user(BlockerId, BlockedId) ->
    SQL = "DELETE FROM user_blocks WHERE blocker_id = $1 AND blocked_id = $2",
    case aethertalk_db:query(SQL, [BlockerId, BlockedId]) of
        {ok, 1} ->
            ok;
        {ok, 0} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_is_user_blocked(UserId1, UserId2) ->
    SQL = "SELECT 1 FROM user_blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)",
    case aethertalk_db:query(SQL, [UserId1, UserId2]) of
        {ok, {_Columns, []}} ->
            {ok, false};
        {ok, {_Columns, _}} ->
            {ok, true};
        {error, Reason} ->
            {error, Reason}
    end.

do_update_user_settings(UserId, Settings) ->
    % Settings is a map of setting_key => setting_value
    InsertValues = maps:fold(fun(Key, Value, Acc) ->
        EncodedValue = jsx:encode(Value),
        ["($1, '" ++ binary_to_list(Key) ++ "', '" ++ binary_to_list(EncodedValue) ++ "')" | Acc]
    end, [], Settings),
    
    ValuesClause = string:join(InsertValues, ", "),
    SQL = "INSERT INTO user_settings (user_id, setting_key, setting_value) VALUES " ++ ValuesClause ++
          " ON CONFLICT (user_id, setting_key) DO UPDATE SET setting_value = EXCLUDED.setting_value, updated_at = NOW()",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, _} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

do_get_user_settings(UserId) ->
    SQL = "SELECT setting_key, setting_value FROM user_settings WHERE user_id = $1",
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, Rows}} ->
            Settings = maps:from_list([{Key, jsx:decode(Value)} || {Key, Value} <- Rows]),
            {ok, Settings};
        {error, Reason} ->
            {error, Reason}
    end.

%% Helper functions

validate_registration_data(UserData) ->
    PhoneNumber = maps:get(phone_number, UserData, undefined),
    Password = maps:get(password, UserData, undefined),
    
    case {PhoneNumber, Password} of
        {undefined, _} ->
            {error, missing_phone_number};
        {_, undefined} ->
            {error, missing_password};
        {Phone, Pass} when is_binary(Phone), is_binary(Pass) ->
            case byte_size(Pass) >= ?PASSWORD_MIN_LENGTH of
                true ->
                    case validate_phone_number(Phone) of
                        true -> ok;
                        false -> {error, invalid_phone_number}
                    end;
                false ->
                    {error, password_too_short}
            end;
        _ ->
            {error, invalid_input}
    end.

validate_phone_number(PhoneNumber) ->
    % Basic phone number validation (can be enhanced)
    case re:run(PhoneNumber, "^\\+?[1-9]\\d{1,14}$") of
        {match, _} -> true;
        nomatch -> false
    end.

row_to_user_map({Id, PhoneNumber, Username, DisplayName, Email, ProfilePictureUrl, 
                 Status, IsOnline, LastSeen, IsVerified, IsBusiness, Language, Timezone,
                 PrivacySettings, NotificationSettings, CreatedAt, UpdatedAt}) ->
    #{
        id => Id,
        phone_number => PhoneNumber,
        username => Username,
        display_name => DisplayName,
        email => Email,
        profile_picture_url => ProfilePictureUrl,
        status => Status,
        is_online => IsOnline,
        last_seen => LastSeen,
        is_verified => IsVerified,
        is_business => IsBusiness,
        language => Language,
        timezone => Timezone,
        privacy_settings => case PrivacySettings of
            null -> #{};
            _ -> jsx:decode(PrivacySettings)
        end,
        notification_settings => case NotificationSettings of
            null -> #{};
            _ -> jsx:decode(NotificationSettings)
        end,
        created_at => CreatedAt,
        updated_at => UpdatedAt
    }.

row_to_user_map_with_password({Id, PhoneNumber, Username, DisplayName, Email, PasswordHash,
                               ProfilePictureUrl, Status, IsOnline, LastSeen, IsVerified, 
                               IsBusiness, Language, Timezone, PrivacySettings, NotificationSettings,
                               CreatedAt, UpdatedAt}) ->
    #{
        id => Id,
        phone_number => PhoneNumber,
        username => Username,
        display_name => DisplayName,
        email => Email,
        password_hash => PasswordHash,
        profile_picture_url => ProfilePictureUrl,
        status => Status,
        is_online => IsOnline,
        last_seen => LastSeen,
        is_verified => IsVerified,
        is_business => IsBusiness,
        language => Language,
        timezone => Timezone,
        privacy_settings => case PrivacySettings of
            null -> #{};
            _ -> jsx:decode(PrivacySettings)
        end,
        notification_settings => case NotificationSettings of
            null -> #{};
            _ -> jsx:decode(NotificationSettings)
        end,
        created_at => CreatedAt,
        updated_at => UpdatedAt
    }.

row_to_contact_map({ContactId, ContactUserId, ContactDisplayName, IsBlocked, IsFavorite, AddedAt,
                    Username, UserDisplayName, ProfilePictureUrl, Status, IsOnline, LastSeen}) ->
    #{
        id => ContactId,
        contact_user_id => ContactUserId,
        display_name => ContactDisplayName,
        is_blocked => IsBlocked,
        is_favorite => IsFavorite,
        added_at => AddedAt,
        user => #{
            username => Username,
            display_name => UserDisplayName,
            profile_picture_url => ProfilePictureUrl,
            status => Status,
            is_online => IsOnline,
            last_seen => LastSeen
        }
    }.

build_update_clause(Updates, StartParam) ->
    {SetParts, Params, _} = maps:fold(fun(Key, Value, {Parts, ParamList, ParamNum}) ->
        Part = atom_to_list(Key) ++ " = $" ++ integer_to_list(ParamNum),
        {[Part | Parts], [Value | ParamList], ParamNum + 1}
    end, {[], [], StartParam}, Updates),
    
    {string:join(lists:reverse(SetParts), ", "), lists:reverse(Params)}.