package Koha::Contrib::Sudoc::Spool;
# ABSTRACT: Spool des fichiers de notices

use Moose;
use Modern::Perl;
use File::Copy;


# Le spool se trouve dans le sous-répertore var/spool du répertoire racine
# pointé par la variable d'environnement SUDOC. Les fichiers arrivent de
# l'ABES dans le répertoire 'staged'. Puis quand ils sont entièrement
# téléchargés, ils sont déplacés en 'waiting'. De là, ils sont chargés un à un
# dans Koha. Après chargement, ils sont déplacés en 'done'.

my $types = [
    [
        "Fichiers contenant les autorités qui ont été chargées :",
        'done',
        'c',
    ], 
    [
        "Fichiers contenant les notices biblio qui ont été chargées :",
        'done',
        '[a|b]',
    ], 
    [
        "Fichiers contenant les autorités en attente de chargement :",
        'waiting',
        'c',
    ], 
    [
        "Fichiers contenant les notices biblio en attente de chargement :",
        'waiting',
        '[a|b]',
    ], 
    [
        "Fichiers des autorités en cours de transfert :",
        'staged',
        'c',
    ], 
    [
        "Fichiers de notices biblio en cours de transfert :",
        'staged',
        '[a|b]',
    ], 
];


# Moulinette SUDOC
has sudoc => (
    is => 'rw',
    isa => 'Koha::Contrib::Sudoc',
    required => 1,
);

has root => (
    is => 'rw',
    isa => 'Str',
    lazy => 1,
    builder => '_build_root',
);

sub _build_root { shift->sudoc->root . '/var/spool'; }


sub _sortable_name {
    my $name = shift;
    if ( $name =~ /^TR(\d*)R(\d*)([A-C])(.*)$/ ) {
        my $letter = $3 eq 'A' ? 'B' :
                     $3 eq 'B' ? 'A' : $3;
        $name = sprintf("TR%05dR%05d", $1, $2) . $letter . $4;
    }
    elsif ( $name =~ /^(.*)R(\d*)([A-C])(.*)\.RAW$/ ) {
        my $letter = $3 eq 'A' ? 'B' :
                     $3 eq 'B' ? 'A' : $3;
        $name = "$1R$2$letter$4.RAW";
    }
    return $name;
}


# Retourne les fichiers d'une categorie (staged/waiting/done) et d'un
# type donnée. Par ex: 
# $files = $spool->file('waiting', 'c');
# $files = $spool->file('done', '[a|b]');
sub files {
    my ($self, $where, $type) = @_;
    my $dir = $self->root . "/$where";
    opendir(my $hdir, $dir) || die "Impossible d'ouvrir $dir: $!";
    [ sort { _sortable_name($a) cmp _sortable_name($b) }
        grep { /$type\d{3}.raw$/i } readdir($hdir) ];
}


# Retourne le premier lot de fichiers d'une catégorie et d'un type donnée
sub first_batch_files {
    my ($self, $where, $type) = @_;

    my $files = $self->files($where, $type);
    return $files unless @$files;

    my ($prefix_first) = $files->[0] =~ /^(.*)001.RAW/;
    my @first_files;
    for my $file (@$files) {
        my ($prefix) = $file =~ /^(.*)\d{3}.RAW/;
        last if $prefix ne $prefix_first;
        push @first_files, $file;
    }
    return \@first_files;
}


# Retourne la pathname d'un fichier qu'on retrouve, dans l'ordre, soit
# dans le spool 'waiting' soit dans le spool 'done'. Si le fichier
# n'existe pas, retourne undef.
sub file_path {
    my ($self, $name) = @_;
    
    for my $where (qw /waiting done/) {
        my $path = $self->root . "/$where/$name";
        return $path if -f $path;
    }
    return;
}


# Déplace un fichier dans le spool 'done'
sub move_done {
    my ($self, $name) = @_;
    my $path = $self->root . "/waiting/$name";
    return unless -f $path;
    my $target = $self->root . "/done/$name";
    move($path, $target);   
}


# Déplace tous les fichiers de l'ILN courant de staged dans waiting
sub staged_to_waiting {
    my $self = shift;
    
    my $staged = $self->root . "/staged";
    my $target = $self->root . "/waiting";
    opendir(my $hdir, $staged) || die "Impossible d'ouvrir $staged: $!";
    my @files = sort grep { not /^\./ } readdir($hdir);
    for my $file (@files) {
        move("$staged/$file", $target);
    }
}


# Liste le contenu des répertoires du spool
sub list {
    my $self = shift;
    for ( @$types ) {
        my ($msg, $where, $type) = @$_;
        my $files = $self->sudoc->spool->files($where, $type);
        next unless @$files;
        say $msg;
        my $count = 0;
        for my $file (@$files) {
            $count++;
            print sprintf ("  %3d. ", $count), $file, "\n";
        }
    }

}


sub command {
    my $self = shift;
    if ( @_ ) {
        for my $file (@_) {
            my $path = $self->file_path($file);
            unless ( $path ) {
                say "Le fichier '$file' n'existe pas";
                next;
            }
            say "Fichier $path";
            system( "yaz-marcdump $path | less" );
        }
    }
    else {
        $self->list();
    }
}


1;