package FileProcess;
use Moose;

use diagnostics;
use POE;
use EchoWatcher;

with 'WatchableTask';


# Mode verbeux ?
has verbose => ( is => 'rw', isa => 'Int' );

# Le watcher qui renvoie un message au fur et à mesure du traitement
has watcher => ( 
    is => 'rw', 
    isa => 'EchoWatcher'
);

# Le compteur d'avancement, nombre d'enregistrements traités
has count => ( is => 'rw', isa => 'Int', default => 0 );

# TODELETE
# Will the session (POE task) run in an existing kernel?
# has run_already =>  ( is => 'rw', isa => 'Bool', default => 0 );

# Is it a blocking task (not a POE task)
has blocking => ( is => 'rw', isa => 'Bool', default => 0 );


sub run {
    my $self = shift;
    if ( $self->blocking) {
        $self->run_blocking();
    }
    else {
        $self->run_poe();
    }
}


sub run_blocking {
    my $self = shift;
    while ( $self->process() ) {
        ;
    }
}


sub run_poe {
    my $self = shift;
    if ( $self->verbose ) {
        my $watcher = EchoWatcher->new( delay => 2, action => $self );
        $self->watcher( $watcher );
        $watcher->start();
    }
    POE::Session->create(
        inline_states => {
            _start => sub { $_[KERNEL]->yield("next") },
            next   => sub {
                if ( $self->process() ) {
                    $_[KERNEL]->yield("next");
                }
                elsif ( $self->verbose() ) {
                    $self->watcher->stop();
                }
            },
        },
    );
    #POE::Kernel->run() unless $self->run_already;
    POE::Kernel->run();
}


sub process {
    my $self = shift;
    $self->count( $self->count + 1 );
    return;
}


sub start_message {
    print "Start process...\n";
}


sub process_message {
    my $self = shift;
    print sprintf("  %#6d", $self->count), "\n";    
}

sub end_message {
    my $self = shift; 
    print sprintf("  %#6d", $self->count), " records processed.\n";
}


no Moose;
__PACKAGE__->meta->make_immutable;

1;


=head1 NAME

FileProcess - Base class for file processing
    
=head1 DESCRIPTION

This class must be surclassed to implement a specific conversion logic. Some
generic are available here to be used in each implementation.
    
=head1 PARAMETERS

=head2 
=back

