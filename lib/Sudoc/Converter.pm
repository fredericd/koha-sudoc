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

package Sudoc::Converter;
use Moose;

use YAML;

# Moulinette SUDOC
has sudoc => ( is => 'rw', isa => 'Sudoc', required => 1 );


# On supprime un certain nombre de champs de la notice SUDOC entrante
sub clear {
    my ($self, $record) = @_;
}


# Création des exemplaires Koha en 995 en fonction des données locales SUDOC
sub itemize {
    my ($self, $record) = @_;
}


# On remplit le $9 Koha des champs liés à des autorités
sub authoritize {
    my ($self, $record) = @_;

    # Ne rien faire si c'est demandé pour l'ILN
    return unless $self->sudoc->c->{ $self->sudoc->iln }->{biblio}->{authoritize};

    my $zconn = $self->sudoc->koha->zauth();
    for my $field ( $record->field('5..|6..|7..') ) {
        my $ppn = $field->subfield('3');
        next unless $ppn;
        my $rs = $zconn->search_pqf( "\@attr 1=PPN $ppn" );
        if ($rs->size() >= 1 ) {
            my $auth = MARC::Moose::Record::new_from(
                $rs->record(0)->raw(), 'Iso2709' );
            my @sf;
            for ( @{$field->subf} ) {
                push @sf, [ $_->[0] => $_->[1] ];
                push @sf, [ '9' => $auth->field('001')->value ]
                    if $_->[0] eq '3';
            }
            $field->subf(\@sf);
        }
    }
}


# Fusion d'une notice entrante Sudoc avec une notice Koha
sub merge {
    my ($self, $record, $krecord) = @_;
}


1;
