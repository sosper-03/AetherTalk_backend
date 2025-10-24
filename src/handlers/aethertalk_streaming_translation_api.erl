%% @doc Streaming Translation API Handlers
%% Provides REST API endpoints for real-time translation features
-module(aethertalk_streaming_translation_api).

-export([init/2]).

%% Cowboy handler callbacks
init(Req, State) ->
    Method = cowboy_req:method(Req),
    Path = cowboy_req:path(Req),
    
    try
        Response = handle_request(Method, Path, Req),
        {ok, Response, State}
    catch
        Error:Reason ->
            lager:error("Streaming translation API error: ~p:~p", [Error, Reason]),
            ErrorResp = cowboy_req:reply(500, 
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"internal_server_error">>}),
                Req),
            {ok, ErrorResp, State}
    end.

%% Handle different API endpoints
handle_request(<<"POST">>, <<"/api/v1/translation/streaming/start">>, Req) ->
    handle_start_streaming_translation(Req);

handle_request(<<"POST">>, Path, Req) when byte_size(Path) > 40 ->
    case binary:match(Path, <<"/api/v1/translation/streaming/">>) of
        {0, _} ->
            % Extract session ID from path
            PathSuffix = binary:part(Path, 34, byte_size(Path) - 34),
            case binary:split(PathSuffix, <<"/">>) of
                [SessionId, <<"audio">>] ->
                    handle_stream_audio(SessionId, Req);
                [SessionId, <<"end">>] ->
                    handle_end_streaming_translation(SessionId, Req);
                _ ->
                    handle_unknown_request(<<"POST">>, Path, Req)
            end;
        nomatch ->
            handle_unknown_request(<<"POST">>, Path, Req)
    end;

handle_request(<<"GET">>, <<"/api/v1/translation/settings">>, Req) ->
    handle_get_translation_settings(Req);

handle_request(<<"PUT">>, <<"/api/v1/translation/settings">>, Req) ->
    handle_update_translation_settings(Req);

handle_request(<<"GET">>, <<"/api/v1/translation/languages">>, Req) ->
    handle_get_supported_languages(Req);

handle_request(<<"GET">>, <<"/api/v1/translation/voices">>, Req) ->
    handle_get_available_voices(Req);

handle_request(<<"POST">>, <<"/api/v1/translation/text">>, Req) ->
    handle_translate_text(Req);

handle_request(<<"POST">>, <<"/api/v1/translation/detect-language">>, Req) ->
    handle_detect_language(Req);

handle_request(Method, Path, Req) ->
    handle_unknown_request(Method, Path, Req).

%% @private
handle_unknown_request(Method, Path, Req) ->
    lager:warning("Unhandled streaming translation API request: ~s ~s", [Method, Path]),
    cowboy_req:reply(404, 
        #{<<"content-type">> => <<"application/json">>},
        jsx:encode(#{error => <<"endpoint_not_found">>}),
        Req).

%%%===================================================================
%%% Streaming Translation Handlers
%%%===================================================================

%% @private
handle_start_streaming_translation(Req) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, UserId} ->
            case get_json_body(Req) of
                {ok, #{<<"source_language">> := SourceLang, 
                       <<"target_language">> := TargetLang}} ->
                    
                    Voice = maps:get(<<"voice">>, get_json_body_result(Req), <<"en-US-female-1">>),
                    
                    % Start streaming translation session
                    case aethertalk_streaming_translation:start_translation_session(
                            UserId, SourceLang, TargetLang, Voice, self()) of
                        {ok, SessionId} ->
                            cowboy_req:reply(200,
                                #{<<"content-type">> => <<"application/json">>},
                                jsx:encode(#{
                                    success => true,
                                    session_id => SessionId,
                                    message => <<"Streaming translation session started">>
                                }),
                                Req);
                        {error, translation_disabled} ->
                            cowboy_req:reply(400,
                                #{<<"content-type">> => <<"application/json">>},
                                jsx:encode(#{error => <<"Translation is disabled for this user">>}),
                                Req);
                        {error, Reason} ->
                            lager:error("Failed to start streaming translation: ~p", [Reason]),
                            cowboy_req:reply(500,
                                #{<<"content-type">> => <<"application/json">>},
                                jsx:encode(#{error => <<"Failed to start translation session">>}),
                                Req)
                    end;
                {ok, _} ->
                    cowboy_req:reply(400,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"Missing source_language or target_language">>}),
                        Req);
                {error, _} ->
                    cowboy_req:reply(400,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"Invalid JSON body">>}),
                        Req)
            end;
        {error, _} ->
            cowboy_req:reply(401,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Authentication required">>}),
                Req)
    end.

%% @private
handle_stream_audio(SessionId, Req) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, _UserId} ->
            case cowboy_req:has_body(Req) of
                true ->
                    {ok, AudioData, _} = cowboy_req:read_body(Req),
                    
                    % Stream audio chunk to translation session
                    aethertalk_streaming_translation:stream_audio_chunk(SessionId, AudioData),
                    
                    cowboy_req:reply(200,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{
                            success => true,
                            message => <<"Audio chunk processed">>
                        }),
                        Req);
                false ->
                    cowboy_req:reply(400,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"No audio data provided">>}),
                        Req)
            end;
        {error, _} ->
            cowboy_req:reply(401,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Authentication required">>}),
                Req)
    end.

%% @private
handle_end_streaming_translation(SessionId, Req) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, _UserId} ->
            aethertalk_streaming_translation:end_translation_session(SessionId),
            
            cowboy_req:reply(200,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{
                    success => true,
                    message => <<"Translation session ended">>
                }),
                Req);
        {error, _} ->
            cowboy_req:reply(401,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Authentication required">>}),
                Req)
    end.

