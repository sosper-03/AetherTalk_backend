%%%-------------------------------------------------------------------
%%% @doc
%%% Polls Management Service for AetherTalk
%%% Handles poll creation, voting, and results
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_polls_manager).
-behaviour(gen_server).

% OTP callbacks
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    create_poll/5,
    get_poll/1,
    vote_poll/3,
    get_poll_results/1,
    close_poll/2,
    get_user_vote/2,
    get_chat_polls/1,
    delete_poll/2
]).

-include("aethertalk.hrl").

-record(state, {}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Create a new poll
create_poll(ChatId, CreatorId, Question, Options, ExpiresAt) ->
    gen_server:call(?MODULE, {create_poll, ChatId, CreatorId, Question, Options, ExpiresAt}).

%% @doc Get poll details
get_poll(PollId) ->
    gen_server:call(?MODULE, {get_poll, PollId}).

%% @doc Vote on a poll
vote_poll(PollId, UserId, OptionId) ->
    gen_server:call(?MODULE, {vote_poll, PollId, UserId, OptionId}).

%% @doc Get poll results
get_poll_results(PollId) ->
    gen_server:call(?MODULE, {get_poll_results, PollId}).

%% @doc Close a poll
close_poll(PollId, UserId) ->
    gen_server:call(?MODULE, {close_poll, PollId, UserId}).

%% @doc Get user's vote for a poll
get_user_vote(PollId, UserId) ->
    gen_server:call(?MODULE, {get_user_vote, PollId, UserId}).

%% @doc Get all polls in a chat
get_chat_polls(ChatId) ->
    gen_server:call(?MODULE, {get_chat_polls, ChatId}).

%% @doc Delete a poll
delete_poll(PollId, UserId) ->
    gen_server:call(?MODULE, {delete_poll, PollId, UserId}).

%% ===================================================================
%% gen_server callbacks
%% ===================================================================

init([]) ->
    io:format("Polls Manager started~n"),
    {ok, #state{}}.

handle_call({create_poll, ChatId, CreatorId, Question, Options, ExpiresAt}, _From, State) ->
    Result = do_create_poll(ChatId, CreatorId, Question, Options, ExpiresAt),
    {reply, Result, State};

handle_call({get_poll, PollId}, _From, State) ->
    Result = do_get_poll(PollId),
    {reply, Result, State};

handle_call({vote_poll, PollId, UserId, OptionId}, _From, State) ->
    Result = do_vote_poll(PollId, UserId, OptionId),
    {reply, Result, State};

handle_call({get_poll_results, PollId}, _From, State) ->
    Result = do_get_poll_results(PollId),
    {reply, Result, State};

handle_call({close_poll, PollId, UserId}, _From, State) ->
    Result = do_close_poll(PollId, UserId),
    {reply, Result, State};

handle_call({get_user_vote, PollId, UserId}, _From, State) ->
    Result = do_get_user_vote(PollId, UserId),
    {reply, Result, State};

handle_call({get_chat_polls, ChatId}, _From, State) ->
    Result = do_get_chat_polls(ChatId),
    {reply, Result, State};

handle_call({delete_poll, PollId, UserId}, _From, State) ->
    Result = do_delete_poll(PollId, UserId),
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

do_create_poll(ChatId, CreatorId, Question, Options, ExpiresAt) ->
    PollId = aethertalk_utils:generate_uuid(),
    
    % Create poll record
    SQL = "INSERT INTO polls (id, chat_id, creator_id, question, expires_at, created_at) 
           VALUES ($1, $2, $3, $4, $5, NOW()) RETURNING created_at",
    
    case aethertalk_db:query(SQL, [PollId, ChatId, CreatorId, Question, ExpiresAt]) of
        {ok, {_Columns, [{CreatedAt}]}} ->
            % Create poll options
            case create_poll_options(PollId, Options) of
                {ok, OptionsList} ->
                    Poll = #{
                        id => PollId,
                        chat_id => ChatId,
                        creator_id => CreatorId,
                        question => Question,
                        options => OptionsList,
                        expires_at => ExpiresAt,
                        created_at => CreatedAt,
                        is_closed => false,
                        total_votes => 0
                    },
                    
                    % Create message for the poll
                    MessageId = aethertalk_utils:generate_uuid(),
                    MessageSQL = "INSERT INTO messages (id, chat_id, sender_id, message_type, content, created_at) 
                                 VALUES ($1, $2, $3, 'poll', $4, NOW())",
                    PollContent = jiffy:encode(#{poll_id => PollId}),
                    aethertalk_db:query(MessageSQL, [MessageId, ChatId, CreatorId, PollContent]),
                    
                    % Notify about new poll
                    notify_poll_created(ChatId, PollId),
                    {ok, Poll#{message_id => MessageId}};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_get_poll(PollId) ->
    SQL = "SELECT p.id, p.chat_id, p.creator_id, p.question, p.expires_at, 
                  p.created_at, p.is_closed,
                  u.username, u.full_name, u.avatar_url
           FROM polls p
           JOIN users u ON p.creator_id = u.id
           WHERE p.id = $1 AND p.is_deleted = FALSE",
    
    case aethertalk_db:query(SQL, [PollId]) of
        {ok, {_Columns, [{Id, ChatId, CreatorId, Question, ExpiresAt, CreatedAt, IsClosed,
                         Username, FullName, AvatarUrl}]}} ->
            % Get poll options with vote counts
            case get_poll_options_with_votes(PollId) of
                {ok, Options} ->
                    TotalVotes = lists:sum([maps:get(vote_count, Option) || Option <- Options]),
                    
                    Poll = #{
                        id => Id,
                        chat_id => ChatId,
                        creator_id => CreatorId,
                        question => Question,
                        options => Options,
                        expires_at => ExpiresAt,
                        created_at => CreatedAt,
                        is_closed => IsClosed,
                        total_votes => TotalVotes,
                        creator => #{
                            username => Username,
                            full_name => FullName,
                            avatar_url => AvatarUrl
                        }
                    },
                    {ok, Poll};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_vote_poll(PollId, UserId, OptionId) ->
    % Check if poll exists and is not closed/expired
    case check_poll_votable(PollId) of
        ok ->
            % Check if user already voted
            CheckSQL = "SELECT option_id FROM poll_votes WHERE poll_id = $1 AND user_id = $2",
            case aethertalk_db:query(CheckSQL, [PollId, UserId]) of
                {ok, {_Columns, []}} ->
                    % User hasn't voted, add new vote
                    InsertSQL = "INSERT INTO poll_votes (poll_id, user_id, option_id, voted_at) 
                                VALUES ($1, $2, $3, NOW()) RETURNING id, voted_at",
                    case aethertalk_db:query(InsertSQL, [PollId, UserId, OptionId]) of
                        {ok, {_Cols, [{VoteId, VotedAt}]}} ->
                            Vote = #{
                                id => VoteId,
                                poll_id => PollId,
                                user_id => UserId,
                                option_id => OptionId,
                                voted_at => VotedAt
                            },
                            
                            % Notify about new vote
                            notify_poll_voted(PollId, UserId, OptionId),
                            {ok, Vote};
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {ok, {_Columns, [{ExistingOptionId}]}} ->
                    if ExistingOptionId =:= OptionId ->
                        {error, already_voted_same_option};
                    true ->
                        % Update existing vote
                        UpdateSQL = "UPDATE poll_votes SET option_id = $1, voted_at = NOW() 
                                    WHERE poll_id = $2 AND user_id = $3",
                        case aethertalk_db:query(UpdateSQL, [OptionId, PollId, UserId]) of
                            {ok, 1} ->
                                % Notify about vote change
                                notify_poll_vote_changed(PollId, UserId, ExistingOptionId, OptionId),
                                {ok, vote_changed};
                            {error, Reason} ->
                                {error, Reason}
                        end
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_get_poll_results(PollId) ->
    SQL = "SELECT po.id, po.option_text, COUNT(pv.id) as vote_count,
                  ARRAY_AGG(
                      CASE WHEN pv.user_id IS NOT NULL THEN
                          JSON_BUILD_OBJECT(
                              'user_id', u.id,
                              'username', u.username,
                              'full_name', u.full_name,
                              'avatar_url', u.avatar_url,
                              'voted_at', pv.voted_at
                          )
                      ELSE NULL END
                  ) FILTER (WHERE pv.user_id IS NOT NULL) as voters
           FROM poll_options po
           LEFT JOIN poll_votes pv ON po.id = pv.option_id
           LEFT JOIN users u ON pv.user_id = u.id
           WHERE po.poll_id = $1
           GROUP BY po.id, po.option_text, po.option_order
           ORDER BY po.option_order",
    
    case aethertalk_db:query(SQL, [PollId]) of
        {ok, {_Columns, Rows}} ->
            Results = lists:map(fun({OptionId, OptionText, VoteCount, Voters}) ->
                #{
                    option_id => OptionId,
                    option_text => OptionText,
                    vote_count => VoteCount,
                    voters => case Voters of
                        null -> [];
                        _ -> Voters
                    end
                }
            end, Rows),
            
            TotalVotes = lists:sum([maps:get(vote_count, Result) || Result <- Results]),
            
            {ok, #{
                poll_id => PollId,
                results => Results,
                total_votes => TotalVotes
            }};
        {error, Reason} ->
            {error, Reason}
    end.

