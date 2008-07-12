#!/usr/bin/perl -w
#
# Module: vpn-config.pl
# 
# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2006, 2007 Vyatta, Inc.
# All Rights Reserved.
# 
# Authors: Justin Fletcher, Marat Nepomnyashy
# Date: 2007
# Description: Start Openswan VPN based on verified configuration
#
# **** End License ****
# 

use strict;
use lib "/opt/vyatta/share/perl5/";

use constant IKELIFETIME_DEFAULT     => 28800;  # 8 hours
use constant ESPLIFETIME_DEFAULT     => 3600;   # 1 hour
use constant REKEYMARGIN_DEFAULT     => 540;    # 9 minutes
use constant REKEYFUZZ_DEFAULT       => 100;
use constant INVALID_LOCAL_IP        => 254;
use constant VPN_MAX_PROPOSALS       => 10;

use VyattaVPNUtil;
use Getopt::Long;

my $changes_dir;
my $newconfig_dir;
my $config_file;
my $secrets_file;
my $init_script;
GetOptions("changes_dir=s" => \$changes_dir, "newconfig_dir=s" => \$newconfig_dir, "config_file=s" => \$config_file, "secrets_file=s" => \$secrets_file, "init_script=s" => \$init_script);

my $clustering_ip = 0;
my $error = 0;
my $genout;
my $genout_secrets;

$genout .= "# generated by $0\n\n";
$genout_secrets .= "# generated by $0\n\n";


#
# Prepare VyattaConfig object
# 
use VyattaConfig;
my $vc = new VyattaConfig();
my $vcVPN = new VyattaConfig();

if (defined($changes_dir) && $changes_dir ne '') {
    $vc->{_changes_only_dir_base} = $changes_dir;
    $vcVPN->{_changes_only_dir_base} = $changes_dir;
}
if (defined($newconfig_dir) && $newconfig_dir ne '') {
    $vc->{_new_config_dir_base} = $newconfig_dir;
    $vcVPN->{_new_config_dir_base} = $newconfig_dir;
}

$genout .=  "# using 'changes only' directory:   $vcVPN->{_changes_only_dir_base}\n";
$genout .=  "# using 'new config' directory:     $vcVPN->{_new_config_dir_base}\n\n";

$genout_secrets .=  "# using 'changes only' directory:   $vcVPN->{_changes_only_dir_base}\n";
$genout_secrets .=  "# using 'new config' directory:     $vcVPN->{_new_config_dir_base}\n\n";



$vcVPN->setLevel('vpn');

