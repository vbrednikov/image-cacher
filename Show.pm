#!/usr/bin/perl -wT
use DL;
use Cache;

use strict;

package Show;

sub new {
    my $class=shift;
    my $self={};
    bless($self,$class);
    $self->init();
    return $self;
}

sub init {
    my $self=shift;

    $self->{cache}=Cache->new();
    $self->{cache}->path("tmp1");
    $self->{dl}=DL->new();
    $self->{dl}->cache($self->{cache});
    1;
}

sub _error {
    my $self=shift;
    my $str=shift;
    $self->{error_msg}=$str;
    return;
}

sub error {
    my $self=shift;
    return $self->{error_msg};
}

sub run {
    my $self=shift;
    my $uri;
    if(($uri)=$ENV{QUERY_STRING}=~/image_url=([^&]*)&?$/){
        $uri=~s/\+/ /g;
        $uri=~s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
    } else {
        return $self->_error("Unknown parameter");
    }
    unless($self->{cache}->get($uri)){ # if found, printed to stdout
        warn "Not found, dl $uri directly";
        my $dlfile=$self->{dl}->get($uri);   # print image or error to stdout and returns array to store it in cache
        if(!$dlfile){return $self->_error($self->{dl}->error()); }
        else { $self->{cache}->store(%{$dlfile}); }
    } else {
    }

    1;
}

1;
