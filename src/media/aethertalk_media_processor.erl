%%%-------------------------------------------------------------------
%% @doc AetherTalk media processing service
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_media_processor).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    process_image/2,
    process_video/2,
    process_audio/2,
    generate_thumbnail/2,
    get_media_info/1,
    delete_media/1
]).

-include("aethertalk.hrl").

-record(state, {}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    io:format("Media processor started~n"),
    {ok, #state{}}.

handle_call({process_image, FilePath, Options}, _From, State) ->
    Result = do_process_image(FilePath, Options),
    {reply, Result, State};

handle_call({process_video, FilePath, Options}, _From, State) ->
    Result = do_process_video(FilePath, Options),
    {reply, Result, State};

handle_call({process_audio, FilePath, Options}, _From, State) ->
    Result = do_process_audio(FilePath, Options),
    {reply, Result, State};

handle_call({generate_thumbnail, FilePath, Options}, _From, State) ->
    Result = do_generate_thumbnail(FilePath, Options),
    {reply, Result, State};

handle_call({get_media_info, FilePath}, _From, State) ->
    Result = do_get_media_info(FilePath),
    {reply, Result, State};

handle_call({delete_media, MediaId}, _From, State) ->
    Result = do_delete_media(MediaId),
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

process_image(FilePath, Options) ->
    gen_server:call(?MODULE, {process_image, FilePath, Options}).

process_video(FilePath, Options) ->
    gen_server:call(?MODULE, {process_video, FilePath, Options}).

process_audio(FilePath, Options) ->
    gen_server:call(?MODULE, {process_audio, FilePath, Options}).

generate_thumbnail(FilePath, Options) ->
    gen_server:call(?MODULE, {generate_thumbnail, FilePath, Options}).

get_media_info(FilePath) ->
    gen_server:call(?MODULE, {get_media_info, FilePath}).

delete_media(MediaId) ->
    gen_server:call(?MODULE, {delete_media, MediaId}).

%% Internal functions

do_process_image(FilePath, Options) ->
    % Basic image processing implementation
    try
        MaxWidth = maps:get(max_width, Options, ?IMAGE_MAX_WIDTH),
        MaxHeight = maps:get(max_height, Options, ?IMAGE_MAX_HEIGHT),
        _Quality = maps:get(quality, Options, 85),
        
        % This is a placeholder - in production you'd use ImageMagick or similar
        ProcessedPath = FilePath ++ ".processed",
        
        % Simulate processing
        timer:sleep(100),
        
        {ok, #{
            original_path => FilePath,
            processed_path => ProcessedPath,
            width => MaxWidth,
            height => MaxHeight,
            file_size => 1024000, % Placeholder
            format => <<"jpeg">>
        }}
    catch
        _:Error ->
            io:format("Image processing failed: ~p~n", [Error]),
            {error, processing_failed}
    end.

do_process_video(FilePath, Options) ->
    % Basic video processing implementation
    try
        MaxDuration = maps:get(max_duration, Options, ?VIDEO_MAX_DURATION),
        _Quality = maps:get(quality, Options, <<"medium">>),
        
        % This is a placeholder - in production you'd use FFmpeg
        ProcessedPath = FilePath ++ ".processed.mp4",
        
        % Simulate processing
        timer:sleep(1000),
        
        {ok, #{
            original_path => FilePath,
            processed_path => ProcessedPath,
            duration => MaxDuration,
            width => 1280,
            height => 720,
            file_size => 5120000, % Placeholder
            format => <<"mp4">>,
            bitrate => 1000000
        }}
    catch
        _:Error ->
            io:format("Video processing failed: ~p~n", [Error]),
            {error, processing_failed}
    end.

do_process_audio(FilePath, Options) ->
    % Basic audio processing implementation
    try
        MaxDuration = maps:get(max_duration, Options, ?AUDIO_MAX_DURATION),
        _Quality = maps:get(quality, Options, <<"medium">>),
        
        % This is a placeholder - in production you'd use FFmpeg
        ProcessedPath = FilePath ++ ".processed.mp3",
        
        % Simulate processing
        timer:sleep(500),
        
        {ok, #{
            original_path => FilePath,
            processed_path => ProcessedPath,
            duration => MaxDuration,
            file_size => 2048000, % Placeholder
            format => <<"mp3">>,
            bitrate => 128000,
            sample_rate => 44100
        }}
    catch
        _:Error ->
            io:format("Audio processing failed: ~p~n", [Error]),
            {error, processing_failed}
    end.

do_generate_thumbnail(FilePath, Options) ->
    % Generate thumbnail for images or videos
    try
        Size = maps:get(size, Options, ?THUMBNAIL_SIZE),
        
        % This is a placeholder
        ThumbnailPath = FilePath ++ ".thumb.jpg",
        
        % Simulate thumbnail generation
        timer:sleep(200),
        
        {ok, #{
            original_path => FilePath,
            thumbnail_path => ThumbnailPath,
            width => Size,
            height => Size,
            file_size => 10240 % Placeholder
        }}
    catch
        _:Error ->
            io:format("Thumbnail generation failed: ~p~n", [Error]),
            {error, thumbnail_failed}
    end.

do_get_media_info(FilePath) ->
    % Get media file information
    try
        case file:read_file_info(FilePath) of
            {ok, FileInfo} ->
                Size = element(2, FileInfo),
                ModTime = element(6, FileInfo),
                
                % Detect file type based on extension
                Extension = filename:extension(FilePath),
                MimeType = get_mime_type(Extension),
                
                {ok, #{
                    file_path => FilePath,
                    file_size => Size,
                    mime_type => MimeType,
                    modified_time => ModTime
                }};
            {error, Reason} ->
                {error, Reason}
        end
    catch
        _:Error ->
            io:format("Failed to get media info: ~p~n", [Error]),
            {error, info_failed}
    end.

do_delete_media(MediaId) ->
    % Delete media file and database record
    SQL = "SELECT file_path, thumbnail_path FROM media WHERE id = $1",
    case aethertalk_db:query(SQL, [MediaId]) of
        {ok, {_Columns, [{FilePath, ThumbnailPath}]}} ->
            % Delete files
            file:delete(FilePath),
            case ThumbnailPath of
                null -> ok;
                _ -> file:delete(ThumbnailPath)
            end,
            
            % Delete database record
            DeleteSQL = "DELETE FROM media WHERE id = $1",
            case aethertalk_db:query(DeleteSQL, [MediaId]) of
                {ok, 1} ->
                    ok;
                {error, Reason} ->
                    {error, Reason}
            end;
        {ok, {_Columns, []}} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

%% Helper functions

get_mime_type(Extension) ->
    case string:to_lower(Extension) of
        ".jpg" -> <<"image/jpeg">>;
        ".jpeg" -> <<"image/jpeg">>;
        ".png" -> <<"image/png">>;
        ".gif" -> <<"image/gif">>;
        ".webp" -> <<"image/webp">>;
        ".mp4" -> <<"video/mp4">>;
        ".avi" -> <<"video/avi">>;
        ".mov" -> <<"video/quicktime">>;
        ".webm" -> <<"video/webm">>;
        ".mp3" -> <<"audio/mpeg">>;
        ".wav" -> <<"audio/wav">>;
        ".ogg" -> <<"audio/ogg">>;
        ".m4a" -> <<"audio/mp4">>;
        ".pdf" -> <<"application/pdf">>;
        ".doc" -> <<"application/msword">>;
        ".docx" -> <<"application/vnd.openxmlformats-officedocument.wordprocessingml.document">>;
        _ -> <<"application/octet-stream">>
    end.