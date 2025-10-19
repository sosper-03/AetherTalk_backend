%%%-------------------------------------------------------------------
%% @doc AetherTalk top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 10,
        period => 60
    },
    
    ChildSpecs = [
        % Core infrastructure supervisors
        #{
            id => aethertalk_core_sup,
            start => {aethertalk_core_sup, start_link, []},
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [aethertalk_core_sup]
        },
        
        % Database connection pools
        #{
            id => aethertalk_db_sup,
            start => {aethertalk_db_sup, start_link, []},
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [aethertalk_db_sup]
        },
        
        % User management system
        #{
            id => aethertalk_user_manager,
            start => {aethertalk_user_manager, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_user_manager]
        },
        
        % Message routing system
        #{
            id => aethertalk_message_router,
            start => {aethertalk_message_router, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_message_router]
        },
        
        % Presence management
        #{
            id => aethertalk_presence_manager,
            start => {aethertalk_presence_manager, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_presence_manager]
        },
        
        % Call management system
        #{
            id => aethertalk_call_manager,
            start => {aethertalk_call_manager, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_call_manager]
        },
        
        % Media processing service
        #{
            id => aethertalk_media_processor,
            start => {aethertalk_media_processor, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_media_processor]
        },
        
        % Translation service
        #{
            id => aethertalk_translation_service,
            start => {aethertalk_translation_service, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_translation_service]
        },
        
        % Notification service
        #{
            id => aethertalk_notification_service,
            start => {aethertalk_notification_service, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_notification_service]
        },
        
        % Group management system
        #{
            id => aethertalk_group_manager,
            start => {aethertalk_group_manager, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_group_manager]
        },
        
        % Status/Stories management
        #{
            id => aethertalk_status_manager,
            start => {aethertalk_status_manager, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_status_manager]
        },
        
        % Message reactions system
        #{
            id => aethertalk_reactions_manager,
            start => {aethertalk_reactions_manager, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_reactions_manager]
        },
        
        % Polls management system
        #{
            id => aethertalk_polls_manager,
            start => {aethertalk_polls_manager, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_polls_manager]
        },
        
        % Disappearing messages system
        #{
            id => aethertalk_disappearing_messages,
            start => {aethertalk_disappearing_messages, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_disappearing_messages]
        },
        
        % Location sharing service
        #{
            id => aethertalk_location_service,
            start => {aethertalk_location_service, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_location_service]
        },
        
        % Security services
        #{
            id => aethertalk_encryption,
            start => {aethertalk_encryption, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_encryption]
        },
        
        #{
            id => aethertalk_rate_limiter,
            start => {aethertalk_rate_limiter, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_rate_limiter]
        },
        
        #{
            id => aethertalk_mfa,
            start => {aethertalk_mfa, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [aethertalk_mfa]
        },
        
        % HTTP/WebSocket API supervisor
        #{
            id => aethertalk_api_sup,
            start => {aethertalk_api_sup, start_link, []},
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [aethertalk_api_sup]
        }
    ],
    
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions
