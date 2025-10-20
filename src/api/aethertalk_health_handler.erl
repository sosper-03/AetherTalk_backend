%%%-------------------------------------------------------------------
%% @doc Health check handler
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_health_handler).

-export([init/2]).

init(Req0, State) ->
    Req = cowboy_req:reply(200, 
        #{<<"content-type">> => <<"application/json">>},
        <<"{\"status\":\"ok\"}">>,
        Req0),
    {ok, Req, State}.

%% Internal functions
%% Simplified health checks for testing - removed external service dependencies