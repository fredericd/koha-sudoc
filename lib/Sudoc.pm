# Copyright (C) 2011 Tamil s.a.r.l. - http://www.tamil.fr
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

package Sudoc;
use Moose;

use FindBin qw( $Bin );
use lib "$Bin/../lib";
use YAML qw( LoadFile Dump );
use Koha;
use Sudoc::Spool;
use MARC::Moose::Field::Std;
use MARC::Moose::Field::Control;



# L'ILN sélectionnée
has iln => (
    is => 'rw',
    isa => 'Str',
    trigger => sub {
        my ($self, $iln) = @_;
        my $conf = $self->c->{$iln};
        unless ($conf) {
            print "L'ILN $iln est absent de sudoc.conf\n";
            exit;
        }
        $self->koha( Koha->new( conf_file => $self->c->{$iln}->{koha_conf} ) );
    }
);

# L'instance de Koha de l'ILN courant
has koha => ( is => 'rw', isa => 'Koha' );

# La racine de l'environnement d'exécution du chargeur
has sudoc_root => ( is => 'rw', isa => 'Str' );

# Le contenu du fichier de config
has c => ( is => 'rw', );

# Le Spool
has spool => ( is => 'rw', isa => 'Sudoc::Spool' );


sub BUILD {
    my $self = shift;

    my $sudoc_root = $Bin;
    $sudoc_root =~ s/\/bin$//;
    $self->sudoc_root( $sudoc_root );

    # L'object Sudoc::Spool
    $self->spool( Sudoc::Spool->new( sudoc => $self ) );

    # Lecture du fichier de config et création du hash branchcode => RCR par ILN
    my $file = "$sudoc_root/etc/sudoc.conf";
    my $c = LoadFile($file);
    while ( my ($iln, $conf) = each %$c ) {
        my %branchcode;
        while ( my ($rcr, $branch) = each %{$conf->{rcr}} ) {
            $branchcode{$branch} = $rcr;
        }
        $conf->{branch} = \%branchcode;
    }
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
