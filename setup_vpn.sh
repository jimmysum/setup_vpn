#!/bin/sh

if [ `id -u` -ne 0 ]
then
  echo "请使用root身份运行此脚本"
  exit 0
fi
while true
do
	read -p "请输入PPTP/L2TP帐号名： " VPN_USER
	if [ -z $VPN_USER ]
	then
		echo "帐号名不能为空"
	else
		break
	fi
done



while true; do
  read -p "请输入PPTP/L2TP密码： " VPN_PASSWD
  if [ -z $VPN_PASSWD ]
  then
    echo "密码不能为空"
  else
    break
  fi
done

while true
do
	read -p "请输入L2TP密钥: " VPN_PSK
	if [ -z $VPN_PSK  ]
	then
		echo "密钥不可为空"
	else
		break
	fi
done



while true
do
	read -p "请输入shadowsocks密码: " SS_PASSWD
	if [ -z $SS_PASSWD ]
	then
		echo "shadowsocks密码不可为空"
	else
		break
	fi
done



echo "开始为你必备软件，请稍等！"

apt-get update > /dev/null
apt-get install wget -y  > /dev/null

MY_IP=`wget -q -O - http://wtfismyip.com/text` 
echo "你的服务器IP为 $MY_IP"
echo "============================================================"

apt-get install libnss3-dev libnspr4-dev pkg-config libpam0g-dev libcap-ng-dev libcap-ng-utils libselinux1-dev libcurl4-nss-dev libgmp3-dev flex bison gcc make libunbound-dev libnss3-tools ppp pptpd -y  > /dev/null

echo "开始配置PPTP"
cat > /etc/pptpd.conf << EOF
option /etc/ppp/pptpd-options
localip 192.168.0.1
remoteip 192.168.0.23-238
EOF

echo "ms-dns 8.8.8.8" > /etc/ppp/pptpd-options
echo "ms-dns 8.8.4.4" >> /etc/ppp/pptpd-options



echo "net.ipv4.ip_forward=1" >>  /etc/sysctl.conf
sysctl -p > /dev/null

iptables -t nat -A POSTROUTING -s 192.168.0.0/24 -o eth0 -j MASQUERADE
iptables-save > /etc/iptables

update-rc.d ptpd defaults > /dev/null
service pptpd start > /dev/null 








echo "开始配置L2TP......"
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
$VPN_USER  *  $VPN_PASSWD  *
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


echo "开始配置shadowsocks......."
apt-get install python-pip   -y > /dev/null
pip install shadowsocks  > /dev/null
mkdir /etc/shadowsocks
cat > /etc/shadowsocks/config.json << EOF
{
	"service_ip" : "$MY_IP",
	"service_port" : 8388,
	"local_port" : 1080,
	"password" : "$SS_PASSWD",
	"timeout" : 600,
	"method" : "aes-256-cfb"
}
EOF
ssserver -c /etc/shadowsocks/config.json > /var/log/shadowsocks.log &





echo "配置成功！帐号信息如下"
echo "========================================================================================================"
echo "服务器ip      ：        $MY_IP    "
echo ""
echo "L2TP/PPTP 帐号：        $VPN_USER "
echo "L2TP/PPTP 密码：        $VPN_PASSWD"
echo "L2TP      密钥：        $VPN_PSK" 

echo "---------------------------------------"
echo "shadowsocks服务端口：   8388"
echo "shadowsocks密码    :    $SS_PASSWD"
echo "加密方式           ：   aes-256-cfb"
echo "======================================================================================================="


sleep 2
exit 0
