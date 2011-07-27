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

package Sudoc::Converter;
use Moose;


# Moulinette SUDOC
has sudoc => ( is => 'rw', isa => 'Sudoc', required => 1 );

# Les exemplaires courants. 
# ->{rcr}->{id}->{915}
#              ->{930}
#              ->{999}
# 076797597:
#   915:
#   917:
#   930:
#   999:
# 243615450:
#   915:
#   930:
#   991:
has item => ( is => 'rw', isa => 'HashRef' );


# Les méthodes de cette classe sont appelées dans un certain ordre par
# le chargeur des notices biblios, selon qu'il s'agisse d'une nouvelle
# notice ou d'une notice qui existe déjà dans Koha:
#
# Méthode       ajout  modif 
# skip            0      0
# init            O      O
# authoritize     O      O
# linking         O      O
# itemize         N      O
# merge           O      N
# clean           O      O
# framework       O      N


# La notice doit-elle être passée ? Par défaut, on garde toute notice.
sub skip {
    my ($self, $record) = @_;
    return 0;
}


# Première méthode appelée pour un enregistrement SUDOC entrant, que ce
# soit un doublon ou une nouvelle notice.
# Initialisation du hash item
sub init {
    my ($self, $record) = @_;

    my $myrcr = $self->sudoc->c->{$self->sudoc->iln}->{rcr};
    # On crée la structure de données items
    my $item = {};
    for my $field ( $record->field('9..') ) {
        my $value = $field->subfield('5');
        next unless $value;
        my ($rcr, $id) = $value =~ /(.*):(.*)/;
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

    # On supprime de la notice SUDOC les champs à exclure
    my $conf = $self->sudoc->c->{$self->sudoc->iln}->{biblio};
    my $exclure = $conf->{exclure};
    if ( $exclure && ref($exclure) eq 'ARRAY' ) {
        $record->fields( [ grep { not $_->tag ~~ @$exclure } @{$record->fields} ] );
    }

}


# On remplit le $9 Koha des champs liés à des autorités
sub authoritize {
    my ($self, $record) = @_;

    # Ne rien faire si c'est demandé pour l'ILN
    return unless $self->sudoc->c->{ $self->sudoc->iln }->{biblio}->{authoritize};

    my $zconn = $self->sudoc->koha->zauth();
    for my $field ( $record->field('5..|6..|7..') ) {
        my @subf;
        for my $sf ( @{$field->subf} ) {
            my ($letter, $value) = @$sf;
            push @subf, [ $letter => $value ];
            if ( $letter eq '3' ) {
                my $rs = $zconn->search_pqf( "\@attr 1=PPN $value" );
                if ($rs->size() >= 1 ) {
                    my $auth = MARC::Moose::Record::new_from(
                        $rs->record(0)->raw(), 'Iso2709' );
                    push @subf, [ '9' => $auth->field('001')->value ]
                        if $auth;
                }
            }
        }
        $field->subf(\@subf);
    }
}


# Lien des notices biblio entre elles
sub linking {
    my ($self, $record) = @_;

    # Ne rien faire si c'est demandé pour l'ILN
    return unless $self->sudoc->c->{ $self->sudoc->iln }->{biblio}->{linking};

    my $zconn = $self->sudoc->koha->zbiblio();
    for my $field ( $record->field('4..|5..') ) {
        my @subf;
        for my $sf ( @{$field->subf} ) {
            my ($letter, $value) = @$sf;
            push @subf, [ $letter => $value ];
            if ( $letter eq '0' ) {
                my $rs = $zconn->search_pqf( "\@attr 1=PPN $value" );
                if ($rs->size() >= 1 ) {
                    my $biblio = MARC::Moose::Record::new_from(
                        $rs->record(0)->raw(), 'Iso2709' );
                    push @subf, [ '9' => $self->sudoc->koha->get_biblionumber($biblio) ],
                        if $biblio;
                }
            }
        }
        $field->subf(\@subf);
    }
}


# Création des exemplaires Koha en 995 en fonction des données locales
# SUDOC, au moyen de la structure de données $self->item.
sub itemize {
    my ($self, $record) = @_;

    my $myrcr = $self->sudoc->c->{$self->sudoc->iln}->{rcr};
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
    my $field = shift;
    my $key;
    for ( @{$field->subf} ) {
        my ($letter, $value) = @$_;
        next unless $letter =~ /[a-z]/;
        $key .= $value;
    }
    return $key;
}


# Fusion d'une notice entrante Sudoc avec une notice Koha
sub merge {
    my ($self, $record, $krecord) = @_;

    # On garde les champs "protégés" de la notice Koha
    # On évite les doublons
    my $conf = $self->sudoc->c->{$self->sudoc->iln}->{biblio};
    if ( my $proteger = $conf->{proteger} ) {
        my $pt = {}; # Hash de hash de tag - clé de dédoublonnage
        for my $tag ( @$proteger ) {
            $pt->{$tag} ||= {};
            for my $field ( $record->field($tag) ) {
                my $key = _key_dedup($field);
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


# On nettoie la notice entrante : suppression de champs, ajout auto de
# champs, etc.
sub clean {
    my ($self, $record) = @_;
}


# Le framework auquel affecter la notice biblio. Valeur par défaut prise
# dans sudoc.conf.  Peut-être surchargé pour attribuer un framework
# différent en fonction du type de doc.
sub framework {
    my ($self, $record) = @_;
    $self->sudoc->c->{$self->sudoc->iln}->{biblio}->{framework};
}

1;
