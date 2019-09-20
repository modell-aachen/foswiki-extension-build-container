#
# Copyright (C) 2004-2012 C-Dot Consultants - All rights reserved
# Copyright (C) 2008-2010 Foswiki Contributors
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html
#
package Foswiki::Contrib::Build;

use strict;
use JSON;
use Thread::Pool;

our @stageFilters;

=begin TML

---++++ target_stage
stages all the files to be in the release in a tmpDir, ready for target_archive

=cut

sub target_stage {
    my $this    = shift;
    my $project = $this->{project};

    push( @stageFilters, { RE => qr/\.txt$/, filter => 'filter_txt' } );
    push( @stageFilters, { RE => qr/\.pm$/,  filter => 'filter_pm' } );

    $this->{tmpDir} ||= File::Temp::tempdir( CLEANUP => 1 );
    File::Path::mkpath( $this->{tmpDir} );

    $this->copy_fileset( $this->{files}, $this->{basedir}, $this->{tmpDir} );

    foreach my $file ( @{ $this->{files} } ) {
        foreach my $filter (@stageFilters) {
            if ( $file->{name} =~ /$filter->{RE}/ ) {

                #print "FILTER $file->{name} $filter->{RE} $filter->{filter}\n";
                my $fn = $filter->{filter};
                $this->$fn(
                    $this->{basedir} . '/' . $file->{name},
                    $this->{tmpDir} . '/' . $file->{name}
                );
            }
        }
    }
    if ( -e $this->{tmpDir} . '/' . $this->{topic_root} . '.txt' ) {
        $this->cp(
            $this->{tmpDir} . '/' . $this->{topic_root} . '.txt',
            $this->{basedir} . '/' . $project . '.txt'
        );
    }

    $this->apply_perms( $this->{files}, $this->{tmpDir} );

    if ( $this->{other_modules} ) {
        my $libs = join( ':', @INC );
        my @commands = ();
        foreach my $module ( @{ $this->{other_modules} } ) {

            die
"$Foswiki::Contrib::Build::basedir / $module does not exist, cannot build $module\n"
              unless ( -e "$Foswiki::Contrib::Build::basedir/$module" );

            warn "Installing $module in $this->{tmpDir}\n";

            #SMELL: uses legacy TWIKI_ exports
            my $cmd =
"export FOSWIKI_HOME=$this->{tmpDir}; export FOSWIKI_LIBS=$libs; export TWIKI_HOME=$this->{tmpDir}; export TWIKI_LIBS=$libs; cd $Foswiki::Contrib::Build::basedir/$module; perl build.pl handsoff_install";

            push @commands, $cmd;
        }

        my $pool = Thread::Pool->new({
           workers => 3,
           do => sub {
               my ($command) = @_;
               print `$command`;
           },
        });

        foreach my $command ( @commands ) {
           $pool->job($command);
        }
        $pool->shutdown;
    }
    $this->generate_metadatafile();
}

sub generate_metadatafile {
    my $this    = shift;
    my $project = $this->{project};

    my %metadata = (
        date => $this->{DATE},
        release => $this->{RELEASE},
        version => "".$this->{VERSION},
        manifest => $this->{files},
        description => $this->{SHORTDESCRIPTION},
        dependencies => $this->{dependencies}
    );
    my $json = to_json(\%metadata, {utf8 => 1, pretty => 1});
    my $metaDataFile = $this->{basedir} . '/metadata.json';

    open(my $fh, '>:encoding(UTF-8)', $metaDataFile)
      or die "Could not open file '$metaDataFile'";
    print $fh $json;
    close $fh;
    return;
}

1;
