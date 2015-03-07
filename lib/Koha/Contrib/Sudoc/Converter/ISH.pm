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

package Koha::Contrib::Sudoc::Converter::ISH;
use Moose;

extends 'Sudoc::Converter';

use YAML;

# Moulinette SUDOC
has sudoc => ( is => 'rw', isa => 'Sudoc', required => 1 );




# Création des exemplaires Koha en 995 en fonction des données locales SUDOC
sub itemize {
    my ($self, $record) = @_;
}




1;
