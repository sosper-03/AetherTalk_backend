%%%-------------------------------------------------------------------
%%% @doc
%%% Group API endpoints for AetherTalk
%%% Handles HTTP requests for group management operations
%%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_group_api).

-export([init/2]).

-include("aethertalk.hrl").

%% Cowboy handler
init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Path = cowboy_req:path_info(Req0),
    
    Req = case {Method, Path} of
        {<<"POST">>, [<<"groups">>]} ->
            handle_create_group(Req0, State);
        {<<"GET">>, [<<"groups">>, GroupId]} ->
            handle_get_group(Req0#{group_id => GroupId}, State);
        {<<"PUT">>, [<<"groups">>, GroupId]} ->
            handle_update_group(Req0#{group_id => GroupId}, State);
        {<<"DELETE">>, [<<"groups">>, GroupId]} ->
            handle_delete_group(Req0#{group_id => GroupId}, State);
        {<<"POST">>, [<<"groups">>, GroupId, <<"members">>]} ->
            handle_add_member(Req0#{group_id => GroupId}, State);
        {<<"DELETE">>, [<<"groups">>, GroupId, <<"members">>, UserId]} ->
            handle_remove_member(Req0#{group_id => GroupId, user_id => UserId}, State);
        {<<"PUT">>, [<<"groups">>, GroupId, <<"members">>, UserId, <<"promote">>]} ->
            handle_promote_member(Req0#{group_id => GroupId, user_id => UserId}, State);
        {<<"PUT">>, [<<"groups">>, GroupId, <<"members">>, UserId, <<"demote">>]} ->
            handle_demote_member(Req0#{group_id => GroupId, user_id => UserId}, State);
        {<<"GET">>, [<<"groups">>, GroupId, <<"members">>]} ->
            handle_get_members(Req0#{group_id => GroupId}, State);
        {<<"GET">>, [<<"users">>, <<"groups">>]} ->
            handle_get_user_groups(Req0, State);
        {<<"POST">>, [<<"groups">>, GroupId, <<"leave">>]} ->
            handle_leave_group(Req0#{group_id => GroupId}, State);
        {<<"PUT">>, [<<"groups">>, GroupId, <<"settings">>]} ->
            handle_update_settings(Req0#{group_id => GroupId}, State);
        {<<"POST">>, [<<"broadcasts">>]} ->
            handle_create_broadcast(Req0, State);
        {<<"GET">>, [<<"broadcasts">>]} ->
            handle_get_broadcasts(Req0, State);
        {<<"POST">>, [<<"broadcasts">>, BroadcastId, <<"send">>]} ->
            handle_send_broadcast(Req0#{broadcast_id => BroadcastId}, State);
        _ ->
            cowboy_req:reply(404, #{<<"content-type">> => <<"application/json">>},
                           jiffy:encode(#{error => <<"Not found">>}), Req0)
    end,
    
    {ok, Req, State}.

%% Create new group
handle_create_group(Req, _State) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, UserId} ->
            case cowboy_req:read_body(Req) of
                {ok, Body, Req1} ->
                    case parse_create_group_request(Body) of
                        {ok, Name, Description} ->
                            case aethertalk_group_manager:create_group(UserId, Name, Description) of
                                {ok, Group} ->
                                    Response = jiffy:encode(#{
                                        success => true,
                                        group => Group
                                    }),
                                    cowboy_req:reply(201, #{<<"content-type">> => <<"application/json">>},
                                                   Response, Req1);
                                {error, Reason} ->
                                    ErrorResponse = jiffy:encode(#{
                                        success => false,
                                        error => atom_to_binary(Reason, utf8)
                                    }),
                                    cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                                   ErrorResponse, Req1)
                            end;
                        {error, invalid_body} ->
                            ErrorResponse = jiffy:encode(#{
                                success => false,
                                error => <<"Invalid request body">>
                            }),
                            cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                           ErrorResponse, Req1)
                    end;
                {error, _} ->
                    ErrorResponse = jiffy:encode(#{
                        success => false,
                        error => <<"Failed to read request body">>
                    }),
                    cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                   ErrorResponse, Req)
            end;
        {error, _} ->
            ErrorResponse = jiffy:encode(#{
                success => false,
                error => <<"Unauthorized">>
            }),
            cowboy_req:reply(401, #{<<"content-type">> => <<"application/json">>},
                           ErrorResponse, Req)
    end.

%% Get group information
handle_get_group(Req, _State) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, UserId} ->
            GroupId = maps:get(group_id, Req),
            
            case aethertalk_group_manager:get_group_info(GroupId, UserId) of
                {ok, Group} ->
                    Response = jiffy:encode(#{
                        success => true,
                        group => Group
                    }),
                    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>},
                                   Response, Req);
                {error, Reason} ->
                    ErrorResponse = jiffy:encode(#{
                        success => false,
                        error => atom_to_binary(Reason, utf8)
                    }),
                    cowboy_req:reply(404, #{<<"content-type">> => <<"application/json">>},
                                   ErrorResponse, Req)
            end;
        {error, _} ->
            ErrorResponse = jiffy:encode(#{
                success => false,
                error => <<"Unauthorized">>
            }),
            cowboy_req:reply(401, #{<<"content-type">> => <<"application/json">>},
                           ErrorResponse, Req)
    end.

