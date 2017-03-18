%%%-------------------------------------------------------------------
%%% @author Kalin
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%% Handles MQTT websocket connections, similar to the day mqttl_receiver handles
%%% MQTT TCP connections.
%%% @end
%%% Created : 16. Mar 2017 8:58 PM
%%%-------------------------------------------------------------------
-module(mqttl_ws).
-author("Kalin").

-include("mqttl_packets.hrl").

%% API
-export([init/3, websocket_init/3, send/2, websocket_info/3, websocket_handle/3]).

-record(state,{
  opts,
  conn_mod    ::module(),
  conn_pid    ::pid(),
  parser_pid  ::pid()
}).

%%% ======================================================================
%%% API
%%% ======================================================================
-spec send(Pid::pid(),Packet::mqttl_packet()) -> ok.
send(Pid,Packet) ->
  Pid ! {packet,Packet},
  ok.

%%% ======================================================================
%%% Callbacks
%%% ======================================================================

init(_, _Req, _Opts) ->
  {upgrade, protocol, cowboy_websocket}.

websocket_init(_Type, Req, Opts) ->
  case validate_sec_protocol(Req) of
    error -> {shutdown, Req};
    {ok,Req1} ->
      {_, ConnMod} = lists:keyfind(conn_mod, 1, Opts),
      ConnOpts = proplists:get_value(conn_opts,Opts,#{}),
      {ok,ConnPid} = ConnMod:new_link(?MODULE,self(),ConnOpts),
      {ok,ParserPid} = mqttl_parse_proc:start_link(ConnPid,ConnMod,ConnOpts),
      {ok,Req1,#state{conn_mod = ConnMod,
                      conn_pid = ConnPid,
                      parser_pid = ParserPid}}
  end.

validate_sec_protocol(Req) ->
  case cowboy_req:parse_header(<<"sec-websocket-protocol">>, Req) of
    {ok, undefined, _} ->
      {ok, Req};
    {ok, SubProts, Req2} ->
      case lists:keymember(<<"mqtt">>, 1, SubProts) of
        true ->
          Req3 = cowboy_req:set_resp_header(<<"sec-websocket-protocol">>,<<"mqtt">>,Req2),
          {ok, Req3};
        false ->
          error
      end
  end.

websocket_handle({binary,Frame}, Req, S = #state{parser_pid = ParserPid}) ->
  ParserPid ! {data,Frame},
  {ok, Req, S};


websocket_handle(_Frame, Req, #state{conn_mod = ConnMod,conn_pid = ConnPid}) ->
  ConnMod:bad_packet(ConnPid,undefined),
  {shutdown,Req}.

websocket_info({packet,Packet}, Req, State) ->
  {reply, {binary, mqttl_builder:build_packet(Packet)}, Req, State}.
