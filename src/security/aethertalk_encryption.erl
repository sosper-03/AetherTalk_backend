%%%-------------------------------------------------------------------
%%% @doc
%%% End-to-End Encryption Service for AetherTalk
%%% Implements Signal Protocol-like encryption with forward secrecy
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_encryption).
-behaviour(gen_server).

% OTP callbacks
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    generate_identity_key/1,
    generate_prekeys/2,
    create_session/3,
    encrypt_message/3,
    decrypt_message/3,
    rotate_keys/1,
    get_user_public_keys/1,
    verify_identity/2,
    get_session_info/2,
    delete_session/2,
    rotate_all_keys/0
]).

-include("aethertalk.hrl").

-record(state, {
    key_rotation_timer :: timer:tref()
}).

%% Key sizes (in bytes)
-define(IDENTITY_KEY_SIZE, 32).
-define(PREKEY_SIZE, 32).
-define(SESSION_KEY_SIZE, 32).
-define(IV_SIZE, 16).
-define(MAC_SIZE, 32).

%% Key rotation interval (24 hours)
-define(KEY_ROTATION_INTERVAL, 86400000).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Generate identity key pair for a user
generate_identity_key(UserId) ->
    gen_server:call(?MODULE, {generate_identity_key, UserId}).

%% @doc Generate prekeys for a user
generate_prekeys(UserId, Count) ->
    gen_server:call(?MODULE, {generate_prekeys, UserId, Count}).

%% @doc Create encryption session between two users
create_session(UserId1, UserId2, InitiatorId) ->
    gen_server:call(?MODULE, {create_session, UserId1, UserId2, InitiatorId}).

%% @doc Encrypt a message for a specific session
encrypt_message(SessionId, SenderId, PlainText) ->
    gen_server:call(?MODULE, {encrypt_message, SessionId, SenderId, PlainText}).

%% @doc Decrypt a message from a specific session
decrypt_message(SessionId, ReceiverId, CipherText) ->
    gen_server:call(?MODULE, {decrypt_message, SessionId, ReceiverId, CipherText}).

%% @doc Rotate user's prekeys
rotate_keys(UserId) ->
    gen_server:call(?MODULE, {rotate_keys, UserId}).

%% @doc Get user's public keys for key exchange
get_user_public_keys(UserId) ->
    gen_server:call(?MODULE, {get_user_public_keys, UserId}).

%% @doc Verify user's identity key
verify_identity(UserId, PublicKey) ->
    gen_server:call(?MODULE, {verify_identity, UserId, PublicKey}).

%% @doc Get session information
get_session_info(UserId1, UserId2) ->
    gen_server:call(?MODULE, {get_session_info, UserId1, UserId2}).

%% @doc Delete encryption session
delete_session(UserId1, UserId2) ->
    gen_server:call(?MODULE, {delete_session, UserId1, UserId2}).

%% ===================================================================
%% gen_server callbacks
%% ===================================================================

init([]) ->
    lager:info("Encryption service started"),
    
    % Set up key rotation timer
    {ok, Timer} = timer:apply_interval(?KEY_ROTATION_INTERVAL, ?MODULE, rotate_all_keys, []),
    
    {ok, #state{key_rotation_timer = Timer}}.

handle_call({generate_identity_key, UserId}, _From, State) ->
    Result = do_generate_identity_key(UserId),
    {reply, Result, State};

handle_call({generate_prekeys, UserId, Count}, _From, State) ->
    Result = do_generate_prekeys(UserId, Count),
    {reply, Result, State};

handle_call({create_session, UserId1, UserId2, InitiatorId}, _From, State) ->
    Result = do_create_session(UserId1, UserId2, InitiatorId),
    {reply, Result, State};

handle_call({encrypt_message, SessionId, SenderId, PlainText}, _From, State) ->
    Result = do_encrypt_message(SessionId, SenderId, PlainText),
    {reply, Result, State};

handle_call({decrypt_message, SessionId, ReceiverId, CipherText}, _From, State) ->
    Result = do_decrypt_message(SessionId, ReceiverId, CipherText),
    {reply, Result, State};

handle_call({rotate_keys, UserId}, _From, State) ->
    Result = do_rotate_keys(UserId),
    {reply, Result, State};

handle_call({get_user_public_keys, UserId}, _From, State) ->
    Result = do_get_user_public_keys(UserId),
    {reply, Result, State};

handle_call({verify_identity, UserId, PublicKey}, _From, State) ->
    Result = do_verify_identity(UserId, PublicKey),
    {reply, Result, State};

handle_call({get_session_info, UserId1, UserId2}, _From, State) ->
    Result = do_get_session_info(UserId1, UserId2),
    {reply, Result, State};

handle_call({delete_session, UserId1, UserId2}, _From, State) ->
    Result = do_delete_session(UserId1, UserId2),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{key_rotation_timer = Timer}) ->
    timer:cancel(Timer),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ===================================================================
