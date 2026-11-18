# kgateway PR #14704: UDPRoute `sourceIP` hash policy has no effect

On a single-backend UDPRoute, a BackendConfigPolicy with `ringHash` + `sourceIP` doesn't keep a client IP on one backend. New sessions from the same client IP land on random backends.

PR: https://github.com/kgateway-dev/kgateway/pull/14704

## Cause

The PR emits the `sourceIP` hash twice: on `udp_proxy.hash_policies`, and on the backend cluster's RingHash `consistent_hashing_lb_config.hash_policy` (see the PR's golden `testutils/outputs/udp-routing/backend-policy-proxy.yaml`). Envoy's ring-hash/Maglev load balancer prefers the cluster's hash policy over the UDP context hash (`thread_aware_lb_impl.cc`, "use the hash policy in the load balancer first"). `udp_proxy` calls `chooseHost(peer, nullptr)` without stream info, so the cluster's `source_ip` hash returns nothing and the LB falls back to a random value.

## Scope

This reproducer runs Envoy directly with the config the PR generates, so it doesn't need kgateway images built from the unreleased PR branch. The kgateway side is shown by the PR's golden output: it emits both hash policies.

## Steps

```sh
./test.sh                     # both Envoy versions, both configs (needs Docker)
N=50 VERSIONS=v1.40.2 ./test.sh
```

`test.sh` sends one datagram from each of 30 source ports (30 new `udp_proxy` sessions) from one client IP, and counts which backend replied.

| Config | What it is |
|---|---|
| `envoy/envoy-kgateway-pr.yaml` | What the PR generates: `udp_proxy.hash_policies: source_ip` **and** a cluster-level RingHash `hash_policy: source_ip` |
| `envoy/envoy-control.yaml` | The same, without the cluster-level `hash_policy` |

## Expected

All sessions from one client IP reach the same backend.

## Actual (2026-11-18)

```
== Envoy v1.39.6, envoy-kgateway-pr.yaml (30 sessions)   ->  9 backend-a, 8 backend-b, 12 backend-c, 1 no-reply
== Envoy v1.39.6, envoy-control.yaml     (30 sessions)   -> 30 backend-b
== Envoy v1.40.2, envoy-kgateway-pr.yaml (30 sessions)   ->  8 backend-a, 10 backend-b, 12 backend-c
== Envoy v1.40.2, envoy-control.yaml     (30 sessions)   -> 30 backend-b
```

The PR's config spreads one client IP over all three backends. Removing the cluster-level hash policy makes `udp_proxy`'s `source_ip` hash take effect. The single `no-reply` was one datagram right after startup.

Fix for kgateway: for UDP, don't put the hash policy on the cluster; set it only on `udp_proxy.hash_policies`.

## Versions

| Component | Version |
|---|---|
| kgateway | PR #14704 head [`1a337b77c8`](https://github.com/kgateway-dev/kgateway/commit/1a337b77c8) (2026-11-02), unreleased; config taken from its golden output |
| Envoy | `envoyproxy/envoy:v1.39.6` (the PR's Makefile `ENVOY_IMAGE`) and `v1.40.2` (kgateway main's `ENVOY_IMAGE`) |
| Gateway API | not used (Envoy-only reproducer) |
| UDP backends/client | `alpine/socat:1.8.0.3` |
| Built | 2026-11-18 |
