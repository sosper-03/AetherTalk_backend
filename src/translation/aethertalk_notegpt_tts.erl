%% @doc NoteGPT Text-to-Speech Service Integration
%% Provides text-to-speech conversion using NoteGPT API
-module(aethertalk_notegpt_tts).

-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([synthesize_speech/3, synthesize_speech/4]).
-export([start_streaming_synthesis/4]).
-export([stream_text_chunk/2]).
-export([end_streaming_synthesis/1]).
-export([get_available_voices/0]).
-export([get_supported_languages/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(DEFAULT_TIMEOUT, 20000).
-define(TEXT_CHUNK_SIZE, 200).

-record(state, {
    api_url :: binary(),
    http_options :: list(),
    streaming_sessions :: map()
}).

-record(streaming_session, {
    language :: binary(),
    voice :: binary(),
    callback_pid :: pid(),
    text_buffer :: binary(),
    session_id :: binary(),
    created_at :: integer()
}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Starts the NoteGPT TTS server
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Synthesize speech from text
-spec synthesize_speech(binary(), binary(), binary()) -> {ok, binary()} | {error, term()}.
synthesize_speech(Text, Language, Voice) ->
    synthesize_speech(Text, Language, Voice, ?DEFAULT_TIMEOUT).

%% @doc Synthesize speech with custom timeout
-spec synthesize_speech(binary(), binary(), binary(), integer()) -> {ok, binary()} | {error, term()}.
synthesize_speech(Text, Language, Voice, Timeout) ->
    gen_server:call(?SERVER, {synthesize, Text, Language, Voice}, Timeout).

%% @doc Start streaming speech synthesis session
-spec start_streaming_synthesis(binary(), binary(), binary(), pid()) -> {ok, binary()} | {error, term()}.
start_streaming_synthesis(SessionId, Language, Voice, CallbackPid) ->
    gen_server:call(?SERVER, {start_streaming, SessionId, Language, Voice, CallbackPid}).

%% @doc Stream text chunk to synthesis session
-spec stream_text_chunk(binary(), binary()) -> ok.
stream_text_chunk(SessionId, TextChunk) ->
    gen_server:cast(?SERVER, {stream_text, SessionId, TextChunk}).

%% @doc End streaming synthesis session
-spec end_streaming_synthesis(binary()) -> ok.
end_streaming_synthesis(SessionId) ->
    gen_server:cast(?SERVER, {end_streaming, SessionId}).

%% @doc Get available voices
-spec get_available_voices() -> {ok, list()} | {error, term()}.
get_available_voices() ->
    gen_server:call(?SERVER, get_voices).

%% @doc Get supported languages
-spec get_supported_languages() -> {ok, list()} | {error, term()}.
get_supported_languages() ->
    gen_server:call(?SERVER, get_languages).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
init([]) ->
    ApiUrl = case os:getenv("NOTEGPT_TTS_URL") of
        false -> <<"https://api.notegpt.io/v1/tts">>;
        Url -> list_to_binary(Url)
    end,
    
    HttpOptions = [
        {timeout, 60000},
        {connect_timeout, 10000},
        {ssl, [{verify, verify_none}]}
    ],
    
    lager:info("NoteGPT TTS service started with URL: ~s", [ApiUrl]),
    
    {ok, #state{
        api_url = ApiUrl,
        http_options = HttpOptions,
        streaming_sessions = #{}
    }}.

%% @private
handle_call({synthesize, Text, Language, Voice}, _From, State) ->
    Result = perform_synthesis(Text, Language, Voice, State),
    {reply, Result, State};

handle_call({start_streaming, SessionId, Language, Voice, CallbackPid}, _From, State) ->
    Session = #streaming_session{
        language = Language,
        voice = Voice,
        callback_pid = CallbackPid,
        text_buffer = <<>>,
        session_id = SessionId,
        created_at = erlang:system_time(second)
    },
    
    NewSessions = maps:put(SessionId, Session, State#state.streaming_sessions),
    NewState = State#state{streaming_sessions = NewSessions},
    
    lager:info("Started streaming synthesis session: ~s (~s, ~s)", [SessionId, Language, Voice]),
    
    {reply, {ok, SessionId}, NewState};

handle_call(get_voices, _From, State) ->
    Voices = get_available_voices_impl(),
    {reply, {ok, Voices}, State};

handle_call(get_languages, _From, State) ->
    Languages = get_supported_languages_impl(),
    {reply, {ok, Languages}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({stream_text, SessionId, TextChunk}, State) ->
    case maps:get(SessionId, State#state.streaming_sessions, undefined) of
        undefined ->
            lager:warning("Streaming session not found: ~s", [SessionId]),
            {noreply, State};
        Session ->
            NewState = process_text_chunk(SessionId, TextChunk, Session, State),
            {noreply, NewState}
    end;

handle_cast({end_streaming, SessionId}, State) ->
    case maps:get(SessionId, State#state.streaming_sessions, undefined) of
        undefined ->
            {noreply, State};
        Session ->
            % Process any remaining text buffer
            process_final_text(SessionId, Session, State),
            NewSessions = maps:remove(SessionId, State#state.streaming_sessions),
            NewState = State#state{streaming_sessions = NewSessions},
            lager:info("Ended streaming synthesis session: ~s", [SessionId]),
            {noreply, NewState}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
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
perform_synthesis(Text, Language, Voice, _State) ->
    % For demo purposes, we'll simulate the NoteGPT API call
    % In a real implementation, you would make an HTTP request to NoteGPT
    
    case validate_synthesis_params(Text, Language, Voice) of
        ok ->
            % Simulate audio generation
            AudioData = simulate_audio_generation(Text, Language, Voice),
            lager:info("Synthesized speech for text: ~s (language: ~s, voice: ~s)", 
                      [truncate_text(Text, 50), Language, Voice]),
            {ok, AudioData};
        {error, Reason} ->
            {error, Reason}
    end.

%% @private
process_text_chunk(SessionId, TextChunk, Session, State) ->
    Buffer = Session#streaming_session.text_buffer,
    NewBuffer = <<Buffer/binary, TextChunk/binary>>,
    
    % Check if we have enough text to synthesize
    if
        byte_size(NewBuffer) >= ?TEXT_CHUNK_SIZE ->
            % Find a good break point (sentence end, word boundary, etc.)
            {ToSynthesize, Remaining} = find_synthesis_boundary(NewBuffer),
            
            % Perform synthesis
            Language = Session#streaming_session.language,
            Voice = Session#streaming_session.voice,
            CallbackPid = Session#streaming_session.callback_pid,
            
            case perform_synthesis(ToSynthesize, Language, Voice, State) of
                {ok, AudioData} ->
                    % Send audio chunk to callback
                    CallbackPid ! {synthesis_chunk, SessionId, AudioData},
                    
                    % Update session with remaining buffer
                    UpdatedSession = Session#streaming_session{text_buffer = Remaining},
                    NewSessions = maps:put(SessionId, UpdatedSession, State#state.streaming_sessions),
                    State#state{streaming_sessions = NewSessions};
                {error, Reason} ->
                    lager:error("Streaming synthesis failed for session ~s: ~p", [SessionId, Reason]),
                    CallbackPid ! {synthesis_error, SessionId, Reason},
                    State
            end;
        true ->
            % Buffer the text chunk
            UpdatedSession = Session#streaming_session{text_buffer = NewBuffer},
            NewSessions = maps:put(SessionId, UpdatedSession, State#state.streaming_sessions),
            State#state{streaming_sessions = NewSessions}
    end.

%% @private
process_final_text(SessionId, Session, State) ->
    Buffer = Session#streaming_session.text_buffer,
    
    if
        byte_size(Buffer) > 0 ->
            Language = Session#streaming_session.language,
            Voice = Session#streaming_session.voice,
            CallbackPid = Session#streaming_session.callback_pid,
            
            case perform_synthesis(Buffer, Language, Voice, State) of
                {ok, AudioData} ->
                    CallbackPid ! {synthesis_chunk, SessionId, AudioData},
                    CallbackPid ! {synthesis_complete, SessionId};
                {error, Reason} ->
                    lager:error("Final text synthesis failed for session ~s: ~p", [SessionId, Reason]),
                    CallbackPid ! {synthesis_error, SessionId, Reason}
            end;
        true ->
            CallbackPid = Session#streaming_session.callback_pid,
            CallbackPid ! {synthesis_complete, SessionId}
    end.

%% @private
find_synthesis_boundary(Buffer) ->
    % Try to find sentence boundaries first
    case binary:matches(Buffer, [<<". ">>, <<"! ">>, <<"? ">>, <<"\n">>]) of
        [] ->
            % No sentence boundary, try word boundary
            case binary:last(Buffer) of
                $\s ->
                    {Buffer, <<>>};
                _ ->
                    % Find last space
                    case binary:match(Buffer, <<" ">>, [{scope, {byte_size(Buffer) - 50, 50}}]) of
                        {Pos, _} ->
                            <<ToSynthesize:Pos/binary, Remaining/binary>> = Buffer,
                            {ToSynthesize, Remaining};
                        nomatch ->
                            % No good boundary, split at chunk size
                            Size = min(byte_size(Buffer), ?TEXT_CHUNK_SIZE),
                            <<ToSynthesize:Size/binary, Remaining/binary>> = Buffer,
                            {ToSynthesize, Remaining}
                    end
            end;
        Matches ->
            % Use the last sentence boundary
            {Pos, Len} = lists:last(Matches),
            SplitPos = Pos + Len,
            <<ToSynthesize:SplitPos/binary, Remaining/binary>> = Buffer,
            {ToSynthesize, Remaining}
    end.

%% @private
validate_synthesis_params(Text, Language, Voice) ->
    case byte_size(Text) of
        0 -> {error, empty_text};
        Size when Size > 5000 -> {error, text_too_long};
        _ ->
            case is_supported_language(Language) of
                true ->
                    case is_available_voice(Voice, Language) of
                        true -> ok;
                        false -> {error, unsupported_voice}
                    end;
                false -> {error, unsupported_language}
            end
    end.

%% @private
simulate_audio_generation(Text, Language, Voice) ->
    % This is a simulation for demo purposes
    % In real implementation, this would call the NoteGPT API
    
    TextLength = byte_size(Text),
    
    % Generate simulated audio data based on text length
    % Approximate 1 second of audio per 10 characters (rough estimate)
    AudioDurationMs = max(1000, TextLength * 100),
    
    % Generate WAV header for simulated audio
    SampleRate = 22050,
    BitsPerSample = 16,
    Channels = 1,
    
    % Calculate audio data size
    AudioDataSize = (AudioDurationMs * SampleRate * BitsPerSample * Channels) div (1000 * 8),
    
    % Generate WAV header
    WavHeader = generate_wav_header(AudioDataSize, SampleRate, BitsPerSample, Channels),
    
    % Generate simulated audio data (silence with some variation)
    AudioData = generate_simulated_audio(AudioDataSize, Language, Voice),
    
    <<WavHeader/binary, AudioData/binary>>.

%% @private
generate_wav_header(DataSize, SampleRate, BitsPerSample, Channels) ->
    ByteRate = SampleRate * Channels * BitsPerSample div 8,
    BlockAlign = Channels * BitsPerSample div 8,
    FileSize = DataSize + 36,
    
    <<"RIFF", FileSize:32/little, "WAVE",
      "fmt ", 16:32/little, 1:16/little, Channels:16/little,
      SampleRate:32/little, ByteRate:32/little, BlockAlign:16/little,
      BitsPerSample:16/little, "data", DataSize:32/little>>.

%% @private
generate_simulated_audio(Size, _Language, _Voice) ->
    % Generate simple sine wave pattern for demo
    << <<(round(127 * math:sin(I * 0.1))):8/signed>> || I <- lists:seq(1, Size) >>.

%% @private
is_supported_language(Language) ->
    SupportedLanguages = [<<"en">>, <<"es">>, <<"fr">>, <<"de">>, <<"it">>, <<"pt">>, 
                         <<"ru">>, <<"ja">>, <<"ko">>, <<"zh">>, <<"ar">>, <<"hi">>,
                         <<"nl">>, <<"sv">>, <<"no">>, <<"da">>, <<"fi">>, <<"pl">>,
                         <<"tr">>, <<"he">>],
    lists:member(Language, SupportedLanguages).

%% @private
is_available_voice(Voice, Language) ->
    AvailableVoices = get_voices_for_language(Language),
    lists:any(fun(#{<<"id">> := VoiceId}) -> VoiceId =:= Voice end, AvailableVoices).

%% @private
get_voices_for_language(<<"en">>) ->
    [#{<<"id">> => <<"en-US-female-1">>, <<"name">> => <<"Emma">>, <<"gender">> => <<"female">>},
     #{<<"id">> => <<"en-US-male-1">>, <<"name">> => <<"James">>, <<"gender">> => <<"male">>},
     #{<<"id">> => <<"en-GB-female-1">>, <<"name">> => <<"Sophie">>, <<"gender">> => <<"female">>},
     #{<<"id">> => <<"en-AU-male-1">>, <<"name">> => <<"Oliver">>, <<"gender">> => <<"male">>}];
get_voices_for_language(<<"es">>) ->
    [#{<<"id">> => <<"es-ES-female-1">>, <<"name">> => <<"Carmen">>, <<"gender">> => <<"female">>},
     #{<<"id">> => <<"es-ES-male-1">>, <<"name">> => <<"Diego">>, <<"gender">> => <<"male">>},
     #{<<"id">> => <<"es-MX-female-1">>, <<"name">> => <<"Maria">>, <<"gender">> => <<"female">>}];
get_voices_for_language(<<"fr">>) ->
    [#{<<"id">> => <<"fr-FR-female-1">>, <<"name">> => <<"Celine">>, <<"gender">> => <<"female">>},
     #{<<"id">> => <<"fr-FR-male-1">>, <<"name">> => <<"Pierre">>, <<"gender">> => <<"male">>}];
get_voices_for_language(<<"de">>) ->
    [#{<<"id">> => <<"de-DE-female-1">>, <<"name">> => <<"Greta">>, <<"gender">> => <<"female">>},
     #{<<"id">> => <<"de-DE-male-1">>, <<"name">> => <<"Hans">>, <<"gender">> => <<"male">>}];
get_voices_for_language(_) ->
    [#{<<"id">> => <<"default-female">>, <<"name">> => <<"Default Female">>, <<"gender">> => <<"female">>},
     #{<<"id">> => <<"default-male">>, <<"name">> => <<"Default Male">>, <<"gender">> => <<"male">>}].

%% @private
get_available_voices_impl() ->
    Languages = [<<"en">>, <<"es">>, <<"fr">>, <<"de">>, <<"it">>, <<"pt">>, <<"ru">>, <<"ja">>],
    lists:foldl(fun(Lang, Acc) ->
        Voices = get_voices_for_language(Lang),
        VoicesWithLang = [Voice#{<<"language">> => Lang} || Voice <- Voices],
        Acc ++ VoicesWithLang
    end, [], Languages).

%% @private
get_supported_languages_impl() ->
    [
        #{<<"code">> => <<"en">>, <<"name">> => <<"English">>},
        #{<<"code">> => <<"es">>, <<"name">> => <<"Spanish">>},
        #{<<"code">> => <<"fr">>, <<"name">> => <<"French">>},
        #{<<"code">> => <<"de">>, <<"name">> => <<"German">>},
        #{<<"code">> => <<"it">>, <<"name">> => <<"Italian">>},
        #{<<"code">> => <<"pt">>, <<"name">> => <<"Portuguese">>},
        #{<<"code">> => <<"ru">>, <<"name">> => <<"Russian">>},
        #{<<"code">> => <<"ja">>, <<"name">> => <<"Japanese">>},
        #{<<"code">> => <<"ko">>, <<"name">> => <<"Korean">>},
        #{<<"code">> => <<"zh">>, <<"name">> => <<"Chinese">>},
        #{<<"code">> => <<"ar">>, <<"name">> => <<"Arabic">>},
        #{<<"code">> => <<"hi">>, <<"name">> => <<"Hindi">>}
    ].

%% @private
truncate_text(Text, MaxLength) when byte_size(Text) =< MaxLength ->
    Text;
truncate_text(Text, MaxLength) ->
    <<Truncated:MaxLength/binary, _/binary>> = Text,
    <<Truncated/binary, "...">>.

