%% @doc Streaming Translation Coordinator
%% Orchestrates the complete audio translation pipeline:
%% Audio -> STT -> Translation -> TTS -> Audio
-module(aethertalk_streaming_translation).

-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([start_translation_session/5]).
-export([stream_audio_chunk/2]).
-export([end_translation_session/1]).
-export([get_user_translation_settings/1]).
-export([update_user_translation_settings/2]).
-export([get_supported_languages/0]).
-export([get_available_voices/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
    translation_sessions :: map(),
    user_settings :: map()
}).

-record(translation_session, {
    session_id :: binary(),
    user_id :: binary(),
    source_language :: binary(),
    target_language :: binary(),
    voice :: binary(),
    callback_pid :: pid(),
    stt_session_id :: binary(),
    translation_session_id :: binary(),
    tts_session_id :: binary(),
    enabled :: boolean(),
    text_output :: boolean(),
    voice_output :: boolean(),
    created_at :: integer()
}).

-record(user_translation_settings, {
    user_id :: binary(),
    enabled :: boolean(),
    source_language :: binary(),
    target_language :: binary(),
    voice :: binary(),
    text_output :: boolean(),
    voice_output :: boolean(),
    auto_detect :: boolean()
}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Starts the streaming translation coordinator
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Start a new translation session for a user
-spec start_translation_session(binary(), binary(), binary(), binary(), pid()) -> 
    {ok, binary()} | {error, term()}.
start_translation_session(UserId, SourceLang, TargetLang, Voice, CallbackPid) ->
    gen_server:call(?SERVER, {start_session, UserId, SourceLang, TargetLang, Voice, CallbackPid}).

%% @doc Stream audio chunk to translation session
-spec stream_audio_chunk(binary(), binary()) -> ok.
stream_audio_chunk(SessionId, AudioChunk) ->
    gen_server:cast(?SERVER, {stream_audio, SessionId, AudioChunk}).

%% @doc End translation session
-spec end_translation_session(binary()) -> ok.
end_translation_session(SessionId) ->
    gen_server:cast(?SERVER, {end_session, SessionId}).

%% @doc Get user's translation settings
-spec get_user_translation_settings(binary()) -> {ok, map()} | {error, term()}.
get_user_translation_settings(UserId) ->
    gen_server:call(?SERVER, {get_user_settings, UserId}).

%% @doc Update user's translation settings
-spec update_user_translation_settings(binary(), map()) -> ok | {error, term()}.
update_user_translation_settings(UserId, Settings) ->
    gen_server:call(?SERVER, {update_user_settings, UserId, Settings}).

%% @doc Get supported languages
-spec get_supported_languages() -> {ok, list()}.
get_supported_languages() ->
    gen_server:call(?SERVER, get_languages).

%% @doc Get available voices
-spec get_available_voices() -> {ok, list()}.
get_available_voices() ->
    gen_server:call(?SERVER, get_voices).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
init([]) ->
    lager:info("Streaming translation coordinator started"),
    
    {ok, #state{
        translation_sessions = #{},
        user_settings = #{}
    }}.

