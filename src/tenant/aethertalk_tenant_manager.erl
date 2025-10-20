%%%-------------------------------------------------------------------
%%% @doc
%%% Tenant Management Service for AetherTalk
%%% Handles multi-tenant operations, isolation, and resource management
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_tenant_manager).
-behaviour(gen_server).

% OTP callbacks
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    create_tenant/4,
    create_tenant/6,
    get_tenant/1,
    get_tenant_by_slug/1,
    get_tenant_by_domain/1,
    update_tenant/2,
    delete_tenant/1,
    list_tenants/0,
    list_tenants/2,
    add_user_to_tenant/3,
    remove_user_from_tenant/2,
    get_tenant_users/1,
    get_user_tenants/1,
    set_tenant_context/1,
    get_current_tenant/0,
    clear_tenant_context/0,
    get_tenant_stats/1,
    check_tenant_limits/2,
    is_tenant_active/1
]).

-include("aethertalk.hrl").

-record(state, {
    tenant_cache :: ets:tid(),
    cache_ttl :: integer()
}).

-define(CACHE_TTL, 300). % 5 minutes
-define(DEFAULT_TENANT_ID, <<"11111111-1111-1111-1111-111111111111">>).

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Create a new tenant with basic parameters
create_tenant(Name, Slug, Domain, Plan) ->
    create_tenant(Name, Slug, Domain, Plan, 100, 10).

%% @doc Create a new tenant with full parameters
create_tenant(Name, Slug, Domain, Plan, MaxUsers, MaxStorageGB) ->
    gen_server:call(?MODULE, {create_tenant, Name, Slug, Domain, Plan, MaxUsers, MaxStorageGB}).

%% @doc Get tenant by ID
get_tenant(TenantId) ->
    gen_server:call(?MODULE, {get_tenant, TenantId}).

%% @doc Get tenant by slug
get_tenant_by_slug(Slug) ->
    gen_server:call(?MODULE, {get_tenant_by_slug, Slug}).

%% @doc Get tenant by domain
get_tenant_by_domain(Domain) ->
    gen_server:call(?MODULE, {get_tenant_by_domain, Domain}).

%% @doc Update tenant information
update_tenant(TenantId, Updates) ->
    gen_server:call(?MODULE, {update_tenant, TenantId, Updates}).

%% @doc Delete tenant (soft delete)
delete_tenant(TenantId) ->
    gen_server:call(?MODULE, {delete_tenant, TenantId}).

%% @doc List all active tenants
list_tenants() ->
    gen_server:call(?MODULE, list_tenants).

%% @doc List tenants with pagination
list_tenants(Limit, Offset) ->
    gen_server:call(?MODULE, {list_tenants, Limit, Offset}).

%% @doc Add user to tenant with role
add_user_to_tenant(TenantId, UserId, Role) ->
    gen_server:call(?MODULE, {add_user_to_tenant, TenantId, UserId, Role}).

%% @doc Remove user from tenant
remove_user_from_tenant(TenantId, UserId) ->
    gen_server:call(?MODULE, {remove_user_from_tenant, TenantId, UserId}).

%% @doc Get all users in a tenant
get_tenant_users(TenantId) ->
    gen_server:call(?MODULE, {get_tenant_users, TenantId}).

%% @doc Get all tenants for a user
get_user_tenants(UserId) ->
    gen_server:call(?MODULE, {get_user_tenants, UserId}).

%% @doc Set tenant context for current process
set_tenant_context(TenantId) ->
    put(current_tenant_id, TenantId),
    % Set PostgreSQL session variable for RLS
    case aethertalk_db:query("SET app.current_tenant_id = $1", [TenantId]) of
        {ok, _} -> ok;
        {error, Reason} -> 
            lager:error("Failed to set tenant context: ~p", [Reason]),
            {error, Reason}
    end.

%% @doc Get current tenant context
get_current_tenant() ->
    get(current_tenant_id).

