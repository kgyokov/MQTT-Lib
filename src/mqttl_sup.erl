-module(mqttl_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, start_listener/5, stop_listener/1]).

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
start_listener(Transport,TransOpts,ConnMod,ConnOpts,ProtoOpts) ->
  InjProtoOpts = [
    {connection_type, worker}, %% mqtt_ranch_sup is an adaptor for the mqtt_connection_sup
    %% @todo: Maybe inject this another way
    {shutdown,proplists:get_value(shutdown,ProtoOpts,5000)},
    %%{connection_type, supervisor} %% mqtt_ranch_sup is an adaptor for the mqtt_connection_sup
    {conn_mod,ConnMod},
    {conn_opts,ConnOpts}
  ],
  NbAcceptors = proplists:get_value(acceptors,ProtoOpts,1000),
  {ok,_} = start(Transport,NbAcceptors,TransOpts,InjProtoOpts).

stop_listener(Transport) ->
  Ref = case Transport of
          tcp   -> mqtt_tcp;
          ssl   -> mqtt_ssl;
          http  -> mqtt_http;
          https -> mqtt_https;
          _ -> error(protocol_not_implemented)
        end,
  ranch:stop_listener(Ref).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok, { {one_for_one, 5, 10}, []} }.

%% ===================================================================
%% PRIVATE
%% ===================================================================

start(tcp,NbAcceptors,TransOpts,InjProtoOpts) ->
  RanchOpts = to_ranch_opts(InjProtoOpts),
  ranch:start_listener(mqtt_tcp, NbAcceptors, ranch_tcp, TransOpts, mqttl_ranch_sup,RanchOpts);

start(ssl,NbAcceptors,TransOpts,InjProtoOpts) ->
  RanchOpts = to_ranch_opts(InjProtoOpts),
  ranch:start_listener(mqtt_ssl, NbAcceptors, ranch_ssl, TransOpts, mqttl_ranch_sup,RanchOpts);

start(http,NbAcceptors,TransOpts,InjProtoOpts) ->
  CowboyOpts = to_cowboy_opts(InjProtoOpts),
  cowboy:start_http(mqtt_http,NbAcceptors,TransOpts,CowboyOpts );

start(https,NbAcceptors,TransOpts,InjProtoOpts) ->
  CowboyOpts = to_cowboy_opts(InjProtoOpts),
  cowboy:start_https(mqtt_https,NbAcceptors,TransOpts,CowboyOpts);

start(_,_,_,_) -> error(protocol_not_implemented).

to_ranch_opts(InjProtoOpts) -> InjProtoOpts.
to_cowboy_opts(InjProtoOpts) -> dispatch(InjProtoOpts).

dispatch(InjProtoOpts) ->
  Dispatch = cowboy_router:compile([
    %% {HostMatch, list({PathMatch, Handler, Opts})}
    {'_', [{"/mqtt", mqttl_ws, InjProtoOpts}]}
  ]),
  [{env, [{dispatch, Dispatch}]}|InjProtoOpts].