%% Update group information
handle_update_group(Req, _State) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, _UserId} ->
            GroupId = maps:get(group_id, Req),
            
            case cowboy_req:read_body(Req) of
                {ok, Body, Req1} ->
                    case parse_json_body(Body) of
                        {ok, Updates} ->
                            case aethertalk_group_manager:update_group(GroupId, Updates) of
                                {ok, Result} ->
                                    Response = jiffy:encode(#{
                                        success => true,
                                        result => Result
                                    }),
                                    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>},
                                                   Response, Req1);
                                {error, Reason} ->
                                    ErrorResponse = jiffy:encode(#{
                                        success => false,
                                        error => atom_to_binary(Reason, utf8)
                                    }),
                                    cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                                   ErrorResponse, Req1)
                            end;
                        {error, invalid_json} ->
                            ErrorResponse = jiffy:encode(#{
                                success => false,
                                error => <<"Invalid request body">>
                            }),
                            cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                           ErrorResponse, Req1)
                    end;
                {error, _} ->
                    ErrorResponse = jiffy:encode(#{
                        success => false,
                        error => <<"Failed to read request body">>
                    }),
                    cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                   ErrorResponse, Req)
            end;
        {error, _} ->
            ErrorResponse = jiffy:encode(#{
                success => false,
                error => <<"Unauthorized">>
            }),
            cowboy_req:reply(401, #{<<"content-type">> => <<"application/json">>},
                           ErrorResponse, Req)
    end.

%% Delete group
handle_delete_group(Req, _State) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, UserId} ->
            GroupId = maps:get(group_id, Req),
            
            case aethertalk_group_manager:delete_group(GroupId, UserId) of
                ok ->
                    Response = jiffy:encode(#{
                        success => true,
                        message => <<"Group deleted successfully">>
                    }),
                    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>},
                                   Response, Req);
                {error, Reason} ->
                    ErrorResponse = jiffy:encode(#{
                        success => false,
                        error => atom_to_binary(Reason, utf8)
                    }),
                    cowboy_req:reply(403, #{<<"content-type">> => <<"application/json">>},
                                   ErrorResponse, Req)
            end;
        {error, _} ->
            ErrorResponse = jiffy:encode(#{
                success => false,
                error => <<"Unauthorized">>
            }),
            cowboy_req:reply(401, #{<<"content-type">> => <<"application/json">>},
                           ErrorResponse, Req)
    end.

%% Add member to group
handle_add_member(Req, _State) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, AdminId} ->
            GroupId = maps:get(group_id, Req),
            
            case cowboy_req:read_body(Req) of
                {ok, Body, Req1} ->
                    case parse_add_member_request(Body) of
                        {ok, UserId} ->
                            case aethertalk_group_manager:add_member(GroupId, UserId, AdminId) of
                                {ok, Member} ->
                                    Response = jiffy:encode(#{
                                        success => true,
                                        member => Member
                                    }),
                                    cowboy_req:reply(201, #{<<"content-type">> => <<"application/json">>},
                                                   Response, Req1);
                                {error, Reason} ->
                                    ErrorResponse = jiffy:encode(#{
                                        success => false,
                                        error => atom_to_binary(Reason, utf8)
                                    }),
                                    cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                                   ErrorResponse, Req1)
                            end;
                        {error, invalid_body} ->
                            ErrorResponse = jiffy:encode(#{
                                success => false,
                                error => <<"Invalid request body">>
                            }),
                            cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                           ErrorResponse, Req1)
                    end;
                {error, _} ->
                    ErrorResponse = jiffy:encode(#{
                        success => false,
                        error => <<"Failed to read request body">>
                    }),
                    cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                   ErrorResponse, Req)
            end;
        {error, _} ->
            ErrorResponse = jiffy:encode(#{
                success => false,
                error => <<"Unauthorized">>
            }),
            cowboy_req:reply(401, #{<<"content-type">> => <<"application/json">>},
                           ErrorResponse, Req)
    end.

