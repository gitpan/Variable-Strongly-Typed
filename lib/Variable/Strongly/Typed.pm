package Variable::Strongly::Typed;

use version; $VERSION = qv('1.0.0');

use warnings;
use strict;
use Carp;

# Tie any 'TYPE' attributes to me
use Attribute::Handlers;

# Our 3 friends for scalars & arrays & hashes
use Variable::Strongly::Typed::Scalar;
use Variable::Strongly::Typed::Array;
use Variable::Strongly::Typed::Hash;
use Variable::Strongly::Typed::Validators;

# Can't use Class::Std as it wants the 'ATTR' attribute
#   as does Attribute::Handlers...  Bummer
use Class::Std::Utils;
{
    # class variables
    my %actual_object_of;   # The actual object ref
    my %validator_sub_of;   # Validate subroutine
    my %type_of;            # Strong Type of this variable

    do {
        no warnings 'redefine';
        sub UNIVERSAL::TYPE : ATTR(SCALAR) {
            my ($package, $symbol, $referent, $attr, $data) = @_;
    
            tie $$referent, 'Variable::Strongly::Typed::Scalar', $data;
        }
    
        sub UNIVERSAL::TYPE : ATTR(ARRAY) {
            my ($package, $symbol, $referent, $attr, $data) = @_;
    
            tie @$referent, 'Variable::Strongly::Typed::Array', $data;
        }
    
        sub UNIVERSAL::TYPE : ATTR(HASH) {
            my ($package, $symbol, $referent, $attr, $data) = @_;
    
            tie %$referent, 'Variable::Strongly::Typed::Hash', $data;
        }
    };

    # Set up our class variables
    sub _init {
        my($self, $object, $type) = @_;
        my $ident = ident $self;

        $actual_object_of   {$ident} = $object;
        $validator_sub_of   {$ident} = $self->_make_validator_sub($type);
        $type_of            {$ident} = $type;

        return $self;
    }

    # Get actual object ref
    sub _get_object {
        my($self) = @_;
        return $actual_object_of{ident $self};
    }

    # Check if a value is okay...
    # IF this returns w/o croaking then all is okay...
    sub _check_values {
        my ($self, @values) = @_;

        my($valid_sub) = $validator_sub_of {ident $self};

        # if valid or failed sub says it's okay then ok
        #   otherwise undef
        # Note this works slightly differently then Tie::Constrained
        #   as we have no notion of an 'original' or 'default' value
        # 'failed' sub will croak if not valid...
        foreach my $val (@values) {

            # This'll croak if a value is not valid
            $valid_sub->($val) 
                || croak($self->_make_error_message($val));
        }

        # if we got this far all must be good
        return \@values;
    }

    sub _make_error_message {
        my($self, $val) = @_;

        # 'num', 'string', 'IO::File' or CODE ref if user defined
        my $valid_type = $type_of{ident $self};

        # Scalar, Array, or Hash
        my ($variable_type) = $self =~ /:: ([^:=]+) =/xms;
        $variable_type = lc $variable_type;

        # Type this variable is supposed to be
        my($strong_type) = $type_of{ident $self};

        # String-ify value
        if (ref $val) {
            $val = (ref $val) . ' reference';
        } else {
            $val = "'$val'";
        }

        my $msg;
        if (ref $valid_type eq 'CODE') {
            $msg = "Cannot assign $val to a user-validated"
                . " $variable_type variable!";
        } else {
            $msg = "Cannot assign $val to a" 
                . ($variable_type eq 'array' ? 'n' : '')
                . " $variable_type of type $strong_type!";
        }

        return $msg;
    }

    sub _make_validator_sub {
        my($self, $val) = @_;

        # User supplied??
        return $val if ($val && (ref($val) eq 'CODE'));

        my $condition;

        # Stuff like 'int', 'string', 'float' ... 'primitive' types
        $condition = $Variable::Strongly::Typed::Validators::conditions{$val};

        unless ($condition) {
            # It's either SCALAR, ARRAY, HASH the exact object type
            #   or an isa...  A reference type basically
            $condition = 
                'ref && ((ref eq ' . "'$val'" . ')'
                . ' || (ref ne "SCALAR" && ref ne "ARRAY"'
                .   ' && ref ne "HASH" && $_->isa(' . "'$val'" . ')))';
        }

        # Concoct validate sub
        my $sub = 
            eval 'sub { local $_ = shift; !$_ || (' . $condition . ') }';

        if ($@) {
            croak("Unable to create a Strongly Typed $val!!");
        }

        return $sub;
    }

    # Clean Up, Clean Up, Everybody's Doing Some, Clean Up
    #   -Walter (26 months)
    sub DESTROY {
        my($self) = @_;
        my $ident = ident $self;

        my $obj = $self->_get_object;
        undef  $obj;
        delete $actual_object_of{$ident};
        delete $validator_sub_of{$ident};
        delete $type_of         {$ident};
    }

}

