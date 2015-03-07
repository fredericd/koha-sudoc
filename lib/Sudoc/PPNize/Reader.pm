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

package Sudoc::PPNize::Reader;
use Moose;


with 'MooseX::RW::Reader::File';



sub read {
    my $self = shift;

    my $fh = $self->fh;
    
    my $line = <$fh>;
    return 0 unless $line;

    chop $line;
    my ($ppn, $biblionumber) = $line =~ /PPN (.*) : (.*)/;
    return { ppn => $ppn, biblionumber => $biblionumber };
}



no Moose;
__PACKAGE__->meta->make_immutable;
1;