if ($vcVPN->exists('ipsec')) {

    #
    # Check that ESP groups have been specified
    #
    my @esp_groups = $vcVPN->listNodes('ipsec esp-group');
    if (@esp_groups == 0) {
	#$error = 1;
	#print STDERR "VPN configuration error.  No ESP groups configured.  At least one ESP group required.\n";
        # XXX for now this will be checked below for site-to-site peer
    } else {
	foreach my $esp_group (@esp_groups) {
	    my @esp_group_proposals = $vcVPN->listNodes("ipsec esp-group $esp_group proposal");
	    if (@esp_group_proposals == 0) {
		$error = 1;
		print STDERR "VPN configuration error.  No proposals configured for ESP group \"$esp_group\".  At least one proposal required.\n";
	    } elsif (@esp_group_proposals > VPN_MAX_PROPOSALS) {
		$error = 1;
		print STDERR 'VPN configuration error.  A total of ' . @esp_group_proposals . " proposals have been configured for ESP group \"$esp_group\".  The maximum proposals allowed for an ESP group is " . VPN_MAX_PROPOSALS . "\n";
	    } else {
		foreach my $esp_group_proposal (@esp_group_proposals) {
		    my $esp_group_proposal_encryption = $vcVPN->returnValue("ipsec esp-group $esp_group proposal $esp_group_proposal encryption");
		    if (!defined($esp_group_proposal_encryption) || $esp_group_proposal_encryption eq "") {
			$error = 1;
			print STDERR "VPN configuration error.  No encryption specified for ESP group \"$esp_group\" proposal $esp_group_proposal.\n";
		    }
		    my $esp_group_proposal_hash = $vcVPN->returnValue("ipsec esp-group $esp_group proposal $esp_group_proposal hash");
		    if (!defined($esp_group_proposal_hash) || $esp_group_proposal_hash eq "") {
			$error = 1;
			print STDERR "VPN configuration error.  No hash specified for ESP group \"$esp_group\" proposal $esp_group_proposal.\n";
		    }
		}
	    }
	}
    }


    #
    # Check that IKE groups have been specified
    #
    my @ike_groups = $vcVPN->listNodes('ipsec ike-group');
    if (@ike_groups == 0) {
	#$error = 1;
	#print STDERR "VPN configuration error.  No IKE groups configured.  At least one IKE group required.\n";
        # XXX for now this will be checked below for site-to-site peer
    } else {
	foreach my $ike_group (@ike_groups) {
	    my @ike_group_proposals = $vcVPN->listNodes("ipsec ike-group $ike_group proposal");
	    if (@ike_group_proposals == 0) {
		$error = 1;
		print STDERR "VPN configuration error.  No proposals configured for IKE group \"$ike_group\".  At least one proposal required.\n";
	    } elsif (@ike_group_proposals > VPN_MAX_PROPOSALS) {
		$error = 1;
		print STDERR 'VPN configuration error.  A total of ' . @ike_group_proposals . " proposals have been configured for IKE group \"$ike_group\".  The maximum proposals allowed for an IKE group is " . VPN_MAX_PROPOSALS . "\n";
	    } else {
		foreach my $ike_group_proposal (@ike_group_proposals) {
		    my $ike_group_proposal_encryption = $vcVPN->returnValue("ipsec ike-group $ike_group proposal $ike_group_proposal encryption");
		    if (!defined($ike_group_proposal_encryption) || $ike_group_proposal_encryption eq "") {
			$error = 1;
			print STDERR "VPN configuration error.  No encryption specified for IKE group \"$ike_group\" proposal $ike_group_proposal.\n";
		    }
		    my $ike_group_proposal_hash = $vcVPN->returnValue("ipsec ike-group $ike_group proposal $ike_group_proposal hash");
		    if (!defined($ike_group_proposal_hash) || $ike_group_proposal_hash eq "") {
			$error = 1;
			print STDERR "VPN configuration error.  No hash specified for IKE group \"$ike_group\" proposal $ike_group_proposal.\n";
		    }
		}
	    }
	}
    }

    #
    # Check the local key file
    # Note: $local_key_file will be used later when reading the keys
    # 
    my $running_local_key_file = VyattaVPNUtil::rsa_get_local_key_file();
    my $local_key_file = $vcVPN->returnValue('rsa-keys local-key file');
    if (!defined($local_key_file)) {
	$local_key_file = VyattaVPNUtil::LOCAL_KEY_FILE_DEFAULT;
    }
    if ($local_key_file ne $running_local_key_file) {
	    
	# Sanity check the usr specified local_key_file
	#
	# 1). Must start with "/"
	# 2). Only allow alpha-numeric, ".", "-", "_", or "/".
	# 3). Don't allow "//"
	# 4). Verify that it's not a directory
	#
	if ($local_key_file !~ /^\//) {
	    $error = 1;
	    print STDERR "VPN configuration error.  Invalid local RSA key file path \"$local_key_file\".  Does not start with a '/'.\n";
	}
	if ($local_key_file =~ /[^a-zA-Z0-9\.\-\_\/]/g) {
	    $error = 1;
	    print STDERR "VPN configuration error.  Invalid local RSA key file path \"$local_key_file\".  Contains a character that is not alpha-numeric and not '.', '-', '_', '/'.\n";
	}
	if ($local_key_file =~ /\/\//g) {
	    $error = 1;
	    print STDERR "VPN configuration error.  Invalid local RSA key file path \"$local_key_file\".  Contains string \"//\".\n";
	}
	if (-d $local_key_file) {
	    $error = 1;
	    print STDERR "VPN configuration error.  Invalid local RSA key file path \"$local_key_file\".  Path is a directory rather than a file.\n";
	}
	
	if ($error == 0) {
	    if (-r $running_local_key_file && !(-e $local_key_file)) {
		VyattaVPNUtil::vpn_debug "cp $running_local_key_file $local_key_file";
		my ($dirpath) = ($local_key_file =~ m#^(.*/)?.*#s);
		my $rc = system("mkdir -p $dirpath");
		if ($rc != 0) {
		    $error = 1;
		    print STDERR "VPN configuration error.  Could not copy previous local RSA key file \"$running_local_key_file\" to new local RSA key file \"$local_key_file\".  Could not mkdir [$dirpath] $!\n";
		} else {
		    $rc = system("cp $running_local_key_file $local_key_file");
		    if ($rc != 0) {
			$error = 1;
			print STDERR "VPN configuration error.  Could not copy previous local RSA key file \"$running_local_key_file\" to new local RSA key file \"$local_key_file\".  $!\n";
		    }
		}
	    }
	}
    }

    #
    # Version 2
    #
    $genout .= "version 2.0\n";
    $genout .= "\n";
    $genout .= "config setup\n";
    
    #
    # Interfaces
    #
    my @interfaces = $vcVPN->returnValues('ipsec ipsec-interfaces interface');
    if (@interfaces == 0) {
	$error = 1;
	print STDERR "VPN configuration error.  No IPSEC interfaces specified.\n";
    } else {
	$genout .= "\tinterfaces=\"";
	my $counter = 0;
	foreach my $interface (@interfaces) {
	    if ($counter > 0) {
		$genout .= ' ';
	    }
	    $genout .= "ipsec$counter=$interface";
	    ++$counter;
	}
	if (hasLocalWildcard($vcVPN, 0)) {
	    if ($counter > 0) {
		$genout .= ' ';
	    }
	    $genout .= '%defaultroute';
	}
	$genout .= "\"\n";
    }
    
    #
    # NAT traversal
    #
    my $nat_traversal = $vcVPN->returnValue('ipsec nat-traversal');
    if (defined($nat_traversal)) {
	if ($nat_traversal eq 'enable') {
	    $genout .= "\tnat_traversal=yes\n";
	} elsif ($nat_traversal eq 'disable') {
	    $genout .= "\tnat_traversal=no\n";
	} elsif ($nat_traversal ne '') {
	    $error = 1;
	    print STDERR "VPN configuration error.  Invalid value \"$nat_traversal\" specified for 'nat-traversal'.  Only \"enable\" or \"disable\" accepted.\n";
	}
    }

    #
    # NAT networks
    #
    my @nat_networks = $vcVPN->listNodes('ipsec nat-networks allowed-network');
    if (@nat_networks > 0) {
	my $first_nat_net = 1;
	foreach my $nat_network (@nat_networks) {
	    if ($first_nat_net) {
		$genout .= "\tvirtual_private=\"\%v4:$nat_network";
		$first_nat_net = 0;
	    } else {
		$genout .= ",\%v4:$nat_network";
	    }
	    
	    my @nat_network_excludes = $vcVPN->returnValues("ipsec nat-networks allowed-network $nat_network exclude");
	    foreach my $nat_network_exclude (@nat_network_excludes) {
		$genout .= ",\%v4:\!$nat_network_exclude";
	    }
	}
	$genout .= "\"\n";
    }

    #
    # copy-tos
    #
    my $copy_tos = $vcVPN->returnValue('ipsec copy-tos');
    if (defined($copy_tos) && $copy_tos eq 'enable') {
	$genout .= "\thidetos=no\n";
    } else {
	$genout .= "\thidetos=yes\n";
    }

    #
    # Logging
    #
    my $facility = $vcVPN->returnValue('ipsec logging facility');
    my $level = $vcVPN->returnValue('ipsec logging level');
    if ((defined($facility) && $facility ne '') && (!defined($level) || $level eq '')) {
	$error = 1;
	print STDERR "VPN configuration error.  VPN logging facility has been specified without the VPN logging level.  One may not be specified without the other.\n";
    } elsif ((!defined($facility) || $facility eq '') && (defined($level) && $level ne '')) {
	$error = 1;
	print STDERR "VPN configuration error.  VPN logging level has been specified without the VPN logging facility.  One may not be specified without the other.\n";
    }
    
    if (defined($level) and ($level eq "err")) {
	$level = "error"; # This allows the cli to be consistent with syslog.
    }
    if (defined($facility) and defined($level)) {
	$genout .= "\tsyslog=$facility.$level\n";
    }

    my @logmodes = $vcVPN->returnValues('ipsec logging log-modes');
    if (@logmodes > 0) {
	my $debugmode = '';
	foreach my $mode (@logmodes) {
	    if ($mode eq "all") {
		$debugmode = "all";
		last;
	    }
	    if ($debugmode eq '') {
		$debugmode = "$mode";
	    } else {
		$debugmode .= " $mode";
	    }
	}
	$genout .= "\tplutodebug=\"$debugmode\"\n";
    }

    $genout .= "\tnhelpers=5\n";
    $genout .= "\tplutowait=yes\n";

    #
    # Disable implicit connections
    #
    foreach my $conn (qw/clear clear-or-private private-or-clear private block packetdefault/) {
	$genout .= "\n";
	$genout .= "conn $conn\n";
	$genout .= "\tauto=ignore\n";
    }

    #
    # Connection configurations
    #
    my $wildcard_psk = undef;
    my @peers = $vcVPN->listNodes('ipsec site-to-site peer');
    if (@peers == 0) {
	#$error = 1;
	#print STDERR "VPN configuration error.  No peers configured.  At least one peer required.\n";
        print "Warning: There are no site-to-site peers configured for IPSec.\n";
    }
    foreach my $peer (@peers) {
	my $peer_ike_group = $vcVPN->returnValue("ipsec site-to-site peer $peer ike-group");
	if (!defined($peer_ike_group) || $peer_ike_group eq '') {
	    $error = 1;
	    print STDERR "VPN configuration error.  No IKE group specified for peer \"$peer\".\n";
	} elsif (!$vcVPN->exists("ipsec ike-group $peer_ike_group")) {
	    $error = 1;
	    print STDERR "VPN configuration error.  The IKE group \"$peer_ike_group\" specified for peer \"$peer\" has not been configured.\n";
	}

	my $lip = $vcVPN->returnValue("ipsec site-to-site peer $peer local-ip");
	my $authid = $vcVPN->returnValue(
			    "ipsec site-to-site peer $peer authentication id");
	if (!defined($lip) || $lip eq "") {
	    $error = 1;
	    print STDERR "VPN configuration error.  No local IP specified for peer \"$peer\"\n";
	} elsif ($lip ne '0.0.0.0') {
	    # not '0.0.0.0' special case.
	    # check interface addresses.
	    use VyattaMisc;
	    if (!VyattaMisc::isIPinInterfaces($vc, $lip, @interfaces)) {
		
		# Due to Bug 2411, the quick short-term fix
		# as described in comment #4, is to assume
		# that a peer local-ip not found in any of
		# the interfaces on the system must then be
		# a cluster IP.  The commit then proceeds
		# without errors, but the ipsec daemons are
		# not started either.  This will cause a
		# silent failure if the IP mismatch is only
		# due to a user error, but allows VPN/cluster
		# interoperability.
		
		vpn_log("The local-ip address $lip of peer \"$peer\" has not been configured in any of the local interfaces.  Assuming it is configured in clustering.\n");
		$clustering_ip = 1;
		
#				if (VyattaMisc::isClusterIP($vc, $lip)) {
#					# Verified that dealing with a cluster IP.
#					$clustering_ip = 1;
#				} else {
#					$error = 1;
#					print STDERR "VPN configuration error.  Local IP $lip specified for peer \"$peer\" has not been configured in any of the ipsec interfaces or clustering.\n";
#				}
		
	    }
	}

	#
	# Name connection by peer and tunnel
	#
	my @tunnels = $vcVPN->listNodes("ipsec site-to-site peer $peer tunnel");
	if (@tunnels == 0) {
	    $error = 1;
	    print STDERR "VPN configuration error.  No tunnels configured for peer \"$peer\".  At least one tunnel required per peer.\n";
	}
	foreach my $tunnel (@tunnels) {

	    my $peer_tunnel_esp_group = $vcVPN->returnValue("ipsec site-to-site peer $peer tunnel $tunnel esp-group");
	    if (!defined($peer_tunnel_esp_group) || $peer_tunnel_esp_group eq '') {
		$error = 1;
		print STDERR "VPN configuration error.  No ESP group specified for peer \"$peer\" tunnel $tunnel.\n";
	    } elsif (!$vcVPN->exists("ipsec esp-group $peer_tunnel_esp_group")) {
		$error = 1;
		print STDERR "VPN configuration error.  The ESP group \"$peer_tunnel_esp_group\" specified for peer \"$peer\" tunnel $tunnel has not been configured.\n";
	    }
	   
            my $conn_head = "\nconn peer-$peer-tunnel-$tunnel\n";
            $conn_head =~ s/ peer-@/ peer-/;
	    $genout .= $conn_head;
	    
	    #
	    # Assign left and right to local and remote interfaces
	    #
	    if (defined($lip)) {
		if ($lip eq '0.0.0.0') {
		    if (!defined($authid)) {
			print STDERR 'VPN configuration error.  '
			             . 'The "authentication id" must be '
				     . 'configured if local IP is 0.0.0.0.'
				     . "\n";
			$error = 1;
		    } else {
                      $genout .= "\tleft=%defaultroute\n";
                      $genout .= "\tleftid=$authid\n";
                    }
		} else {
		    $genout .= "\tleft=$lip\n";
		}
	    }
	    
	    my $any_peer = 0;
	    my $right;
	    my $rightid = undef;
            if ($peer =~ /^\@/) {
                # peer is an "ID"
                $rightid = $peer;
            }
	    if (($peer eq 'any') or ($peer eq '0.0.0.0')
                or defined($rightid)) {
		$right = '%any';
		$any_peer = 1;
	    } else {
		$right = $peer;
	    }
	    $genout .= "\tright=$right\n";
	    $genout .= "\trightid=$rightid\n" if (defined($rightid));
	    if ($any_peer) {
		$genout .= "\trekey=no\n";
	    }

	    #
	    # Write tunnel configuration
	    #
	    my $leftsubnet = $vcVPN->returnValue("ipsec site-to-site peer $peer tunnel $tunnel local-subnet");
	    if (defined($leftsubnet) && $leftsubnet eq 'any') {
		$leftsubnet = '0.0.0.0/0';
	    }
	    if (defined($leftsubnet)) {
		$genout .= "\tleftsubnet=$leftsubnet\n";
	    }

	    my $remotesubnet = $vcVPN->returnValue("ipsec site-to-site peer $peer tunnel $tunnel remote-subnet");
	    
	    my $rightsubnet;
	    my $allow_nat_networks = $vcVPN->returnValue("ipsec site-to-site peer $peer tunnel $tunnel allow-nat-networks");
	    my $allow_public_networks = $vcVPN->returnValue("ipsec site-to-site peer $peer tunnel $tunnel allow-public-networks");
	    
	    if (defined($allow_nat_networks) && $allow_nat_networks eq 'enable') {
		if (defined($remotesubnet) && $remotesubnet ne "") {
		    $error = 1;
		    print STDERR "VPN configuration error.  The 'remote-subnet' has been specified while 'allow-nat-networks' has been enabled for peer \"$peer\" tunnel $tunnel.  Both not allowed at once.\n";
		}
		
		my @allowed_network = $vcVPN->listNodes('ipsec nat-networks allowed-network');
		if (@allowed_network == 0) {
		    $error = 1;
		    print STDERR "VPN configuration error.  While 'allow-nat-networks' has been enabled for peer \"$peer\" tunnel $tunnel, no global allowed NAT networks have been configured.\n";
		}
		
		$rightsubnet = "%priv";
		if (defined($allow_public_networks) && $allow_public_networks eq "enable") {
		    if (defined($remotesubnet) && $remotesubnet ne "") {
			$error = 1;
			print STDERR "VPN configuration error.  The 'remote-subnet' has been specified while 'allow-public-networks' has been enabled for peer \"$peer\" tunnel $tunnel.  Both not allowed at once.\n";
		    }
		    $rightsubnet .= ",%no";
		}
	    } else {
		$rightsubnet = $remotesubnet;
		if (defined($rightsubnet) && $rightsubnet eq 'any') {
		    $rightsubnet = '0.0.0.0/0';
		}
	    }
	    if (defined($rightsubnet)) {
		$genout .= "\trightsubnet=$rightsubnet\n";
	    }
	    
	    #
	    # Write IKE configuration from group
	    #
	    my $ikelifetime = IKELIFETIME_DEFAULT;
	    $genout .= "\tike=";
	    my $ike_group = $vcVPN->returnValue("ipsec site-to-site peer $peer ike-group");
	    if (defined($ike_group) && $ike_group ne '') {
	        my @ike_proposals = $vcVPN->listNodes("ipsec ike-group $ike_group proposal");
	    
                my $first_ike_proposal = 1;
	        foreach my $ike_proposal (@ike_proposals) {
		    #
		    # Get encryption, hash & Diffie-Hellman  key size
	            #
		    my $encryption = $vcVPN->returnValue("ipsec ike-group $ike_group proposal $ike_proposal encryption");
		    my $hash = $vcVPN->returnValue("ipsec ike-group $ike_group proposal $ike_proposal hash");
		    my $dh_group = $vcVPN->returnValue("ipsec ike-group $ike_group proposal $ike_proposal dh-group");
		
		    #
		    # Write separator if not first proposal
		    #
		    if ($first_ike_proposal) {
		        $first_ike_proposal = 0;
		    } else {
		        $genout .= ",";
		    }
		
		    #
		    # Write values
		    #
		    if (defined($encryption) && defined($hash)) {
		        $genout .= "$encryption-$hash";
		        if (defined($dh_group)) {
			    if ($dh_group eq '2') {
			        $genout .= '-modp1024';
			    } elsif ($dh_group eq '5') {
			        $genout .= '-modp1536';
			    } elsif ($dh_group ne '') {
			        $error = 1;
			        print STDERR "VPN configuration error.  Invalid 'dh-group' $dh_group specified for peer \"$peer\" tunnel $tunnel.  Only 2 or 5 accepted.\n";
			    }
		        }
		    }
		}
	        $genout .= "\n";
	    
	        my $t_ikelifetime = $vcVPN->returnValue("ipsec ike-group $ike_group lifetime");
	        if (defined($t_ikelifetime) && $t_ikelifetime ne '') {
		    $ikelifetime = $t_ikelifetime;
	        }
	        $genout .= "\tikelifetime=$ikelifetime" . "s\n";
	    
	        #
	        # Check for agressive-mode
	        #
	        my $aggressive_mode = $vcVPN->returnValue("ipsec ike-group $ike_group aggressive-mode");
	        if (defined($aggressive_mode)) {
		    if ($aggressive_mode eq 'enable') {
		        $genout .= "\taggrmode=yes\n";
		    } else {
		        $genout .= "\taggrmode=no\n";
		    }
	        }
	    

	        #
	        # Check for Dead Peer Detection DPD
	        #
	        my $dpd_interval = $vcVPN->returnValue("ipsec ike-group $ike_group dead-peer-detection interval");
	        my $dpd_timeout = $vcVPN->returnValue("ipsec ike-group $ike_group dead-peer-detection timeout");
	        my $dpd_action = $vcVPN->returnValue("ipsec ike-group $ike_group dead-peer-detection action");
	        if (defined($dpd_interval) && defined($dpd_timeout) && defined($dpd_action)) {
		    $genout .= "\tdpddelay=$dpd_interval" . "s\n";
		    $genout .= "\tdpdtimeout=$dpd_timeout" . "s\n";
		    $genout .= "\tdpdaction=$dpd_action\n";
		}
	    }

	    #
	    # Write ESP configuration from group
	    #
	    my $esplifetime = ESPLIFETIME_DEFAULT;
	    $genout .= "\tesp=";
	    my $esp_group = $vcVPN->returnValue("ipsec site-to-site peer $peer tunnel $tunnel esp-group");
	    if (defined($esp_group) && $esp_group ne '') {
                my @esp_proposals = $vcVPN->listNodes("ipsec esp-group $esp_group proposal");
                my $first_esp_proposal = 1;
                foreach my $esp_proposal (@esp_proposals) {
		    #
		    # Get encryption, hash
		    #
		    my $encryption = $vcVPN->returnValue("ipsec esp-group $esp_group proposal $esp_proposal encryption");
		    my $hash = $vcVPN->returnValue("ipsec esp-group $esp_group proposal $esp_proposal hash");
		
		    #
		    # Write separator if not first proposal
	            #
		    if ($first_esp_proposal) {
		        $first_esp_proposal = 0;
		    } else {
		        $genout .= ",";
		    }
		
		    #
		    # Write values
		    #
		    if (defined($encryption) && defined($hash)) {
		        $genout .= "$encryption-$hash";
                    }
		}
	        $genout .= "\n";
	    
	        my $t_esplifetime = $vcVPN->returnValue("ipsec esp-group $esp_group lifetime");
	        if (defined($t_esplifetime) && $t_esplifetime ne '') {
		    $esplifetime = $t_esplifetime;
	        }
	        $genout .= "\tkeylife=$esplifetime" . "s\n";

	        my $lower_lifetime = $ikelifetime;
	        if ($esplifetime < $ikelifetime) {
		    $lower_lifetime = $esplifetime;
	        }
	    
	        #
	        # The lifetime values need to be greater than:
	        #   rekeymargin*(100+rekeyfuzz)/100
	        #
	        my $rekeymargin = REKEYMARGIN_DEFAULT;
	        if ($lower_lifetime <= (2 * $rekeymargin)) {
		    $rekeymargin = int($lower_lifetime / 2) - 1;
	        }
	        $genout .= "\trekeymargin=$rekeymargin" . "s\n";
	    
	        #
	        # Mode (tunnel or transport)
	        #
	        my $espmode = $vcVPN->returnValue("ipsec esp-group $esp_group mode");
	        if (!defined($espmode) || $espmode eq '') {
		    $espmode = "tunnel";
	        }
                if ($espmode eq "transport") {
		    if (defined $leftsubnet or defined $rightsubnet) {
			$error = 1;
			print STDERR "VPN configuration error.  Can not use local-subnet or remote-subnet when using transport mode\n";
		    }
		}
	        $genout .= "\ttype=$espmode\n";
	    
	        #
	        # Perfect Forward Secrecy
	        #
	        my $pfs = $vcVPN->returnValue("ipsec esp-group $esp_group pfs");
	        if (defined($pfs)) {
		    if ($pfs eq 'enable') {
		        $genout .= "\tpfs=yes\n";
		    } else {
		        $genout .= "\tpfs=no\n";
		    }
                }

	        #
	        # Compression
	        #
	        my $compression = $vcVPN->returnValue("ipsec esp-group $esp_group compression");
	        if (defined($compression)) {
		    if ($compression eq 'enable') {
		        $genout .= "\tcompress=yes\n";
		    } else {
		        $genout .= "\tcompress=no\n";
                    }
		}
	    }

	    #
	    # Authentication mode
	    #
	    #
	    # Write shared secrets to ipsec.secrets
	    #
	    my $auth_mode = $vcVPN->returnValue("ipsec site-to-site peer $peer authentication mode");
	    if (!defined($auth_mode) || $auth_mode eq '') {
		$error = 1;
		print STDERR "VPN configuration error.  No authentication mode for peer \"$peer\" specified.\n";
	    } elsif (defined($auth_mode) && ($auth_mode eq 'pre-shared-secret')) {
		my $psk = $vcVPN->returnValue("ipsec site-to-site peer $peer authentication pre-shared-secret");
		if (!defined($psk) || $psk eq '') {
		    $error = 1;
		    print STDERR "VPN configuration error.  No 'pre-shared-secret' specified for peer \"$peer\" while 'pre-shared-secret' authentication mode is specified.\n";
		}

		my $right;
		if (($peer eq 'any') or ($peer eq '0.0.0.0')
                    or ($peer =~ /^\@/)) {
		    $right = '%any';
                    if (defined($wildcard_psk)) {
                      if ($wildcard_psk ne $psk) {
                        $error = 1;
                        print STDERR 'VPN configuration error.  '
                                     . 'All dynamic peers must have the same '
                                     . "'pre-shared-secret'.\n";
                      }
                    } else {
                      $wildcard_psk = $psk;
                    }
		} else {
		    $right = $peer;
		}
		my $index1 = ($lip eq '0.0.0.0' && defined($authid))
                             ? "$authid" : $lip;
		$genout_secrets .= "$index1 $right : PSK \"$psk\"\n";
		$genout .= "\tauthby=secret\n";
	    } elsif (defined($auth_mode) && $auth_mode eq 'rsa') {
		
		unless (-r $local_key_file) {
		    $error = 1;
		    if (-e $local_key_file) {
			print STDERR "VPN configuration error.  Invalid local RSA key file path \"$local_key_file\".  Filesystem read permission absent.\n";
		    } else {
			print STDERR "VPN configuration error.  Invalid local RSA key file path \"$local_key_file\".  File absent.  Use the 'vpn rsa-key generate' command to create.\n";
		    }
		}

		$genout .= "\tauthby=rsasig\n";
		my $local_key = VyattaVPNUtil::rsa_get_local_pubkey($local_key_file);
		if (!defined($local_key) || $local_key eq "") {
		    $error = 1;
		    print STDERR "VPN configuration error.  Unable to determine local public key from local key file \"$local_key_file\" for peer \"$peer\".\n";
		} else {
		    $genout .= "\tleftrsasigkey=$local_key\n";
		}

		my $rsa_key_name = $vcVPN->returnValue("ipsec site-to-site peer $peer authentication rsa-key-name");
		if (!defined($rsa_key_name) || $rsa_key_name eq "") {
		    $error = 1;
		    print STDERR "VPN configuration error.  No 'rsa-key-name' specified for peer \"$peer\" while 'rsa' authentication mode is specified.\n";
		} else {
		    my $remote_key = $vcVPN->returnValue("rsa-keys rsa-key-name $rsa_key_name rsa-key");
		    if (!defined($remote_key) || $remote_key eq "") {
			$error = 1;
			print STDERR "VPN configuration error.  No remote key configured for rsa key name \"$rsa_key_name\" that is specified for peer \"$peer\".\n";
		    } else {
			$genout .= "\trightrsasigkey=$remote_key\n";
		    }
		}
		$genout_secrets .=  "include $local_key_file\n";
	    } else {
		$error = 1;
		print STDERR "VPN configuration error.  Unknown authentication mode \"$auth_mode\" for peer \"$peer\" specified.\n";
	    }
	    
	    #
	    # Start automatically
	    #
	    if ($any_peer) {
		$genout .= "\tauto=add\n";
	    } else {
		$genout .= "\tauto=start\n";
	    }
	}
    }
} else {
    #
    # remove any previous config lines, so that when "clear vpn ipsec-process"
    # is called it won't find the vyatta keyword and therefore will not try
    # to start the ipsec process.
    #
    $genout = '';
    $genout .=  "# No VPN configuration exists.\n";
    $genout_secrets .=  "# No VPN configuration exists.\n";
}

if (!(defined($config_file) && ($config_file ne '') && defined($secrets_file) && ($secrets_file ne ''))) {
    print "Regular config file output would be:\n\n$genout\n\n";
    print "Secrets config file output would be:\n\n$genout_secrets\n\n";
    exit (0);
}


if ($error == 0) {
    if ($vcVPN->isDeleted('.') || !$vcVPN->exists('.')
        || $vcVPN->isDeleted('ipsec') || !$vcVPN->exists('ipsec')) {
	if (VyattaVPNUtil::is_vpn_running()) {
	    vpn_exec('ipsec setup --stop', 'stop ipsec');
	}
	if (!VyattaVPNUtil::enableICMP('1')) {
	    $error = 1;
	    print STDERR "VPN commit error.  Unable to re-enable ICMP redirects.\n";
	}
	write_config($genout, $config_file, $genout_secrets, $secrets_file);
    } else {
	if (!VyattaVPNUtil::enableICMP('0')) {
	    $error = 1;
	    print STDERR "VPN commit error.  Unable to disable ICMP redirects.\n";
	}
	# Assumming that if there was a local IP missmatch and clustering is enabled,
	# then the clustering scripts will take care of starting the VPN daemon.
	if ($clustering_ip) {
	    # If the local-ip is provided by clustering, then just write out the configuration,
	    # but do not start the VPN daemon
	    
	    write_config($genout, $config_file, $genout_secrets, $secrets_file);
	    
	    vpn_log("Wrote out configuration to files '$config_file' and '$secrets_file'.  VPN/ipsec daemons not started due to clustering.\n");
	    
	} else {
	    if (VyattaVPNUtil::is_vpn_running()) {
		if (isFullRestartRequired($vcVPN)) {
		    #
		    # Full restart required
		    #
		    write_config($genout, $config_file, $genout_secrets, $secrets_file);
		    vpn_exec('ipsec setup --restart', 'restart ipsec');
		} else {
		    my @conn_down;
		    my @conn_delete;
		    my @conn_replace;
		    my @conn_add;
		    my @conn_up;
		    partial_restart($vcVPN, \@conn_down, \@conn_delete, \@conn_replace, \@conn_add, \@conn_up);

		    foreach my $conn (@conn_down) {
			vpn_exec("ipsec auto --down $conn", "bring down ipsec connection $conn");
		    }
		    foreach my $conn (@conn_delete) {
			vpn_exec("ipsec auto --delete $conn", "delete ipsec connection $conn");
		    }
		    
		    write_config($genout, $config_file, $genout_secrets, $secrets_file);
		    vpn_exec('ipsec auto --rereadall', 're-read ipsec configuration');

		    foreach my $conn (@conn_replace) {
			vpn_exec("ipsec auto --replace $conn", "replace ipsec connection $conn");
		    }
		    foreach my $conn (@conn_add) {
			vpn_exec("ipsec auto --add $conn", "add ipsec connection $conn");
		    }
		    foreach my $conn (@conn_up) {
			vpn_exec("ipsec auto --asynchronous --up $conn", "bring up replaced ipsec connection $conn");
		    }
		    
		}
	    } else {
		write_config($genout, $config_file, $genout_secrets, $secrets_file);
		vpn_exec('ipsec setup --start', 'start ipsec');
	    }
	}
    }
}


#
# If error return error
#
if ($error) {
    print STDERR "VPN configuration commit aborted due to error(s).\n";
    exit(1);
}


#
# Return success
#
exit 0;


sub write_config {
    my ($genout, $config_file, $genout_secrets, $secrets_file) = @_;
    
    open OUTPUT_CONFIG, ">$config_file";
    print OUTPUT_CONFIG $genout;
    close OUTPUT_CONFIG;
    
    open OUTPUT_SECRETS, ">$secrets_file";
    print OUTPUT_SECRETS $genout_secrets;
    close OUTPUT_SECRETS;
}

sub partial_restart {
    my ($vcVPN, $conn_down, $conn_delete, $conn_replace, $conn_add, $conn_up) = @_;
    
    my $debug = 0;

    #
    #
    # Print configuration trees if debug enabled
    #
    
    if ($debug) {
	print "Modified configuration:\n";
	printTree();
	print "\n";
	print "\nUnmodified configuration:\n";
	printTreeOrig();
	print "\n";
    }
    
    #
    # Add and modify connections individually
    #
    my %peers = $vcVPN->listNodeStatus('ipsec site-to-site peer');
    while (my ($peer, $peer_status) = each %peers) {
	
	if ($peer_status eq 'added') {
	    my @tunnels = $vcVPN->listNodes("ipsec site-to-site peer $peer tunnel");
	    foreach my $tunnel (@tunnels) {
		addConnection($peer, $tunnel, $conn_add, $conn_up);
	    }
	} elsif ($peer_status eq 'changed') {
	    my $restart_all_tunnels = 0;
	    if ($vcVPN->isChangedOrDeleted("ipsec site-to-site peer $peer authentication")) {
		$restart_all_tunnels = 1;
	    } elsif ($vcVPN->isChangedOrDeleted("ipsec site-to-site peer $peer ike-group")) {
		$restart_all_tunnels = 1;
	    } elsif ($vcVPN->isChangedOrDeleted("ipsec site-to-site peer $peer local-ip")) {
		$restart_all_tunnels = 1;
	    }
	    my %tunnels = $vcVPN->listNodeStatus("ipsec site-to-site peer $peer tunnel");
	    while (my ($tunnel, $tunnel_status) = each %tunnels) {
		my $conn = "peer-$peer-tunnel-$tunnel";
                $conn =~ s/peer-@/peer-/;
		if ($tunnel_status eq 'added') {
		    addConnection($peer, $tunnel, $conn_add, $conn_up);
		} elsif ($tunnel_status eq 'changed') {
		    replaceConnection($peer, $tunnel, $conn_down, $conn_replace, $conn_up);
		} elsif ($tunnel_status eq 'deleted') {
		    deleteConnection($conn, $conn_down, $conn_delete);
		} elsif ($tunnel_status eq 'static') {
		    if ($restart_all_tunnels || dependenciesChanged($vcVPN, $peer, $tunnel)) {
			replaceConnection($peer, $tunnel, $conn_down, $conn_replace, $conn_up);
		    }
		}
	    }
	} elsif ($peer_status eq 'deleted') {
	    my @tunnels = $vcVPN->listOrigNodes("ipsec site-to-site peer $peer tunnel");
	    foreach my $tunnel (@tunnels) {
		my $conn = "peer-$peer-tunnel-$tunnel";
                $conn =~ s/peer-@/peer-/;
		deleteConnection($conn, $conn_down, $conn_delete);
	    }
	} elsif ($peer_status eq 'static') {
	    my @tunnels = $vcVPN->listNodes("ipsec site-to-site peer $peer tunnel");
	    foreach my $tunnel (@tunnels) {
		if (dependenciesChanged($vcVPN, $peer, $tunnel)) {
		    replaceConnection($peer, $tunnel, $conn_down, $conn_replace, $conn_up);
		}
	    }
	}
    }
}

sub vpn_exec {
    my ($command, $desc) = @_;

    if ($error != 0) {
	return;
    }

    open LOG, ">> /tmp/ipsec.log";
    
    use POSIX;
    my $timestamp = strftime("%Y-%m-%d %H:%M.%S", localtime);
    
    print LOG "$timestamp\nExecuting: $command\nDescription: $desc\n";

    if ($error == 0) {
	my $cmd_out = qx($command);
        my $rval = ($? >> 8);
	print LOG "Output:\n$cmd_out\n---\n";
	print LOG "Return code: $rval\n";
	if ($rval) {
            if ($command =~ /^ipsec auto --asynchronous --up/
                && ($rval == 104 || $rval == 29)) {
                print LOG "OK when bringing up VPN connection\n";
	    } else {
                $error = 1;
                print LOG "VPN commit error.  Unable to $desc, received error code $?\n";
                print STDERR "VPN commit error.  Unable to $desc, received error code $?\n";
                print STDERR "$cmd_out\n";
            }
	}
    } else {
	print LOG "Execution not performed due to previous error.\n";
    }
    
    print LOG "---\n\n";
    close LOG;
}

sub vpn_log {
    my ($log) = @_;
    
    open LOG, ">> /tmp/ipsec.log";
    
    use POSIX;
    my $timestamp = strftime("%Y-%m-%d %H:%M.%S", localtime);
    
    print LOG "$timestamp\n$log\n";
    print LOG "---\n\n";
    close LOG;
}

sub addConnection {
    my ($peer, $tunnel, $conn_add, $conn_up) = @_;
    my $conn = "peer-$peer-tunnel-$tunnel";
    $conn =~ s/peer-@/peer-/;
    push(@$conn_add, $conn);
    if ($peer ne '0.0.0.0') {
	push(@$conn_up,  $conn);
    }
}

sub replaceConnection {
    my ($peer, $tunnel, $conn_down, $conn_replace, $conn_up) = @_;
    my $conn = "peer-$peer-tunnel-$tunnel";
    $conn =~ s/peer-@/peer-/;
    push(@$conn_down, $conn);
    push(@$conn_replace, $conn);
    if ($peer ne '0.0.0.0') {
	push(@$conn_up, $conn);
    }
}

sub deleteConnection {
    my ($conn, $conn_down, $conn_delete) = @_;
    push(@$conn_down, $conn);
    push(@$conn_delete, $conn);
}

sub isFullRestartRequired {
    my ($vcVPN) = @_;
    
    my $restartf = 0;
    
    #
    # Check for configuration differences
    #
    #
    # See what has been changed
    #
    if ($vcVPN->isChangedOrDeleted('ipsec copy-tos')) {
	#
	# Top level system parameter modified; full restart required
	#
	
	$restartf = 1;
    } elsif ($vcVPN->isChangedOrDeleted('ipsec logging')) {
	#
	# Top level system parameter modified; full restart required
	#
	
	$restartf = 1;
    } elsif ($vcVPN->isChangedOrDeleted('ipsec ipsec-interfaces')) {
	#
	# Top level system parameter modified; full restart required
	#
	
	$restartf = 1;
    } elsif ($vcVPN->isChangedOrDeleted('ipsec nat-traversal')) {
	#
	# Top level system parameter modified; full restart required
	#
	
	$restartf = 1;
    } elsif ($vcVPN->isChangedOrDeleted('ipsec nat-networks')) {
	#
	# Top level system parameter modified; full restart required
	#
	# FIXME: in reality this global doesn't affect every tunnel
	
	$restartf = 1;
    } elsif (hasLocalWildcard($vcVPN, 0) != hasLocalWildcard($vcVPN, 1)) {
	# local wild card has changed. this affects ipsec-interfaces.
	$restartf = 1;
    }
    
    return $restartf;
}

sub dependenciesChanged {
    my ($vcVPN, $peer, $tunnel) = @_;
    my $auth_mode = $vcVPN->returnValue("ipsec site-to-site peer $peer authentication mode");
    if (defined($auth_mode) && $auth_mode eq 'rsa') {
	if ($vcVPN->isChangedOrDeleted('rsa-keys local-key')) {
	    return 1;
	}
	my $rsa_key_name = $vcVPN->returnValue("ipsec site-to-site peer $peer authentication rsa-key-name");
	if ($vcVPN->isChangedOrDeleted("rsa-keys rsa-key-name $rsa_key_name")) {
	    return 1;
	}
    }

    my $ike_group = $vcVPN->returnValue("ipsec site-to-site peer $peer ike-group");
    if ($vcVPN->isChangedOrDeleted("ipsec ike-group $ike_group")) {
	return 1;
    }

    my $esp_group = $vcVPN->returnValue("ipsec site-to-site peer $peer tunnel $tunnel esp-group");
    if ($vcVPN->isChangedOrDeleted("ipsec esp-group $esp_group")) {
	return 1;
    }

    return 0;
}

sub printTree {
    my ($vc, $path, $depth) = @_;
    
    my @children = $vc->listNodes($path);
    foreach my $child (@children) {
	print '    ' x $depth;
	print $child . "\n";
	printTree($vc, "$path $child", $depth + 1);
    }
}

sub printTreeOrig {
    my ($vc, $path, $depth) = @_;

    my @children = $vc->listOrigNodes($path);
    foreach my $child (@children) {
	print '    ' x $depth;
	print $child . "\n";
	printTreeOrig($vc, "$path $child", $depth + 1);
    }
}

sub hasLocalWildcard {
    my $vc = shift;
    my $orig = shift;
    my @peers = $vc->listNodes('ipsec site-to-site peer');
    if ($orig) {
	@peers = $vc->listOrigNodes('ipsec site-to-site peer');
    }
    return 0 if (@peers == 0);
    foreach my $peer (@peers) {
	my $lip
	    = $vcVPN->returnValue("ipsec site-to-site peer $peer local-ip");
	if ($orig) {
	    $lip = $vcVPN->returnOrigValue(
				    "ipsec site-to-site peer $peer local-ip");
	}
	return 1 if ($lip eq '0.0.0.0');
    }
    return 0;
}

# end of file
