#!/usr/bin/bash
# Author: liqiang
# Email : liqiang3@sugon.com
# Version : 
#  1. 自定义IO压力
#  2. 指定IO模型
#  3. 多IO模型测试
#  4. 创建、添加、替换三种模式
#  5. 完善storadmin用户的权限配置
#  6. 增加debug和data_errors设置
#  7. 优化硬盘权限修改操作
#  8. 20210806：允许不连续IP范围，调整OLTP和OLAP模型

## 基础函数
#获取IP列表，空格分隔，范围用-指定，如'1.1.1.1-10,2.2.2.2'
function ip_list()
{
	local in="$1"
	in=${in//,/ }
	local out=
	local mode=4
	local seq=.
	local head=
	local tail=
	local ips=
	local ipe=
	
	if [[ "$in" =~ "." ]];then mode=4; seq="."
	elif [[ "$in" =~ ':' ]];then mode=6; seq=':'
	else echo "IP error" >&2; return 1
	fi
	
	for i in `echo $in`; do
		head=${i%$seq*}
		tail=${i##*$seq}
		ips=${tail%%-*}
		if [ $mode -eq 6 ];then ips=$((16#$ips)); fi
		ipe=${tail##*-}
		if [ $mode -eq 6 ];then ipe=$((16#$ipe)); fi
		for j in `seq $ips $ipe`; do
			if [ $mode -eq 6 ];then j=`printf "%X" $j`; fi
			out=$out"$head$seq$j "
		done
	done
	echo $out
}

#检查IP列表，保留连通IP，剔除不通IP
function ip_list_check()
{
	local in="$1"
	local out=
	
	for i in `echo ${!in}`; do
		ping -c 2 $i >/dev/null
		if [ $? -eq 0 ];then out=$out" $i"; else echo "$i can't connect" >&2; fi
	done
	echo $out
}

#检查IP列表服务器，目录是否存在
function dir_check()
{
	local ips="$1"
	local dir="$2"
	for i in `echo ${!ips}`; do
		ssh -Tq $USER@$i "$SUDO test -d $dir"
		if [ $? -ne 0 ];then 
			echo "There is no $dir on $i, please scp..." >&2
			exit
		fi
		ssh -Tq $USER@$i "$SUDO chown -R $USER $dir"
	done
}

#获取数字列表，空格分隔，范围用-指定，如'1-10,20'
function num_list()
{
	local in="$1"
	in=${in//,/ }
	local out=
	local ns=
	local ne=
	lcoal tm=
	for i in `echo $in`; do
		ns=${i%%-*}
		ne=${i##*-}
		for j in `seq $ns $ne`; do
			out=$out" $j"
		done
	done
	echo $out
}


## 拼接配置文件
#vdbench文件标题部分
function f_vdb_f_title()
{
	local usage="Usage: $FUNCNAME -d <debug> -d <data_errors>" 
	local dg=
	local er=
	OPTIND=1
	OPTERR=0
	while getopts "d:e:" opt; do
		case $opt in 
		d) dg=$OPTARG ;;
		e) er=$OPTARG ;;
		?) echo $usage; return 1;;
		esac
	done
	dg=${dg:-27}
	er=${er:-10}
	echo debug=$dg | tee $VDB_FILE
	echo data_errors=$er | tee -a $VDB_FILE
}

#vdbench文件hd主机定义部分
function f_vdb_f_hd()
{
	echo "hd=default,shell=ssh,vdbench=`pwd`,user=`whoami`" | tee -a $VDB_FILE
	hn=1
	for i in `echo $VDB_HOST_IP_LIST`; do
		echo "hd=hd$hn,system=$i" | tee -a $VDB_FILE
		((hn++))
	done
}

#vdbench文件sd磁盘定义部分
function f_vdb_f_sd()
{	local usage="Usage: $FUNCNAME -p <threads> -l <lun type>" 
	local th=
	local lt=
	OPTIND=1
	OPTERR=0
	while getopts "p:l:" opt; do
		case $opt in 
		p) th=$OPTARG ;;
		l) lt=$OPTARG ;;
		?) echo $usage; return 1;;
		esac
	done
	th=${th:-32}
	lt=${lt:-direct}
	echo "sd=default,openflags=o_direct,threads=$th" | tee -a $VDB_FILE
	local sn=1
	local hn=1
	for i in `echo $VDB_HOST_IP_LIST`; do
		if [ "$lt" == "direct" ];then
			ssh -Tq $USER@$i "lsscsi|grep -i -e sugon -e suma|grep -i stor|awk '{print \$NF}'" > $TMPFILE
			ssh -Tq $USER@$i "lsscsi|grep -i -e sugon -e suma|grep -i stor|awk '{print \$NF}'|$SUDO xargs -i chmod 777 {}" 
			ssh -Tq $USER@$i "$SUDO chmod 777 \`lsscsi|grep -i -e sugon -e suma|grep -i stor|awk '{print \$NF}'\`" 
		elif [ "$lt" == "vm" ];then
			ssh -Tq $USER@$i "lsscsi|grep /dev/sd|grep -v 'sda '|awk '{print \$NF}'" > $TMPFILE
			ssh -Tq $USER@$i "lsscsi|grep /dev/sd|grep -v 'sda '|awk '{print \$NF}'|$SUDO xargs -i chmod 777 {}"
			ssh -Tq $USER@$i "$SUDO chmod 777 \`$SUDO lsscsi|grep /dev/sd|grep -v 'sda '|awk '{print \$NF}'\`"
		else
			echo "Error: Lun type should be direct or vm" >&2; return 1
		fi
		while read disk; do
			echo "sd=sd$sn,hd=hd$hn,lun=$disk" | tee -a $VDB_FILE
			((sn++))
		done <$TMPFILE
		((hn++))
	done
	NUM_SD=$sn
}

#vdbench文件wd负载定义部分
function f_vdb_f_wd()
{
	local usage="Usage: $FUNCNAME -b <block size kb> -r <read pct> -s <seek pct> -k <skew>" 
	local bs=
	local rp=
	local sp=
	local sk=
	local SKEW=
	MAXWN=$((MAXWN+1))
	local wn=$MAXWN
	WN_LIST="${WN_LIST}wd${wn},"
	OPTIND=1
	OPTERR=0
	while getopts "b:r:s:k:" opt; do
		case $opt in 
		b) bs=$OPTARG ;;
		r) rp=$OPTARG ;;
		s) sp=$OPTARG ;;
		k) sk=$OPTARG ;;
		?) echo $usage; return 1;;
		esac
	done
	if [ "$sk" ];then
		SKEW=",skew=$sk"
	fi
	echo "wd=wd${wn},sd=sd*,xfersize=${bs}k,rdpct=${rp},seekpct=${sp}${SKEW}" | tee -a $VDB_FILE
}

