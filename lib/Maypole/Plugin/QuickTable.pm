package Maypole::Plugin::QuickTable;

use warnings;
use strict;

use NEXT;

use HTML::QuickTable;

use Maypole::Config;
Maypole::Config->mk_accessors( qw( quicktable_defaults ) );

our $VERSION = 0.1;

=head1 NAME

Maypole::Plugin::QuickTable - HTML::QuickTable goodness for Maypole

=head1 SYNOPSIS

    use Maypole::Application qw( QuickTable );

=head1 METHODS

=over

=item setup 

=cut

sub setup
{
    my $r = shift;
    
    $r->NEXT::DISTINCT::setup( @_ );

    $r->config->{quicktable_defaults} ||= {};
    
    my $model = $r->config->model ||
        die "Please configure a model in $r before calling setup()";    
    
    no strict 'refs';
    *{"$model\::quicktable_defaults"} = sub {{}};
}

=item quick_table

Returns a L<HTML::QuickTable|HTML::QuickTable> object for formatting data. Set 
global defaults in the C<quicktable_defaults> slot of the config object. Set class-specific 
defaults by defining a C<quicktable_defaults> method in the class. Override these by passing 
args to the C<quick_table> call.

    print $request->quick_table( %args )->render( $data );

Pass a Maypole/CDBI object in the C<object> slot, and its data will be extracted 
and C<<$qt->render>> called for you:

    print $request->quick_table( %args, object => $object );
    
Foreign objects will be displayed as links to the view template. 

=cut

sub quick_table
{
    my $self = shift;
    
    my %args = ( %{ $self->config->quicktable_defaults }, 
                 %{ $self->model_class->quicktable_defaults }, 
                 @_,
                 );    
         
    my $object = delete $args{object};
      
    return HTML::QuickTable->new( %args ) unless $object;                    
    
    $args{labels} ||= 1;
    
    my $qt = HTML::QuickTable->new( %args );
    
    #die Data::Dumper::Dumper( [ $self->tabulate( $object, 1 ) ] );
    
    return $qt->render( [ $self->tabulate( $object, with_colnames => 1 ) ] );
}

=item tabulate( $object|$arrayref_of_objects, [ $with_colnames ] )

Extract data from a Maypole/CDBI object (or multiple objects), ready to pass to C<<quick_table->render>>. 
Data will start with a row of column names if C<$with_colnames> is true. 

=cut

# HTML::QuickTable seems to accept an array of arrayrefs, which is undocumented, but 
# simplifies this code - just pass whatever this returns, directly to render(). In fact, 
# HTML::QuickTable::render() puts the data into an arrayref if it's supplied as an array, 
# so it seems safe to rely on.
sub tabulate
{
    my ( $self, $objects, %args ) = @_;
    
    my @objects = ref( $objects ) eq 'ARRAY' ? @$objects : ( $objects );
    
    my @data = map { $self->_tabulate( $_, $args{callback} ) } @objects; 
    
    return @data unless $args{with_colnames};
    
    # If no rows (e.g. no search results), return 1 empty row to cause the table 
    # headers to be printed correctly.
    unless ( @data )
    {
        my @empty_row;
        push( @empty_row, '' ) for $self->model_class->display_columns;
        @data = ( [ @empty_row ] );
    }
    
    #my %names = $objects[0]->column_names;
    my %names = $self->model_class->column_names;
    
    unshift @data, [ map { $names{ $_ } } $self->model_class->display_columns ];

    return @data;
}

sub _tabulate
{
    my ( $self, $object, $callback ) = @_;
    
    my $str_col = $object->stringify_column;
    
    my @cols = $object->display_columns;
    
    my $data = [ map { $self->maybe_link_view( $_ ) } 
                 map { $_ eq $str_col ? $object : $object->get( $_ ) } 
                 @cols 
                 ];
                 
    push( @$data, $callback->( $object ) ) if $callback;
                 
    return $data;
}

=item maybe_link_view( $thing )

Returns C<$thing> unless it isa C<Maypole::Model::Base>, in which case 
a link to the view template for the object is returned.

=cut

sub maybe_link_view
{
    my ( $self, $thing ) = @_; 
    
    return $thing unless UNIVERSAL::isa( $thing, 'Maypole::Model::Base' );
    
    return $self->link( table      => $thing->table,
                        action     => 'view',
                        additional => $thing->id,
                        label      => $thing,
                        );
}

=item link( %args )

Returns a link, calling C<make_path> to generate the path. 

    %args = ( table      => $table,
              action     => $action,        # called 'command' in the original link template
              additional => $additional,    # optional - generally an object ID
              label      => $label,
              );

=cut

sub link
{
    my ( $self, %args ) = @_;
    
    do { die "no $_" unless $args{ $_ } } for qw( table
                                                  action
                                                  label
                                                  );    
    
    my $path = $self->make_path( %args );
    
    return sprintf '<a href="%s">%s</a>', $path, $args{label};
}

=item make_path( %args )

This is the counterpart to C<Maypole::parse_path>. It generates a path to use in links, 
form actions etc. To implement your own path scheme, just override this method and C<parse_path>.

    %args = ( table      => $table,
              action     => $action,        # called 'command' in the original link template
              additional => $additional,    # optional - generally an object ID
              );

=cut

sub make_path
{
    my ( $self, %args ) = @_;

    do { die "no $_" unless $args{ $_ } } for qw( table
                                                  action
                                                  );    

    my $base = $self->config->uri_base;
    $base = '' if $base eq '/';
        
    my $add = $args{additional} ? "/$args{additional}" : '';
    
    return sprintf '%s/%s/%s%s', $base, $args{table}, $args{action}, $add;
}

=back
 
=head1 AUTHOR

David Baird, C<< <cpan@riverside-cms.co.uk> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-maypole-plugin-quicktable@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Maypole-Plugin-QuickTable>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2005 David Baird, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Maypole::Plugin::QuickTable
