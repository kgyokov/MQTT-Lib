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

%% API
-export([init/3, websocket_init/3, send/2, websocket_info/3, websocket_handle/3]).

-record(state,{
  opts,
  conn_mod    ::module(),
  conn_pid    ::pid(),
  buffer      ::
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
      {ok,ConnPid} = ConnMod:new_link(?MODULE,self(),Opts),
      {ok, Req1, #state{conn_mod = ConnMod,conn_pid = ConnPid}}
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

websocket_handle({binary,Frame}, Req, S = #state{conn_mod = ConnMod,
                                                 conn_pid = ConnPid,
                                                 buffer = Buffer}) ->
  {Packets,Buffer1} = handle_binary_frame(Frame,Buffer),
  Parsed = [mqttl_parser:parse_packet(P) || P <- Packets],
  Errors = [Reason || {error,Reason} <- Parsed],
  case Errors of
    [] ->
      [ConnMod:handle_packet(ConnPid,P) ||P <- Parsed],
      {ok, Req, S#state{buffer = Buffer1}};
    [Reason|_] ->
      handle_error(ConnPid,ConnMod,Reason),
      {shutdown,Req}
  end;


websocket_handle(_Frame, _Req, S = #state{conn_mod = ConnMod,conn_pid = ConnPid}) ->
  handle_error(ConnPid,ConnMod,malformed_packet).


handle_error(ConnPid, ConnMod, Reason) ->
  case Reason of
    invalid_flags ->
      ConnMod:bad_packet(ConnPid,invalid_flags);
    malformed_packet ->
      ConnMod:bad_packet(ConnPid,undefined);
    {unexpected_disconnect,Details} ->
      ConnMod:unexpected_disconnect(ConnPid,Details)
    %% @todo: More errors
  end.


handle_binary_frame(Frame,idle) -> ok;
handle_binary_frame(Frame,{Current,Expecting}) -> ok.


websocket_info({packet,Packet}, Req, State) ->
  {reply, {binary, mqttl_builder:build_packet(Packet)}, Req, State}.
