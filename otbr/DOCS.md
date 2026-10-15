# OpenThread Border Router (patched)

This is the upstream [OpenThread Border Router add-on][upstream] with a few of
its scripts replaced. The image is built on top of the upstream image of the
same version, so OpenThread itself, the firewall, the REST API, discovery and
the web UI behave exactly as upstream. Read the [upstream documentation][docs]
for everything not covered here.

## Differences from upstream

### Radios without flow control

Without flow control, upstream always deasserts DTR and RTS when it opens the
serial port. The Sonoff Dongle Plus MG24 wires DTR to the radio's reset line,
so that holds the radio in reset and the agent never reaches it. Here the
`uart_init_deassert` option controls this, and it is off by default. Upstream's
settings migration step, which opens the port the same way, is skipped; it only
matters when moving the border router to a different radio.

### Staying in charge next to Apple border routers

Apple TVs and HomePods are Thread border routers too, and their defaults beat
OpenThread's on three roles:

| Role | Decided by | Apple | Upstream | Default here |
|---|---|---|---|---|
| Leader | leader weight when partitions merge | 68 | 64 | 72, and take over after start |
| OMR prefix (device addresses) | preference | DHCPv6-PD prefix at medium | ULA at low | ULA at high |
| SRP server (service registration) | entry type, then sequence number | anycast | unicast | anycast, newer sequence number |

With the defaults here the Apple border routers withdraw their prefix and SRP
entries, and take them over again when this border router is gone. OpenThread
keeps none of these settings, so the configure script applies them on every
start. The SRP server forgets its registrations on restart and devices only
re-register when the entry changes, so the sequence number steps on every
start; it is kept in `/data/thread/srp-seqnum` and cycles from 146 to 209.

Set `omr_preference` to `default` and turn off `take_leadership` and
`srp_anycast` to get upstream behaviour, and set `leader_weight` to 64 and
`tx_power` to 6 for upstream's values.

### Status log

Every `status_interval` minutes the add-on logs one line with the node's role,
partition, leader weight, router and child counts, the prefixes, routes and SRP
entries in the network data, and the SRP server's state. That makes the
border router's state readable from the add-on log alone.

## Options

The options shared with upstream keep their meaning; see the upstream
documentation. Defaults differ for `flow_control` (off) and `otbr_log_level`
(`warning`). The added options:

- `uart_init_deassert`: deassert DTR and RTS at start, as upstream does
  without flow control.
- `tx_power`: radio transmit power in dBm (upstream: 6).
- `leader_weight`: leader weight (upstream: 64).
- `take_leadership`: start a new partition as leader after the agent has
  attached.
- `omr_preference`: `default`, `low`, `med` or `high`.
- `srp_anycast`: run the SRP server in anycast mode.
- `status_interval`: minutes between status lines, 0 to turn them off.

## Updating to a new upstream version

1. Change the image tag in `build.yaml` and the version in `config.yaml`.
2. Compare every file under `rootfs/` with the same file in the new upstream
   version, and carry over upstream's changes.
3. Note the change in `CHANGELOG.md`.

[upstream]: https://github.com/home-assistant/addons/tree/master/openthread_border_router
[docs]: https://github.com/home-assistant/addons/blob/master/openthread_border_router/DOCS.md
