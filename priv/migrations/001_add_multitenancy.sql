-- Migration: Add Multi-Tenancy Support
-- This migration adds tenant isolation to the AetherTalk database

-- Create tenants table
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    domain VARCHAR(255),
    settings JSONB DEFAULT '{}',
    plan VARCHAR(50) DEFAULT 'basic' CHECK (plan IN ('basic', 'professional', 'enterprise')),
    max_users INTEGER DEFAULT 100,
    max_storage_gb INTEGER DEFAULT 10,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_tenants_slug ON tenants(slug);
CREATE INDEX idx_tenants_domain ON tenants(domain);
CREATE INDEX idx_tenants_is_active ON tenants(is_active);

-- Create tenant_users table for user-tenant relationships
CREATE TABLE tenant_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(50) DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'moderator', 'member')),
    permissions JSONB DEFAULT '{}',
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE,
    UNIQUE(tenant_id, user_id)
);

CREATE INDEX idx_tenant_users_tenant_id ON tenant_users(tenant_id);
CREATE INDEX idx_tenant_users_user_id ON tenant_users(user_id);
CREATE INDEX idx_tenant_users_role ON tenant_users(role);

-- Add tenant_id to existing tables
ALTER TABLE users ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE chats ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE messages ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE contacts ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE user_settings ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE user_sessions ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE notifications ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE file_uploads ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE voice_calls ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE video_calls ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE call_participants ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE user_status ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE message_reactions ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE message_threads ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE user_blocks ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE audit_logs ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE rate_limits ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE custom_rate_limits ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE security_events ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE user_devices ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE push_subscriptions ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE webhooks ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE webhook_events ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE api_keys ADD COLUMN tenant_id UUID REFERENCES tenants(id);

-- Create indexes for tenant_id columns
CREATE INDEX idx_users_tenant_id ON users(tenant_id);
CREATE INDEX idx_chats_tenant_id ON chats(tenant_id);
CREATE INDEX idx_messages_tenant_id ON messages(tenant_id);
CREATE INDEX idx_contacts_tenant_id ON contacts(tenant_id);
CREATE INDEX idx_user_settings_tenant_id ON user_settings(tenant_id);
CREATE INDEX idx_user_sessions_tenant_id ON user_sessions(tenant_id);
CREATE INDEX idx_notifications_tenant_id ON notifications(tenant_id);
CREATE INDEX idx_file_uploads_tenant_id ON file_uploads(tenant_id);
CREATE INDEX idx_voice_calls_tenant_id ON voice_calls(tenant_id);
CREATE INDEX idx_video_calls_tenant_id ON video_calls(tenant_id);
CREATE INDEX idx_call_participants_tenant_id ON call_participants(tenant_id);
CREATE INDEX idx_user_status_tenant_id ON user_status(tenant_id);
CREATE INDEX idx_message_reactions_tenant_id ON message_reactions(tenant_id);
CREATE INDEX idx_message_threads_tenant_id ON message_threads(tenant_id);
CREATE INDEX idx_user_blocks_tenant_id ON user_blocks(tenant_id);
CREATE INDEX idx_audit_logs_tenant_id ON audit_logs(tenant_id);
CREATE INDEX idx_rate_limits_tenant_id ON rate_limits(tenant_id);
CREATE INDEX idx_custom_rate_limits_tenant_id ON custom_rate_limits(tenant_id);
CREATE INDEX idx_security_events_tenant_id ON security_events(tenant_id);
CREATE INDEX idx_user_devices_tenant_id ON user_devices(tenant_id);
CREATE INDEX idx_push_subscriptions_tenant_id ON push_subscriptions(tenant_id);
CREATE INDEX idx_webhooks_tenant_id ON webhooks(tenant_id);
CREATE INDEX idx_webhook_events_tenant_id ON webhook_events(tenant_id);
CREATE INDEX idx_api_keys_tenant_id ON api_keys(tenant_id);

-- Create default tenant
INSERT INTO tenants (id, name, slug, domain, plan, max_users, max_storage_gb)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    'Default Tenant',
    'default',
    'localhost',
    'enterprise',
    10000,
    1000
);

-- Update system user to belong to default tenant
UPDATE users 
SET tenant_id = '11111111-1111-1111-1111-111111111111'
WHERE id = '00000000-0000-0000-0000-000000000000';