do_close_poll(PollId, UserId) ->
    % Check if user is the creator
    CheckSQL = "SELECT creator_id FROM polls WHERE id = $1 AND is_deleted = FALSE",
    case aethertalk_db:query(CheckSQL, [PollId]) of
        {ok, {_Columns, [{UserId}]}} ->
            % Close the poll
            SQL = "UPDATE polls SET is_closed = TRUE WHERE id = $1",
            case aethertalk_db:query(SQL, [PollId]) of
                {ok, 1} ->
                    % Notify about poll closure
                    notify_poll_closed(PollId),
                    ok;
                {ok, 0} ->
                    {error, not_found};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, {_Columns, [{_OtherUserId}]}} ->
            {error, not_creator};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_user_vote(PollId, UserId) ->
    SQL = "SELECT pv.option_id, pv.voted_at, po.option_text
           FROM poll_votes pv
           JOIN poll_options po ON pv.option_id = po.id
           WHERE pv.poll_id = $1 AND pv.user_id = $2",
    
    case aethertalk_db:query(SQL, [PollId, UserId]) of
        {ok, {_Columns, [{OptionId, VotedAt, OptionText}]}} ->
            Vote = #{
                option_id => OptionId,
                option_text => OptionText,
                voted_at => VotedAt
            },
            {ok, Vote};
        {ok, {_Columns, []}} ->
            {error, not_voted};
        {error, Reason} ->
            {error, Reason}
    end.

