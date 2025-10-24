%% @doc WebSocket handler for streaming translation events
%% Provides real-time translation updates via WebSocket
-module(aethertalk_streaming_translation_ws).

-export([init/2]).
-export([websocket_init/1]).
-export([websocket_handle/2]).
-export([websocket_info/2]).
-export([terminate/3]).

-record(state, {
    user_id :: binary(),
    translation_session_id :: binary() | undefined,
    authenticated :: boolean()
}).

%%%===================================================================
%%% Cowboy WebSocket Callbacks
%%%===================================================================

%% @private
init(Req, _State) ->
    lager:info("Streaming translation WebSocket connection initiated"),
    {cowboy_websocket, Req, #state{authenticated = false}}.

%% @private
websocket_init(State) ->
    lager:info("Streaming translation WebSocket initialized"),
    
    % Send welcome message
    WelcomeMsg = jsx:encode(#{
        type => <<"welcome">>,
        message => <<"Streaming translation WebSocket connected">>,
        timestamp => erlang:system_time(second)
    }),
    
    {[{text, WelcomeMsg}], State}.

%% @private
websocket_handle({text, Msg}, State) ->
    try
        Data = jsx:decode(Msg, [return_maps]),
        handle_message(Data, State)
    catch
        Error:Reason ->
            lager:error("Failed to parse WebSocket message: ~p:~p", [Error, Reason]),
            ErrorMsg = jsx:encode(#{
                type => <<"error">>,
                message => <<"Invalid message format">>,
                timestamp => erlang:system_time(second)
            }),
            {[{text, ErrorMsg}], State}
    end;

websocket_handle({binary, Data}, State) ->
    % Handle binary audio data for streaming translation
    case State#state.authenticated of
        true ->
            case State#state.translation_session_id of
                undefined ->
                    ErrorMsg = jsx:encode(#{
                        type => <<"error">>,
                        message => <<"No active translation session">>,
                        timestamp => erlang:system_time(second)
                    }),
                    {[{text, ErrorMsg}], State};
                SessionId ->
                    % Stream audio data to translation service
                    aethertalk_streaming_translation:stream_audio_chunk(SessionId, Data),
                    {[], State}
            end;
        false ->
            ErrorMsg = jsx:encode(#{
                type => <<"error">>,
                message => <<"Authentication required">>,
                timestamp => erlang:system_time(second)
            }),
            {[{text, ErrorMsg}], State}
    end;

websocket_handle(_Frame, State) ->
    {[], State}.

%% @private
websocket_info({translation_text, SessionId, Text}, State) ->
    case State#state.translation_session_id of
        SessionId ->
            Msg = jsx:encode(#{
                type => <<"translation_text">>,
                session_id => SessionId,
                text => Text,
                timestamp => erlang:system_time(second)
            }),
            {[{text, Msg}], State};
        _ ->
            {[], State}
    end;

websocket_info({transcription_text, SessionId, Text}, State) ->
    case State#state.translation_session_id of
        SessionId ->
            Msg = jsx:encode(#{
                type => <<"transcription_text">>,
                session_id => SessionId,
                text => Text,
                timestamp => erlang:system_time(second)
            }),
            {[{text, Msg}], State};
        _ ->
            {[], State}
    end;

websocket_info({translation_audio, SessionId, AudioData}, State) ->
    case State#state.translation_session_id of
        SessionId ->
            % Send audio data as binary frame
            {[{binary, AudioData}], State};
        _ ->
            {[], State}
    end;

websocket_info({translation_complete, SessionId}, State) ->
    case State#state.translation_session_id of
        SessionId ->
            Msg = jsx:encode(#{
                type => <<"translation_complete">>,
                session_id => SessionId,
                timestamp => erlang:system_time(second)
            }),
            NewState = State#state{translation_session_id = undefined},
            {[{text, Msg}], NewState};
        _ ->
            {[], State}
    end;

websocket_info({translation_error, SessionId, Reason}, State) ->
    case State#state.translation_session_id of
        SessionId ->
            Msg = jsx:encode(#{
                type => <<"translation_error">>,
                session_id => SessionId,
                error => format_error(Reason),
                timestamp => erlang:system_time(second)
            }),
            NewState = State#state{translation_session_id = undefined},
            {[{text, Msg}], NewState};
        _ ->
            {[], State}
    end;

