package Koha::Contrib::Sudoc;
# ABSTRACT: Chargeur Koha par Tamil

use Moose;
use Modern::Perl;
use YAML qw( LoadFile Dump );
use Koha::Contrib::Sudoc::Koha;
use Koha::Contrib::Sudoc::Spool;
use MARC::Moose::Field::Std;
use MARC::Moose::Field::Control;
use File::Copy;
use File::ShareDir ':ALL';


# L'instance de Koha de l'ILN courant
has koha => ( is => 'rw', isa => 'Koha::Contrib::Sudoc::Koha', default => sub { Koha::Contrib::Sudoc::Koha->new() } );


# La racine de l'environnement d'exécution du chargeur
has root => (
    is => 'rw',
    isa => 'Str',
    default => sub {
        my $self = shift;
        my $root = $ENV{SUDOC};
        unless ($root) {
            say "Il manque la variable d'environnement SUDOC.";
            exit;
        }
        unless ( -d $root ) {
            say "variable d'environnement SUDOC=$root";
            say "Ce répertoire n'existe pas. Il faut le créer, puis initialiser le chargeur si nécessaire.";
            exit;
        }
        unshift @INC, "$root/lib";
        $self->root( $root );
    },
);

# Le contenu du fichier de config
has c => ( is => 'rw', );

# Le Spool
has spool => ( is => 'rw', isa => 'Koha::Contrib::Sudoc::Spool' );


sub BUILD {
    my $self = shift;

    # Lecture du fichier de config et création du hash branchcode => RCR par ILN
    my $file = $self->root . "/etc/sudoc.conf";
    return unless -e $file;
    my $c = LoadFile($file);
    my %branchcode;
    while ( my ($rcr, $branch) = each %{$c->{rcr}} ) {
        $branchcode{$branch} = $rcr;
    }
    $c->{branch} = \%branchcode;
    $self->c($c);

    # L'object Sudoc::Spool
    $self->spool( Koha::Contrib::Sudoc::Spool->new( sudoc => $self ) );
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


# Crée les sous-répertoires d'un ILN, s'ils n'existent pas déjà
sub init {
    my $self = shift;

    say "La variable d'environnement SUDOC définit le répertoire racine : ", $self->root;
    say "Initialisation du répertoire des données du Chargeur SUDOC d'un ILN.";
    chdir($self->root);

    say "Création des répertoire 'etc', 'lib' et 'var'.";
    mkdir $_  for qw/ etc lib var /;

    if ( -f 'etc/sudoc.conf') {
        say "Le fichier 'etc/sudoc.conf' existe déjà. On ne le remplace pas par le fichier modèle.";
    }
    else {
        say "Création d'un fichier modèle 'etc/sudoc.conf'.";
        my $conf_path = dist_file('Koha-Contrib-Sudoc', 'etc/sudoc.conf');
        copy($conf_path, "etc/sudoc.conf");
    }
    
    say "Création des répertoires 'var/log' et 'var/spool'.";
    chdir('var');
    mkdir $_ for qw/ log spool /;

    chdir('spool');
    mkdir $_ for qw/ staged waiting done /;
}

1;

=pod

=head1 DESCRIPTION

Koha::Contrib::Sudoc est le Chargeur Sudoc pour Koha développé par Tamil.
Le fonctionnement de cet outil est décrit ici : 
L<http://www.tamil.fr/sudoc/sudoc.html>.

=cut
