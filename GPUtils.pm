###############################################################################
#
# Developed with Kate
#
#  Copyright: Norbert Truchsess
#  All rights reserved
#
#       Contributors:
#         - Marko Oldenburg (CoolTux)
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License,or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################

package GPUtils;
use Exporter qw( import );

use strict;
use warnings;

our %EXPORT_TAGS = (all => [qw(GP_Define GP_Catch GP_ForallClients GP_Import GP_Export GP_RedirectMainFn GP_RestoreMainFn GP_IsRedirectedFn)]);
Exporter::export_ok_tags('all');

#add FHEM/lib to @INC if it's not allready included. Should rather be in fhem.pl than here though...
BEGIN {
  if (!grep(/FHEM\/lib$/,@INC)) {
    foreach my $inc (grep(/FHEM$/,@INC)) {
      push @INC,$inc."/lib";
    };
  };
};

sub GP_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);
  my $module = $main::modules{$hash->{TYPE}};
  return $module->{NumArgs}." arguments expected" if ((defined $module->{NumArgs}) and ($module->{NumArgs} ne scalar(@a)-2));
  $hash->{STATE} = 'defined';
  if ($main::init_done) {
    eval { &{$module->{InitFn}}( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return GP_Catch($@) if $@;
  }
  return undef;
}

sub GP_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}

sub GP_ForallClients($$@)
{
  my ($hash,$fn,@args) = @_;
  foreach my $d ( sort keys %main::defs ) {
    if (   defined( $main::defs{$d} )
      && defined( $main::defs{$d}{IODev} )
      && $main::defs{$d}{IODev} == $hash ) {
      	&$fn($main::defs{$d},@args);
    }
  }
  return undef;
}

sub GP_Import(@)
{
  no strict qw/refs/; ## no critic
  my $pkg = caller(0);
  foreach (@_) {
    *{$pkg.'::'.$_} = *{'main::'.$_};
  }
}

sub GP_Export(@)
{
    no strict qw/refs/;    ## no critic
    my $pkg  = caller(0);
    my $main = $pkg;
    $main =~ s/^(?:.+::)?([^:]+)$/main::$1\_/g;
    foreach (@_) {
        *{ $main . $_ } = *{ $pkg . '::' . $_ };
    }
}

sub GP_RedirectMainFn ($$;$$) {
    my ( $func, $fnew, $fren, $dev ) = @_;
    my $pkg = caller(0);
    $func = 'main::' . $func unless ( $func =~ /^main::/ );
    $fnew = $pkg . '::'      unless ( $fnew =~ /::/ );
    if ( !$fren && $func =~ /::([^:]+)$/ ) {
        $fren = 'main::Main_' . $1;
    }

    no strict qw/refs/;
    if ( !defined( *{$func} ) ) {
        $@ =
            "ERROR: Main subroutine $func() cannot be redirected"
          . ' because it does not exist';
    }
    elsif ( !defined( *{$fnew} ) ) {
        $@ =
            "ERROR: Main subroutine $func() cannot be redirected"
          . " because target subroutine $fnew() does not exist";
    }
    elsif (defined( $main::data{redirectedMainFn} )
        && defined( $main::data{redirectedMainFn}{$func} )
        && $main::data{redirectedMainFn}{$func} ne $fnew )
    {
        $@ =
            "ERROR: Cannot redirect subroutine $func()"
          . ' because it already links to '
          . $main::data{redirectedMainFn}{$func} . '()';
    }
    elsif (defined( $main::data{renamedMainFn} )
        && defined( $main::data{renamedMainFn}{$func} )
        && $main::data{renamedMainFn}{$func} ne $fren )
    {
        $@ =
            "ERROR: Main subroutine $func() can not be renamed to $fren()"
          . ' because it was already renamed to subroutine '
          . $main::data{renamedMainFn}{$func}
          . '() by '
          . $main::data{redirectedMainFn}{$func} . '()';
    }
    return 0 if ($@);

    # only rename once
    unless ( defined( $main::data{renamedMainFn} )
        && $main::data{renamedMainFn}{$func} )
    {
        *{$fren} = *{$func};
        $main::data{renamedMainFn}{$func} = $fren;
    }

    # only link once
    unless ( defined( $main::data{redirectedMainFn} )
        && $main::data{redirectedMainFn}{$func} )
    {
        *{$func} = *{$fnew};
        $main::data{redirectedMainFn}{$func}    = $fnew;
        $main::data{redirectedMainFnDev}{$func} = $dev
          if ( main::IsDevice($dev) );

        main::Log3 undef, 3,
            '['
          . ( caller(1) )[3] . '] '
          . (
            main::IsDevice($dev)
            ? "$dev: "
            : ''
          )
          . "Main subroutine $func() was redirected to use subroutine $fnew()."
          . " Original subroutine is still available as $fren().";
    }

    return $fren;
}

sub GP_RestoreMainFn {
    my ($func) = @_;
    $func = 'main::' . $func unless ( $func =~ /^main::/ );
    no strict qw/refs/;
    return 0 unless ( defined( *{$func} ) );
    if (   defined( $main::data{renamedMainFn} )
        && defined( $main::data{renamedMainFn}{$func} ) )
    {
        *{$func} = *{ $main::data{renamedMainFn}{$func} };

        my $dev =
             defined( $main::data{redirectedMainFnDev} )
          && defined( $main::data{redirectedMainFnDev}{$func} )
          && main::IsDevice( $main::data{redirectedMainFnDev}{$func} )
          ? $main::data{redirectedMainFnDev}{$func}
          : undef;
        main::Log3 undef, 3,
            '['
          . ( caller(1) )[3] . '] '
          . (
            $dev
            ? "$dev: "
            : ''
          )
          . "Original main subroutine $func() was restored and unlinked from "
          . $main::data{redirectedMainFn}{$func};

        delete $main::data{redirectedMainFn}{$func};
        delete $main::data{redirectedMainFnDev}{$func};
        delete $main::data{renamedMainFn}{$func};
        delete $main::data{redirectedMainFn}
          unless ( defined( $main::data{redirectedMainFn} ) );
        delete $main::data{redirectedMainFnDev}
          unless ( defined( $main::data{redirectedMainFnDev} ) );
        delete $main::data{renamedMainFn}
          unless ( defined( $main::data{renamedMainFn} ) );
    }
    if (   defined( $main::data{redirectedMainFn} )
        && defined( $main::data{redirectedMainFn}{$func} ) )
    {
        $@ = "Failed to restore main function $func()";
        main::Log3 undef, 3, "ERROR: " . $@;
        return 0;
    }
    else {
    }
    return $func;
}

sub GP_IsRedirectedFn($) {
    my ($func) = @_;
    $func = 'main::' . $func unless ( $func =~ /^main::/ );
    no strict qw/refs/;
    return undef unless ( defined( *{$func} ) );
    return wantarray
      ? (
        $main::data{redirectedMainFn}{$func},
        (
            defined( $main::data{renamedMainFn} )
              && defined( $main::data{renamedMainFn}{$func} )
            ? $main::data{renamedMainFn}{$func}
            : undef
        )
      )
      : 1
      if ( defined( $main::data{redirectedMainFn} )
        && defined( $main::data{redirectedMainFn}{$func} ) );
    return 0;
}

1;

