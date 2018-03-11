#!/bin/bash

##############################
# VPN with network namespace #
##############################

# network namespace name
NAMESPACE="cma"
# Real internet interface name 
ETH0="wlp2s0"
# virtual ethernet (root namespace) interface name
VETH1="veth1"
# virtual ethernet (target namespace) interface name
VETH2="veth2"
# ip address for veth1
VETH1_ADDR="10.10.10.1"
# ip addres for veth2
VETH2_ADDR="10.10.10.2"
# masquerade source ip address
MASQUERADE_SOURCE="10.10.10.0"

if [[ $EUID -ne 0 ]]; then
    echo "You must be root to run this script"
    exit 1
fi

start_namespace ()
{
	set -x

	# Remove namespace if it exists
	ip netns del $NAMESPACE &>/dev/null

	# Create namespace
	ip netns add $NAMESPACE

	# Create veth1 to veth2 link
	ip link add $VETH1 type veth peer name $VETH2

	# Add veth2 to target namespace
	ip link set $VETH2 netns $NAMESPACE

	# Setup IP address of veth1
	ip addr add $VETH1_ADDR/24 dev $VETH1
	ip link set $VETH1 up

	# Setup IP address of veth2
	ip netns exec $NAMESPACE ip addr add $VETH2_ADDR/24 dev $VETH2
	ip netns exec $NAMESPACE ip link set $VETH2 up
	ip netns exec $NAMESPACE ip link set lo up

	# Set default route through veth1
	ip netns exec $NAMESPACE ip route add default via $VETH1_ADDR

	# Share internet access between host and NS
	# Enable IP-forwarding
	sysctl net.ipv4.ip_forward=1

	# Flush forward rules, policy DROP by default
	iptables -P FORWARD DROP
	iptables -F FORWARD

	# Flush nat rules
	iptables -t nat -F

	# Enable masquerading
	#iptables -t nat -A POSTROUTING -s 10.200.1.0/255.255.255.0 -o eth0 -j MASQUERADE
	iptables -t nat -A POSTROUTING -s $MASQUERADE_SOURCE/24 -o $ETH0 -j MASQUERADE

	# Allow forwarding between eth0 and veth1
	iptables -A FORWARD -i $ETH0 -o $VETH1 -j ACCEPT
	iptables -A FORWARD -o $ETH0 -i $VETH1 -j ACCEPT

}

stop_namespace ()
{
	set -x
	
	ip netns pids $NAMESPACE | xargs -rd'\n' kill
	sysctl net.ipv4.ip_forward=0
	iptables -D FORWARD -o $ETH0 -i $VETH1 -j ACCEPT
	iptables -D FORWARD -i $ETH0 -o $VETH1 -j ACCEPT
	iptables -t nat -D POSTROUTING -s $MASQUERADE_SOURCE/24 -o $ETH0 -j MASQUERADE
	ip link del $VETH1
	ip netns delete $NAMESPACE
}

case "$1" in
	start)
		start_namespace
		;;
	stop)
		stop_namespace
		;;
	*)
		if [[ -z "$1" ]]; then
			echo "Usage: $0 <start | stop>"
			exit 1
		fi
		echo "Unknown command: $1"
    	exit 1
		;;	
esac