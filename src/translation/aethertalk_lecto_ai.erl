%% @doc Lecto AI Translation Service Integration
%% Provides real-time text translation using Lecto AI API
-module(aethertalk_lecto_ai).

-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([translate_text/3, translate_text/4]).
-export([translate_streaming/4]).
-export([get_supported_languages/0]).
-export([detect_language/1]).
-export([stream_text_chunk/2, end_streaming_session/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(DEFAULT_TIMEOUT, 10000).
-define(STREAMING_CHUNK_SIZE, 512).

-record(state, {
    api_key :: binary(),
    base_url :: binary(),
    http_options :: list(),
    streaming_sessions :: map()
}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Starts the Lecto AI translation server
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Translate text from source language to target language
-spec translate_text(binary(), binary(), binary()) -> 
    {ok, binary()} | {error, term()}.
translate_text(Text, SourceLang, TargetLang) ->
    translate_text(Text, SourceLang, TargetLang, ?DEFAULT_TIMEOUT).

%% @doc Translate text with custom timeout
-spec translate_text(binary(), binary(), binary(), integer()) -> 
    {ok, binary()} | {error, term()}.
translate_text(Text, SourceLang, TargetLang, Timeout) ->
    gen_server:call(?SERVER, {translate, Text, SourceLang, TargetLang}, Timeout).

%% @doc Start streaming translation session
-spec translate_streaming(binary(), binary(), binary(), pid()) -> 
    {ok, binary()} | {error, term()}.
translate_streaming(SessionId, SourceLang, TargetLang, CallbackPid) ->
    gen_server:call(?SERVER, {start_streaming, SessionId, SourceLang, TargetLang, CallbackPid}).

%% @doc Get list of supported languages
-spec get_supported_languages() -> {ok, list()} | {error, term()}.
get_supported_languages() ->
    gen_server:call(?SERVER, get_languages).

%% @doc Detect language of given text
-spec detect_language(binary()) -> {ok, binary()} | {error, term()}.
detect_language(Text) ->
    gen_server:call(?SERVER, {detect_language, Text}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
init([]) ->
    ApiKey = case os:getenv("LECTO_AI_API_KEY") of
        false -> <<"JAKBSJP-A2WMV50-N43CNV1-2F8X8EV">>;
        Key -> list_to_binary(Key)
    end,
    
    BaseUrl = case os:getenv("LECTO_AI_BASE_URL") of
        false -> <<"https://api.lecto.ai/v1">>;
        Url -> list_to_binary(Url)
    end,
    
    HttpOptions = [
        {timeout, 30000},
        {connect_timeout, 10000},
        {ssl, [{verify, verify_none}]}
    ],
    
    lager:info("Lecto AI translation service started with API key: ~s", [mask_api_key(ApiKey)]),
    
    {ok, #state{
        api_key = ApiKey,
        base_url = BaseUrl,
        http_options = HttpOptions,
        streaming_sessions = #{}
    }}.

%% @private
handle_call({translate, Text, SourceLang, TargetLang}, _From, State) ->
    Result = perform_translation(Text, SourceLang, TargetLang, State),
    {reply, Result, State};

handle_call({start_streaming, SessionId, SourceLang, TargetLang, CallbackPid}, _From, State) ->
    StreamingSession = #{
        source_lang => SourceLang,
        target_lang => TargetLang,
        callback_pid => CallbackPid,
        buffer => <<>>,
        created_at => erlang:system_time(second)
    },
    
    NewSessions = maps:put(SessionId, StreamingSession, State#state.streaming_sessions),
    NewState = State#state{streaming_sessions = NewSessions},
    
    lager:info("Started streaming translation session: ~s (~s -> ~s)", 
               [SessionId, SourceLang, TargetLang]),
    
    {reply, {ok, SessionId}, NewState};

handle_call(get_languages, _From, State) ->
    Result = get_supported_languages_impl(State),
    {reply, Result, State};

handle_call({detect_language, Text}, _From, State) ->
    Result = detect_language_impl(Text, State),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({stream_text, SessionId, TextChunk}, State) ->
    case maps:get(SessionId, State#state.streaming_sessions, undefined) of
        undefined ->
            lager:warning("Streaming session not found: ~s", [SessionId]),
            {noreply, State};
        Session ->
            NewState = process_streaming_chunk(SessionId, TextChunk, Session, State),
            {noreply, NewState}
    end;

handle_cast({end_streaming, SessionId}, State) ->
    case maps:get(SessionId, State#state.streaming_sessions, undefined) of
        undefined ->
            {noreply, State};
        Session ->
            % Process any remaining buffer
            process_final_chunk(SessionId, Session, State),
            NewSessions = maps:remove(SessionId, State#state.streaming_sessions),
            NewState = State#state{streaming_sessions = NewSessions},
            lager:info("Ended streaming translation session: ~s", [SessionId]),
            {noreply, NewState}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({stream_chunk, SessionId, TextChunk}, State) ->
    gen_server:cast(?SERVER, {stream_text, SessionId, TextChunk}),
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
perform_translation(Text, SourceLang, TargetLang, State) ->
    Url = <<(State#state.base_url)/binary, "/translate">>,
    
    RequestBody = jsx:encode(#{
        <<"text">> => Text,
        <<"source">> => normalize_language_code(SourceLang),
        <<"target">> => normalize_language_code(TargetLang),
        <<"format">> => <<"text">>
    }),
    
    Headers = [
        {"Content-Type", "application/json"},
        {"Authorization", "Bearer " ++ binary_to_list(State#state.api_key)},
        {"User-Agent", "AetherTalk/1.0"}
    ],
    
    case httpc:request(post, {binary_to_list(Url), Headers, "application/json", RequestBody}, 
                      State#state.http_options, []) of
        {ok, {{_, 200, _}, _ResponseHeaders, ResponseBody}} ->
            try
                Response = jsx:decode(list_to_binary(ResponseBody), [return_maps]),
                case maps:get(<<"translation">>, Response, undefined) of
                    undefined ->
                        % Try alternative response format
                        case maps:get(<<"translated_text">>, Response, undefined) of
                            undefined ->
                                lager:error("No translation found in response: ~p", [Response]),
                                {error, no_translation_found};
                            TranslatedText ->
                                {ok, TranslatedText}
                        end;
                    TranslatedText ->
                        {ok, TranslatedText}
                end
            catch
                Error:Reason ->
                    lager:error("Failed to parse translation response: ~p:~p", [Error, Reason]),
                    {error, parse_error}
            end;
        {ok, {{_, StatusCode, _}, _ResponseHeaders, ResponseBody}} ->
            lager:error("Translation API error ~p: ~s", [StatusCode, ResponseBody]),
            {error, {api_error, StatusCode, ResponseBody}};
        {error, Reason} ->
            lager:error("Translation request failed: ~p", [Reason]),
            {error, {request_failed, Reason}}
    end.

%% @private
process_streaming_chunk(SessionId, TextChunk, Session, State) ->
    Buffer = maps:get(buffer, Session),
    NewBuffer = <<Buffer/binary, TextChunk/binary>>,
    
    % Check if we have enough text to translate
    if
        byte_size(NewBuffer) >= ?STREAMING_CHUNK_SIZE ->
            % Find a good break point (sentence end, word boundary, etc.)
            {ToTranslate, Remaining} = find_translation_boundary(NewBuffer),
            
            % Perform translation
            SourceLang = maps:get(source_lang, Session),
            TargetLang = maps:get(target_lang, Session),
            CallbackPid = maps:get(callback_pid, Session),
            
            case perform_translation(ToTranslate, SourceLang, TargetLang, State) of
                {ok, TranslatedText} ->
                    % Send translated chunk to callback
                    CallbackPid ! {translation_chunk, SessionId, TranslatedText},
                    
                    % Update session with remaining buffer
                    UpdatedSession = Session#{buffer => Remaining},
                    NewSessions = maps:put(SessionId, UpdatedSession, State#state.streaming_sessions),
                    State#state{streaming_sessions = NewSessions};
                {error, Reason} ->
                    lager:error("Streaming translation failed for session ~s: ~p", [SessionId, Reason]),
                    CallbackPid ! {translation_error, SessionId, Reason},
                    State
            end;
        true ->
            % Buffer the chunk
            UpdatedSession = Session#{buffer => NewBuffer},
            NewSessions = maps:put(SessionId, UpdatedSession, State#state.streaming_sessions),
            State#state{streaming_sessions = NewSessions}
    end.

%% @private
process_final_chunk(SessionId, Session, State) ->
    Buffer = maps:get(buffer, Session),
    
    if
        byte_size(Buffer) > 0 ->
            SourceLang = maps:get(source_lang, Session),
            TargetLang = maps:get(target_lang, Session),
            CallbackPid = maps:get(callback_pid, Session),
            
            case perform_translation(Buffer, SourceLang, TargetLang, State) of
                {ok, TranslatedText} ->
                    CallbackPid ! {translation_chunk, SessionId, TranslatedText},
                    CallbackPid ! {translation_complete, SessionId};
                {error, Reason} ->
                    lager:error("Final chunk translation failed for session ~s: ~p", [SessionId, Reason]),
                    CallbackPid ! {translation_error, SessionId, Reason}
            end;
        true ->
            CallbackPid = maps:get(callback_pid, Session),
            CallbackPid ! {translation_complete, SessionId}
    end.

%% @private
find_translation_boundary(Buffer) ->
    % Try to find sentence boundaries first
    case binary:matches(Buffer, [<<". ">>, <<"! ">>, <<"? ">>]) of
        [] ->
            % No sentence boundary, try word boundary
            case binary:last(Buffer) of
                $\s ->
                    {Buffer, <<>>};
                _ ->
                    % Find last space
                    case binary:match(Buffer, <<" ">>, [{scope, {byte_size(Buffer) - 100, 100}}]) of
                        {Pos, _} ->
                            <<ToTranslate:Pos/binary, Remaining/binary>> = Buffer,
                            {ToTranslate, Remaining};
                        nomatch ->
                            % No good boundary, split at chunk size
                            Size = min(byte_size(Buffer), ?STREAMING_CHUNK_SIZE),
                            <<ToTranslate:Size/binary, Remaining/binary>> = Buffer,
                            {ToTranslate, Remaining}
                    end
            end;
        Matches ->
            % Use the last sentence boundary
            {Pos, Len} = lists:last(Matches),
            SplitPos = Pos + Len,
            <<ToTranslate:SplitPos/binary, Remaining/binary>> = Buffer,
            {ToTranslate, Remaining}
    end.

%% @private
get_supported_languages_impl(State) ->
    Url = <<(State#state.base_url)/binary, "/languages">>,
    
    Headers = [
        {"Authorization", "Bearer " ++ binary_to_list(State#state.api_key)},
        {"User-Agent", "AetherTalk/1.0"}
    ],
    
    case httpc:request(get, {binary_to_list(Url), Headers}, State#state.http_options, []) of
        {ok, {{_, 200, _}, _ResponseHeaders, ResponseBody}} ->
            try
                Response = jsx:decode(list_to_binary(ResponseBody), [return_maps]),
                Languages = maps:get(<<"languages">>, Response, []),
                {ok, Languages}
            catch
                Error:Reason ->
                    lager:error("Failed to parse languages response: ~p:~p", [Error, Reason]),
                    {error, parse_error}
            end;
        {ok, {{_, StatusCode, _}, _ResponseHeaders, ResponseBody}} ->
            lager:error("Languages API error ~p: ~s", [StatusCode, ResponseBody]),
            {error, {api_error, StatusCode}};
        {error, Reason} ->
            lager:error("Languages request failed: ~p", [Reason]),
            {error, {request_failed, Reason}}
    end.

%% @private
detect_language_impl(Text, State) ->
    Url = <<(State#state.base_url)/binary, "/detect">>,
    
    RequestBody = jsx:encode(#{
        <<"text">> => Text
    }),
    
    Headers = [
        {"Content-Type", "application/json"},
        {"Authorization", "Bearer " ++ binary_to_list(State#state.api_key)},
        {"User-Agent", "AetherTalk/1.0"}
    ],
    
    case httpc:request(post, {binary_to_list(Url), Headers, "application/json", RequestBody}, 
                      State#state.http_options, []) of
        {ok, {{_, 200, _}, _ResponseHeaders, ResponseBody}} ->
            try
                Response = jsx:decode(list_to_binary(ResponseBody), [return_maps]),
                Language = maps:get(<<"language">>, Response, <<"unknown">>),
                {ok, Language}
            catch
                Error:Reason ->
                    lager:error("Failed to parse detection response: ~p:~p", [Error, Reason]),
                    {error, parse_error}
            end;
        {ok, {{_, StatusCode, _}, _ResponseHeaders, ResponseBody}} ->
            lager:error("Detection API error ~p: ~s", [StatusCode, ResponseBody]),
            {error, {api_error, StatusCode}};
        {error, Reason} ->
            lager:error("Detection request failed: ~p", [Reason]),
            {error, {request_failed, Reason}}
    end.

%% @private
normalize_language_code(<<"auto">>) -> <<"auto">>;
normalize_language_code(<<"en">>) -> <<"en">>;
normalize_language_code(<<"es">>) -> <<"es">>;
normalize_language_code(<<"fr">>) -> <<"fr">>;
normalize_language_code(<<"de">>) -> <<"de">>;
normalize_language_code(<<"it">>) -> <<"it">>;
normalize_language_code(<<"pt">>) -> <<"pt">>;
normalize_language_code(<<"ru">>) -> <<"ru">>;
normalize_language_code(<<"ja">>) -> <<"ja">>;
normalize_language_code(<<"ko">>) -> <<"ko">>;
normalize_language_code(<<"zh">>) -> <<"zh">>;
normalize_language_code(<<"ar">>) -> <<"ar">>;
normalize_language_code(<<"hi">>) -> <<"hi">>;
normalize_language_code(Other) -> Other.

%% @private
mask_api_key(ApiKey) when byte_size(ApiKey) > 8 ->
    <<Prefix:4/binary, _:4/binary, Suffix/binary>> = ApiKey,
    <<Prefix/binary, "****", Suffix/binary>>;
mask_api_key(_ApiKey) ->
    <<"****">>.

%%%===================================================================
%%% Public API for streaming
%%%===================================================================

%% @doc Send text chunk to streaming session
-spec stream_text_chunk(binary(), binary()) -> ok.
stream_text_chunk(SessionId, TextChunk) ->
    gen_server:cast(?SERVER, {stream_text, SessionId, TextChunk}).

%% @doc End streaming session
-spec end_streaming_session(binary()) -> ok.
end_streaming_session(SessionId) ->
    gen_server:cast(?SERVER, {end_streaming, SessionId}).

