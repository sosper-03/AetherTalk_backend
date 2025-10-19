%%%-------------------------------------------------------------------
%% @doc AetherTalk translation service
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_translation_service).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    translate_text/3,
    detect_language/1,
    get_supported_languages/0,
    translate_message/2
]).

-include("aethertalk.hrl").

-record(state, {}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    lager:info("Translation service started"),
    {ok, #state{}}.

handle_call({translate_text, Text, FromLang, ToLang}, _From, State) ->
    Result = do_translate_text(Text, FromLang, ToLang),
    {reply, Result, State};

handle_call({detect_language, Text}, _From, State) ->
    Result = do_detect_language(Text),
    {reply, Result, State};

handle_call(get_supported_languages, _From, State) ->
    Result = do_get_supported_languages(),
    {reply, Result, State};

handle_call({translate_message, MessageId, ToLang}, _From, State) ->
    Result = do_translate_message(MessageId, ToLang),
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

translate_text(Text, FromLang, ToLang) ->
    gen_server:call(?MODULE, {translate_text, Text, FromLang, ToLang}).

detect_language(Text) ->
    gen_server:call(?MODULE, {detect_language, Text}).

get_supported_languages() ->
    gen_server:call(?MODULE, get_supported_languages).

translate_message(MessageId, ToLang) ->
    gen_server:call(?MODULE, {translate_message, MessageId, ToLang}).

%% Internal functions (stubs for now)

do_translate_text(Text, FromLang, ToLang) ->
    % This is a stub - in production you'd integrate with Google Translate, 
    % Azure Translator, or similar service
    case {FromLang, ToLang} of
        {Same, Same} ->
            {ok, #{
                original_text => Text,
                translated_text => Text,
                from_language => FromLang,
                to_language => ToLang,
                confidence => 1.0
            }};
        _ ->
            % Simulate translation
            TranslatedText = <<"[Translated: ", Text/binary, "]">>,
            {ok, #{
                original_text => Text,
                translated_text => TranslatedText,
                from_language => FromLang,
                to_language => ToLang,
                confidence => 0.95
            }}
    end.

do_detect_language(Text) ->
    % This is a stub - in production you'd use language detection service
    case byte_size(Text) of
        Size when Size > 0 ->
            % Simple heuristic based on common words
            DetectedLang = case binary:match(Text, [<<"hello">>, <<"the">>, <<"and">>]) of
                nomatch -> <<"unknown">>;
                _ -> <<"en">>
            end,
            {ok, #{
                language => DetectedLang,
                confidence => 0.8
            }};
        _ ->
            {error, empty_text}
    end.

do_get_supported_languages() ->
    {ok, ?SUPPORTED_LANGUAGES}.

do_translate_message(MessageId, ToLang) ->
    % Get message content
    SQL = "SELECT content FROM messages WHERE id = $1 AND message_type = 'text'",
    case aethertalk_db:query(SQL, [MessageId]) of
        {ok, {_Columns, [{Content}]}} ->
            % Detect source language
            case do_detect_language(Content) of
                {ok, #{language := FromLang}} ->
                    % Translate text
                    do_translate_text(Content, FromLang, ToLang);
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, {_Columns, []}} ->
            {error, message_not_found};
        {error, Reason} ->
            {error, Reason}
    end.