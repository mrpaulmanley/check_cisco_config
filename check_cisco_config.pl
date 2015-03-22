#!/usr/bin/perl

use Getopt::Std;
use Switch;
use Tie::File;
use File::Copy;
use File::Touch;

#Script name and version. Used when printing the usage page
$script = "check_cisco_config.pl";
$script_version = "0.5";
$snmparg = '';

check_arguments ();
check_backup_directory ();
check_device_backup_directory ();
check_tftp_directory ();
tftp_config ();
analyze_config ();
exit $status;

sub check_arguments {
  getopts("H:v:x:X:a:A:u:C:I:T:L:l:S:N:t");
  if ($opt_H){
    $hostip = $opt_H;
  }
  else {
    print "Host IP address not specified\n";
    print_usage();
  }
  if ( ! $opt_v) {
    print "SNMP version not specified.\n";
    print_usage();
  }
  elsif ($opt_v =~ /^([13]|2c)$/){
    $version = $opt_v;
    $snmparg .= " -v " . $version;
  }
  else {
    print "Version must be 1, 2c or 3.\n";
    print_usage();
  }
if ($version == 3){
  $snmplevel = "noAuthNoPriv";
  if ($opt_u){
    $snmpuser = $opt_u;
    $snmparg .= " -u " . $snmpuser;
  }
  else {
    print "SNMP user not specified.\n";
    print_usage();
  }
if ( ! (($opt_x) xor ($opt_X))) {
if ($opt_x && $opt_X) {
  if ($opt_x =~ /^([AD]ES|[ad]es)$/){
    $snmpprivproto = $opt_x;
    $snmparg .= " -x " . $snmpprivproto;
  }
  else {
    print "Unknown SNMP privacy protocol.\n";
    print_usage();
  }
  if ($opt_X) {
    $snmpprivpass = $opt_X;
    $snmparg .= " -X " . $snmpprivpass;
    $priv = 1;
  }
  else {
    print "SNMP privacy password not specified.\n";
    print_usage();
  }
}
else {$priv = 0;}
}
else {
  print "Missing some of privacy parameters.\n";
  print_usage();
}
if (!(($opt_a) xor ($opt_A))) {
if ($opt_a && $opt_A) {
  if ($opt_a =~ /^(sha|SHA|md5|MD5)$/) {
    $snmpauthproto = $opt_a;
    $snmparg .= " -a " . $snmpauthproto;
  }
  else {
    print "Unknown SNMP authentication protocol.\n";
    print_usage();
  }
  if ($opt_A) {
    $snmpauthpass = $opt_A;
    $snmparg .= " -A " . $snmpauthpass;
    $auth = 1;
  }
  else {
    print "SNMP authentication password not specified.\n";
    print_usage();
  }
}
else {$auth = 0;}
}
else {
  print "Missing some of authentication parameters.\n";
  print_usage();
}
 if ($auth = 1) {
  if ($priv = 1) {
   $snmplevel = "authPriv";
  }
  else {
   $snmplevel = "authNoPriv";
  }
 }
 else {
  $snmplevel = "noAuthNoPriv";
 }
 $snmparg .= " -l " . $snmplevel;
}
elsif ($version =~ /^(1|2c)$/){
  if ($opt_C){
    $community = $opt_C;
  }
  else {
    $community = "public";
  }
  $snmparg .= " -c " . $community;

}
  if ($opt_I){
    $tftp_IP = $opt_I;
  }
  else {
    print "IP Address of TFTP server not specified\n";
    print_usage();
  }
  if ($opt_T){
    $config_type = $opt_T;
    #check if a valid config type was specified
    switch ($opt_T) {
      case "running" {}
      case "current" {
         $config_type = "running";
        }
      case "startup" {}
      else {
        print "Invalid configuration type specified\n";
        print_usage();
      }
    }
  }
  else {
    print "Configuration type not specified\n";
    print_usage();
  }
  if ($opt_L){
    $config_path = $opt_L;
  }
  else {
    print "Path to configuration backup directory not specified\n";
    print_usage();
  }
  if ($opt_l){
    $tftp_path = $opt_l;
  }
  else {
    print "Path to tftp directory not specified\n";
    print_usage();
  }
  if ($opt_N){
    $device_name = $opt_N;
  }
  else {
    $device_name = $hostip;
  }
  if ($opt_t){
    $timeout = $opt_t;
  }
  else {
    $timeout = 60;
  }
}

