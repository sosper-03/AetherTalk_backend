%%%-------------------------------------------------------------------
%%% @doc
%%% Translation Service for AetherTalk
%%% Provides real-time translation for messages and voice/video calls
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_translation_service).
-behaviour(gen_server).

% OTP callbacks
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    translate_text/3,
    translate_message/4,
    detect_language/1,
    get_supported_languages/0,
    enable_auto_translate/3,
    disable_auto_translate/2,
    get_translation_settings/2,
    translate_voice/4,
    get_translation_stats/1,
    batch_translate/3,
    cache_translation/4,
    get_cached_translation/3
]).

-include("aethertalk.hrl").

-record(state, {
    translation_cache :: ets:tid(),
    api_keys :: #{atom() => string()},
    providers :: [atom()],
    default_provider :: atom(),
    cache_ttl :: integer(),
    stats :: #{atom() => integer()}
}).

-record(translation_result, {
    original_text :: binary(),
    translated_text :: binary(),
    source_lang :: binary(),
    target_lang :: binary(),
    confidence :: float(),
    provider :: atom(),
    cached_at :: integer()
}).

-define(CACHE_TTL, 3600). % 1 hour
-define(MAX_TEXT_LENGTH, 5000).
-define(SUPPORTED_PROVIDERS, [google, azure, aws, libre]).

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Translate text from source language to target language
translate_text(Text, SourceLang, TargetLang) ->
    gen_server:call(?MODULE, {translate_text, Text, SourceLang, TargetLang}).

%% @doc Translate a message and store the translation
translate_message(MessageId, Text, SourceLang, TargetLang) ->
    gen_server:call(?MODULE, {translate_message, MessageId, Text, SourceLang, TargetLang}).

%% @doc Detect the language of given text
detect_language(Text) ->
    gen_server:call(?MODULE, {detect_language, Text}).

%% @doc Get list of supported languages
get_supported_languages() ->
    gen_server:call(?MODULE, get_supported_languages).

%% @doc Enable auto-translation for a user in a chat
enable_auto_translate(UserId, ChatId, TargetLang) ->
    gen_server:call(?MODULE, {enable_auto_translate, UserId, ChatId, TargetLang}).

%% @doc Disable auto-translation for a user in a chat
disable_auto_translate(UserId, ChatId) ->
    gen_server:call(?MODULE, {disable_auto_translate, UserId, ChatId}).

%% @doc Get translation settings for a user in a chat
get_translation_settings(UserId, ChatId) ->
    gen_server:call(?MODULE, {get_translation_settings, UserId, ChatId}).

%% @doc Translate voice/audio content
translate_voice(AudioData, SourceLang, TargetLang, Format) ->
    gen_server:call(?MODULE, {translate_voice, AudioData, SourceLang, TargetLang, Format}).

%% @doc Get translation statistics for a user
get_translation_stats(UserId) ->
    gen_server:call(?MODULE, {get_translation_stats, UserId}).

%% @doc Translate multiple texts in batch
batch_translate(Texts, SourceLang, TargetLang) ->
    gen_server:call(?MODULE, {batch_translate, Texts, SourceLang, TargetLang}).

%% @doc Cache a translation result
cache_translation(Text, SourceLang, TargetLang, Translation) ->
    gen_server:cast(?MODULE, {cache_translation, Text, SourceLang, TargetLang, Translation}).

%% @doc Get cached translation if available
get_cached_translation(Text, SourceLang, TargetLang) ->
    gen_server:call(?MODULE, {get_cached_translation, Text, SourceLang, TargetLang}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    % Create ETS table for translation cache
    TranslationCache = ets:new(translation_cache, [set, protected, named_table]),
    
    % Load API keys from configuration
    ApiKeys = load_api_keys(),
    
    % Determine available providers
    Providers = get_available_providers(ApiKeys),
    DefaultProvider = get_default_provider(Providers),
    
    % Start cache cleanup timer
    timer:send_interval(300000, cleanup_cache), % Every 5 minutes
    
    io:format("Translation service started with providers: ~p~n", [Providers]),
    {ok, #state{
        translation_cache = TranslationCache,
        api_keys = ApiKeys,
        providers = Providers,
        default_provider = DefaultProvider,
        cache_ttl = ?CACHE_TTL,
        stats = #{
            translations_requested => 0,
            translations_cached => 0,
            cache_hits => 0,
            cache_misses => 0
        }
    }}.