1; # Magic true value required at end of module
__END__

=head1 NAME

Variable::Strongly::Typed - Let some variables be strongly typed


=head1 VERSION

This document describes Variable::Strongly::Typed version 1.0.0


=head1 SYNOPSIS

    use Variable::Strongly::Typed;

    my $int             :TYPE('int');       # must have an 'int' value
    my $float           :TYPE('float');     # must have a 'float' value
    my $string          :TYPE('string');    # must not be a reference
    my $file            :TYPE('IO::File');  # must be an IO::File
    my @array_of_ints   :TYPE('int');       # Each slot must contain an int
    my %hash_of_floats  :TYPE('float');     # Each value must be a float

    my @array_of_rgb :TYPE(\&red_green_blue); # my enumerated type

    # ... and later ...

    $int = 23;          # All is well
    $int = 'howdy!';    # This line will croak with a good error message

    $float = 3.23;              # All is well, nothing to see here
    $float = new XML::Parser;   # croak!

    $array_of_ints[23] = 44;    # Groovy
    $array_of_ints[12] = 'yah'; # croak!

    $hash_of_floats{pi} = 3.14159;      # no problem
    $hash_of_floats{e}  = new IO::File; # croak!

    # Return 1 if this val is RED, BLUE, or GREEN
    #   0 otherwise
    sub red_green_blue {
        local $_ = shift;

        /\A RED \z/xms || /\A BLUE \z/xms || /\A GREEN \z/xms;
    }

    $array_of_my_very_own_types[23] = 99;       # croak!
    $array_of_my_very_own_types[2] = 'BLUE';    # OK!

=head1 DESCRIPTION

    This modules allow you to strongly type your variables.  Also known
    as the 'no fun' module - it can greatly enhance you code's quality
    and robustness.

    By enforcing types on some (or all) of your variables you will eliminate
    a large class of careless (& not so careless) errors.

    This could also aid an editor or code-browsing tools to verify code 
    correctness without having to execute the script.

=head1 INTERFACE 

    Variable types are specified using the 'TYPE' attribute.  There are 
    currently 7 builtin types:

    'int'       => /\A \d+ \z/xms;
    'string'    => anything that's not a reference (!ref)
    'float'     => standard float regex
    'bool'      => same as 'int'
    'SCALAR'    => unblessed scalar ref
    'ARRAY'     => unblessed array ref
    'HASH'      => unblessed hash ref

    You can also specify a class name like 'XML::Parser' - note this is 
    NOT the same as 'HASH' which represents an unblessed HASH reference.

    Note when specifying 'XML::Parser' assigning 'XML::Parser' or any subclass of 
    'XML::Parser' will be valid - it does a $value->isa('XML::Parser')
    (or whatever the type you specified was) to test the value.

    If you try to assign an illegal value to your variable the assignment will
    croak with an informative error message.  Perhaps in the future there'll be
    an option to only carp...

    All builtin types allow 'undef' or any false value as a valid value.  Your
    own types (see section below) should probably do the same.

=head1 ROLLING YOUR OWN TYPES
    
    NOTE: You do NOT have to roll your own type to just specify a blessed
    object - see the section above!

    Specifying a CODE ref in your TYPE() attribute allows you to define your
    own types.  Your function will be call with 1 parameter - the value that's
    about to be assigned to any variable of that TYPE().

    Returning 1 (or any true value) will allow the assignment to happen.
    Return 0 (or any false value) will cause to assignment to croak.

    I'm sure you can dream up of all sorts of interesting types -
    enumerated types, all sorts of specific string types, bounded numbers,
    words only from a specific language are the sorts of things that pop
    into my mind.  Again I heartily expect you to surprise me with 
    the types you come up with.

    Note also you must allow for 'undef' as that is the initial value your
    variable will have!  Allowing for any false value may also be a good idea.

=head1 DIAGNOSTICS

    croak'ed error messages for built-in types look like:
        
      Cannot assign <value> to a [ scalar | hash | array ] of type <whatever>

    croak'ed error messages for user-supplied types look like:
        
      Cannot assign <value> to a user-validated  [ scalar | hash | array ] variable

=head1 CONFIGURATION AND ENVIRONMENT

Variable::Strongly::Typed requires no configuration files or environment variables.

=head1 DEPENDENCIES

    Attribute::Handlers handle the attribute stuff
    Class::Std::Utils handle the basic 'inside-out' module work
    Test::More for testing
    version for versioning

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-perl-strongly-typed@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

Mark Ethan Trostler  C<< <mark@zzo.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2005, Mark Ethan Trostler C<< <mark@zzo.com> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
