%%%-------------------------------------------------------------------
%%% @doc
%%% Message Reactions Management Service for AetherTalk
%%% Handles message reactions, emojis, and reaction analytics
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_reactions_manager).
-behaviour(gen_server).

% OTP callbacks
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    add_reaction/3,
    remove_reaction/3,
    get_message_reactions/1,
    get_reaction_users/2,
    toggle_reaction/3,
    get_popular_reactions/0,
    get_user_reaction_stats/1
]).

-include("aethertalk.hrl").

-record(state, {}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Add a reaction to a message
add_reaction(MessageId, UserId, Reaction) ->
    gen_server:call(?MODULE, {add_reaction, MessageId, UserId, Reaction}).

%% @doc Remove a reaction from a message
remove_reaction(MessageId, UserId, Reaction) ->
    gen_server:call(?MODULE, {remove_reaction, MessageId, UserId, Reaction}).

%% @doc Get all reactions for a message
get_message_reactions(MessageId) ->
    gen_server:call(?MODULE, {get_message_reactions, MessageId}).

%% @doc Get users who reacted with a specific reaction
get_reaction_users(MessageId, Reaction) ->
    gen_server:call(?MODULE, {get_reaction_users, MessageId, Reaction}).

%% @doc Toggle a reaction (add if not exists, remove if exists)
toggle_reaction(MessageId, UserId, Reaction) ->
    gen_server:call(?MODULE, {toggle_reaction, MessageId, UserId, Reaction}).

%% @doc Get popular reactions across the platform
get_popular_reactions() ->
    gen_server:call(?MODULE, get_popular_reactions).

%% @doc Get reaction statistics for a user
get_user_reaction_stats(UserId) ->
    gen_server:call(?MODULE, {get_user_reaction_stats, UserId}).

%% ===================================================================
%% gen_server callbacks
%% ===================================================================

init([]) ->
    io:format("Reactions Manager started~n"),
    {ok, #state{}}.

handle_call({add_reaction, MessageId, UserId, Reaction}, _From, State) ->
    Result = do_add_reaction(MessageId, UserId, Reaction),
    {reply, Result, State};

handle_call({remove_reaction, MessageId, UserId, Reaction}, _From, State) ->
    Result = do_remove_reaction(MessageId, UserId, Reaction),
    {reply, Result, State};

handle_call({get_message_reactions, MessageId}, _From, State) ->
    Result = do_get_message_reactions(MessageId),
    {reply, Result, State};

handle_call({get_reaction_users, MessageId, Reaction}, _From, State) ->
    Result = do_get_reaction_users(MessageId, Reaction),
    {reply, Result, State};

handle_call({toggle_reaction, MessageId, UserId, Reaction}, _From, State) ->
    Result = do_toggle_reaction(MessageId, UserId, Reaction),
    {reply, Result, State};

handle_call(get_popular_reactions, _From, State) ->
    Result = do_get_popular_reactions(),
    {reply, Result, State};

handle_call({get_user_reaction_stats, UserId}, _From, State) ->
    Result = do_get_user_reaction_stats(UserId),
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

do_add_reaction(MessageId, UserId, Reaction) ->
    % First check if message exists
    case check_message_exists(MessageId) of
        true ->
            % Check if user already reacted with this reaction
            CheckSQL = "SELECT id FROM message_reactions 
                       WHERE message_id = $1 AND user_id = $2 AND reaction = $3",
            case aethertalk_db:query(CheckSQL, [MessageId, UserId, Reaction]) of
                {ok, {_Columns, []}} ->
                    % Add new reaction
                    InsertSQL = "INSERT INTO message_reactions (message_id, user_id, reaction, created_at) 
                                VALUES ($1, $2, $3, NOW()) RETURNING id, created_at",
                    case aethertalk_db:query(InsertSQL, [MessageId, UserId, Reaction]) of
                        {ok, {_Cols, [{ReactionId, CreatedAt}]}} ->
                            ReactionData = #{
                                id => ReactionId,
                                message_id => MessageId,
                                user_id => UserId,
                                reaction => Reaction,
                                created_at => CreatedAt
                            },
                            
                            % Notify about new reaction
                            notify_reaction_added(MessageId, UserId, Reaction),
                            {ok, ReactionData};
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {ok, {_Columns, [_]}} ->
                    {error, already_reacted};
                {error, Reason} ->
                    {error, Reason}
            end;
        false ->
            {error, message_not_found}
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
            {error, reaction_not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_message_reactions(MessageId) ->
    SQL = "SELECT mr.reaction, COUNT(*) as count,
                  ARRAY_AGG(
                      JSON_BUILD_OBJECT(
                          'user_id', u.id,
                          'username', u.username,
                          'full_name', u.full_name,
                          'avatar_url', u.avatar_url,
                          'created_at', mr.created_at
                      )
                  ) as users
           FROM message_reactions mr
           JOIN users u ON mr.user_id = u.id
           WHERE mr.message_id = $1
           GROUP BY mr.reaction
           ORDER BY count DESC, mr.reaction",
    
    case aethertalk_db:query(SQL, [MessageId]) of
        {ok, {_Columns, Rows}} ->
            Reactions = lists:map(fun({Reaction, Count, Users}) ->
                #{
                    reaction => Reaction,
                    count => Count,
                    users => Users
                }
            end, Rows),
            {ok, Reactions};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_reaction_users(MessageId, Reaction) ->
    SQL = "SELECT mr.user_id, mr.created_at, u.username, u.full_name, u.avatar_url
           FROM message_reactions mr
           JOIN users u ON mr.user_id = u.id
           WHERE mr.message_id = $1 AND mr.reaction = $2
           ORDER BY mr.created_at ASC",
    
    case aethertalk_db:query(SQL, [MessageId, Reaction]) of
        {ok, {_Columns, Rows}} ->
            Users = lists:map(fun({UserId, CreatedAt, Username, FullName, AvatarUrl}) ->
                #{
                    user_id => UserId,
                    created_at => CreatedAt,
                    username => Username,
                    full_name => FullName,
                    avatar_url => AvatarUrl
                }
            end, Rows),
            {ok, Users};
        {error, Reason} ->
            {error, Reason}
    end.