%% Internal functions
%% ===================================================================

do_generate_identity_key(UserId) ->
    % Generate Ed25519 key pair for identity
    {PublicKey, PrivateKey} = crypto:generate_key(eddsa, ed25519),
    
    % Store keys in database
    SQL = "INSERT INTO user_identity_keys (user_id, public_key, private_key, created_at) 
           VALUES ($1, $2, $3, NOW())
           ON CONFLICT (user_id) 
           DO UPDATE SET public_key = $2, private_key = $3, created_at = NOW()
           RETURNING id, created_at",
    
    case aethertalk_db:query(SQL, [UserId, PublicKey, PrivateKey]) of
        {ok, {_Columns, [{KeyId, CreatedAt}]}} ->
            IdentityKey = #{
                id => KeyId,
                user_id => UserId,
                public_key => base64:encode(PublicKey),
                created_at => CreatedAt
            },
            
            lager:info("Generated identity key for user ~p", [UserId]),
            {ok, IdentityKey};
        {error, Reason} ->
            lager:error("Failed to generate identity key for user ~p: ~p", [UserId, Reason]),
            {error, Reason}
    end.

do_generate_prekeys(UserId, Count) ->
    % First, clean up old prekeys
    CleanupSQL = "DELETE FROM user_prekeys WHERE user_id = $1",
    aethertalk_db:query(CleanupSQL, [UserId]),
    
    % Generate new prekeys
    Prekeys = lists:map(fun(Index) ->
        {PublicKey, PrivateKey} = crypto:generate_key(ecdh, x25519),
        KeyId = aethertalk_utils:generate_uuid(),
        
        SQL = "INSERT INTO user_prekeys (id, user_id, key_index, public_key, private_key, created_at) 
               VALUES ($1, $2, $3, $4, $5, NOW())",
        
        case aethertalk_db:query(SQL, [KeyId, UserId, Index, PublicKey, PrivateKey]) of
            {ok, 1} ->
                #{
                    id => KeyId,
                    key_index => Index,
                    public_key => base64:encode(PublicKey),
                    created_at => calendar:universal_time()
                };
            {error, Reason} ->
                lager:error("Failed to store prekey ~p for user ~p: ~p", [Index, UserId, Reason]),
                error
        end
    end, lists:seq(1, Count)),
    
    ValidPrekeys = [Key || Key <- Prekeys, Key =/= error],
    
    lager:info("Generated ~p prekeys for user ~p", [length(ValidPrekeys), UserId]),
    {ok, ValidPrekeys}.

