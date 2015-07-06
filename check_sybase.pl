#!/usr/bin/perl

## A Nagios plugin that connects to a Sybase database and checks free space.
##
## Copyright (c) 2015 Fabian Reichardt
##
##
## This program is free software; you can redistribute it and/or
## modify it under the terms of the GNU General Public License
## as published by the Free Software Foundation; either version 2
## of the License, or (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.


## You will need the following additional software:
## CPAN Text::Trim
## sqsh (http://sourceforge.net/projects/sqsh/)

use Getopt::Long;
#use Text::Trim qw(trim);

my %conf = (
	timedef		=> "30",									# timeout of plugin
	sudo 		=> "/usr/bin/sudo su - root -c",			# path to sudo command
	sqsh	 	=> "/usr/local/bin/sqsh",					# path to sapcontrol binarie
	ps			=> "/bin/ps -ef",							# path to ps command
	usrbin		=> "/usr/bin",								# path to /usr/bin, currently used for grep/fgrep only
	);


#
# Dont change anything below these lines ...
#


GetOptions(
    "v"         => \$ver,
    "version"   => \$ver,
    "h"         => \$help,
    "help"      => \$help,			
    "port=i"	=> \$port,			# sybase port number to connect to
    "meth=s"    => \$meth,			# monitoring methode
    "db=s"    	=> \$db,			# monitoring database
    "warn=o"    => \$warn,			# warning level
    "crit=o" 	=> \$crit,			# critical level
    "t=i"       => \$timec,			# timeout of the check
    "time=i" 	=> \$timec,			# timeout of the check
    "host=s"	=> \$host,			# monitored-system
    "user=s"	=> \$user,			# monitoring user on remote-system
    "pass=s"	=> \$pass,			# password for monitoring-user on remote-system
	);


version();
help();
precheck();
        

# timeout routine
$SIG{ALRM} = \&plugin_timeout;
eval {
		alarm ($timeout);
        };

sub precheck{
	my $command = `$conf{sqsh} -v`;
	if ( index($command, 'sqsh-2') == -1 )
		{
			print "\n";
			print "sqsh 2.x not found or configuration string wrong.\n";
			print "Please check sqsh bin variable in script.\n";
			print "If sqsh is not installed on this system, \n";
			print "check http://sourceforge.net/projects/sqsh/ for more details.\n";
			print "\n";
			exit 3;		
		}
	}

#start freespace check
if ( $meth eq "freespace" )
	{
	if ( $warn ne undef && $crit ne undef )
		{
			freespace();		
		}
	else
		{
			print "UNKNOWN - you must define a warning-level and a critical level.\n";
			exit 3;
		}
		
	if ( $rc_command == 0 )
		{	
			nagroutine_out();
		}
	
	elsif ( $rc_command > 0)
		{
			unknown_obj();
		}
	}
elsif ( $meth eq "freelogspace" )
	{
	if ( $warn ne undef && $crit ne undef )
		{
			freelogspace();		
		}
	else
		{
			print "UNKNOWN - you must define a warning-level and a critical level.\n";
			exit 3;
		}
		
	if ( $rc_command == 0 )
		{	
			nagroutine_out();
		}
	
	elsif ( $rc_command > 0)
		{
			unknown_obj();
		}
	}
	

