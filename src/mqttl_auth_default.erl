%%%-------------------------------------------------------------------
%%% @author Kalin
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%% Authorizes everything
%%% @end
%%% Created : 21. Feb 2015 9:02 PM
%%%-------------------------------------------------------------------
-module(mqttl_auth_default).
-author("Kalin").
-behaviour(mqttl_auth).

%% API
-export([connect/1, subscribe/2, publish/2]).

connect(Packet) -> {ok,Packet,default}.

subscribe(QoS, default) -> QoS.

publish(_Topic, default) -> ok.