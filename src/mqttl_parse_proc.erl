%%%-------------------------------------------------------------------
%%% @author Kalin
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 17. Mar 2017 8:14 PM
%%%-------------------------------------------------------------------
-module(mqttl_parse_proc).
-author("Kalin").

-include("mqttl_parsing.hrl").

%% API
-export([start_link/3]).

%%
%% @todo: Do not create a special process for parsing
%%

start_link(ConnPid,ConnMod,Opts) ->
  {ok,spawn_link(fun() -> start_loop(ConnPid,ConnMod,Opts) end)}.

start_loop(ConnPid,ConnMod,Opts) ->
  MaxBuffer = maps:get(buffer_size,Opts,128000),
  S = #parse_state{
    buffer = <<>>,
    max_buffer_size = MaxBuffer,
    readfun = fun recv/1
  },
  loop(ConnPid,ConnMod,S).

loop(ConnPid,ConnMod,S) ->
  case mqttl_parser:parse_packet(S) of
    {ok, P1,S1} ->
      error_logger:info_msg("processing packet ~p~n", [P1]),
      ConnMod:handle_packet(ConnPid,P1),
      loop(ConnPid,ConnMod,S1);
    {error,Reason} ->
      error_logger:info_msg("Parse error ~p~n", [Reason]),
      handle_error(ConnPid,ConnMod,Reason)
  end.

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

%% callback for parser process
recv(MinExpected) ->
  recv(MinExpected,<<>>).

recv(0,Acc) ->
  receive
    {data,Data} ->
      {ok,<<Acc/binary,Data/binary>>};
    _ -> exit(normal)
  end;

recv(MinExpected,Acc) when byte_size(Acc) >= MinExpected ->
  {ok,Acc};

recv(MinExpected,Acc) ->
  receive
    {data,Data} ->
      recv(MinExpected,<<Acc/binary,Data/binary>>);
    _ -> exit(normal)
  end.