%%%-------------------------------------------------------------------
%% @doc AetherTalk message routing system
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_message_router).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    send_message/1,
    get_messages/3,
    get_chat_messages/4,
    mark_message_delivered/2,
    mark_message_read/2,
    edit_message/3,
    delete_message/2,
    forward_message/3,
    add_reaction/3,
    remove_reaction/3,
    get_message_reactions/1,
    create_chat/1,
    get_chat/1,
    get_user_chats/1,
    update_chat/2,
    archive_chat/2,
    pin_chat/2,
    mute_chat/3
]).

-include("aethertalk.hrl").

-record(state, {}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    io:format("Message router started~n"),
    {ok, #state{}}.

handle_call({send_message, MessageData}, _From, State) ->
    Result = do_send_message(MessageData),
    {reply, Result, State};

handle_call({get_messages, ChatId, Limit, Offset}, _From, State) ->
    Result = do_get_messages(ChatId, Limit, Offset),
    {reply, Result, State};

handle_call({get_chat_messages, ChatId, Limit, Offset, UserId}, _From, State) ->
    Result = do_get_chat_messages(ChatId, Limit, Offset, UserId),
    {reply, Result, State};

handle_call({mark_message_delivered, MessageId, UserId}, _From, State) ->
    Result = do_mark_message_delivered(MessageId, UserId),
    {reply, Result, State};

handle_call({mark_message_read, MessageId, UserId}, _From, State) ->
    Result = do_mark_message_read(MessageId, UserId),
    {reply, Result, State};

handle_call({edit_message, MessageId, NewContent, UserId}, _From, State) ->
    Result = do_edit_message(MessageId, NewContent, UserId),
    {reply, Result, State};

handle_call({delete_message, MessageId, UserId}, _From, State) ->
    Result = do_delete_message(MessageId, UserId),
    {reply, Result, State};

handle_call({forward_message, MessageId, ToChatId, UserId}, _From, State) ->
    Result = do_forward_message(MessageId, ToChatId, UserId),
    {reply, Result, State};

handle_call({add_reaction, MessageId, UserId, Reaction}, _From, State) ->
    Result = do_add_reaction(MessageId, UserId, Reaction),
    {reply, Result, State};

handle_call({remove_reaction, MessageId, UserId, Reaction}, _From, State) ->
    Result = do_remove_reaction(MessageId, UserId, Reaction),
    {reply, Result, State};

handle_call({get_message_reactions, MessageId}, _From, State) ->
    Result = do_get_message_reactions(MessageId),
    {reply, Result, State};

handle_call({create_chat, ChatData}, _From, State) ->
    Result = do_create_chat(ChatData),
    {reply, Result, State};

handle_call({get_chat, ChatId}, _From, State) ->
    Result = do_get_chat(ChatId),
    {reply, Result, State};

handle_call({get_user_chats, UserId}, _From, State) ->
    Result = do_get_user_chats(UserId),
    {reply, Result, State};

handle_call({update_chat, ChatId, Updates}, _From, State) ->
    Result = do_update_chat(ChatId, Updates),
    {reply, Result, State};

handle_call({archive_chat, ChatId, UserId}, _From, State) ->
    Result = do_archive_chat(ChatId, UserId),
    {reply, Result, State};

handle_call({pin_chat, ChatId, UserId}, _From, State) ->
    Result = do_pin_chat(ChatId, UserId),
    {reply, Result, State};

handle_call({mute_chat, ChatId, UserId, Duration}, _From, State) ->
    Result = do_mute_chat(ChatId, UserId, Duration),
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

send_message(MessageData) ->
    gen_server:call(?MODULE, {send_message, MessageData}).

get_messages(ChatId, Limit, Offset) ->
    gen_server:call(?MODULE, {get_messages, ChatId, Limit, Offset}).

get_chat_messages(ChatId, Limit, Offset, UserId) ->
    gen_server:call(?MODULE, {get_chat_messages, ChatId, Limit, Offset, UserId}).

mark_message_delivered(MessageId, UserId) ->
    gen_server:call(?MODULE, {mark_message_delivered, MessageId, UserId}).

mark_message_read(MessageId, UserId) ->
    gen_server:call(?MODULE, {mark_message_read, MessageId, UserId}).

edit_message(MessageId, NewContent, UserId) ->
    gen_server:call(?MODULE, {edit_message, MessageId, NewContent, UserId}).

delete_message(MessageId, UserId) ->
    gen_server:call(?MODULE, {delete_message, MessageId, UserId}).

forward_message(MessageId, ToChatId, UserId) ->
    gen_server:call(?MODULE, {forward_message, MessageId, ToChatId, UserId}).

add_reaction(MessageId, UserId, Reaction) ->
    gen_server:call(?MODULE, {add_reaction, MessageId, UserId, Reaction}).

remove_reaction(MessageId, UserId, Reaction) ->
    gen_server:call(?MODULE, {remove_reaction, MessageId, UserId, Reaction}).

get_message_reactions(MessageId) ->
    gen_server:call(?MODULE, {get_message_reactions, MessageId}).

create_chat(ChatData) ->
    gen_server:call(?MODULE, {create_chat, ChatData}).

get_chat(ChatId) ->
    gen_server:call(?MODULE, {get_chat, ChatId}).

get_user_chats(UserId) ->
    gen_server:call(?MODULE, {get_user_chats, UserId}).

update_chat(ChatId, Updates) ->
    gen_server:call(?MODULE, {update_chat, ChatId, Updates}).

archive_chat(ChatId, UserId) ->
    gen_server:call(?MODULE, {archive_chat, ChatId, UserId}).

pin_chat(ChatId, UserId) ->
    gen_server:call(?MODULE, {pin_chat, ChatId, UserId}).

mute_chat(ChatId, UserId, Duration) ->
    gen_server:call(?MODULE, {mute_chat, ChatId, UserId, Duration}).

%% Internal functions

do_send_message(MessageData) ->
    ChatId = maps:get(chat_id, MessageData),
    SenderId = maps:get(sender_id, MessageData),
    MessageType = maps:get(message_type, MessageData, ?MSG_TYPE_TEXT),
    Content = maps:get(content, MessageData, null),
    MediaUrl = maps:get(media_url, MessageData, null),
    MediaMetadata = maps:get(media_metadata, MessageData, #{}),
    ReplyToId = maps:get(reply_to_id, MessageData, null),
    ExpiresAt = maps:get(expires_at, MessageData, null),
    
    % Validate message data
    case validate_message_data(MessageData) of
        ok ->
            % Check if user has permission to send to this chat
            case check_send_permission(SenderId, ChatId) of
                ok ->
                    % Insert message into database
                    SQL = "INSERT INTO messages (chat_id, sender_id, message_type, content, media_url, 
                                               media_metadata, reply_to_id, expires_at) 
                           VALUES ($1, $2, $3, $4, $5, $6, $7, $8) 
                           RETURNING id, created_at",
                    Params = [
                        ChatId, SenderId, MessageType, Content, MediaUrl,
                        jsx:encode(MediaMetadata), ReplyToId, ExpiresAt
                    ],
                    
                    case aethertalk_db:query(SQL, Params) of
                        {ok, {_Columns, [{MessageId, CreatedAt}]}} ->
                            % Update chat's last message
                            update_chat_last_message(ChatId, MessageId, CreatedAt),
                            
                            % Create message record
                            Message = #{
                                id => MessageId,
                                chat_id => ChatId,
                                sender_id => SenderId,
                                message_type => MessageType,
                                content => Content,
                                media_url => MediaUrl,
                                media_metadata => MediaMetadata,
                                reply_to_id => ReplyToId,
                                expires_at => ExpiresAt,
                                delivery_status => ?DELIVERY_SENT,
                                created_at => CreatedAt
                            },
                            
                            % Send real-time notification to chat participants
                            notify_chat_participants(ChatId, Message, SenderId),
                            
                            % Handle translation if needed
                            handle_message_translation(Message),
                            
                            io:format("Message sent successfully: ~p~n", [MessageId]),
                            {ok, Message};
                        {error, Reason} ->
                            io:format("Failed to send message: ~p~n", [Reason]),
                            {error, message_send_failed}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, ValidationError} ->
            {error, ValidationError}
    end.

