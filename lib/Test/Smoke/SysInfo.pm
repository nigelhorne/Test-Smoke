package Test::Smoke::SysInfo;
use strict;

# $Id$
use vars qw( $VERSION );
$VERSION = '0.002';

=head1 NAME

Test::Smoke::SysInfo - OO interface to system specific information

=head1 SYNOPSIS

    use Test::Smoke::SysInfo;

    my $si = Test::Smoke::SysInfo->new;

    printf "Number of CPU's: %d\n", $si->ncpu;
    printf "Processor type: %s\n", $si->cpu_type;   # short
    printf "Processor description: %s\n", $si->cpu; # long

=head1 DESCRIPTION

Sometimes one wants a more eleborate description of the system one is smoking.

=head1 METHODS

=over 4

=item Test::Smoke::SysInfo->new( )

Dispatch to one of the OS-specific packages.

=cut

sub new {
    my $proto = shift;
    my $class = ref $proto ? ref $proto : $proto;

    CASE: {
        local $_ = $^O;

        /aix/i        && return bless AIX(),     $class;

        /darwin|bsd/i && return bless BSD(),     $class;

        /hp-?ux/i     && return bless HPUX(),    $class;

        /linux/i      && return bless Linux(),   $class;

        /irix/i       && return bless IRIX(),    $class;

        /solaris|sunos|osf/i 
                      && return bless Solaris(), $class;

        /cygwin|mswin32|windows/i
                      && return bless Windows(), $class;
    }
    return bless Generic(), $class;
}

my %info = map { ($_ => undef ) } qw( ncpu cpu cpu_type host );

sub AUTOLOAD {
    my $self = shift;
    use vars qw( $AUTOLOAD );

    ( my $method = $AUTOLOAD ) =~ s/^.*::(.+)$/\L$1/;

    return $self->{ "_$method" } if exists $info{ "$method" };
}

=item __get_cpu_type( )

This is the short info string about the cpu-type. The L<POSIX> module
should provide one (portably) with C<POSIX::uname()>.

=cut

sub __get_cpu_type {
    require POSIX;
    return (POSIX::uname())[4];
}

=item __get_cpu( )

We do not have a portable way to get this information, so assign
C<_cpu_type> to it.

=cut

sub __get_cpu { return __get_cpu_type() }

=item __get_hostname( )

Get the hostname from C<POSIX::uname()).

=cut

sub __get_hostname {
    require POSIX;
    return (POSIX::uname())[1];
}

sub __get_ncpu { return '' }

=item Generic( )

Get the information from C<POSIX::uname()>

=cut

sub Generic {

    return {
        _cpu_type => __get_cpu_type(),
        _cpu      => __get_cpu(),
        _ncpu     => __get_ncpu(),
        _host     => __get_hostname(),
    };

}

=item AIX( )

Use the L<lsdev> program to find information.

=cut

sub AIX {
    my @lsdev = grep /Available/ => `lsdev -C -c processor -S Available`;
    my( $info ) = grep /^\S+/ => @lsdev;
    ( $info ) = $info =~ /^(\S+)/;
    my( $cpu ) = grep /^enable:[^:\s]+/ => `lsattr -E -O -l $info`;
    ( $cpu ) = $cpu =~ /^enable:([^:\s]+)/;

    return {
        _cpu_type => $cpu,
        _cpu      => $cpu
        _ncpu     => scalar @lsdev,
        _host     => __get_hostname(),
    };
}

=item HPUX( )

Use the L<ioscan> program to find information.

=cut

sub HPUX {
    # here we need something with 'ioscan' ?
    my $hpux = Generic();
    $hpux->{_ncpu} = grep /^processor/ => `ioscan -fnkC processor`;
    return $hpux;
}

=item BSD( )

Use the L<sysctl> program to find information.

=cut

sub BSD {
    my %sysctl;
    foreach my $name ( qw( model machine ncpu ) ) {
        chomp( $sysctl{ $name } = `sysctl hw.$name` );
        $sysctl{ $name } =~ s/^hw\.$name\s*[:=]\s*//;
    }

    return {
        _cpu_type => $sysctl{machine},
        _cpu      => $sysctl{model},
        _ncpu     => $sysctl{ncpu},
        _host     => __get_hostname(),
    };
}

