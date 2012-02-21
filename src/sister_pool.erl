-module(sister_pool).

-behaviour(gen_server).

%% API
-export([follow/1,
         follow/2,
         follow/3,
         start_link/1,
         stop/0]).

%% gen_server callbacks
-export([code_change/3,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         init/1,
         terminate/2]).

-define(MAX_USERS_PER_CONN, 25).

-record(state, {max_conns          :: pos_integer(),
                stopped=false      :: boolean(),
                workers=dict:new() :: dict:dictionary()}).

%% ===================================================================
%% API functions
%% ===================================================================

-spec follow (list(nonempty_string()))
             -> ok | {error, Reason::term()}.
follow(UserIds) ->
    NoOp = fun(_) -> ok end,
    follow(UserIds, NoOp, NoOp).

-spec follow (list(nonempty_string()), pid())
             -> ok | {error, Reason::term()}.
follow(UserIds, Pid) when is_pid(Pid) ->
    FStream = fun(Bin) -> Pid ! {stream, Bin} end,
    FError = fun(Resp) -> Pid ! {error, Resp} end,
    follow(UserIds, FStream, FError).

-spec follow (list(nonempty_string()), function(), function())
             -> ok | {error, Reason::term()}.
follow([], _, _) ->
    ok;
follow(UserIds, FStream, FError) when is_list(UserIds) ->
    gen_server:call(?MODULE, {follow, UserIds, FStream, FError}).

start_link(MaxSize) ->
    process_flag(trap_exit, true),
    gen_server:start_link({local, ?MODULE}, ?MODULE, [MaxSize], []).

stop() ->
    gen_server:call(?MODULE, stop).

%% ===================================================================
%% gen_server callbacks
%% ===================================================================

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

handle_call({follow, UserIds, FStream, FError}, _From, State) ->
    follow(UserIds, FStream, FError, State);
handle_call(stop, _From, State) ->
    {stop, normal, State}.

%% add uids to underutilized workers until they are all full
%% add workers until we run out of uids
%% grab the worker following the least ids
%% if that worker is following 25 ids, start a new one
%% otherwise reconnect that worker with one more id

%% error if the number of uids requested plus the number already followed is > 25,000
%% sort workers based on utilization
follow(Uids, FStream, FError, State) ->
    {State, RestUids, FailedUids} = fill_workers(Uids, State),
    {State, RestUids, FailedUids} = start_workers(Uids, FStream, FError, State),
    {ok, {RestUids, FailedUids}, State}.

fill_workers(Uids, State) ->
    F = fun({_,UidsA}, {_,UidsB}) -> length(UidsA) =< length(UidsB) end,
    Workers = lists:sort(dict:to_list(State#state.workers)),
    fill_workers(State, Uids, [], Workers).

fill_workers([], FailedUids, State, Workers) ->
    {State, [], FailedUids};
fill_workers(RestUids, FailedUids, State, Workers) ->
    % pop first worker
    [{Pid,Uids}|Rest] = Workers,
    % if full, give up
    if
        length(Uids) >= ?MAX_USERS_PER_CONN ->
            Workers1 = lists:append(Rest, [{Pid,Uids}]),
            fill_workers(Workers1, RestUids, FailedUids);
        true ->
            {[], 

            
            
    % otherwise, reconnect
    % if reconnect fail, add failed uids to failed uid list and move on
    % otherwise, add to end of worker list and move on

-spec follow (list(nonempty_string()), fun(), fun(), #state{})
             -> ok | {error, Reason::term()}.
follow(Uids, FStream, FError, State) ->
    #state{max_conns=MaxConns, workers=Workers} = State,
    F = fun({_,UidsA}, {_,UidsB}) -> length(UidsA) =< length(UidsB) end,
    WorkerList = dict:to_list(Workers),
    {Pid, OldUids} = hd(lists:sort(F, WorkerList)),
    Uids1 = Uids ++ OldUids,
    if
        length(WorkerList) == 0 ->
            follow_start(Uids1, FStream, FError, State);
        length(WorkerList) =< MaxConns,
        length(Uids1) < ?MAX_USERS_PER_CONN ->
            follow_reconnect(Pid, Uids1, State);
        length(WorkerList) < MaxConns ->
            follow_start(Uids1, FStream, FError, State);
        true ->
            {ok, {error, too_many_connections}, State}
    end.

follow_reconnect(WorkerPid, UserIds, State) ->
    metal:info("Reconnecting worker ~p", [WorkerPid]),
    case sister_worker:reconnect(WorkerPid, UserIds, State) of
        ok ->
            Workers = dict:store(WorkerPid, UserIds, State#state.workers),
            {ok, ok, State#state{workers=Workers}};
        {error, Reason} ->
            {ok, {error, Reason}, State}
    end.

follow_start(UserIds, FStream, FError, State) ->
    Spec = sister_pool_sup:child_worker(UserIds, FStream, FError),    
    metal:info("Starting worker: ~p", [Spec]),
    case supervisor:start_child(sister_pool_sup, Spec) of
        {ok, WorkerPid} ->
            metal:info("Worker ~p started", [WorkerPid]),
            true = link(WorkerPid),
            metal:info("Linked to worker"),
            Workers = dict:store(WorkerPid, UserIds, State#state.workers),
            {ok, ok, State#state{workers=Workers}};
        {error, Reason} ->
            {ok, {error, Reason}, State}
    end.

handle_cast(Msg, State) ->
    metal:warning("Unexpected cast: ~p", [Msg]),
    {noreply, State}.

handle_info({'EXIT', Pid, normal}, State) ->
    metal:info("Worker ~p finished", [Pid]),
    Workers = dict:erase(Pid, State#state.workers),
    % attempt reconnect
    {noreply, State#state{workers=Workers}};
handle_info({'EXIT', Pid, {error, 401}}, State) ->
    metal:error("Worker ~p was denied authorization - shutting down", [Pid]),
    {noreply, stop_all(State)};
handle_info({'EXIT', Pid, {error, 420}}, State) ->
    metal:info("Worker ~p was rate-limited", [Pid]),
    Workers = dict:erase(Pid, State#state.workers),
    % attempt reconnect after a delay 
    {noreply, State#state{workers=Workers}};
handle_info({'EXIT', Pid, Reason}, State) ->
    metal:info("Worker ~p crashed: ~p", [Pid, Reason]),
    Workers = dict:erase(Pid, State#state.workers),
    % attempt reconnect
    {noreply, State#state{workers=Workers}};
handle_info(Other, State) ->
    metal:warning("Unexpected info: ~p", [Other]),
    {noreply, State}.

-spec init ([pos_integer()]) -> {ok, #state{}} | {error, any()}.
init(MaxConns) ->
    {ok, #state{max_conns=MaxConns}}.

terminate(Reason, State) ->
    metal:warning("~p terminating with reason: ~p", [?MODULE, Reason]),
    {ok, State}.

%% ===================================================================
%% Private functions
%% ===================================================================

stop_all(State) ->
    ok = supervisor:terminate_child(sister_sup, sister_pool_sup),
    {ok, _Child, _Info} = supervisor:restart_child(sister_sup, sister_pool_sup),
    State#state{stopped=true, workers=dict:new()}.