#vdbench文件rd执行定义部分
function f_vdb_f_rd()
{
	local usage="Usage: $FUNCNAME -t <time> -w <warmup> -i <interval>" 
	local tm=
	local wm=
	local it=
	((MAXRN++))
	local rn=$MAXRN
	WN_LIST="${WN_LIST%,*}"
	WN_LIST="${WN_LIST})"
	OPTIND=1
	OPTERR=0
	while getopts "t:w:i:" opt; do
		case $opt in 
		t) tm=$OPTARG ;;
		w) wm=$OPTARG ;;
		i) it=$OPTARG ;;
		?) echo $usage; return 1;;
		esac
	done
	tm=${tm:-864000}
	wm=${wm:-120}
	it=${it:-10}
	echo "rd=rd${rn},wd=${WN_LIST},iorate=max,elapsed=${tm},warmup=${wm},interval=${it}" | tee -a $VDB_FILE
}

#按序整合vdbench parameter file
function f_vdb_f_sort()
{
	local sort_tmp=vdb_sort_tmp
	$SUDO touch $sort_tmp; $SUDO chmod 777 $sort_tmp
	cat $VDB_FILE|grep -v ^wd=|grep -v ^rd= >$sort_tmp
	cat $VDB_FILE|grep ^wd= >>$sort_tmp
	cat $VDB_FILE|grep ^rd= >>$sort_tmp
	$SUDO mv $sort_tmp $VDB_FILE
}


