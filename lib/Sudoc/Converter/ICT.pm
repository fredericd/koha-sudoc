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

package Sudoc::Converter::ICT;
use Moose;

extends 'Sudoc::Converter';

use MARC::Moose::Field::Std;
use YAML;


# Création des exemplaires Koha en 995 en fonction des données locales SUDOC
after 'itemize' => sub {
    my ($self, $record) = @_;
};


# Les champs à supprimer de la notice entrante.
my @todelete = qw( 915 917 930 991 999);
 
after 'clean' => sub {
    my ($self, $record) = @_;

    # Suppression des champs SUDOC dont on ne veut pas dans le catalogue
    # Koha
    $record->fields( [ grep { not $_->tag ~~ @todelete } @{$record->fields} ] );

    # On détermine le type de doc biblio
    my $tdoc;
    if ( my $field = $record->field('995') ) {
        $tdoc = $field->subfield('r');
        $tdoc = 'MONO' unless $tdoc;
    }
    if ( $tdoc ) {
        $record->append( MARC::Moose::Field::Std->new(
            tag => '915', subf => [ [ a => $tdoc ], [ b => '0' ] ] ) );
    }
};

1;
