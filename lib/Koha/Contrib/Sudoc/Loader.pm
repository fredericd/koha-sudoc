package Koha::Contrib::Sudoc::Loader;
# ABSTRACT: Classe de base pour le chargement de notices biblio/autorité

use Moose;
use Modern::Perl;
use MARC::Moose::Reader::File::Iso2709;
use Koha::Contrib::Sudoc::Converter;
use Log::Dispatch;
use Log::Dispatch::Screen;
use Log::Dispatch::File;
use Try::Tiny;
use DateTime;


# Moulinette SUDOC
has sudoc => ( is => 'rw', isa => 'Koha::Contrib::Sudoc', required => 1 );

# Fichier des notices biblios/autorités
has file => ( is => 'rw', isa => 'Str', required => 1 );

# Chargement effectif ?
has doit => ( is => 'rw', isa => 'Bool', default => 0 );

# Compteur d'enregistrements traités
has count => (  is => 'rw', isa => 'Int', default => 0 );

# Compteur d'enregistrements ajoutés
has count_added => (  is => 'rw', isa => 'Int', default => 0 );

# Compteur d'enregistrements remplacés
has count_replaced => (  is => 'rw', isa => 'Int', default => 0 );

# Compteur d'enregistrements non traités
has count_skipped => ( is => 'rw', isa => 'Int', default => 0 );

# Converter
has converter => (
    is      => 'rw',
    isa     => 'Koha::Contrib::Sudoc::Converter',
);

# Le logger
has log => (
    is => 'rw',
    isa => 'Log::Dispatch',
    default => sub { Log::Dispatch->new() },
);


sub BUILD {
    my $self = shift;

    my $id = ref($self);
    ($id) = $id =~ /.*:(.*)$/;

    $self->log->add( Log::Dispatch::Screen->new(
        name      => 'screen',
        min_level => 'notice',
    ) );
    $self->log->add( Log::Dispatch::File->new(
        name      => 'file1',
        min_level => 'debug',
        filename  => $self->sudoc->root . "/var/log/$id.log",
        mode      => '>>',
        binmode   => ':encoding(utf8)',
    ) );


    # Instanciation du converter
    my $class = $self->sudoc->c->{biblio}->{converter};
    try {
        Class::MOP::load_class($class);
    } catch {
        $self->log->warning(
            "Attention : le convertisseur $class est introuvable dans le répertoire 'lib'. " .
            "Le convertisseur par défaut sera utilisé.\n");
        $class = 'Koha::Contrib::Sudoc::Converter';
    };
    $class = $class->new(sudoc => $self->sudoc, log => $self->log);
    $self->converter($class);
}


# C'est cette méthodes qui est surchargée par les sous-classes dédiées au
# traitement des notices biblio et d'autorités
sub handle_record {
    my ($self, $record) = @_;
}


sub run {
    my $self = shift;

    my $dt = DateTime->now;
    $self->log->debug($dt->dmy . " " . $dt->hms . "\n");
    $self->log->notice("Chargement du fichier " . $self->file . "\n");
    $self->log->notice("** Test **\n") unless $self->doit;
    my $reader = MARC::Moose::Reader::File::Iso2709->new(
        file => $self->sudoc->spool->file_path( $self->file ) );
    while ( my $record = $reader->read() ) {
        $self->count( $self->count + 1 );
        $self->handle_record($record);
    }
    
    $self->sudoc->spool->move_done($self->file)  if $self->doit;
    $self->log->notice(
         "Nombre d'enregistrements traités : " . $self->count . "\n" .
         "Nombre d'enregistrements ajoutés : " . $self->count_added . "\n" .
         "Nombre d'enregistrements fusionnés : " . $self->count_replaced . "\n" .
         "Nombre d'enregistrements ignorées : " . $self->count_skipped . "\n"
     );
    $self->log->notice("** Test ** Le fichier " . $self->file . " n'a pas été chargé\n")
        unless $self->doit;
    $self->log->debug("\n");
}

1;
