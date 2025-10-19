%%%-------------------------------------------------------------------
%% @doc AetherTalk WebSocket handler
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_websocket_handler).

-compile({no_auto_import,[atom_to_binary/1]}).

-export([init/2, websocket_init/1, websocket_handle/2, websocket_info/2, terminate/3]).

-include("aethertalk.hrl").

-record(state, {
    user_id,
    session_id,
    device_id,
    authenticated = false,
    rate_limit_counter = 0,
    rate_limit_reset_time,
    subscribed_chats = []
}).

init(Req, _State) ->
    % Extract query parameters
    #{
        token := Token,
        device_id := DeviceId
    } = cowboy_req:match_qs([{token, [], undefined}, {device_id, [], undefined}], Req),
    
    State = #state{
        device_id = DeviceId,
        rate_limit_reset_time = erlang:system_time(second) + ?RATE_LIMIT_WINDOW
    },
    
    case Token of
        undefined ->
            % No token provided, will need to authenticate via WebSocket
            {cowboy_websocket, Req, State};
        _ ->
            % Try to authenticate with token
            case authenticate_token(Token) of
                {ok, UserId, SessionId} ->
                    AuthenticatedState = State#state{
                        user_id = UserId,
                        session_id = SessionId,
                        authenticated = true
                    },
                    {cowboy_websocket, Req, AuthenticatedState};
                {error, _Reason} ->
                    % Invalid token, will need to authenticate via WebSocket
                    {cowboy_websocket, Req, State}
            end
    end.

websocket_init(State) ->
    case State#state.authenticated of
        true ->
            % Register connection
            SessionData = #{
                session_id => State#state.session_id,
                device_id => State#state.device_id
            },
            aethertalk_websocket_manager:register_connection(self(), State#state.user_id, SessionData),
            
            % Send welcome message
            WelcomeMsg = #{
                type => <<"welcome">>,
                data => #{
                    user_id => State#state.user_id,
                    session_id => State#state.session_id
                }
            },
            {[{text, jsx:encode(WelcomeMsg)}], State};
        false ->
            % Send authentication required message
            AuthMsg = #{
                type => <<"auth_required">>,
                data => #{
                    message => <<"Authentication required">>
                }
            },
            {[{text, jsx:encode(AuthMsg)}], State}
    end.

websocket_handle({text, Data}, State) ->
    case check_rate_limit(State) of
        ok ->
            try
                Message = jsx:decode(Data),
                handle_message(Message, State)
            catch
                _:_ ->
                    ErrorMsg = create_error_message(<<"invalid_json">>, <<"Invalid JSON format">>),
                    {[{text, jsx:encode(ErrorMsg)}], State}
            end;
        {error, rate_limited} ->
            ErrorMsg = create_error_message(<<"rate_limited">>, <<"Too many requests">>),
            {[{text, jsx:encode(ErrorMsg)}], State}
    end;

websocket_handle({binary, _Data}, State) ->
    % Binary messages not supported
    ErrorMsg = create_error_message(<<"unsupported">>, <<"Binary messages not supported">>),
    {[{text, jsx:encode(ErrorMsg)}], State};

websocket_handle(_Frame, State) ->
    {ok, State}.

websocket_info({send_message, Message}, State) ->
    {[{text, jsx:encode(Message)}], State};

websocket_info({ping}, State) ->
    PingMsg = #{type => <<"ping">>, timestamp => erlang:system_time(second)},
    {[{text, jsx:encode(PingMsg)}], State};

websocket_info(_Info, State) ->
    {ok, State}.

terminate(_Reason, _Req, State) ->
    case State#state.authenticated of
        true ->
            aethertalk_websocket_manager:unregister_connection(self());
        false ->
            ok
    end,
    ok.

%% Internal functions