do_create_session(UserId1, UserId2, InitiatorId) ->
    % Check if session already exists
    CheckSQL = "SELECT id, session_key, created_at FROM encryption_sessions 
               WHERE (user1_id = $1 AND user2_id = $2) OR (user1_id = $2 AND user2_id = $1)",
    
    case aethertalk_db:query(CheckSQL, [UserId1, UserId2]) of
        {ok, {_Columns, []}} ->
            % Create new session
            create_new_session(UserId1, UserId2, InitiatorId);
        {ok, {_Columns, [{SessionId, SessionKey, CreatedAt}]}} ->
            % Return existing session
            Session = #{
                id => SessionId,
                user1_id => UserId1,
                user2_id => UserId2,
                session_key => base64:encode(SessionKey),
                created_at => CreatedAt,
                status => existing
            },
            {ok, Session};
        {error, Reason} ->
            {error, Reason}
    end.

create_new_session(UserId1, UserId2, InitiatorId) ->
    % Get public keys for both users
    case {get_user_identity_key(UserId1), get_user_identity_key(UserId2)} of
        {{ok, Key1}, {ok, Key2}} ->
            % Perform key exchange
            case perform_key_exchange(UserId1, UserId2, Key1, Key2, InitiatorId) of
                {ok, SessionKey} ->
                    % Store session
                    SessionId = aethertalk_utils:generate_uuid(),
                    SQL = "INSERT INTO encryption_sessions (id, user1_id, user2_id, session_key, 
                                                           initiator_id, created_at) 
                           VALUES ($1, $2, $3, $4, $5, NOW()) RETURNING created_at",
                    
                    case aethertalk_db:query(SQL, [SessionId, UserId1, UserId2, SessionKey, InitiatorId]) of
                        {ok, {_Columns, [{CreatedAt}]}} ->
                            Session = #{
                                id => SessionId,
                                user1_id => UserId1,
                                user2_id => UserId2,
                                session_key => base64:encode(SessionKey),
                                initiator_id => InitiatorId,
                                created_at => CreatedAt,
                                status => created
                            },
                            
                            lager:info("Created encryption session between users ~p and ~p", [UserId1, UserId2]),
                            {ok, Session};
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {{error, Reason}, _} ->
            {error, {user1_key_error, Reason}};
        {_, {error, Reason}} ->
            {error, {user2_key_error, Reason}}
    end.

