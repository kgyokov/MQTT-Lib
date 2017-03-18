%%%-------------------------------------------------------------------
%%% @author Kalin
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% gen_server to parse incoming packets and forward them to the connection process
%%%
%%% @end
%%% Created : 26. Jan 2015 10:13 PM
%%%-------------------------------------------------------------------
-module(mqttl_receiver).
-author("Kalin").

-include("mqttl_parsing.hrl").

-behaviour(gen_server).

%% API
-export([start_link/2]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).


-record(state, {
    socket,
    transport,
    opts,
    conn_mod    ::module(),
    conn_pid    ::pid(),
    parser_pid  ::pid()
}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(
    {Transport :: any(),Ref :: ranch:ref(), Socket :: any(),ConnMod::module()},
    Options :: [any()]
) ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(TRS,Options) ->
    gen_server:start_link(?MODULE, [TRS, Options], []).

%%disconnect(Pid) ->
%%    gen_server:cast(Pid,disconnect).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init([{Transport,Ref,Socket,ConnMod},Opts]) ->
    process_flag(trap_exit,true),
    self() ! {async_init,Ref,Opts},
    S = #state{socket = Socket,transport = Transport,conn_mod = ConnMod},
    {ok, S}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).

handle_cast(_Request, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).

handle_info({'EXIT',ParserPid, Reason},S = #state{conn_mod = ConnMod,
                                                  parser_pid = ParserPid,
                                                  conn_pid = ConnPid}) ->
    ConnMod:unexpected_disconnect(ConnPid,Reason),
    {stop, normal, S};

handle_info({async_init,Ref,Opts},S = #state{transport = Transport,
                                             socket = Socket,
                                             conn_mod = ConnMod}) ->
    ConnOpts = proplists:get_value(conn_opts,Opts,[]),
    {ok,ConnPid} = ConnMod:new_link(Transport,Socket,ConnOpts),
    error_logger:info_msg("Connection Process ~p started",[ConnPid]),
    ok = ranch:accept_ack(Ref),
    ok = Transport:setopts(Socket, [{active, once}]),
    {ok,ParserPid} = mqttl_parse_proc:start_link(ConnPid,ConnMod,ConnOpts),
    {noreply, S#state{conn_pid = ConnPid,
                      parser_pid = ParserPid}};

handle_info({tcp, Socket, Data}, S = #state{socket = Socket, transport = Transport, parser_pid = ParserPid}) ->
    Transport:setopts(Socket, [{active, once}]),
    error_logger:info_msg("received data ~p",[Data]),
    ParserPid ! {data,Data},
    {noreply, S};

handle_info({tcp_closed, Socket}, S = #state{conn_pid = ConnPid,
                                             conn_mod = ConnMod,
                                             socket = Socket}) ->
    ConnMod:unexpected_disconnect(ConnPid,closed),
    {stop, tcp_closed, S};

handle_info({tcp_error, Socket, Reason},  S = #state{conn_pid = ConnPid,
                                                     conn_mod = ConnMod,
                                                     socket = Socket}) ->
    ConnMod:unexpected_disconnect(ConnPid,Reason),
    {stop, tcp_error, S};

handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State = #state{transport = Transport, socket = Socket}) ->
    error_logger:info_msg("Receiver shutting down ~p~n", [_Reason]),
    Transport:close(Socket),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================


