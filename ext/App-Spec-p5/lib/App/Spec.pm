# ABSTRACT: Specification for commandline app
use strict;
use warnings;
package App::Spec;
use 5.010;

our $VERSION = '0.000'; # VERSION

use App::Spec::Command;
use App::Spec::Option;
use App::Spec::Parameter;
use List::Util qw/ any /;
use YAML::XS ();

use Moo;

has name => ( is => 'rw' );
has appspec => ( is => 'rw' );
has class => ( is => 'rw' );
has title => ( is => 'rw' );
has markup => ( is => 'rw', default => 'pod' );
has options => ( is => 'rw' );
has subcommands => ( is => 'rw', default => sub { +{} } );
has abstract => ( is => 'rw' );
has description => ( is => 'rw' );

my $DATA = do { local $/; <DATA> };
my $default_spec;

sub _read_default_spec {
    $default_spec ||= YAML::XS::Load($DATA);
    return $default_spec;
}

sub runner {
    my ($self) = @_;
    my $class = $self->class;
    my $run = $class->new({
        spec => $self
    });
    return $run;
}

sub read {
    my ($class, $file) = @_;
    unless (defined $file) {
        die "No filename given";
    }

    my $spec;
    if (ref $file eq 'GLOB') {
        my $data = do { local $/; <$file> };
        $spec = eval { YAML::XS::Load($data) };
    }
    elsif (not ref $file) {
        $spec = eval { YAML::XS::LoadFile($file) };
    }
    elsif (ref $file eq 'SCALAR') {
        my $data = $$file;
        $spec = eval { YAML::XS::Load($data) };
    }
    elsif (ref $file eq 'HASH') {
        $spec = $file;
    }

    unless ($spec) {
        die "Error reading '$file': $@";
    }

    my $default;
    {
        $default = $class->_read_default_spec;

        for my $opt (@{ $default->{options} }) {
            my $name = $opt->{name};
            unless (any { $_->{name} eq $name } @{ $spec->{options} }) {
                push @{ $spec->{options} }, $opt;
            }
        }

        for my $key (keys %{ $default->{subcommands} } ) {
            my $cmd = $default->{subcommands}->{ $key };
            $spec->{subcommands}->{ $key } ||= $cmd;
        }
    }

    # add subcommands to help command
    my $help_subcmds = $spec->{subcommands}->{help}->{subcommands} ||= {};
    $class->_add_subcommands($help_subcmds, $spec->{subcommands}, { subcommand_required => 0 });

    my $commands;
    for my $name (keys %{ $spec->{subcommands} || [] }) {
        my $cmd = $spec->{subcommands}->{ $name };
        $commands->{ $name } = App::Spec::Command->build({
            name => $name,
            %$cmd,
        });
    }

    my $self = $class->new({
        name => $spec->{name},
        appspec => $spec->{appspec},
        class => $spec->{class},
        title => $spec->{title},
        markup => $spec->{markup},
        options => [map {
            App::Spec::Option->build($_)
        } @{ $spec->{options} || [] }],
        subcommands => $commands,
        abstract => $spec->{abstract},
        description => $spec->{description},
    });
    return $self;
}

sub _add_subcommands {
    my ($self, $commands1, $commands2, $ref) = @_;
    for my $name (keys %{ $commands2 || {} }) {
        next if $name eq "help";
        my $cmd = $commands2->{ $name };
        $commands1->{ $name } = {
            name => $name,
            subcommands => {},
            %$ref,
        };
        my $subcmds = $cmd->{subcommands} || {};
        $self->_add_subcommands($commands1->{ $name }->{subcommands}, $subcmds, $ref);
    }
}

