#!/bin/bash

# List of handlers to create
handlers=(
    "aethertalk_user_handler"
    "aethertalk_contact_handler"
    "aethertalk_settings_handler"
    "aethertalk_chat_handler"
    "aethertalk_message_handler"
    "aethertalk_media_handler"
    "aethertalk_group_handler"
    "aethertalk_group_member_handler"
    "aethertalk_call_handler"
    "aethertalk_call_join_handler"
    "aethertalk_media_upload_handler"
    "aethertalk_media_download_handler"
    "aethertalk_status_handler"
    "aethertalk_notification_handler"
)

for handler in "${handlers[@]}"; do
    cat > "src/api/${handler}.erl" << EOF
%%%-------------------------------------------------------------------
%% @doc ${handler} - Basic stub implementation
%% @end
%%%-------------------------------------------------------------------

-module(${handler}).

-export([init/2]).

init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Path = cowboy_req:path(Req0),
    
    Response = #{
        success => true,
        message => <<"Handler ${handler} - Method: ", Method/binary, ", Path: ", Path/binary>>,
        timestamp => erlang:system_time(second),
        data => #{}
    },
    
    Req = cowboy_req:reply(200,
        #{<<"content-type">> => <<"application/json">>},
        jsx:encode(Response),
        Req0),
    {ok, Req, State}.
EOF
    echo "Created ${handler}.erl"
done

echo "All handlers created successfully!"