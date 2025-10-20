%%%-------------------------------------------------------------------
%% @doc AetherTalk media utilities
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_media).

-export([init_storage/0]).

-include("aethertalk.hrl").

init_storage() ->
    MediaPath = aethertalk_app:get_env(media_storage_path, "./media"),
    
    % Create media directories
    Directories = [
        MediaPath,
        filename:join(MediaPath, "images"),
        filename:join(MediaPath, "videos"),
        filename:join(MediaPath, "audio"),
        filename:join(MediaPath, "documents"),
        filename:join(MediaPath, "thumbnails"),
        filename:join(MediaPath, "temp")
    ],
    
    lists:foreach(fun(Dir) ->
        case filelib:ensure_dir(filename:join(Dir, "dummy")) of
            ok ->
                io:format("Created media directory: ~s~n", [Dir]);
            {error, Reason} ->
                io:format("Failed to create media directory ~s: ~p~n", [Dir, Reason])
        end
    end, Directories),
    
    ok.