%% @doc Cloud storage manager for AetherTalk
%% Provides unified interface for multiple cloud storage providers
-module(aethertalk_cloud_storage).

-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([upload_file/3, download_file/2, delete_file/2]).
-export([list_files/1, get_file_info/2, get_download_url/2]).
-export([get_storage_stats/0, switch_provider/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
    current_provider :: atom(),
    providers = [] :: list(),
    config :: map()
}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Starts the cloud storage manager
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Upload a file to cloud storage
-spec upload_file(binary(), binary(), binary()) -> {ok, binary()} | {error, term()}.
upload_file(FileName, FileData, FolderPath) ->
    gen_server:call(?SERVER, {upload_file, FileName, FileData, FolderPath}, 60000).

%% @doc Download a file from cloud storage
-spec download_file(binary(), binary()) -> {ok, binary()} | {error, term()}.
download_file(FileId, LocalPath) ->
    gen_server:call(?SERVER, {download_file, FileId, LocalPath}, 60000).

%% @doc Delete a file from cloud storage
-spec delete_file(binary(), binary()) -> ok | {error, term()}.
delete_file(FileId, FolderPath) ->
    gen_server:call(?SERVER, {delete_file, FileId, FolderPath}, 30000).

%% @doc List files in a folder
-spec list_files(binary()) -> {ok, list()} | {error, term()}.
list_files(FolderPath) ->
    gen_server:call(?SERVER, {list_files, FolderPath}, 30000).

%% @doc Get file information
-spec get_file_info(binary(), binary()) -> {ok, map()} | {error, term()}.
get_file_info(FileId, FolderPath) ->
    gen_server:call(?SERVER, {get_file_info, FileId, FolderPath}, 30000).

%% @doc Get download URL for a file
-spec get_download_url(binary(), binary()) -> {ok, binary()} | {error, term()}.
get_download_url(FileId, FolderPath) ->
    gen_server:call(?SERVER, {get_download_url, FileId, FolderPath}, 30000).

%% @doc Get storage statistics
-spec get_storage_stats() -> {ok, map()} | {error, term()}.
get_storage_stats() ->
    gen_server:call(?SERVER, get_storage_stats, 30000).

%% @doc Switch storage provider
-spec switch_provider(atom()) -> ok | {error, term()}.
switch_provider(Provider) ->
    gen_server:call(?SERVER, {switch_provider, Provider}, 30000).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    % Load configuration
    Config = load_config(),
    CurrentProvider = maps:get(current_provider, Config, mega),
    
    % Initialize available providers
    Providers = initialize_providers(Config),
    
    lager:info("Cloud storage manager initialized with provider: ~p", [CurrentProvider]),
    
    {ok, #state{
        current_provider = CurrentProvider,
        providers = Providers,
        config = Config
    }}.

handle_call({upload_file, FileName, FileData, FolderPath}, _From, State) ->
    Result = do_upload_file(FileName, FileData, FolderPath, State),
    {reply, Result, State};

handle_call({download_file, FileId, LocalPath}, _From, State) ->
    Result = do_download_file(FileId, LocalPath, State),
    {reply, Result, State};

handle_call({delete_file, FileId, FolderPath}, _From, State) ->
    Result = do_delete_file(FileId, FolderPath, State),
    {reply, Result, State};

handle_call({list_files, FolderPath}, _From, State) ->
    Result = do_list_files(FolderPath, State),
    {reply, Result, State};

handle_call({get_file_info, FileId, FolderPath}, _From, State) ->
    Result = do_get_file_info(FileId, FolderPath, State),
    {reply, Result, State};

handle_call({get_download_url, FileId, FolderPath}, _From, State) ->
    Result = do_get_download_url(FileId, FolderPath, State),
    {reply, Result, State};

handle_call(get_storage_stats, _From, State) ->
    Result = do_get_storage_stats(State),
    {reply, Result, State};