%%%===================================================================
%%% Settings Handlers
%%%===================================================================

%% @private
handle_get_translation_settings(Req) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, UserId} ->
            case aethertalk_streaming_translation:get_user_translation_settings(UserId) of
                {ok, Settings} ->
                    cowboy_req:reply(200,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{
                            success => true,
                            settings => Settings
                        }),
                        Req);
                {error, Reason} ->
                    lager:error("Failed to get translation settings: ~p", [Reason]),
                    cowboy_req:reply(500,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"Failed to get settings">>}),
                        Req)
            end;
        {error, _} ->
            cowboy_req:reply(401,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Authentication required">>}),
                Req)
    end.

%% @private
handle_update_translation_settings(Req) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, UserId} ->
            case get_json_body(Req) of
                {ok, Settings} ->
                    case aethertalk_streaming_translation:update_user_translation_settings(UserId, Settings) of
                        ok ->
                            cowboy_req:reply(200,
                                #{<<"content-type">> => <<"application/json">>},
                                jsx:encode(#{
                                    success => true,
                                    message => <<"Translation settings updated">>
                                }),
                                Req);
                        {error, Reason} ->
                            lager:error("Failed to update translation settings: ~p", [Reason]),
                            cowboy_req:reply(500,
                                #{<<"content-type">> => <<"application/json">>},
                                jsx:encode(#{error => <<"Failed to update settings">>}),
                                Req)
                    end;
                {error, _} ->
                    cowboy_req:reply(400,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"Invalid JSON body">>}),
                        Req)
            end;
        {error, _} ->
            cowboy_req:reply(401,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Authentication required">>}),
                Req)
    end.

%%%===================================================================
%%% Information Handlers
%%%===================================================================

%% @private
handle_get_supported_languages(Req) ->
    case aethertalk_streaming_translation:get_supported_languages() of
        {ok, Languages} ->
            cowboy_req:reply(200,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{
                    success => true,
                    languages => Languages
                }),
                Req);
        {error, Reason} ->
            lager:error("Failed to get supported languages: ~p", [Reason]),
            cowboy_req:reply(500,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Failed to get languages">>}),
                Req)
    end.

%% @private
handle_get_available_voices(Req) ->
    case aethertalk_streaming_translation:get_available_voices() of
        {ok, Voices} ->
            cowboy_req:reply(200,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{
                    success => true,
                    voices => Voices
                }),
                Req);
        {error, Reason} ->
            lager:error("Failed to get available voices: ~p", [Reason]),
            cowboy_req:reply(500,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Failed to get voices">>}),
                Req)
    end.

%%%===================================================================
%%% Direct Translation Handlers
%%%===================================================================

%% @private
handle_translate_text(Req) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, _UserId} ->
            case get_json_body(Req) of
                {ok, #{<<"text">> := Text, 
                       <<"source_language">> := SourceLang, 
                       <<"target_language">> := TargetLang}} ->
                    
                    case aethertalk_lecto_ai:translate_text(Text, SourceLang, TargetLang) of
                        {ok, TranslatedText} ->
                            cowboy_req:reply(200,
                                #{<<"content-type">> => <<"application/json">>},
                                jsx:encode(#{
                                    success => true,
                                    translated_text => TranslatedText,
                                    source_language => SourceLang,
                                    target_language => TargetLang
                                }),
                                Req);
                        {error, Reason} ->
                            lager:error("Text translation failed: ~p", [Reason]),
                            cowboy_req:reply(500,
                                #{<<"content-type">> => <<"application/json">>},
                                jsx:encode(#{error => <<"Translation failed">>}),
                                Req)
                    end;
                {ok, _} ->
                    cowboy_req:reply(400,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"Missing required fields: text, source_language, target_language">>}),
                        Req);
                {error, _} ->
                    cowboy_req:reply(400,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"Invalid JSON body">>}),
                        Req)
            end;
        {error, _} ->
            cowboy_req:reply(401,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Authentication required">>}),
                Req)
    end.

%% @private
handle_detect_language(Req) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, _UserId} ->
            case get_json_body(Req) of
                {ok, #{<<"text">> := Text}} ->
                    case aethertalk_lecto_ai:detect_language(Text) of
                        {ok, Language} ->
                            cowboy_req:reply(200,
                                #{<<"content-type">> => <<"application/json">>},
                                jsx:encode(#{
                                    success => true,
                                    detected_language => Language
                                }),
                                Req);
                        {error, Reason} ->
                            lager:error("Language detection failed: ~p", [Reason]),
                            cowboy_req:reply(500,
                                #{<<"content-type">> => <<"application/json">>},
                                jsx:encode(#{error => <<"Language detection failed">>}),
                                Req)
                    end;
                {ok, _} ->
                    cowboy_req:reply(400,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"Missing text field">>}),
                        Req);
                {error, _} ->
                    cowboy_req:reply(400,
                        #{<<"content-type">> => <<"application/json">>},
                        jsx:encode(#{error => <<"Invalid JSON body">>}),
                        Req)
            end;
        {error, _} ->
            cowboy_req:reply(401,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(#{error => <<"Authentication required">>}),
                Req)
    end.

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @private
get_json_body(Req) ->
    case cowboy_req:has_body(Req) of
        true ->
            {ok, Body, _} = cowboy_req:read_body(Req),
            try
                {ok, jsx:decode(Body, [return_maps])}
            catch
                _:_ -> {error, invalid_json}
            end;
        false ->
            {error, no_body}
    end.

%% @private
get_json_body_result(Req) ->
    case get_json_body(Req) of
        {ok, Body} -> Body;
        {error, _} -> #{}
    end.