sub freespace{
	if ( $db eq "master" )
		{
			#print "Sub: Freespace->Master\n";
			my $real_sid = `$conf{sqsh} -S "${host}":"${port}" -U "${user}" -P "${pass}" -b <<QRY
	set nocount on
	go
	set proc_return_status off
	go
	SELECT CONVERT(char(20), db_name(D.dbid))
	FROM master..sysdatabases D,
	master..sysusages U
	WHERE U.dbid = D.dbid
	AND ((D.dbid = 1) AND (D.status != 256))
	GROUP BY D.dbid
	ORDER BY db_name(D.dbid)
	go
QRY`; 
			printf "%s\n", clean_output($real_sid);
			my $master_check = `$conf{sqsh} -S "${host}":"${port}" -U "${user}" -P "${pass}" -b <<QRY
	set nocount on
	go
	set proc_return_status off
	go
	declare \@pagesize float
	select \@pagesize=(select @\@maxpagesize)
	SELECT STR(SUM(CASE WHEN U.segmap != 4 THEN curunreservedpgs(U.dbid, U.lstart, U.unreservedpgs)END)*\@pagesize/1048576.00000000,10,1)
	FROM master..sysdatabases D,
	master..sysusages U
	WHERE U.dbid = D.dbid
	AND ((D.dbid = 1) AND (D.status != 256))
	GROUP BY D.dbid
	ORDER BY db_name(D.dbid)
	go
QRY`;
			$rc_command = $?;
			#print "$master_check\n";
			#Get only third line from output:
			my $data_free = `echo "${master_check}" | awk 'NR==3'`;
			#print "$data_free\n";
			#Remove all blanks in the output:
			$perf_value = `echo "${data_free}" | sed -e 's/ //g'`;
			#Remove all special characters:
			$perf_value =~ s/[\ |\s]//g;
			$perf_unit = "MB";
			#print "$data_free\n";
			#print "$perf_value";
		}
	elsif ( $db eq "SID" )
		{
			#print "Sub: Freespace->SID\n";
			my $real_sid = `$conf{sqsh} -S "${host}":"${port}" -U "${user}" -P "${pass}" -b <<QRY
	set nocount on
	go
	set proc_return_status off
	go
	SELECT CONVERT(char(20), db_name(D.dbid))
	FROM master..sysdatabases D,
	master..sysusages U
	WHERE U.dbid = D.dbid
	AND ((D.dbid > 3) AND (D.dbid < 5) AND (D.status != 256))
	GROUP BY D.dbid
	ORDER BY db_name(D.dbid)
	go
QRY`; 
			#printf "%s\n", clean_output($real_sid);
			$db = clean_output($real_sid);
			my $master_check = `$conf{sqsh} -S "${host}":"${port}" -U "${user}" -P "${pass}" -b <<QRY
	set nocount on
	go
	set proc_return_status off
	go
	declare \@pagesize float
	select \@pagesize=(select @\@maxpagesize)
	SELECT STR(SUM(CASE WHEN U.segmap != 4 THEN curunreservedpgs(U.dbid, U.lstart, U.unreservedpgs)END)*\@pagesize/1048576.00000000,10,1)
	FROM master..sysdatabases D,
	master..sysusages U
	WHERE U.dbid = D.dbid
	AND ((D.dbid > 3) AND (D.dbid < 5) AND (D.status != 256))
	GROUP BY D.dbid
	ORDER BY db_name(D.dbid)
	go
QRY`;
			$rc_command = $?;
			#print "$master_check\n";
			#Get only third line from output:
			my $data_free = `echo "${master_check}" | awk 'NR==3'`;
			#print "$data_free\n";
			#Remove all blanks in the output:
			$perf_value = `echo "${data_free}" | sed -e 's/ //g'`;
			#Remove all special characters:
			$perf_value =~ s/[\ |\s]//g;
			$perf_unit = "MB";
			#print "$data_free\n";
			#print "$perf_value";
		}
	}


sub freelogspace{
	if ( $db eq "master" )
		{
			#print "Sub: Freespace->Master\n";
			my $real_sid = `$conf{sqsh} -S "${host}":"${port}" -U "${user}" -P "${pass}" -b <<QRY
	set nocount on
	go
	set proc_return_status off
	go
	SELECT CONVERT(char(20), db_name(D.dbid))
	FROM master..sysdatabases D,
	master..sysusages U
	WHERE U.dbid = D.dbid
	AND ((D.dbid = 1) AND (D.status != 256))
	GROUP BY D.dbid
	ORDER BY db_name(D.dbid)
	go
QRY`; 
			printf "%s\n", clean_output($real_sid);
			my $master_check = `$conf{sqsh} -S "${host}":"${port}" -U "${user}" -P "${pass}" -b <<QRY
	set nocount on
	go
	set proc_return_status off
	go
	declare \@pagesize float
	select \@pagesize=(select @\@maxpagesize)
	SELECT STR(SUM(CASE WHEN U.segmap != 4 THEN curunreservedpgs(U.dbid, U.lstart, U.unreservedpgs)END)*\@pagesize/1048576.00000000,10,1)
	FROM master..sysdatabases D,
	master..sysusages U
	WHERE U.dbid = D.dbid
	AND ((D.dbid = 1) AND (D.status != 256))
	GROUP BY D.dbid
	ORDER BY db_name(D.dbid)
	go
QRY`;
			$rc_command = $?;
			#print "$master_check\n";
			#Get only third line from output:
			my $data_free = `echo "${master_check}" | awk 'NR==3'`;
			#print "$data_free\n";
			#Remove all blanks in the output:
			$perf_value = `echo "${data_free}" | sed -e 's/ //g'`;
			#Remove all special characters:
			$perf_value =~ s/[\ |\s]//g;
			$perf_unit = "MB";
			#print "$data_free\n";
			#print "$perf_value";
		}
	elsif ( $db eq "SID" )
		{
			#print "Sub: Freespace->SID\n";
			my $real_sid = `$conf{sqsh} -S "${host}":"${port}" -U "${user}" -P "${pass}" -b <<QRY
	set nocount on
	go
	set proc_return_status off
	go
	SELECT CONVERT(char(20), db_name(D.dbid))
	FROM master..sysdatabases D,
	master..sysusages U
	WHERE U.dbid = D.dbid
	AND ((D.dbid > 3) AND (D.dbid < 5) AND (D.status != 256))
	GROUP BY D.dbid
	ORDER BY db_name(D.dbid)
	go
QRY`; 
			#printf "%s\n", clean_output($real_sid);
			$db = clean_output($real_sid);
			my $sid_log_check = `$conf{sqsh} -S "${host}":"${port}" -U "${user}" -P "${pass}" -b <<QRY
	set nocount on
	go
	set proc_return_status off
	go
	declare \@pagesize float
	select \@pagesize=(select @\@maxpagesize)
	SELECT 
	STR(100 * (1 - 1.0 * lct_admin("logsegment_freepages",D.dbid) /
	SUM(CASE WHEN U.segmap = 4 THEN U.size END)),8,1)
	FROM master..sysdatabases D,
	master..sysusages U
	WHERE U.dbid = D.dbid
	AND ((D.dbid > 3) AND (D.dbid < 5) AND (D.status != 256))
	GROUP BY D.dbid
	ORDER BY db_name(D.dbid)
	go
QRY`;
			$rc_command = $?;
			#print "$master_check\n";
			#Get only third line from output:
			$perf_value = clean_output($sid_log_check);
			$perf_unit = "%";
			#print "$data_free\n";
			#print "$perf_value";
		}
	}

	
