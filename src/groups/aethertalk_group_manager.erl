%%%-------------------------------------------------------------------
%%% @doc
%%% Group Management Service for AetherTalk
%%% Handles group creation, member management, admin controls, and settings
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_group_manager).
-behaviour(gen_server).

% OTP callbacks
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    create_group/3,
    get_group/1,
    update_group/2,
    delete_group/2,
    add_member/3,
    remove_member/3,
    promote_member/3,
    demote_member/3,
    get_group_members/1,
    get_user_groups/1,
    update_group_settings/3,
    leave_group/2,
    get_group_info/2,
    create_broadcast_list/3,
    get_broadcast_lists/1,
    send_broadcast/3
]).

-include("aethertalk.hrl").

-record(state, {}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Create a new group
create_group(CreatorId, GroupName, Description) ->
    gen_server:call(?MODULE, {create_group, CreatorId, GroupName, Description}).

%% @doc Get group information
get_group(GroupId) ->
    gen_server:call(?MODULE, {get_group, GroupId}).

%% @doc Update group information
update_group(GroupId, Updates) ->
    gen_server:call(?MODULE, {update_group, GroupId, Updates}).

%% @doc Delete a group
delete_group(GroupId, AdminId) ->
    gen_server:call(?MODULE, {delete_group, GroupId, AdminId}).

%% @doc Add member to group
add_member(GroupId, UserId, AdminId) ->
    gen_server:call(?MODULE, {add_member, GroupId, UserId, AdminId}).

%% @doc Remove member from group
remove_member(GroupId, UserId, AdminId) ->
    gen_server:call(?MODULE, {remove_member, GroupId, UserId, AdminId}).

%% @doc Promote member to admin
promote_member(GroupId, UserId, AdminId) ->
    gen_server:call(?MODULE, {promote_member, GroupId, UserId, AdminId}).

%% @doc Demote admin to member
demote_member(GroupId, UserId, AdminId) ->
    gen_server:call(?MODULE, {demote_member, GroupId, UserId, AdminId}).

%% @doc Get group members
get_group_members(GroupId) ->
    gen_server:call(?MODULE, {get_group_members, GroupId}).

%% @doc Get user's groups
get_user_groups(UserId) ->
    gen_server:call(?MODULE, {get_user_groups, UserId}).

%% @doc Update group settings
update_group_settings(GroupId, Settings, AdminId) ->
    gen_server:call(?MODULE, {update_group_settings, GroupId, Settings, AdminId}).

%% @doc Leave group
leave_group(GroupId, UserId) ->
    gen_server:call(?MODULE, {leave_group, GroupId, UserId}).

%% @doc Get group info for user
get_group_info(GroupId, UserId) ->
    gen_server:call(?MODULE, {get_group_info, GroupId, UserId}).

%% @doc Create broadcast list
create_broadcast_list(CreatorId, Name, MemberIds) ->
    gen_server:call(?MODULE, {create_broadcast_list, CreatorId, Name, MemberIds}).

%% @doc Get user's broadcast lists
get_broadcast_lists(UserId) ->
    gen_server:call(?MODULE, {get_broadcast_lists, UserId}).

%% @doc Send broadcast message
send_broadcast(BroadcastId, SenderId, Message) ->
    gen_server:call(?MODULE, {send_broadcast, BroadcastId, SenderId, Message}).

%% ===================================================================
%% gen_server callbacks
%% ===================================================================

init([]) ->
    lager:info("Group Manager started"),
    {ok, #state{}}.

handle_call({create_group, CreatorId, GroupName, Description}, _From, State) ->
    Result = do_create_group(CreatorId, GroupName, Description),
    {reply, Result, State};

handle_call({get_group, GroupId}, _From, State) ->
    Result = do_get_group(GroupId),
    {reply, Result, State};

handle_call({update_group, GroupId, Updates}, _From, State) ->
    Result = do_update_group(GroupId, Updates),
    {reply, Result, State};

handle_call({delete_group, GroupId, AdminId}, _From, State) ->
    Result = do_delete_group(GroupId, AdminId),
    {reply, Result, State};

handle_call({add_member, GroupId, UserId, AdminId}, _From, State) ->
    Result = do_add_member(GroupId, UserId, AdminId),
    {reply, Result, State};

handle_call({remove_member, GroupId, UserId, AdminId}, _From, State) ->
    Result = do_remove_member(GroupId, UserId, AdminId),
    {reply, Result, State};

handle_call({promote_member, GroupId, UserId, AdminId}, _From, State) ->
    Result = do_promote_member(GroupId, UserId, AdminId),
    {reply, Result, State};

handle_call({demote_member, GroupId, UserId, AdminId}, _From, State) ->
    Result = do_demote_member(GroupId, UserId, AdminId),
    {reply, Result, State};

handle_call({get_group_members, GroupId}, _From, State) ->
    Result = do_get_group_members(GroupId),
    {reply, Result, State};

handle_call({get_user_groups, UserId}, _From, State) ->
    Result = do_get_user_groups(UserId),
    {reply, Result, State};

handle_call({update_group_settings, GroupId, Settings, AdminId}, _From, State) ->
    Result = do_update_group_settings(GroupId, Settings, AdminId),
    {reply, Result, State};

handle_call({leave_group, GroupId, UserId}, _From, State) ->
    Result = do_leave_group(GroupId, UserId),
    {reply, Result, State};

handle_call({get_group_info, GroupId, UserId}, _From, State) ->
    Result = do_get_group_info(GroupId, UserId),
    {reply, Result, State};

handle_call({create_broadcast_list, CreatorId, Name, MemberIds}, _From, State) ->
    Result = do_create_broadcast_list(CreatorId, Name, MemberIds),
    {reply, Result, State};

handle_call({get_broadcast_lists, UserId}, _From, State) ->
    Result = do_get_broadcast_lists(UserId),
    {reply, Result, State};

handle_call({send_broadcast, BroadcastId, SenderId, Message}, _From, State) ->
    Result = do_send_broadcast(BroadcastId, SenderId, Message),
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

%% ===================================================================
%% Internal functions
%% ===================================================================

do_create_group(CreatorId, GroupName, Description) ->
    GroupId = aethertalk_utils:generate_uuid(),
    ChatId = aethertalk_utils:generate_uuid(),
    
    % Create group record
    SQL = "INSERT INTO groups (id, name, description, creator_id, chat_id, created_at, updated_at) 
           VALUES ($1, $2, $3, $4, $5, NOW(), NOW()) RETURNING created_at",
    
    case aethertalk_db:query(SQL, [GroupId, GroupName, Description, CreatorId, ChatId]) of
        {ok, {_Columns, [{CreatedAt}]}} ->
            % Create associated chat
            ChatSQL = "INSERT INTO chats (id, type, name, created_by, created_at, updated_at) 
                      VALUES ($1, 'group', $2, $3, NOW(), NOW())",
            case aethertalk_db:query(ChatSQL, [ChatId, GroupName, CreatorId]) of
                {ok, 1} ->
                    % Add creator as admin member
                    case do_add_member_internal(GroupId, CreatorId, <<"admin">>) of
                        {ok, _} ->
                            Group = #{
                                id => GroupId,
                                name => GroupName,
                                description => Description,
                                creator_id => CreatorId,
                                chat_id => ChatId,
                                created_at => CreatedAt,
                                member_count => 1
                            },
                            
                            % Notify about group creation
                            notify_group_created(Group),
                            {ok, Group};
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_get_group(GroupId) ->
    SQL = "SELECT g.id, g.name, g.description, g.creator_id, g.chat_id, g.avatar_url,
                  g.settings, g.created_at, g.updated_at,
                  COUNT(gm.user_id) as member_count
           FROM groups g
           LEFT JOIN group_members gm ON g.id = gm.group_id
           WHERE g.id = $1 AND g.is_deleted = FALSE
           GROUP BY g.id",
    
    case aethertalk_db:query(SQL, [GroupId]) of
        {ok, {_Columns, [{Id, Name, Description, CreatorId, ChatId, AvatarUrl,
                         Settings, CreatedAt, UpdatedAt, MemberCount}]}} ->
            Group = #{
                id => Id,
                name => Name,
                description => Description,
                creator_id => CreatorId,
                chat_id => ChatId,
                avatar_url => AvatarUrl,
                settings => Settings,
                created_at => CreatedAt,
                updated_at => UpdatedAt,
                member_count => MemberCount
            },
            {ok, Group};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_update_group(GroupId, Updates) ->
    % Build dynamic update query
    {SetClause, Values} = build_update_clause(Updates, 1),
    SQL = "UPDATE groups SET " ++ SetClause ++ ", updated_at = NOW() 
           WHERE id = $" ++ integer_to_list(length(Values) + 1) ++ " RETURNING updated_at",
    
    case aethertalk_db:query(SQL, Values ++ [GroupId]) of
        {ok, {_Columns, [{UpdatedAt}]}} ->
            % Notify group members about update
            notify_group_updated(GroupId, Updates),
            {ok, #{updated_at => UpdatedAt}};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_delete_group(GroupId, AdminId) ->
    % Check if user is admin
    case check_admin_permission(GroupId, AdminId) of
        ok ->
            % Soft delete the group
            SQL = "UPDATE groups SET is_deleted = TRUE, updated_at = NOW() WHERE id = $1",
            case aethertalk_db:query(SQL, [GroupId]) of
                {ok, 1} ->
                    % Notify all members about group deletion
                    notify_group_deleted(GroupId),
                    ok;
                {ok, 0} ->
                    {error, not_found};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_add_member(GroupId, UserId, AdminId) ->
    % Check if requester is admin
    case check_admin_permission(GroupId, AdminId) of
        ok ->
            do_add_member_internal(GroupId, UserId, <<"member">>);
        {error, Reason} ->
            {error, Reason}
    end.

do_add_member_internal(GroupId, UserId, Role) ->
    % Check if user is already a member
    CheckSQL = "SELECT id FROM group_members WHERE group_id = $1 AND user_id = $2",
    case aethertalk_db:query(CheckSQL, [GroupId, UserId]) of
        {ok, {_Columns, []}} ->
            % Add new member
            InsertSQL = "INSERT INTO group_members (group_id, user_id, role, joined_at) 
                        VALUES ($1, $2, $3, NOW()) RETURNING id, joined_at",
            case aethertalk_db:query(InsertSQL, [GroupId, UserId, Role]) of
                {ok, {_Cols, [{MemberId, JoinedAt}]}} ->
                    Member = #{
                        id => MemberId,
                        group_id => GroupId,
                        user_id => UserId,
                        role => Role,
                        joined_at => JoinedAt
                    },
                    
                    % Notify group about new member
                    notify_member_added(GroupId, UserId),
                    {ok, Member};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, {_Columns, [_]}} ->
            {error, already_member};
        {error, Reason} ->
            {error, Reason}
    end.