## 主机操作函数
#主机清理iscsi LUN
function f_host_iscsi_clean()
{
	for i in `echo $VDB_HOST_IP_LIST`; do
		ssh -Tq $USER@$i "$SUDO iscsiadm -m node -u; $SUDO iscsiadm -m node -o delete" >/dev/null
		if [ $? -eq 0 ];then
			echo "$i iscsi clean successfully"
		else 
			echo "$i iscsi clean failed"
		fi
	done
}

#主机重新login iscsi LUN
function f_host_iscsi_login()
{
	vp=$1
	for i in `echo $VDB_HOST_IP_LIST`; do
		ssh -Tq $USER@$i "$SUDO iscsiadm -m discovery -p $vp -t st; $SUDO iscsiadm -m node -l" >/dev/null
		if [ $? -eq 0 ];then
			echo "$i iscsi login successfully"
		else 
			echo "$i iscsi login failed"
		fi
	done
}


## IO压力模板
#展示目前支持的IO模型
function f_vdb_f_mode_list()
{
	cat <<EOF
IO Mode List:
    oltp : 20%-8k rr, 45%-4k rr, 15%-8k rw, 10%-64k sr, 10%-64k sw
    olap : 15%-4k rr, 5%-4k rw, %70-64k sr, 10%-64k sw
    seq-wirte : 1M seek 0 read 0
    seq-read : 1M seek 0 read 100
    rand-wirte : 8k seek 100 read 0
    rand-read : 8k seek 100 read 100
    olap-log : 2/4/8/16/32/64K, read 10, seek 0
    dwh : 512K, read 90, seek 0
    web : 4/8K, read 95, seek 75
    web-log : 8K, read 0, seek 0
    fs : 64K, read 80, seek 100
    exchange2007 : 8K, read 60, seek 100
    exchange2010 : 32K, read 60, seek 100
    exchange2013 : 32K, read 70, seek 100
    os-paging : 64K, read 90, seek 0
    mssql-log : 64K, read 0, seek 0
    vdi-start : 16/32K, read 100, seek 100
    vdi-login : 16/32K, read 0, seek 100
    vdi-run : 16/32K, read 20, seek 0
    spc : 4K, read 40, seek 70
    vedio : 512K, read 40, seek 70
EOF
}

#配置IO模型
function f_vdb_f_mode()
{
	local md="$1"
	if [ "$md" == "oltp" ];then
		f_vdb_f_wd -b 8 -r 100 -s 100 -k 20
		f_vdb_f_wd -b 4 -r 100 -s 100 -k 45
		f_vdb_f_wd -b 8 -r 0 -s 100 -k 15
		f_vdb_f_wd -b 64 -r 100 -s 0 -k 10
		f_vdb_f_wd -b 64 -r 0 -s 0 -k 10
	elif [ "$md" == "olap" ];then
		f_vdb_f_wd -b 4 -r 100 -s 100 -k 15
		f_vdb_f_wd -b 4 -r 0 -s 100 -k 5
		f_vdb_f_wd -b 64 -r 100 -s 0 -k 70
		f_vdb_f_wd -b 64 -r 0 -s 0 -k 10
	elif [ "$md" == "seq-wirte" ];then
		f_vdb_f_wd -b 1024 -r 0 -s 0 
	elif [ "$md" == "seq-read" ];then
		f_vdb_f_wd -b 1024 -r 100 -s 0
	elif [ "$md" == "rand-wirte" ];then
		f_vdb_f_wd -b 8 -r 0 -s 100
	elif [ "$md" == "rand-read" ];then
		f_vdb_f_wd -b 8 -r 100 -s 100
	elif [ "$md" == "olap-log" ];then
		f_vdb_f_wd -b 2 -r 10 -s 0
		f_vdb_f_wd -b 4 -r 10 -s 0
		f_vdb_f_wd -b 8 -r 10 -s 0
		f_vdb_f_wd -b 16 -r 10 -s 0
		f_vdb_f_wd -b 32 -r 10 -s 0
		f_vdb_f_wd -b 64 -r 10 -s 0
	elif [ "$md" == "dwh" ];then
		f_vdb_f_wd -b 512 -r 90 -s 0
	elif [ "$md" == "web" ];then
		f_vdb_f_wd -b 4 -r 95 -s 75
		f_vdb_f_wd -b 8 -r 95 -s 75
	elif [ "$md" == "web-log" ];then
		f_vdb_f_wd -b 8 -r 0 -s 0
	elif [ "$md" == "fs" ];then
		f_vdb_f_wd -b 64 -r 80 -s 100
	elif [ "$md" == "exchange2007" ];then
		f_vdb_f_wd -b 8 -r 60 -s 100
	elif [ "$md" == "exchange2010" ];then
		f_vdb_f_wd -b 32 -r 60 -s 100
	elif [ "$md" == "exchange2013" ];then
		f_vdb_f_wd -b 32 -r 70 -s 100
	elif [ "$md" == "os-paging" ];then
		f_vdb_f_wd -b 64 -r 90 -s 0
	elif [ "$md" == "mssql-log" ];then
		f_vdb_f_wd -b 64 -r 0 -s 0
	elif [ "$md" == "vdi-start" ];then
		f_vdb_f_wd -b 16 -r 100 -s 100
		f_vdb_f_wd -b 32 -r 100 -s 100
	elif [ "$md" == "vdi-login" ];then
		f_vdb_f_wd -b 16 -r 0 -s 100
		f_vdb_f_wd -b 32 -r 0 -s 100
	elif [ "$md" == "vdi-run" ];then
		f_vdb_f_wd -b 16 -r 20 -s 0
		f_vdb_f_wd -b 32 -r 20 -s 0
	elif [ "$md" == "spc" ];then
		f_vdb_f_wd -b 4 -r 40 -s 70
	elif [ "$md" == "vedio" ];then
		f_vdb_f_wd -b 512 -r 40 -s 70
	else
		f_vdb_f_mode_list
	fi
}

