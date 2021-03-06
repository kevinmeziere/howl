-module(howl_app).

-behaviour(application).
-include("howl_version.hrl").

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    DPRules =
        [{<<"/howl/[...]">>, howl_http_handler, []}] ++
        wiggle_app:dispatches(),

    Dispatch = cowboy_router:compile([{'_', DPRules}]),

    {ok, HTTPPort} = application:get_env(howl, http_port),
    {ok, Acceptors} = application:get_env(howl, acceptors),
    {ok, Compression} = application:get_env(howl, compression),


    {ok, _} = cowboy:start_http(http, Acceptors, [{port, HTTPPort}],
                                [{env, [{dispatch, Dispatch}]}]),
    case application:get_env(howl, ssl) of
        {ok, on} ->
            {ok, SSLPort} = application:get_env(howl, ssl_port),
            {ok, SSLCA} = application:get_env(howl, ssl_cacertfile),
            {ok, SSLCert} = application:get_env(howl, ssl_certfile),
            {ok, SSLKey} = application:get_env(howl, ssl_keyfile),
            {ok, _} = cowboy:start_https(https, Acceptors,
                                         [{port, SSLPort},
                                          {cacertfile, SSLCA},
                                          {certfile, SSLCert},
                                          {keyfile, SSLKey}],
                                         [{compress, Compression},
                                          {env, [{dispatch, Dispatch}]}]);
        _ ->
            ok
    end,
    case howl_sup:start_link() of
        {ok, Pid} ->
            spawn(fun delay_mdns_anouncement/0),
            ok = riak_core:register([{vnode_module, howl_vnode}]),
            ok = riak_core_ring_events:add_guarded_handler(
                   howl_ring_event_handler, []),
            ok = riak_core_node_watcher_events:add_guarded_handler(
                   howl_node_event_handler, []),
            ok = riak_core_node_watcher:service_up(howl, self()),
            howl_snmp_handler:start(),
            {ok, Pid};
        {error, Reason} ->
            {error, Reason}
    end.

stop(_State) ->
    ok.


delay_mdns_anouncement() ->
    riak_core:wait_for_application(howl),
    Services = riak_core_node_watcher:services(),
    delay_mdns_anouncement(Services).
delay_mdns_anouncement([]) ->
    lager:info("[mdns] Enabling mDNS annoucements."),
    mdns_server_fsm:start();
delay_mdns_anouncement([S | R]) ->
    riak_core:wait_for_service(S),
    delay_mdns_anouncement(R).
