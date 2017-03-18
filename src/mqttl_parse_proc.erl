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
  #{buffer_size := BufferSize} = Opts,
  %% calback for the parser process to get new data
  ReadFun =
    fun(ExpectedSize) ->
      receive_data(ExpectedSize)
    end,

  ParseState = #parse_state{
    buffer = <<>>,
    max_buffer_size = BufferSize,
    readfun =  ReadFun
  },
  loop_over_socket(ConnPid,ConnMod,ParseState).

loop_over_socket(ConnPid,ConnMod,ParseState) ->
  case mqttl_parser:parse_packet(ParseState) of
    {ok, NewPacket,NewParseState} ->
      error_logger:info_msg("processing packet ~p~n", [NewPacket]),
      ConnMod:handle_packet(ConnPid,NewPacket),
      loop_over_socket(ConnPid,ConnMod,NewParseState);
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
receive_data(MinExpected) ->
  receive_data(MinExpected,<<>>).

receive_data(0,Acc) ->
  receive
    {data,Data} ->
      {ok,<<Acc/binary,Data/binary>>};
    _ -> exit(normal)
  end;

receive_data(MinExpected,Acc) when byte_size(Acc) >= MinExpected ->
  {ok,Acc};

receive_data(MinExpected,Acc) ->
  receive
    {data,Data} ->
      receive_data(MinExpected,<<Acc/binary,Data/binary>>);
    _ -> exit(normal)
  end.