%% @doc Clear tenant context
clear_tenant_context() ->
    erase(current_tenant_id),
    aethertalk_db:query("SET app.current_tenant_id = NULL", []).

%% @doc Get tenant statistics
get_tenant_stats(TenantId) ->
    gen_server:call(?MODULE, {get_tenant_stats, TenantId}).

%% @doc Check if tenant is within limits
check_tenant_limits(TenantId, Resource) ->
    gen_server:call(?MODULE, {check_tenant_limits, TenantId, Resource}).

%% @doc Check if tenant is active
is_tenant_active(TenantId) ->
    gen_server:call(?MODULE, {is_tenant_active, TenantId}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    % Create ETS table for tenant caching
    TenantCache = ets:new(tenant_cache, [set, protected, named_table]),
    
    % Start cache cleanup timer
    timer:send_interval(60000, cleanup_cache), % Every minute
    
    lager:info("Tenant manager started"),
    {ok, #state{
        tenant_cache = TenantCache,
        cache_ttl = ?CACHE_TTL
    }}.

handle_call({create_tenant, Name, Slug, Domain, Plan, MaxUsers, MaxStorageGB}, _From, State) ->
    Result = do_create_tenant(Name, Slug, Domain, Plan, MaxUsers, MaxStorageGB),
    {reply, Result, State};

handle_call({get_tenant, TenantId}, _From, State) ->
    Result = do_get_tenant(TenantId, State),
    {reply, Result, State};

handle_call({get_tenant_by_slug, Slug}, _From, State) ->
    Result = do_get_tenant_by_slug(Slug, State),
    {reply, Result, State};

handle_call({get_tenant_by_domain, Domain}, _From, State) ->
    Result = do_get_tenant_by_domain(Domain, State),
    {reply, Result, State};

handle_call({update_tenant, TenantId, Updates}, _From, State) ->
    Result = do_update_tenant(TenantId, Updates, State),
    {reply, Result, State};

handle_call({delete_tenant, TenantId}, _From, State) ->
    Result = do_delete_tenant(TenantId, State),
    {reply, Result, State};

handle_call(list_tenants, _From, State) ->
    Result = do_list_tenants(),
    {reply, Result, State};

handle_call({list_tenants, Limit, Offset}, _From, State) ->
    Result = do_list_tenants(Limit, Offset),
    {reply, Result, State};

handle_call({add_user_to_tenant, TenantId, UserId, Role}, _From, State) ->
    Result = do_add_user_to_tenant(TenantId, UserId, Role),
    {reply, Result, State};

handle_call({remove_user_from_tenant, TenantId, UserId}, _From, State) ->
    Result = do_remove_user_from_tenant(TenantId, UserId),
    {reply, Result, State};

handle_call({get_tenant_users, TenantId}, _From, State) ->
    Result = do_get_tenant_users(TenantId),
    {reply, Result, State};

handle_call({get_user_tenants, UserId}, _From, State) ->
    Result = do_get_user_tenants(UserId),
    {reply, Result, State};

handle_call({get_tenant_stats, TenantId}, _From, State) ->
    Result = do_get_tenant_stats(TenantId),
    {reply, Result, State};

handle_call({check_tenant_limits, TenantId, Resource}, _From, State) ->
    Result = do_check_tenant_limits(TenantId, Resource),
    {reply, Result, State};

handle_call({is_tenant_active, TenantId}, _From, State) ->
    Result = do_is_tenant_active(TenantId, State),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(cleanup_cache, State) ->
    do_cleanup_cache(State),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