#脚本帮助
function usage()
{
	cat <<EOF
Name:
    $SCRIPT - scan lun on hosts and create parameter file for vdbench
Usage: 
    $SCRIPT -h <ip list> [-c] -f <para file> -b <block size> -r <read pct> -s <seek pct> -t <time> -v <SVIP>
    $SCRIPT -h <ip list> [-c] -f <para file> -m <io mode> -t <time>
Options:
    -a <modify mode>, default create, eg. create append replace
    -h <ip list> , the ip list of hosts, eg. 192.168.11.1-3,10.10.10.101.
    [-c] , check ip, discard the inactive ips.
    [-d <debug>], default 27, debug level.
    [-e <data_errors>], default 10, IO errors number to exit.
    [-f <para file>], default vdb_para, the parameter file will be created.
    [-o <out para file>], the output parameter file.
    [-b <block size>], default 1024, block size.
    [-r <read pct>], default 0, read percent.
    [-s <seek pct>], default eof, seek percent.
    [-t <time>], default 864000, run time.
    [-v <svip list>], will clean, rescan and relogin, eg. 170.16.0.1-2.
    [-m <io mode>], specify IO mode, eg. olap oltp, list to get all io mode.
    [-p <threads>], default 32, the max threads of sd.
    [-l <lun type>], default direct, eg. vm direct.
    [-w <warm time>], default 120, warmup time.
    [-i <interval>], default 10, interval time.
    [-k <skew>], default null
EOF
	f_vdb_f_mode_list
}

#主脚本
if [ "$USER" == "storadmin" ];then
	SUDO="sudo "
elif [ "$USER" == "root" ];then
	SUDO=""
else
	echo "The user should be storadmin or root"; exit 2