do_get_chat_polls(ChatId) ->
    SQL = "SELECT p.id, p.question, p.expires_at, p.created_at, p.is_closed,
                  u.username, u.full_name, u.avatar_url,
                  COUNT(pv.id) as total_votes
           FROM polls p
           JOIN users u ON p.creator_id = u.id
           LEFT JOIN poll_votes pv ON p.id = pv.poll_id
           WHERE p.chat_id = $1 AND p.is_deleted = FALSE
           GROUP BY p.id, u.username, u.full_name, u.avatar_url
           ORDER BY p.created_at DESC",
    
    case aethertalk_db:query(SQL, [ChatId]) of
        {ok, {_Columns, Rows}} ->
            Polls = lists:map(fun({Id, Question, ExpiresAt, CreatedAt, IsClosed,
                                  Username, FullName, AvatarUrl, TotalVotes}) ->
                #{
                    id => Id,
                    question => Question,
                    expires_at => ExpiresAt,
                    created_at => CreatedAt,
                    is_closed => IsClosed,
                    total_votes => TotalVotes,
                    creator => #{
                        username => Username,
                        full_name => FullName,
                        avatar_url => AvatarUrl
                    }
                }
            end, Rows),
            {ok, Polls};
        {error, Reason} ->
            {error, Reason}
    end.

do_delete_poll(PollId, UserId) ->
    % Check if user is the creator
    CheckSQL = "SELECT creator_id FROM polls WHERE id = $1 AND is_deleted = FALSE",
    case aethertalk_db:query(CheckSQL, [PollId]) of
        {ok, {_Columns, [{UserId}]}} ->
            % Soft delete the poll
            SQL = "UPDATE polls SET is_deleted = TRUE WHERE id = $1",
            case aethertalk_db:query(SQL, [PollId]) of
                {ok, 1} ->
                    % Notify about poll deletion
                    notify_poll_deleted(PollId),
                    ok;
                {ok, 0} ->
                    {error, not_found};
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, {_Columns, [{_OtherUserId}]}} ->
            {error, not_creator};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