handle_call({translate_text, Text, SourceLang, TargetLang}, _From, State) ->
    Result = do_translate_text(Text, SourceLang, TargetLang, State),
    NewStats = increment_stat(translations_requested, State#state.stats),
    NewState = State#state{stats = NewStats},
    {reply, Result, NewState};

handle_call({translate_message, MessageId, Text, SourceLang, TargetLang}, _From, State) ->
    Result = do_translate_message(MessageId, Text, SourceLang, TargetLang, State),
    NewStats = increment_stat(translations_requested, State#state.stats),
    NewState = State#state{stats = NewStats},
    {reply, Result, NewState};

handle_call({detect_language, Text}, _From, State) ->
    Result = do_detect_language(Text, State),
    {reply, Result, State};

handle_call(get_supported_languages, _From, State) ->
    Languages = get_supported_languages_list(),
    {reply, {ok, Languages}, State};

handle_call({enable_auto_translate, UserId, ChatId, TargetLang}, _From, State) ->
    Result = do_enable_auto_translate(UserId, ChatId, TargetLang),
    {reply, Result, State};

handle_call({disable_auto_translate, UserId, ChatId}, _From, State) ->
    Result = do_disable_auto_translate(UserId, ChatId),
    {reply, Result, State};

handle_call({get_translation_settings, UserId, ChatId}, _From, State) ->
    Result = do_get_translation_settings(UserId, ChatId),
    {reply, Result, State};

handle_call({translate_voice, AudioData, SourceLang, TargetLang, Format}, _From, State) ->
    Result = do_translate_voice(AudioData, SourceLang, TargetLang, Format, State),
    {reply, Result, State};

handle_call({get_translation_stats, UserId}, _From, State) ->
    Result = do_get_translation_stats(UserId),
    {reply, Result, State};

handle_call({batch_translate, Texts, SourceLang, TargetLang}, _From, State) ->
    Result = do_batch_translate(Texts, SourceLang, TargetLang, State),
    NewStats = increment_stat(translations_requested, State#state.stats, length(Texts)),
    NewState = State#state{stats = NewStats},
    {reply, Result, NewState};

handle_call({get_cached_translation, Text, SourceLang, TargetLang}, _From, State) ->
    Result = do_get_cached_translation(Text, SourceLang, TargetLang, State),
    {NewStats, CacheResult} = case Result of
        {ok, Translation} ->
            {increment_stat(cache_hits, State#state.stats), {ok, Translation}};
        {error, not_found} ->
            {increment_stat(cache_misses, State#state.stats), {error, not_found}}
    end,
    NewState = State#state{stats = NewStats},
    {reply, CacheResult, NewState};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({cache_translation, Text, SourceLang, TargetLang, Translation}, State) ->
    do_cache_translation(Text, SourceLang, TargetLang, Translation, State),
    NewStats = increment_stat(translations_cached, State#state.stats),
    NewState = State#state{stats = NewStats},
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(cleanup_cache, State) ->
    do_cleanup_cache(State),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

do_translate_text(Text, SourceLang, TargetLang, State) ->
    % Validate input
    case validate_translation_request(Text, SourceLang, TargetLang) of
        ok ->
            % Check cache first
            case do_get_cached_translation(Text, SourceLang, TargetLang, State) of
                {ok, CachedResult} ->
                    io:format("Cache hit for translation: ~s -> ~s~n", [SourceLang, TargetLang]),
                    {ok, CachedResult};
                {error, not_found} ->
                    % Perform actual translation
                    case perform_translation(Text, SourceLang, TargetLang, State) of
                        {ok, Translation} ->
                            % Cache the result
                            do_cache_translation(Text, SourceLang, TargetLang, Translation, State),
                            {ok, Translation};
                        Error ->
                            Error
                    end
            end;
        Error ->
            Error
    end.

do_translate_message(MessageId, Text, SourceLang, TargetLang, State) ->
    case do_translate_text(Text, SourceLang, TargetLang, State) of
        {ok, Translation} ->
            % Store translation in database
            case store_message_translation(MessageId, Translation, SourceLang, TargetLang) of
                ok ->
                    io:format("Stored translation for message ~s: ~s -> ~s~n", 
                              [MessageId, SourceLang, TargetLang]),
                    {ok, Translation};
                {error, Reason} ->
                    io:format("Failed to store message translation: ~p~n", [Reason]),
                    % Still return the translation even if storage failed
                    {ok, Translation}
            end;
        Error ->
            Error
    end.

do_detect_language(Text, State) ->
    case validate_text_input(Text) of
        ok ->
            case detect_language_with_provider(Text, State#state.default_provider, State) of
                {ok, Language, Confidence} ->
                    {ok, #{language => Language, confidence => Confidence}};
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

do_enable_auto_translate(UserId, ChatId, TargetLang) ->
    SQL = "INSERT INTO user_translation_settings (user_id, chat_id, target_language, auto_translate, created_at) 
           VALUES ($1, $2, $3, TRUE, NOW()) 
           ON CONFLICT (user_id, chat_id) 
           DO UPDATE SET target_language = $3, auto_translate = TRUE, updated_at = NOW()",
    
    case aethertalk_db:query(SQL, [UserId, ChatId, TargetLang]) of
        {ok, _} ->
            io:format("Enabled auto-translate for user ~s in chat ~s to ~s~n", 
                      [UserId, ChatId, TargetLang]),
            ok;
        {error, Reason} ->
            io:format("Failed to enable auto-translate: ~p~n", [Reason]),
            {error, database_error}
    end.

do_disable_auto_translate(UserId, ChatId) ->
    SQL = "UPDATE user_translation_settings 
           SET auto_translate = FALSE, updated_at = NOW() 
           WHERE user_id = $1 AND chat_id = $2",
    
    case aethertalk_db:query(SQL, [UserId, ChatId]) of
        {ok, _} ->
            io:format("Disabled auto-translate for user ~s in chat ~s~n", [UserId, ChatId]),
            ok;
        {error, Reason} ->
            io:format("Failed to disable auto-translate: ~p~n", [Reason]),
            {error, database_error}
    end.

do_get_translation_settings(UserId, ChatId) ->
    SQL = "SELECT target_language, auto_translate, created_at, updated_at 
           FROM user_translation_settings 
           WHERE user_id = $1 AND chat_id = $2",
    
    case aethertalk_db:query(SQL, [UserId, ChatId]) of
        {ok, {_Columns, [{TargetLang, AutoTranslate, CreatedAt, UpdatedAt}]}} ->
            Settings = #{
                target_language => TargetLang,
                auto_translate => AutoTranslate,
                created_at => CreatedAt,
                updated_at => UpdatedAt
            },
            {ok, Settings};
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            io:format("Failed to get translation settings: ~p~n", [Reason]),
            {error, database_error}
    end.

do_translate_voice(AudioData, SourceLang, TargetLang, Format, State) ->
    % This would integrate with speech-to-text, translation, and text-to-speech services
    case validate_audio_input(AudioData, Format) of
        ok ->
            % Step 1: Convert speech to text
            case speech_to_text(AudioData, SourceLang, Format) of
                {ok, SourceText} ->
                    % Step 2: Translate the text
                    case do_translate_text(SourceText, SourceLang, TargetLang, State) of
                        {ok, TranslatedText} ->
                            % Step 3: Convert translated text to speech
                            case text_to_speech(TranslatedText, TargetLang) of
                                {ok, TranslatedAudio} ->
                                    {ok, #{
                                        original_text => SourceText,
                                        translated_text => TranslatedText,
                                        translated_audio => TranslatedAudio,
                                        source_lang => SourceLang,
                                        target_lang => TargetLang
                                    }};
                                Error ->
                                    Error
                            end;
                        Error ->
                            Error
                    end;
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

do_get_translation_stats(UserId) ->
    SQL = "SELECT 
               COUNT(*) as total_translations,
               COUNT(DISTINCT source_language) as source_languages,
               COUNT(DISTINCT target_language) as target_languages,
               MIN(created_at) as first_translation,
               MAX(created_at) as last_translation
           FROM message_translations mt
           JOIN messages m ON mt.message_id = m.id
           WHERE m.sender_id = $1",
    
    case aethertalk_db:query(SQL, [UserId]) of
        {ok, {_Columns, [{Total, SourceLangs, TargetLangs, FirstTranslation, LastTranslation}]}} ->
            Stats = #{
                total_translations => Total,
                source_languages_used => SourceLangs,
                target_languages_used => TargetLangs,
                first_translation => FirstTranslation,
                last_translation => LastTranslation
            },
            {ok, Stats};
        {error, Reason} ->
            io:format("Failed to get translation stats: ~p~n", [Reason]),
            {error, database_error}
    end.

do_batch_translate(Texts, SourceLang, TargetLang, State) ->
    % Translate multiple texts efficiently
    Results = lists:map(fun(Text) ->
        case do_translate_text(Text, SourceLang, TargetLang, State) of
            {ok, Translation} -> {ok, Translation};
            Error -> Error
        end
    end, Texts),
    
    % Check if all translations succeeded
    case lists:all(fun({ok, _}) -> true; (_) -> false end, Results) of
        true ->
            Translations = [T || {ok, T} <- Results],
            {ok, Translations};
        false ->
            % Return partial results with errors
            {partial, Results}
    end.

do_get_cached_translation(Text, SourceLang, TargetLang, State) ->
    CacheKey = generate_cache_key(Text, SourceLang, TargetLang),
    
    case ets:lookup(State#state.translation_cache, CacheKey) of
        [{CacheKey, Translation, CachedAt}] ->
            Now = erlang:system_time(second),
            if
                Now - CachedAt < State#state.cache_ttl ->
                    {ok, Translation};
                true ->
                    % Cache expired
                    ets:delete(State#state.translation_cache, CacheKey),
                    {error, not_found}
            end;
        [] ->
            {error, not_found}
    end.

do_cache_translation(Text, SourceLang, TargetLang, Translation, State) ->
    CacheKey = generate_cache_key(Text, SourceLang, TargetLang),
    Now = erlang:system_time(second),
    
    TranslationResult = #translation_result{
        original_text = Text,
        translated_text = Translation,
        source_lang = SourceLang,
        target_lang = TargetLang,
        confidence = 1.0,
        provider = State#state.default_provider,
        cached_at = Now
    },
    
    ets:insert(State#state.translation_cache, {CacheKey, TranslationResult, Now}),
    io:format("Cached translation: ~s -> ~s~n", [SourceLang, TargetLang]).

do_cleanup_cache(State) ->
    Now = erlang:system_time(second),
    TTL = State#state.cache_ttl,
    
    % Get all cache entries
    AllEntries = ets:tab2list(State#state.translation_cache),
    
    % Remove expired entries
    ExpiredCount = lists:foldl(fun({CacheKey, _Translation, CachedAt}, Count) ->
        if
            Now - CachedAt >= TTL ->
                ets:delete(State#state.translation_cache, CacheKey),
                Count + 1;
            true ->
                Count
        end
    end, 0, AllEntries),
    
    if
        ExpiredCount > 0 ->
            io:format("Cleaned up ~p expired translation cache entries~n", [ExpiredCount]);
        true ->
            ok
    end.

%% Translation provider functions

perform_translation(Text, SourceLang, TargetLang, State) ->
    Provider = State#state.default_provider,
    
    case Provider of
        google -> translate_with_google(Text, SourceLang, TargetLang, State);
        azure -> translate_with_azure(Text, SourceLang, TargetLang, State);
        aws -> translate_with_aws(Text, SourceLang, TargetLang, State);
        libre -> translate_with_libre(Text, SourceLang, TargetLang, State);
        _ -> {error, unsupported_provider}
    end.

translate_with_libre(Text, SourceLang, TargetLang, _State) ->
    % LibreTranslate (open source) API call - simplified implementation
    case {SourceLang, TargetLang} of
        {Same, Same} ->
            {ok, Text};
        _ ->
            % Simulate translation for now
            TranslatedText = <<"[Translated from ", SourceLang/binary, " to ", TargetLang/binary, "]: ", Text/binary>>,
            {ok, TranslatedText}
    end.

translate_with_google(_Text, _SourceLang, _TargetLang, _State) ->
    {error, not_implemented}.

translate_with_azure(_Text, _SourceLang, _TargetLang, _State) ->
    {error, not_implemented}.

translate_with_aws(_Text, _SourceLang, _TargetLang, _State) ->
    {error, not_implemented}.

detect_language_with_provider(Text, Provider, _State) ->
    case Provider of
        libre -> detect_language_simple(Text);
        _ -> {error, unsupported_provider}
    end.

detect_language_simple(Text) ->
    % Simple language detection based on common words
    case binary:match(Text, [<<"hello">>, <<"the">>, <<"and">>, <<"is">>, <<"are">>]) of
        nomatch -> 
            case binary:match(Text, [<<"hola">>, <<"el">>, <<"la">>, <<"es">>, <<"son">>]) of
                nomatch -> {ok, <<"unknown">>, 0.5};
                _ -> {ok, <<"es">>, 0.7}
            end;
        _ -> {ok, <<"en">>, 0.8}
    end.

%% Voice translation functions (placeholder implementations)

speech_to_text(AudioData, Language, Format) ->
    % This would integrate with speech recognition services
    io:format("Converting speech to text: ~p bytes, ~s, ~s~n", [byte_size(AudioData), Language, Format]),
    {ok, <<"Hello, this is a placeholder text from speech recognition.">>}.

text_to_speech(Text, Language) ->
    % This would integrate with text-to-speech services
    io:format("Converting text to speech: ~s, ~s~n", [Text, Language]),
    {ok, <<"placeholder_audio_data">>}.

%% Validation functions

validate_translation_request(Text, SourceLang, TargetLang) ->
    case validate_text_input(Text) of
        ok ->
            case validate_language_codes([SourceLang, TargetLang]) of
                ok -> ok;
                Error -> Error
            end;
        Error -> Error
    end.

validate_text_input(Text) when is_binary(Text) ->
    case byte_size(Text) of
        0 -> {error, empty_text};
        Size when Size > ?MAX_TEXT_LENGTH -> {error, text_too_long};
        _ -> ok
    end;
validate_text_input(_) ->
    {error, invalid_text_format}.

validate_language_codes(Languages) ->
    SupportedLangs = get_supported_language_codes(),
    case lists:all(fun(Lang) -> lists:member(Lang, SupportedLangs) end, Languages) of
        true -> ok;
        false -> {error, unsupported_language}
    end.

validate_audio_input(AudioData, Format) when is_binary(AudioData) ->
    SupportedFormats = [<<"wav">>, <<"mp3">>, <<"ogg">>, <<"webm">>],
    case lists:member(Format, SupportedFormats) of
        true -> ok;
        false -> {error, unsupported_audio_format}
    end;
validate_audio_input(_, _) ->
    {error, invalid_audio_data}.

%% Helper functions

generate_cache_key(Text, SourceLang, TargetLang) ->
    Data = <<Text/binary, SourceLang/binary, TargetLang/binary>>,
    crypto:hash(sha256, Data).

increment_stat(StatName, Stats) ->
    increment_stat(StatName, Stats, 1).

increment_stat(StatName, Stats, Increment) ->
    CurrentValue = maps:get(StatName, Stats, 0),
    maps:put(StatName, CurrentValue + Increment, Stats).

load_api_keys() ->
    % Load API keys from configuration or environment variables
    #{
        google => os:getenv("GOOGLE_TRANSLATE_API_KEY", ""),
        azure => os:getenv("AZURE_TRANSLATOR_API_KEY", ""),
        aws => os:getenv("AWS_TRANSLATE_API_KEY", ""),
        libre => "" % LibreTranslate doesn't require API key for public instance
    }.

get_available_providers(ApiKeys) ->
    lists:filter(fun(Provider) ->
        case Provider of
            libre -> true; % Always available
            _ -> 
                Key = maps:get(Provider, ApiKeys, ""),
                Key =/= ""
        end
    end, ?SUPPORTED_PROVIDERS).

get_default_provider(Providers) ->
    case Providers of
        [] -> libre; % Fallback to LibreTranslate
        [First | _] -> First
    end.

get_supported_languages_list() ->
    % Common language codes supported by most translation services
    [
        #{code => <<"en">>, name => <<"English">>},
        #{code => <<"es">>, name => <<"Spanish">>},
        #{code => <<"fr">>, name => <<"French">>},
        #{code => <<"de">>, name => <<"German">>},
        #{code => <<"it">>, name => <<"Italian">>},
        #{code => <<"pt">>, name => <<"Portuguese">>},
        #{code => <<"ru">>, name => <<"Russian">>},
        #{code => <<"ja">>, name => <<"Japanese">>},
        #{code => <<"ko">>, name => <<"Korean">>},
        #{code => <<"zh">>, name => <<"Chinese">>},
        #{code => <<"ar">>, name => <<"Arabic">>},
        #{code => <<"hi">>, name => <<"Hindi">>}
    ].

get_supported_language_codes() ->
    [Code || #{code := Code} <- get_supported_languages_list()].

%% Database operations

store_message_translation(MessageId, Translation, SourceLang, TargetLang) ->
    SQL = "INSERT INTO message_translations (message_id, translated_text, source_language, target_language, created_at) 
           VALUES ($1, $2, $3, $4, NOW())",
    
    case aethertalk_db:query(SQL, [MessageId, Translation, SourceLang, TargetLang]) of
        {ok, _} -> ok;
        {error, Reason} -> {error, Reason}
    end.