do_get_messages(ChatId, Limit, Offset) ->
    SQL = "SELECT m.id, m.chat_id, m.sender_id, m.reply_to_id, m.forward_from_id,
                  m.message_type, m.content, m.media_url, m.media_metadata,
                  m.is_edited, m.is_deleted, m.is_forwarded, m.delivery_status,
                  m.expires_at, m.created_at, m.updated_at,
                  u.username, u.display_name, u.profile_picture_url
           FROM messages m
           JOIN users u ON m.sender_id = u.id
           WHERE m.chat_id = $1 AND m.is_deleted = FALSE
           ORDER BY m.created_at DESC
           LIMIT $2 OFFSET $3",
    
    case aethertalk_db:query(SQL, [ChatId, Limit, Offset]) of
        {ok, {_Columns, Rows}} ->
            Messages = [row_to_message_map(Row) || Row <- Rows],
            {ok, Messages};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_chat_messages(ChatId, Limit, Offset, UserId) ->
    % Check if user has access to this chat
    case check_chat_access(UserId, ChatId) of
        ok ->
            do_get_messages(ChatId, Limit, Offset);
        {error, Reason} ->
            {error, Reason}
    end.

do_mark_message_delivered(MessageId, UserId) ->
    % Update delivery status
    SQL = "UPDATE messages SET delivery_status = $1, updated_at = NOW() 
           WHERE id = $2 AND delivery_status = 'sent'",
    case aethertalk_db:query(SQL, [?DELIVERY_DELIVERED, MessageId]) of
        {ok, 1} ->
            % Notify sender about delivery
            notify_delivery_status(MessageId, UserId, ?DELIVERY_DELIVERED),
            ok;
        {ok, 0} ->
            {error, not_found_or_already_delivered};
        {error, Reason} ->
            {error, Reason}
    end.