handle_message(#{<<"type">> := <<"auth">>, <<"data">> := AuthData}, State) ->
    case State#state.authenticated of
        true ->
            ErrorMsg = create_error_message(<<"already_authenticated">>, <<"Already authenticated">>),
            {[{text, jsx:encode(ErrorMsg)}], State};
        false ->
            handle_authentication(AuthData, State)
    end;

handle_message(#{<<"type">> := Type, <<"data">> := Data}, State) ->
    case State#state.authenticated of
        true ->
            handle_authenticated_message(Type, Data, State);
        false ->
            ErrorMsg = create_error_message(<<"not_authenticated">>, <<"Authentication required">>),
            {[{text, jsx:encode(ErrorMsg)}], State}
    end;

handle_message(_Message, State) ->
    ErrorMsg = create_error_message(<<"invalid_message">>, <<"Invalid message format">>),
    {[{text, jsx:encode(ErrorMsg)}], State}.

handle_authentication(AuthData, State) ->
    Token = maps:get(<<"token">>, AuthData, undefined),
    case Token of
        undefined ->
            ErrorMsg = create_error_message(<<"missing_token">>, <<"Token required">>),
            {[{text, jsx:encode(ErrorMsg)}], State};
        _ ->
            case authenticate_token(Token) of
                {ok, UserId, SessionId} ->
                    % Register connection
                    SessionData = #{
                        session_id => SessionId,
                        device_id => State#state.device_id
                    },
                    aethertalk_websocket_manager:register_connection(self(), UserId, SessionData),
                    
                    % Send success response
                    SuccessMsg = #{
                        type => <<"auth_success">>,
                        data => #{
                            user_id => UserId,
                            session_id => SessionId
                        }
                    },
                    
                    NewState = State#state{
                        user_id = UserId,
                        session_id = SessionId,
                        authenticated = true
                    },
                    {[{text, jsx:encode(SuccessMsg)}], NewState};
                {error, Reason} ->
                    ErrorMsg = create_error_message(<<"auth_failed">>, atom_to_binary(Reason)),
                    {[{text, jsx:encode(ErrorMsg)}], State}
            end
    end.

handle_authenticated_message(<<"send_message">>, MessageData, State) ->
    % Add sender_id to message data
    EnrichedData = MessageData#{<<"sender_id">> => State#state.user_id},
    
    case aethertalk_message_router:send_message(EnrichedData) of
        {ok, Message} ->
            AckMsg = #{
                type => <<"message_sent">>,
                data => Message
            },
            {[{text, jsx:encode(AckMsg)}], State};
        {error, Reason} ->
            ErrorMsg = create_error_message(<<"send_failed">>, atom_to_binary(Reason)),
            {[{text, jsx:encode(ErrorMsg)}], State}
    end;