websocket_info(_Info, State) ->
    {[], State}.

%% @private
terminate(Reason, _PartialReq, State) ->
    lager:info("Streaming translation WebSocket terminated: ~p", [Reason]),
    
    % Clean up translation session if active
    case State#state.translation_session_id of
        undefined -> ok;
        SessionId ->
            aethertalk_streaming_translation:end_translation_session(SessionId)
    end,
    
    ok.

%%%===================================================================
%%% Message Handlers
%%%===================================================================

%% @private
handle_message(#{<<"type">> := <<"authenticate">>, <<"token">> := Token}, State) ->
    case aethertalk_auth:verify_jwt_token(Token) of
        {ok, UserId} ->
            lager:info("Streaming translation WebSocket authenticated for user: ~s", [UserId]),
            
            AuthMsg = jsx:encode(#{
                type => <<"authenticated">>,
                user_id => UserId,
                timestamp => erlang:system_time(second)
            }),
            
            NewState = State#state{
                user_id = UserId,
                authenticated = true
            },
            
            {[{text, AuthMsg}], NewState};
        {error, Reason} ->
            lager:warning("Streaming translation WebSocket authentication failed: ~p", [Reason]),
            
            ErrorMsg = jsx:encode(#{
                type => <<"auth_error">>,
                message => <<"Authentication failed">>,
                timestamp => erlang:system_time(second)
            }),
            
            {[{text, ErrorMsg}], State}
    end;

handle_message(#{<<"type">> := <<"start_translation">>, 
                 <<"source_language">> := SourceLang,
                 <<"target_language">> := TargetLang} = Data, State) ->
    case State#state.authenticated of
        false ->
            ErrorMsg = jsx:encode(#{
                type => <<"error">>,
                message => <<"Authentication required">>,
                timestamp => erlang:system_time(second)
            }),
            {[{text, ErrorMsg}], State};
        true ->
            Voice = maps:get(<<"voice">>, Data, <<"en-US-female-1">>),
            UserId = State#state.user_id,
            
            case aethertalk_streaming_translation:start_translation_session(
                    UserId, SourceLang, TargetLang, Voice, self()) of
                {ok, SessionId} ->
                    lager:info("Started streaming translation session: ~s", [SessionId]),
                    
                    StartMsg = jsx:encode(#{
                        type => <<"translation_started">>,
                        session_id => SessionId,
                        source_language => SourceLang,
                        target_language => TargetLang,
                        voice => Voice,
                        timestamp => erlang:system_time(second)
                    }),
                    
                    NewState = State#state{translation_session_id = SessionId},
                    {[{text, StartMsg}], NewState};
                {error, Reason} ->
                    lager:error("Failed to start streaming translation: ~p", [Reason]),
                    
                    ErrorMsg = jsx:encode(#{
                        type => <<"error">>,
                        message => format_error(Reason),
                        timestamp => erlang:system_time(second)
                    }),
                    
                    {[{text, ErrorMsg}], State}
            end
    end;

handle_message(#{<<"type">> := <<"ping">>}, State) ->
    PongMsg = jsx:encode(#{
        type => <<"pong">>,
        timestamp => erlang:system_time(second)
    }),
    {[{text, PongMsg}], State};

handle_message(Data, State) ->
    lager:warning("Unknown streaming translation WebSocket message: ~p", [Data]),
    
    ErrorMsg = jsx:encode(#{
        type => <<"error">>,
        message => <<"Unknown message type">>,
        timestamp => erlang:system_time(second)
    }),
    
    {[{text, ErrorMsg}], State}.

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @private
format_error(translation_disabled) ->
    <<"Translation is disabled for this user">>;
format_error({stt_failed, Reason}) ->
    <<"Speech-to-text service failed: ", (format_error(Reason))/binary>>;
format_error({translation_failed, Reason}) ->
    <<"Translation service failed: ", (format_error(Reason))/binary>>;
format_error({tts_failed, Reason}) ->
    <<"Text-to-speech service failed: ", (format_error(Reason))/binary>>;
format_error(Reason) when is_atom(Reason) ->
    atom_to_binary(Reason, utf8);
format_error(Reason) when is_binary(Reason) ->
    Reason;
format_error(Reason) ->
    iolist_to_binary(io_lib:format("~p", [Reason])).