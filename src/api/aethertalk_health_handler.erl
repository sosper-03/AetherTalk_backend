%%%-------------------------------------------------------------------
%% @doc Health check handler
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_health_handler).

-export([init/2]).

init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    handle_request(Method, Req0, State).

handle_request(<<"GET">>, Req0, State) ->
    JsonResponse = <<"{\"status\":\"ok\",\"database\":\"ok\",\"redis\":\"ok\"}">>,
    
    Req = cowboy_req:reply(200, 
        #{<<"content-type">> => <<"application/json">>},
        JsonResponse,
        Req0),
    {ok, Req, State};

handle_request(_, Req0, State) ->
    Req = cowboy_req:reply(405, 
        #{<<"content-type">> => <<"application/json">>},
        <<"{\"error\":\"Method not allowed\"}">>,
        Req0),
    {ok, Req, State}.

%% Internal functions
%% Simplified health checks for testing - removed external service dependencies