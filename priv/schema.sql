-- AetherTalk Database Schema
-- PostgreSQL database schema for enterprise messaging platform

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Users table (updated with phone verification support)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255),
    avatar_url TEXT,
    phone_number VARCHAR(20) UNIQUE,
    status VARCHAR(20) DEFAULT 'offline' CHECK (status IN ('online', 'offline', 'away', 'busy')),
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_verified BOOLEAN DEFAULT FALSE,
    phone_verified BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_last_seen ON users(last_seen);
CREATE INDEX idx_users_created_at ON users(created_at);

-- User settings table
CREATE TABLE user_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    setting_key VARCHAR(100) NOT NULL,
    setting_value JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, setting_key)
);

CREATE INDEX idx_user_settings_user_id ON user_settings(user_id);
CREATE INDEX idx_user_settings_key ON user_settings(setting_key);

-- Contacts table
CREATE TABLE contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    display_name VARCHAR(255),
    is_blocked BOOLEAN DEFAULT FALSE,
    is_favorite BOOLEAN DEFAULT FALSE,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, contact_user_id)
);

CREATE INDEX idx_contacts_user_id ON contacts(user_id);
CREATE INDEX idx_contacts_contact_user_id ON contacts(contact_user_id);
CREATE INDEX idx_contacts_is_blocked ON contacts(is_blocked);
CREATE INDEX idx_contacts_is_favorite ON contacts(is_favorite);

-- Chats table
CREATE TABLE chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type VARCHAR(20) NOT NULL CHECK (type IN ('direct', 'group')),
    name VARCHAR(255),
    description TEXT,
    avatar_url TEXT,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    is_archived BOOLEAN DEFAULT FALSE,
    is_pinned BOOLEAN DEFAULT FALSE,
    is_muted BOOLEAN DEFAULT FALSE,
    last_message_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_chats_type ON chats(type);
CREATE INDEX idx_chats_created_by ON chats(created_by);
CREATE INDEX idx_chats_last_message_at ON chats(last_message_at);
CREATE INDEX idx_chats_created_at ON chats(created_at);

-- Chat participants table
CREATE TABLE chat_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(20) DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    left_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(chat_id, user_id)
);

CREATE INDEX idx_chat_participants_chat_id ON chat_participants(chat_id);
CREATE INDEX idx_chat_participants_user_id ON chat_participants(user_id);
CREATE INDEX idx_chat_participants_role ON chat_participants(role);

-- Messages table
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reply_to_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    message_type VARCHAR(20) NOT NULL DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'video', 'audio', 'file', 'location', 'contact')),
    content TEXT,
    media_url TEXT,
    media_metadata JSONB DEFAULT '{}',
    is_edited BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    is_forwarded BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_messages_chat_id ON messages(chat_id);
CREATE INDEX idx_messages_sender_id ON messages(sender_id);
CREATE INDEX idx_messages_reply_to_id ON messages(reply_to_id);
CREATE INDEX idx_messages_message_type ON messages(message_type);
CREATE INDEX idx_messages_created_at ON messages(created_at);
CREATE INDEX idx_messages_is_deleted ON messages(is_deleted);

-- Message delivery status table
CREATE TABLE message_delivery_status (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'sent' CHECK (status IN ('sent', 'delivered', 'read')),
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(message_id, user_id)
);

CREATE INDEX idx_message_delivery_status_message_id ON message_delivery_status(message_id);
CREATE INDEX idx_message_delivery_status_user_id ON message_delivery_status(user_id);
CREATE INDEX idx_message_delivery_status_status ON message_delivery_status(status);
CREATE INDEX idx_message_delivery_status_timestamp ON message_delivery_status(timestamp);

-- Message reactions table
CREATE TABLE message_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reaction VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(message_id, user_id, reaction)
);

CREATE INDEX idx_message_reactions_message_id ON message_reactions(message_id);
CREATE INDEX idx_message_reactions_user_id ON message_reactions(user_id);
CREATE INDEX idx_message_reactions_reaction ON message_reactions(reaction);

