%%%-------------------------------------------------------------------
%% @doc AetherTalk API supervisor
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_api_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 60
    },
    
    % Get port configurations
    HttpPort = aethertalk_app:get_env(http_port, 8080),
    _HttpsPort = aethertalk_app:get_env(https_port, 8443),
    _WebSocketPort = aethertalk_app:get_env(websocket_port, 8081),
    _MaxConnections = aethertalk_app:get_env(max_connections, 10000),
    
    % Define routes
    Dispatch = cowboy_router:compile([
        {'_', [
            % REST API routes
            {"/api/v1/auth/register", aethertalk_auth_handler, []},
            {"/api/v1/auth/login", aethertalk_auth_handler, []},
            {"/api/v1/auth/logout", aethertalk_auth_handler, []},
            {"/api/v1/auth/refresh", aethertalk_auth_handler, []},
            
            {"/api/v1/users/profile", aethertalk_user_handler, []},
            {"/api/v1/users/contacts", aethertalk_contact_handler, []},
            {"/api/v1/users/settings", aethertalk_settings_handler, []},
            
            {"/api/v1/chats", aethertalk_chat_handler, []},
            {"/api/v1/chats/:chat_id/messages", aethertalk_message_handler, []},
            {"/api/v1/chats/:chat_id/media", aethertalk_media_handler, []},
            
            {"/api/v1/groups", aethertalk_group_handler, []},
            {"/api/v1/groups/:group_id/members", aethertalk_group_member_handler, []},
            
            {"/api/v1/calls", aethertalk_call_handler, []},
            {"/api/v1/calls/:call_id/join", aethertalk_call_join_handler, []},
            
            {"/api/v1/media/upload", aethertalk_media_upload_handler, []},
            {"/api/v1/media/:media_id", aethertalk_media_download_handler, []},
            
            {"/api/v1/status", aethertalk_status_handler, []},
            {"/api/v1/notifications", aethertalk_notification_handler, []},
            
            % WebSocket endpoint
            {"/ws", aethertalk_websocket_handler, []},
            
            % Health check
            {"/health", aethertalk_health_handler, []},
            
            % Test endpoint
            {"/test", aethertalk_test_handler, []},
            
            % Static files
            {"/[...]", cowboy_static, {priv_dir, aethertalk, "static"}}
        ]}
    ]),
    
    ChildSpecs = [
        % HTTP server
        #{
            id => aethertalk_http_listener,
            start => {cowboy, start_clear, [
                aethertalk_http_listener,
                #{socket_opts => [{port, HttpPort}], num_acceptors => 100},
                #{env => #{dispatch => Dispatch}}
            ]},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [cowboy]
        },
        
        % WebSocket connection manager
        #{
            id => aethertalk_websocket_manager,
            start => {aethertalk_websocket_manager, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_websocket_manager]
        }
    ],
    
    {ok, {SupFlags, ChildSpecs}}.