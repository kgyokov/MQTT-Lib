-module(mqttl_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, start_listener/4, stop_listener/1]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%@todo: wrap the connection process in a callback module (implemented by ConnMod)
start_listener(Transport, TransOpts, ConnMod, ProtoOpts) ->
  TcpProtoOpts = [
    {shutdown,proplists:get_value(shutdown,ProtoOpts,5000)},
    %%{connection_type, supervisor} %% mqtt_ranch_sup is an adaptor for the mqtt_connection_sup
    {connection_type, worker}, %% mqtt_ranch_sup is an adaptor for the mqtt_connection_sup
    %% @todo: Maybe inject this another way
    {conn_mod,ConnMod}
  ],
  NbAcceptors = proplists:get_value(acceptors,ProtoOpts,1000),
  case Transport of
    tcp -> {ok,_} = ranch:start_listener(mqtt_tcp, NbAcceptors, ranch_tcp, TransOpts, mqttl_ranch_sup, TcpProtoOpts);
    _ -> error(protocol_not_implemented)
  end.

stop_listener(Transport) ->
  Ref = case Transport of
          tcp -> mqtt_tcp;
          _ -> error(protocol_not_implemented)
        end,
  ranch:stop_listener(Ref).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok, { {one_for_one, 5, 10}, []} }.