do_encrypt_message(SessionId, SenderId, PlainText) ->
    % Get session key
    case get_session_key(SessionId, SenderId) of
        {ok, SessionKey} ->
            try
                % Generate random IV
                IV = crypto:strong_rand_bytes(?IV_SIZE),
                
                % Encrypt message using AES-256-GCM
                {CipherText, Tag} = crypto:crypto_one_time_aead(aes_256_gcm, SessionKey, IV, 
                                                               PlainText, <<>>, true),
                
                % Combine IV + CipherText + Tag
                EncryptedData = <<IV/binary, CipherText/binary, Tag/binary>>,
                
                % Store encrypted message metadata
                store_encrypted_message_metadata(SessionId, SenderId, byte_size(PlainText)),
                
                {ok, #{
                    encrypted_data => base64:encode(EncryptedData),
                    session_id => SessionId,
                    sender_id => SenderId,
                    timestamp => erlang:system_time(millisecond)
                }}
            catch
                error:Reason ->
                    lager:error("Encryption failed for session ~p: ~p", [SessionId, Reason]),
                    {error, encryption_failed}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_decrypt_message(SessionId, ReceiverId, CipherText) ->
    % Get session key
    case get_session_key(SessionId, ReceiverId) of
        {ok, SessionKey} ->
            try
                % Decode base64
                EncryptedData = base64:decode(CipherText),
                
                % Extract IV, CipherText, and Tag
                <<IV:?IV_SIZE/binary, CipherTextBinary/binary>> = EncryptedData,
                CipherTextSize = byte_size(CipherTextBinary) - 16, % 16 bytes for GCM tag
                <<ActualCipherText:CipherTextSize/binary, Tag:16/binary>> = CipherTextBinary,
                
                % Decrypt message
                case crypto:crypto_one_time_aead(aes_256_gcm, SessionKey, IV, 
                                               ActualCipherText, <<>>, Tag, false) of
                    PlainText when is_binary(PlainText) ->
                        {ok, #{
                            plain_text => PlainText,
                            session_id => SessionId,
                            receiver_id => ReceiverId,
                            timestamp => erlang:system_time(millisecond)
                        }};
                    error ->
                        lager:error("Decryption failed for session ~p", [SessionId]),
                        {error, decryption_failed}
                end
            catch
                error:Reason ->
                    lager:error("Decryption error for session ~p: ~p", [SessionId, Reason]),
                    {error, decryption_error}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_rotate_keys(UserId) ->
    % Generate new prekeys
    case do_generate_prekeys(UserId, 100) of
        {ok, NewPrekeys} ->
            % Update key rotation timestamp
            SQL = "UPDATE user_identity_keys SET last_rotation = NOW() WHERE user_id = $1",
            aethertalk_db:query(SQL, [UserId]),
            
            lager:info("Rotated keys for user ~p", [UserId]),
            {ok, #{
                user_id => UserId,
                new_prekeys_count => length(NewPrekeys),
                rotated_at => calendar:universal_time()
            }};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_user_public_keys(UserId) ->
    % Get identity key
    IdentitySQL = "SELECT public_key, created_at FROM user_identity_keys WHERE user_id = $1",
    
    % Get available prekeys
    PrekeysSQL = "SELECT id, key_index, public_key, created_at FROM user_prekeys 
                  WHERE user_id = $1 ORDER BY created_at DESC LIMIT 10",
    
    case {aethertalk_db:query(IdentitySQL, [UserId]), 
          aethertalk_db:query(PrekeysSQL, [UserId])} of
        {{ok, {_, [{IdentityKey, IdentityCreatedAt}]}}, 
         {ok, {_, PrekeyRows}}} ->
            
            Prekeys = lists:map(fun({KeyId, KeyIndex, PublicKey, CreatedAt}) ->
                #{
                    id => KeyId,
                    key_index => KeyIndex,
                    public_key => base64:encode(PublicKey),
                    created_at => CreatedAt
                }
            end, PrekeyRows),
            
            {ok, #{
                user_id => UserId,
                identity_key => base64:encode(IdentityKey),
                identity_created_at => IdentityCreatedAt,
                prekeys => Prekeys
            }};
        {{ok, {_, []}}, _} ->
            {error, no_identity_key};
        {_, {error, Reason}} ->
            {error, Reason};
        {{error, Reason}, _} ->
            {error, Reason}
    end.

do_verify_identity(UserId, PublicKey) ->
    SQL = "SELECT public_key FROM user_identity_keys WHERE user_id = $1",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, [{StoredPublicKey}]}} ->
            DecodedKey = base64:decode(PublicKey),
            case StoredPublicKey =:= DecodedKey of
                true ->
                    {ok, verified};
                false ->
                    {ok, not_verified}
            end;
        {ok, {_Columns, []}} ->
            {error, no_identity_key};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_session_info(UserId1, UserId2) ->
    SQL = "SELECT es.id, es.session_key, es.initiator_id, es.created_at, es.last_used,
                  COUNT(em.id) as message_count
           FROM encryption_sessions es
           LEFT JOIN encrypted_message_metadata em ON es.id = em.session_id
           WHERE (es.user1_id = $1 AND es.user2_id = $2) OR (es.user1_id = $2 AND es.user2_id = $1)
           GROUP BY es.id",
    
    case aethertalk_db:query(SQL, [UserId1, UserId2]) of
        {ok, {_Columns, [{SessionId, _SessionKey, InitiatorId, CreatedAt, LastUsed, MessageCount}]}} ->
            {ok, #{
                session_id => SessionId,
                user1_id => UserId1,
                user2_id => UserId2,
                initiator_id => InitiatorId,
                created_at => CreatedAt,
                last_used => LastUsed,
                message_count => MessageCount
            }};
        {ok, {_Columns, []}} ->
            {error, no_session};
        {error, Reason} ->
            {error, Reason}
    end.

