%%%-------------------------------------------------------------------
%% @doc AetherTalk common header file
%% @end
%%%-------------------------------------------------------------------

%% Application constants
-define(APP_NAME, aethertalk).
-define(APP_VERSION, "1.0.0").

%% Database constants
-define(DEFAULT_TIMEOUT, 5000).
-define(MAX_QUERY_TIMEOUT, 30000).

%% Message types
-define(MSG_TYPE_TEXT, text).
-define(MSG_TYPE_IMAGE, image).
-define(MSG_TYPE_VIDEO, video).
-define(MSG_TYPE_AUDIO, audio).
-define(MSG_TYPE_DOCUMENT, document).
-define(MSG_TYPE_LOCATION, location).
-define(MSG_TYPE_CONTACT, contact).
-define(MSG_TYPE_POLL, poll).
-define(MSG_TYPE_SYSTEM, system).

%% Chat types
-define(CHAT_TYPE_DIRECT, direct).
-define(CHAT_TYPE_GROUP, group).
-define(CHAT_TYPE_BROADCAST, broadcast).

%% Call types
-define(CALL_TYPE_VOICE, voice).
-define(CALL_TYPE_VIDEO, video).
-define(CALL_TYPE_GROUP_VOICE, group_voice).
-define(CALL_TYPE_GROUP_VIDEO, group_video).

%% Call status
-define(CALL_STATUS_INITIATED, initiated).
-define(CALL_STATUS_RINGING, ringing).
-define(CALL_STATUS_ACTIVE, active).
-define(CALL_STATUS_ENDED, ended).
-define(CALL_STATUS_MISSED, missed).
-define(CALL_STATUS_DECLINED, declined).

%% User roles
-define(ROLE_OWNER, owner).
-define(ROLE_ADMIN, admin).
-define(ROLE_MEMBER, member).

%% Delivery status
-define(DELIVERY_SENT, sent).
-define(DELIVERY_DELIVERED, delivered).
-define(DELIVERY_READ, read).

%% Privacy levels
-define(PRIVACY_PUBLIC, public).
-define(PRIVACY_CONTACTS, contacts).
-define(PRIVACY_CLOSE_FRIENDS, close_friends).

%% Encryption key types
-define(KEY_TYPE_IDENTITY, identity).
-define(KEY_TYPE_PREKEY, prekey).
-define(KEY_TYPE_SIGNED_PREKEY, signed_prekey).
-define(KEY_TYPE_ONE_TIME, one_time).

%% WebSocket message types
-define(WS_MSG_AUTH, auth).
-define(WS_MSG_MESSAGE, message).
-define(WS_MSG_TYPING, typing).
-define(WS_MSG_PRESENCE, presence).
-define(WS_MSG_CALL_SIGNAL, call_signal).
-define(WS_MSG_NOTIFICATION, notification).
-define(WS_MSG_ACK, ack).
-define(WS_MSG_ERROR, error).

%% Rate limiting
-define(RATE_LIMIT_WINDOW, 60). % seconds
-define(RATE_LIMIT_MAX_REQUESTS, 100).

%% File size limits
-define(MAX_IMAGE_SIZE, 10485760). % 10MB
-define(MAX_VIDEO_SIZE, 104857600). % 100MB
-define(MAX_AUDIO_SIZE, 52428800). % 50MB
-define(MAX_DOCUMENT_SIZE, 104857600). % 100MB

%% Media processing
-define(IMAGE_MAX_WIDTH, 1920).
-define(IMAGE_MAX_HEIGHT, 1080).
-define(THUMBNAIL_SIZE, 150).
-define(VIDEO_MAX_DURATION, 300). % 5 minutes
-define(AUDIO_MAX_DURATION, 600). % 10 minutes

%% Session management
-define(SESSION_TIMEOUT, 86400). % 24 hours
-define(REFRESH_TOKEN_TIMEOUT, 604800). % 7 days
-define(MAX_SESSIONS_PER_USER, 5).

%% Security
-define(PASSWORD_MIN_LENGTH, 8).
-define(MAX_LOGIN_ATTEMPTS, 5).
-define(LOGIN_LOCKOUT_DURATION, 900). % 15 minutes

%% Translation
-define(SUPPORTED_LANGUAGES, [
    "en", "es", "fr", "de", "it", "pt", "ru", "zh", "ja", "ko", "ar", "hi"
]).

%% Record definitions
-record(user, {
    id,
    phone_number,
    username,
    display_name,
    email,
    password_hash,
    profile_picture_url,
    status,
    is_online = false,
    last_seen,
    is_verified = false,
    is_business = false,
    two_factor_enabled = false,
    two_factor_secret,
    language = "en",
    timezone = "UTC",
    privacy_settings = #{},
    notification_settings = #{},
    created_at,
    updated_at
}).

-record(message, {
    id,
    chat_id,
    sender_id,
    reply_to_id,
    forward_from_id,
    message_type,
    content,
    media_url,
    media_metadata = #{},
    is_edited = false,
    is_deleted = false,
    is_forwarded = false,
    delivery_status = sent,
    expires_at,
    encryption_key_id,
    created_at,
    updated_at
}).

-record(chat, {
    id,
    type,
    name,
    description,
    avatar_url,
    created_by,
    is_archived = false,
    is_pinned = false,
    is_muted = false,
    last_message_id,
    last_message_at,
    participant_count = 0,
    settings = #{},
    created_at,
    updated_at
}).

-record(call, {
    id,
    chat_id,
    initiator_id,
    call_type,
    status = initiated,
    started_at,
    ended_at,
    duration = 0,
    recording_url,
    quality_level = medium,
    settings = #{}
}).

-record(websocket_state, {
    user_id,
    session_id,
    device_id,
    authenticated = false,
    subscriptions = [],
    last_ping,
    rate_limit_counter = 0,
    rate_limit_reset_time
}).

%% Type definitions
-type user_id() :: binary().
-type chat_id() :: binary().
-type message_id() :: binary().
-type call_id() :: binary().
-type session_id() :: binary().
-type device_id() :: binary().

-type message_type() :: text | image | video | audio | document | location | contact | poll | system.
-type chat_type() :: direct | group | broadcast.
-type call_type() :: voice | video | group_voice | group_video.
-type call_status() :: initiated | ringing | active | ended | missed | declined.
-type user_role() :: owner | admin | member.
-type delivery_status() :: sent | delivered | read.
-type privacy_level() :: public | contacts | close_friends.

%% Error types
-type error_reason() :: 
    unauthorized | 
    forbidden | 
    not_found | 
    invalid_input | 
    rate_limited | 
    internal_error | 
    database_error | 
    network_error |
    encryption_error |
    media_processing_error.