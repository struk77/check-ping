#!/bin/ash

send_msg () {
    logger "$1"
    # Replace with your own bot and chat ids #####
    APIURL="https://api.telegram.org/botXXXXXX:YYYYYYY/sendMessage"
    [ $HOUR -ge 8 ] && curl $APIURL -d chat_id=ZZZZZZZZZZ -d text="$1"  
}

main () {
    PACKETS=10
    PACKETSOK=7
    USINGWAN=0
    # Replace with your own #####
    WAN1GW="192.168.0.1"
    WAN2GW="192.168.1.1"
    WAN3GW="192.168.2.1"
    TESTWAN1="8.8.8.8"
    TESTWAN2="8.8.4.4"
    TESTWAN3="1.1.1.1"
    ##############################
    logFile="/root/check-ping.log"
    FPING="/usr/bin/fping"

    [ ! -f $logFile ] && touch $logFile

    LOGCHANGED=$(stat -c %Y "$logFile")
    NOW=$(date +%s)

    ELAPSED=$(( $NOW - $LOGCHANGED ))
    if [ $ELAPSED -le 30 ];then exit;fi

    logger "0" | tee /proc/sys/net/ipv4/conf/*/send_redirects

    ip r del $TESTWAN1
    ip r del $TESTWAN2
    ip r del $TESTWAN3
    ip r add $TESTWAN1 via $WAN1GW >/dev/null 2>&1
    ip r add $TESTWAN2 via $WAN2GW >/dev/null 2>&1
    ip r add $TESTWAN3 via $WAN3GW >/null 2>&1

    # We'll run this in the intervals given above
    while sleep 1s
    do
            touch $logFile
            HOUR=$(date +%H)
        # Try to figure out the current route
        TARGET=$(ip route | awk '/default via/ {print $3; exit}')
        # Set the variable, so let the script now which connection is it dealing with
        if [ "$WAN1GW" = "$TARGET" ]; then 
                USINGWAN=1;
        elif [ "$WAN2GW" = "$TARGET" ]; then
                USINGWAN=2;
        elif [ "$WAN3GW" = "$TARGET" ]; then
                USINGWAN=3;
        fi
            #logger -n `date` >> $logFile
        logger " Using WAN $USINGWAN"
            # We'll ping as many times the $PACKETS variable tells, and test if we have connection:
            RET=$($FPING -a -c $PACKETS $TESTWAN1 $TESTWAN2 $TESTWAN3 2>&1 | cut -c33-40)
            RETWAN1=$(echo $RET|cut -d"/" -f2)
            RETWAN2=$(echo $RET|cut -d"/" -f4)
            RETWAN3=$(echo $RET|cut -d"/" -f6)
            if [ "$RETWAN1" -gt "$PACKETS" ] || [ "$RETWAN2" -gt "$PACKETS" ] || [ "$RETWAN3" -gt "$PACKETS" ];then
                exit 1
            fi
    # creating files of states
        if [ "$RETWAN1" -lt "$PACKETSOK" ] && [ ! -f /tmp/DOWN_WAN1 ];then touch /tmp/DOWN_WAN1;rm -f /tmp/UP_WAN1;fi
        if [ "$RETWAN1" -eq "$PACKETS" ] && [ ! -f /tmp/UP_WAN1 ];then rm -f /tmp/DOWN_WAN1;touch /tmp/UP_WAN1;fi

        if [ "$RETWAN2" -lt "$PACKETSOK" ] && [ ! -f /tmp/DOWN_WAN2 ];then touch /tmp/DOWN_WAN2;rm -f /tmp/UP_WAN2;fi
        if [ "$RETWAN2" -eq "$PACKETS" ] && [ ! -f /tmp/UP_WAN2 ];then rm -f /tmp/DOWN_WAN2;touch /tmp/UP_WAN2;fi

        if [ "$RETWAN3" -lt "$PACKETSOK" ] && [ ! -f /tmp/DOWN_WAN3 ];then touch /tmp/DOWN_WAN3;rm -f /tmp/UP_WAN3;fi
        if [ "$RETWAN3" -eq "$PACKETS" ] && [ ! -f /tmp/UP_WAN3 ];then rm -f /tmp/DOWN_WAN3;touch /tmp/UP_WAN3;fi

        if test $(find /tmp/UP_WAN1 -mmin +20 2>/dev/null);then OLD_WAN1=1;else OLD_WAN1=0;fi
        if test $(find /tmp/UP_WAN2 -mmin +20 2>/dev/null);then OLD_WAN2=1;else OLD_WAN2=0;fi
        if test $(find /tmp/UP_WAN3 -mmin +20 2>/dev/null);then OLD_WAN3=1;else OLD_WAN3=0;fi

        [ -z "$RETWAN1" ] && RETWAN1=0 
        [ -z "$RETWAN2" ] && RETWAN2=0
        [ -z "$RETWAN3" ] && RETWAN3=0
        logger " RETWAN1=$RETWAN1 RETWAN2=$RETWAN2 RETWAN3=$RETWAN3 OLD_WAN1=$OLD_WAN1 OLD_WAN2=$OLD_WAN2 OLD_WAN3=$OLD_WAN3" 
    ## If we don't have connection, change the active WAN port (If there is any loss with multiple packets, it should change either)
        if [ "$USINGWAN" = "1" ] && [ "$RETWAN2" = "$PACKETS" ] && [ "$RETWAN1" -lt "$PACKETSOK" ]; then
            # change from WAN1 to WAN2
            ip route delete default
            ip route add default via $WAN2GW
            /etc/init.d/openvpn stop && /etc/init.d/openvpn start
            USINGWAN=2
            RETWAN1=0
            RETWAN2=10
            send_msg "Changed gateway to WAN2"
            continue
        elif [ "$USINGWAN" -ne 3 ] && [ "$RETWAN3" = "$PACKETS" ] && ( ( [ "$RETWAN2" -lt "$PACKETSOK" ] && [ "$OLD_WAN1" -eq 0 ] ) || ( [ "$RETWAN1" -lt "$PACKETSOK" ] && [ "$OLD_WAN2" -eq 0 ] ) ); then
            # change from WAN1/WAN2 to WAN3
            ip route delete default
            ip route add default via $WAN3GW
            logger "Changing gateway to WAN3"
            /etc/init.d/openvpn stop && /etc/init.d/openvpn start
            USINGWAN=3
            RETWAN1=0
            RETWAN2=0
            RETWAN3=10
            send_msg "Changed gateway to WAN3"
            continue
        fi

        if [ "$USINGWAN" = 2 ] && [ "$RETWAN1" = "$PACKETS" ] && [ "$OLD_WAN1" = "1" ]; then
        # change from WAN2 to WAN1
            ip route delete default
            ip route add default via $WAN1GW
            /etc/init.d/openvpn stop && /etc/init.d/openvpn start
            USINGWAN=1
            send_msg "Returned from backup to WAN1"
            continue
        elif [ "$USINGWAN" = 3 ] && [ "$RETWAN1" = "$PACKETS" ] && [ "$OLD_WAN1" = "1" ]; then
        # change from WAN3 to WAN1
            ip route delete default
            ip route add default via $WAN1GW
            /etc/init.d/openvpn stop && /etc/init.d/openvpn start
            USINGWAN=1
            send_msg "Returned from backup to WAN1"
            continue
        elif [ "$USINGWAN" = 3 ] && [ "$RETWAN2" = "$PACKETS" ] && [ "$OLD_WAN2" = "1" ]; then
        # change from WAN3 to WAN2
            ip route delete default
            ip route add default via $WAN2GW
            /etc/init.d/openvpn stop && /etc/init.d/openvpn start
            USINGWAN=2
            send_msg "Returned from backup to WAN2"
            continue
        fi;
    done;
}

main "$@"
