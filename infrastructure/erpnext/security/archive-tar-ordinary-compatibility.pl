#!/usr/bin/env perl
use strict;
use warnings;
use Archive::Tar;
use Cwd qw(abs_path);
use File::Temp qw(tempdir);
use JSON::PP;

die "Wrong Archive::Tar version" unless $Archive::Tar::VERSION eq '3.14';
my $loaded = abs_path($INC{'Archive/Tar.pm'});
die "Unexpected active module" unless $loaded eq '/usr/share/perl/5.40.1/Archive/Tar.pm';
my $directory = tempdir('erp-archive-tar-XXXXXX', TMPDIR => 1, CLEANUP => 1);
chdir $directory or die $!;
my @formats = (['plain.tar', 0], ['gzip.tar.gz', Archive::Tar::COMPRESS_GZIP()],
               ['bzip2.tar.bz2', Archive::Tar::COMPRESS_BZIP()]);
for my $format (@formats) {
    my ($name, $compression) = @$format;
    my $writer = Archive::Tar->new;
    $writer->add_data('synthetic-order.txt', "Synthetic order quantity 12\n");
    $writer->write($name, $compression) or die "Cannot write $name";
    my $reader = Archive::Tar->new;
    $reader->read($name, $compression) or die "Cannot read $name";
    die "Wrong round trip" unless $reader->get_content('synthetic-order.txt') eq "Synthetic order quantity 12\n";
}
open my $listing, '-|', '/usr/bin/ptar', '-tf', 'plain.tar' or die 'ptar list failed';
my $listed = do { local $/; <$listing> };
close $listing or die 'ptar list failed';
die 'Unexpected ptar listing' unless $listed eq "synthetic-order.txt\n";
print JSON::PP->new->canonical->encode({status => 'passed', module => $loaded,
    version => "$Archive::Tar::VERSION", formats => [map { $_->[0] } @formats],
    checks => ['create/read synthetic archives', 'ptar list'], application_data => 'none'}), "\n";