-- Media files table
CREATE TABLE media_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    uploader_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    filename VARCHAR(255) NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    file_type VARCHAR(100) NOT NULL,
    file_size BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_path TEXT NOT NULL,
    thumbnail_path TEXT,
    is_encrypted BOOLEAN DEFAULT FALSE,
    encryption_key TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_media_files_uploader_id ON media_files(uploader_id);
CREATE INDEX idx_media_files_file_type ON media_files(file_type);
CREATE INDEX idx_media_files_created_at ON media_files(created_at);

-- Calls table
CREATE TABLE calls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caller_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    callee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    call_type VARCHAR(20) NOT NULL CHECK (call_type IN ('voice', 'video')),
    status VARCHAR(20) NOT NULL DEFAULT 'initiated' CHECK (status IN ('initiated', 'ringing', 'answered', 'ended', 'missed', 'declined')),
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    answered_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,
    duration INTEGER DEFAULT 0,
    quality_score INTEGER CHECK (quality_score >= 1 AND quality_score <= 5),
    metadata JSONB DEFAULT '{}'
);

CREATE INDEX idx_calls_caller_id ON calls(caller_id);
CREATE INDEX idx_calls_callee_id ON calls(callee_id);
CREATE INDEX idx_calls_call_type ON calls(call_type);
CREATE INDEX idx_calls_status ON calls(status);
CREATE INDEX idx_calls_started_at ON calls(started_at);

-- Notifications table
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    data JSONB DEFAULT '{}',
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_created_at ON notifications(created_at);
CREATE INDEX idx_notifications_is_read ON notifications(is_read);

-- Groups table
CREATE TABLE groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    avatar_url TEXT,
    settings JSONB DEFAULT '{}',
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_groups_creator_id ON groups(creator_id);
CREATE INDEX idx_groups_chat_id ON groups(chat_id);
CREATE INDEX idx_groups_created_at ON groups(created_at);
CREATE INDEX idx_groups_is_deleted ON groups(is_deleted);

-- Group members table
CREATE TABLE group_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(group_id, user_id)
);

CREATE INDEX idx_group_members_group_id ON group_members(group_id);
CREATE INDEX idx_group_members_user_id ON group_members(user_id);
CREATE INDEX idx_group_members_role ON group_members(role);
CREATE INDEX idx_group_members_joined_at ON group_members(joined_at);

-- Broadcast lists table
CREATE TABLE broadcast_lists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_broadcast_lists_creator_id ON broadcast_lists(creator_id);
CREATE INDEX idx_broadcast_lists_created_at ON broadcast_lists(created_at);

-- Broadcast list members table
CREATE TABLE broadcast_list_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    broadcast_list_id UUID NOT NULL REFERENCES broadcast_lists(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(broadcast_list_id, user_id)
);

CREATE INDEX idx_broadcast_list_members_list_id ON broadcast_list_members(broadcast_list_id);
CREATE INDEX idx_broadcast_list_members_user_id ON broadcast_list_members(user_id);
CREATE INDEX idx_broadcast_list_members_added_at ON broadcast_list_members(added_at);

-- Status/Stories table (for future implementation)
CREATE TABLE user_status (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT,
    media_url TEXT,
    media_type VARCHAR(20) CHECK (media_type IN ('image', 'video')),
    background_color VARCHAR(7),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_user_status_user_id ON user_status(user_id);
CREATE INDEX idx_user_status_expires_at ON user_status(expires_at);
CREATE INDEX idx_user_status_created_at ON user_status(created_at);
CREATE INDEX idx_user_status_is_deleted ON user_status(is_deleted);

-- Status views table (who viewed the status)
CREATE TABLE status_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    status_id UUID NOT NULL REFERENCES user_status(id) ON DELETE CASCADE,
    viewer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    viewed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(status_id, viewer_id)
);

