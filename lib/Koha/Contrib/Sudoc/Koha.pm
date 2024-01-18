package Koha::Contrib::Sudoc::Koha;
# ABSTRACT: Lien à Koha

use Moose;
use Modern::Perl;
use Carp;
use XML::Simple;
use DBI;
use ZOOM;
use MARC::Moose::Record;
use C4::Biblio qw/ GetMarcFromKohaField GetFrameworkCode /;;
use Search::Elasticsearch;
use YAML;
use MIME::Base64;
use Try::Tiny;


has conf_file => ( is => 'rw', isa => 'Str' );

has dbh => ( is => 'rw' );

has conf => ( is => 'rw' );

has _zconn => ( is => 'rw', isa => 'HashRef' );

has es => ( is => 'rw' );

has es_index => ( is=> 'rw' );

has sth_biblio => (is => 'rw' );


sub BUILD {
    my $self = shift;

    # Use KOHA_CONF environment variable by default
    $self->conf_file( $ENV{KOHA_CONF} )  unless $self->conf_file;

    $self->conf( XMLin( $self->conf_file,
        keyattr => ['id'], forcearray => ['listen', 'server', 'serverinfo'],
        suppressempty => '     ') );

    # Database Handler
    my $c = $self->conf->{config};
    $self->dbh( DBI->connect(
        "DBI:"     . $c->{db_scheme} .
        ":dbname=" . $c->{database} .
        ";host="   . $c->{hostname} .
        ";port="   . $c->{port},
        $c->{user}, $c->{pass} )
    ) or carp $DBI::errstr;
    if ( $c->{db_scheme} eq 'mysql' ) {
        # Force utf8 communication between MySQL and koha
        $self->dbh->{ mysql_enable_utf8 } = 1;
        $self->dbh->do( "set NAMES 'utf8'" );
        my $tz = $ENV{TZ};
        ($tz) and $self->dbh->do( qq(SET time_zone = "$tz") );
    }

    if ( C4::Context->preference('SearchEngine') eq 'Elasticsearch' ) {
        my $param = $c->{elasticsearch};
        my $es = Search::Elasticsearch->new( nodes => $param->{server} );
        $self->es( $es );
        $self->es_index( {
            biblios     => $param->{index_name} . '_biblios',
            authorities => $param->{index_name} . '_authorities',
        } );
    }

    # Zebra connections
    $self->_zconn( { biblio => undef, auth => undef } );

    # Récupération d'une notice biblio brute
    # Since version 17.05 marcxml biblio record is stored in biblio_metadata table.
    my $version = C4::Context->preference('Version');
    $self->sth_biblio( $self->dbh->prepare(
        $version =~ /^([0-9]{2})/ && $1 >= 17
        ? "SELECT metadata FROM biblio_metadata WHERE biblionumber=? "
        : "SELECT marcxml FROM biblioitems WHERE biblionumber=? "
    ) );
}


# Réinitialisation des deux connexions
sub zconn_reset {
    my $self = shift;

    return if $self->es; # Ne rien faire en mode ES

    my $zcs = $self->_zconn;
    for my $server ( keys %$zcs ) {
        my $zc = $zcs->{$server};
        $zc->destroy() if $zc;
        undef $zcs->{$server};
    }
}


sub zconn {
    my ($self, $server) = @_;

    my $zc = $self->_zconn->{$server};
    #return $zc  if $zc && $zc->errcode() == 0 && $zc->_check();
    return $zc  if $zc;

    #FIXME: à réactiver pour s'assurer que de nouvelles connexions ne sont
    # créées inutilement.
    #print "zconn: nouvelle connexion\n";
    my $c        = $self->conf;
    my $name     = $server eq 'biblio' ? 'biblioserver' : 'authorityserver';
    #my $syntax   = "Unimarc";
    my $host     = $c->{listen}->{$name}->{content};
    my $user     = $c->{serverinfo}->{$name}->{user};
    my $password = $c->{serverinfo}->{$name}->{password};
    my $auth     = $user && $password;

    # set options
    my $o = new ZOOM::Options();
    if ( $user && $password ) {
        $o->option( user     => $user );
        $o->option( password => $password );
    }
    #$o->option(async => 1) if $async;
    #$o->option(count => $piggyback) if $piggyback;
    $o->option( cqlfile => $c->{server}->{$name}->{cql2rpn} );
    $o->option( cclfile => $c->{serverinfo}->{$name}->{ccl2rpn} );
    #$o->option( preferredRecordSyntax => $syntax );
    $o->option( elementSetName => "F"); # F for 'full' as opposed to B for 'brief'
    $o->option( databaseName => $server eq 'biblio' ? "biblios" : "authorities");

    $zc = create ZOOM::Connection( $o );
    $zc->connect($host, 0);
    carp "something wrong with the connection: ". $zc->errmsg()
        if $zc->errcode;

    $self->_zconn->{$server} = $zc;
    return $zc;
}


