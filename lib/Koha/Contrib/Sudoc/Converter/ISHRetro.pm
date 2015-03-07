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

package Koha::Contrib::Sudoc::Converter::ISHRetro;
use Moose;

extends 'Sudoc::Converter';

use MARC::Moose::Field::Std;
use YAML;
use Locale::TextDomain 'fr.tamil.sudoc';





override 'merge' => sub {
    my ($self, $sudoc, $koha) = @_;

    my @tags = ( (map { sprintf("6%02d", $_) } ( 0..99 )), '995');
    for my $tag (@tags) {
        my @fields = $sudoc->field($tag); 
        next unless @fields;
        $koha->append(@fields);
    }

    my @all_tags = map { sprintf("%03d", $_) } ( 1..999 );
    for my $tag (@all_tags) {
        next if $tag ~~ @tags || $tag == '410'; # On passe, déjà traité plus haut
        my @fields = $sudoc->field($tag);
        next unless @fields;
        next if $koha->field($tag);
        $koha->append(@fields);
    }

    $sudoc->fields( $koha->fields );
};


# Les champs à supprimer de la notice entrante.
my @todelete = qw(035 917 930 991 999);

after 'clean' => sub {
    my ($self, $record) = @_;

    # Suppression des champs SUDOC dont on ne veut pas dans le catalogue
    $record->fields( [ grep { not $_->tag ~~ @todelete } @{$record->fields} ] );
};


1;
