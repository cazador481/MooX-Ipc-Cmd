package MooX::Ipc::Cmd::Exception;
use Moo;
extends 'Throwable::Error';
has 'stderr'      => (is => 'ro', predicate => 1,);
has 'cmd'         => (is => 'ro', required  => 1,);
has 'exit_status' => (is => 'ro', required  => 1);
has 'signal'      => (is => 'ro', predicate => 1,);

use overload
  q{""}    => 'as_string',
  fallback => 1;

  #message to print when dieing
has +message => (
    is =>'ro',
    lazy    => 1,
    default => sub {
        my $self = shift;
        my $str = join(" ", @{$self->cmd});
        if ($self->has_signal)
        {
            $str .= " failed with signal " . $self->signal;
        }
        else
        {
            $str .= " failed with exit status " . $self->exit_status;
            if ($self->has_stderr && defined $self->stderr)
            {
                $str = "\nSTDERR is :\n" . join("\n  ", @{$self->stderr});
            }
        }
        return $str;
    },
);

1;

