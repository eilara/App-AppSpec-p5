# ABSTRACT: App Module ad utilities for appspec tool
use strict;
use warnings;
use 5.010;
use utf8;
package App::AppSpec;
use Term::ANSIColor;

our $VERSION = '0.000'; # VERSION

use base 'App::Spec::Run';

sub read_spec {
    my ($self) = @_;
    my $parameters = $self->parameters;

    my $spec_file = $parameters->{spec_file};
    my $spec = App::Spec->read($spec_file);
    return $spec;
}

sub cmd_completion {
    my ($self) = @_;
    my $options = $self->options;
    my $parameters = $self->parameters;

    my $shell = $options->{zsh} ? "zsh" : $options->{bash} ? "bash" : '';
    die "Specify which shell" unless $shell;

    my $spec = $self->read_spec;
    my $completion = $spec->generate_completion(
        shell => $shell,
    );
    say $completion;
}

sub generate_pod {
    my ($self) = @_;
    my $parameters = $self->parameters;

    my $spec = $self->read_spec;
    my $pod = $spec->generate_pod(
    );
    say $pod;
}

sub colorize {
    my ($self) = @_;
    # TODO
    my $options = $self->options || {};
    my $color = $options->{color};
    my $env_color = $ENV{PERL5_APPSPEC_COLOR_OUTPUT} // 1;
    return unless -t STDOUT;
    return ($color || $env_color);
}

sub validate {
    my ($self) = @_;
    my $options = $self->options;
    my $parameters = $self->parameters;
    my $color = $self->colorize;

    my @errors;
    require App::AppSpec::Schema::Validator;
    my $validator = App::AppSpec::Schema::Validator->new;
    my $spec_file = $parameters->{spec_file};
    if (ref $spec_file eq 'SCALAR') {
        my $spec = YAML::XS::Load($$spec_file);
        @errors = $validator->validate_spec($spec);
    }
    else {
        @errors = $validator->validate_spec_file($spec_file);
    }
    binmode STDOUT, ":encoding(utf-8)";
    if (@errors) {
        print $validator->format_errors(\@errors);
        $color and print color 'red';
        say "Not valid!";
        $color and print color 'reset';
    }
    else {
        $color and print color 'bold green';
        say "Validated ✓";
        $color and print color 'reset';
    }
}

1;
