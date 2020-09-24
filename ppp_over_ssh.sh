#!/usr/bin/env bash
# @Author: Seaky
# @Date:   2020/9/1 9:30

# auth
SSH_HOST='remote.server'
SSH_PORT=22
SSH_USER=''
SSH_KEYFILE=''
# paste the content of the private key to $SSH_KEY for skipping duplicate the key to server
SSH_KEY=''

# local
CMD_PPPD='/usr/sbin/pppd'
CMD_SSH='/usr/bin/ssh'
LOCAL_IFNAME=''
LOCAL_VPN_IP='10.220.0.102'
CHECK_INTERVAL=1800

# remote
REMOTE_IFNAME=''
REMOTE_VPN_IP='10.222.0.101'
VPNN=100
#REMOTE_NETWORK='1.1.1.1 2.2.2.0/24'    # network via remote vpn, split by space
REMOTE_NETWORK=''

# auto set a ifname if it is not assigned
[ -z $LOCAL_IFNAME ] && LOCAL_IFNAME="to_"${SSH_HOST}
[ -z $REMOTE_IFNAME ] && REMOTE_IFNAME="to_"$(hostname)

# verify ssh key
TEMP_KEY=false
if [ -z "$SSH_KEYFILE" ]
then
	if [ -n "$SSH_KEY" ]
	then
	    SSH_KEYFILE="$(basename $0)_${LOCAL_IFNAME}.tmpkey"
        TEMP_KEY=true
	fi
fi

[ -z "$SSH_KEYFILE" ] && echo "no ssh key given." && exit 1

PID_FILE="$(basename $0)_${LOCAL_IFNAME}.pid"
SSH_OPTION="-o StrictHostKeyChecking=no -o ConnectTimeout=10"


connect()
{
    if [ -z "$(ps -ef | egrep ${REMOTE_VPN_IP}:${LOCAL_VPN_IP} | grep -v grep)" ]
    then
        if $TEMP_KEY
        then
            echo "Create temporary key file $SSH_KEYFILE"
            echo $$SSH_KEY > $SSH_KEYFILE
        fi
        sudo -E ${CMD_PPPD} updetach noauth silent nodeflate ifname $LOCAL_IFNAME \
        pty "${CMD_SSH} ${SSH_OPTION} -i ${SSH_KEYFILE} -p $SSH_PORT ${SSH_USER}@${SSH_HOST} \
            sudo ${CMD_PPPD} nodetach notty noauth ifname ${REMOTE_IFNAME} \
            ipparam vpn ${VPNN} ${REMOTE_VPN_IP}:${LOCAL_VPN_IP}"
        [ -n "$REMOTE_NETWORK" ] && for nw in $REMOTE_NETWORK; do sudo ip route add $nw via $REMOTE_VPN_IP; done
    else
        echo "$(date)  Tunnel ${LOCAL_IFNAME} is running"
    fi
}

disconnect()
{
    if [ -n "$(ps -ef | egrep ${REMOTE_VPN_IP}:${LOCAL_VPN_IP} | grep -v grep)" ]
    then
        [ -n "$REMOTE_NETWORK" ] && for nw in $REMOTE_NETWORK; do sudo ip route del $nw via $REMOTE_VPN_IP; done
        ps -ef | grep ${REMOTE_VPN_IP}:${LOCAL_VPN_IP} | grep -v grep | awk '{print $2}' | xargs sudo kill
    fi
}


start()
{
    while true
    do
        if [ -f $PID_FILE ]
        then
            [ $(cat ${PID_FILE}) != $$ ] && echo "Pid file $PID_FILE is already exist." && exit 1
            connect
        else
            connect
            echo $$ > $PID_FILE
        fi
        sleep $CHECK_INTERVAL
    done
}

stop()
{
    disconnect
    if [ -f $PID_FILE ]
    then
        cat $PID_FILE | xargs sudo kill
        [ -f $PID_FILE ] && rm $PID_FILE
        $TEMP_KEY && [ -f $SSH_KEYFILE ] && rm $SSH_KEYFILE
    fi
}

restart()
{
	stop
	start
}

[ -z $1 ] && echo "$0 start|stop|restart" || $1