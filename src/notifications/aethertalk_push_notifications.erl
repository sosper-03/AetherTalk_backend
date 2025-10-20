-module(aethertalk_push_notifications).

-export([
    send_call_notification/4,
    send_message_notification/3,
    send_group_notification/3,
    register_device/3,
    unregister_device/2
]).

%% Send call notification
send_call_notification(UserId, CallerId, CallType, CallId) ->
    lager:info("Sending call notification to user ~p from caller ~p", [UserId, CallerId]),
    
    % Get user's device tokens
    case get_user_device_tokens(UserId) of
        {ok, Tokens} when length(Tokens) > 0 ->
            Payload = #{
                type => call,
                call_id => CallId,
                caller_id => CallerId,
                call_type => CallType,
                timestamp => aethertalk_utils:get_current_timestamp()
            },
            send_to_devices(Tokens, Payload);
        {ok, []} ->
            lager:warning("No device tokens found for user ~p", [UserId]),
            {error, no_devices};
        {error, Reason} ->
            lager:error("Failed to get device tokens for user ~p: ~p", [UserId, Reason]),
            {error, Reason}
    end.

%% Send message notification
send_message_notification(UserId, SenderId, MessageContent) ->
    lager:info("Sending message notification to user ~p from sender ~p", [UserId, SenderId]),
    
    case get_user_device_tokens(UserId) of
        {ok, Tokens} when length(Tokens) > 0 ->
            Payload = #{
                type => message,
                sender_id => SenderId,
                content => MessageContent,
                timestamp => aethertalk_utils:get_current_timestamp()
            },
            send_to_devices(Tokens, Payload);
        {ok, []} ->
            {error, no_devices};
        {error, Reason} ->
            {error, Reason}
    end.

%% Send group notification
send_group_notification(GroupId, SenderId, NotificationType) ->
    lager:info("Sending group notification for group ~p from sender ~p", [GroupId, SenderId]),
    
    case get_group_member_tokens(GroupId) of
        {ok, Tokens} when length(Tokens) > 0 ->
            Payload = #{
                type => group,
                group_id => GroupId,
                sender_id => SenderId,
                notification_type => NotificationType,
                timestamp => aethertalk_utils:get_current_timestamp()
            },
            send_to_devices(Tokens, Payload);
        {ok, []} ->
            {error, no_devices};
        {error, Reason} ->
            {error, Reason}
    end.

%% Register device token for push notifications
register_device(UserId, DeviceToken, Platform) ->
    lager:info("Registering device token for user ~p on platform ~p", [UserId, Platform]),
    
    Query = "INSERT INTO push_subscriptions (user_id, device_token, platform, created_at) 
             VALUES ($1, $2, $3, NOW()) 
             ON CONFLICT (user_id, device_token) 
             DO UPDATE SET platform = $3, updated_at = NOW()",
    
    case aethertalk_db:query(Query, [UserId, DeviceToken, Platform]) of
        {ok, _} ->
            lager:info("Device token registered successfully for user ~p", [UserId]),
            ok;
        {error, Reason} ->
            lager:error("Failed to register device token for user ~p: ~p", [UserId, Reason]),
            {error, Reason}
    end.

%% Unregister device token
unregister_device(UserId, DeviceToken) ->
    lager:info("Unregistering device token for user ~p", [UserId]),
    
    Query = "DELETE FROM push_subscriptions WHERE user_id = $1 AND device_token = $2",
    
    case aethertalk_db:query(Query, [UserId, DeviceToken]) of
        {ok, _} ->
            lager:info("Device token unregistered successfully for user ~p", [UserId]),
            ok;
        {error, Reason} ->
            lager:error("Failed to unregister device token for user ~p: ~p", [UserId, Reason]),
            {error, Reason}
    end.

%% Private functions

