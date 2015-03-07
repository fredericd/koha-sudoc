# Copyright (C) 2015 Tamil s.a.r.l. - http://www.tamil.fr
#
# This file is part of Chargeur SUDOC Koha.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Koha::Contrib::Sudoc;
use Moose;

use Modern::Perl;
use YAML qw( LoadFile Dump );
use Koha::Contrib::Sudoc::Koha;
use Koha::Contrib::Sudoc::Spool;
use MARC::Moose::Field::Std;
use MARC::Moose::Field::Control;



# L'instance de Koha de l'ILN courant
has koha => ( is => 'rw', isa => 'Koha::Contrib::Sudoc::Koha', default => sub { Koha::Contrib::Sudoc::Koha->new() } );


# La racine de l'environnement d'exécution du chargeur
has root => (
    is => 'rw',
    isa => 'Str',
    default => sub {
        my $self = shift;
        my $dir = $ENV{SUDOC};
        unless ($dir) {
            say "Il manque la variable d'environnement SUDOC.";
            exit;
        }
        $self->root( $dir );
    },
);

# Le contenu du fichier de config
has c => ( is => 'rw', );

# Le Spool
has spool => ( is => 'rw', isa => 'Koha::Contrib::Sudoc::Spool' );


sub BUILD {
    my $self = shift;

    # L'object Sudoc::Spool
    $self->spool( Koha::Contrib::Sudoc::Spool->new( sudoc => $self ) );

    # Lecture du fichier de config et création du hash branchcode => RCR par ILN
    my $file = $self->root . "/etc/sudoc.conf";
    my $c = LoadFile($file);
    my %branchcode;
    while ( my ($rcr, $branch) = each %{$c->{rcr}} ) {
        $branchcode{$branch} = $rcr;
    }
    $c->{branch} = \%branchcode;
    $self->c($c);
}


# Déplace le PPN (001) d'une notice SUDOC dans une zone Koha
sub ppn_move {
    my ($self, $record, $tag) = @_;

    return unless $tag && length($tag >= 3);

    my $letter;
    if ( $tag =~ /(\d{3})([0-9a-z])/ ) { $tag = $1, $letter = $2; }
    elsif ( $tag =~ /(\d{3})/ ) { $tag = $1 };   

    return if $tag eq '001';

    my $ppn = $record->field('001')->value;
    $record->append(
        $letter
        ? MARC::Moose::Field::Std->new( tag => $tag, subf => [ [ $letter => $ppn ] ] )
        : MARC::Moose::Field::Control->new( tag => $tag, value => $ppn )
    );

    $record->fields( [ grep { $_->tag ne '001' } @{$record->fields} ] );
}

1;
