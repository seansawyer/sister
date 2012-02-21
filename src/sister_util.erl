-module(sister_util).

-export([connect/1,
         ensure_deps/1,
         ensure_started/1]).

connect(UserIds) when length(UserIds) =< 25 ->
    {ok, Url} = application:get_env(sister, twitter_ss_endpoint),
    {ok, ConsumerKey} = application:get_env(sister, twitter_consumer_key),
    {ok, ConsumerSecret} = application:get_env(sister, twitter_consumer_secret),
    {ok, Token} = application:get_env(sister, twitter_token),
    {ok, TokenSecret} = application:get_env(sister, twitter_token_secret),
    Consumer = {ConsumerKey, ConsumerSecret, hmac_sha1},
    Follow = string:join(UserIds, ","),
    Opts = [{sync, false}, {stream, self}],
    oauth:get(Url, [{"follow", Follow}], Consumer, Token, TokenSecret, Opts).

-spec ensure_deps (atom()) -> ok.
ensure_deps(App) ->
    ensure_loaded(App),
    {ok, Deps} = application:get_key(App, applications),
    lists:foreach(fun ensure_started/1, Deps),
    ok.

-spec ensure_started (atom()) -> ok.
ensure_started(App) ->
    case application:start(App) of
        ok ->
            ok;
        {error, {already_started, App}} ->
            ok
    end.  

%% ===================================================================
%% Private functions
%% ===================================================================

-spec ensure_loaded (atom()) -> ok.
ensure_loaded(App) ->
    case application:load(App) of
        ok ->
            ok;
        {error, {already_loaded, App}} ->
            ok
    end.  