do_remove_member(GroupId, UserId, AdminId) ->
    % Check if requester is admin
    case check_admin_permission(GroupId, AdminId) of
        ok ->
            % Cannot remove the creator
            case is_group_creator(GroupId, UserId) of
                true ->
                    {error, cannot_remove_creator};
                false ->
                    SQL = "DELETE FROM group_members WHERE group_id = $1 AND user_id = $2",
                    case aethertalk_db:query(SQL, [GroupId, UserId]) of
                        {ok, 1} ->
                            % Notify group about member removal
                            notify_member_removed(GroupId, UserId),
                            ok;
                        {ok, 0} ->
                            {error, not_member};
                        {error, Reason} ->
                            {error, Reason}
                    end
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_promote_member(GroupId, UserId, AdminId) ->
    % Check if requester is admin
    case check_admin_permission(GroupId, AdminId) of
        ok ->
            SQL = "UPDATE group_members SET role = 'admin' 
                   WHERE group_id = $1 AND user_id = $2 AND role = 'member'",
            case aethertalk_db:query(SQL, [GroupId, UserId]) of
                {ok, 1} ->
                    % Notify group about promotion
                    notify_member_promoted(GroupId, UserId),
                    ok;
                {ok, 0} ->
                    {error, not_member_or_already_admin};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_demote_member(GroupId, UserId, AdminId) ->
    % Check if requester is admin
    case check_admin_permission(GroupId, AdminId) of
        ok ->
            % Cannot demote the creator
            case is_group_creator(GroupId, UserId) of
                true ->
                    {error, cannot_demote_creator};
                false ->
                    SQL = "UPDATE group_members SET role = 'member' 
                           WHERE group_id = $1 AND user_id = $2 AND role = 'admin'",
                    case aethertalk_db:query(SQL, [GroupId, UserId]) of
                        {ok, 1} ->
                            % Notify group about demotion
                            notify_member_demoted(GroupId, UserId),
                            ok;
                        {ok, 0} ->
                            {error, not_admin};
                        {error, Reason} ->
                            {error, Reason}
                    end
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_get_group_members(GroupId) ->
    SQL = "SELECT gm.user_id, gm.role, gm.joined_at, u.username, u.full_name, u.avatar_url
           FROM group_members gm
           JOIN users u ON gm.user_id = u.id
           WHERE gm.group_id = $1
           ORDER BY gm.joined_at ASC",
    
    case aethertalk_db:query(SQL, [GroupId]) of
        {ok, {_Columns, Rows}} ->
            Members = lists:map(fun({UserId, Role, JoinedAt, Username, FullName, AvatarUrl}) ->
                #{
                    user_id => UserId,
                    role => Role,
                    joined_at => JoinedAt,
                    username => Username,
                    full_name => FullName,
                    avatar_url => AvatarUrl
                }
            end, Rows),
            {ok, Members};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_user_groups(UserId) ->
    SQL = "SELECT g.id, g.name, g.description, g.avatar_url, g.created_at,
                  gm.role, gm.joined_at,
                  COUNT(gm2.user_id) as member_count
           FROM groups g
           JOIN group_members gm ON g.id = gm.group_id
           LEFT JOIN group_members gm2 ON g.id = gm2.group_id
           WHERE gm.user_id = $1 AND g.is_deleted = FALSE
           GROUP BY g.id, gm.role, gm.joined_at
           ORDER BY gm.joined_at DESC",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, Rows}} ->
            Groups = lists:map(fun({GroupId, Name, Description, AvatarUrl, CreatedAt,
                                   Role, JoinedAt, MemberCount}) ->
                #{
                    id => GroupId,
                    name => Name,
                    description => Description,
                    avatar_url => AvatarUrl,
                    created_at => CreatedAt,
                    role => Role,
                    joined_at => JoinedAt,
                    member_count => MemberCount
                }
            end, Rows),
            {ok, Groups};
        {error, Reason} ->
            {error, Reason}
    end.

