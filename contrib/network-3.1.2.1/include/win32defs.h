#ifndef IP_OPTIONS
#define IP_OPTIONS                 1 // Set/get IP options.
#endif
#ifndef IP_HDRINCL
#define IP_HDRINCL                 2 // Header is included with data.
#endif
#ifndef IP_TOS
#define IP_TOS                     3 // IP type of service.
#endif
#ifndef IP_TTL
#define IP_TTL                     4 // IP TTL (hop limit).
#endif
#ifndef IP_MULTICAST_IF
#define IP_MULTICAST_IF            9 // IP multicast interface.
#endif
#ifndef IP_MULTICAST_TTL
#define IP_MULTICAST_TTL          10 // IP multicast TTL (hop limit).
#endif
#ifndef IP_MULTICAST_LOOP
#define IP_MULTICAST_LOOP         11 // IP multicast loopback.
#endif
#ifndef IP_ADD_MEMBERSHIP
#define IP_ADD_MEMBERSHIP         12 // Add an IP group membership.
#endif
#ifndef IP_DROP_MEMBERSHIP
#define IP_DROP_MEMBERSHIP        13 // Drop an IP group membership.
#endif
#ifndef IP_DONTFRAGMENT
#define IP_DONTFRAGMENT           14 // Don't fragment IP datagrams.
#endif
#ifndef IP_ADD_SOURCE_MEMBERSHIP
#define IP_ADD_SOURCE_MEMBERSHIP  15 // Join IP group/source.
#endif
#ifndef IP_DROP_SOURCE_MEMBERSHIP
#define IP_DROP_SOURCE_MEMBERSHIP 16 // Leave IP group/source.
#endif
#ifndef IP_BLOCK_SOURCE
#define IP_BLOCK_SOURCE           17 // Block IP group/source.
#endif
#ifndef IP_UNBLOCK_SOURCE
#define IP_UNBLOCK_SOURCE         18 // Unblock IP group/source.
#endif
#ifndef IP_PKTINFO
#define IP_PKTINFO                19 // Receive packet information.
#endif
#ifndef IP_HOPLIMIT
#define IP_HOPLIMIT               21 // Receive packet hop limit.
#endif
#ifndef IP_RECVTTL
#define IP_RECVTTL                21 // Receive packet Time To Live (TTL).
#endif
#ifndef IP_RECEIVE_BROADCAST
#define IP_RECEIVE_BROADCAST      22 // Allow/block broadcast reception.
#endif
#ifndef IP_RECVIF
#define IP_RECVIF                 24 // Receive arrival interface.
#endif
#ifndef IP_RECVDSTADDR
#define IP_RECVDSTADDR            25 // Receive destination address.
#endif
#ifndef IP_IFLIST
#define IP_IFLIST                 28 // Enable/Disable an interface list.
#endif
#ifndef IP_ADD_IFLIST
#define IP_ADD_IFLIST             29 // Add an interface list entry.
#endif
#ifndef IP_DEL_IFLIST
#define IP_DEL_IFLIST             30 // Delete an interface list entry.
#endif
#ifndef IP_UNICAST_IF
#define IP_UNICAST_IF             31 // IP unicast interface.
#endif
#ifndef IP_RTHDR
#define IP_RTHDR                  32 // Set/get IPv6 routing header.
#endif
#ifndef IP_GET_IFLIST
#define IP_GET_IFLIST             33 // Get an interface list.
#endif
#ifndef IP_RECVRTHDR
#define IP_RECVRTHDR              38 // Receive the routing header.
#endif
#ifndef IP_TCLASS
#define IP_TCLASS                 39 // Packet traffic class.
#endif
#ifndef IP_RECVTCLASS
#define IP_RECVTCLASS             40 // Receive packet traffic class.
#endif
#ifndef IP_RECVTOS
#define IP_RECVTOS                40 // Receive packet Type Of Service (TOS).
#endif
#ifndef IP_ORIGINAL_ARRIVAL_IF
#define IP_ORIGINAL_ARRIVAL_IF    47 // Original Arrival Interface Index.
#endif
#ifndef IP_ECN
#define IP_ECN                    50 // Receive ECN codepoints in the IP header.
#endif
#ifndef IP_PKTINFO_EX
#define IP_PKTINFO_EX             51 // Receive extended packet information.
#endif
#ifndef IP_WFP_REDIRECT_RECORDS
#define IP_WFP_REDIRECT_RECORDS   60 // WFP's Connection Redirect Records.
#endif
#ifndef IP_WFP_REDIRECT_CONTEXT
#define IP_WFP_REDIRECT_CONTEXT   70 // WFP's Connection Redirect Context.
#endif
#ifndef IP_MTU_DISCOVER
#define IP_MTU_DISCOVER           71 // Set/get path MTU discover state.
#endif
#ifndef IP_MTU
#define IP_MTU                    73 // Get path MTU.
#endif
#ifndef IP_NRT_INTERFACE
#define IP_NRT_INTERFACE          74 // Set NRT interface constraint (outbound).
#endif
#ifndef IP_RECVERR
#define IP_RECVERR                75 // Receive ICMP errors.
#endif
#ifndef IPV6_TCLASS
#define IPV6_TCLASS 39
#endif