%% Get device tokens for a user
get_user_device_tokens(UserId) ->
    Query = "SELECT device_token, platform FROM push_subscriptions WHERE user_id = $1 AND active = true",
    
    case aethertalk_db:query(Query, [UserId]) of
        {ok, Rows} ->
            Tokens = [#{token => Token, platform => Platform} || {Token, Platform} <- Rows],
            {ok, Tokens};
        {error, Reason} ->
            {error, Reason}
    end.

%% Get device tokens for all members of a group
get_group_member_tokens(GroupId) ->
    Query = "SELECT DISTINCT ps.device_token, ps.platform 
             FROM push_subscriptions ps 
             JOIN group_members gm ON ps.user_id = gm.user_id 
             WHERE gm.group_id = $1 AND ps.active = true",
    
    case aethertalk_db:query(Query, [GroupId]) of
        {ok, Rows} ->
            Tokens = [#{token => Token, platform => Platform} || {Token, Platform} <- Rows],
            {ok, Tokens};
        {error, Reason} ->
            {error, Reason}
    end.

%% Send notification to multiple devices
send_to_devices(Tokens, Payload) ->
    lager:info("Sending notification to ~p devices", [length(Tokens)]),
    
    Results = lists:map(fun(TokenInfo) ->
        send_to_device(TokenInfo, Payload)
    end, Tokens),
    
    SuccessCount = length([R || R <- Results, R =:= ok]),
    FailureCount = length(Results) - SuccessCount,
    
    lager:info("Notification sent: ~p successful, ~p failed", [SuccessCount, FailureCount]),
    
    case FailureCount of
        0 -> ok;
        _ -> {partial_success, SuccessCount, FailureCount}
    end.

%% Send notification to a single device
send_to_device(#{token := Token, platform := Platform}, Payload) ->
    case Platform of
        <<"android">> -> send_fcm_notification(Token, Payload);
        <<"ios">> -> send_apns_notification(Token, Payload);
        _ -> 
            lager:warning("Unsupported platform: ~p", [Platform]),
            {error, unsupported_platform}
    end.

%% Send FCM notification (Android)
send_fcm_notification(Token, Payload) ->
    lager:info("Sending FCM notification to token ~p", [Token]),
    
    % This is a placeholder implementation
    % In a real implementation, you would use the FCM HTTP v1 API
    case send_http_notification("https://fcm.googleapis.com/fcm/send", Token, Payload) of
        ok -> 
            lager:info("FCM notification sent successfully"),
            ok;
        {error, Reason} ->
            lager:error("Failed to send FCM notification: ~p", [Reason]),
            {error, Reason}
    end.

%% Send APNS notification (iOS)
send_apns_notification(Token, Payload) ->
    lager:info("Sending APNS notification to token ~p", [Token]),
    
    % This is a placeholder implementation
    % In a real implementation, you would use the APNS HTTP/2 API
    case send_http_notification("https://api.push.apple.com/3/device/" ++ Token, Token, Payload) of
        ok -> 
            lager:info("APNS notification sent successfully"),
            ok;
        {error, Reason} ->
            lager:error("Failed to send APNS notification: ~p", [Reason]),
            {error, Reason}
    end.

%% Send HTTP notification (placeholder implementation)
send_http_notification(Url, Token, Payload) ->
    lager:info("Sending HTTP notification to ~p", [Url]),
    
    % This is a simplified implementation
    % In production, you would use proper HTTP client with authentication
    Headers = [
        {"Content-Type", "application/json"},
        {"Authorization", "key=your-server-key"}
    ],
    
    Body = jsx:encode(#{
        to => Token,
        data => Payload,
        notification => #{
            title => maps:get(type, Payload, <<"AetherTalk">>),
            body => format_notification_body(Payload)
        }
    }),
    
    case hackney:post(Url, Headers, Body, []) of
        {ok, 200, _Headers, _Body} -> ok;
        {ok, StatusCode, _Headers, ResponseBody} ->
            lager:error("HTTP notification failed with status ~p: ~p", [StatusCode, ResponseBody]),
            {error, {http_error, StatusCode}};
        {error, Reason} ->
            lager:error("HTTP notification request failed: ~p", [Reason]),
            {error, Reason}
    end.

%% Format notification body based on payload type
format_notification_body(#{type := call, caller_id := CallerId}) ->
    iolist_to_binary(["Incoming call from ", CallerId]);
format_notification_body(#{type := message, sender_id := SenderId}) ->
    iolist_to_binary(["New message from ", SenderId]);
format_notification_body(#{type := group, notification_type := Type}) ->
    iolist_to_binary(["Group ", atom_to_list(Type)]);
format_notification_body(_) ->
    <<"New notification">>.