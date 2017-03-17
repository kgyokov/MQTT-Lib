%%%-------------------------------------------------------------------
%%% @author Kalin
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%% Authentication / Authroization behavior
%%% @end
%%% Created : 04. Feb 2015 11:11 PM
%%%-------------------------------------------------------------------
-module(mqttl_auth).
-author("Kalin").

-include("mqttl_packets.hrl").

-callback connect(Configuration::any(),Packet::#'CONNECT'{}) ->
    {ok, AuthCtx::any()}     %% AuthCtx can contain things like claims, etc.
    |{error,Reason::bad_credentials | any()}.     %% error, e.g. invalid password

-callback subscribe({Filter::any(),QoS::qos()},AuthCtx::any()) ->
    ok | {error,Reason::any()}.

-callback publish({Topic::any(),Qos::qos()},AuthCtx::any()) ->
    ok | {error,Reason::any()}.

