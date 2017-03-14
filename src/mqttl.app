%%%-------------------------------------------------------------------
%%% @author Kalin
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. Mar 2017 7:59 PM
%%%-------------------------------------------------------------------
{application, mqttl, [
  {description, "MQTT Library"},
  {vsn, "0.0.1"},
  {registered, []},
  {applications, [
    kernel,
    stdlib
  ]},
  {mod, {mqttl, []}},
  {env, []}
]}.