CREATE INDEX idx_status_views_status_id ON status_views(status_id);
CREATE INDEX idx_status_views_viewer_id ON status_views(viewer_id);
CREATE INDEX idx_status_views_viewed_at ON status_views(viewed_at);

-- Polls table
CREATE TABLE polls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    question TEXT NOT NULL,
    is_closed BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_polls_chat_id ON polls(chat_id);
CREATE INDEX idx_polls_creator_id ON polls(creator_id);
CREATE INDEX idx_polls_created_at ON polls(created_at);
CREATE INDEX idx_polls_expires_at ON polls(expires_at);
CREATE INDEX idx_polls_is_closed ON polls(is_closed);
CREATE INDEX idx_polls_is_deleted ON polls(is_deleted);

-- Poll options table
CREATE TABLE poll_options (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    poll_id UUID NOT NULL REFERENCES polls(id) ON DELETE CASCADE,
    option_text TEXT NOT NULL,
    option_order INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_poll_options_poll_id ON poll_options(poll_id);
CREATE INDEX idx_poll_options_order ON poll_options(poll_id, option_order);

-- Poll votes table
CREATE TABLE poll_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    poll_id UUID NOT NULL REFERENCES polls(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    option_id UUID NOT NULL REFERENCES poll_options(id) ON DELETE CASCADE,
    voted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(poll_id, user_id)
);

CREATE INDEX idx_poll_votes_poll_id ON poll_votes(poll_id);
CREATE INDEX idx_poll_votes_user_id ON poll_votes(user_id);
CREATE INDEX idx_poll_votes_option_id ON poll_votes(option_id);
CREATE INDEX idx_poll_votes_voted_at ON poll_votes(voted_at);

-- Chat disappearing message settings
CREATE TABLE chat_disappearing_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    timer_seconds INTEGER NOT NULL DEFAULT 0,
    set_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(chat_id)
);

CREATE INDEX idx_chat_disappearing_settings_chat_id ON chat_disappearing_settings(chat_id);
CREATE INDEX idx_chat_disappearing_settings_set_by ON chat_disappearing_settings(set_by);

-- Disappearing messages tracking
CREATE TABLE disappearing_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    delete_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(message_id)
);

CREATE INDEX idx_disappearing_messages_message_id ON disappearing_messages(message_id);
CREATE INDEX idx_disappearing_messages_delete_at ON disappearing_messages(delete_at);
CREATE INDEX idx_disappearing_messages_created_at ON disappearing_messages(created_at);

-- Location messages table
CREATE TABLE location_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    address TEXT,
    location_type VARCHAR(20) NOT NULL DEFAULT 'static' CHECK (location_type IN ('static', 'live')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(message_id)
);

CREATE INDEX idx_location_messages_message_id ON location_messages(message_id);
CREATE INDEX idx_location_messages_coordinates ON location_messages(latitude, longitude);
CREATE INDEX idx_location_messages_type ON location_messages(location_type);

-- Live locations table
CREATE TABLE live_locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    address TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_live_locations_message_id ON live_locations(message_id);
CREATE INDEX idx_live_locations_user_id ON live_locations(user_id);
CREATE INDEX idx_live_locations_chat_id ON live_locations(chat_id);
CREATE INDEX idx_live_locations_coordinates ON live_locations(latitude, longitude);
CREATE INDEX idx_live_locations_active ON live_locations(is_active);
CREATE INDEX idx_live_locations_expires_at ON live_locations(expires_at);
CREATE INDEX idx_live_locations_updated_at ON live_locations(updated_at);

-- Security and Encryption Tables

-- User identity keys for end-to-end encryption
CREATE TABLE user_identity_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    public_key BYTEA NOT NULL,
    private_key BYTEA NOT NULL,
    last_rotation TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id)
);

CREATE INDEX idx_user_identity_keys_user_id ON user_identity_keys(user_id);
CREATE INDEX idx_user_identity_keys_last_rotation ON user_identity_keys(last_rotation);