=item IRIX( )

Use the L<hinv> program to get the system information.

=cut

sub IRIX {
    chomp( my( $cpu ) = `hinv -t cpu` );
    $cpu =~ s/^CPU:\s+//;
    chomp( my @processor = `hinv -c processor` );
    my( $cpu_cnt) = grep /\d+.+processors?$/i => @processor;
    my $ncpu = (split " ", $cpu_cnt)[0];
    my $type = (split " ", $cpu_cnt)[-2];

    return {
        _cpu_type => $type,
        _cpu      => $cpu,
        _ncpu     => $ncpu,
        _host     => __get_hostname(),
    };

}

=item __from_proc_cpuinfo( $key, $lines )

Helper function to get information from F</proc/cpuinfo>

=cut

sub __from_proc_cpuinfo {
    my( $key, $lines ) = @_;
    my( $value ) = grep /^\s*$key\s*[:=]\s*/i => @$lines;
    $value =~ s/^\s*$key\s*[:=]\s*//i;
    return $value;
}

=item Linux( )

Use the C</proc/cpuinfo> preudofile to get the system information.

=cut

sub Linux {
    local *CPUINFO;
    my( $type, $cpu, $ncpu ) = ( __get_cpu_type() );

    if ( open CPUINFO, "< /proc/cpuinfo" ) {
        chomp( my @cpu_info = <CPUINFO> );
        close CPUINFO;
        # every processor has its own 'block', so count the blocks
        $ncpu = $type =~ /sparc/
            ? __from_proc_cpuinfo( 'ncpus active', \@cpu_info )
            : scalar grep /^processor\s+:\s+/ => @cpu_info;
        my %info;
        my @parts = $type =~ /sparc/
            ? ('cpu')
            : ('model name', 'vendor_id', 'cpu mhz' );
        foreach my $part ( @parts ) {
            $info{ $part } = __from_proc_cpuinfo( $part, \@cpu_info );
        }
        $cpu = $type =~ /sparc/
            ? $info{cpu}
            : sprintf "%s (%s %.0fMHz)", map $info{ $_ } => @parts
    } else {
    }
    return {
        _cpu_type => $type,
        _cpu      => $cpu,
        _ncpu     => $ncpu,
        _host     => __get_hostname(),
    };
}

=item Solaris( )

Use the L<psrinfo> program to get the system information.

=cut

sub Solaris {

    my( $psrinfo ) = grep /the .* operates .* mhz/ix => `psrinfo -v`;
    my $type = __get_cpu_type();
    my( $cpu, $speed ) = $psrinfo =~ /the (\w+) processor.*at (\d+) mhz/i;
    $cpu .= " (${speed}MHz)";
    my $ncpu = grep /on-line/ => `psrinfo`;

    return {
        _cpu_type => $type,
        _cpu      => $cpu,
        _ncpu     => $ncpu,
        _host     => __get_hostname(),
    };
}

=item Windows( )

Use the C<%ENV> hash to find information. Fall back on the *::Generic
values if these values have been unset or are unavailable (sorry I do
not have Win9[58]).

=cut

sub Windows {

    return {
        _cpu_type => $ENV{PROCESSOR_ARCHITECTURE},
        _cpu      => $ENV{PROCESSOR_IDENTIFIER},
        _ncpu     => $ENV{NUMBER_OF_PROCESSORS},
        _host     => __get_hostname(),
    };
}

1;

=back

=head1 SEE ALSO

L<Test::Smoke::Smoker>

=head1 COPYRIGHT

(c) 2002-2003, Abe Timmerman <abeltje@cpan.org> All rights reserved.

With contributions from Jarkko Hietaniemi, Merijn Brand, Campo
Weijerman.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

See:

=over 4

=item * http://www.perl.com/perl/misc/Artistic.html

=item * http://www.gnu.org/copyleft/gpl.html

=back

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut