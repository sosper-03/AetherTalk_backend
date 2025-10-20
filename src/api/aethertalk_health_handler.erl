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
    Response = #{
        status => <<"ok">>,
        timestamp => erlang:system_time(second),
        version => <<"1.0.0">>,
        services => #{
            database => check_database(),
            redis => check_redis()
        }
    },
    
    Req = cowboy_req:reply(200, 
        #{<<"content-type">> => <<"application/json">>},
        jsx:encode(Response),
        Req0),
    {ok, Req, State};

handle_request(_, Req0, State) ->
    Req = cowboy_req:reply(405, 
        #{<<"content-type">> => <<"application/json">>},
        jsx:encode(#{error => <<"Method not allowed">>}),
        Req0),
    {ok, Req, State}.

%% Internal functions
check_database() ->
    try
        case aethertalk_db:health_check() of
            ok -> <<"ok">>;
            _ -> <<"error">>
        end
    catch
        _:_ -> <<"error">>
    end.

check_redis() ->
    try
        case aethertalk_redis_worker:health_check() of
            ok -> <<"ok">>;
            _ -> <<"error">>
        end
    catch
        _:_ -> <<"error">>
    end.