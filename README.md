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
