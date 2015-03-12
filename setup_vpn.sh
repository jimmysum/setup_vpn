#!/bin/sh

if [ `id -u` -ne 0 ]
then
  echo "请使用root身份运行此脚本"
  exit 0
fi
while true
do
	read -p "请输入你需要的帐号名： " VPN_USER
	if [ "A$VPN_USER" = "A" ]
	then
		echo "帐号名不能为空"
	else
		break
	fi
done



while true; do
  read -p "请输入你需要的密码： " VPN_PASSWD
  if [ "x$VPN_PASSWD" = "x" ]
  then
    echo "密码不能为空"
  else
    break
  fi
done


echo "请输入L2TP密钥： "; read -p "" VPN_PSK; 
echo ""

apt-get update > /dev/null
apt-get install wget -y  > /dev/null

MY_IP=`wget -q -O - http://wtfismyip.com/text` 
echo "你的服务器IP为 $MY_IP"
echo "============================================================"
echo "开始为你下载，请稍等！"

apt-get install libnss3-dev libnspr4-dev pkg-config libpam0g-dev libcap-ng-dev libcap-ng-utils libselinux1-dev libcurl4-nss-dev libgmp3-dev flex bison gcc make libunbound-dev libnss3-tools -y  > /dev/null

if [ "$?" = "1" ]
then
  echo "异常错误，程序终止"
  exit 0
fi

apt-get install xl2tpd -y > /dev/null

if [ "$?" = "1" ]
then
  echo "异常错误，程序终止"
  exit 0
fi

mkdir -p /opt/src
cd /opt/src
wget -qO- https://download.libreswan.org/libreswan-3.12.tar.gz | tar xvz > /dev/null
cd libreswan-3.12
make programs > /dev/null
make install > /dev/null

if [ "$?" = "1" ]
then
  echo "异常错误，程序终止"
  exit 0
fi


cat > /etc/ipsec.conf <<EOF
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
  rightprotoport=17/%any
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

cat > /etc/ipsec.secrets <<EOF
$MY_IP  %any  : PSK "$VPN_PSK"
EOF

cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701
;debug avp = yes
;debug network = yes
;debug state = yes
;debug tunnel = yes
[lns default]
ip range = 192.168.42.10-192.168.42.250
local ip = 192.168.42.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
;ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

cat > /etc/ppp/options.xl2tpd <<EOF
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

cat > /etc/ppp/chap-secrets <<EOF
$VPN_USER  l2tpd  $VPN_PASSWD  *
EOF

/bin/cp -f /etc/rc.local /etc/rc.local.old
cat > /etc/rc.local <<EOF
#!/bin/sh -e
iptables -t nat -A POSTROUTING -j MASQUERADE
echo 1 > /proc/sys/net/ipv4/ip_forward
for each in /proc/sys/net/ipv4/conf/*
do
  echo 0 > $each/accept_redirects
  echo 0 > $each/send_redirects
done
/usr/sbin/service ipsec restart
/usr/sbin/service xl2tpd restart
EOF


iptables -t nat -A POSTROUTING -j MASQUERADE > /dev/null
echo 1 > /proc/sys/net/ipv4/ip_forward
for each in /proc/sys/net/ipv4/conf/*
do
  echo 0 > $each/accept_redirects
  echo 0 > $each/send_redirects
done

if [ ! -f /etc/ipsec.d/cert8.db ] ; then
   echo > /var/tmp/libreswan-nss-pwd
   /usr/bin/certutil -N -f /var/tmp/libreswan-nss-pwd -d /etc/ipsec.d > /dev/null
   /bin/rm -f /var/tmp/libreswan-nss-pwd
fi

/sbin/sysctl -p > /dev/null


/usr/sbin/service ipsec restart > /dev/null
/usr/sbin/service xl2tpd restart > /dev/null

echo "配置成功！"

sleep 2
exit 0
