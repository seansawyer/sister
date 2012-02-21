-module(sister_worker).

-behaviour(gen_server).

%% API
-export([start_link/3,
         stop/1]).

%% gen_server callbacks
-export([code_change/3,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         init/1,
         terminate/2]).

-record(state, {f_error    :: function(),
                f_stream   :: function(),
                request_id :: reference(),
                user_ids   :: list(nonempty_string())}).

%% ===================================================================
%% API functions
%% ===================================================================

reconnect(Ref, UserIds) ->
    gen_server:call(Ref, {reconnect, UserIds}).

start_link(UserIds, FStream, FError) ->
    Arg = [UserIds, FStream, FError],
    gen_server:start_link(?MODULE, Arg, [{timeout, 90000}]).

stop(Ref) ->
    gen_server:call(Ref, stop).

%% ===================================================================
%% gen_server callbacks
%% ===================================================================

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

handle_call({reconnect, UserIds}, _From, State) ->
    RequestId = State#state.request_id,
    metal:info("Reconnecting worker - canceling request ~p", [RequestId]),
    httpc:cancel_request(RequestId),
    case sister_util:connect(UserIds) of
        {ok, RequestId1} ->
            metal:info("Reconnected - request id is ~p, new follow list is ~p",
                       [RequestId1, UserIds]),
            {ok, ok, State#state{request_id=RequestId1}};
        {error, Reason} ->
            metal:error("Reconnect failed: ~p", [Reason]),
            {stop, Reason, {error, Reason}, State}
    end;
handle_call(stop, _From, State) ->
    RequestId = State#state.request_id,
    metal:info("Stopping worker - canceling request ~p", [RequestId]),
    httpc:cancel_request(RequestId),
    {stop, normal, State}.

handle_cast(Request, State) ->
    metal:warning("Unexpected cast: ~p", [Request]),
    {noreply, State}.

handle_info({http, {RequestId, stream_start, _Hdrs}}, State) ->
    metal:info("Request ~p - stream start", [RequestId]),
    {noreply, State};
handle_info({http, {RequestId, stream, BinBodyPart}}, State) ->
    metal:info("Request ~p - stream part (~p): ~p",
               [RequestId, size(BinBodyPart), BinBodyPart]),
    F = State#state.f_stream,
    F(BinBodyPart),
    {noreply, State};
handle_info({http, {RequestId, stream_end, _Hdrs}}, State) ->
    metal:info("Stream end - request id: ~p", [RequestId]),
    {stop, normal, State};
handle_info({http, {RequestId, {{_,401,_}, _Hdrs, _Body}=Resp}}, State) ->
    metal:error("Request ~p - (401) Unauthorized", [RequestId]),
    F = State#state.f_error,
    F(Resp),
    {stop, {error, 401}, State};
handle_info({http, {RequestId, {{_,420,_}, _Hdrs, _Body}=Resp}}, State) ->
    metal:warning("Request ~p - (420) Enhance your calm, bro", [RequestId]),
    F = State#state.f_error,
    F(Resp),
    {stop, {error, 420}, State};
handle_info({http, {RequestId, {{_,Code,_}, _Hdrs, _Body}}=Resp}, State) ->
    metal:warning("Request ~p - unexpected response code: ~p",
                  [RequestId, Code]),
    F = State#state.f_error,
    F(Resp),
    {stop, {error, Code}, State};
handle_info(Other, State) ->
    metal:warning("Unexpected info: ~p", [Other]),
    {noreply, State}.

init([UserIds, FStream, FError]) ->
    case sister_util:connect(UserIds) of
        {ok, RequestId} ->
            metal:info("Request ~p established", [RequestId]),
            {ok, #state{f_error=FError,
                        f_stream=FStream,
                        request_id=RequestId,
                        user_ids=UserIds}};
        {error, Reason} ->
            metal:info("Request failed: ~p", [Reason]),
            {stop, Reason}
    end.

terminate(Reason, State) ->
    metal:warning("~p terminating with reason: ~p", [?MODULE, Reason]),
    {ok, State}.
