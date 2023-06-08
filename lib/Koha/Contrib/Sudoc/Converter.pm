package Koha::Contrib::Sudoc::Converter;
# ABSTRACT: Classe de base pour convertir les notices

use Moose;
use utf8;
use Modern::Perl;

# Moulinette SUDOC
has sudoc => ( is => 'rw', isa => 'Koha::Contrib::Sudoc', required => 1 );

=attr log

Logger L<Log::Dispatch> hérité de la classe parente L<Koha::Contrib::Sudoc::Loader>.

=cut
has log => ( is => 'rw', isa => 'Log::Dispatch' );

=attr item

Les exemplaires courants. 

 ->{rcr}->{id}->{915}
              ->{930}
              ->{999}
 076797597:
   915:
   917:
   930:
   999:
 243615450:
   915:
   930:
   991:

=cut
has item => ( is => 'rw', isa => 'HashRef' );


=head1 DESCRIPTION

Les méthodes de cette classe sont appelées dans un certain ordre par
le chargeur des notices biblios, selon qu'il s'agisse d'une nouvelle
notice ou d'une notice qui existe déjà dans Koha:

 Méthode       ajout  modif 
 --------------------------
 build           0      0
 skip            O      O
 init            O      O
 authoritize     O      O
 linking         O      O
 itemize         O      O
 merge           N      O
 clean           O      O
 framework       O      N
 biblio_add      O      N
 biblio_modif    N      O

Il y a en plus la méthode end() qui est appelée à la fin du traitement de
toutes les notices du fichier.

=cut

=method build

Fabrique les structures de données nécessaires pour la notice qu'on s'apprête à
traiter.

=cut
sub build {
    my ($self, $record) = @_;

    # On crée la structure de données items
    my $myrcr = $self->sudoc->c->{rcr};
    my $item = {};
    for my $field ( @{$record->fields} ) {
        next if ref $field eq 'MARC::Moose::Field::Control';
        my $value = $field->subfield('5');
        next unless $value;
        my ($rcr, $id) = $value =~ /(.*):(.*)/;
        next unless $rcr; # Probablement un champ 035
        unless ( $myrcr->{$rcr} ) {
            # Cas, improbable, d'un RCR qui ne serait pas dans la liste des RCR
            # FIXME On pourrait le logguer quelque part.
            next;
        }
        $item->{$rcr} ||= {};
        $item->{$rcr}->{$id} ||= {};
        $item->{$rcr}->{$id}->{$field->tag} = $field;
    }
    $self->item($item);
}


=method skip

La notice doit-elle être passée ? Par défaut, on garde toute notice.

=cut
sub skip {
    return 0;
}


=method init

Méthode appelée après C<skip> pour un enregistrement SUDOC entrant, que ce soit
un doublon ou une nouvelle notice.  Suppression de la notice entrante des
champs définis dans C<sudoc.conf> : C<biblio-exclure>

=cut
sub init {
    my ($self, $record) = @_;

    # On supprime de la notice SUDOC les champs à exclure
    my $exclure = $self->sudoc->c->{biblio}->{exclure};
    if ( $exclure && ref($exclure) eq 'ARRAY' ) {
        my %hexclure;
        $hexclure{$_} = 1 for @$exclure;
        $record->fields( [ grep { not $hexclure{$_->tag} } @{$record->fields} ] );
    }
}


=method authoritize

On remplit le $9 Koha des champs liés à des autorités

=cut
sub authoritize {
    my ($self, $record) = @_;

    # Ne rien faire si c'est demandé pour l'ILN
    return unless $self->sudoc->c->{biblio}->{authoritize};

    my $koha = $self->sudoc->koha;
    for my $field ( $record->field('5..|6..|7..') ) {
        my @subf;
        for my $sf ( @{$field->subf} ) {
            my ($letter, $value) = @$sf;
            push @subf, [ $letter => $value ];
            next if $letter ne '3';
            my ($authid, undef) = $koha->get_auth_by_ppn($value);
            push @subf, [ 9 => $authid ] if $authid;
        }
        $field->subf(\@subf);
    }
}


=method linking

Lien des notices biblio entre elles. Les liens entre notices se trouvent dans
les zones 4xx et 5xx, sous-champ $0 qui contient un PPN. A partir du PPN, la
notice liée est retrouvée dans Koha et son biblionumber est placée en $9, le
$0 étant conservé.

