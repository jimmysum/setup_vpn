#!/bin/bash
#set simple pptp vpn and ipsec/l2tp vpn and shadowsocks server

if [ `id -u` -ne 0 ]
then
	echo "请在root身份下使用此脚本"
	exit 0
fi

echo "安装之前，请先输入你需要建立的帐号信息"


while true
do
	read -p "请输入账户名: " VPN_USER
	if [ "A$VPN_USER" = "A" ]
	then
		echo "用户名不能为空"
	else
		break;
	fi
done

while true
do
	read -p "请输入密码： " VPN_PASSWD
	if [ "A$VPN_PASSWD" = "A" ]
	then
		echo "密码不能为空"
	else
		break;
	fi
done

while true
do
	read -p "请输入L2TP密钥： " VPN_PSK
	if [ "A$VPN_PSK" = "A" ]
	then
		echo "L2TP密钥不能为空"
	else
		break;
	fi
done


apt-get update > /dev/null
apt-get install wget -y > /dev/null

MY_IP=`wget -q -O - http://wtfismyip.com/text`
if [ "A$MY_IP" = "A" ]
then
	echo "无法自动获取你服务器ip，请手动输入！"
	while true
	do
		read -p "请输入你的服务器ip" MY_IP
		if [ "A$MY_IP" = "A" ] 
		then
			echo "服务器ip不能为空"
		else
			break;
		fi
	done
fi

echo "=============================================================="
echo "                开始为你配置，请耐心等待                     "
echo "============================================================="

apt-get install xl2tpd openswan -y > /dev/null


if [ "$?" = "1" ]
then
	echo "发生错误，配置终止"
	exit 0
fi


cat > /etc/ipsec.conf << EOF
version 2.0
config setup

dumpdir=/var/run/pluto/
nat_traversal=yes
virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v4:!192.168.42.0/24
oe=off
protostack=netkey
nhelpers=0
interfaces=%defaultroute

conn vpnpsk

connaddrfamily=ipv4
auto=add
left=$MY_IP
leftid=$MY_IP
leftsubnet=$MY_IP/32
leftnexthop=%defaultroute
leftprotoport=17/1701
rithtprotoport=17/%any
right=%any
rightsubnetwithin=0.0.0.0/0
forceencaps=yes
authby=secret
pfs=no
type=transport
auth=esp
ike=3des-sha1,aes-sha1
phase2alg=3des-sha1,aes-sha1
rekey=no
keyingtries=5
dpddelay=30
dpdtimeout=120
dpdaction=clear
EOF


cat > /etc/ipsec.secrets << EOF
$MY_IP %any : PSK "$VPN_PSK"
EOF

cat > /etc/xl2tpd/xl2tpd.conf << EOF
[global]
port = 1701

[lns default]
ip range = 192.168.42.10-192.168.42.250
local ip = 192.168.42.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

cat > /etc/ppp/options.xl2tpd << EOF
ipcp-accept-local
ipcp-accept-remote
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
crtscts
idle 1800
mtu 1280
mru 1280
lock
lcp-echo-failure 10
lcp-echo-interval 60
connect-delay 5000
EOF

cat > /etc/ppp/chap-secrets << EOF
$VPN_USER * $VPN_PASSWD *
EOF

cat > /etc/rc.local << EOF
iptables -t nat -a POSTROUTING -j MASQUERADE
echo 1 > /proc/sys/net/ipv4/ip_forward
for each in /proc/sys/net/ipv4/conf/*
do
	echo 0 > $each/accept_redirects
	echo 0 > $each/send_redirects
done
/usr/sbin/service ipsec restart
/usr/sbin/service xl2tpd restart
EOF

iptables -t nat -a POSTROUTING -j MASQUERADE > /dev/null

echo 1 > /proc/sys/net/ipv4/ip_forward
for each in /proc/sys/net/ipv4/conf/*
do
	echo 0 > $each/accept_redirects
	echo 0 > $each/send_redirects
done

/sbin/sysctl -p > /dev/null

/usr/sbin/service ipsec restart > /dev/null
/usr/sbin/service xl2tpd restart > /dev/null

echo "完成"

sleep 3

exit 0










