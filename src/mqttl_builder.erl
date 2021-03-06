%%%-------------------------------------------------------------------
%%% @author Kalin
%%% @copyright (C) 2014, <COMPANY>
%%% @doc
%%% Build MQTT packages
%%% @end
%%% Created : 15. Dec 2014 9:34 PM
%%%-------------------------------------------------------------------
-module(mqttl_builder).
-author("Kalin").

-define(FLAG(Flag), (case Flag of true -> 1; false -> 0 end):1).

-include("mqttl_packets.hrl").
-include("mqttl_parsing.hrl").
%% API
-export([build_packet/1, build_string/1, build_var_length/1]).

build_packet(Packet) ->
    Rest = list_to_binary([build_rest(Packet)]),
    <<(build_packet_type(Packet)):4,(build_flags(Packet))/bits,
       (build_var_length(byte_size(Rest)))/binary,
        Rest/binary>>.

build_flags(Packet) ->
    case Packet of
        #'SUBSCRIBE'{}      ->  <<2#0010:4>>;
        #'UNSUBSCRIBE'{}    ->  <<2#0010:4>>;
        #'PUBREL'{}         ->  <<2#0010:4>>;
        #'PUBLISH' { qos = QoS, dup = Dup, retain = Retain } ->
            <<?FLAG(Dup),QoS:2,?FLAG(Retain)>>;
        _ -> <<0:4>>
    end.

build_packet_type(Packet)->
    case Packet of
        #'CONNECT'{}    -> ?CONNECT;
        #'CONNACK'{}    -> ?CONNACK;
        #'PUBLISH'{}    -> ?PUBLISH;
        #'PUBACK'{}     -> ?PUBACK;
        #'PUBREC'{}     -> ?PUBREC;
        #'PUBREL'{}     -> ?PUBREL;
        #'PUBCOMP'{}    -> ?PUBCOMP;
        #'SUBSCRIBE'{}  -> ?SUBSCRIBE;
        #'SUBACK'{}     -> ?SUBACK;
        #'UNSUBSCRIBE'{}-> ?UNSUBSCRIBE;
        #'UNSUBACK'{}   -> ?UNSUBACK;
        #'PINGREQ'{}    -> ?PINGREQ;
        #'PINGRESP'{}   -> ?PINGRESP;
        #'DISCONNECT'{} -> ?DISCONNECT
    end.


build_rest(#'CONNECT'{
    client_id = ClientId,
    username = Username,
    password = Password,
    protocol_name = ProtocolName,
    protocol_version = ProtocolVersion,
    will = WillDetails,
    clean_session = CleanSession,
    keep_alive = KeepAlive
})->
    %% Validation
    case {ProtocolName,ProtocolVersion} of
        {<<"MQTT">>,4} -> ok;
        _ -> throw(unknown_protocol_and_version)
    end,

    <<
    (build_string(ProtocolName))/binary,
    ProtocolVersion:8,
    %% Flags
    (maybe_flag(Username))/bits,
    (maybe_flag(Password))/bits,

    (case WillDetails of
         undefined -> <<0:4>>;
         #will_details{retain = WillRetain,qos = WillQos} ->
             <<?FLAG(WillRetain),WillQos:2,1:1>>
     end)/bits,

    ?FLAG(CleanSession),
    0:1, %Reserved

    KeepAlive:16,

    %% Payload
    (build_string(ClientId))/binary,
    (case WillDetails of
         undefined ->
             <<>>;
         #will_details{topic = WillTopic, content = WillMessage} ->
             <<(build_string(WillTopic))/binary,(build_string(WillMessage))/binary>>
     end)/binary,
    (maybe_build_string(Username))/binary,
    (maybe_build_string(Password))/binary
    >>;

%%--------------------------------------------------------
%% CONNACK
%%--------------------------------------------------------
build_rest(#'CONNACK'{session_present = SessionPresent, return_code = ReturnCode})->
    <<
    0:7,
    (case ReturnCode of
         ?CONNACK_ACCEPTED ->
             case SessionPresent of
                 true   -> 1;
                 false  -> 0
             end;
         _ -> 0
    end):1,
    ReturnCode:8
    >>;

%%--------------------------------------------------------
%% PUBLISH
%%--------------------------------------------------------
%% PacketId used with Qos = 1 or 2
build_rest(#'PUBLISH'{
    packet_id = PacketId,
    qos = QoS,
    topic = Topic,
    content = Content}) when (QoS =:= ?QOS_1 orelse
                              QoS =:= ?QOS_2)
                             andalso is_integer(PacketId) ->
    <<(build_string(Topic))/binary,
    PacketId:16,
    Content/binary>>;

build_rest(#'PUBLISH'{
    qos = QoS,
    topic = Topic,
    content = Content}) when QoS =:= ?QOS_0 ->
    <<(build_string(Topic))/binary,
    Content/binary>>;


build_rest(#'PUBACK'{packet_id = PacketId})-> <<PacketId:16>>;
build_rest(#'PUBREC'{packet_id = PacketId})-> <<PacketId:16>>;
build_rest(#'PUBREL'{packet_id = PacketId})-> <<PacketId:16>>;
build_rest(#'PUBCOMP'{packet_id = PacketId})-> <<PacketId:16>>;

%%% @todo: maybe build binaries more efficiently than lists:map)

%%--------------------------------------------------------
%% Subscriptions
%%--------------------------------------------------------
build_rest(#'SUBSCRIBE'{packet_id = PacketId, subscriptions = Subscriptions})->
    [<<PacketId:16>> |
        [[build_string(Topic),<<0:6,QoS:2>>] || {Topic,QoS} <- Subscriptions]
    ];

build_rest(#'SUBACK'{packet_id = PacketId, return_codes = ReturnCodes})->
    [<<PacketId:16>> |
        [<<Code:8>> || Code <- ReturnCodes]
    ];


build_rest(#'UNSUBSCRIBE'{packet_id = PacketId, topic_filters = TopicFilters})->
    [<<PacketId:16>> |
        [build_string(Filter) || Filter <- TopicFilters]
    ];

build_rest(#'UNSUBACK'{packet_id = PacketId}) ->
    <<PacketId:16>>;

%%--------------------------------------------------------
%% PING
%%--------------------------------------------------------
build_rest(#'PINGREQ'{})  -> <<>>;
build_rest(#'PINGRESP'{}) -> <<>>;
%%--------------------------------------------------------
%% Misc
%%--------------------------------------------------------
build_rest(#'DISCONNECT'{}) -> <<>>.


%%=========================================================
%%
%% HELPERS
%%
%%=========================================================
maybe_build_string(undefined)   ->   <<>>;
maybe_build_string(S)           ->  build_string(S).

build_string(S) when is_list(S) ->  build_string(list_to_binary(S));
build_string(<<S/binary>>)      ->  <<(byte_size(S)):16,S/binary>>.

build_var_length(Length) ->
    build_var_length(Length,<<>>).

build_var_length(_Length,Acc) when byte_size(Acc) >= 4 ->
    throw(variable_length_too_large);

build_var_length(Length,Acc)->
    NextLength = Length bsr 7,
    case NextLength of
        0 -> <<Acc/binary,0:1,Length:7>>;
        _ -> build_var_length(NextLength,<<Acc/binary,1:1,Length:7>>)
    end.

maybe_flag(undefined)   ->    <<0:1>>;
maybe_flag(_)           ->    <<1:1>>.