%% @private
handle_call({start_session, UserId, SourceLang, TargetLang, Voice, CallbackPid}, _From, State) ->
    SessionId = generate_session_id(),
    
    % Get user settings to check if translation is enabled
    UserSettings = get_user_settings_internal(UserId, State),
    
    case UserSettings#user_translation_settings.enabled of
        false ->
            {reply, {error, translation_disabled}, State};
        true ->
            % Start sub-sessions for STT, Translation, and TTS
            STTSessionId = <<SessionId/binary, "_stt">>,
            TranslationSessionId = <<SessionId/binary, "_trans">>,
            TTSSessionId = <<SessionId/binary, "_tts">>,
            
            % Create translation session record
            Session = #translation_session{
                session_id = SessionId,
                user_id = UserId,
                source_language = SourceLang,
                target_language = TargetLang,
                voice = Voice,
                callback_pid = CallbackPid,
                stt_session_id = STTSessionId,
                translation_session_id = TranslationSessionId,
                tts_session_id = TTSSessionId,
                enabled = UserSettings#user_translation_settings.enabled,
                text_output = UserSettings#user_translation_settings.text_output,
                voice_output = UserSettings#user_translation_settings.voice_output,
                created_at = erlang:system_time(second)
            },
            
            % Start STT session
            case aethertalk_maestra_stt:start_streaming_transcription(STTSessionId, SourceLang, self()) of
                {ok, _} ->
                    % Start translation session
                    case aethertalk_lecto_ai:translate_streaming(TranslationSessionId, SourceLang, TargetLang, self()) of
                        {ok, _} ->
                            % Start TTS session if voice output is enabled
                            TTSResult = case UserSettings#user_translation_settings.voice_output of
                                true ->
                                    aethertalk_notegpt_tts:start_streaming_synthesis(TTSSessionId, TargetLang, Voice, self());
                                false ->
                                    {ok, disabled}
                            end,
                            
                            case TTSResult of
                                {ok, _} ->
                                    NewSessions = maps:put(SessionId, Session, State#state.translation_sessions),
                                    NewState = State#state{translation_sessions = NewSessions},
                                    
                                    lager:info("Started streaming translation session: ~s for user ~s (~s -> ~s)", 
                                              [SessionId, UserId, SourceLang, TargetLang]),
                                    
                                    {reply, {ok, SessionId}, NewState};
                                {error, Reason} ->
                                    % Cleanup STT and translation sessions
                                    aethertalk_maestra_stt:end_streaming_transcription(STTSessionId),
                                    aethertalk_lecto_ai:end_streaming_session(TranslationSessionId),
                                    {reply, {error, {tts_failed, Reason}}, State}
                            end;
                        {error, Reason} ->
                            % Cleanup STT session
                            aethertalk_maestra_stt:end_streaming_transcription(STTSessionId),
                            {reply, {error, {translation_failed, Reason}}, State}
                    end;
                {error, Reason} ->
                    {reply, {error, {stt_failed, Reason}}, State}
            end
    end;

handle_call({get_user_settings, UserId}, _From, State) ->
    Settings = get_user_settings_internal(UserId, State),
    SettingsMap = user_settings_to_map(Settings),
    {reply, {ok, SettingsMap}, State};

handle_call({update_user_settings, UserId, SettingsMap}, _From, State) ->
    Settings = map_to_user_settings(UserId, SettingsMap),
    NewUserSettings = maps:put(UserId, Settings, State#state.user_settings),
    NewState = State#state{user_settings = NewUserSettings},
    
    lager:info("Updated translation settings for user ~s", [UserId]),
    {reply, ok, NewState};

handle_call(get_languages, _From, State) ->
    case aethertalk_maestra_stt:get_supported_languages() of
        {ok, Languages} ->
            {reply, {ok, Languages}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(get_voices, _From, State) ->
    case aethertalk_notegpt_tts:get_available_voices() of
        {ok, Voices} ->
            {reply, {ok, Voices}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({stream_audio, SessionId, AudioChunk}, State) ->
    case maps:get(SessionId, State#state.translation_sessions, undefined) of
        undefined ->
            lager:warning("Translation session not found: ~s", [SessionId]),
            {noreply, State};
        Session ->
            % Forward audio to STT session
            aethertalk_maestra_stt:stream_audio_chunk(Session#translation_session.stt_session_id, AudioChunk),
            {noreply, State}
    end;

handle_cast({end_session, SessionId}, State) ->
    case maps:get(SessionId, State#state.translation_sessions, undefined) of
        undefined ->
            {noreply, State};
        Session ->
            % End all sub-sessions
            aethertalk_maestra_stt:end_streaming_transcription(Session#translation_session.stt_session_id),
            aethertalk_lecto_ai:end_streaming_session(Session#translation_session.translation_session_id),
            
            case Session#translation_session.voice_output of
                true ->
                    aethertalk_notegpt_tts:end_streaming_synthesis(Session#translation_session.tts_session_id);
                false ->
                    ok
            end,
            
            % Remove session
            NewSessions = maps:remove(SessionId, State#state.translation_sessions),
            NewState = State#state{translation_sessions = NewSessions},
            
            lager:info("Ended streaming translation session: ~s", [SessionId]),
            {noreply, NewState}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({transcription_chunk, STTSessionId, TranscribedText}, State) ->
    % Find the session by STT session ID
    case find_session_by_stt_id(STTSessionId, State#state.translation_sessions) of
        {ok, SessionId, Session} ->
            % Send transcribed text to translation service
            aethertalk_lecto_ai:stream_text_chunk(Session#translation_session.translation_session_id, TranscribedText),
            
            % If text output is enabled, send to callback
            case Session#translation_session.text_output of
                true ->
                    Session#translation_session.callback_pid ! {transcription_text, SessionId, TranscribedText};
                false ->
                    ok
            end;
        not_found ->
            lager:warning("Session not found for STT session: ~s", [STTSessionId])
    end,
    {noreply, State};

handle_info({translation_chunk, TranslationSessionId, TranslatedText}, State) ->
    % Find the session by translation session ID
    case find_session_by_translation_id(TranslationSessionId, State#state.translation_sessions) of
        {ok, SessionId, Session} ->
            % Send translated text to TTS if voice output is enabled
            case Session#translation_session.voice_output of
                true ->
                    aethertalk_notegpt_tts:stream_text_chunk(Session#translation_session.tts_session_id, TranslatedText);
                false ->
                    ok
            end,
            
            % If text output is enabled, send to callback
            case Session#translation_session.text_output of
                true ->
                    Session#translation_session.callback_pid ! {translation_text, SessionId, TranslatedText};
                false ->
                    ok
            end;
        not_found ->
            lager:warning("Session not found for translation session: ~s", [TranslationSessionId])
    end,
    {noreply, State};

handle_info({synthesis_chunk, TTSSessionId, AudioData}, State) ->
    % Find the session by TTS session ID
    case find_session_by_tts_id(TTSSessionId, State#state.translation_sessions) of
        {ok, SessionId, Session} ->
            % Send synthesized audio to callback
            Session#translation_session.callback_pid ! {translation_audio, SessionId, AudioData};
        not_found ->
            lager:warning("Session not found for TTS session: ~s", [TTSSessionId])
    end,
    {noreply, State};

handle_info({transcription_complete, STTSessionId}, State) ->
    case find_session_by_stt_id(STTSessionId, State#state.translation_sessions) of
        {ok, _SessionId, Session} ->
            aethertalk_lecto_ai:end_streaming_session(Session#translation_session.translation_session_id);
        not_found ->
            ok
    end,
    {noreply, State};

handle_info({translation_complete, TranslationSessionId}, State) ->
    case find_session_by_translation_id(TranslationSessionId, State#state.translation_sessions) of
        {ok, SessionId, Session} ->
            case Session#translation_session.voice_output of
                true ->
                    aethertalk_notegpt_tts:end_streaming_synthesis(Session#translation_session.tts_session_id);
                false ->
                    Session#translation_session.callback_pid ! {translation_complete, SessionId}
            end;
        not_found ->
            ok
    end,
    {noreply, State};

handle_info({synthesis_complete, TTSSessionId}, State) ->
    case find_session_by_tts_id(TTSSessionId, State#state.translation_sessions) of
        {ok, SessionId, Session} ->
            Session#translation_session.callback_pid ! {translation_complete, SessionId};
        not_found ->
            ok
    end,
    {noreply, State};

handle_info({transcription_error, STTSessionId, Reason}, State) ->
    case find_session_by_stt_id(STTSessionId, State#state.translation_sessions) of
        {ok, SessionId, Session} ->
            Session#translation_session.callback_pid ! {translation_error, SessionId, {stt_error, Reason}};
        not_found ->
            ok
    end,
    {noreply, State};

handle_info({translation_error, TranslationSessionId, Reason}, State) ->
    case find_session_by_translation_id(TranslationSessionId, State#state.translation_sessions) of
        {ok, SessionId, Session} ->
            Session#translation_session.callback_pid ! {translation_error, SessionId, {translation_error, Reason}};
        not_found ->
            ok
    end,
    {noreply, State};

handle_info({synthesis_error, TTSSessionId, Reason}, State) ->
    case find_session_by_tts_id(TTSSessionId, State#state.translation_sessions) of
        {ok, SessionId, Session} ->
            Session#translation_session.callback_pid ! {translation_error, SessionId, {tts_error, Reason}};
        not_found ->
            ok
    end,
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @private
generate_session_id() ->
    Timestamp = integer_to_binary(erlang:system_time(microsecond)),
    Random = integer_to_binary(rand:uniform(999999)),
    <<"stream_trans_", Timestamp/binary, "_", Random/binary>>.

%% @private
get_user_settings_internal(UserId, State) ->
    case maps:get(UserId, State#state.user_settings, undefined) of
        undefined ->
            % Return default settings
            #user_translation_settings{
                user_id = UserId,
                enabled = false,
                source_language = <<"auto">>,
                target_language = <<"en">>,
                voice = <<"en-US-female-1">>,
                text_output = true,
                voice_output = true,
                auto_detect = true
            };
        Settings ->
            Settings
    end.

%% @private
user_settings_to_map(Settings) ->
    #{
        <<"user_id">> => Settings#user_translation_settings.user_id,
        <<"enabled">> => Settings#user_translation_settings.enabled,
        <<"source_language">> => Settings#user_translation_settings.source_language,
        <<"target_language">> => Settings#user_translation_settings.target_language,
        <<"voice">> => Settings#user_translation_settings.voice,
        <<"text_output">> => Settings#user_translation_settings.text_output,
        <<"voice_output">> => Settings#user_translation_settings.voice_output,
        <<"auto_detect">> => Settings#user_translation_settings.auto_detect
    }.

%% @private
map_to_user_settings(UserId, SettingsMap) ->
    #user_translation_settings{
        user_id = UserId,
        enabled = maps:get(<<"enabled">>, SettingsMap, false),
        source_language = maps:get(<<"source_language">>, SettingsMap, <<"auto">>),
        target_language = maps:get(<<"target_language">>, SettingsMap, <<"en">>),
        voice = maps:get(<<"voice">>, SettingsMap, <<"en-US-female-1">>),
        text_output = maps:get(<<"text_output">>, SettingsMap, true),
        voice_output = maps:get(<<"voice_output">>, SettingsMap, true),
        auto_detect = maps:get(<<"auto_detect">>, SettingsMap, true)
    }.

%% @private
find_session_by_stt_id(STTSessionId, Sessions) ->
    maps:fold(fun(SessionId, Session, Acc) ->
        case Session#translation_session.stt_session_id of
            STTSessionId -> {ok, SessionId, Session};
            _ -> Acc
        end
    end, not_found, Sessions).

%% @private
find_session_by_translation_id(TranslationSessionId, Sessions) ->
    maps:fold(fun(SessionId, Session, Acc) ->
        case Session#translation_session.translation_session_id of
            TranslationSessionId -> {ok, SessionId, Session};
            _ -> Acc
        end
    end, not_found, Sessions).

%% @private
find_session_by_tts_id(TTSSessionId, Sessions) ->
    maps:fold(fun(SessionId, Session, Acc) ->
        case Session#translation_session.tts_session_id of
            TTSSessionId -> {ok, SessionId, Session};
            _ -> Acc
        end
    end, not_found, Sessions).