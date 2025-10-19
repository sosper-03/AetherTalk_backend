%%%-------------------------------------------------------------------
%% @doc AetherTalk database interface
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_db).

-export([
    init_schema/0,
    query/2, query/3,
    transaction/1,
    get_connection/0,
    return_connection/1
]).

-include("aethertalk.hrl").

%% @doc Initialize database schema
init_schema() ->
    lager:info("Initializing database schema"),
    
    % Create tables if they don't exist
    Tables = [
        create_users_table(),
        create_contacts_table(),
        create_chats_table(),
        create_messages_table(),
        create_groups_table(),
        create_group_members_table(),
        create_media_table(),
        create_calls_table(),
        create_call_participants_table(),
        create_user_sessions_table(),
        create_user_settings_table(),
        create_notifications_table(),
        create_status_updates_table(),
        create_message_reactions_table(),
        create_user_blocks_table(),
        create_encryption_keys_table()
    ],
    
    lists:foreach(fun(TableSQL) ->
        case query(TableSQL, []) of
            {ok, _} -> ok;
            {error, Reason} ->
                lager:error("Failed to create table: ~p", [Reason]),
                error({table_creation_failed, Reason})
        end
    end, Tables),
    
    lager:info("Database schema initialized successfully"),
    ok.

%% @doc Execute a query
query(SQL, Params) ->
    query(SQL, Params, 5000).

query(SQL, Params, Timeout) ->
    poolboy:transaction(postgres_pool, fun(Worker) ->
        aethertalk_db_worker:query(Worker, SQL, Params, Timeout)
    end).

%% @doc Execute a transaction
transaction(Fun) ->
    poolboy:transaction(postgres_pool, fun(Worker) ->
        aethertalk_db_worker:transaction(Worker, Fun)
    end).

%% @doc Get a database connection
get_connection() ->
    poolboy:checkout(postgres_pool).

%% @doc Return a database connection
return_connection(Connection) ->
    poolboy:checkin(postgres_pool, Connection).

%% Internal functions

create_users_table() ->
    "CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        phone_number VARCHAR(20) UNIQUE NOT NULL,
        username VARCHAR(50) UNIQUE,
        display_name VARCHAR(100),
        email VARCHAR(255),
        password_hash VARCHAR(255) NOT NULL,
        profile_picture_url TEXT,
        status TEXT DEFAULT 'Hey there! I am using AetherTalk.',
        is_online BOOLEAN DEFAULT FALSE,
        last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        is_verified BOOLEAN DEFAULT FALSE,
        is_business BOOLEAN DEFAULT FALSE,
        two_factor_enabled BOOLEAN DEFAULT FALSE,
        two_factor_secret VARCHAR(32),
        language VARCHAR(10) DEFAULT 'en',
        timezone VARCHAR(50) DEFAULT 'UTC',
        privacy_settings JSONB DEFAULT '{}',
        notification_settings JSONB DEFAULT '{}',
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    )".

create_contacts_table() ->
    "CREATE TABLE IF NOT EXISTS contacts (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        contact_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        display_name VARCHAR(100),
        is_blocked BOOLEAN DEFAULT FALSE,
        is_favorite BOOLEAN DEFAULT FALSE,
        added_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        UNIQUE(user_id, contact_user_id)
    )".

create_chats_table() ->
    "CREATE TABLE IF NOT EXISTS chats (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        type VARCHAR(20) NOT NULL CHECK (type IN ('direct', 'group', 'broadcast')),
        name VARCHAR(100),
        description TEXT,
        avatar_url TEXT,
        created_by UUID REFERENCES users(id),
        is_archived BOOLEAN DEFAULT FALSE,
        is_pinned BOOLEAN DEFAULT FALSE,
        is_muted BOOLEAN DEFAULT FALSE,
        last_message_id UUID,
        last_message_at TIMESTAMP WITH TIME ZONE,
        participant_count INTEGER DEFAULT 0,
        settings JSONB DEFAULT '{}',
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    )".

create_messages_table() ->
    "CREATE TABLE IF NOT EXISTS messages (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
        sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        reply_to_id UUID REFERENCES messages(id),
        forward_from_id UUID REFERENCES messages(id),
        message_type VARCHAR(20) NOT NULL CHECK (message_type IN ('text', 'image', 'video', 'audio', 'document', 'location', 'contact', 'poll', 'system')),
        content TEXT,
        media_url TEXT,
        media_metadata JSONB,
        is_edited BOOLEAN DEFAULT FALSE,
        is_deleted BOOLEAN DEFAULT FALSE,
        is_forwarded BOOLEAN DEFAULT FALSE,
        delivery_status VARCHAR(20) DEFAULT 'sent' CHECK (delivery_status IN ('sent', 'delivered', 'read')),
        expires_at TIMESTAMP WITH TIME ZONE,
        encryption_key_id UUID,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    )".

