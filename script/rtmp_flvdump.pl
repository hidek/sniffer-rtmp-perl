#!/usr/bin/env perl

use strict;
use warnings;
use FindBin::libs;

use Pod::Usage;
use Getopt::Long;

use Sniffer::RTMP;
use JSON::Syck;

use Data::AMF::IO;

use Time::HiRes qw/gettimeofday tv_interval/;

GetOptions(
    \my %option,
    qw/help/
);
pod2usage(0) if $option{help};

my $dev    = $ARGV[0] or pod2usage(1);
my $output = $ARGV[1] or pod2usage(1);

my $start_t;

open my $fh, ">$output" or die $!;
END { close $fh }

# write flv header
print $fh 'FLV';
print $fh pack('C', 1);
print $fh pack('C', 0b00000101);
print $fh pack('N', 9);
print $fh pack('N', 0);

sub log_method {
    my ($dir, $packet, $method, $id, $args) = @_;

    my $type = $packet->type == 0x14 ? 'invoke' : 'notify';

    print $dir eq 'in' ? '<=' : '>=';
    print " [$type]";
    print " method:$method";
    print " id:$id";

    if (@$args) {
        my $args = join ', ', map { JSON::Syck::Dump($_) } @$args;
        print " args:$args";
    }
    print "\n";
}

sub log_other {
    my $type = shift;

    return sub {
        my ($dir, $packet) = @_;
        print $dir eq 'in' ? '<=' : '>=';
        print " [${type}]\n";

        return unless $dir eq 'in';

        if ($packet->type == 0x08 or $packet->type == 0x09) {
            my $io = Data::AMF::IO->new;

            # packet type
            $io->write_u8( $packet->type );

            # packet data size
            $io->write_u24( $packet->size );

            # relative timestamp
            unless ($start_t) {
                $start_t = [gettimeofday];
                $io->write_u32(0);
            }
            else {
                my $t = tv_interval( $start_t, [gettimeofday] );
                $io->write_u24( int($t*1000) );
                $io->write_u8(0);
            }

            $io->write_u24(0);
            $io->write( $packet->data );

            $io->write_u32( $packet->size + 11 );

            print $fh $io->data;
        }
        elsif ($packet->type == 0x16) {
            print $fh $packet->data;
        }
    };
};

Sniffer::RTMP->new(
    device    => $dev,
    callbacks => {
        chunk_size         => log_other('chunk_size'),
        bytes_read         => log_other('bytes_read'),
        ping               => log_other('ping'),
        server_bw          => log_other('server_bw'),
        client_bw          => log_other('client_bw'),
        audio              => log_other('audio'),
        video              => log_other('video'),
        flex_stream        => log_other('flex_stream'),
        flex_shared_object => log_other('flex_shared_object'),
        flex_message       => log_other('flex_message'),
        notify             => \&log_method,
        shared_object      => log_other('shared_object'),
        invoke             => \&log_method,
        flv_data           => log_other('flv_data'),
        unknown            => log_other('unknown'),
    },
)->run;

=head1 NAME

rtmp_dump.pl - example script to dump rtmp packet

=head1 SYNOPSIS

=head1 AUTHOR

Daisuke Murase <typester@cpan.org>

=head1 COPYRIGHT

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut

1;

