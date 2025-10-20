%%%-------------------------------------------------------------------
%%% @doc
%%% Cluster Management Service for AetherTalk
%%% Handles node discovery, clustering, and distributed operations
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_cluster_manager).
-behaviour(gen_server).

% OTP callbacks
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% Public API
-export([
    join_cluster/1,
    leave_cluster/0,
    get_cluster_nodes/0,
    get_node_status/0,
    get_cluster_status/0,
    broadcast_message/2,
    send_to_node/3,
    get_node_load/0,
    get_cluster_load/0,
    elect_leader/0,
    is_leader/0,
    get_leader/0,
    register_service/2,
    unregister_service/1,
    discover_services/1,
    health_check/0
]).

-include("aethertalk.hrl").

-record(state, {
    node_name :: atom(),
    cluster_nodes :: [atom()],
    leader_node :: atom() | undefined,
    is_leader :: boolean(),
    services :: #{atom() => term()},
    last_heartbeat :: integer(),
    heartbeat_interval :: integer()
}).

-define(HEARTBEAT_INTERVAL, 30000). % 30 seconds
-define(NODE_TIMEOUT, 90000). % 90 seconds
-define(LEADER_ELECTION_TIMEOUT, 5000). % 5 seconds

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

join_cluster(NodeName) ->
    gen_server:call(?MODULE, {join_cluster, NodeName}).

leave_cluster() ->
    gen_server:call(?MODULE, leave_cluster).

get_cluster_nodes() ->
    gen_server:call(?MODULE, get_cluster_nodes).

get_node_status() ->
    gen_server:call(?MODULE, get_node_status).

get_cluster_status() ->
    gen_server:call(?MODULE, get_cluster_status).

broadcast_message(Message, Data) ->
    gen_server:cast(?MODULE, {broadcast_message, Message, Data}).

send_to_node(Node, Message, Data) ->
    gen_server:cast(?MODULE, {send_to_node, Node, Message, Data}).

get_node_load() ->
    gen_server:call(?MODULE, get_node_load).

get_cluster_load() ->
    gen_server:call(?MODULE, get_cluster_load).

elect_leader() ->
    gen_server:cast(?MODULE, elect_leader).

is_leader() ->
    gen_server:call(?MODULE, is_leader).

get_leader() ->
    gen_server:call(?MODULE, get_leader).

register_service(ServiceName, ServiceData) ->
    gen_server:call(?MODULE, {register_service, ServiceName, ServiceData}).

unregister_service(ServiceName) ->
    gen_server:call(?MODULE, {unregister_service, ServiceName}).

discover_services(ServiceName) ->
    gen_server:call(?MODULE, {discover_services, ServiceName}).

health_check() ->
    gen_server:call(?MODULE, health_check).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    % Set up node monitoring
    net_kernel:monitor_nodes(true),
    
    % Start heartbeat timer
    timer:send_interval(?HEARTBEAT_INTERVAL, heartbeat),
    
    % Initialize state
    NodeName = node(),
    State = #state{
        node_name = NodeName,
        cluster_nodes = [NodeName],
        leader_node = NodeName,
        is_leader = true,
        services = #{},
        last_heartbeat = erlang:system_time(millisecond),
        heartbeat_interval = ?HEARTBEAT_INTERVAL
    },
    
    io:format("Cluster manager started on node ~p~n", [NodeName]),
    {ok, State}.

