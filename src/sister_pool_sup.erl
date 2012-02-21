-module(sister_pool_sup).

-behaviour(supervisor).

%% API
-export([child_worker/3,
         start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok, {{one_for_one, 5, 10}, []}}.

%% ===================================================================
%% Private functions
%% ===================================================================

-spec child_worker ([nonempty_string(),...], function(), function())
                   -> supervisor:child_spec().
child_worker(UserIds, FStream, FError) ->
    Mod = sister_worker,
    Args = [UserIds, FStream, FError],
    {UserIds, {Mod, start_link, Args}, transient, 5000, worker, [Mod]}.