%% Remove member from group
handle_remove_member(Req, _State) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, AdminId} ->
            GroupId = maps:get(group_id, Req),
            UserId = maps:get(user_id, Req),
            
            case aethertalk_group_manager:remove_member(GroupId, UserId, AdminId) of
                ok ->
                    Response = jiffy:encode(#{
                        success => true,
                        message => <<"Member removed successfully">>
                    }),
                    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>},
                                   Response, Req);
                {error, Reason} ->
                    ErrorResponse = jiffy:encode(#{
                        success => false,
                        error => atom_to_binary(Reason, utf8)
                    }),
                    cowboy_req:reply(403, #{<<"content-type">> => <<"application/json">>},
                                   ErrorResponse, Req)
            end;
        {error, _} ->
            ErrorResponse = jiffy:encode(#{
                success => false,
                error => <<"Unauthorized">>
            }),
            cowboy_req:reply(401, #{<<"content-type">> => <<"application/json">>},
                           ErrorResponse, Req)
    end.

%% Promote member to admin
handle_promote_member(Req, _State) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, AdminId} ->
            GroupId = maps:get(group_id, Req),
            UserId = maps:get(user_id, Req),
            
            case aethertalk_group_manager:promote_member(GroupId, UserId, AdminId) of
                ok ->
                    Response = jiffy:encode(#{
                        success => true,
                        message => <<"Member promoted to admin">>
                    }),
                    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>},
                                   Response, Req);
                {error, Reason} ->
                    ErrorResponse = jiffy:encode(#{
                        success => false,
                        error => atom_to_binary(Reason, utf8)
                    }),
                    cowboy_req:reply(403, #{<<"content-type">> => <<"application/json">>},
                                   ErrorResponse, Req)
            end;
        {error, _} ->
            ErrorResponse = jiffy:encode(#{
                success => false,
                error => <<"Unauthorized">>
            }),
            cowboy_req:reply(401, #{<<"content-type">> => <<"application/json">>},
                           ErrorResponse, Req)
    end.

%% Demote admin to member
handle_demote_member(Req, _State) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, AdminId} ->
            GroupId = maps:get(group_id, Req),
            UserId = maps:get(user_id, Req),
            
            case aethertalk_group_manager:demote_member(GroupId, UserId, AdminId) of
                ok ->
                    Response = jiffy:encode(#{
                        success => true,
                        message => <<"Admin demoted to member">>
                    }),
                    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>},
                                   Response, Req);
                {error, Reason} ->
                    ErrorResponse = jiffy:encode(#{
                        success => false,
                        error => atom_to_binary(Reason, utf8)
                    }),
                    cowboy_req:reply(403, #{<<"content-type">> => <<"application/json">>},
                                   ErrorResponse, Req)
            end;
        {error, _} ->
            ErrorResponse = jiffy:encode(#{
                success => false,
                error => <<"Unauthorized">>
            }),
            cowboy_req:reply(401, #{<<"content-type">> => <<"application/json">>},
                           ErrorResponse, Req)
    end.

%% Get group members
handle_get_members(Req, _State) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, _UserId} ->
            GroupId = maps:get(group_id, Req),
            
            case aethertalk_group_manager:get_group_members(GroupId) of
                {ok, Members} ->
                    Response = jiffy:encode(#{
                        success => true,
                        members => Members
                    }),
                    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>},
                                   Response, Req);
                {error, Reason} ->
                    ErrorResponse = jiffy:encode(#{
                        success => false,
                        error => atom_to_binary(Reason, utf8)
                    }),
                    cowboy_req:reply(404, #{<<"content-type">> => <<"application/json">>},
                                   ErrorResponse, Req)
            end;
        {error, _} ->
            ErrorResponse = jiffy:encode(#{
                success => false,
                error => <<"Unauthorized">>
            }),
            cowboy_req:reply(401, #{<<"content-type">> => <<"application/json">>},
                           ErrorResponse, Req)
    end.

