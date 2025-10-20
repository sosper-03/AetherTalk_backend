%% @doc Maestra Speech-to-Text Service Integration
%% Provides real-time speech transcription using Maestra API
-module(aethertalk_maestra_stt).

-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([transcribe_audio/2, transcribe_audio/3]).
-export([start_streaming_transcription/3]).
-export([stream_audio_chunk/2]).
-export([end_streaming_transcription/1]).
-export([get_supported_languages/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(DEFAULT_TIMEOUT, 15000).
-define(AUDIO_CHUNK_SIZE, 4096).
-define(SUPPORTED_FORMATS, [<<"wav">>, <<"mp3">>, <<"m4a">>, <<"flac">>, <<"ogg">>]).

-record(state, {
    api_url :: binary(),
    http_options :: list(),
    streaming_sessions :: map()
}).

-record(streaming_session, {
    language :: binary(),
    callback_pid :: pid(),
    audio_buffer :: binary(),
    session_id :: binary(),
    created_at :: integer()
}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Starts the Maestra STT server
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Transcribe audio file or binary data
-spec transcribe_audio(binary(), binary()) -> {ok, binary()} | {error, term()}.
transcribe_audio(AudioData, Language) ->
    transcribe_audio(AudioData, Language, ?DEFAULT_TIMEOUT).

%% @doc Transcribe audio with custom timeout
-spec transcribe_audio(binary(), binary(), integer()) -> {ok, binary()} | {error, term()}.
transcribe_audio(AudioData, Language, Timeout) ->
    gen_server:call(?SERVER, {transcribe, AudioData, Language}, Timeout).

%% @doc Start streaming transcription session
-spec start_streaming_transcription(binary(), binary(), pid()) -> {ok, binary()} | {error, term()}.
start_streaming_transcription(SessionId, Language, CallbackPid) ->
    gen_server:call(?SERVER, {start_streaming, SessionId, Language, CallbackPid}).

%% @doc Stream audio chunk to transcription session
-spec stream_audio_chunk(binary(), binary()) -> ok.
stream_audio_chunk(SessionId, AudioChunk) ->
    gen_server:cast(?SERVER, {stream_audio, SessionId, AudioChunk}).

%% @doc End streaming transcription session
-spec end_streaming_transcription(binary()) -> ok.
end_streaming_transcription(SessionId) ->
    gen_server:cast(?SERVER, {end_streaming, SessionId}).

%% @doc Get supported languages
-spec get_supported_languages() -> {ok, list()} | {error, term()}.
get_supported_languages() ->
    gen_server:call(?SERVER, get_languages).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
init([]) ->
    ApiUrl = case os:getenv("MAESTRA_STT_URL") of
        false -> <<"https://api.maestra.ai/v1/stt">>;
        Url -> list_to_binary(Url)
    end,
    
    HttpOptions = [
        {timeout, 60000},
        {connect_timeout, 10000},
        {ssl, [{verify, verify_none}]}
    ],
    
    lager:info("Maestra STT service started with URL: ~s", [ApiUrl]),
    
    {ok, #state{
        api_url = ApiUrl,
        http_options = HttpOptions,
        streaming_sessions = #{}
    }}.

%% @private
handle_call({transcribe, AudioData, Language}, _From, State) ->
    Result = perform_transcription(AudioData, Language, State),
    {reply, Result, State};

handle_call({start_streaming, SessionId, Language, CallbackPid}, _From, State) ->
    Session = #streaming_session{
        language = Language,
        callback_pid = CallbackPid,
        audio_buffer = <<>>,
        session_id = SessionId,
        created_at = erlang:system_time(second)
    },
    
    NewSessions = maps:put(SessionId, Session, State#state.streaming_sessions),
    NewState = State#state{streaming_sessions = NewSessions},
    
    lager:info("Started streaming transcription session: ~s (language: ~s)", [SessionId, Language]),
    
    {reply, {ok, SessionId}, NewState};

handle_call(get_languages, _From, State) ->
    Languages = get_supported_languages_impl(),
    {reply, {ok, Languages}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({stream_audio, SessionId, AudioChunk}, State) ->
    case maps:get(SessionId, State#state.streaming_sessions, undefined) of
        undefined ->
            lager:warning("Streaming session not found: ~s", [SessionId]),
            {noreply, State};
        Session ->
            NewState = process_audio_chunk(SessionId, AudioChunk, Session, State),
            {noreply, NewState}
    end;

handle_cast({end_streaming, SessionId}, State) ->
    case maps:get(SessionId, State#state.streaming_sessions, undefined) of
        undefined ->
            {noreply, State};
        Session ->
            % Process any remaining audio buffer
            process_final_audio(SessionId, Session, State),
            NewSessions = maps:remove(SessionId, State#state.streaming_sessions),
            NewState = State#state{streaming_sessions = NewSessions},
            lager:info("Ended streaming transcription session: ~s", [SessionId]),
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
perform_transcription(AudioData, Language, _State) ->
    % For demo purposes, we'll simulate the Maestra API call
    % In a real implementation, you would make an HTTP request to Maestra
    
    case is_valid_audio_format(AudioData) of
        true ->
            % Simulate transcription based on audio characteristics
            TranscribedText = simulate_transcription(AudioData, Language),
            lager:info("Transcribed ~p bytes of audio to: ~s", [byte_size(AudioData), TranscribedText]),
            {ok, TranscribedText};
        false ->
            {error, unsupported_audio_format}
    end.

%% @private
process_audio_chunk(SessionId, AudioChunk, Session, State) ->
    Buffer = Session#streaming_session.audio_buffer,
    NewBuffer = <<Buffer/binary, AudioChunk/binary>>,
    
    % Check if we have enough audio data to transcribe
    if
        byte_size(NewBuffer) >= ?AUDIO_CHUNK_SIZE ->
            % Extract chunk for transcription
            <<ToTranscribe:?AUDIO_CHUNK_SIZE/binary, Remaining/binary>> = NewBuffer,
            
            % Perform transcription
            Language = Session#streaming_session.language,
            CallbackPid = Session#streaming_session.callback_pid,
            
            case perform_transcription(ToTranscribe, Language, State) of
                {ok, TranscribedText} ->
                    % Send transcribed text to callback
                    CallbackPid ! {transcription_chunk, SessionId, TranscribedText},
                    
                    % Update session with remaining buffer
                    UpdatedSession = Session#streaming_session{audio_buffer = Remaining},
                    NewSessions = maps:put(SessionId, UpdatedSession, State#state.streaming_sessions),
                    State#state{streaming_sessions = NewSessions};
                {error, Reason} ->
                    lager:error("Streaming transcription failed for session ~s: ~p", [SessionId, Reason]),
                    CallbackPid ! {transcription_error, SessionId, Reason},
                    State
            end;
        true ->
            % Buffer the audio chunk
            UpdatedSession = Session#streaming_session{audio_buffer = NewBuffer},
            NewSessions = maps:put(SessionId, UpdatedSession, State#state.streaming_sessions),
            State#state{streaming_sessions = NewSessions}
    end.

%% @private
process_final_audio(SessionId, Session, State) ->
    Buffer = Session#streaming_session.audio_buffer,
    
    if
        byte_size(Buffer) > 0 ->
            Language = Session#streaming_session.language,
            CallbackPid = Session#streaming_session.callback_pid,
            
            case perform_transcription(Buffer, Language, State) of
                {ok, TranscribedText} ->
                    CallbackPid ! {transcription_chunk, SessionId, TranscribedText},
                    CallbackPid ! {transcription_complete, SessionId};
                {error, Reason} ->
                    lager:error("Final audio transcription failed for session ~s: ~p", [SessionId, Reason]),
                    CallbackPid ! {transcription_error, SessionId, Reason}
            end;
        true ->
            CallbackPid = Session#streaming_session.callback_pid,
            CallbackPid ! {transcription_complete, SessionId}
    end.

%% @private
is_valid_audio_format(AudioData) when byte_size(AudioData) < 44 ->
    false; % Too small to be valid audio
is_valid_audio_format(AudioData) ->
    % Check for common audio file headers
    case AudioData of
        <<"RIFF", _:4/binary, "WAVE", _/binary>> -> true; % WAV
        <<255, 251, _/binary>> -> true; % MP3
        <<255, 243, _/binary>> -> true; % MP3
        <<"fLaC", _/binary>> -> true; % FLAC
        <<"OggS", _/binary>> -> true; % OGG
        <<_:4/binary, "ftyp", _/binary>> -> true; % M4A/MP4
        _ -> 
            % If no header match, assume it's raw audio data
            byte_size(AudioData) > 1000 % Minimum size for meaningful audio
    end.

%% @private
simulate_transcription(AudioData, Language) ->
    % This is a simulation for demo purposes
    % In real implementation, this would call the Maestra API
    
    AudioSize = byte_size(AudioData),
    
    % Generate sample transcription based on language and audio size
    case Language of
        <<"en">> -> 
            generate_english_sample(AudioSize);
        <<"es">> -> 
            generate_spanish_sample(AudioSize);
        <<"fr">> -> 
            generate_french_sample(AudioSize);
        <<"de">> -> 
            generate_german_sample(AudioSize);
        _ -> 
            generate_english_sample(AudioSize)
    end.

%% @private
generate_english_sample(AudioSize) when AudioSize < 2000 ->
    <<"Hello">>;
generate_english_sample(AudioSize) when AudioSize < 4000 ->
    <<"Hello, how are you?">>;
generate_english_sample(AudioSize) when AudioSize < 8000 ->
    <<"Hello, how are you doing today?">>;
generate_english_sample(_) ->
    <<"Hello, how are you doing today? I hope you're having a great time.">>.

%% @private
generate_spanish_sample(AudioSize) when AudioSize < 2000 ->
    <<"Hola">>;
generate_spanish_sample(AudioSize) when AudioSize < 4000 ->
    <<"Hola, ¿cómo estás?">>;
generate_spanish_sample(AudioSize) when AudioSize < 8000 ->
    <<"Hola, ¿cómo estás hoy?">>;
generate_spanish_sample(_) ->
    <<"Hola, ¿cómo estás hoy? Espero que tengas un buen día.">>.

%% @private
generate_french_sample(AudioSize) when AudioSize < 2000 ->
    <<"Bonjour">>;
generate_french_sample(AudioSize) when AudioSize < 4000 ->
    <<"Bonjour, comment allez-vous?">>;
generate_french_sample(AudioSize) when AudioSize < 8000 ->
    <<"Bonjour, comment allez-vous aujourd'hui?">>;
generate_french_sample(_) ->
    <<"Bonjour, comment allez-vous aujourd'hui? J'espère que vous passez une bonne journée.">>.

%% @private
generate_german_sample(AudioSize) when AudioSize < 2000 ->
    <<"Hallo">>;
generate_german_sample(AudioSize) when AudioSize < 4000 ->
    <<"Hallo, wie geht es dir?">>;
generate_german_sample(AudioSize) when AudioSize < 8000 ->
    <<"Hallo, wie geht es dir heute?">>;
generate_german_sample(_) ->
    <<"Hallo, wie geht es dir heute? Ich hoffe, du hast einen schönen Tag.">>.

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
        #{<<"code">> => <<"hi">>, <<"name">> => <<"Hindi">>},
        #{<<"code">> => <<"nl">>, <<"name">> => <<"Dutch">>},
        #{<<"code">> => <<"sv">>, <<"name">> => <<"Swedish">>},
        #{<<"code">> => <<"no">>, <<"name">> => <<"Norwegian">>},
        #{<<"code">> => <<"da">>, <<"name">> => <<"Danish">>},
        #{<<"code">> => <<"fi">>, <<"name">> => <<"Finnish">>},
        #{<<"code">> => <<"pl">>, <<"name">> => <<"Polish">>},
        #{<<"code">> => <<"tr">>, <<"name">> => <<"Turkish">>},
        #{<<"code">> => <<"he">>, <<"name">> => <<"Hebrew">>}
    ].