-- User prekeys for key exchange
CREATE TABLE user_prekeys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key_index INTEGER NOT NULL,
    public_key BYTEA NOT NULL,
    private_key BYTEA NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, key_index)
);

CREATE INDEX idx_user_prekeys_user_id ON user_prekeys(user_id);
CREATE INDEX idx_user_prekeys_created_at ON user_prekeys(created_at);

-- Encryption sessions between users
CREATE TABLE encryption_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user1_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user2_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_key BYTEA NOT NULL,
    initiator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_used TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user1_id, user2_id)
);

CREATE INDEX idx_encryption_sessions_user1 ON encryption_sessions(user1_id);
CREATE INDEX idx_encryption_sessions_user2 ON encryption_sessions(user2_id);
CREATE INDEX idx_encryption_sessions_last_used ON encryption_sessions(last_used);

-- Encrypted message metadata
CREATE TABLE encrypted_message_metadata (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES encryption_sessions(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plain_text_size INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_encrypted_message_metadata_session ON encrypted_message_metadata(session_id);
CREATE INDEX idx_encrypted_message_metadata_sender ON encrypted_message_metadata(sender_id);
CREATE INDEX idx_encrypted_message_metadata_created_at ON encrypted_message_metadata(created_at);

-- Multi-Factor Authentication settings
CREATE TABLE user_mfa_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    totp_secret BYTEA,
    totp_enabled BOOLEAN DEFAULT FALSE,
    backup_codes JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id)
);

CREATE INDEX idx_user_mfa_settings_user_id ON user_mfa_settings(user_id);
CREATE INDEX idx_user_mfa_settings_totp_enabled ON user_mfa_settings(totp_enabled);

-- SMS verification codes
CREATE TABLE sms_verification_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code VARCHAR(10) NOT NULL,
    attempts INTEGER DEFAULT 0,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id)
);

CREATE INDEX idx_sms_verification_codes_user_id ON sms_verification_codes(user_id);
CREATE INDEX idx_sms_verification_codes_expires_at ON sms_verification_codes(expires_at);

-- MFA audit log
CREATE TABLE mfa_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type VARCHAR(50) NOT NULL,
    result VARCHAR(20) NOT NULL,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_mfa_audit_log_user_id ON mfa_audit_log(user_id);
CREATE INDEX idx_mfa_audit_log_event_type ON mfa_audit_log(event_type);
CREATE INDEX idx_mfa_audit_log_created_at ON mfa_audit_log(created_at);

-- CSRF tokens
CREATE TABLE csrf_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id)
);

CREATE INDEX idx_csrf_tokens_user_id ON csrf_tokens(user_id);
CREATE INDEX idx_csrf_tokens_expires_at ON csrf_tokens(expires_at);

-- Custom rate limits
CREATE TABLE custom_rate_limits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    action VARCHAR(50) NOT NULL,
    limit_count INTEGER NOT NULL,
    window_seconds INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, action)
);

CREATE INDEX idx_custom_rate_limits_user_id ON custom_rate_limits(user_id);
CREATE INDEX idx_custom_rate_limits_action ON custom_rate_limits(action);

-- Rate limit violations log
CREATE TABLE rate_limit_violations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(50) NOT NULL,
    client_ip INET NOT NULL,
    limit_type VARCHAR(20) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_rate_limit_violations_user_id ON rate_limit_violations(user_id);
CREATE INDEX idx_rate_limit_violations_client_ip ON rate_limit_violations(client_ip);
CREATE INDEX idx_rate_limit_violations_created_at ON rate_limit_violations(created_at);

-- Security events log
CREATE TABLE security_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type VARCHAR(50) NOT NULL,
    client_ip INET NOT NULL,
    user_agent TEXT,
    path TEXT,
    method VARCHAR(10),
    event_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_security_events_event_type ON security_events(event_type);
CREATE INDEX idx_security_events_client_ip ON security_events(client_ip);
CREATE INDEX idx_security_events_created_at ON security_events(created_at);

