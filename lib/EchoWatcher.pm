package EchoWatcher;
use Moose;
use AnyEvent;

has delay   => ( is => 'rw', isa => 'Int', default => 1 );
has action  => ( is => 'rw', does => 'WatchableTask' );
has stopped => ( is => 'rw', isa => 'Int', default => 0 );

has wait => ( is => 'rw' );


sub start {
    my $self = shift;

    $self->action->start_message(),
    $self->wait( AnyEvent->timer(
        after => $self->delay,
        interval => $self->delay,
        cb    => sub {
            $self->action()->process_message(),
        },
    ) );
}


sub stop {
    my $self = shift;
    $self->action->end_message();
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

=head1 COPYRIGHT AND LICENSE

Copyright 2009 by Tamil, s.a.r.l.

L<http://www.tamil.fr>

This library is free software; you can redistribute it and/or modify
it under the same terms of either:

=over 4

=item * the GNU General Public Licence published by the Free Software
Foundation, either version 1, or (at your option) any later version or

=item * the Artistic Licence version 2.0.

=back