do_toggle_reaction(MessageId, UserId, Reaction) ->
    % Check if reaction already exists
    CheckSQL = "SELECT id FROM message_reactions 
               WHERE message_id = $1 AND user_id = $2 AND reaction = $3",
    
    case aethertalk_db:query(CheckSQL, [MessageId, UserId, Reaction]) of
        {ok, {_Columns, []}} ->
            % Reaction doesn't exist, add it
            do_add_reaction(MessageId, UserId, Reaction);
        {ok, {_Columns, [_]}} ->
            % Reaction exists, remove it
            case do_remove_reaction(MessageId, UserId, Reaction) of
                ok ->
                    {ok, removed};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_get_popular_reactions() ->
    SQL = "SELECT reaction, COUNT(*) as total_count,
                  COUNT(DISTINCT message_id) as message_count,
                  COUNT(DISTINCT user_id) as user_count
           FROM message_reactions
           WHERE created_at >= NOW() - INTERVAL '30 days'
           GROUP BY reaction
           ORDER BY total_count DESC
           LIMIT 20",
    
    case aethertalk_db:query(SQL, []) of
        {ok, {_Columns, Rows}} ->
            PopularReactions = lists:map(fun({Reaction, TotalCount, MessageCount, UserCount}) ->
                #{
                    reaction => Reaction,
                    total_count => TotalCount,
                    message_count => MessageCount,
                    user_count => UserCount
                }
            end, Rows),
            {ok, PopularReactions};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_user_reaction_stats(UserId) ->
    SQL = "SELECT 
               COUNT(*) as total_reactions,
               COUNT(DISTINCT reaction) as unique_reactions,
               COUNT(DISTINCT message_id) as messages_reacted_to,
               reaction as most_used_reaction,
               COUNT(*) as most_used_count
           FROM message_reactions
           WHERE user_id = $1
           GROUP BY reaction
           ORDER BY COUNT(*) DESC
           LIMIT 1",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, []}} ->
            {ok, #{
                total_reactions => 0,
                unique_reactions => 0,
                messages_reacted_to => 0,
                most_used_reaction => null,
                most_used_count => 0
            }};
        {ok, {_Columns, [{TotalReactions, UniqueReactions, MessagesReactedTo, 
                         MostUsedReaction, MostUsedCount}]}} ->
            Stats = #{
                total_reactions => TotalReactions,
                unique_reactions => UniqueReactions,
                messages_reacted_to => MessagesReactedTo,
                most_used_reaction => MostUsedReaction,
                most_used_count => MostUsedCount
            },
            {ok, Stats};
        {error, Reason} ->
            {error, Reason}
    end.

%% Helper functions

check_message_exists(MessageId) ->
    SQL = "SELECT id FROM messages WHERE id = $1 AND is_deleted = FALSE",
    case aethertalk_db:query(SQL, [MessageId]) of
        {ok, {_Columns, [_]}} ->
            true;
        _ ->
            false
    end.

%% Notification functions

notify_reaction_added(MessageId, UserId, Reaction) ->
    io:format("Reaction ~p added to message ~p by user ~p~n", [Reaction, MessageId, UserId]),
    % Get message details for notification
    spawn(fun() ->
        case get_message_details(MessageId) of
            {ok, MessageDetails} ->
                ChatId = maps:get(chat_id, MessageDetails),
                SenderId = maps:get(sender_id, MessageDetails),
                
                % Notify message sender (if different from reactor)
                if UserId =/= SenderId ->
                    Notification = #{
                        type => <<"message_reaction_added">>,
                        message_id => MessageId,
                        chat_id => ChatId,
                        user_id => UserId,
                        reaction => Reaction,
                        timestamp => erlang:system_time(millisecond)
                    },
                    aethertalk_websocket_manager:send_to_user(SenderId, Notification);
                true ->
                    ok
                end,
                
                % Broadcast to chat participants
                Broadcast = #{
                    type => <<"reaction_added">>,
                    message_id => MessageId,
                    user_id => UserId,
                    reaction => Reaction,
                    timestamp => erlang:system_time(millisecond)
                },
                aethertalk_websocket_manager:broadcast_to_chat(ChatId, Broadcast);
            {error, _} ->
                ok
        end
    end).

notify_reaction_removed(MessageId, UserId, Reaction) ->
    io:format("Reaction ~p removed from message ~p by user ~p~n", [Reaction, MessageId, UserId]),
    % Get message details for notification
    spawn(fun() ->
        case get_message_details(MessageId) of
            {ok, MessageDetails} ->
                ChatId = maps:get(chat_id, MessageDetails),
                
                % Broadcast to chat participants
                Broadcast = #{
                    type => <<"reaction_removed">>,
                    message_id => MessageId,
                    user_id => UserId,
                    reaction => Reaction,
                    timestamp => erlang:system_time(millisecond)
                },
                aethertalk_websocket_manager:broadcast_to_chat(ChatId, Broadcast);
            {error, _} ->
                ok
        end
    end).

get_message_details(MessageId) ->
    SQL = "SELECT chat_id, sender_id FROM messages WHERE id = $1",
    case aethertalk_db:query(SQL, [MessageId]) of
        {ok, {_Columns, [{ChatId, SenderId}]}} ->
            {ok, #{chat_id => ChatId, sender_id => SenderId}};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.