do_mark_message_read(MessageId, UserId) ->
    % Update delivery status
    SQL = "UPDATE messages SET delivery_status = $1, updated_at = NOW() 
           WHERE id = $2 AND delivery_status IN ('sent', 'delivered')",
    case aethertalk_db:query(SQL, [?DELIVERY_READ, MessageId]) of
        {ok, 1} ->
            % Notify sender about read receipt
            notify_delivery_status(MessageId, UserId, ?DELIVERY_READ),
            ok;
        {ok, 0} ->
            {error, not_found_or_already_read};
        {error, Reason} ->
            {error, Reason}
    end.

do_edit_message(MessageId, NewContent, UserId) ->
    % Check if user owns the message
    CheckSQL = "SELECT sender_id FROM messages WHERE id = $1 AND is_deleted = FALSE",
    case aethertalk_db:query(CheckSQL, [MessageId]) of
        {ok, {_Columns, [{SenderId}]}} when SenderId =:= UserId ->
            % Update message content
            UpdateSQL = "UPDATE messages SET content = $1, is_edited = TRUE, updated_at = NOW() 
                        WHERE id = $2 RETURNING updated_at",
            case aethertalk_db:query(UpdateSQL, [NewContent, MessageId]) of
                {ok, {_Cols, [{UpdatedAt}]}} ->
                    % Notify chat participants about edit
                    notify_message_edit(MessageId, NewContent),
                    {ok, #{updated_at => UpdatedAt}};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, {_Columns, [{_OtherSenderId}]}} ->
            {error, unauthorized};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_delete_message(MessageId, UserId) ->
    % Check if user owns the message
    CheckSQL = "SELECT sender_id, chat_id FROM messages WHERE id = $1 AND is_deleted = FALSE",
    case aethertalk_db:query(CheckSQL, [MessageId]) of
        {ok, {_Columns, [{SenderId, ChatId}]}} when SenderId =:= UserId ->
            % Mark message as deleted
            UpdateSQL = "UPDATE messages SET is_deleted = TRUE, content = NULL, 
                        media_url = NULL, updated_at = NOW() WHERE id = $1",
            case aethertalk_db:query(UpdateSQL, [MessageId]) of
                {ok, 1} ->
                    % Notify chat participants about deletion
                    notify_message_deletion(MessageId, ChatId),
                    ok;
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, {_Columns, [{_OtherSenderId, _}]}} ->
            {error, unauthorized};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_forward_message(MessageId, ToChatId, UserId) ->
    % Get original message
    GetSQL = "SELECT content, message_type, media_url, media_metadata 
              FROM messages WHERE id = $1 AND is_deleted = FALSE",
    case aethertalk_db:query(GetSQL, [MessageId]) of
        {ok, {_Columns, [{Content, MessageType, MediaUrl, MediaMetadata}]}} ->
            % Create forwarded message
            ForwardData = #{
                chat_id => ToChatId,
                sender_id => UserId,
                message_type => MessageType,
                content => Content,
                media_url => MediaUrl,
                media_metadata => jsx:decode(MediaMetadata),
                forward_from_id => MessageId
            },
            do_send_message(ForwardData);
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_add_reaction(MessageId, UserId, Reaction) ->
    SQL = "INSERT INTO message_reactions (message_id, user_id, reaction) 
           VALUES ($1, $2, $3) 
           ON CONFLICT (message_id, user_id, reaction) DO NOTHING 
           RETURNING id",
    case aethertalk_db:query(SQL, [MessageId, UserId, Reaction]) of
        {ok, {_Columns, [{ReactionId}]}} ->
            % Notify about new reaction
            notify_reaction_added(MessageId, UserId, Reaction),
            {ok, #{id => ReactionId}};
        {ok, {_Columns, []}} ->
            {error, reaction_already_exists};
        {error, Reason} ->
            {error, Reason}
    end.

do_remove_reaction(MessageId, UserId, Reaction) ->
    SQL = "DELETE FROM message_reactions 
           WHERE message_id = $1 AND user_id = $2 AND reaction = $3",
    case aethertalk_db:query(SQL, [MessageId, UserId, Reaction]) of
        {ok, 1} ->
            % Notify about reaction removal
            notify_reaction_removed(MessageId, UserId, Reaction),
            ok;
        {ok, 0} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_message_reactions(MessageId) ->
    SQL = "SELECT r.reaction, r.user_id, r.created_at, u.username, u.display_name
           FROM message_reactions r
           JOIN users u ON r.user_id = u.id
           WHERE r.message_id = $1
           ORDER BY r.created_at",
    case aethertalk_db:query(SQL, [MessageId]) of
        {ok, {_Columns, Rows}} ->
            Reactions = [row_to_reaction_map(Row) || Row <- Rows],
            {ok, Reactions};
        {error, Reason} ->
            {error, Reason}
    end.

do_create_chat(ChatData) ->
    Type = maps:get(type, ChatData),
    Name = maps:get(name, ChatData, null),
    Description = maps:get(description, ChatData, null),
    CreatedBy = maps:get(created_by, ChatData),
    
    SQL = "INSERT INTO chats (type, name, description, created_by) 
           VALUES ($1, $2, $3, $4) 
           RETURNING id, created_at",
    case aethertalk_db:query(SQL, [Type, Name, Description, CreatedBy]) of
        {ok, {_Columns, [{ChatId, CreatedAt}]}} ->
            Chat = #{
                id => ChatId,
                type => Type,
                name => Name,
                description => Description,
                created_by => CreatedBy,
                created_at => CreatedAt
            },
            {ok, Chat};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_chat(ChatId) ->
    SQL = "SELECT id, type, name, description, avatar_url, created_by,
                  is_archived, is_pinned, is_muted, last_message_id,
                  last_message_at, participant_count, settings,
                  created_at, updated_at
           FROM chats WHERE id = $1",
    case aethertalk_db:query(SQL, [ChatId]) of
        {ok, {_Columns, []}} ->
            {error, not_found};
        {ok, {_Columns, [Row]}} ->
            {ok, row_to_chat_map(Row)};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_user_chats(UserId) ->
    % This is a simplified version - in reality, you'd need to join with
    % chat participants or group members tables
    SQL = "SELECT DISTINCT c.id, c.type, c.name, c.description, c.avatar_url,
                  c.created_by, c.is_archived, c.is_pinned, c.is_muted,
                  c.last_message_id, c.last_message_at, c.participant_count,
                  c.settings, c.created_at, c.updated_at
           FROM chats c
           WHERE c.created_by = $1 OR c.id IN (
               SELECT DISTINCT chat_id FROM messages WHERE sender_id = $1
           )
           ORDER BY c.last_message_at DESC NULLS LAST",
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, Rows}} ->
            Chats = [row_to_chat_map(Row) || Row <- Rows],
            {ok, Chats};
        {error, Reason} ->
            {error, Reason}
    end.

