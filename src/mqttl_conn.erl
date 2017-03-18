%%%-------------------------------------------------------------------
%%% @author Kalin
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. Mar 2017 8:47 PM
%%%-------------------------------------------------------------------
-module(mqttl_conn).
-author("Kalin").

-include("mqttl_packets.hrl").

%% API
-export([]).

%% @doc
%% Starts a new connection process, passing in a 'Send' module and a 'Send' reference
%% (e.g. mqttl_ws and a Pid of a websocket process)
%% @end
-callback new_link(SendMod::module(),SendRef::any(),Opts::any()) -> {ok,pid()}.

%%todo: Maybe just have the receiver quit and let the mqttl_conn process be killed?
-callback unexpected_disconnect(Pid::any(),Details::any()) -> ok.

%%todo: Maybe just have the receive quit and let the mqttl_conn process be killed?
-callback bad_packet(Pid::pid(),Reason::any()) -> ok.

-callback handle_packet(Pid::pid(),NewPacket::mqttl_packet()) -> ok.