do_update_group_settings(GroupId, Settings, AdminId) ->
    % Check if requester is admin
    case check_admin_permission(GroupId, AdminId) of
        ok ->
            SQL = "UPDATE groups SET settings = $1, updated_at = NOW() 
                   WHERE id = $2 RETURNING updated_at",
            case aethertalk_db:query(SQL, [Settings, GroupId]) of
                {ok, {_Columns, [{UpdatedAt}]}} ->
                    % Notify group about settings update
                    notify_group_settings_updated(GroupId, Settings),
                    {ok, #{updated_at => UpdatedAt}};
                {ok, {_Columns, []}} ->
                    {error, not_found};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_leave_group(GroupId, UserId) ->
    % Check if user is the creator
    case is_group_creator(GroupId, UserId) of
        true ->
            {error, creator_cannot_leave};
        false ->
            SQL = "DELETE FROM group_members WHERE group_id = $1 AND user_id = $2",
            case aethertalk_db:query(SQL, [GroupId, UserId]) of
                {ok, 1} ->
                    % Notify group about member leaving
                    notify_member_left(GroupId, UserId),
                    ok;
                {ok, 0} ->
                    {error, not_member};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

do_get_group_info(GroupId, UserId) ->
    % Check if user is a member
    case is_group_member(GroupId, UserId) of
        true ->
            do_get_group(GroupId);
        false ->
            {error, not_member}
    end.

do_create_broadcast_list(CreatorId, Name, MemberIds) ->
    BroadcastId = aethertalk_utils:generate_uuid(),
    
    % Create broadcast list
    SQL = "INSERT INTO broadcast_lists (id, name, creator_id, created_at, updated_at) 
           VALUES ($1, $2, $3, NOW(), NOW()) RETURNING created_at",
    
    case aethertalk_db:query(SQL, [BroadcastId, Name, CreatorId]) of
        {ok, {_Columns, [{CreatedAt}]}} ->
            % Add members to broadcast list
            case add_broadcast_members(BroadcastId, MemberIds) of
                ok ->
                    BroadcastList = #{
                        id => BroadcastId,
                        name => Name,
                        creator_id => CreatorId,
                        created_at => CreatedAt,
                        member_count => length(MemberIds)
                    },
                    {ok, BroadcastList};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_get_broadcast_lists(UserId) ->
    SQL = "SELECT bl.id, bl.name, bl.created_at,
                  COUNT(blm.user_id) as member_count
           FROM broadcast_lists bl
           LEFT JOIN broadcast_list_members blm ON bl.id = blm.broadcast_list_id
           WHERE bl.creator_id = $1
           GROUP BY bl.id
           ORDER BY bl.created_at DESC",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, Rows}} ->
            BroadcastLists = lists:map(fun({Id, Name, CreatedAt, MemberCount}) ->
                #{
                    id => Id,
                    name => Name,
                    created_at => CreatedAt,
                    member_count => MemberCount
                }
            end, Rows),
            {ok, BroadcastLists};
        {error, Reason} ->
            {error, Reason}
    end.

