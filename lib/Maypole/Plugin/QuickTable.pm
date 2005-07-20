package Maypole::Plugin::QuickTable;

use warnings;
use strict;

use NEXT;

use HTML::QuickTable;

#use Maypole::Config;
#Maypole::Config->mk_accessors( qw( quicktable_defaults ) );

our $VERSION = 0.2;

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

    #$r->config->{quicktable_defaults} ||= {};
    
    my $model = $r->config->model ||
        die "Please configure a model in $r before calling setup()";    
        
    $model->mk_classdata( 'quicktable_defaults', {} );
    
    #no strict 'refs';
    #*{"$model\::quicktable_defaults"} = sub {{}};
}

=item quick_table

Returns a L<HTML::QuickTable|HTML::QuickTable> object for formatting data. 

    print $request->quick_table( %args )->render( $data );

The method gathers arguments from the C<quicktable_defaults> method on the model class. This 
is a L<Class::Data::Inheritable|Class::Data::Inheritable> method, so you can set global 
defaults on the main model class, and then override them in model subclasses. To preserve 
most settings and override others, say something like

    $sub_model->quicktable_defaults( { %{ $model->quicktable_defaults }, %hash_of_overrides } );

Arguments passed in the method call override those stored on the model.

Pass a Maypole/CDBI object in the C<object> slot, and its data will be extracted 
and C<< $qt->render >> called for you:

    print $request->quick_table( %args, object => $object );
    
Related objects will be displayed as links to their view template. 

=cut

sub quick_table
{
    my $self = shift;
    
    my %args = ( %{ $self->model_class->quicktable_defaults }, 
                 @_,
                 );    
         
    my $object = delete $args{object};
      
    # this allows the caller to pass in some prepackaged data and get a table back 
    return HTML::QuickTable->new( %args ) unless $object;                    
    
    $args{labels} ||= 1;
    
    my $qt = HTML::QuickTable->new( %args );
    
    #die Data::Dumper::Dumper( [ $self->tabulate( $object, 1 ) ] );
    
    return $qt->render( [ $self->tabulate( $object, with_colnames => 1 ) ] );
}

=item tabulate( $object|$arrayref_of_objects, %args )

Extract data from a Maypole/CDBI object (or multiple objects), ready to pass to C<< quick_table->render >>. 
Data will start with a row of column names if C<$args{with_colnames}> is true. 

A callback subref can be passed in C<$args{callback}>. It will be called in turn with each object as 
its argument. The result(s) of the call will be added to the row of data for that object. See 
the C<list> template in L<Maypole::FormBuilder|Maypole::FormBuilder>, which uses this technique 
to add C<edit> and C<delete> buttons to each row. 

Arguments:

    callback        coderef
    with_colnames   boolean
    fields          defaults to $object->display_columns

=cut

# HTML::QuickTable seems to accept an array of arrayrefs, which is undocumented, but 
# simplifies this code - just pass whatever this returns, directly to render(). In fact, 
# HTML::QuickTable::render() puts the data into an arrayref if it's supplied as an array, 
# so it seems safe to rely on.
sub tabulate
{
    my ( $self, $objects, %args ) = @_;
    
    my @objects = ref( $objects ) eq 'ARRAY' ? @$objects : ( $objects );
    
    # related() gives has_many fields - should probably also get might_have fields too
    # (the forms in editlistview will show might_have fields)
    my @fields = $args{fields} ? @{ $args{fields} } : 
                                 ( $self->model_class->display_columns, $self->model_class->related );
                                 
    my @data = map { $self->_tabulate( $_, \@fields, $args{callback} ) } @objects; 
    
    return @data unless $args{with_colnames};
    
    # If no rows (e.g. no search results), return 1 empty row to cause the table 
    # headers to be printed correctly.
    unless ( @data )
    {
        my @empty_row;
        push( @empty_row, '' ) for @fields;
        # my @empty_row = ( '' ) x @fields;
        @data = ( [ @empty_row ] ); 
    }
    
    #my %names = $objects[0]->column_names;
    my %names = $self->model_class->column_names;
    
    # not all fields are columns, hence the ucfirst fallback for has_many etc
    unshift @data, [ map { $names{ $_ } || ucfirst( $_ ) } @fields ];

    return @data;
}

# Return an arrayref of values for a single object, which will be passed to 
# QuickTable and rendered as a row in the table. The callback is optional, and 
# can be used to add extra entries to the row. Column values that inflate to CDBI 
# objects will be rendered as links to the view template. Column values that inflate 
# to non-CDBI objects will be returned as the object, which will presumably be evaluated 
# in string context at some point in QT render.
sub _tabulate
{
    my ( $self, $object, $cols, $callback ) = @_;
    
    my $str_col = $object->stringify_column;
    
    if ( $self->debug && ! $str_col )
    {
        warn sprintf "No stringify_column specified in %s - please define a 'Stringify' column " .
            "group with a single column", ref( $object );
    }
    
    # XXX: getting a 'Use of uninitialized value in string eq warning' - looks like 
    # $object->stringify_column can return undef?
    my $data = [ map { $self->maybe_link_view( $_ ) } 
    
                 # for the stringification column (e.g. 'name'), return the object, which 
                 # will be translated into a link to the 'view' template by 
                 # maybe_link_view. Otherwise, return the value, which will be rendered 
                 # verbatim, unless it is an object in a related class, in which case 
                 # it will be rendered as a link to the view template.
                 map { $_ eq $str_col ? $object : $self->maybe_many_link_views( $object->$_ ) } 
                 @$cols 
                 ];
                 
    push( @$data, $callback->( $object ) ) if $callback;
                 
    return $data;
}

=back

=head2 Template replacement methods

The following methods replace a couple of templates/macros in the main Maypole distribution. 
They are used here to construct links to related items. They are also used in the 
L<Maypole::FormBuilder|Maypole::FormBuilder> templates. 

Notice that if you build all paths using these methods in your templates, you can modify the 
path structure used in your site by overriding just two methods: C<Maypole::parse_path()> and 
C<Maypole::Plugin::QuickTable::make_path()>.

=over

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

=item maybe_many_link_views

Runs multiple items through C<maybe_link_view>, returning the results marked up as a list.

=cut

# if the accessor is for a has_many relationship, it might return multiple items, which 
# would each be passed individually to maybe_link_view(), and then each would go in its 
# own column. Instead, we want a list of items to put in a single cell.
sub maybe_many_link_views
{
    my ( $self, @values ) = @_;
    
    return @values unless @values > 1;
    
    my $html = "<ul>\n";
    $html .= "<li>" . $self->maybe_link_view( $_ ) . "</li>\n" for @values;
    $html .= "</ul>\n";

    return $html;
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

=head1 COPYRIGHT & LICENSE

Copyright 2005 David Baird, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Maypole::Plugin::QuickTable
