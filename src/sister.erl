-module(sister).

%% API
-export([follow/1,
         start/0]).

%% ===================================================================
%% API
%% ===================================================================

-spec follow (list(nonempty_string())) -> ok.
follow(UserIds) ->
    sister_pool:follow(UserIds).

start() ->
    sister_util:ensure_deps(sister),
    lager:start(),
    application:set_env(lager, handlers, [lager_console_backend, info]),
    sister_util:ensure_started(sister),
    application:set_env(metal, log_backend, metal_lager).