%% Helper functions

create_poll_options(PollId, Options) ->
    try
        OptionsList = lists:map(fun({Index, OptionText}) ->
            OptionId = aethertalk_utils:generate_uuid(),
            SQL = "INSERT INTO poll_options (id, poll_id, option_text, option_order) 
                   VALUES ($1, $2, $3, $4)",
            case aethertalk_db:query(SQL, [OptionId, PollId, OptionText, Index]) of
                {ok, 1} ->
                    #{
                        id => OptionId,
                        option_text => OptionText,
                        option_order => Index,
                        vote_count => 0
                    };
                {error, Reason} ->
                    throw({error, Reason})
            end
        end, lists:zip(lists:seq(1, length(Options)), Options)),
        
        {ok, OptionsList}
    catch
        throw:Error -> Error
    end.

get_poll_options_with_votes(PollId) ->
    SQL = "SELECT po.id, po.option_text, po.option_order, COUNT(pv.id) as vote_count
           FROM poll_options po
           LEFT JOIN poll_votes pv ON po.id = pv.option_id
           WHERE po.poll_id = $1
           GROUP BY po.id, po.option_text, po.option_order
           ORDER BY po.option_order",
    
    case aethertalk_db:query(SQL, [PollId]) of
        {ok, {_Columns, Rows}} ->
            Options = lists:map(fun({OptionId, OptionText, OptionOrder, VoteCount}) ->
                #{
                    id => OptionId,
                    option_text => OptionText,
                    option_order => OptionOrder,
                    vote_count => VoteCount
                }
            end, Rows),
            {ok, Options};
        {error, Reason} ->
            {error, Reason}
    end.

check_poll_votable(PollId) ->
    SQL = "SELECT is_closed, expires_at FROM polls 
           WHERE id = $1 AND is_deleted = FALSE",
    
    case aethertalk_db:query(SQL, [PollId]) of
        {ok, {_Columns, [{false, ExpiresAt}]}} ->
            Now = calendar:universal_time(),
            if ExpiresAt > Now ->
                ok;
            true ->
                {error, poll_expired}
            end;
        {ok, {_Columns, [{true, _}]}} ->
            {error, poll_closed};
        {ok, {_Columns, []}} ->
            {error, poll_not_found};
        {error, Reason} ->
            {error, Reason}
    end.

%% Notification functions

notify_poll_created(ChatId, PollId) ->
    io:format("Poll created in chat ~p: ~p~n", [ChatId, PollId]),
    spawn(fun() ->
        Notification = #{
            type => <<"poll_created">>,
            chat_id => ChatId,
            poll_id => PollId,
            timestamp => erlang:system_time(millisecond)
        },
        aethertalk_websocket_manager:broadcast_to_chat(ChatId, Notification)
    end).

notify_poll_voted(PollId, UserId, OptionId) ->
    io:format("User ~p voted on poll ~p, option ~p~n", [UserId, PollId, OptionId]),
    spawn(fun() ->
        case get_poll_chat_id(PollId) of
            {ok, ChatId} ->
                Notification = #{
                    type => <<"poll_voted">>,
                    poll_id => PollId,
                    user_id => UserId,
                    option_id => OptionId,
                    timestamp => erlang:system_time(millisecond)
                },
                aethertalk_websocket_manager:broadcast_to_chat(ChatId, Notification);
            {error, _} ->
                ok
        end
    end).

notify_poll_vote_changed(PollId, UserId, OldOptionId, NewOptionId) ->
    io:format("User ~p changed vote on poll ~p from ~p to ~p~n", 
               [UserId, PollId, OldOptionId, NewOptionId]).

notify_poll_closed(PollId) ->
    io:format("Poll closed: ~p~n", [PollId]).

notify_poll_deleted(PollId) ->
    io:format("Poll deleted: ~p~n", [PollId]).

get_poll_chat_id(PollId) ->
    SQL = "SELECT chat_id FROM polls WHERE id = $1",
    case aethertalk_db:query(SQL, [PollId]) of
        {ok, {_Columns, [{ChatId}]}} ->
            {ok, ChatId};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.