handle_authenticated_message(<<"join_chat">>, #{<<"chat_id">> := ChatId}, State) ->
    % Subscribe to chat updates
    aethertalk_websocket_manager:subscribe_to_chat(self(), ChatId),
    
    % Update state
    NewSubscriptions = [ChatId | State#state.subscribed_chats],
    NewState = State#state{subscribed_chats = NewSubscriptions},
    
    AckMsg = #{
        type => <<"chat_joined">>,
        data => #{chat_id => ChatId}
    },
    {[{text, jsx:encode(AckMsg)}], NewState};

handle_authenticated_message(<<"leave_chat">>, #{<<"chat_id">> := ChatId}, State) ->
    % Unsubscribe from chat updates
    aethertalk_websocket_manager:unsubscribe_from_chat(self(), ChatId),
    
    % Update state
    NewSubscriptions = lists:delete(ChatId, State#state.subscribed_chats),
    NewState = State#state{subscribed_chats = NewSubscriptions},
    
    AckMsg = #{
        type => <<"chat_left">>,
        data => #{chat_id => ChatId}
    },
    {[{text, jsx:encode(AckMsg)}], NewState};

handle_authenticated_message(<<"typing_start">>, #{<<"chat_id">> := ChatId}, State) ->
    aethertalk_presence_manager:set_typing(State#state.user_id, ChatId, true),
    {ok, State};

handle_authenticated_message(<<"typing_stop">>, #{<<"chat_id">> := ChatId}, State) ->
    aethertalk_presence_manager:stop_typing(State#state.user_id, ChatId),
    {ok, State};

handle_authenticated_message(<<"mark_delivered">>, #{<<"message_id">> := MessageId}, State) ->
    aethertalk_message_router:mark_message_delivered(MessageId, State#state.user_id),
    {ok, State};

handle_authenticated_message(<<"mark_read">>, #{<<"message_id">> := MessageId}, State) ->
    aethertalk_message_router:mark_message_read(MessageId, State#state.user_id),
    {ok, State};

handle_authenticated_message(<<"get_messages">>, Data, State) ->
    ChatId = maps:get(<<"chat_id">>, Data),
    Limit = maps:get(<<"limit">>, Data, 50),
    Offset = maps:get(<<"offset">>, Data, 0),
    
    case aethertalk_message_router:get_chat_messages(ChatId, Limit, Offset, State#state.user_id) of
        {ok, Messages} ->
            ResponseMsg = #{
                type => <<"messages">>,
                data => #{
                    chat_id => ChatId,
                    messages => Messages
                }
            },
            {[{text, jsx:encode(ResponseMsg)}], State};
        {error, Reason} ->
            ErrorMsg = create_error_message(<<"get_messages_failed">>, atom_to_binary(Reason)),
            {[{text, jsx:encode(ErrorMsg)}], State}
    end;

handle_authenticated_message(<<"get_chats">>, _Data, State) ->
    case aethertalk_message_router:get_user_chats(State#state.user_id) of
        {ok, Chats} ->
            ResponseMsg = #{
                type => <<"chats">>,
                data => #{chats => Chats}
            },
            {[{text, jsx:encode(ResponseMsg)}], State};
        {error, Reason} ->
            ErrorMsg = create_error_message(<<"get_chats_failed">>, atom_to_binary(Reason)),
            {[{text, jsx:encode(ErrorMsg)}], State}
    end;

handle_authenticated_message(<<"call_signal">>, SignalData, State) ->
    % Handle WebRTC signaling
    handle_call_signal(SignalData, State);

handle_authenticated_message(<<"pong">>, _Data, State) ->
    % Handle pong response
    {ok, State};

handle_authenticated_message(Type, _Data, State) ->
    ErrorMsg = create_error_message(<<"unknown_message_type">>, <<"Unknown message type: ", Type/binary>>),
    {[{text, jsx:encode(ErrorMsg)}], State}.

handle_call_signal(SignalData, State) ->
    CallId = maps:get(<<"call_id">>, SignalData),
    SignalType = maps:get(<<"signal_type">>, SignalData),
    Signal = maps:get(<<"signal">>, SignalData),
    
    % Forward signal to call manager
    case aethertalk_call_manager:handle_signal(CallId, State#state.user_id, SignalType, Signal) of
        ok ->
            {ok, State};
        {error, Reason} ->
            ErrorMsg = create_error_message(<<"call_signal_failed">>, atom_to_binary(Reason)),
            {[{text, jsx:encode(ErrorMsg)}], State}
    end.

authenticate_token(Token) ->
    % Validate JWT token
    case aethertalk_auth:validate_token(Token) of
        {ok, Claims} ->
            UserId = maps:get(<<"user_id">>, Claims),
            SessionId = maps:get(<<"session_id">>, Claims),
            {ok, UserId, SessionId};
        {error, Reason} ->
            {error, Reason}
    end.

check_rate_limit(State) ->
    CurrentTime = erlang:system_time(second),
    
    case CurrentTime >= State#state.rate_limit_reset_time of
        true ->
            % Reset rate limit counter
            NewState = State#state{
                rate_limit_counter = 1,
                rate_limit_reset_time = CurrentTime + ?RATE_LIMIT_WINDOW
            },
            {ok, NewState};
        false ->
            case State#state.rate_limit_counter >= ?RATE_LIMIT_MAX_REQUESTS of
                true ->
                    {error, rate_limited};
                false ->
                    NewState = State#state{
                        rate_limit_counter = State#state.rate_limit_counter + 1
                    },
                    {ok, NewState}
            end
    end.

create_error_message(Code, Message) ->
    #{
        type => <<"error">>,
        data => #{
            code => Code,
            message => Message,
            timestamp => erlang:system_time(second)
        }
    }.

atom_to_binary(Atom) when is_atom(Atom) ->
    erlang:atom_to_binary(Atom, utf8);
atom_to_binary(Binary) when is_binary(Binary) ->
    Binary.