sub zbiblio {
    shift->zconn( 'biblio' );
}


sub zauth {
    shift->zconn( 'auth' );
}


sub get_biblionumber {
    my ($self, $record) = @_;
    my ($tag, $letter) = GetMarcFromKohaField("biblio.biblionumber", '');
    $tag < 10
        ? $record->field($tag)->value
        : $record->field($tag)->subfield($letter);
}


sub get_biblionumber_framework {
    my ($self, $record) = @_;
    my $biblionumber = $self->get_biblionumber($record);
    ( $biblionumber,  GetFrameworkCode($biblionumber) );
}


=method get_biblio

Return a MARC::Moose::Record from its biblionumber,
and the record framework: (framework, record)

=cut
sub get_biblio {
    my ($self, $biblionumber) = @_;

    return (undef, undef) unless $biblionumber;
    $self->sth_biblio->execute($biblionumber);
    my ($xml) = $self->sth_biblio->fetchrow;
    return (undef, undef) unless $xml;

    my $record = MARC::Moose::Record::new_from($xml, 'MarcXml');
    return (undef, undef)  unless $record;

    (GetFrameworkCode($biblionumber), $record);
}


=method get_bibio_by_ppn

Lecture d'une notice biblio par son C<PPN>

=cut
sub get_biblio_by_ppn {
    my ($self, $ppn) = @_;

    my ($record, $biblionumber, $framework);;

    if ( my $es = $self->es ) { # Elasticsearch
        my $res = $es->search(
            index => $self->es_index->{biblios},
            body => {
                query => {  match => { ppn => $ppn }  }
            }
        );
        my $hits = $res->{hits}->{hits};
        if ( @$hits != 0 ) {
            my $source = $hits->[0]->{_source};
            $record = _record_from_es($source);
        }
    }
    else {
        try {
            my $rs = $self->zbiblio()->search_pqf( "\@attr 1=PPN $ppn" );
            if ( $rs->size() >= 1 ) {
                $record = $rs->record(0);
                $record = MARC::Moose::Record::new_from( $record->raw(), 'Iso2709' );
            }
        } catch {
            warn "ZOOM error: $_";
        };
    }

    if ( $record ) {
        ($biblionumber, $framework) = $self->get_biblionumber_framework($record);
        return ($biblionumber, $framework, $record);
    }
    return (undef, undef, undef) unless $record;
}


=method get_biblios_by_authid

Retrouve les notices associées à une autorité Koha identifiée par son
C<authid> Retourne un tableau de (biblionumner, framework, record)

=cut
sub get_biblios_by_authid {
    my ($self, $authid) = @_;

    my @records;
    if ( my $es = $self->es ) { # Elasticsearch
        my $res = $es->search(
            index => $self->es_index->{biblios},
            body => {
                query => {  match => { "Koha-Auth-Number" => $authid }  }
            }
        );
        my $hits = $res->{hits}->{hits};
        if ( @$hits != 0 ) {
            for my $source ( @$hits ) {
                $source = $source->{_source};
                my $record = _record_from_es($source);
                next unless $record;
                my ($biblionumber, $framework) = $self->get_biblionumber_framework($record);
                push @records, [$biblionumber, $framework, $record];
            }
        }
    }
    else {
        try {
            my $rs = $self->zbiblio()->search_pqf( "\@attr 1=Koha-Auth-Number $authid" );
            for ( my $i = 0; $i < $rs->size(); $i++ ) {
                my $record = $rs->record($i);
                $record = MARC::Moose::Record::new_from( $record->raw(), 'Iso2709' );
                next unless $record;
                my ($biblionumber, $framework) = $self->get_biblionumber_framework($record);
                push @records, [$biblionumber, $framework, $record];
            }
        } catch {
            warn "ZOOM error: $_";
        };
    }
    return @records;
}


