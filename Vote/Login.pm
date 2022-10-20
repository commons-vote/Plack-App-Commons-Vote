package Plack::App::Commons::Vote::Login;

use base qw(Plack::Component::Tags::HTML);
use strict;
use warnings;

use Plack::Request;
use Plack::Util::Accessor qw(backend theme);
use Tags::HTML::Commons::Vote::Login;

our $VERSION = 0.01;

sub _css {
	my $self = shift;

	$self->{'_html_login'}->process_css($self->{'data'}->{'theme'});

	return;
}

sub _prepare_app {
	my $self = shift;

	$self->{'_html_login'} = Tags::HTML::Commons::Vote::Login->new(
		'css' => $self->css,
		'tags' => $self->tags,
	);

	if (! defined $self->theme) {
		$self->theme('default');
	}

	return;
}

sub _process_actions {
	my ($self, $env) = @_;

	my $req = Plack::Request->new($env);

	# Inicialization of data.
	$self->{'data'} = {};

	my $theme_shortcut = $req->parameters->{'theme'} || $self->theme;
	$self->{'data'}->{'theme'} = $self->backend->fetch_theme_by_shortcut($theme_shortcut);

	return;
}

sub _tags_middle {
	my $self = shift;

	$self->{'_html_login'}->process($self->{'data'}->{'theme'});

	return;
}

1;

__END__