sub clean_output{
	my $s = shift;
	#Get only third line from output:
	$s = `echo "${s}" | awk 'NR==3'`;
	#Remove all blanks in the output:
	$s = `echo "${s}" | sed -e 's/ //g'`;
	#Remove all special characters:
	$s =~ s/[\ |\s]//g;	
	return $s
	}
	
sub nagroutine_out{
	
	if ( $warn < $crit )
		{
			# print "2\n"; 					# for debugging only
			if ( $perf_value < $warn )
				{
					print "OK - $db $perf_value"."$perf_unit|$db=$perf_value"."$perf_unit\n";
        			exit 0;
       			}
			elsif ( $perf_value >= $warn && $perf_value < $crit )
				{
					print "WARNING - $db $perf_value"."$perf_unit|$db=$perf_value"."$perf_unit\n";
       				exit 1;
       			}
			elsif ( $perf_value >= $crit )
				{
					print "CRITICAL - $db $perf_value"."$perf_unit|$db=$perf_value"."$perf_unit\n";
        			exit 2;
				}
		}
	elsif ( $warn > $crit)
		{
			# print "3\n";				# for debuggin only
			if ( $perf_value > $warn )
				{
        			print "OK - $db $perf_value"."$perf_unit|$db=$perf_value"."$perf_unit\n";
        			exit 0;
       			}
			elsif ( $perf_value <= $warn && $perf_value > $crit )
				{
        			print "WARNING - $db $perf_value"."$perf_unit|$db=$perf_value"."$perf_unit\n";
       				exit 1;
       			}
			elsif ( $perf_value <= $crit )
				{
    				print "CRITICAL - $db $perf_value"."$perf_unit|$db=$perf_value"."$perf_unit\n";
        			exit 2;
				}
		}
}


sub help{
	if ( $help == "1" ) 
			{
			print "\n";
			print "Usage:\n";
			print "	check_sybase.pl -host <hostname> -port <Sybase-Port-NR> -db <SID|master|sybcontrol> -meth <freespace> -w <WARNING-LEVEL> -c <CRITICAL-LEVEL> -t <TIME_IN_SEC> -user <USER> -pass <PASS>\n";
			print "\n";
			print "Options:\n";
			print "\n";
			print "	-host: HOSTNAME\n";
			print "\n";
			print "	-port: Sybase port number\n";
			print "\n";
			print "\n";
			print "	-db: <SID|master|sybcontrol>\n";
			print "		SID:		Main Sybase database.\n";
			print "		master:		Sybase master database.\n";
			print "		sybcontrol:	Sybase sybcontrol database.\n";
			print "\n";
			print "	-meth: <freespace>\n";
			print "		freespace:	Right now the only option.\n";
			print "\n";
			print "	-w: warning-level\n";
			print "\n";
			print "	-c: Critical Level\n";
			print "\n";
			print "	-t: plugin timeout, default: 30 sec.\n";
			print "\n";
			print "Version: check_sybase.pl -v\n";
			print "\n";
			print "Syntax: check_sybase.pl -host <hostname> -port <Sybase-Port-NR> -db <SID|master|sybcontrol> -meth <freespace> -w <WARNING-LEVEL> -c <CRITICAL-LEVEL> -t <TIME_IN_SEC> -user <USER> -pass <PASS>\n";
			print "\n";
			print "Examples:\n";
			print "\n";
			print "	check_sybase.pl -host <host> -db SID -meth freespace\n";
			print "		Outputs the remaining free space of DB SID\n";
			print "\n";
			print "\n";
	}
}

sub version{
		if ( $ver == "1" )
			{
				print "\n";
				print "Version: \n";
				print "	0.1 -> add initial check\n";
				print "\n";
				print "For changes, ideas or bugs please contact fabian.reichardt\@cbs-consulting.de\n";
				print "\n";
				exit 0;
			}
	}		
