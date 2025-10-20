%%%-------------------------------------------------------------------
%% @doc Simple test handler
%% @end
%%%-------------------------------------------------------------------

-module(aethertalk_test_handler).

-export([init/2]).

init(Req0, State) ->
    Response = #{
        message => <<"Hello from AetherTalk!">>,
        timestamp => erlang:system_time(second)
    },
    
    Req = cowboy_req:reply(200, 
        #{<<"content-type">> => <<"application/json">>},
        jsx:encode(Response),
        Req0),
    {ok, Req, State}.