sub _record_from_es {
    my $source = shift;

    my $record = MARC::Moose::Record->new();

    my $raw;
    if ( $raw = $source->{record} ) {
        # FIXME: obsolete now?
        my @fields;
        for my $field ( @$raw ) {
            my $tag = shift @$field;
            if ( $tag eq 'LDR' ) {
                $record->_leader($field->[3]);
            }
            elsif ( $tag le '009' ) {
                push @fields, MARC::Moose::Field::Control->new(
                    tag => $tag, value => $field->[3] );
            }
            else {
                my $f = MARC::Moose::Field::Std->new(
                    tag => $tag, ind1 => shift @$field, ind2 => shift @$field );
                my @subf;
                while (@$field) {
                    push @subf, [ shift @$field => shift @$field ];
                }
                $f->subf( \@subf);
                push @fields, $f;
            }
        }
        $record->fields(\@fields );
    }
    elsif ( $raw = $source->{marc_data_array} ) {
        my @fields;
        for my $field ( @{$raw->{fields}} ) {
            my $tag = [ keys %$field ]->[0];
            my $value = $field->{$tag};
            if ( $tag le '009' ) {
                push @fields, MARC::Moose::Field::Control->new(
                    tag => $tag, value => $value );
            }
            else {
                my $f = MARC::Moose::Field::Std->new(
                    tag => $tag, ind1 => $value->{ind1}, ind2 => $value->{ind2} );
                my @subf;
                for (@{$value->{subfields}}) {
                    my $letter = [ keys %$_ ]->[0];
                    my $val = $_->{$letter};
                    push @subf, [ $letter, $val ];
                }
                $f->subf(\@subf);
                push @fields, $f;
            }
        }
        $record->fields( \@fields );
        $record->_leader($raw->{leader});
    }
    elsif ($source->{marc_format} eq 'base64ISO2709') {
        $record = MARC::Moose::Record::new_from(decode_base64($source->{marc_data}),'Iso2709');
    }
    elsif ($source->{marc_format} eq 'MARCXML') {
        $record = MARC::Moose::Record::new_from($source->{marc_data},'Marcxml');
    }
    return $record;
}


=method get_auth_by_ppn

Lecture d'une autorité par son PPN. Renvoie un tableau contenant deux entrées:
l'authid de l'autorité et l'enregistrement de l'autorité trouvée.

=cut
sub get_auth_by_ppn {
    my ($self, $ppn) = @_;

    my ($authid, $record);

    if ( my $es = $self->es ) { # Elasticsearch
        my $res = $es->search(
            index => $self->es_index->{authorities},
            body => {
                query => {  match => { ppn => $ppn }  }
            }
        );
        my $hits = $res->{hits}->{hits};
        if ( @$hits != 0 ) {
            my $source = $hits->[0]->{_source};
            $record = _record_from_es($source);
        }
    }
    else { # Zebra
        try {
            my $rs = $self->zauth()->search_pqf( "\@attr 1=PPN $ppn" );
            if ( $rs->size() >= 1 ) {
                $record = $rs->record(0);
                $record = MARC::Moose::Record::new_from( $record->raw(), 'Iso2709' );
            } 
        };
    }

    $authid = $record->field('001')->value if $record;
    return ($authid, $record);
}


__PACKAGE__->meta->make_immutable;

1;

=head1 SYNOPSYS

  # Default Koha instance, defined in default koha-conf.xml file,
  # identified by KOHA_CONF environment variable
  my $k1 = Koha->new();

  my $k2 = Koha->new( conf_file => '/usr/koha/world-library/etc/koha-conf.xml' );

=head1 DESCRIPTION