do_update_chat(ChatId, Updates) ->
    % Build dynamic update query
    {SetClause, Params} = build_update_clause(Updates, 2),
    SQL = "UPDATE chats SET " ++ SetClause ++ ", updated_at = NOW() 
           WHERE id = $1 RETURNING updated_at",
    
    case aethertalk_db:query(SQL, [ChatId | Params]) of
        {ok, {_Columns, [{UpdatedAt}]}} ->
            {ok, #{updated_at => UpdatedAt}};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_archive_chat(ChatId, _UserId) ->
    % This would typically be per-user setting
    SQL = "UPDATE chats SET is_archived = TRUE, updated_at = NOW() WHERE id = $1",
    case aethertalk_db:query(SQL, [ChatId]) of
        {ok, 1} ->
            ok;
        {ok, 0} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_pin_chat(ChatId, _UserId) ->
    SQL = "UPDATE chats SET is_pinned = TRUE, updated_at = NOW() WHERE id = $1",
    case aethertalk_db:query(SQL, [ChatId]) of
        {ok, 1} ->
            ok;
        {ok, 0} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_mute_chat(ChatId, _UserId, Duration) ->
    SQL = "UPDATE chats SET is_muted = TRUE, updated_at = NOW() WHERE id = $1",
    case aethertalk_db:query(SQL, [ChatId]) of
        {ok, 1} ->
            % Schedule unmute if duration is specified
            case Duration of
                undefined -> ok;
                _ -> schedule_unmute(ChatId, Duration)
            end,
            ok;
        {ok, 0} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

%% Helper functions

validate_message_data(MessageData) ->
    ChatId = maps:get(chat_id, MessageData, undefined),
    SenderId = maps:get(sender_id, MessageData, undefined),
    MessageType = maps:get(message_type, MessageData, ?MSG_TYPE_TEXT),
    Content = maps:get(content, MessageData, undefined),
    
    case {ChatId, SenderId} of
        {undefined, _} ->
            {error, missing_chat_id};
        {_, undefined} ->
            {error, missing_sender_id};
        {_, _} ->
            case MessageType of
                ?MSG_TYPE_TEXT when Content =:= undefined ->
                    {error, missing_content};
                _ ->
                    ok
            end
    end.

check_send_permission(_SenderId, ChatId) ->
    % Check if user is blocked or has permission to send to this chat
    % This is a simplified version
    case do_get_chat(ChatId) of
        {ok, _Chat} ->
            ok;
        {error, not_found} ->
            {error, chat_not_found};
        {error, Reason} ->
            {error, Reason}
    end.

check_chat_access(_UserId, ChatId) ->
    % Check if user has access to this chat
    % This is a simplified version
    case do_get_chat(ChatId) of
        {ok, _Chat} ->
            ok;
        {error, not_found} ->
            {error, chat_not_found};
        {error, Reason} ->
            {error, Reason}
    end.

update_chat_last_message(ChatId, MessageId, CreatedAt) ->
    SQL = "UPDATE chats SET last_message_id = $1, last_message_at = $2, updated_at = NOW() 
           WHERE id = $3",
    aethertalk_db:query(SQL, [MessageId, CreatedAt, ChatId]).

notify_chat_participants(ChatId, Message, SenderId) ->
    % Send real-time notification via WebSocket
    aethertalk_websocket_manager:broadcast_to_chat(ChatId, #{
        type => ?WS_MSG_MESSAGE,
        data => Message
    }, SenderId).

