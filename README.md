check_cisco_config
==================
http://exchange.nagios.org/directory/Plugins/Network-and-Systems-Management/Check_Cisco_Config/details

<pre>
This is a Nagios plugin that will utilize SNMPset and TFTP to backup and alert on changes for Cisco IOS devices.

I successfully use this plugin with the following switches and APs (it probably works with many more, but this is only what I have in production.)

Switches (LANBASE and LANLITE)
2950
2960
2960S
3560

APs (Autonomous)
1200
1231
1242

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

Sample Check Command
# cisco configuration check
    define command {
        command_name    check_cisco_config
        command_line    perl $USER1$/check_cisco_config.pl -H $HOSTADDRESS$ -C private -I 192.168.1.100 -T running -L /usr/local/nagios/cisco_configs -l /usr/local/nagios/tftp -N $HOSTNAME$
    }

Sample Service Template
  define service{
    name                                cisco-config-check-service
    use                                 generic-service
    check_period                        24x7
    max_check_attempts                  1
    normal_check_interval               720
    retry_check_interval                1
    contact_groups                      nagios.admins
    notification_options                w
    notification_interval               240
    notification_period                 24x7
    is_volatile                         1
    register                            0
  }

Note regarding email notifications 
  The default notify-service-by-email includes: 
  Output: $SERVICEOUTPUT$\n 
  $SERVICEOUTPUT$ only includes the first line of service output. 
  This should be replaced with: 
  Output: $SERVICEOUTPUT$\n$LONGSERVICEOUTPUT$\n
  
Note regarding Outlook (all versions)
  http://support.microsoft.com/kb/287816

Note regarding TFTP server
  The files created by your TFTP server must be writable by the Nagios process. 
  Most TFTP servers in Linux do not respect the permissions of the parent 
  directory when creating files. Make sure the permissions your TFTP server is 
  using allow the Nagios process to write to the files.
  
Sample TFTP setup in Ubuntu Gutsy (maybe works in more recent versions?)
  $sudo apt-get install xinetd tftpd tftp
  $sudo vi /etc/xinet.d/tftp
  Add the following lines to the file and save it
    service tftp
    {
    protocol        = udp
    port            = 69
    socket_type     = dgram
    wait            = yes
    user            = nagios
    group           = nagios
    server          = /usr/sbin/in.tftpd
    server_args     = /usr/local/nagios/tftp
    disable         = no
    }

  $sudo /etc/init.d/xinetd restart

Sample creating and securing directories
  $sudo mkdir /usr/local/nagios/cisco_configs
  $sudo mkdir /usr/local/nagios/tftp
  $sudo chmod -R 775 /usr/local/nagios/cisco_configs
  $sudo chmod 770 /usr/local/nagios/tftp
  $sudo chown -R nagios /usr/local/nagios/cisco_configs
  $sudo chgrp -R nagios /usr/local/nagios/cisco_configs
  $sudo chown nagios /usr/local/nagios/tftp
  $sudo chgrp nagios /usr/local/nagios/tftp
</pre>