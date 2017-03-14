%%%-------------------------------------------------------------------
%%% @author Kalin
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%  Simple Adaptor mapping ranch_protocol to mqttl_receiver
%%% @end
%%% Created : 20. Feb 2015 12:40 AM
%%%-------------------------------------------------------------------
-module(mqttl_ranch_sup).
-author("Kalin").

-behaviour(ranch_protocol).

%% API
-export([start_link/4]).

start_link(Ref, Socket, Transport, Opts) ->
    %%@todo: Maybe inject this another way?
    ConnMod = proplists:get_value(conn_mod,Opts),
    TRSC = {Transport,Ref,Socket,ConnMod},
    mqttl_receiver:start_link(TRSC,Opts).