do_send_broadcast(BroadcastId, SenderId, Message) ->
    % Check if sender is the creator of broadcast list
    case is_broadcast_creator(BroadcastId, SenderId) of
        true ->
            % Get broadcast list members
            SQL = "SELECT user_id FROM broadcast_list_members WHERE broadcast_list_id = $1",
            case aethertalk_db:query(SQL, [BroadcastId]) of
                {ok, {_Columns, Rows}} ->
                    MemberIds = [UserId || {UserId} <- Rows],
                    % Send individual messages to each member
                    send_broadcast_messages(SenderId, MemberIds, Message),
                    {ok, #{sent_to => length(MemberIds)}};
                {error, Reason} ->
                    {error, Reason}
            end;
        false ->
            {error, not_authorized}
    end.

%% Helper functions

build_update_clause(Updates, StartIndex) ->
    build_update_clause(maps:to_list(Updates), StartIndex, [], []).

build_update_clause([], _Index, Clauses, Values) ->
    {string:join(lists:reverse(Clauses), ", "), lists:reverse(Values)};
build_update_clause([{Key, Value} | Rest], Index, Clauses, Values) ->
    Clause = atom_to_list(Key) ++ " = $" ++ integer_to_list(Index),
    build_update_clause(Rest, Index + 1, [Clause | Clauses], [Value | Values]).

check_admin_permission(GroupId, UserId) ->
    SQL = "SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2",
    case aethertalk_db:query(SQL, [GroupId, UserId]) of
        {ok, {_Columns, [{<<"admin">>}]}} ->
            ok;
        {ok, {_Columns, [{<<"member">>}]}} ->
            {error, not_admin};
        {ok, {_Columns, []}} ->
            {error, not_member};
        {error, Reason} ->
            {error, Reason}
    end.

is_group_creator(GroupId, UserId) ->
    SQL = "SELECT creator_id FROM groups WHERE id = $1",
    case aethertalk_db:query(SQL, [GroupId]) of
        {ok, {_Columns, [{UserId}]}} ->
            true;
        _ ->
            false
    end.

is_group_member(GroupId, UserId) ->
    SQL = "SELECT id FROM group_members WHERE group_id = $1 AND user_id = $2",
    case aethertalk_db:query(SQL, [GroupId, UserId]) of
        {ok, {_Columns, [_]}} ->
            true;
        _ ->
            false
    end.

is_broadcast_creator(BroadcastId, UserId) ->
    SQL = "SELECT creator_id FROM broadcast_lists WHERE id = $1",
    case aethertalk_db:query(SQL, [BroadcastId]) of
        {ok, {_Columns, [{UserId}]}} ->
            true;
        _ ->
            false
    end.

add_broadcast_members(BroadcastId, MemberIds) ->
    Values = [[BroadcastId, MemberId] || MemberId <- MemberIds],
    SQL = "INSERT INTO broadcast_list_members (broadcast_list_id, user_id) VALUES ($1, $2)",
    
    try
        lists:foreach(fun([BId, UId]) ->
            case aethertalk_db:query(SQL, [BId, UId]) of
                {ok, 1} -> ok;
                {error, Reason} -> throw({error, Reason})
            end
        end, Values),
        ok
    catch
        throw:Error -> Error
    end.

send_broadcast_messages(SenderId, MemberIds, Message) ->
    % This would integrate with the message router to send individual messages
    lists:foreach(fun(MemberId) ->
        % Create individual chat if doesn't exist and send message
        spawn(fun() ->
            aethertalk_message_router:send_message(SenderId, MemberId, Message)
        end)
    end, MemberIds).

%% Notification functions

notify_group_created(Group) ->
    lager:info("Group created: ~p", [maps:get(id, Group)]).

notify_group_updated(GroupId, _Updates) ->
    lager:info("Group updated: ~p", [GroupId]).

notify_group_deleted(GroupId) ->
    lager:info("Group deleted: ~p", [GroupId]).

notify_member_added(GroupId, UserId) ->
    lager:info("Member ~p added to group ~p", [UserId, GroupId]).

notify_member_removed(GroupId, UserId) ->
    lager:info("Member ~p removed from group ~p", [UserId, GroupId]).

notify_member_promoted(GroupId, UserId) ->
    lager:info("Member ~p promoted to admin in group ~p", [UserId, GroupId]).

notify_member_demoted(GroupId, UserId) ->
    lager:info("Admin ~p demoted to member in group ~p", [UserId, GroupId]).

notify_member_left(GroupId, UserId) ->
    lager:info("Member ~p left group ~p", [UserId, GroupId]).

notify_group_settings_updated(GroupId, _Settings) ->
    lager:info("Group settings updated for group ~p", [GroupId]).