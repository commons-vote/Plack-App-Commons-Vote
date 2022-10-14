package Plack::App::Commons::Vote::Login;

use base qw(Plack::Component::Tags::HTML);
use strict;
use warnings;

use Tags::HTML::Commons::Vote::Login;

our $VERSION = 0.01;

sub _css {
	my $self = shift;

	$self->{'_html_login'}->process_css;

	return;
}

sub _prepare_app {
	my $self = shift;

	$self->{'_html_login'} = Tags::HTML::Commons::Vote::Login->new(
		'css' => $self->css,
		'tags' => $self->tags,
	);

	return;
}

sub _tags_middle {
	my $self = shift;

	$self->{'_html_login'}->process;

	return;
}

1;

__END__