notify_delivery_status(MessageId, UserId, Status) ->
    % Notify sender about delivery status change
    aethertalk_websocket_manager:send_to_user(UserId, #{
        type => delivery_status,
        message_id => MessageId,
        status => Status
    }).

notify_message_edit(_MessageId, _NewContent) ->
    % Notify chat participants about message edit
    % Implementation would get chat participants and send notifications
    ok.

notify_message_deletion(MessageId, ChatId) ->
    % Notify chat participants about message deletion
    aethertalk_websocket_manager:broadcast_to_chat(ChatId, #{
        type => message_deleted,
        message_id => MessageId
    }).

notify_reaction_added(_MessageId, _UserId, _Reaction) ->
    % Notify about new reaction
    ok.

notify_reaction_removed(_MessageId, _UserId, _Reaction) ->
    % Notify about reaction removal
    ok.

handle_message_translation(_Message) ->
    % Handle automatic translation if enabled
    % This would integrate with the translation service
    ok.

schedule_unmute(ChatId, Duration) ->
    % Schedule a task to unmute the chat after duration
    erlang:send_after(Duration * 1000, self(), {unmute_chat, ChatId}).

row_to_message_map({Id, ChatId, SenderId, ReplyToId, ForwardFromId, MessageType,
                    Content, MediaUrl, MediaMetadata, IsEdited, IsDeleted, IsForwarded,
                    DeliveryStatus, ExpiresAt, CreatedAt, UpdatedAt,
                    Username, DisplayName, ProfilePictureUrl}) ->
    #{
        id => Id,
        chat_id => ChatId,
        sender_id => SenderId,
        reply_to_id => ReplyToId,
        forward_from_id => ForwardFromId,
        message_type => MessageType,
        content => Content,
        media_url => MediaUrl,
        media_metadata => case MediaMetadata of
            null -> #{};
            _ -> jsx:decode(MediaMetadata)
        end,
        is_edited => IsEdited,
        is_deleted => IsDeleted,
        is_forwarded => IsForwarded,
        delivery_status => DeliveryStatus,
        expires_at => ExpiresAt,
        created_at => CreatedAt,
        updated_at => UpdatedAt,
        sender => #{
            username => Username,
            display_name => DisplayName,
            profile_picture_url => ProfilePictureUrl
        }
    }.