handle_call({join_cluster, TargetNode}, _From, State) ->
    Result = do_join_cluster(TargetNode, State),
    case Result of
        {ok, NewState} ->
            {reply, ok, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(leave_cluster, _From, State) ->
    NewState = do_leave_cluster(State),
    {reply, ok, NewState};

handle_call(get_cluster_nodes, _From, State) ->
    {reply, {ok, State#state.cluster_nodes}, State};

handle_call(get_node_status, _From, State) ->
    Status = do_get_node_status(State),
    {reply, {ok, Status}, State};

handle_call(get_cluster_status, _From, State) ->
    Status = do_get_cluster_status(State),
    {reply, {ok, Status}, State};

handle_call(get_node_load, _From, State) ->
    Load = do_get_node_load(),
    {reply, {ok, Load}, State};

handle_call(get_cluster_load, _From, State) ->
    Load = do_get_cluster_load(State),
    {reply, {ok, Load}, State};

handle_call(is_leader, _From, State) ->
    {reply, State#state.is_leader, State};

handle_call(get_leader, _From, State) ->
    {reply, {ok, State#state.leader_node}, State};

handle_call({register_service, ServiceName, ServiceData}, _From, State) ->
    NewServices = maps:put(ServiceName, ServiceData, State#state.services),
    NewState = State#state{services = NewServices},
    
    % Broadcast service registration to cluster
    broadcast_to_cluster({service_registered, node(), ServiceName, ServiceData}, State),
    
    io:format("Registered service ~p on node ~p~n", [ServiceName, node()]),
    {reply, ok, NewState};

handle_call({unregister_service, ServiceName}, _From, State) ->
    NewServices = maps:remove(ServiceName, State#state.services),
    NewState = State#state{services = NewServices},
    
    % Broadcast service unregistration to cluster
    broadcast_to_cluster({service_unregistered, node(), ServiceName}, State),
    
    io:format("Unregistered service ~p from node ~p~n", [ServiceName, node()]),
    {reply, ok, NewState};

handle_call({discover_services, ServiceName}, _From, State) ->
    Services = do_discover_services(ServiceName, State),
    {reply, {ok, Services}, State};

handle_call(health_check, _From, State) ->
    Health = do_health_check(State),
    {reply, {ok, Health}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({broadcast_message, Message, Data}, State) ->
    broadcast_to_cluster({Message, Data}, State),
    {noreply, State};

handle_cast({send_to_node, Node, Message, Data}, State) ->
    send_message_to_node(Node, {Message, Data}),
    {noreply, State};

handle_cast(elect_leader, State) ->
    NewState = do_elect_leader(State),
    {noreply, NewState};

handle_cast({cluster_message, FromNode, Message}, State) ->
    NewState = handle_cluster_message(FromNode, Message, State),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(heartbeat, State) ->
    NewState = do_heartbeat(State),
    {noreply, NewState};

handle_info({nodeup, Node}, State) ->
    io:format("Node ~p joined the cluster~n", [Node]),
    NewNodes = lists:usort([Node | State#state.cluster_nodes]),
    NewState = State#state{cluster_nodes = NewNodes},
    
    % Send cluster info to new node
    send_message_to_node(Node, {cluster_info, State#state.cluster_nodes, State#state.leader_node}),
    
    % Trigger leader election if needed
    case State#state.is_leader of
        true ->
            % We're the leader, inform the new node
            send_message_to_node(Node, {leader_announcement, node()});
        false ->
            % Trigger leader election
            gen_server:cast(?MODULE, elect_leader)
    end,
    
    {noreply, NewState};

handle_info({nodedown, Node}, State) ->
    io:format("Node ~p left the cluster~n", [Node]),
    NewNodes = lists:delete(Node, State#state.cluster_nodes),
    
    % Check if the leader went down
    NewState = case State#state.leader_node of
        Node ->
            % Leader went down, trigger election
            gen_server:cast(?MODULE, elect_leader),
            State#state{cluster_nodes = NewNodes, leader_node = undefined, is_leader = false};
        _ ->
            State#state{cluster_nodes = NewNodes}
    end,
    
    {noreply, NewState};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    net_kernel:monitor_nodes(false),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

do_join_cluster(TargetNode, State) ->
    case net_adm:ping(TargetNode) of
        pong ->
            % Successfully connected to target node
            case rpc:call(TargetNode, ?MODULE, get_cluster_nodes, []) of
                {ok, ClusterNodes} ->
                    % Join the cluster
                    AllNodes = lists:usort([node() | ClusterNodes]),
                    
                    % Notify all nodes about the new member
                    lists:foreach(fun(Node) ->
                        if Node =/= node() ->
                            send_message_to_node(Node, {node_joined, node()});
                        true -> ok
                        end
                    end, AllNodes),
                    
                    % Get leader information
                    {ok, Leader} = rpc:call(TargetNode, ?MODULE, get_leader, []),
                    
                    NewState = State#state{
                        cluster_nodes = AllNodes,
                        leader_node = Leader,
                        is_leader = (Leader =:= node())
                    },
                    
                    io:format("Successfully joined cluster with nodes: ~p~n", [AllNodes]),
                    {ok, NewState};
                Error ->
                    io:format("Failed to get cluster info from ~p: ~p~n", [TargetNode, Error]),
                    {error, cluster_info_failed}
            end;
        pang ->
            io:format("Failed to connect to target node ~p~n", [TargetNode]),
            {error, connection_failed}
    end.

do_leave_cluster(State) ->
    % Notify all other nodes that we're leaving
    OtherNodes = lists:delete(node(), State#state.cluster_nodes),
    lists:foreach(fun(Node) ->
        send_message_to_node(Node, {node_leaving, node()})
    end, OtherNodes),
    
    % If we're the leader, trigger election on other nodes
    case State#state.is_leader andalso length(OtherNodes) > 0 of
        true ->
            lists:foreach(fun(Node) ->
                send_message_to_node(Node, {trigger_election})
            end, OtherNodes);
        false ->
            ok
    end,
    
    % Reset to single-node cluster
    NewState = State#state{
        cluster_nodes = [node()],
        leader_node = node(),
        is_leader = true
    },
    
    io:format("Left cluster, now running as single node~n"),
    NewState.

do_get_node_status(State) ->
    #{
        node => State#state.node_name,
        is_leader => State#state.is_leader,
        leader => State#state.leader_node,
        cluster_size => length(State#state.cluster_nodes),
        services => maps:keys(State#state.services),
        uptime => get_uptime(),
        memory_usage => get_memory_usage(),
        cpu_usage => get_cpu_usage(),
        last_heartbeat => State#state.last_heartbeat
    }.

do_get_cluster_status(State) ->
    NodeStatuses = lists:map(fun(Node) ->
        case Node =:= node() of
            true ->
                do_get_node_status(State);
            false ->
                case rpc:call(Node, ?MODULE, get_node_status, [], 5000) of
                    {ok, Status} -> Status;
                    _ -> #{node => Node, status => unreachable}
                end
        end
    end, State#state.cluster_nodes),
    
    #{
        cluster_nodes => State#state.cluster_nodes,
        leader => State#state.leader_node,
        total_nodes => length(State#state.cluster_nodes),
        healthy_nodes => length([N || #{status := S} = N <- NodeStatuses, S =/= unreachable]),
        node_statuses => NodeStatuses
    }.

do_get_node_load() ->
    #{
        cpu_usage => get_cpu_usage(),
        memory_usage => get_memory_usage(),
        process_count => erlang:system_info(process_count),
        run_queue => erlang:statistics(run_queue),
        io_input => element(2, erlang:statistics(io)),
        io_output => element(1, erlang:statistics(io)),
        reductions => element(1, erlang:statistics(reductions))
    }.

do_get_cluster_load(State) ->
    NodeLoads = lists:map(fun(Node) ->
        case Node =:= node() of
            true ->
                {Node, do_get_node_load()};
            false ->
                case rpc:call(Node, ?MODULE, get_node_load, [], 5000) of
                    {ok, Load} -> {Node, Load};
                    _ -> {Node, #{status => unreachable}}
                end
        end
    end, State#state.cluster_nodes),
    
    % Calculate cluster averages
    ValidLoads = [Load || {_, Load} <- NodeLoads, not maps:is_key(status, Load)],
    
    case ValidLoads of
        [] ->
            #{node_loads => NodeLoads, cluster_average => #{}};
        _ ->
            AvgCPU = lists:sum([maps:get(cpu_usage, L, 0) || L <- ValidLoads]) / length(ValidLoads),
            AvgMemory = lists:sum([maps:get(memory_usage, L, 0) || L <- ValidLoads]) / length(ValidLoads),
            TotalProcesses = lists:sum([maps:get(process_count, L, 0) || L <- ValidLoads]),
            
            #{
                node_loads => NodeLoads,
                cluster_average => #{
                    cpu_usage => AvgCPU,
                    memory_usage => AvgMemory,
                    total_processes => TotalProcesses,
                    healthy_nodes => length(ValidLoads)
                }
            }
    end.

do_elect_leader(State) ->
    % Simple leader election: node with lowest name becomes leader
    SortedNodes = lists:sort(State#state.cluster_nodes),
    NewLeader = hd(SortedNodes),
    
    IsNewLeader = (NewLeader =:= node()),
    
    % Announce new leader to all nodes
    broadcast_to_cluster({leader_elected, NewLeader}, State),
    
    case IsNewLeader of
        true ->
            io:format("Elected as cluster leader~n"),
            % Start leader-specific tasks
            start_leader_tasks();
        false ->
            io:format("Node ~p elected as cluster leader~n", [NewLeader]),
            % Stop leader-specific tasks if we were leader before
            case State#state.is_leader of
                true -> stop_leader_tasks();
                false -> ok
            end
    end,
    
    State#state{
        leader_node = NewLeader,
        is_leader = IsNewLeader
    }.

do_discover_services(ServiceName, State) ->
    % Get services from all cluster nodes
    lists:foldl(fun(Node, Acc) ->
        case Node =:= node() of
            true ->
                case maps:get(ServiceName, State#state.services, undefined) of
                    undefined -> Acc;
                    ServiceData -> [{Node, ServiceData} | Acc]
                end;
            false ->
                case rpc:call(Node, gen_server, call, [?MODULE, {get_service, ServiceName}], 5000) of
                    {ok, ServiceData} -> [{Node, ServiceData} | Acc];
                    _ -> Acc
                end
        end
    end, [], State#state.cluster_nodes).

do_health_check(State) ->
    NodeHealth = #{
        node => node(),
        status => healthy,
        uptime => get_uptime(),
        memory => get_memory_usage(),
        cpu => get_cpu_usage(),
        processes => erlang:system_info(process_count),
        cluster_connected => length(State#state.cluster_nodes) > 1,
        is_leader => State#state.is_leader,
        services => maps:keys(State#state.services)
    },
    
    % Check critical services
    CriticalServices = [aethertalk_db, aethertalk_redis, aethertalk_websocket],
    ServiceHealth = lists:map(fun(Service) ->
        case whereis(Service) of
            undefined -> {Service, down};
            Pid when is_pid(Pid) -> {Service, up}
        end
    end, CriticalServices),
    
    OverallStatus = case lists:any(fun({_, Status}) -> Status =:= down end, ServiceHealth) of
        true -> degraded;
        false -> healthy
    end,
    
    NodeHealth#{
        overall_status => OverallStatus,
        service_health => ServiceHealth
    }.

do_heartbeat(State) ->
    Now = erlang:system_time(millisecond),
    
    % Send heartbeat to all cluster nodes
    HeartbeatData = #{
        node => node(),
        timestamp => Now,
        load => do_get_node_load(),
        services => maps:keys(State#state.services)
    },
    
    broadcast_to_cluster({heartbeat, HeartbeatData}, State),
    
    State#state{last_heartbeat = Now}.

handle_cluster_message(FromNode, Message, State) ->
    case Message of
        {heartbeat, _HeartbeatData} ->
            % Update node information
            io:format("Received heartbeat from ~p~n", [FromNode]),
            State;
        
        {leader_elected, NewLeader} ->
            IsNewLeader = (NewLeader =:= node()),
            case IsNewLeader andalso not State#state.is_leader of
                true -> start_leader_tasks();
                false -> 
                    case State#state.is_leader andalso not IsNewLeader of
                        true -> stop_leader_tasks();
                        false -> ok
                    end
            end,
            State#state{leader_node = NewLeader, is_leader = IsNewLeader};
        
        {node_joined, Node} ->
            NewNodes = lists:usort([Node | State#state.cluster_nodes]),
            io:format("Node ~p joined cluster~n", [Node]),
            State#state{cluster_nodes = NewNodes};
        
        {node_leaving, Node} ->
            NewNodes = lists:delete(Node, State#state.cluster_nodes),
            io:format("Node ~p leaving cluster~n", [Node]),
            NewState = State#state{cluster_nodes = NewNodes},
            
            % If leader is leaving, trigger election
            case State#state.leader_node of
                Node -> do_elect_leader(NewState);
                _ -> NewState
            end;
        
        {trigger_election} ->
            do_elect_leader(State);
        
        {service_registered, Node, ServiceName, _ServiceData} ->
            io:format("Service ~p registered on node ~p~n", [ServiceName, Node]),
            State;
        
        {service_unregistered, Node, ServiceName} ->
            io:format("Service ~p unregistered from node ~p~n", [ServiceName, Node]),
            State;
        
        _ ->
            io:format("Unknown cluster message from ~p: ~p~n", [FromNode, Message]),
            State
    end.

broadcast_to_cluster(Message, State) ->
    OtherNodes = lists:delete(node(), State#state.cluster_nodes),
    lists:foreach(fun(Node) ->
        send_message_to_node(Node, Message)
    end, OtherNodes).

send_message_to_node(Node, Message) ->
    gen_server:cast({?MODULE, Node}, {cluster_message, node(), Message}).

start_leader_tasks() ->
    % Start leader-specific background tasks
    io:format("Starting leader tasks~n"),
    ok.

stop_leader_tasks() ->
    % Stop leader-specific background tasks
    io:format("Stopping leader tasks~n"),
    ok.

%% Utility functions
get_uptime() ->
    {UpTime, _} = erlang:statistics(wall_clock),
    UpTime.

get_memory_usage() ->
    erlang:memory(total).

get_cpu_usage() ->
    % Simple CPU usage approximation
    case erlang:statistics(scheduler_wall_time) of
        undefined -> 0;
        _ -> 
            % This is a simplified version - in production you'd want more accurate CPU monitoring
            element(1, erlang:statistics(reductions)) rem 100
    end.