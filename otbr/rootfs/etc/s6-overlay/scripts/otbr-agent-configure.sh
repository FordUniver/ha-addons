#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Configure OTBR depending on add-on settings
#
# Patched copy of the upstream add-on's configure script (3.3.0). It runs once
# otbr-agent is up, so it is where runtime-only radio and MLE settings get
# applied on every start; OpenThread persists none of them. Changes:
#
# - TX power from the tx_power option instead of a fixed 6 dBm.
# - Options to keep this border router in charge next to Apple border routers,
#   which otherwise take over the network: they advertise leader weight 68
#   against upstream's 64, publish a DHCPv6-PD OMR prefix at medium against
#   upstream's ULA at low, and publish an anycast SRP entry, which outranks
#   upstream's unicast one. Apple border routers withdraw in our favour and
#   take over again when we are gone.
# ==============================================================================

ot-ctl trel enable

if bashio::config.true 'nat64'; then
    bashio::log.info "Enabling NAT64."
    ot-ctl nat64 enable
    ot-ctl dns server upstream enable
fi

mdns_localhostname="$(hostname)-otbr"
bashio::log.info "Setting OpenThread mDNS local hostname to ${mdns_localhostname}."
ot-ctl mdns localhostname "${mdns_localhostname}"
ot-ctl mdns enable

# Upstream uses 6 dBm so the controller does not exceed what other Thread
# routers typically use, which avoids asymmetric links.
tx_power="$(bashio::config 'tx_power')"
bashio::log.info "Setting TX power to ${tx_power} dBm."
ot-ctl txpower "${tx_power}"

leader_weight="$(bashio::config 'leader_weight')"
bashio::log.info "Setting leader weight to ${leader_weight}."
ot-ctl leaderweight "${leader_weight}"

# The local prefix is derived from the BR ULA prefix in the settings, so it
# stays the same across restarts.
omr_preference="$(bashio::config 'omr_preference')"
if [[ "${omr_preference}" != "default" ]]; then
    omr_prefix="$(ot-ctl br omrprefix local | head -n1 | tr -d '\r')"
    if [[ "${omr_prefix}" == */64 ]]; then
        bashio::log.info "Publishing OMR prefix ${omr_prefix} at ${omr_preference} preference."
        ot-ctl br omrconfig custom "${omr_prefix}" "${omr_preference}"
    else
        bashio::log.warning "No local OMR prefix (got '${omr_prefix}'); keeping the default."
    fi
fi

if bashio::config.true 'srp_anycast'; then
    # Clients use the newest sequence number (RFC 1982); Apple border routers
    # were seen with 82 and 83, and every value from 146 to 209 is newer than
    # any value from 82 to 145. The server forgets its registrations on
    # restart, and clients only re-register when the entry changes, so step the
    # number on every start (in unicast mode the server moves to the next port
    # for the same reason).
    seq_file=/data/thread/srp-seqnum
    seq="$(cat "${seq_file}" 2>/dev/null || true)"
    if [[ "${seq}" =~ ^[0-9]+$ ]] && ((seq >= 146 && seq < 209)); then
        seq=$((seq + 1))
    else
        seq=146
    fi
    echo "${seq}" >"${seq_file}"

    # Address mode and sequence number can only change while the server is
    # disabled, which also turns off auto-enable.
    bashio::log.info "Running the SRP server in anycast mode, sequence number ${seq}."
    ot-ctl srp server disable
    ot-ctl srp server addrmode anycast
    ot-ctl srp server seqnum "${seq}"
    ot-ctl srp server auto enable
fi

if bashio::config.true 'take_leadership'; then
    # The weight only counts when partitions are compared, and only for the
    # current leader. After a restart we usually rejoin the existing partition
    # as a plain router, so start a new partition as leader; with the higher
    # weight the others merge in.
    for _ in $(seq 1 120); do
        state="$(ot-ctl state | head -n1 | tr -d '\r')"
        case "${state}" in
            leader)
                exit 0
                ;;
            child | router)
                bashio::log.info "Attached as ${state}; taking over as leader."
                ot-ctl state leader
                exit 0
                ;;
        esac
        sleep 1
    done
    bashio::log.warning "Not attached after 120 s; leaving leadership to the mesh."
fi
