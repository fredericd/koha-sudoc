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

package Koha::BiblioReader;
use Moose;

use Moose::Util::TypeConstraints;

use MARC::Moose::Record;
use MARC::Moose::Parser::Iso2709;

with 'MooseX::RW::Reader';


has koha => ( is => 'rw', isa => 'Koha', required => 1 );

has select => (
    is      => 'rw',
    isa     => 'Str',
    default => 'SELECT biblionumber FROM biblio',
);

has sth => (
    is => 'rw',
    lazy => 1,
    default => sub {
        my $self = shift;
        my $sth  = $self->koha->dbh->prepare( $self->select );
        $sth->execute();
        $self->sth($sth);
    },
);

has parser => (
    is => 'rw',
    default => sub { MARC::Moose::Parser::Iso2709->new() }
);

# Last returned record biblionumber;
has id => ( is => 'rw' );



sub read {
    my $self = shift;

    while ( my ($id) = $self->sth->fetchrow ) {
        if ( my $record = $self->get( $id ) ) {
            $self->count($self->count + 1);
            $self->id( $id );
            return $record;
        }
    }
    return 0;
}


sub get {
    my ($self, $id) = @_;

    my $sth = $self->koha->dbh->prepare(
        "SELECT marc FROM biblioitems WHERE biblionumber=? ");
    $sth->execute( $id );
    my ($marc) = $sth->fetchrow;
    my $record = $self->parser->parse($marc);
    return $record;
}


no Moose;
__PACKAGE__->meta->make_immutable;
1;

=head1 NAME

Koha::BiblioReader - Koha biblio records reader
   
=head1 SYNOPSYS

  # Read all biblio records and returns MARC::Moose::Record objects
  # Do it for a default Koha instace.
  my $reader = Koha::BiblioReader->new( koha => Koha->new() );
  while ( $record = $reader->read() ) {
      ;
  }

  # With a selection of biblios
  my $reader = Koha::BiblioReader->new(
    koha => Koha->new(),
    select => "SELECT biblionumber FROM biblio WHERE biblionumber > 10000",
  );

=head1 COPYRIGHT AND LICENSE

Copyright 2011 by Tamil, s.a.r.l.

L<http://www.tamil.fr>

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl 5 itself.

=cut