create_groups_table() ->
    "CREATE TABLE IF NOT EXISTS groups (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
        invite_link VARCHAR(255) UNIQUE,
        max_participants INTEGER DEFAULT 256,
        is_public BOOLEAN DEFAULT FALSE,
        join_approval_required BOOLEAN DEFAULT FALSE,
        admin_only_messaging BOOLEAN DEFAULT FALSE,
        settings JSONB DEFAULT '{}',
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    )".

create_group_members_table() ->
    "CREATE TABLE IF NOT EXISTS group_members (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        role VARCHAR(20) DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
        joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        invited_by UUID REFERENCES users(id),
        is_muted BOOLEAN DEFAULT FALSE,
        UNIQUE(group_id, user_id)
    )".

create_media_table() ->
    "CREATE TABLE IF NOT EXISTS media (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
        uploader_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        filename VARCHAR(255) NOT NULL,
        original_filename VARCHAR(255),
        file_path TEXT NOT NULL,
        file_size BIGINT NOT NULL,
        mime_type VARCHAR(100) NOT NULL,
        width INTEGER,
        height INTEGER,
        duration INTEGER,
        thumbnail_path TEXT,
        is_encrypted BOOLEAN DEFAULT TRUE,
        encryption_key_id UUID,
        checksum VARCHAR(64),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    )".

create_calls_table() ->
    "CREATE TABLE IF NOT EXISTS calls (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
        initiator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        call_type VARCHAR(20) NOT NULL CHECK (call_type IN ('voice', 'video', 'group_voice', 'group_video')),
        status VARCHAR(20) DEFAULT 'initiated' CHECK (status IN ('initiated', 'ringing', 'active', 'ended', 'missed', 'declined')),
        started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        ended_at TIMESTAMP WITH TIME ZONE,
        duration INTEGER DEFAULT 0,
        recording_url TEXT,
        quality_level VARCHAR(20) DEFAULT 'medium',
        settings JSONB DEFAULT '{}'
    )".

create_call_participants_table() ->
    "CREATE TABLE IF NOT EXISTS call_participants (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        call_id UUID NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        joined_at TIMESTAMP WITH TIME ZONE,
        left_at TIMESTAMP WITH TIME ZONE,
        status VARCHAR(20) DEFAULT 'invited' CHECK (status IN ('invited', 'joined', 'left', 'declined')),
        is_muted BOOLEAN DEFAULT FALSE,
        is_video_enabled BOOLEAN DEFAULT TRUE,
        UNIQUE(call_id, user_id)
    )".

create_user_sessions_table() ->
    "CREATE TABLE IF NOT EXISTS user_sessions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        session_token VARCHAR(255) UNIQUE NOT NULL,
        refresh_token VARCHAR(255) UNIQUE NOT NULL,
        device_id VARCHAR(255),
        device_type VARCHAR(50),
        device_name VARCHAR(100),
        ip_address INET,
        user_agent TEXT,
        is_active BOOLEAN DEFAULT TRUE,
        expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        last_used_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    )".

create_user_settings_table() ->
    "CREATE TABLE IF NOT EXISTS user_settings (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        setting_key VARCHAR(100) NOT NULL,
        setting_value JSONB NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        UNIQUE(user_id, setting_key)
    )".

create_notifications_table() ->
    "CREATE TABLE IF NOT EXISTS notifications (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        type VARCHAR(50) NOT NULL,
        title VARCHAR(255) NOT NULL,
        body TEXT NOT NULL,
        data JSONB DEFAULT '{}',
        is_read BOOLEAN DEFAULT FALSE,
        is_sent BOOLEAN DEFAULT FALSE,
        scheduled_at TIMESTAMP WITH TIME ZONE,
        sent_at TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    )".

create_status_updates_table() ->
    "CREATE TABLE IF NOT EXISTS status_updates (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        content TEXT,
        media_url TEXT,
        media_type VARCHAR(20),
        background_color VARCHAR(7),
        font_style VARCHAR(50),
        privacy_level VARCHAR(20) DEFAULT 'contacts' CHECK (privacy_level IN ('public', 'contacts', 'close_friends')),
        view_count INTEGER DEFAULT 0,
        expires_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '24 hours'),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    )".

create_message_reactions_table() ->
    "CREATE TABLE IF NOT EXISTS message_reactions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        reaction VARCHAR(10) NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        UNIQUE(message_id, user_id, reaction)
    )".

create_user_blocks_table() ->
    "CREATE TABLE IF NOT EXISTS user_blocks (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        reason TEXT,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        UNIQUE(blocker_id, blocked_id)
    )".

create_encryption_keys_table() ->
    "CREATE TABLE IF NOT EXISTS encryption_keys (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        key_type VARCHAR(20) NOT NULL CHECK (key_type IN ('identity', 'prekey', 'signed_prekey', 'one_time')),
        public_key TEXT NOT NULL,
        private_key TEXT,
        key_id INTEGER,
        signature TEXT,
        is_active BOOLEAN DEFAULT TRUE,
        expires_at TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    )".