sub check_backup_directory {
  #check if the path to the config root exists
  unless (-e $config_path) {
    print "The path to the configuration backup directory does not exist.\n";
    #nagios interprets exit code of 2 as critical
    exit 2;
  }
  #check if the path to the config root is writeable
  unless(-w $config_path) {
    print "The path to the configuration backup directory is not writeable.\n";
    #nagios interprets exit code of 2 as critical
    exit 2;
  }
}

sub check_device_backup_directory {
  #check if the path to the devices folder already exists and create if needed
  unless (-e $config_path . '/' . $device_name) {
    mkdir $config_path . '/' . $device_name;
  }
  #check if the path to the devices folder is writeable
  unless(-w $config_path . '/' . $device_name) {
    print "The path to the devices backup directory is not writeable.\n";
    #nagios interprets exit code of 2 as critical
    exit 2;
  }
}

sub check_tftp_directory {
  #check if the path to the tftp folder exists
  unless (-e $tftp_path) {
    print "The path to the tftp directory does not exist.\n";
    #nagios interprets exit code of 2 as critical
    exit 2;
  }
  #check if the path to the tftp folder is writeable
  unless(-w $tftp_path) {
    print "The path to the tftp directory is not writeable.\n";
    #nagios interprets exit code of 2 as critical
    exit 2;
  }
}

sub get_sysoid_and_vendor {
  #check sysOID
  $sysoid = `snmpget -O qvn $snmparg $hostip 1.3.6.1.2.1.1.2.0`;
  #extract vendor enterprise ID
  $vendor = $sysoid;
  $vendor =~ s/^\.1\.3\.6\.1\.4\.1\.([0-9]*)[\s\S]*/\1/;
}

sub make_backup {
  switch ($vendor) {
        #Cisco
        case "9" {
                print "Backup Cisco config...\n";
                `snmpset $snmparg $hostip 1.3.6.1.4.1.9.9.96.1.1.1.1.2.$randomint i 1 .1.3.6.1.4.1.9.9.96.1.1.1.1.3.$randomint i 4 .1.3.6.1.4.1.9.9.96.1.1.1.1.4.$randomint i 1 .1.3.6.1.4.1.9.9.96.1.1.1.1.5.$randomint a \"$tftp_IP\" .1.3.6.1.4.1.9.9.96.1.1.1.1.6.$randomint s \"$device_name-$config_type-confg-temp.cfg\" .1.3.6.1.4.1.9.9.96.1.1.1.1.14.$randomint i 4`;
        }
        #H3C
        case "25506" {
                print "backup H3C config...\n";
                switch ($config_type) {
                        case "running" {$cfg_type = 3;}
                        case "startup" {$cfg_type = 6;}
                        else {print "Fail!"; exit 2;}
                }
                `snmpset $snmparg $hostip 1.3.6.1.4.1.25506.2.4.1.2.4.1.2.$randomint i $cfg_type 1.3.6.1.4.1.25506.2.4.1.2.4.1.3.$randomint i 2 1.3.6.1.4.1.25506.2.4.1.2.4.1.4.$randomint s $device_name-$config_type-confg-temp\.cfg 1.3.6.1.4.1.25506.2.4.1.2.4.1.5.$randomint a $tftp_IP 1.3.6.1.4.1.25506.2.4.1.2.4.1.9.$randomint i 4`
        }
        else { print "Device enterprise ID \"".$vendor."\" = unknown => no backup\n"; exit 2; }
  }
}

sub tftp_config {
  #if there is an old temp config for some reason, delete it
  if (-e $tftp_path . '/' . $device_name . "-" . $config_type . "-confg-temp.cfg") {
    unlink($tftp_path . '/' . $device_name . "-" . $config_type . "-confg-temp.cfg");
  }
  #touch the file we are going to transfer so tftpd will allow us to accept the
  #incoming file. We also need to set the perms to 0777
  touch($tftp_path . '/' . $device_name . "-" . $config_type . "-confg-temp.cfg");
  chmod 0777, "$tftp_path/$device_name-$config_type-confg-temp.cfg";
  #use snmp get to get device sysOID and its vendor enterprise ID
  get_sysoid_and_vendor();
  #set a random number to use with SNMPset. this is what identifies the current
  #snmpset session.
  $randomint = int(rand(999));
  #use snmp set to make the device TFTP its config to us
  make_backup();
  #loop until we see a temp file or timeout is up
  $timer = 0;
  until (-e $tftp_path . '/' . $device_name . "-" . $config_type . "-confg-temp.cfg") {
    sleep(1);
    $timer = $timer + 1;
    if ($timer >= $timeout) {
      print "TFTP transfer timed out after " . $timer . " seconds\n";
      #nagios interprets exit code of 2 as critical
      exit 2;
    }
  }
  #cause the script to sleep for 20 seconds to make sure the file is finished
  #transferring before we try to act on it.
  sleep(20);
  #convert to unix text format and move the newly TFTPed config to the device directory for analysis
  `dos2unix "$tftp_path$device_name-$config_type-confg-temp.cfg"`;
  move($tftp_path . '/' . $device_name . "-" . $config_type . "-confg-temp.cfg",$config_path . '/' . $device_name . '/' . $device_name . "-" . $config_type . "-confg-temp.cfg");
  #pull the file into an array so we can grep out some unneeded lines.
  tie @text, 'Tie::File', "$config_path/$device_name/$device_name-$config_type-confg-temp.cfg"
    or die "Could not Tie config file in sub tftp_config: $!\n";
  #grep out the lines we don't want.
  @text = grep (!/NVRAM config last updated at|Last configuration change at|No configuration change since last restart|ntp clock-period/, @text);
  #commit changes back to original file
  untie @text;
  #change permissions on file
  chmod 0775, "$config_path/$device_name/$device_name-$config_type-confg-temp.cfg";
}

