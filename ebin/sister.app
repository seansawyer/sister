{application,sister,
    [{description,"Erlang client for the Twitter site streams API"},
     {vsn,"1"},
     {registered,[]},
     {applications,[kernel,stdlib,crypto,public_key,ssl,inets,oauth]},
     {mod,{sister_app,[]}},
     {env,
         [{twitter_ss_endpoint,"https://sitestream.twitter.com/2b/site.json"},
          {twitter_app_id,"985671"},
          {twitter_consumer_key,"y9stzKb8bhw6spMyWZXtfg"},
          {twitter_consumer_secret,
              "vEi18UlK73AtHhm6kmEPSvnf4m6TuJx7ZVudMkdUVtI"},
          {twitter_token,"14075837-EhDOmDCTUdPHAmkK6CBYnx7fK4mXmFh1H5q84ALVj"},
          {twitter_token_secret,"n7llOKp3Ob9rqxsmIb1YhQJ7esahTpTB1iJbgT7sg"}]},
     {modules,
         [sister,sister_app,sister_pool,sister_pool_sup,sister_sup,
          sister_util,sister_worker]}]}.