do_create_tenant(Name, Slug, Domain, Plan, MaxUsers, MaxStorageGB) ->
    SQL = "INSERT INTO tenants (name, slug, domain, plan, max_users, max_storage_gb) 
           VALUES ($1, $2, $3, $4, $5, $6) 
           RETURNING id, created_at",
    
    case aethertalk_db:query(SQL, [Name, Slug, Domain, Plan, MaxUsers, MaxStorageGB]) of
        {ok, {_Columns, [{TenantId, CreatedAt}]}} ->
            lager:info("Created tenant ~s (~s) with ID ~s", [Name, Slug, TenantId]),
            Tenant = #{
                id => TenantId,
                name => Name,
                slug => Slug,
                domain => Domain,
                plan => Plan,
                max_users => MaxUsers,
                max_storage_gb => MaxStorageGB,
                is_active => true,
                created_at => CreatedAt
            },
            {ok, Tenant};
        {error, {error, error, <<"23505">>, unique_violation, _}} ->
            {error, slug_already_exists};
        {error, Reason} ->
            lager:error("Failed to create tenant: ~p", [Reason]),
            {error, Reason}
    end.

do_get_tenant(TenantId, State) ->
    % Check cache first
    case ets:lookup(State#state.tenant_cache, TenantId) of
        [{TenantId, Tenant, CachedAt}] ->
            Now = erlang:system_time(second),
            if
                Now - CachedAt < State#state.cache_ttl ->
                    {ok, Tenant};
                true ->
                    % Cache expired, fetch from DB
                    fetch_and_cache_tenant(TenantId, State)
            end;
        [] ->
            fetch_and_cache_tenant(TenantId, State)
    end.

fetch_and_cache_tenant(TenantId, State) ->
    SQL = "SELECT id, name, slug, domain, settings, plan, max_users, max_storage_gb, 
                  is_active, created_at, updated_at 
           FROM tenants WHERE id = $1",
    
    case aethertalk_db:query(SQL, [TenantId]) of
        {ok, {_Columns, [{Id, Name, Slug, Domain, Settings, Plan, MaxUsers, MaxStorageGB, 
                         IsActive, CreatedAt, UpdatedAt}]}} ->
            Tenant = #{
                id => Id,
                name => Name,
                slug => Slug,
                domain => Domain,
                settings => Settings,
                plan => Plan,
                max_users => MaxUsers,
                max_storage_gb => MaxStorageGB,
                is_active => IsActive,
                created_at => CreatedAt,
                updated_at => UpdatedAt
            },
            % Cache the result
            Now = erlang:system_time(second),
            ets:insert(State#state.tenant_cache, {TenantId, Tenant, Now}),
            {ok, Tenant};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            lager:error("Failed to fetch tenant ~s: ~p", [TenantId, Reason]),
            {error, Reason}
    end.

do_get_tenant_by_slug(Slug, State) ->
    SQL = "SELECT id, name, slug, domain, settings, plan, max_users, max_storage_gb, 
                  is_active, created_at, updated_at 
           FROM tenants WHERE slug = $1 AND is_active = TRUE",
    
    case aethertalk_db:query(SQL, [Slug]) of
        {ok, {_Columns, [{Id, Name, TenantSlug, Domain, Settings, Plan, MaxUsers, MaxStorageGB, 
                         IsActive, CreatedAt, UpdatedAt}]}} ->
            Tenant = #{
                id => Id,
                name => Name,
                slug => TenantSlug,
                domain => Domain,
                settings => Settings,
                plan => Plan,
                max_users => MaxUsers,
                max_storage_gb => MaxStorageGB,
                is_active => IsActive,
                created_at => CreatedAt,
                updated_at => UpdatedAt
            },
            % Cache the result
            Now = erlang:system_time(second),
            ets:insert(State#state.tenant_cache, {Id, Tenant, Now}),
            {ok, Tenant};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            lager:error("Failed to fetch tenant by slug ~s: ~p", [Slug, Reason]),
            {error, Reason}
    end.

do_get_tenant_by_domain(Domain, State) ->
    SQL = "SELECT id, name, slug, domain, settings, plan, max_users, max_storage_gb, 
                  is_active, created_at, updated_at 
           FROM tenants WHERE domain = $1 AND is_active = TRUE",
    
    case aethertalk_db:query(SQL, [Domain]) of
        {ok, {_Columns, [{Id, Name, Slug, TenantDomain, Settings, Plan, MaxUsers, MaxStorageGB, 
                         IsActive, CreatedAt, UpdatedAt}]}} ->
            Tenant = #{
                id => Id,
                name => Name,
                slug => Slug,
                domain => TenantDomain,
                settings => Settings,
                plan => Plan,
                max_users => MaxUsers,
                max_storage_gb => MaxStorageGB,
                is_active => IsActive,
                created_at => CreatedAt,
                updated_at => UpdatedAt
            },
            % Cache the result
            Now = erlang:system_time(second),
            ets:insert(State#state.tenant_cache, {Id, Tenant, Now}),
            {ok, Tenant};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            lager:error("Failed to fetch tenant by domain ~s: ~p", [Domain, Reason]),
            {error, Reason}
    end.

do_update_tenant(TenantId, Updates, State) ->
    % Build dynamic UPDATE query based on provided updates
    {SetClauses, Values} = build_update_clauses(Updates, 1, [], [TenantId]),
    
    case SetClauses of
        [] ->
            {error, no_updates_provided};
        _ ->
            SQL = "UPDATE tenants SET " ++ string:join(SetClauses, ", ") ++ 
                  ", updated_at = NOW() WHERE id = $" ++ integer_to_list(length(Values)) ++ 
                  " RETURNING updated_at",
            
            case aethertalk_db:query(SQL, lists:reverse(Values)) of
                {ok, {_Columns, [{UpdatedAt}]}} ->
                    % Invalidate cache
                    ets:delete(State#state.tenant_cache, TenantId),
                    lager:info("Updated tenant ~s", [TenantId]),
                    {ok, #{updated_at => UpdatedAt}};
                {ok, {_Columns, []}} ->
                    {error, not_found};
                {error, Reason} ->
                    lager:error("Failed to update tenant ~s: ~p", [TenantId, Reason]),
                    {error, Reason}
            end
    end.

build_update_clauses([], _ParamNum, Clauses, Values) ->
    {lists:reverse(Clauses), Values};
build_update_clauses([{Field, Value} | Rest], ParamNum, Clauses, Values) ->
    FieldStr = atom_to_list(Field),
    Clause = FieldStr ++ " = $" ++ integer_to_list(ParamNum),
    build_update_clauses(Rest, ParamNum + 1, [Clause | Clauses], [Value | Values]).

do_delete_tenant(TenantId, State) ->
    SQL = "UPDATE tenants SET is_active = FALSE, updated_at = NOW() WHERE id = $1",
    
    case aethertalk_db:query(SQL, [TenantId]) of
        {ok, {_Columns, _}} ->
            % Invalidate cache
            ets:delete(State#state.tenant_cache, TenantId),
            lager:info("Deleted tenant ~s", [TenantId]),
            ok;
        {error, Reason} ->
            lager:error("Failed to delete tenant ~s: ~p", [TenantId, Reason]),
            {error, Reason}
    end.

do_list_tenants() ->
    SQL = "SELECT id, name, slug, domain, plan, max_users, max_storage_gb, 
                  is_active, created_at 
           FROM tenants WHERE is_active = TRUE ORDER BY created_at DESC",
    
    case aethertalk_db:query(SQL, []) of
        {ok, {_Columns, Rows}} ->
            Tenants = [#{
                id => Id,
                name => Name,
                slug => Slug,
                domain => Domain,
                plan => Plan,
                max_users => MaxUsers,
                max_storage_gb => MaxStorageGB,
                is_active => IsActive,
                created_at => CreatedAt
            } || {Id, Name, Slug, Domain, Plan, MaxUsers, MaxStorageGB, IsActive, CreatedAt} <- Rows],
            {ok, Tenants};
        {error, Reason} ->
            lager:error("Failed to list tenants: ~p", [Reason]),
            {error, Reason}
    end.

do_list_tenants(Limit, Offset) ->
    SQL = "SELECT id, name, slug, domain, plan, max_users, max_storage_gb, 
                  is_active, created_at 
           FROM tenants WHERE is_active = TRUE 
           ORDER BY created_at DESC LIMIT $1 OFFSET $2",
    
    case aethertalk_db:query(SQL, [Limit, Offset]) of
        {ok, {_Columns, Rows}} ->
            Tenants = [#{
                id => Id,
                name => Name,
                slug => Slug,
                domain => Domain,
                plan => Plan,
                max_users => MaxUsers,
                max_storage_gb => MaxStorageGB,
                is_active => IsActive,
                created_at => CreatedAt
            } || {Id, Name, Slug, Domain, Plan, MaxUsers, MaxStorageGB, IsActive, CreatedAt} <- Rows],
            {ok, Tenants};
        {error, Reason} ->
            lager:error("Failed to list tenants: ~p", [Reason]),
            {error, Reason}
    end.

do_add_user_to_tenant(TenantId, UserId, Role) ->
    SQL = "INSERT INTO tenant_users (tenant_id, user_id, role) 
           VALUES ($1, $2, $3) 
           ON CONFLICT (tenant_id, user_id) 
           DO UPDATE SET role = $3, is_active = TRUE",
    
    case aethertalk_db:query(SQL, [TenantId, UserId, Role]) of
        {ok, _} ->
            % Update user's primary tenant
            UpdateSQL = "UPDATE users SET tenant_id = $1 WHERE id = $2",
            case aethertalk_db:query(UpdateSQL, [TenantId, UserId]) of
                {ok, _} ->
                    lager:info("Added user ~s to tenant ~s with role ~s", [UserId, TenantId, Role]),
                    ok;
                {error, Reason} ->
                    lager:error("Failed to update user tenant: ~p", [Reason]),
                    {error, Reason}
            end;
        {error, Reason} ->
            lager:error("Failed to add user ~s to tenant ~s: ~p", [UserId, TenantId, Reason]),
            {error, Reason}
    end.

do_remove_user_from_tenant(TenantId, UserId) ->
    SQL = "UPDATE tenant_users SET is_active = FALSE WHERE tenant_id = $1 AND user_id = $2",
    
    case aethertalk_db:query(SQL, [TenantId, UserId]) of
        {ok, _} ->
            lager:info("Removed user ~s from tenant ~s", [UserId, TenantId]),
            ok;
        {error, Reason} ->
            lager:error("Failed to remove user ~s from tenant ~s: ~p", [UserId, TenantId, Reason]),
            {error, Reason}
    end.

do_get_tenant_users(TenantId) ->
    SQL = "SELECT tu.user_id, tu.role, tu.joined_at, u.username, u.email, u.full_name 
           FROM tenant_users tu 
           JOIN users u ON tu.user_id = u.id 
           WHERE tu.tenant_id = $1 AND tu.is_active = TRUE 
           ORDER BY tu.joined_at",
    
    case aethertalk_db:query(SQL, [TenantId]) of
        {ok, {_Columns, Rows}} ->
            Users = [#{
                user_id => UserId,
                role => Role,
                joined_at => JoinedAt,
                username => Username,
                email => Email,
                full_name => FullName
            } || {UserId, Role, JoinedAt, Username, Email, FullName} <- Rows],
            {ok, Users};
        {error, Reason} ->
            lager:error("Failed to get tenant users for ~s: ~p", [TenantId, Reason]),
            {error, Reason}
    end.

do_get_user_tenants(UserId) ->
    SQL = "SELECT tu.tenant_id, tu.role, tu.joined_at, t.name, t.slug, t.domain 
           FROM tenant_users tu 
           JOIN tenants t ON tu.tenant_id = t.id 
           WHERE tu.user_id = $1 AND tu.is_active = TRUE AND t.is_active = TRUE 
           ORDER BY tu.joined_at",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, Rows}} ->
            Tenants = [#{
                tenant_id => TenantId,
                role => Role,
                joined_at => JoinedAt,
                name => Name,
                slug => Slug,
                domain => Domain
            } || {TenantId, Role, JoinedAt, Name, Slug, Domain} <- Rows],
            {ok, Tenants};
        {error, Reason} ->
            lager:error("Failed to get user tenants for ~s: ~p", [UserId, Reason]),
            {error, Reason}
    end.

