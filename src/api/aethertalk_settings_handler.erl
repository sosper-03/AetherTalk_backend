%%%-------------------------------------------------------------------
%% @doc aethertalk_settings_handler - Basic stub implementation
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_settings_handler).

-export([init/2]).

init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Path = cowboy_req:path(Req0),
    
    Response = #{
        success => true,
        message => <<"Handler aethertalk_settings_handler - Method: ", Method/binary, ", Path: ", Path/binary>>,
        timestamp => erlang:system_time(second),
        data => #{}
    },
    
    Req = cowboy_req:reply(200,
        #{<<"content-type">> => <<"application/json">>},
        jsx:encode(Response),
        Req0),
    {ok, Req, State}.