sub analyze_config {
  #check if there is an existing config to compare to
  if (-e $config_path . '/' . $device_name . '/' . $device_name . "-" . $config_type . "-confg-current") {
    #diff the backed up config with the new temp config
    $diff_result = `diff -U 7 \"$config_path/$device_name/$device_name-$config_type-confg-current\" \"$config_path/$device_name/$device_name-$config_type-confg-temp.cfg\" | grep -v -a -e \'---\' -e \'+++\' -e \'@@\'`;
    #if there is no difference, then delete the temp config and set ok status
    if ($diff_result eq "") {
      unlink($config_path . '/' . $device_name . '/' . $device_name . "-" . $config_type . "-confg-temp.cfg");
      print "Status is OK\n";
      #nagios interprets exit code of 0 as OK
      $status = 0;
    }
    else {
      #create a timestamp for backing up the old config
      @now = localtime();
      $timeStamp = sprintf("%04d%02d%02d%02d%02d%02d",
                          $now[5]+1900, $now[4]+1, $now[3],
                          $now[2],      $now[1],   $now[0]);
      #backup the old config
      move($config_path . '/' . $device_name . '/' . $device_name . "-" . $config_type . "-confg-current",$config_path . '/' . $device_name . '/' . $device_name . "-" . $config_type . "-confg-" . $timeStamp);
      #rename the temp config as the new current config
      move($config_path . '/' . $device_name . '/' . $device_name . "-" . $config_type . "-confg-temp.cfg",$config_path . '/' . $device_name . '/' . $device_name . "-" . $config_type . "-confg-current");
      #print out the diff results
      print "The following changes were made to " . $device_name . "\n\n";
      print "Added lines are indicated by a +\n";
      print "Removed lines are indicated by a -\n\n";
      print "================================================================================\n";
      print $diff_result;
      print "================================================================================\n";
      #set warning status
      #nagios interprets exit code of 1 as warning
      $status = 1;
    }
  }
  #if there was no existing config to compare to, then just rename the temp
  #config as the new current and set OK status
  else {
    move($config_path . '/' . $device_name . '/' . $device_name . "-" . $config_type . "-confg-temp.cfg",$config_path . '/' . $device_name . '/' . $device_name . "-" . $config_type . "-confg-current");
    print "Status is OK\n";
    #nagios interprets exit code of 0 as OK
    $status = 0;
  }
}

sub print_usage {
  print << "USAGE";

--------------------------------------------------------------------------------
$script v$script_version

Uses SNMP to initiate backup of Cisco configuration to TFTP. After backup the
config can be compared to the last backup and alert with any changes.

Usage: check_cisco_config.pl -H <hostip> -v <SNMPversion> -C <SNMPcommunity> -a [SHA|MD5] -A <SNMPauthPassword> -x [AES|DES] -X <SNMPprivacyPassword> -u <SNMPuser> -I <TFTP IP>
-T <ConfigType> -L <config path> -l <tftp path> -N <device name>

Options: -H     IP address
         -C     Community (default is public)
         -I     IP address of the tftp server
         -T     Configuration type to backup [running] [startup]
         -L     Local absolute path to root of the configuration backup
                directory
         -l     Local absolute path to the TFTP root
                Used when the TFTP root is at a lower level than the desired
                configuration backup directory.
         -N     Optional device name. (default is IP address specified for -H)

USAGE
  #nagios interprets exit code of 2 as Critical
  exit 2;
}