handle_call({switch_provider, Provider}, _From, State) ->
    case lists:member(Provider, State#state.providers) of
        true ->
            NewState = State#state{current_provider = Provider},
            lager:info("Switched storage provider to: ~p", [Provider]),
            {reply, ok, NewState};
        false ->
            {reply, {error, {provider_not_available, Provider}}, State}
    end;

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

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @private
load_config() ->
    StorageType = get_env_var("MEDIA_STORAGE_TYPE", "mega"),
    
    Config = #{
        current_provider => list_to_atom(StorageType),
        mega => #{
            username => get_env_var("MEGA_USERNAME", undefined),
            password => get_env_var("MEGA_PASSWORD", undefined)
        },
        google_drive => #{
            client_id => get_env_var("GOOGLE_DRIVE_CLIENT_ID", undefined),
            client_secret => get_env_var("GOOGLE_DRIVE_CLIENT_SECRET", undefined),
            refresh_token => get_env_var("GOOGLE_DRIVE_REFRESH_TOKEN", undefined)
        },
        onedrive => #{
            client_id => get_env_var("ONEDRIVE_CLIENT_ID", undefined),
            client_secret => get_env_var("ONEDRIVE_CLIENT_SECRET", undefined),
            refresh_token => get_env_var("ONEDRIVE_REFRESH_TOKEN", undefined)
        }
    },
    
    lager:info("Loaded cloud storage configuration for provider: ~s", [StorageType]),
    Config.

%% @private
get_env_var(VarName, Default) ->
    case os:getenv(VarName) of
        false -> Default;
        Value -> Value
    end.

%% @private
initialize_providers(Config) ->
    AvailableProviders = [],
    
    % Check MEGA
    MegaConfig = maps:get(mega, Config),
    MegaProviders = case {maps:get(username, MegaConfig), maps:get(password, MegaConfig)} of
        {undefined, _} -> [];
        {_, undefined} -> [];
        {_, _} -> [mega]
    end,
    
    % Check Google Drive
    GDriveConfig = maps:get(google_drive, Config),
    GDriveProviders = case {maps:get(client_id, GDriveConfig), maps:get(client_secret, GDriveConfig)} of
        {undefined, _} -> [];
        {_, undefined} -> [];
        {_, _} -> [google_drive]
    end,
    
    % Check OneDrive
    OneDriveConfig = maps:get(onedrive, Config),
    OneDriveProviders = case {maps:get(client_id, OneDriveConfig), maps:get(client_secret, OneDriveConfig)} of
        {undefined, _} -> [];
        {_, undefined} -> [];
        {_, _} -> [onedrive]
    end,
    
    AllProviders = AvailableProviders ++ MegaProviders ++ GDriveProviders ++ OneDriveProviders,
    lager:info("Available storage providers: ~p", [AllProviders]),
    AllProviders.

%% @private
do_upload_file(FileName, FileData, FolderPath, State) ->
    Provider = State#state.current_provider,
    
    case Provider of
        mega ->
            case whereis(aethertalk_mega_storage) of
                undefined ->
                    {error, mega_storage_not_available};
                _Pid ->
                    aethertalk_mega_storage:upload_file(FileName, FileData, FolderPath)
            end;
        google_drive ->
            do_google_drive_upload(FileName, FileData, FolderPath, State);
        onedrive ->
            do_onedrive_upload(FileName, FileData, FolderPath, State);
        _ ->
            {error, {unsupported_provider, Provider}}
    end.

%% @private
do_download_file(FileId, LocalPath, State) ->
    Provider = State#state.current_provider,
    
    case Provider of
        mega ->
            case whereis(aethertalk_mega_storage) of
                undefined ->
                    {error, mega_storage_not_available};
                _Pid ->
                    aethertalk_mega_storage:download_file(FileId, LocalPath)
            end;
        google_drive ->
            do_google_drive_download(FileId, LocalPath, State);
        onedrive ->
            do_onedrive_download(FileId, LocalPath, State);
        _ ->
            {error, {unsupported_provider, Provider}}
    end.

%% @private
do_delete_file(FileId, FolderPath, State) ->
    Provider = State#state.current_provider,
    
    case Provider of
        mega ->
            case whereis(aethertalk_mega_storage) of
                undefined ->
                    {error, mega_storage_not_available};
                _Pid ->
                    aethertalk_mega_storage:delete_file(FileId, FolderPath)
            end;
        google_drive ->
            do_google_drive_delete(FileId, FolderPath, State);
        onedrive ->
            do_onedrive_delete(FileId, FolderPath, State);
        _ ->
            {error, {unsupported_provider, Provider}}
    end.

%% @private
do_list_files(FolderPath, State) ->
    Provider = State#state.current_provider,
    
    case Provider of
        mega ->
            case whereis(aethertalk_mega_storage) of
                undefined ->
                    {error, mega_storage_not_available};
                _Pid ->
                    aethertalk_mega_storage:list_files(FolderPath)
            end;
        google_drive ->
            do_google_drive_list(FolderPath, State);
        onedrive ->
            do_onedrive_list(FolderPath, State);
        _ ->
            {error, {unsupported_provider, Provider}}
    end.

