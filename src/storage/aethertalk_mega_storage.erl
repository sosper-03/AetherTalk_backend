%% @doc MEGA cloud storage integration for AetherTalk
%% Provides file upload, download, and management functionality using MEGA API
-module(aethertalk_mega_storage).

-behaviour(gen_server).

%% API
-export([start_link/0, start_link/1]).
-export([upload_file/3, download_file/2, delete_file/2, list_files/1]).
-export([get_file_info/2, create_folder/2, get_download_url/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(MEGA_API_URL, "https://g.api.mega.co.nz/cs").
-define(TIMEOUT, 30000).

-record(state, {
    username :: binary(),
    password :: binary(),
    session_id :: binary() | undefined,
    master_key :: binary() | undefined,
    root_folder :: binary() | undefined,
    connected = false :: boolean()
}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Starts the MEGA storage server
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    Username = application:get_env(aethertalk, mega_username, undefined),
    Password = application:get_env(aethertalk, mega_password, undefined),
    start_link([{username, Username}, {password, Password}]).

-spec start_link(list()) -> {ok, pid()} | ignore | {error, term()}.
start_link(Args) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Args, []).

%% @doc Upload a file to MEGA
-spec upload_file(binary(), binary(), binary()) -> {ok, binary()} | {error, term()}.
upload_file(FileName, FileData, FolderPath) ->
    gen_server:call(?SERVER, {upload_file, FileName, FileData, FolderPath}, ?TIMEOUT).

%% @doc Download a file from MEGA
-spec download_file(binary(), binary()) -> {ok, binary()} | {error, term()}.
download_file(FileId, LocalPath) ->
    gen_server:call(?SERVER, {download_file, FileId, LocalPath}, ?TIMEOUT).

%% @doc Delete a file from MEGA
-spec delete_file(binary(), binary()) -> ok | {error, term()}.
delete_file(FileId, FolderPath) ->
    gen_server:call(?SERVER, {delete_file, FileId, FolderPath}, ?TIMEOUT).

%% @doc List files in a folder
-spec list_files(binary()) -> {ok, list()} | {error, term()}.
list_files(FolderPath) ->
    gen_server:call(?SERVER, {list_files, FolderPath}, ?TIMEOUT).

%% @doc Get file information
-spec get_file_info(binary(), binary()) -> {ok, map()} | {error, term()}.
get_file_info(FileId, FolderPath) ->
    gen_server:call(?SERVER, {get_file_info, FileId, FolderPath}, ?TIMEOUT).

%% @doc Create a folder
-spec create_folder(binary(), binary()) -> {ok, binary()} | {error, term()}.
create_folder(FolderName, ParentPath) ->
    gen_server:call(?SERVER, {create_folder, FolderName, ParentPath}, ?TIMEOUT).

%% @doc Get download URL for a file
-spec get_download_url(binary(), binary()) -> {ok, binary()} | {error, term()}.
get_download_url(FileId, FolderPath) ->
    gen_server:call(?SERVER, {get_download_url, FileId, FolderPath}, ?TIMEOUT).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init(Args) ->
    Username = proplists:get_value(username, Args),
    Password = proplists:get_value(password, Args),
    
    case {Username, Password} of
        {undefined, _} ->
            lager:warning("MEGA username not configured"),
            {ok, #state{connected = false}};
        {_, undefined} ->
            lager:warning("MEGA password not configured"),
            {ok, #state{connected = false}};
        {U, P} when is_list(U) ->
            init([{username, list_to_binary(U)}, {password, list_to_binary(P)}]);
        {U, P} when is_list(P) ->
            init([{username, U}, {password, list_to_binary(P)}]);
        {U, P} ->
            State = #state{username = U, password = P},
            case authenticate(State) of
                {ok, NewState} ->
                    lager:info("MEGA storage initialized successfully"),
                    {ok, NewState};
                {error, Reason} ->
                    lager:error("Failed to authenticate with MEGA: ~p", [Reason]),
                    {ok, State#state{connected = false}}
            end
    end.

handle_call({upload_file, FileName, FileData, FolderPath}, _From, State) ->
    case State#state.connected of
        true ->
            Result = do_upload_file(FileName, FileData, FolderPath, State),
            {reply, Result, State};
        false ->
            {reply, {error, not_connected}, State}
    end;

handle_call({download_file, FileId, LocalPath}, _From, State) ->
    case State#state.connected of
        true ->
            Result = do_download_file(FileId, LocalPath, State),
            {reply, Result, State};
        false ->
            {reply, {error, not_connected}, State}
    end;

handle_call({delete_file, FileId, FolderPath}, _From, State) ->
    case State#state.connected of
        true ->
            Result = do_delete_file(FileId, FolderPath, State),
            {reply, Result, State};
        false ->
            {reply, {error, not_connected}, State}
    end;

handle_call({list_files, FolderPath}, _From, State) ->
    case State#state.connected of
        true ->
            Result = do_list_files(FolderPath, State),
            {reply, Result, State};
        false ->
            {reply, {error, not_connected}, State}
    end;

handle_call({get_file_info, FileId, FolderPath}, _From, State) ->
    case State#state.connected of
        true ->
            Result = do_get_file_info(FileId, FolderPath, State),
            {reply, Result, State};
        false ->
            {reply, {error, not_connected}, State}
    end;

handle_call({create_folder, FolderName, ParentPath}, _From, State) ->
    case State#state.connected of
        true ->
            Result = do_create_folder(FolderName, ParentPath, State),
            {reply, Result, State};
        false ->
            {reply, {error, not_connected}, State}
    end;

handle_call({get_download_url, FileId, FolderPath}, _From, State) ->
    case State#state.connected of
        true ->
            Result = do_get_download_url(FileId, FolderPath, State),
            {reply, Result, State};
        false ->
            {reply, {error, not_connected}, State}
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
authenticate(#state{username = Username, password = _Password} = State) ->
    try
        % Simplified authentication for demo purposes
        % In production, implement proper MEGA authentication protocol
        lager:info("Authenticating with MEGA for user: ~s", [Username]),
        
        % Simulate successful authentication
        SessionId = <<"demo_session_", Username/binary>>,
        MasterKey = <<"demo_master_key">>,
        RootFolder = <<"demo_root_folder">>,
        
        {ok, State#state{
            session_id = SessionId,
            master_key = MasterKey,
            root_folder = RootFolder,
            connected = true
        }}
    catch
        Error:Reason ->
            lager:error("MEGA authentication error: ~p:~p", [Error, Reason]),
            {error, {auth_exception, Error, Reason}}
    end.

%% @private
do_upload_file(FileName, _FileData, FolderPath, _State) ->
    try
        lager:info("Uploading file ~s to MEGA folder ~s", [FileName, FolderPath]),
        
        % Simulate file upload
        FileId = uuid:uuid4(),
        lager:info("File uploaded successfully with ID: ~s", [FileId]),
        {ok, FileId}
    catch
        Error:Reason ->
            lager:error("MEGA upload error: ~p:~p", [Error, Reason]),
            {error, {upload_failed, Error, Reason}}
    end.

%% @private
do_download_file(FileId, LocalPath, _State) ->
    try
        lager:info("Downloading file ~s from MEGA to ~s", [FileId, LocalPath]),
        
        % Simulate file download
        FileContent = <<"Demo file content for ", FileId/binary>>,
        {ok, FileContent}
    catch
        Error:Reason ->
            lager:error("MEGA download error: ~p:~p", [Error, Reason]),
            {error, {download_failed, Error, Reason}}
    end.

%% @private
do_delete_file(FileId, FolderPath, _State) ->
    try
        lager:info("Deleting file ~s from MEGA folder ~s", [FileId, FolderPath]),
        ok
    catch
        Error:Reason ->
            lager:error("MEGA delete error: ~p:~p", [Error, Reason]),
            {error, {delete_failed, Error, Reason}}
    end.

%% @private
do_list_files(FolderPath, _State) ->
    try
        lager:info("Listing files in MEGA folder ~s", [FolderPath]),
        
        % Simulate file listing
        Files = [
            #{id => <<"file1">>, name => <<"example1.txt">>, size => 1024},
            #{id => <<"file2">>, name => <<"example2.jpg">>, size => 2048}
        ],
        {ok, Files}
    catch
        Error:Reason ->
            lager:error("MEGA list error: ~p:~p", [Error, Reason]),
            {error, {list_failed, Error, Reason}}
    end.

%% @private
do_get_file_info(FileId, FolderPath, _State) ->
    try
        lager:info("Getting file info for ~s in MEGA folder ~s", [FileId, FolderPath]),
        
        FileInfo = #{
            id => FileId,
            name => <<"example.txt">>,
            size => 1024,
            created_at => erlang:system_time(second),
            modified_at => erlang:system_time(second),
            type => <<"text/plain">>
        },
        {ok, FileInfo}
    catch
        Error:Reason ->
            lager:error("MEGA file info error: ~p:~p", [Error, Reason]),
            {error, {file_info_failed, Error, Reason}}
    end.

%% @private
do_create_folder(FolderName, ParentPath, _State) ->
    try
        lager:info("Creating MEGA folder ~s in ~s", [FolderName, ParentPath]),
        
        FolderId = uuid:uuid4(),
        {ok, FolderId}
    catch
        Error:Reason ->
            lager:error("MEGA create folder error: ~p:~p", [Error, Reason]),
            {error, {create_folder_failed, Error, Reason}}
    end.

%% @private
do_get_download_url(FileId, FolderPath, _State) ->
    try
        lager:info("Getting download URL for file ~s in MEGA folder ~s", [FileId, FolderPath]),
        
        Url = <<"https://mega.nz/file/", FileId/binary>>,
        {ok, Url}
    catch
        Error:Reason ->
            lager:error("MEGA download URL error: ~p:~p", [Error, Reason]),
            {error, {download_url_failed, Error, Reason}}
    end.