do_get_tenant_stats(TenantId) ->
    % Since we don't have the view yet, let's calculate stats manually
    UserCountSQL = "SELECT COUNT(*) FROM tenant_users WHERE tenant_id = $1 AND is_active = TRUE",
    ChatCountSQL = "SELECT COUNT(*) FROM chats WHERE tenant_id = $1",
    MessageCountSQL = "SELECT COUNT(*) FROM messages WHERE tenant_id = $1 AND is_deleted = FALSE",
    StorageSQL = "SELECT COALESCE(SUM(file_size), 0) FROM file_uploads WHERE tenant_id = $1",
    TenantSQL = "SELECT max_users, max_storage_gb FROM tenants WHERE id = $1",
    
    try
        {ok, {_, [{UserCount}]}} = aethertalk_db:query(UserCountSQL, [TenantId]),
        {ok, {_, [{ChatCount}]}} = aethertalk_db:query(ChatCountSQL, [TenantId]),
        {ok, {_, [{MessageCount}]}} = aethertalk_db:query(MessageCountSQL, [TenantId]),
        {ok, {_, [{StorageUsed}]}} = aethertalk_db:query(StorageSQL, [TenantId]),
        {ok, {_, [{MaxUsers, MaxStorageGB}]}} = aethertalk_db:query(TenantSQL, [TenantId]),
        
        MaxStorage = MaxStorageGB * 1024 * 1024 * 1024, % Convert GB to bytes
        
        Stats = #{
            user_count => UserCount,
            chat_count => ChatCount,
            message_count => MessageCount,
            storage_used_bytes => StorageUsed,
            max_users => MaxUsers,
            max_storage_bytes => MaxStorage,
            storage_usage_percent => case MaxStorage of
                0 -> 0;
                _ -> (StorageUsed * 100) div MaxStorage
            end,
            user_usage_percent => case MaxUsers of
                0 -> 0;
                _ -> (UserCount * 100) div MaxUsers
            end
        },
        {ok, Stats}
    catch
        _:Reason ->
            lager:error("Failed to get tenant stats for ~s: ~p", [TenantId, Reason]),
            {error, Reason}
    end.

