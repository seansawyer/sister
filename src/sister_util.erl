-module(sister_util).

-export([connect/1,
         consume/1]).

connect(UserIds) when length(UserIds) > 100 ->
    {ok, Url} = application:get_env(sister, twitter_ss_endpoint),
    {ok, ConsumerKey} = application:get_env(sister, twitter_consumer_key),
    {ok, ConsumerSecret} = application:get_env(sister, twitter_consumer_secret),
    {ok, Token} = application:get_env(sister, twitter_token),
    {ok, TokenSecret} = application:get_env(sister, twitter_token_secret),
    Consumer = {ConsumerKey, ConsumerSecret, hmac_sha1},
    Follow = string:join(UserIds, ","),
    Opts = [{sync, false}, {stream, self}],
    oauth:get(Url, [{"follow", Follow}], Consumer, Token, TokenSecret, Opts).

consume(RequestId) ->
    receive
        {http, {RequestId, stream_start, _Headers}} ->
            consume(RequestId);
        {http, {RequestId, stream, BinBodyPart}} ->
            sister_pool:stream_message(BinBodyPart),
            consume(RequestId);
        {http, {RequestId, stream_end, _Headers}} ->
            {ok, RequestId};
        Other ->
            metal:warning("Received unexpected message: ~n", [Other])
    after
        90000 ->
            httpc:cancel_request(RequestId)
    end.