sub usage {
    my ($self, %args) = @_;
    my $cmds = $args{commands};
    my %highlights = %{ $args{highlights} || {} };
    my $color = $args{color};
    my $appname = $self->name;

    if (keys %highlights and $color) {
        require Term::ANSIColor;
    }

    my $abstract = $self->abstract // '';
    my $title = $self->title;
    my ($options, $parameters, $subcmds) = $self->gather_options_parameters($cmds);
    my $usage = <<"EOM";
$appname - $title
$abstract

EOM

    my $body = '';
    $usage .= "Usage: $appname @$cmds";
    if (keys %$subcmds) {
        my $maxlength = 0;
        my @table;
        my $usage_string = "<subcommands>";
        my $header = "Subcommands:";
        if ($color and $highlights{subcommands}) {
            $usage_string = Term::ANSIColor::colored([qw/ bold red /], $usage_string);
            $header = Term::ANSIColor::colored([qw/ bold red /], $header);
        }
        $usage .= " $usage_string";
        $body .= "$header\n";
        for my $name (sort keys %$subcmds) {
            my $cmd_spec = $subcmds->{ $name };
            my $summary = $cmd_spec->summary;
            push @table, [$name, $summary];
            if (length $name > $maxlength) {
                $maxlength = length $name;
            }
        }
        $body .= $self->_output_table(\@table, [$maxlength]);
    }

    if (@$parameters) {
        my $maxlength = 0;
        my @table;
        my @highlights;
        for my $param (@$parameters) {
            my $name = $param->name;
            my $highlight = $highlights{parameters}->{ $name };
            push @highlights, ($color and $highlight) ? 1 : 0;
            my $summary = $param->summary;
            $usage .= " " . $param->to_usage_header;
            my ($req, $multi) = (' ', '  ');
            if ($param->required) {
                $req = "*";
            }
            if ($param->multiple) {
                $multi = '[]';
            }
            push @table, [$name, $req, $multi, $summary];
            if (length $name > $maxlength) {
                $maxlength = length $name;
            }
        }
        $body .= "Parameters:\n";
        my @lines = $self->_output_table(\@table, [$maxlength]);
        my $lines = $self->_colorize_lines(\@lines, \@highlights);
        $body .= $lines;
    }

    if (@$options) {
        my @highlights;
        $usage .= " [options]";
        my $maxlength = 0;
        my @table;
        for my $opt (sort { $a->name cmp $b->name } @$options) {
            my $name = $opt->name;
            my $highlight = $highlights{options}->{ $name };
            push @highlights, ($color and $highlight) ? 1 : 0;
            my $aliases = $opt->aliases;
            my $summary = $opt->summary;
            my @names = map {
                length $_ > 1 ? "--$_" : "-$_"
            } ($name, @$aliases);
            my $string = "@names";
            if (length $string > $maxlength) {
                $maxlength = length $string;
            }
            my ($req, $multi) = (' ', '  ');
            if ($opt->required) {
                $req = "*";
            }
            if ($opt->multiple) {
                $multi = '[]';
            }
            push @table, [$string, $req, $multi, $summary];
        }
        $body .= "\nOptions:\n";
        my @lines = $self->_output_table(\@table, [$maxlength]);
        my $lines = $self->_colorize_lines(\@lines, \@highlights);
        $body .= $lines;
    }

    return "$usage\n\n$body";
}

sub generate_pod {
    my ($self) = @_;

    require App::Spec::Pod;
    my $generator = App::Spec::Pod->new(
        spec => $self,
    );
    my $pod = $generator->generate;
    return $pod;

}

sub _colorize_lines {
    my ($self, $lines, $highlights) = @_;
    my $output = '';
    for my $i (0 .. $#$lines) {
        my $line = $lines->[ $i ];
        if ($highlights->[ $i ]) {
            $line = Term::ANSIColor::colored([qw/ bold red /], $line);
        }
        $output .= $line;
    }
    return $output;
}

sub _output_table {
    my ($self, $table, $lengths) = @_;
    my @lines;
    my @lengths = map {
        defined $lengths->[$_] ? "%-$lengths->[$_]s" : "%s"
    } 0 .. @{ $table->[0] } - 1;
    for my $row (@$table) {
        no warnings 'uninitialized';
        push @lines, sprintf join('  ', @lengths) . "\n", @$row;
    }
    return wantarray ? @lines : join '', @lines;
}


sub gather_options_parameters {
    my ($self, $cmds) = @_;
    my @options;
    my @parameters;
    my $global_options = $self->options;
    my $commands = $self->subcommands;
    push @options, @$global_options;

    for my $cmd (@$cmds) {
        my $cmd_spec = $commands->{ $cmd };
        my $options = $cmd_spec->options || [];
        my $parameters = $cmd_spec->parameters || [];
        push @options, @$options;
        push @parameters, @$parameters;

        $commands = $cmd_spec->subcommands || {};

    }
    return \@options, \@parameters, $commands;
}

sub generate_completion {
    my ($self, %args) = @_;
    my $shell = delete $args{shell};
    require App::Spec::Completion::Zsh;
    require App::Spec::Completion::Bash;

    if ($shell eq "zsh") {
        my $completer = App::Spec::Completion::Zsh->new({
            spec => $self,
        });
        return $completer->generate_completion(%args);
    }
    elsif ($shell eq "bash") {
        my $completer = App::Spec::Completion::Bash->new({
            spec => $self,
        });
        return $completer->generate_completion(%args);
    }
}


sub make_getopt {
    my ($self, $options, $result, $specs) = @_;
    my @getopt;
    for my $opt (@$options) {
        my $name = $opt->name;
        my $spec = $name;
        unless ($opt->type eq 'flag') {
            $spec .= "=s";
        }
        $specs->{ $name } = $opt;
        if ($opt->multiple) {
            $result->{ $name } = [];
            $spec .= '@';
        }
        push @getopt, $spec, \$result->{ $name },
    }
    return @getopt;
}

1;

__DATA__
options:
    -   name: help
        description: Show command help
        type: flag
        aliases:
        - h
subcommands:
    help:
        op: cmd_help
        summary: Show command help
        subcommand_required: 0
        options:
        -   name: all
            type: flag
    _complete:
        summary: Generate self completion
        op: cmd_self_completion
        options:
            -   name: name
                description: name of the program
            -   name: zsh
                description: for zsh
                type: flag
            -   name: bash
                description: for bash
                type: flag
#            -   name: without-description
#                type: flag
#                default: false
#                description: generate without description
