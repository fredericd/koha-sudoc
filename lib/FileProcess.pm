package FileProcess;
use Moose;

use diagnostics;
use AnyEvent;
use EchoWatcher;
use Locale::TextDomain 'fr.tamil.sudoc';

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

# Is it a blocking task (not a task)
has blocking => ( is => 'rw', isa => 'Bool', default => 0 );


sub run {
    my $self = shift;
    if ( $self->blocking) {
        $self->run_blocking();
    }
    else {
        $self->run_task();
    }
}


sub run_blocking {
    my $self = shift;
    while ( $self->process() ) {
        ;
    }
}


sub run_task {
    my $self = shift;

    if ( $self->verbose ) {
        my $watcher = EchoWatcher->new( delay => 1, action => $self );
        $self->watcher( $watcher );
        $watcher->start();
    }

    my $end_run = AnyEvent->condvar;
    my $idle = AnyEvent->idle(
        cb => sub {
            unless ( $self->process() ) {
                $self->watcher->stop() if $self->watcher;
                $end_run->send;
            }
        }
    );
    $end_run->recv;
}


sub process {
    my $self = shift;
    $self->count( $self->count + 1 );
}


sub start_message {
    print __"Start process...\n";
}


sub process_message {
    my $self = shift;
    print sprintf("  %#6d", $self->count), "\n";    
}

sub end_message {
    my $self = shift; 
    print __xn("One record processed",
               "Records processed: {count}",
               $self->count,
               count => $self->count), "\n";
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

=head1 COPYRIGHT AND LICENSE

Copyright 2009-2011 by Tamil, s.a.r.l.

L<http://www.tamil.fr>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.


