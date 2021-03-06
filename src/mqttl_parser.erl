%%%-------------------------------------------------------------------
%%% @author Kalin
%%% @copyright (C) 2014, <COMPANY>
%%% @doc
%%% Parses MQTT packets
%%% @end
%%% Created : 04. Dec 2014 9:34 PM
%%%-------------------------------------------------------------------
-module(mqttl_parser).
-author("Kalin").

-include("mqttl_parsing.hrl").
-include("mqttl_packets.hrl").

%% API
-export([parse_packet/1, parse_string/1, parse_variable_length/1]).


%% ========================================================
%% Communication Adaptors
%% ========================================================

read_at_least(#parse_state {buffer =  Buffer, max_buffer_size =  MaxBufferSize},  TotalExpected)
    when TotalExpected + byte_size(Buffer) > MaxBufferSize ->
    throw({error, buffer_overflow });

read_at_least(#parse_state {buffer =  Buffer}, TotalExpected)
    when TotalExpected =<  byte_size(Buffer) ->
    <<Buffer/binary>>;

read_at_least(S = #parse_state {readfun = ReadFun,buffer =  Buffer}, TotalExpected)
    when TotalExpected > byte_size(Buffer)->
    case ReadFun(TotalExpected - byte_size(Buffer)) of
        {ok,NewFragment} ->
            NewBuffer = <<Buffer/binary,NewFragment/binary>>,
            read_at_least( S#parse_state{ buffer = NewBuffer}, TotalExpected); %% append the newly retrieved bytes
        {error,Reason} ->
            throw({error,Reason})
    end.

read(_ReadFun, MaxBufferSize, Buffer) when byte_size(Buffer) > MaxBufferSize  ->
    throw({error, buffer_overflow });
read(ReadFun, _MaxBufferSize, Buffer) ->
    case ReadFun(0) of
        {ok,NewFragment} ->
            <<Buffer/binary,NewFragment/binary>>; %% append the newly retrieved bytes
        {error,Reason} ->
            throw({error,Reason})
    end.

read(S = #parse_state{max_buffer_size = MaxBufferSize, buffer = Buffer, readfun = ReadFun}) ->
    S#parse_state{buffer =  read(ReadFun, MaxBufferSize, Buffer)}.

%% ========================================================
%%      PRIMITIVES:
%%
%%      strings
%%      variable lengths
%%      etc
%% ========================================================

%%[MQTT-1.5.3]
parse_string(#parse_state{buffer = <<0:16,Rest/binary>>}) ->
    {ok, <<>>,Rest};  %% empty string

parse_string(#parse_state{buffer = <<StrLen:16,Str:StrLen/bytes,Rest/binary>>}) ->
    {ok,Str,Rest};

parse_string(S = #parse_state{})-> %
    parse_string(read(S)); %% fallthrough case: not enough data in the buffer

parse_string(<<0:16,Rest/binary>>) ->
    {ok,<<>>,Rest}; %% empty string

parse_string(<<StrLen:16,Str:StrLen/bytes,Rest/binary>>) ->
    {ok,Str,Rest};

parse_string(_PartialString) ->
    {error,incomplete}.

maybe_parse_string(0, Buffer) -> {ok,undefined,Buffer};
maybe_parse_string(1, Buffer) -> parse_string(Buffer).

%%
%% Parses integer using variable length-encoding
%%

parse_variable_length(S) ->
    parse_variable_length(S, 0, 1).

parse_variable_length(S = #parse_state{buffer = <<HasMore:1,Length:7, Rest/binary>>},
                      Sum,
                      Multiplier) ->

    NewSum = Sum + Length * Multiplier,
    if HasMore =:= 1 ->
        parse_variable_length(S#parse_state{buffer = Rest}, NewSum, Multiplier * 128);
        true -> {ok, NewSum, Rest}
    end;

parse_variable_length(S, Sum, Multiplier) ->
    parse_variable_length(read(S), Sum, Multiplier).  %% not enough data in the buffer


%% ========================================================
%% Parsing
%% ========================================================


-spec parse_packet(S::any()) -> {ok, tuple(), #parse_state{}} | {error, any()}.
parse_packet(S)->
    try parse_packet_unsafe(S) of
        {ParsedPacket, NewState} -> {ok,ParsedPacket, NewState}
    catch
        throw:{error,Reason} ->
            {error,Reason}
    end.

parse_packet_unsafe(S = #parse_state{buffer = <<Type:4,Flags:4/bits,Rest/binary>>})->
    %% get the remaining length of the packet
    {ok,Length,Rest1} = parse_variable_length(S#parse_state{buffer = Rest}),
    %% READ the remaining length of the packet
    <<PacketRemainder:Length/bytes,StartOfNextPacket/binary>> = read_at_least(S#parse_state{buffer = Rest1},Length),
    %% parse the entire packet based on type, flags, and all other remaining data
    ParsedPacket = parse_specific_type(Type,Flags,S#parse_state{buffer = PacketRemainder}),
    %% return
    {ParsedPacket, S#parse_state{buffer = StartOfNextPacket}};

%% Insufficient data in Buffer
parse_packet_unsafe(S)->
    parse_packet_unsafe(read(S)).

%% ========================================================
%% CONNECT -- COMPLETE!!!
%% ========================================================

%% MQTT 3.1.2.1 - "The Protocol Name is a UTF-8 encoded string that represents the protocol name “MQTT”, capitalized as shown.
%% The string, its offset and length will not be changed by future versions of the MQTT specification."
parse_specific_type(?CONNECT,
    <<0:4>>,
    S = #parse_state{buffer=
    <<ProtocolNameLen:16,                      %% should be 4 / "MQTT", but according to 3.1.2.1 we may want to give the server
    ProtocolName:ProtocolNameLen/bytes,     %% the option to proceed anyway
    ProtocolLevel:8,
    UsernameFlag:1,PasswordFlag:1,WillRetain:1,WillQoS:2,WillFlag:1,CleanSession:1,_:1,
    KeepAlive:16,
    Payload/binary>>}) ->

    {ok,ClientId,Rest}      = parse_string(S#parse_state{buffer=Payload}), %% 3.1.3.1 does not place strict limitations on the ClientId
    {ok,WillDetails,Rest1}  = maybe_parse_will_details(WillFlag,WillRetain,WillQoS,Rest),
    {ok,Username,Rest2}     = maybe_parse_string(UsernameFlag,Rest1),
    {ok,Password,<<>>}      = maybe_parse_string(PasswordFlag,Rest2),
    #'CONNECT'{
        protocol_name = ProtocolName,
        protocol_version = ProtocolLevel,
        keep_alive = KeepAlive,
        clean_session = CleanSession =:= 1,
        client_id = ClientId,
        will = WillDetails,
        username = Username,
        password = Password
    };


parse_specific_type(?CONNACK, <<0:4>>, #parse_state{buffer = <<0:7,SessionPresent:1,Code:8>>})
    when Code =:= ?CONNACK_ACCEPTED orelse SessionPresent =:= 0 ->
    #'CONNACK'{session_present = SessionPresent =:= 1,return_code = Code};

parse_specific_type(?DISCONNECT,<<0:4>>,_S) ->
    #'DISCONNECT'{};

%% ========================================================
%% PING -- COMPLETE!!!
%% ========================================================
parse_specific_type(?PINGREQ,<<0:4>>,_S) ->
    #'PINGREQ'{};

parse_specific_type(?PINGRESP,<<0:4>>,_S) ->
    #'PINGRESP'{};

%% ========================================================
%% PUBLISH -- COMPLETE!!!
%% ========================================================

parse_specific_type(?PUBLISH,<<Dup:1,QoS:2,Retain:1>>,S) when QoS =< 2 ->

    %% validate flags - @todo: should we do that here? or in the connection process???
    case {Dup,QoS} of
        {1,0} -> throw({error,invalid_flags});
        _     -> ok
    end,

    %#parse_state{buffer = Rest } = S,
    {ok,Topic,Rest1} = parse_string(S),
    {PacketId,Content} =
        if QoS =:= 1; QoS =:= 2 ->
            <<PacketId1:16,Content1/binary>> = Rest1,
            {PacketId1,Content1};
            true ->
                {undefined,Rest1}
        end,

    #'PUBLISH'{
        qos = QoS,
        dup = Dup =:= 1,
        retain = Retain =:= 1,
        topic = Topic,
        content = Content,
        packet_id = PacketId
    };

parse_specific_type(?PUBACK, <<0:4>>,#parse_state{buffer = <<PacketId:16>>}) ->
    #'PUBACK'{packet_id = PacketId};

parse_specific_type(?PUBREC, <<0:4>>,#parse_state{buffer = <<PacketId:16>>}) ->
    #'PUBREC'{packet_id = PacketId};

parse_specific_type(?PUBREL, <<2:4>>,#parse_state{buffer = <<PacketId:16>>}) ->
    #'PUBREL'{packet_id = PacketId};

parse_specific_type(?PUBCOMP, <<0:4>>,#parse_state{buffer = <<PacketId:16>>}) ->
    #'PUBCOMP'{packet_id = PacketId};

%% ========================================================
%% SUBSCRIPTIONS - COMPLETE!!!
%% ========================================================

parse_specific_type(?SUBSCRIBE, <<2:4>>, #parse_state{buffer = <<PacketId:16, Rest/binary>>}) ->
    Subscriptions = lists:reverse(parse_subs(Rest)),
    #'SUBSCRIBE'{
        packet_id = PacketId,
        subscriptions = Subscriptions
    };

parse_specific_type(?SUBACK, <<0:4>>, #parse_state{buffer = <<PacketId:16, Rest/binary>>}) ->
    ReturnCodes = lists:reverse(parse_codes(Rest)),
    #'SUBACK'{
        packet_id = PacketId,
        return_codes = ReturnCodes
    };

parse_specific_type(?UNSUBSCRIBE, <<2:4>>, #parse_state{buffer = <<PacketId:16, Rest/binary>>}) ->
    Topics = lists:reverse(parse_topics(Rest)),
    #'UNSUBSCRIBE'{
        packet_id = PacketId,
        topic_filters = Topics
    };

parse_specific_type(?UNSUBACK, <<0:4>>, #parse_state{buffer = <<PacketId:16>>}) ->
    #'UNSUBACK'{packet_id = PacketId};

parse_specific_type(_Type,_Flags,_State) ->
    throw({error,malformed_packet}).


%% ========================================================
%% Parse helpers
%% ========================================================

parse_codes(Buffer) -> parse_codes(Buffer,[]).
parse_codes(<<>>, Codes) -> Codes;
parse_codes(<<Code:8,Rest/binary>>,Codes) -> parse_codes(Rest,[Code|Codes]).

parse_topics(Buffer) ->
    parse_topics(Buffer,[]).

parse_topics(_Buffer = <<>>,Topics) ->
    Topics;

parse_topics(<<TopicLen:16,Topic:TopicLen/bytes,Rest/binary>>,Topics) ->
    parse_topics(Rest,[Topic|Topics]).

parse_subs(Buffer) ->
    parse_subs(Buffer,[]).

parse_subs(_Buffer = <<>>,[]) ->
    throw({error,protocol_violation});

parse_subs(_Buffer = <<>>,Subscriptions) ->
    Subscriptions;

parse_subs(<<TopicLen:16,Topic:TopicLen/bytes,0:6,QoS:2,Rest/binary>>,
    Subscriptions) when QoS =<2 ->
    parse_subs(Rest,[{Topic,QoS}|Subscriptions]);

parse_subs(_Buffer, _Subscriptions) ->
    throw({error,malformed_packet}).

%% If the Will Flag is set to 0, then the Will QoS MUST be set to 0 (0x00) [MQTT-3.1.2-13]
maybe_parse_will_details(_WillFlag = 0,_WillRetain,_WillQoS = 0,Buffer) ->
    {ok,undefined,Buffer};

maybe_parse_will_details(_WillFlag = 1,WillRetain,WillQoS,Buffer) when WillQoS =< 2 ->
    {ok,WillTopic,Rest1}   =  parse_string(Buffer),
    {ok,WillMessage,Rest2} =  parse_string(Rest1),
    {
        ok,
        #will_details{
            retain = WillRetain =:= 1,
            qos = WillQoS,
            content = WillMessage,
            topic = WillTopic
        },
        Rest2
    }.