%% @private
do_get_file_info(FileId, FolderPath, State) ->
    Provider = State#state.current_provider,
    
    case Provider of
        mega ->
            case whereis(aethertalk_mega_storage) of
                undefined ->
                    {error, mega_storage_not_available};
                _Pid ->
                    aethertalk_mega_storage:get_file_info(FileId, FolderPath)
            end;
        google_drive ->
            do_google_drive_file_info(FileId, FolderPath, State);
        onedrive ->
            do_onedrive_file_info(FileId, FolderPath, State);
        _ ->
            {error, {unsupported_provider, Provider}}
    end.

%% @private
do_get_download_url(FileId, FolderPath, State) ->
    Provider = State#state.current_provider,
    
    case Provider of
        mega ->
            case whereis(aethertalk_mega_storage) of
                undefined ->
                    {error, mega_storage_not_available};
                _Pid ->
                    aethertalk_mega_storage:get_download_url(FileId, FolderPath)
            end;
        google_drive ->
            do_google_drive_download_url(FileId, FolderPath, State);
        onedrive ->
            do_onedrive_download_url(FileId, FolderPath, State);
        _ ->
            {error, {unsupported_provider, Provider}}
    end.

%% @private
do_get_storage_stats(State) ->
    Provider = State#state.current_provider,
    
    Stats = #{
        current_provider => Provider,
        available_providers => State#state.providers,
        total_files => 0,
        total_size => 0,
        last_sync => erlang:system_time(second)
    },
    
    {ok, Stats}.

%% Placeholder functions for Google Drive integration
%% @private
do_google_drive_upload(FileName, _FileData, FolderPath, _State) ->
    lager:info("Google Drive upload: ~s to ~s", [FileName, FolderPath]),
    {ok, <<"gdrive_", FileName/binary>>}.

%% @private
do_google_drive_download(FileId, LocalPath, _State) ->
    lager:info("Google Drive download: ~s to ~s", [FileId, LocalPath]),
    {ok, <<"Google Drive file content">>}.

%% @private
do_google_drive_delete(FileId, FolderPath, _State) ->
    lager:info("Google Drive delete: ~s from ~s", [FileId, FolderPath]),
    ok.

%% @private
do_google_drive_list(FolderPath, _State) ->
    lager:info("Google Drive list: ~s", [FolderPath]),
    {ok, []}.

%% @private
do_google_drive_file_info(FileId, FolderPath, _State) ->
    lager:info("Google Drive file info: ~s in ~s", [FileId, FolderPath]),
    {ok, #{id => FileId, name => <<"gdrive_file.txt">>, size => 1024}}.

%% @private
do_google_drive_download_url(FileId, FolderPath, _State) ->
    lager:info("Google Drive download URL: ~s in ~s", [FileId, FolderPath]),
    {ok, <<"https://drive.google.com/file/d/", FileId/binary>>}.

%% Placeholder functions for OneDrive integration
%% @private
do_onedrive_upload(FileName, _FileData, FolderPath, _State) ->
    lager:info("OneDrive upload: ~s to ~s", [FileName, FolderPath]),
    {ok, <<"onedrive_", FileName/binary>>}.

%% @private
do_onedrive_download(FileId, LocalPath, _State) ->
    lager:info("OneDrive download: ~s to ~s", [FileId, LocalPath]),
    {ok, <<"OneDrive file content">>}.

%% @private
do_onedrive_delete(FileId, FolderPath, _State) ->
    lager:info("OneDrive delete: ~s from ~s", [FileId, FolderPath]),
    ok.

%% @private
do_onedrive_list(FolderPath, _State) ->
    lager:info("OneDrive list: ~s", [FolderPath]),
    {ok, []}.

%% @private
do_onedrive_file_info(FileId, FolderPath, _State) ->
    lager:info("OneDrive file info: ~s in ~s", [FileId, FolderPath]),
    {ok, #{id => FileId, name => <<"onedrive_file.txt">>, size => 1024}}.

%% @private
do_onedrive_download_url(FileId, FolderPath, _State) ->
    lager:info("OneDrive download URL: ~s in ~s", [FileId, FolderPath]),
    {ok, <<"https://onedrive.live.com/download?cid=", FileId/binary>>}.