=cut
sub linking {
    my ($self, $record) = @_;

    # Ne rien faire si c'est demandé pour l'ILN
    return unless $self->sudoc->c->{biblio}->{linking};

    my $koha = $self->sudoc->koha;
    for my $field ( $record->field('4..|5..') ) {
        my @subf;
        for my $sf ( @{$field->subf} ) {
            my ($letter, $value) = @$sf;
            push @subf, [ $letter => $value ];
            next if $letter ne '0';
            my ($biblionumber) = $koha->get_biblio_by_ppn($value);
            push @subf, [ '9' => $biblionumber ] if $biblionumber;
        }
        $field->subf(\@subf);
    }
}


=method itemize

Création des exemplaires Koha en 995 en fonction des données locales SUDOC, au
moyen de la structure de données $self->item. Les champs bib propriétaire
($b), bib détentrice ($c), code à barres ($f) et cote ($k) sont remplis.

=cut
sub itemize {
    my ($self, $record, $koha_record) = @_;

    # Ne rien faire si c'est demandé pour l'ILN
    return unless $self->sudoc->c->{biblio}->{itemize};

    # Pas d'exemplarisation si on modifie une notice Koha
    return if $koha_record;

    my $myrcr = $self->sudoc->c->{rcr};
    my $item = $self->{item};

    # On crée les exemplaires à partir de 930 et 915
    while ( my ($rcr, $item_rcr) = each %$item ) {
        my $branch = $myrcr->{$rcr};
        while ( my ($id, $ex) = each %$item_rcr ) { # Les exemplaires d'un RCR
            # On prend le code à barres en 915$b, et s'il n'y en a pas on prend
            # l'EPN SUDOC ($id)
            my $barcode = $ex->{915};
            $barcode = $barcode->subfield('b')  if $barcode;
            $barcode = $id unless $barcode;
            my $cote = $ex->{930}->subfield('a');
            $record->append( MARC::Moose::Field::Std->new(
                tag => '995',
                subf => [
                    [ b => $branch ],
                    [ c => $branch ],
                    [ f => $barcode ],
                    [ k => $cote ],
                ]
            ) );
        }
    }
}


sub _key_dedup {
    join('', map { lc $_->[1] } grep { $_->[0] =~ /[a-z]/; } @{shift->subf});
}


=method merge

Fusion d'une notice entrante Sudoc avec une notice Koha. Les champs "protégés"
sont conservés dans la notices Koha. Tout le reste de la notice est remplacé
par la notice SUDOC. Les champs prorégés sont dédoublonnés entre la notices
Koha et la notice SUDOC.

=cut
sub merge {
    my ($self, $record, $krecord) = @_;

    # On garde les champs "protégés" de la notice Koha
    # On évite les doublons
    my $conf = $self->sudoc->c->{biblio};
    if ( my $proteger = $conf->{proteger} ) {
        my $pt = {}; # Hash de hash de tag - clé de dédoublonnage
        for my $tag ( @$proteger ) {
            $pt->{$tag} ||= {};
            for my $field ( $record->field($tag) ) {
                my $key = _key_dedup($field);
                next unless $key;
                $pt->{$tag}->{$key} = undef;
            }
        }
        for my $tag ( @$proteger ) { 
            my @fields = $krecord->field($tag);
            next unless @fields;
            if ( exists $pt->{$tag} ) {
                my @keeps;
                for my $field (@fields) {
                    my $key = _key_dedup($field);
                    next unless $key;
                    push @keeps, $field  unless exists $pt->{$tag}->{$key};
                }
                $record->append(@keeps);
            }
            else {
                $record->append(@fields);
            }
        }
    }
}


=method clean

On nettoie la notice : suppression de champs, ajout auto de champs, etc. Cette
opération est faite après la fusion (éventuelle) de notices.

=cut
sub clean {
    my ($self, $record) = @_;
}


=method framework

Le framework auquel affecter la notice biblio. Valeur par défaut prise dans
C<sudoc.conf>.  Peut-être surchargée pour attribuer un framework différent en
fonction du type de doc ou de tout autre critère.

=cut
sub framework {
    my ($self, $record) = @_;
    $self->sudoc->c->{biblio}->{framework} || '';
}


=method biblio_modify

=cut
sub biblio_modify {
    my ($self, $record, $biblionumber, $framework) = @_;
    $self->log->debug(
        "  Notice après traitement :\n" . $self->sudoc->record_as_text($record) );
    $self->log->notice("  * Remplace $biblionumber\n" );
}


=method biblio_add

=cut
sub biblio_add {
    my ($self, $record, $biblionumber, $framework) = @_;

    $self->log->debug(
        "  Notice après traitement :\n" . $self->sudoc->record_as_text($record) );
    my $plus = '';
    $plus = " $biblionumber $framework" if $biblionumber;
    $self->log->notice( "  * Ajout$plus\n" );
}


=method end

Appelé en fin de traitement du fichier Sudoc. Un converter peut générer ici des
états de synthèse.

=cut
sub end { }

1;