%% Get user's groups
handle_get_user_groups(Req, _State) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, UserId} ->
            case aethertalk_group_manager:get_user_groups(UserId) of
                {ok, Groups} ->
                    Response = jiffy:encode(#{
                        success => true,
                        groups => Groups
                    }),
                    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>},
                                   Response, Req);
                {error, Reason} ->
                    ErrorResponse = jiffy:encode(#{
                        success => false,
                        error => atom_to_binary(Reason, utf8)
                    }),
                    cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                   ErrorResponse, Req)
            end;
        {error, _} ->
            ErrorResponse = jiffy:encode(#{
                success => false,
                error => <<"Unauthorized">>
            }),
            cowboy_req:reply(401, #{<<"content-type">> => <<"application/json">>},
                           ErrorResponse, Req)
    end.

%% Leave group
handle_leave_group(Req, _State) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, UserId} ->
            GroupId = maps:get(group_id, Req),
            
            case aethertalk_group_manager:leave_group(GroupId, UserId) of
                ok ->
                    Response = jiffy:encode(#{
                        success => true,
                        message => <<"Left group successfully">>
                    }),
                    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>},
                                   Response, Req);
                {error, Reason} ->
                    ErrorResponse = jiffy:encode(#{
                        success => false,
                        error => atom_to_binary(Reason, utf8)
                    }),
                    cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                   ErrorResponse, Req)
            end;
        {error, _} ->
            ErrorResponse = jiffy:encode(#{
                success => false,
                error => <<"Unauthorized">>
            }),
            cowboy_req:reply(401, #{<<"content-type">> => <<"application/json">>},
                           ErrorResponse, Req)
    end.

%% Update group settings
handle_update_settings(Req, _State) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, AdminId} ->
            GroupId = maps:get(group_id, Req),
            
            case cowboy_req:read_body(Req) of
                {ok, Body, Req1} ->
                    case parse_json_body(Body) of
                        {ok, Settings} ->
                            case aethertalk_group_manager:update_group_settings(GroupId, Settings, AdminId) of
                                {ok, Result} ->
                                    Response = jiffy:encode(#{
                                        success => true,
                                        result => Result
                                    }),
                                    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>},
                                                   Response, Req1);
                                {error, Reason} ->
                                    ErrorResponse = jiffy:encode(#{
                                        success => false,
                                        error => atom_to_binary(Reason, utf8)
                                    }),
                                    cowboy_req:reply(403, #{<<"content-type">> => <<"application/json">>},
                                                   ErrorResponse, Req1)
                            end;
                        {error, invalid_json} ->
                            ErrorResponse = jiffy:encode(#{
                                success => false,
                                error => <<"Invalid request body">>
                            }),
                            cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                           ErrorResponse, Req1)
                    end;
                {error, _} ->
                    ErrorResponse = jiffy:encode(#{
                        success => false,
                        error => <<"Failed to read request body">>
                    }),
                    cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                   ErrorResponse, Req)
            end;
        {error, _} ->
            ErrorResponse = jiffy:encode(#{
                success => false,
                error => <<"Unauthorized">>
            }),
            cowboy_req:reply(401, #{<<"content-type">> => <<"application/json">>},
                           ErrorResponse, Req)
    end.