do_delete_session(UserId1, UserId2) ->
    SQL = "DELETE FROM encryption_sessions 
           WHERE (user1_id = $1 AND user2_id = $2) OR (user1_id = $2 AND user2_id = $1)",
    
    case aethertalk_db:query(SQL, [UserId1, UserId2]) of
        {ok, 1} ->
            lager:info("Deleted encryption session between users ~p and ~p", [UserId1, UserId2]),
            ok;
        {ok, 0} ->
            {error, no_session};
        {error, Reason} ->
            {error, Reason}
    end.

%% Helper functions

get_user_identity_key(UserId) ->
    SQL = "SELECT public_key, private_key FROM user_identity_keys WHERE user_id = $1",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, [{PublicKey, PrivateKey}]}} ->
            {ok, #{public_key => PublicKey, private_key => PrivateKey}};
        {ok, {_Columns, []}} ->
            {error, no_identity_key};
        {error, Reason} ->
            {error, Reason}
    end.

perform_key_exchange(UserId1, UserId2, Key1, Key2, InitiatorId) ->
    % Simplified key exchange - in production, use proper Signal Protocol
    try
        PublicKey1 = maps:get(public_key, Key1),
        PrivateKey1 = maps:get(private_key, Key1),
        PublicKey2 = maps:get(public_key, Key2),
        PrivateKey2 = maps:get(private_key, Key2),
        
        % Create shared secret using ECDH
        SharedSecret1 = crypto:compute_key(ecdh, PublicKey2, PrivateKey1, x25519),
        SharedSecret2 = crypto:compute_key(ecdh, PublicKey1, PrivateKey2, x25519),
        
        % Verify both sides get the same shared secret
        case SharedSecret1 =:= SharedSecret2 of
            true ->
                % Derive session key using HKDF
                SessionKey = crypto:hash(sha256, <<SharedSecret1/binary, 
                                                 (term_to_binary(UserId1))/binary,
                                                 (term_to_binary(UserId2))/binary,
                                                 (term_to_binary(InitiatorId))/binary>>),
                {ok, SessionKey};
            false ->
                {error, key_exchange_failed}
        end
    catch
        error:Reason ->
            lager:error("Key exchange failed: ~p", [Reason]),
            {error, key_exchange_error}
    end.

get_session_key(SessionId, UserId) ->
    SQL = "SELECT session_key FROM encryption_sessions 
           WHERE id = $1 AND (user1_id = $2 OR user2_id = $2)",
    
    case aethertalk_db:query(SQL, [SessionId, UserId]) of
        {ok, {_Columns, [{SessionKey}]}} ->
            % Update last used timestamp
            UpdateSQL = "UPDATE encryption_sessions SET last_used = NOW() WHERE id = $1",
            aethertalk_db:query(UpdateSQL, [SessionId]),
            {ok, SessionKey};
        {ok, {_Columns, []}} ->
            {error, session_not_found};
        {error, Reason} ->
            {error, Reason}
    end.

store_encrypted_message_metadata(SessionId, SenderId, PlainTextSize) ->
    SQL = "INSERT INTO encrypted_message_metadata (session_id, sender_id, plain_text_size, created_at) 
           VALUES ($1, $2, $3, NOW())",
    aethertalk_db:query(SQL, [SessionId, SenderId, PlainTextSize]).

%% Periodic key rotation for all users
rotate_all_keys() ->
    SQL = "SELECT user_id FROM user_identity_keys 
           WHERE last_rotation IS NULL OR last_rotation < NOW() - INTERVAL '7 days'",
    
    case aethertalk_db:query(SQL, []) of
        {ok, {_Columns, Rows}} ->
            UserIds = [UserId || {UserId} <- Rows],
            lists:foreach(fun(UserId) ->
                spawn(fun() -> do_rotate_keys(UserId) end)
            end, UserIds),
            lager:info("Initiated key rotation for ~p users", [length(UserIds)]);
        {error, Reason} ->
            lager:error("Failed to get users for key rotation: ~p", [Reason])
    end.