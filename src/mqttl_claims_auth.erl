%%%-------------------------------------------------------------------
%%% @author Kalin
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%% Claims-based authentication/authorization
%%% @end
%%% Created : 04. Feb 2015 11:33 PM
%%%-------------------------------------------------------------------
-module(mqttl_claims_auth).
-author("Kalin").

-include("mqttl_packets.hrl").

-behaviour(mqttl_auth).

%%%===================================================================
%%% API
%%%===================================================================
-export([connect/2, subscribe/2, publish/2]).


connect(Configuration,#'CONNECT'{client_id = ClientId,username = Username, password = Password}) ->
    try
        [case ClaimsGenerator:get_claims(Options,ClientId,Username,Password) of
             {ok,Claims}     ->  Claims;
             {error,Reason}  ->  throw({auth_error,Reason})
         end
            || {ClaimsGenerator,Options} <- Configuration
        ] of ClaimsLists ->
        lists:foldl(fun merge_claims/2,{[],[]},ClaimsLists)
    catch
        throw:{auth_error,Reason}   ->
            {error,Reason}
    end.

subscribe(NewSub, {_,Sub}) ->
    authorize(NewSub,Sub).

publish(TandQoS, {Pub}) ->
    authorize(TandQoS,Pub).

authorize(FandQoS, {_,Sub}) ->
    case lists:any(fun(S) -> mqttl_topic:is_covered_by(FandQoS,S) end, Sub) of
        true  -> ok;
        false -> {error,unauthroized}
    end.

%%%===================================================================
%%% Internal functions
%%%===================================================================

merge_claims({Pub1,Sub1},{Pub2,Sub2}) ->
    {mqttl_topic:min_cover(Pub1++Pub2),
     mqttl_topic:min_cover(Sub1++Sub2)}.