%% Create broadcast list
handle_create_broadcast(Req, _State) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, UserId} ->
            case cowboy_req:read_body(Req) of
                {ok, Body, Req1} ->
                    case parse_create_broadcast_request(Body) of
                        {ok, Name, MemberIds} ->
                            case aethertalk_group_manager:create_broadcast_list(UserId, Name, MemberIds) of
                                {ok, BroadcastList} ->
                                    Response = jiffy:encode(#{
                                        success => true,
                                        broadcast_list => BroadcastList
                                    }),
                                    cowboy_req:reply(201, #{<<"content-type">> => <<"application/json">>},
                                                   Response, Req1);
                                {error, Reason} ->
                                    ErrorResponse = jiffy:encode(#{
                                        success => false,
                                        error => atom_to_binary(Reason, utf8)
                                    }),
                                    cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                                   ErrorResponse, Req1)
                            end;
                        {error, invalid_body} ->
                            ErrorResponse = jiffy:encode(#{
                                success => false,
                                error => <<"Invalid request body">>
                            }),
                            cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                           ErrorResponse, Req1)
                    end;
                {error, _} ->
                    ErrorResponse = jiffy:encode(#{
                        success => false,
                        error => <<"Failed to read request body">>
                    }),
                    cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                   ErrorResponse, Req)
            end;
        {error, _} ->
            ErrorResponse = jiffy:encode(#{
                success => false,
                error => <<"Unauthorized">>
            }),
            cowboy_req:reply(401, #{<<"content-type">> => <<"application/json">>},
                           ErrorResponse, Req)
    end.

%% Get user's broadcast lists
handle_get_broadcasts(Req, _State) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, UserId} ->
            case aethertalk_group_manager:get_broadcast_lists(UserId) of
                {ok, BroadcastLists} ->
                    Response = jiffy:encode(#{
                        success => true,
                        broadcast_lists => BroadcastLists
                    }),
                    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>},
                                   Response, Req);
                {error, Reason} ->
                    ErrorResponse = jiffy:encode(#{
                        success => false,
                        error => atom_to_binary(Reason, utf8)
                    }),
                    cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                   ErrorResponse, Req)
            end;
        {error, _} ->
            ErrorResponse = jiffy:encode(#{
                success => false,
                error => <<"Unauthorized">>
            }),
            cowboy_req:reply(401, #{<<"content-type">> => <<"application/json">>},
                           ErrorResponse, Req)
    end.

%% Send broadcast message
handle_send_broadcast(Req, _State) ->
    case aethertalk_auth:authenticate_request(Req) of
        {ok, UserId} ->
            BroadcastId = maps:get(broadcast_id, Req),
            
            case cowboy_req:read_body(Req) of
                {ok, Body, Req1} ->
                    case parse_json_body(Body) of
                        {ok, Message} ->
                            case aethertalk_group_manager:send_broadcast(BroadcastId, UserId, Message) of
                                {ok, Result} ->
                                    Response = jiffy:encode(#{
                                        success => true,
                                        result => Result
                                    }),
                                    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>},
                                                   Response, Req1);
                                {error, Reason} ->
                                    ErrorResponse = jiffy:encode(#{
                                        success => false,
                                        error => atom_to_binary(Reason, utf8)
                                    }),
                                    cowboy_req:reply(403, #{<<"content-type">> => <<"application/json">>},
                                                   ErrorResponse, Req1)
                            end;
                        {error, invalid_json} ->
                            ErrorResponse = jiffy:encode(#{
                                success => false,
                                error => <<"Invalid request body">>
                            }),
                            cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                           ErrorResponse, Req1)
                    end;
                {error, _} ->
                    ErrorResponse = jiffy:encode(#{
                        success => false,
                        error => <<"Failed to read request body">>
                    }),
                    cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>},
                                   ErrorResponse, Req)
            end;
        {error, _} ->
            ErrorResponse = jiffy:encode(#{
                success => false,
                error => <<"Unauthorized">>
            }),
            cowboy_req:reply(401, #{<<"content-type">> => <<"application/json">>},
                           ErrorResponse, Req)
    end.

%% Helper functions

parse_create_group_request(Body) ->
    try
        #{<<"name">> := Name, <<"description">> := Description} = jiffy:decode(Body, [return_maps]),
        {ok, Name, Description}
    catch
        _:_ ->
            {error, invalid_body}
    end.

parse_add_member_request(Body) ->
    try
        #{<<"user_id">> := UserId} = jiffy:decode(Body, [return_maps]),
        {ok, UserId}
    catch
        _:_ ->
            {error, invalid_body}
    end.

parse_create_broadcast_request(Body) ->
    try
        #{<<"name">> := Name, <<"member_ids">> := MemberIds} = jiffy:decode(Body, [return_maps]),
        {ok, Name, MemberIds}
    catch
        _:_ ->
            {error, invalid_body}
    end.

parse_json_body(Body) ->
    try
        Data = jiffy:decode(Body, [return_maps]),
        {ok, Data}
    catch
        _:_ ->
            {error, invalid_json}
    end.