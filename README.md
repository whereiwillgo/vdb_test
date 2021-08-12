# vdb_test
```shell
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
```

```
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
```
