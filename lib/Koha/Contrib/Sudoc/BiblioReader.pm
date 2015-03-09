package Koha::Contrib::Sudoc::BiblioReader;
#ABSTRACT: Lecture des notices biblio/autorité

use Moose;
use Moose::Util::TypeConstraints;
use MARC::Moose::Record;
use MARC::Moose::Parser::Iso2709;

with 'MooseX::RW::Reader';


has koha => ( is => 'rw', isa => 'Koha::Contrib::Sudoc::Koha', required => 1 );

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