fi
SCRIPT=$0
SCRIPT=${SCRIPT##*/}

if [ "$SCRIPT" == "vdb_test8.sh" ];then 
	#1. 帮助信息
	if [ $# -eq 0 ]; then usage; exit; fi
	
	#2. 带初始值变量
	ar=create; ic=0; md=custom
	
	#3. 读取选项参数
	OPTIND=1
	OPTERR=0
	while getopts "a:o:cd:e:h:f:b:r:s:t:v:m:p:l:w:i:k:" opt; do
		case $opt in 
		a) ar=$OPTARG ;;
		o) VDB_FILE_OUT=$OPTARG ;;
		c) ic=1 ;;
		d) dg=$OPTARG ;;
		e) er=$OPTARG ;;
		h) hl="$OPTARG" ;;
		f) VDB_FILE=$OPTARG ;;
		b) bs=$OPTARG ;;
		r) rp=$OPTARG ;;
		s) sp=$OPTARG ;;
		t) tm=$OPTARG ;;
		v) vp=$OPTARG ;;
		m) md=$OPTARG ;;
		p) th=$OPTARG ;;
		l) lt=$OPTARG ;;
		w) wm=$OPTARG ;;
		i) it=$OPTARG ;;
		k) sk=$OPTARG ;;
		?) usage; exit;;
		esac
	done
	if [ "$md" == "list" ];then f_vdb_f_mode_list; exit; fi;
	
	#4. 全局变量
	th=${th:-32}
	VDB_FILE=${VDB_FILE:-vdb_para}
	$SUDO touch $VDB_FILE ; $SUDO chmod 777 $VDB_FILE
	TMPFILE=vdb_tmp_`date '+%Y%m%d%H%M%S'`.txt
	$SUDO touch $TMPFILE; $SUDO chmod 777 $TMPFILE
	
	if [ "$hl" ];then 
		VDB_HOST_IP_LIST=$(ip_list "$hl")
		dir_check VDB_HOST_IP_LIST `pwd`
		if [ $ic -eq 1 ];then VDB_HOST_IP_LIST=$(ip_list_check VDB_HOST_IP_LIST); fi
	fi
	MAXWN=0
	MAXRN=0
	WN_LIST="("
	
	#5. 空变量赋默认值
	bs=${bs:-1024}
	rp=${rp:-0}
	sp=${sp:-eof}
	dg=${dg:-27}
	er=${er:-10}
	
	#6. 功能调用
	#6.1 指定svip时，重新挂载LUN
	if [ "$vp" ];then
		f_host_iscsi_clean
		SVIP_LIST=$(ip_list "$vp")
		for i in `echo $SVIP_LIST`; do
			f_host_iscsi_login $i
		done
	fi
	
	#6.2 hd/sd部分：判断是创建、添加还是替换模式
	if [ "$ar" == "create" ];then
		f_vdb_f_title -d $dg -e $er
		f_vdb_f_hd
		f_vdb_f_sd -p "$th" -l "$lt"
	elif [ "$ar" == "append" ];then
		MAXWN=`cat $VDB_FILE|grep ^wd=|awk -F, '{print $1}'|sed 's/wd=wd//g'|sort -n|tail -1`
		MAXRN=`cat $VDB_FILE|grep ^rd=|awk -F, '{print $1}'|sed 's/rd=rd//g'|sort -n|tail -1`
	elif [ "$ar" == "replace" ];then
		cat $VDB_FILE|grep -v ^wd=|grep -v ^rd= >$VDB_FILE_OUT
	else 
		echo "Error: Modify mode should be create append or replace" >&2; return 1
	fi
	
	#6.3 wd部分：判断IO模型
	if [ "$VDB_FILE_OUT" ];then 
		VDB_FILE=$VDB_FILE_OUT
	fi
	if [ "$md" == "custom" ];then 
		SKEW=
		if [ "$sk" ];then
			SKEW="-k $sk"
		fi
		f_vdb_f_wd -b "$bs" -r "$rp" -s "$sp" $SKEW
		md=$md": -b $bs -r $rp -s $sp $SKEW"
	else
		f_vdb_f_mode "$md"
	fi
	
	#6.4 rd部分：设定执行参数
	count=`echo "$WN_LIST"|tr '(' ' '|tr ')' ' '|wc -w`
	if [ $count -gt 0 ];then
		f_vdb_f_rd -t "$tm" -w "$wm" -i "$it"
		f_vdb_f_sort
	fi
	
	#7. 结束
	echo
	UU=`ulimit -u`
	if [ "$UU" != "unlimited" -a $UU -lt $((th*NUM_SD+1000)) ];then
		echo "Warn: ulimit -u(`ulimit -u`) should be unlimited or > $((th*NUM_SD+1000))"
		echo "      Or decrease threads($th) in sd define."
		echo
	fi
	echo "Mode: $md"
	echo "Run : ./vdbench -f $VDB_FILE | tee $VDB_FILE.log"
	$SUDO rm -f $TMPFILE
fi
