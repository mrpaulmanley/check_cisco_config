#!/usr/bin/perl

use Getopt::Std;
use Switch;
use Tie::File;
use File::Copy;

#Script name and version. Used when printing the usage page
$script = "check_cisco_config.pl";
$script_version = "0.2";

check_arguments ();
check_backup_directory ();
check_device_backup_directory ();
check_tftp_directory ();
tftp_config ();
analyze_config ();
exit $status;

sub check_arguments {
  getopts("H:C:I:T:L:l:S:N:t");
  if ($opt_H){
    $hostip = $opt_H;
  }
  else {
    print "Host IP address not specified\n";
    print_usage();
  }
  if ($opt_C){
    $community = $opt_C;
  }
  else {
    $community = "public";
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
    $timeout = 30;
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

sub tftp_config {
  #if there is an old temp config for some reason, delete it
  if (-e $tftp_path . '/' . $device_name . "-confg-temp") {
    unlink($tftp_path . '/' . $device_name . "-confg-temp");
  }
  #set a random number to use with SNMPset. this is what identifies the current
  #snmpset session. 
  $randomint = int(rand(999));
  #use snmp set to make the device TFTP its config to us
  `snmpset -c $community -v 2c $hostip 1.3.6.1.4.1.9.9.96.1.1.1.1.2.$randomint i 1 .1.3.6.1.4.1.9.9.96.1.1.1.1.3.$randomint i 4 .1.3.6.1.4.1.9.9.96.1.1.1.1.4.$randomint i 1 .1.3.6.1.4.1.9.9.96.1.1.1.1.5.$randomint a \"$tftp_IP\" .1.3.6.1.4.1.9.9.96.1.1.1.1.6.$randomint s \"$device_name-confg-temp\" .1.3.6.1.4.1.9.9.96.1.1.1.1.14.$randomint i 4`;
  #loop until we see a temp file or timeout is up
  $timer = 0;
  until (-e $tftp_path . '/' . $device_name . "-confg-temp") {
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
  #move the newly TFTPed config to the device directory for analysis
  move($tftp_path . '/' . $device_name . "-confg-temp",$config_path . '/' . $device_name . '/' . $device_name . "-confg-temp");
  #pull the file into an array so we can grep out some unneeded lines.
  tie @text, 'Tie::File', "$config_path/$device_name/$device_name-confg-temp"
    or die "Could not Tie config file in sub tftp_config: $!\n";
  #grep out the lines we don't want.
  @text = grep (!/NVRAM config last updated at|Last configuration change at|No configuration change since last restart|ntp clock-period/, @text);
  #commit changes back to original file
  untie @text;
  #change permissions on file
  chmod 0775, "$config_path/$device_name/$device_name-confg-temp";
}

sub analyze_config {
  #check if there is an existing config to compare to
  if (-e $config_path . '/' . $device_name . '/' . $device_name . "-confg-current") {
    #diff the backed up config with the new temp config
    $diff_result = `diff -U 7 \"$config_path/$device_name/$device_name-confg-current\" \"$config_path/$device_name/$device_name-confg-temp\" | grep -v -a -e \'---\' -e \'+++\' -e \'@@\'`;
    #if there is no difference, then delete the temp config and set ok status
    if ($diff_result eq "") {
      unlink($config_path . '/' . $device_name . '/' . $device_name . "-confg-temp");
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
      move($config_path . '/' . $device_name . '/' . $device_name . "-confg-current",$config_path . '/' . $device_name . '/' . $device_name . "-confg-" . $timeStamp);
      #rename the temp config as the new current config
      move($config_path . '/' . $device_name . '/' . $device_name . "-confg-temp",$config_path . '/' . $device_name . '/' . $device_name . "-confg-current");
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
    move($config_path . '/' . $device_name . '/' . $device_name . "-confg-temp",$config_path . '/' . $device_name . '/' . $device_name . "-confg-current");
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

Usage: check_cisco_config.pl -H <hostip> -C <community> -I <TFTP IP>
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