row_to_chat_map({Id, Type, Name, Description, AvatarUrl, CreatedBy,
                 IsArchived, IsPinned, IsMuted, LastMessageId, LastMessageAt,
                 ParticipantCount, Settings, CreatedAt, UpdatedAt}) ->
    #{
        id => Id,
        type => Type,
        name => Name,
        description => Description,
        avatar_url => AvatarUrl,
        created_by => CreatedBy,
        is_archived => IsArchived,
        is_pinned => IsPinned,
        is_muted => IsMuted,
        last_message_id => LastMessageId,
        last_message_at => LastMessageAt,
        participant_count => ParticipantCount,
        settings => case Settings of
            null -> #{};
            _ -> jsx:decode(Settings)
        end,
        created_at => CreatedAt,
        updated_at => UpdatedAt
    }.

row_to_reaction_map({Reaction, UserId, CreatedAt, Username, DisplayName}) ->
    #{
        reaction => Reaction,
        user_id => UserId,
        created_at => CreatedAt,
        user => #{
            username => Username,
            display_name => DisplayName
        }
    }.

build_update_clause(Updates, StartParam) ->
    {SetParts, Params, _} = maps:fold(fun(Key, Value, {Parts, ParamList, ParamNum}) ->
        Part = atom_to_list(Key) ++ " = $" ++ integer_to_list(ParamNum),
        {[Part | Parts], [Value | ParamList], ParamNum + 1}
    end, {[], [], StartParam}, Updates),
    
    {string:join(lists:reverse(SetParts), ", "), lists:reverse(Params)}.