-- User roles for authorization
CREATE TABLE user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin', 'moderator', 'support')),
    granted_by UUID REFERENCES users(id) ON DELETE SET NULL,
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(user_id, role)
);

CREATE INDEX idx_user_roles_user_id ON user_roles(user_id);
CREATE INDEX idx_user_roles_role ON user_roles(role);
CREATE INDEX idx_user_roles_expires_at ON user_roles(expires_at);

-- Create some useful views
CREATE VIEW active_users AS
SELECT u.*, 
       CASE 
           WHEN u.last_seen > NOW() - INTERVAL '5 minutes' THEN 'online'
           WHEN u.last_seen > NOW() - INTERVAL '1 hour' THEN 'recently_active'
           ELSE 'offline'
       END as activity_status
FROM users u
WHERE u.is_active = TRUE;

CREATE VIEW chat_summary AS
SELECT c.id,
       c.type,
       c.name,
       c.last_message_at,
       COUNT(DISTINCT cp.user_id) as participant_count,
       COUNT(DISTINCT m.id) as message_count
FROM chats c
LEFT JOIN chat_participants cp ON c.id = cp.chat_id AND cp.left_at IS NULL
LEFT JOIN messages m ON c.id = m.chat_id AND m.is_deleted = FALSE
GROUP BY c.id, c.type, c.name, c.last_message_at;

-- Phone verifications table
CREATE TABLE phone_verifications (
    phone_number VARCHAR(20) PRIMARY KEY,
    verified BOOLEAN DEFAULT FALSE,
    verified_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_phone_verifications_verified ON phone_verifications(verified);
CREATE INDEX idx_phone_verifications_created_at ON phone_verifications(created_at);

-- Phone calls table
CREATE TABLE phone_calls (
    call_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caller_phone VARCHAR(20) NOT NULL,
    callee_phone VARCHAR(20) NOT NULL,
    caller_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    callee_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    call_type VARCHAR(10) NOT NULL CHECK (call_type IN ('voice', 'video')),
    status VARCHAR(20) NOT NULL CHECK (status IN ('ringing', 'active', 'ended', 'rejected')),
    started_at TIMESTAMP WITH TIME ZONE NOT NULL,
    answered_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,
    duration INTEGER, -- Duration in seconds
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_phone_calls_caller_user ON phone_calls(caller_user_id);
CREATE INDEX idx_phone_calls_callee_user ON phone_calls(callee_user_id);
CREATE INDEX idx_phone_calls_status ON phone_calls(status);
CREATE INDEX idx_phone_calls_started_at ON phone_calls(started_at);
CREATE INDEX idx_phone_calls_caller_phone ON phone_calls(caller_phone);
CREATE INDEX idx_phone_calls_callee_phone ON phone_calls(callee_phone);

-- Add phone number index to users table
CREATE INDEX idx_users_phone_number ON users(phone_number);
CREATE INDEX idx_users_phone_verified ON users(phone_verified);

-- User translation settings table
CREATE TABLE user_translation_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    enabled BOOLEAN DEFAULT FALSE,
    source_language VARCHAR(10) DEFAULT 'auto',
    target_language VARCHAR(10) DEFAULT 'en',
    voice VARCHAR(50) DEFAULT 'en-US-female-1',
    text_output BOOLEAN DEFAULT TRUE,
    voice_output BOOLEAN DEFAULT TRUE,
    auto_detect BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_user_translation_settings_enabled ON user_translation_settings(enabled);
CREATE INDEX idx_user_translation_settings_source_lang ON user_translation_settings(source_language);
CREATE INDEX idx_user_translation_settings_target_lang ON user_translation_settings(target_language);

-- Insert default system user for system messages
INSERT INTO users (id, username, email, password_hash, full_name, is_verified, is_active)
VALUES (
    '00000000-0000-0000-0000-000000000000',
    'system',
    'system@aethertalk.com',
    'system',
    'AetherTalk System',
    TRUE,
    TRUE
) ON CONFLICT (id) DO NOTHING;