do_check_tenant_limits(TenantId, Resource) ->
    case do_get_tenant_stats(TenantId) of
        {ok, Stats} ->
            case Resource of
                users ->
                    UserCount = maps:get(user_count, Stats),
                    MaxUsers = maps:get(max_users, Stats),
                    {ok, UserCount < MaxUsers};
                storage ->
                    StorageUsed = maps:get(storage_used_bytes, Stats),
                    MaxStorage = maps:get(max_storage_bytes, Stats),
                    {ok, StorageUsed < MaxStorage};
                _ ->
                    {error, unknown_resource}
            end;
        Error ->
            Error
    end.

do_is_tenant_active(TenantId, State) ->
    case do_get_tenant(TenantId, State) of
        {ok, Tenant} ->
            {ok, maps:get(is_active, Tenant, false)};
        {error, not_found} ->
            {ok, false};
        Error ->
            Error
    end.

do_cleanup_cache(State) ->
    Now = erlang:system_time(second),
    TTL = State#state.cache_ttl,
    
    % Get all cache entries
    AllEntries = ets:tab2list(State#state.tenant_cache),
    
    % Remove expired entries
    ExpiredCount = lists:foldl(fun({TenantId, _Tenant, CachedAt}, Count) ->
        if
            Now - CachedAt >= TTL ->
                ets:delete(State#state.tenant_cache, TenantId),
                Count + 1;
            true ->
                Count
        end
    end, 0, AllEntries),
    
    if
        ExpiredCount > 0 ->
            lager:debug("Cleaned up ~p expired tenant cache entries", [ExpiredCount]);
        true ->
            ok
    end.